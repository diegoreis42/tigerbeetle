const std = @import("std");
const stdx = @import("../stdx.zig");

const assert = std.debug.assert;

const IO = @import("../io.zig").IO;
const FIFOType = @import("../fifo.zig").FIFOType;
const RingBufferType = stdx.RingBufferType;

const EventMetric = @import("event.zig").EventMetric;
const EventMetricAggregate = @import("event.zig").EventMetricAggregate;
const EventTiming = @import("event.zig").EventTiming;
const EventTimingAggregate = @import("event.zig").EventTimingAggregate;

const log = std.log.scoped(.statsd);

/// A resonable value to keep the total length of the packet under a single MTU, for a local
/// network.
///
/// https://github.com/statsd/statsd/blob/master/docs/metric_types.md#multi-metric-packets
const packet_size_max = 1400;

/// No single metric may be larger than this value. If it is, it'll be dropped with an error
/// message.
///
/// TODO: This is a static upper bound, it could be calculated at comptime!
const statsd_line_size_max = 350;
const messages_per_packet = @divFloor(packet_size_max, statsd_line_size_max);

/// This implementation emits on an open-loop: on the emit interval, it fires off up to
/// max_packet_count UDP packets, without waiting for completions.
///
/// The emit interval needs to be large enough that the kernel will have finished processing them
/// before emitting again. If not, an error will be logged.
const max_packet_count = stdx.div_ceil(EventMetric.stack_count + EventTiming.stack_count, messages_per_packet);

const BufferCompletion = struct {
    buffer: [packet_size_max]u8,
    completion: IO.Completion = undefined,
};

const BufferCompletionRing = RingBufferType(*BufferCompletion, .{ .array = max_packet_count });

