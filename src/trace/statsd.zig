const std = @import("std");
const stdx = @import("../stdx.zig");

const IO = @import("../io.zig").IO;
const FIFOType = @import("../fifo.zig").FIFOType;

const max_packet_size = 1400;
const max_packet_count = 256;

const RingBufferType = @import("../ring_buffer.zig").RingBufferType;
const EventTiming = @import("event.zig").EventTiming;
const EventMetric = @import("event.zig").EventMetric;
const EventTimingAggregate = @import("event.zig").EventTimingAggregate;
const EventMetricAggregate = @import("event.zig").EventMetricAggregate;

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

    /// Creates a statsd instance, which will send UDP packets via the IO instance provided.
    pub fn init(allocator: std.mem.Allocator, io: *IO, address: std.net.Address) !StatsD {
        const socket = try io.open_socket(
            address.any.family,
            std.posix.SOCK.DGRAM,
            std.posix.IPPROTO.UDP,
        );
        errdefer io.close_socket(socket);

        var buffer_completions = BufferCompletionRing.init();
        const buffer_completions_buffer = try allocator.alloc(BufferCompletion, max_packet_count);
        for (buffer_completions_buffer) |*buffer_completion| {
            buffer_completions.push_assume_capacity(buffer_completion);
        }

        // 'Connect' the UDP socket, so we can just send() to it normally.
        // FIXME: In io.zig, connrefused etc should be handled better!
        try std.posix.connect(socket, &address.any, address.getOsSockLen());

        return .{
            .socket = socket,
            .io = io,
            .buffer_completions = buffer_completions,
            .buffer_completions_buffer = buffer_completions_buffer,
        };
    }

    // FIXME: io cancellation?
    pub fn deinit(self: *StatsD, allocator: std.mem.Allocator) void {
        self.io.close_socket(self.socket);
        allocator.free(self.buffer_completions_buffer);
        self.buffer_completions.deinit(allocator);
    }

    // FIXME: flip this around; make an iterator over emit_timing and emit_metrics, and have emit
    // call both of those.
    pub fn emit_and_reset(self: *StatsD, events_metric: []?EventMetricAggregate, events_timing: []?EventTimingAggregate) !void {
        // At some point, would it be more efficient to use a hashmap here...?
        var buffer_completion = self.buffer_completions.pop() orelse return error.NoSpaceLeft;
        var index: usize = 0;

        // FIXME: Comptime lenght limits, must be under a packet...
        var single_buffer: [max_packet_size]u8 = undefined;
        std.debug.assert(single_buffer.len <= self.buffer_completions_buffer[0].buffer.len);

        var iterator_metrics = IteratorMetric{
            .events = events_metric,
            .buffer = &single_buffer,
        };

        var iterator_timings = IteratorTiming{
            .events = events_timing,
            .buffer = &single_buffer,
        };

        for (.{ iterator_metrics.next, iterator_timings.next }) |next| {
            // FIXME: Safety counter
            while (true) {
                const line = next();
                if (line == .none) continue;
                if (line == .exhausted) break;

                const statsd_line = line.some;

                // Might need a new buffer, if this one is full.
                if (statsd_line.len > buffer_completion.buffer[index..].len) {
                    self.io.send(
                        *StatsD,
                        self,
                        StatsD.send_callback,
                        &buffer_completion.completion,
                        self.socket,
                        buffer_completion.buffer[0..index],
                    );

                    buffer_completion = self.buffer_completions.pop() orelse return error.NoSpaceLeft;

                    index = 0;
                    std.debug.assert(buffer_completion.buffer[index..].len > statsd_line.len);
                }

                stdx.copy_disjoint(.inexact, u8, buffer_completion.buffer[index..], statsd_line);
                index += statsd_line.len;
            }
        }

        // Send the final packet, if needed, or return the BufferCompletion to the queue.
        if (index > 0) {
            self.io.send(
                *StatsD,
                self,
                StatsD.send_callback,
                &buffer_completion.completion,
                self.socket,
                buffer_completion.buffer[0..index],
            );
        } else {
            self.buffer_completions.push_assume_capacity(buffer_completion);
        }
    }

    fn send_callback(
        self: *StatsD,
        completion: *IO.Completion,
        result: IO.SendError!usize,
    ) void {
        _ = result catch |e| {
            std.log.warn("error sending metric: {}", .{e});
        };
        const buffer_completion: *BufferCompletion = @fieldParentPtr("completion", completion);
        self.buffer_completions.push_assume_capacity(buffer_completion);
    }
};

const IteratorOutput = union(enum) { none, some: []const u8, exhausted };

const IteratorMetric = struct {
    const TagFormatter = EventStatsdTagFormatter(EventMetric);

    buffer: []const u8,
    events_metric: []?EventMetricAggregate,

    index: usize = 0,

    pub fn next(self: *@This()) IteratorOutput {
        defer self.index += 1;
        if (self.index > self.events_metric.len) return .exhausted;
        const event_metric = self.events_metric[self.index] orelse return .none;

        const value = event_metric.value;
        const field_name = switch (event_metric.event) {
            inline else => |_, tag| @tagName(tag),
        };
        const event_metric_tag_formatter = TagFormatter{
            .event = event_metric.event,
        };

        return try std.fmt.bufPrint(
            self.buffer,
            "tigerbeetle.{s}:{}|g|#{s}\n",
            .{ field_name, value, event_metric_tag_formatter },
        );
    }
};

const IteratorTiming = struct {
    const Aggregation = enum { min, avg, max, sum, count };
    const TagFormatter = EventStatsdTagFormatter(EventTiming);

    buffer: []const u8,
    events_timing: []?EventTimingAggregate,

    index: usize = 0,
    index_aggregiation: Aggregation = .min,

    pub fn next(self: *@This()) IteratorOutput {
        defer self.index += 1;
        if (self.index > self.events_metric.len) return .exhausted;
        const event_timing = self.events_timing[self.index] orelse return .none;

        const values = event_timing.values;
        const field_name = switch (event_timing.event) {
            inline else => |_, tag| @tagName(tag),
        };
        const tag_formatter = TagFormatter{
            .event = event_timing.event,
        };

        // FIXME: Report as seconds and follow best practices from prom wiki.
        const value = switch (self.index_aggregiation) {
            .min => values.duration_min_us,
            .avg => @divFloor(values.duration_sum_us, values.count),
            .max => values.duration_max_us,
            .sum => values.duration_sum_us,
            .count => values.count,
            else => unreachable,
        };

        // Emit count and sum as counter metrics, and the rest as gagues. This ensure that ... FIXME
        const statsd_type = if (self.index_aggregiation == .count or self.index_aggregiation == .sum) "c" else "g";
        return try std.fmt.bufPrint(
            self.buffer,
            "tigerbeetle.{s}_seconds.{s}:{}|{s}|#{s}\n",
            .{ field_name, @tagName(self.index_aggregiation), value, statsd_type, tag_formatter },
        );
    }
};

/// Format EventTiming and EventMetric's payload (ie, the tags) in a dogstatsd compatible way:
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
