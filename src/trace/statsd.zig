const std = @import("std");
const stdx = @import("../stdx.zig");

const IO = @import("../io.zig").IO;
const FIFOType = @import("../fifo.zig").FIFOType;
const RingBufferType = @import("../ring_buffer.zig").RingBufferType;

const EventMetric = @import("event.zig").EventMetric;
const EventMetricAggregate = @import("event.zig").EventMetricAggregate;
const EventTiming = @import("event.zig").EventTiming;
const EventTimingAggregate = @import("event.zig").EventTimingAggregate;

const log = std.log.scoped(.statsd);

/// A resonable value to keep the total length of the packet under a single MTU, for a local
/// network.
///
/// https://github.com/statsd/statsd/blob/master/docs/metric_types.md#multi-metric-packets
/// FIXME: Assert no metric is larger than this.
const max_packet_size = 1400;

/// This implementation emits on an open-loop: on the emit interval, it fires off up to
/// max_packet_count UDP packets, without waiting for completions.
///
/// The emit interval needs to be large enough that the kernel will have finished processing them
/// before emitting again. If not, a warning will be printed.
// TODO: For now, this assumes 100 bytes max per event! This can actually be computed exactly....
/// The maximum number of packets that can be sent in one flush. The implementation does not do
/// backpressure, so if all packets haven't finished sending between flush cycles (incredibly
/// unlikely, if not impossible due to how sending UDP packets works in the kernel), then packets
/// will be dropped.
///
/// However, this value needs to be high enough to account for the maximum number of metrics that
/// will be sent _within_ a single flush, given how many metrics can fit into a single packet
///
/// TODO: This is an extreme upper bound, it can be reduced! It assumes a single packet can only
/// take one metric / timing.
const max_packet_count = EventMetric.stack_count + EventTiming.stack_count;

const BufferCompletion = struct {
    buffer: [max_packet_size]u8,
    completion: IO.Completion = undefined,
};

const BufferCompletionRing = RingBufferType(*BufferCompletion, .{ .array = max_packet_count });

pub const StatsD = struct {
    socket: std.posix.socket_t,
    io: *IO,

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
            .socket = socket,
            .io = io,
            .buffer_completions = buffer_completions,
            .buffer_completions_buffer = buffer_completions_buffer,
            .events_metric_emitted = events_metric_emitted,
        };
    }

    // FIXME: io cancellation?
    pub fn deinit(self: *StatsD, allocator: std.mem.Allocator) void {
        self.io.close_socket(self.socket);
        allocator.free(self.events_metric_emitted);
        allocator.free(self.buffer_completions_buffer);
    }

    pub fn emit(self: *StatsD, events_metric: []?EventMetricAggregate, events_timing: []?EventTimingAggregate) !void {
        if (self.buffer_completions.count != max_packet_count) {
            log.warn("{} packets still in flight", .{
                max_packet_count - self.buffer_completions.count,
            });
        }

        // At some point, would it be more efficient to use a hashmap here...?
        var buffer_completion = self.buffer_completions.pop() orelse return error.NoSpaceLeft;
        var buffer_written: usize = 0;

        // FIXME: Comptime lenght limits, must be under a packet...
        // It's less error prone to write into a standalone buffer and copy it into the packet, then
        // to deal with having partially written into a packet and needing to erase that and rewind
        // the iterator to try again.
        // var buffer_single: [max_packet_size]u8 = undefined;
        // std.debug.assert(buffer_single.len <= self.buffer_completions_buffer[0].buffer.len);

        var iterator = Iterator{
            .metrics = .{
                .events_metric = events_metric,
                .events_metric_emitted = self.events_metric_emitted,
            },
            .timings = .{ .events_timing = events_timing },
        };

        while (iterator.next()) |line| {
            if (line == .none) continue;

            const statsd_line = line.some;

            // Might need a new buffer, if this one is full.
            if (statsd_line.len > buffer_completion.buffer[buffer_written..].len) {
                self.io.send(
                    *StatsD,
                    self,
                    StatsD.send_callback,
                    &buffer_completion.completion,
                    self.socket,
                    buffer_completion.buffer[0..buffer_written],
                );

                buffer_completion = self.buffer_completions.pop() orelse return error.NoSpaceLeft;

                buffer_written = 0;
                std.debug.assert(buffer_completion.buffer[buffer_written..].len > statsd_line.len);
            }

            stdx.copy_disjoint(.inexact, u8, buffer_completion.buffer[buffer_written..], statsd_line);
            buffer_written += statsd_line.len;
        }

        // Send the final packet, if needed, or return the BufferCompletion to the queue.
        if (buffer_written > 0) {
            self.io.send(
                *StatsD,
                self,
                StatsD.send_callback,
                &buffer_completion.completion,
                self.socket,
                buffer_completion.buffer[0..buffer_written],
            );
        } else {
            self.buffer_completions.push_assume_capacity(buffer_completion);
        }

        @memcpy(self.events_metric_emitted, events_metric);
    }

    /// The UDP packets containing the metrics are sent in a fire-and-forget manner. Generally,
    /// FIXME: explain why this is ok and reduces complexity
    fn send_callback(
        self: *StatsD,
        completion: *IO.Completion,
        result: IO.SendError!usize,
    ) void {
        _ = result catch |e| {
            log.warn("error sending metric: {}", .{e});
        };
        const buffer_completion: *BufferCompletion = @fieldParentPtr("completion", completion);
        self.buffer_completions.push_assume_capacity(buffer_completion);
    }
};