pub const StatsD = struct {
    implementation: union(enum) {
        udp: struct {
            socket: std.posix.socket_t,
            io: *IO,
        },
        log,
    },

    buffer_completions: BufferCompletionRing,
    buffer_completions_buffer: []BufferCompletion,

    events_metric_emitted: []?EventMetricAggregate,

    /// Creates a statsd instance, which will send UDP packets via the IO instance provided.
    pub fn init(allocator: std.mem.Allocator, io: *IO, address: std.net.Address) !StatsD {
        const socket = try io.open_socket(
            address.any.family,
            std.posix.SOCK.DGRAM,
            std.posix.IPPROTO.UDP,
        );
        errdefer io.close_socket(socket);

        const buffer_completions_buffer = try allocator.alloc(BufferCompletion, max_packet_count);
        errdefer allocator.free(buffer_completions_buffer);

        var buffer_completions = BufferCompletionRing.init();
        for (buffer_completions_buffer) |*buffer_completion| {
            buffer_completions.push_assume_capacity(buffer_completion);
        }

        const events_metric_emitted = try allocator.alloc(?EventMetricAggregate, EventMetric.stack_count);
        errdefer allocator.free(events_metric_emitted);

        @memset(events_metric_emitted, null);

        // 'Connect' the UDP socket, so we can just send() to it normally.
        try std.posix.connect(socket, &address.any, address.getOsSockLen());

        log.info("sending statsd metrics to {}", .{address});

        return .{
            .implementation = .{
                .udp = .{
                    .socket = socket,
                    .io = io,
                },
            },
            .buffer_completions = buffer_completions,
            .buffer_completions_buffer = buffer_completions_buffer,
            .events_metric_emitted = events_metric_emitted,
        };
    }

    // Creates a statsd instance, which will log out the packets that would have been sent. Useful
    // so that all of the other code can run and be tested in the simulator.
    pub fn init_log(allocator: std.mem.Allocator) !StatsD {
        const buffer_completions_buffer = try allocator.alloc(BufferCompletion, max_packet_count);
        errdefer allocator.free(buffer_completions_buffer);

        var buffer_completions = BufferCompletionRing.init();
        for (buffer_completions_buffer) |*buffer_completion| {
            buffer_completions.push_assume_capacity(buffer_completion);
        }

        const events_metric_emitted = try allocator.alloc(?EventMetricAggregate, EventMetric.stack_count);
        errdefer allocator.free(events_metric_emitted);

        @memset(events_metric_emitted, null);

        return .{
            .implementation = .log,
            .buffer_completions = buffer_completions,
            .buffer_completions_buffer = buffer_completions_buffer,
            .events_metric_emitted = events_metric_emitted,
        };
    }

    pub fn deinit(self: *StatsD, allocator: std.mem.Allocator) void {
        if (self.implementation == .udp) self.implementation.udp.io.close_socket(self.implementation.udp.socket);
        allocator.free(self.events_metric_emitted);
        allocator.free(self.buffer_completions_buffer);
    }

    pub fn emit(self: *StatsD, events_metric: []?EventMetricAggregate, events_timing: []?EventTimingAggregate) void {
        // This should really not happen; it means we're emitting so many packets, on a short enough emit timeout, that
        // the kernel hasn't been able to process them all (UDP doesn't block or provide backpressure like a standard TCP socket).
        //
        // Keep it as a log, rather than assert, to avoid the common pitfall of metrics killing the whole system.
        if (self.buffer_completions.count != max_packet_count) {
            log.err("{} / {} packets still in flight; trying to continue", .{
                max_packet_count - self.buffer_completions.count,
                max_packet_count,
            });
        }

        var iterator = Iterator{
            .metrics = .{
                .events_metric = events_metric,
                .events_metric_emitted = self.events_metric_emitted,
            },
            .timings = .{ .events_timing = events_timing },
        };

        var buffer_completion = self.buffer_completions.pop() orelse {
            log.err("insufficient packets to emit any metrics", .{});
            return;
        };
        var buffer_completion_written: usize = 0;

        while (iterator.next()) |line| {
            if (line == .none) continue;

            const statsd_line = line.some;

            // Might need a new buffer, if this one is full.
            if (statsd_line.len > buffer_completion.buffer[buffer_completion_written..].len) {
                switch (self.implementation) {
                    .udp => |udp| {
                        udp.io.send(
                            *StatsD,
                            self,
                            StatsD.send_callback,
                            &buffer_completion.completion,
                            udp.socket,
                            buffer_completion.buffer[0..buffer_completion_written],
                        );
                    },
                    .log => {
                        log.debug("statsd packet: {s}", .{buffer_completion.buffer[0..buffer_completion_written]});
                        StatsD.send_callback(self, &buffer_completion.completion, buffer_completion_written);
                    },
                }

                buffer_completion = self.buffer_completions.pop() orelse {
                    log.err("insufficient packets to emit all metrics", .{});
                    return;
                };

                buffer_completion_written = 0;
                assert(buffer_completion.buffer[buffer_completion_written..].len > statsd_line.len);
            }

            stdx.copy_disjoint(.inexact, u8, buffer_completion.buffer[buffer_completion_written..], statsd_line);
            buffer_completion_written += statsd_line.len;
        }

        // Send the final packet, if needed, or return the BufferCompletion to the queue.
        if (buffer_completion_written > 0) {
            switch (self.implementation) {
                .udp => |udp| {
                    udp.io.send(
                        *StatsD,
                        self,
                        StatsD.send_callback,
                        &buffer_completion.completion,
                        udp.socket,
                        buffer_completion.buffer[0..buffer_completion_written],
                    );
                },
                .log => {
                    log.debug("statsd packet: {s}", .{buffer_completion.buffer[0..buffer_completion_written]});
                    StatsD.send_callback(self, &buffer_completion.completion, buffer_completion_written);
                },
            }
        } else {
            self.buffer_completions.push_assume_capacity(buffer_completion);
        }

        @memcpy(self.events_metric_emitted, events_metric);
    }

    /// The UDP packets containing the metrics are sent in a fire-and-forget manner.
    fn send_callback(
        self: *StatsD,
        completion: *IO.Completion,
        result: IO.SendError!usize,
    ) void {
        // TODO: This could be quite verbose: do we want to throttle it?
        _ = result catch |e| {
            log.warn("error sending metric: {}", .{e});
        };
        const buffer_completion: *BufferCompletion = @fieldParentPtr("completion", completion);
        self.buffer_completions.push_assume_capacity(buffer_completion);
    }
};

