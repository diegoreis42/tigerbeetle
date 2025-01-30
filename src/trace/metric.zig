const std = @import("std");
const assert = std.debug.assert;

const stdx = @import("../stdx.zig");
const IO = @import("../io.zig").IO;
const StatsD = @import("statsd.zig").StatsD;
const Event = @import("event.zig").Event;
const EventTiming = @import("event.zig").EventTiming;
const EventMetric = @import("event.zig").EventMetric;
const EventTimingAggregate = @import("event.zig").EventTimingAggregate;
const EventMetricAggregate = @import("event.zig").EventMetricAggregate;

pub const Metrics = struct {
    events_timing: []?EventTimingAggregate,
    events_metric: []?EventMetricAggregate,

    statsd: ?StatsD,

    pub fn init(allocator: std.mem.Allocator, io_maybe: ?*IO) !Metrics {
        const events_timing = try allocator.alloc(?EventTimingAggregate, EventTiming.stack_count);
        errdefer allocator.free(events_timing);

        @memset(events_timing, null);

        const events_metric = try allocator.alloc(?EventMetricAggregate, EventMetric.stack_count);
        errdefer allocator.free(events_metric);

        @memset(events_metric, null);

        const statsd = if (io_maybe) |io|
            try StatsD.init(allocator, io, try std.net.Address.resolveIp("127.0.0.1", 8125))
        else
            null;
        errdefer if (statsd) |*s| s.deinit(allocator);

        return .{
            .events_timing = events_timing,
            .events_metric = events_metric,
            .statsd = statsd,
        };
    }

    pub fn deinit(self: *Metrics, allocator: std.mem.Allocator) void {
        allocator.free(self.events_metric);
        allocator.free(self.events_timing);
    }

    /// Gauges work on a last-set wins. Multiple calls to .gauge() followed by an emit will result
    /// in the last value being submitted.
    pub fn gauge(self: *Metrics, event_metric: EventMetric, value: u64) void {
        const timing_stack = event_metric.stack();
        self.events_metric[timing_stack] = .{
            .event = event_metric,
            .value = value,
        };
    }

    // Timing works by storing the min, max, sum and count of each value provided. The avg is
    // calculated from sum and count at emit time.
    //
    // When these are emitted upstream (via statsd, currently), upstream must apply different
    // aggregiations:
    // * min/max/avg are considered gauges for aggregation: last value wins.
    // * sum/count are considered counters for aggregation: they are added to the existing values.
    //
    // This matches the default behavior of the `g` and `c` statsd types respectively.
    pub fn timing(self: *Metrics, event_timing: EventTiming, duration_us: u64) void {
        const timing_stack = event_timing.stack();

        if (self.events_timing[timing_stack] == null) {
            self.events_timing[timing_stack] = .{
                .event = event_timing,
                .values = .{
                    .duration_min_us = duration_us,
                    .duration_max_us = duration_us,
                    .duration_sum_us = duration_us,
                    .count = 1,
                },
            };
        } else {
            const timing_existing = self.events_timing[timing_stack].?.values;
            // Certain high cardinality data (eg, op) _can_ differ.
            // TODO: Maybe assert and gate on constants.verify

            self.events_timing[timing_stack].?.values = .{
                .duration_min_us = @min(timing_existing.duration_min_us, duration_us),
                .duration_max_us = @max(timing_existing.duration_max_us, duration_us),
                .duration_sum_us = timing_existing.duration_sum_us +| duration_us,
                .count = timing_existing.count +| 1,
            };
        }
    }

    pub fn emit(self: *Metrics) !void {
        if (self.statsd) |*s| {
            try s.emit(self.events_metric, self.events_timing);
        }

        // For statsd, the right thing is to reset metrics between emitting. For something like
        // Prometheus, this would have to be removed.
        self.reset_all();
    }

    pub fn reset_all(self: *Metrics) void {
        @memset(self.events_metric, null);
        @memset(self.events_timing, null);
    }
};

test "timing overflow" {
    var metrics = try Metrics.init(std.testing.allocator, null);
    defer metrics.deinit(std.testing.allocator);

    const event: EventTiming = .replica_aof_write;
    const value = std.math.maxInt(u64) - 1;
    metrics.timing(event, value);
    metrics.timing(event, value);

    const aggregate = metrics.events_timing[event.stack()].?;

    assert(aggregate.values.count == 2);
    assert(aggregate.values.duration_min_us == value);
    assert(aggregate.values.duration_max_us == value);
    assert(aggregate.values.duration_sum_us == std.math.maxInt(u64));
}