// FIXME: for metrics, keep track of emission and re-emit same values on a timer
const Iterator = struct {
    const Output = ?union(enum) { none, some: []const u8 };

    metrics: struct {
        const TagFormatter = EventStatsdTagFormatter(EventMetric);

        events_metric: []?EventMetricAggregate,
        events_metric_emitted: []?EventMetricAggregate,

        buffer: [max_packet_size]u8 = undefined,
        index: usize = 0,

        pub fn next(self: *@This()) Output {
            defer self.index += 1;
            if (self.index == self.events_metric.len) return null;
            const event_metric = self.events_metric[self.index] orelse return .none;

            // Skip metrics that have the same value as when they were last emitted.
            // FIXME: Add an override counter that will still send them, every minute or so.
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
                .some = stdx.array_print(
                    max_packet_size,
                    &self.buffer,
                    // TODO: Support counters.
                    "tigerbeetle.{[name]s}:{[value]}|g|#{[tags]s}\n",
                    .{ .name = field_name, .value = value, .tags = event_metric_tag_formatter },
                ),
            };
        }
    },

    timings: struct {
        const Aggregation = enum { min, avg, max, sum, count, sentinel };
        const TagFormatter = EventStatsdTagFormatter(EventTiming);

        events_timing: []?EventTimingAggregate,

        buffer: [max_packet_size]u8 = undefined,
        index: usize = 0,
        index_aggregation: Aggregation = .min,

        pub fn next(self: *@This()) Output {
            defer {
                // FIXME: Better way?
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

            // FIXME: Follow best practices from prom wiki.
            // It's common to emit metrics in seconds, rather than us or ms. Internally things are
            // kept as us, and conversion to floating point is done here as late as possible.
            // It is possible to do this without floating point, but ...
            const value = switch (self.index_aggregation) {
                .min => @as(f64, @floatFromInt(values.duration_min_us)) / std.time.us_per_s,
                // Might make more sense to do the div in floating point?
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
            // that can be done. (FIXME: OR IS IT?)
            const statsd_type = if (self.index_aggregation == .count or self.index_aggregation == .sum) "c" else "g";
            return .{
                .some = stdx.array_print(
                    max_packet_size,
                    &self.buffer,
                    "tigerbeetle.{[name]s}_seconds.{[aggregation]s}:{[value]d}|{[statsd_type]s}|#{[tags]s}\n",
                    .{
                        .name = field_name,
                        .aggregation = @tagName(self.index_aggregation),
                        .value = value,
                        .statsd_type = statsd_type,
                        .tags = tag_formatter,
                    },
                ),
            };
        }
    },

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
                        std.debug.assert(data_field.type == bool or
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