const Iterator = struct {
    const Output = ?union(enum) { none, some: []const u8 };
    const MetricsIterator = struct {
        const TagFormatter = EventStatsdTagFormatter(EventMetric);

        events_metric: []?EventMetricAggregate,
        events_metric_emitted: []?EventMetricAggregate,

        buffer: [statsd_line_size_max]u8 = undefined,
        index: usize = 0,

        pub fn next(self: *MetricsIterator) Output {
            assert(self.events_metric.len == self.events_metric_emitted.len);

            defer self.index += 1;
            if (self.index == self.events_metric.len) return null;
            const event_metric = self.events_metric[self.index] orelse return .none;

            // Skip metrics that have the same value as when they were last emitted.
            const event_metric_previous = self.events_metric_emitted[self.index];
            if (event_metric_previous != null and
                event_metric.value == event_metric_previous.?.value)
            {
                return .none;
            }

            const value = event_metric.value;
            const field_name = switch (event_metric.event) {
                inline else => |_, tag| @tagName(tag),
            };
            const event_metric_tag_formatter = TagFormatter{
                .event = event_metric.event,
            };

            return .{
                .some = std.fmt.bufPrint(
                    &self.buffer,
                    // TODO: Support counters.
                    "tigerbeetle.{[name]s}:{[value]}|g|#{[tags]s}\n",
                    .{ .name = field_name, .value = value, .tags = event_metric_tag_formatter },
                ) catch {
                    log.err("metric line for {s} exceeeds buffer size", .{field_name});
                    return .none;
                },
            };
        }
    };

    const TimingsIterator = struct {
        const Aggregation = enum { min, avg, max, sum, count, sentinel };
        const TagFormatter = EventStatsdTagFormatter(EventTiming);

        events_timing: []?EventTimingAggregate,

        buffer: [statsd_line_size_max]u8 = undefined,
        index: usize = 0,
        index_aggregation: Aggregation = .min,

        pub fn next(self: *TimingsIterator) Output {
            defer {
                self.index_aggregation = @enumFromInt(@intFromEnum(self.index_aggregation) + 1);

                if (self.index_aggregation == .sentinel) {
                    self.index += 1;
                    self.index_aggregation = .min;
                }
            }

            if (self.index == self.events_timing.len) return null;

            const event_timing = self.events_timing[self.index] orelse return .none;

            const values = event_timing.values;
            const field_name = switch (event_timing.event) {
                inline else => |_, tag| @tagName(tag),
            };
            const tag_formatter = TagFormatter{
                .event = event_timing.event,
            };

            // It's common to emit metrics in seconds, rather than us or ms. Internally things are
            // kept as us, and conversion to floating point is done here as late as possible.
            // (It is possible to do this without floating point, but not worth it!)
            const value = switch (self.index_aggregation) {
                .min => @as(f64, @floatFromInt(values.duration_min_us)) / std.time.us_per_s,
                // TODO: Might make more sense to do the div in floating point?
                .avg => @as(f64, @floatFromInt(@divFloor(values.duration_sum_us, values.count))) /
                    std.time.us_per_s,
                .max => @as(f64, @floatFromInt(values.duration_max_us)) / std.time.us_per_s,
                .sum => @as(f64, @floatFromInt(values.duration_sum_us)) / std.time.us_per_s,
                .count => @as(f64, @floatFromInt(values.count)), // Collateral damage.
                .sentinel => unreachable,
            };

            // Emit count and sum as counter metrics, and the rest as gagues. This ensures that the
            // upstream statsd server will aggregate count and sum by summing them together, while
            // using last-value-wins for min/avg/max, which is not strictly accurate but the best
            // that can be done.
            // TODO: Or is it?
            const statsd_type = if (self.index_aggregation == .count or self.index_aggregation == .sum) "c" else "g";
            return .{
                .some = std.fmt.bufPrint(
                    &self.buffer,
                    "tigerbeetle.{[name]s}_seconds.{[aggregation]s}:{[value]d}|{[statsd_type]s}|#{[tags]s}\n",
                    .{
                        .name = field_name,
                        .aggregation = @tagName(self.index_aggregation),
                        .value = value,
                        .statsd_type = statsd_type,
                        .tags = tag_formatter,
                    },
                ) catch {
                    log.err("metric line for {s} exceeeds buffer size", .{field_name});
                    return .none;
                },
            };
        }
    };

    metrics: MetricsIterator,
    timings: TimingsIterator,

    metrics_exhausted: bool = false,
    timings_exhausted: bool = false,

    pub fn next(self: *Iterator) Output {
        if (!self.metrics_exhausted) {
            const value = self.metrics.next();
            if (value == null) self.metrics_exhausted = true else return value;
        }
        if (!self.timings_exhausted) {
            const value = self.timings.next();
            if (value == null) self.timings_exhausted = true else return value;
        }
        return null;
    }
};

/// Format EventMetric and EventTiming's payload (ie, the tags) in a dogstatsd compatible way:
/// Tags are comma separated, with a `:` between key:value pairs.
fn EventStatsdTagFormatter(EventType: type) type {
    return struct {
        event: EventType,

        pub fn format(
            formatter: *const @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;

            switch (formatter.event) {
                inline else => |data| {
                    if (@TypeOf(data) == void) {
                        return;
                    }

                    const fields = std.meta.fields(@TypeOf(data));
                    inline for (fields, 0..) |data_field, i| {
                        assert(data_field.type == bool or
                            @typeInfo(data_field.type) == .Int or
                            @typeInfo(data_field.type) == .Enum or
                            @typeInfo(data_field.type) == .Union);

                        const data_field_value = @field(data, data_field.name);
                        try writer.writeAll(data_field.name);
                        try writer.writeByte(':');

                        if (@typeInfo(data_field.type) == .Enum or
                            @typeInfo(data_field.type) == .Union)
                        {
                            try writer.print("{s}", .{@tagName(data_field_value)});
                        } else {
                            try writer.print("{}", .{data_field_value});
                        }

                        if (i != fields.len - 1) {
                            try writer.writeByte(',');
                        }
                    }
                },
            }
        }
    };
}
