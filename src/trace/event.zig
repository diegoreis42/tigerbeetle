const std = @import("std");
const assert = std.debug.assert;

const constants = @import("../constants.zig");

const CommitStage = @import("../vsr/replica.zig").CommitStage;

// FIXME: Doesn't this exist somewhere already?
// FIXME: Naming doesn't align with what we use, eg accounts.id vs Account.id
// FIXME: Exhaustive tests for Event
// FIXME: Make EventTiming and EventMetric only use enums and get rid of cardinality stuff
const TreeEnum = tree_enum: {
    const tree_ids = @import("../state_machine.zig").tree_ids;
    var tree_fields: []const std.builtin.Type.EnumField = &[_]std.builtin.Type.EnumField{};

    for (std.meta.declarations(tree_ids)) |groove_field| {
        const r = @field(tree_ids, groove_field.name);
        for (std.meta.fieldNames(@TypeOf(r))) |field_name| {
            tree_fields = tree_fields ++ &[_]std.builtin.Type.EnumField{.{
                .name = groove_field.name ++ "." ++ field_name,
                .value = @field(r, field_name),
            }};
        }
    }

    break :tree_enum @Type(.{ .Enum = .{
        .tag_type = u64,
        .fields = tree_fields,
        .decls = &.{},
        .is_exhaustive = true,
    } });
};

pub const Event = union(enum) {
    replica_commit: struct { stage: CommitStage, op: ?usize = null },
    replica_aof_write: struct { op: usize },
    replica_sync_table: struct { index: usize },

    compact_beat: struct { tree: TreeEnum, level_b: u8 },
    compact_beat_merge: struct { tree: TreeEnum, level_b: u8 },
    compact_manifest,
    compact_mutable: struct { tree: TreeEnum },
    compact_mutable_suffix: struct { tree: TreeEnum },

    lookup: struct { tree: TreeEnum },
    lookup_worker: struct { index: u8, tree: TreeEnum },

    scan_tree: struct { index: u8, tree: TreeEnum },
    scan_tree_level: struct { index: u8, tree: TreeEnum, level: u8 },

    grid_read: struct { iop: usize },
    grid_write: struct { iop: usize },

    metrics_emit: void,

    pub const EventTag = std.meta.Tag(Event);

    /// Normally, Zig would stringify a union(enum) like this as `{"compact_beat": {"tree": ...}}`.
    /// Remove this extra layer of indirection.
    pub fn jsonStringify(event: Event, jw: anytype) !void {
        switch (event) {
            inline else => |payload, tag| {
                if (@TypeOf(payload) == void) {
                    try jw.write("");
                } else if (tag == .replica_commit) {
                    try jw.write(@tagName(payload.stage));
                } else {
                    try jw.write(payload);
                }
            },
        }
    }

    /// Convert the base event to an EventTiming or EventMetric.
    pub fn as(event: *const Event, EventType: type) EventType {
        return switch (event.*) {
            inline else => |source_payload, tag| {
                const TargetPayload = std.meta.fieldInfo(EventType, tag).type;
                const target_payload_info = @typeInfo(TargetPayload);
                assert(target_payload_info == .Void or target_payload_info == .Struct);

                var target_payload: TargetPayload = undefined;
                if (target_payload_info == .Struct) {
                    inline for (comptime std.meta.fieldNames(TargetPayload)) |field| {
                        @field(target_payload, field) = @field(source_payload, field);
                    }
                }

                return @unionInit(EventType, @tagName(tag), target_payload);
            },
        };
    }
};

/// There's a difference between tracing and aggregate timing. When doing tracing, the code needs
/// to worry about the static allocation required for _concurrent_ traces. That is, there might be
/// multiple `scan_tree`s, with different `index`es happening at once.
///
/// When timing, this is flipped on its head: the timing code doesn't need space for concurrency
/// because it is called once, when an event has finished, and internally aggregates. The
/// aggregiation is needed because there can be an unknown number of calls between flush intervals,
/// compared to tracing which is emitted as it happens.
///
/// Rather, it needs space for the cardinality of the tags you'd like to emit. In the case of
/// `scan_tree`s, this would be the tree it's scanning over, rather than the index of the scan. Eg:
///
/// timing.scan_tree.transfers_id_avg=1234us vs timing.scan_tree.index_0_avg=1234us
pub const EventTracing = union(Event.EventTag) {
    replica_commit,
    replica_aof_write,
    replica_sync_table: struct { index: usize },

    compact_beat,
    compact_beat_merge,
    compact_manifest,
    compact_mutable,
    compact_mutable_suffix,

    lookup,
    lookup_worker: struct { index: u8 },

    scan_tree: struct { index: u8 },
    scan_tree_level: struct { index: u8, level: u8 },

    grid_read: struct { iop: usize },
    grid_write: struct { iop: usize },

    metrics_emit: void,

    pub const stack_limits = std.enums.EnumArray(Event.EventTag, u32).init(.{
        .replica_commit = 1,
        .replica_aof_write = 1,
        .replica_sync_table = constants.grid_missing_tables_max,
        .compact_beat = 1,
        .compact_beat_merge = 1,
        .compact_manifest = 1,
        .compact_mutable = 1,
        .compact_mutable_suffix = 1,
        .lookup = 1,
        .lookup_worker = constants.grid_iops_read_max,
        .scan_tree = constants.lsm_scans_max,
        .scan_tree_level = constants.lsm_scans_max * @as(u32, constants.lsm_levels),
        .grid_read = constants.grid_iops_read_max,
        .grid_write = constants.grid_iops_write_max,
        .metrics_emit = 1,
    });

    pub const stack_bases = array: {
        var array = std.enums.EnumArray(Event.EventTag, u32).initDefault(0, .{});
        var next: u32 = 0;
        for (std.enums.values(Event.EventTag)) |event_type| {
            array.set(event_type, next);
            next += stack_limits.get(event_type);
        }
        break :array array;
    };

    pub const stack_count = count: {
        var count: u32 = 0;
        for (std.enums.values(Event.EventTag)) |event_type| {
            count += stack_limits.get(event_type);
        }
        break :count count;
    };

    // Stack is a u32 since it must be losslessly encoded as a JSON integer.
    pub fn stack(event: *const EventTracing) u32 {
        switch (event.*) {
            inline .replica_sync_table,
            .lookup_worker,
            => |data| {
                assert(data.index < stack_limits.get(event.*));
                const stack_base = stack_bases.get(event.*);
                return stack_base + @as(u32, @intCast(data.index));
            },
            .scan_tree => |data| {
                assert(data.index < constants.lsm_scans_max);
                // This event has "nested" sub-events, so its offset is calculated
                // with padding to accommodate `scan_tree_level` events in between.
                const stack_base = stack_bases.get(event.*);
                const scan_tree_offset = (constants.lsm_levels + 1) * data.index;
                return stack_base + scan_tree_offset;
            },
            .scan_tree_level => |data| {
                assert(data.index < constants.lsm_scans_max);
                assert(data.level < constants.lsm_levels);
                // This is a "nested" event, so its offset is calculated
                // relative to the parent `scan_tree`'s offset.
                const stack_base = stack_bases.get(.scan_tree);
                const scan_tree_offset = (constants.lsm_levels + 1) * data.index;
                const scan_tree_level_offset = data.level + 1;
                return stack_base + scan_tree_offset + scan_tree_level_offset;
            },
            inline .grid_read, .grid_write => |data| {
                assert(data.iop < stack_limits.get(event.*));
                const stack_base = stack_bases.get(event.*);
                return stack_base + @as(u32, @intCast(data.iop));
            },
            inline else => |data, event_tag| {
                comptime assert(@TypeOf(data) == void);
                comptime assert(stack_limits.get(event_tag) == 1);
                return comptime stack_bases.get(event_tag);
            },
        }
    }

    pub fn format(
        event: *const EventTracing,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        switch (event.*) {
            inline else => |data| {
                try writer.print("{}", .{event_equals_format(data)});
            },
        }
    }
};

pub const EventTiming = union(Event.EventTag) {
    replica_commit: struct { stage: CommitStage },
    replica_aof_write,
    replica_sync_table,

    compact_beat: struct { tree: TreeEnum, level_b: u8 },
    compact_beat_merge: struct { tree: TreeEnum, level_b: u8 },
    compact_manifest,
    compact_mutable: struct { tree: TreeEnum },
    compact_mutable_suffix: struct { tree: TreeEnum },

    lookup: struct { tree: TreeEnum },
    lookup_worker: struct { tree: TreeEnum },

    scan_tree: struct { tree: TreeEnum },
    scan_tree_level: struct { tree: TreeEnum, level: u8 },

    grid_read,
    grid_write,

    metrics_emit: void,

    // FIXME: Exhaustively test these with a test. Easy enough!
    pub const stack_limits = std.enums.EnumArray(Event.EventTag, u32).init(.{
        .replica_commit = std.meta.fields(CommitStage).len,
        .replica_aof_write = 1,
        .replica_sync_table = 1,
        .compact_beat = (std.meta.fields(TreeEnum).len + 1) * @as(u32, constants.lsm_levels),
        .compact_beat_merge = (std.meta.fields(TreeEnum).len + 1) * @as(u32, constants.lsm_levels),
        .compact_manifest = 1,
        .compact_mutable = (std.meta.fields(TreeEnum).len + 1),
        .compact_mutable_suffix = (std.meta.fields(TreeEnum).len + 1),
        .lookup = (std.meta.fields(TreeEnum).len + 1),
        .lookup_worker = (std.meta.fields(TreeEnum).len + 1),
        .scan_tree = (std.meta.fields(TreeEnum).len + 1),
        .scan_tree_level = (std.meta.fields(TreeEnum).len + 1) * @as(u32, constants.lsm_levels),
        .grid_read = 1,
        .grid_write = 1,
        .metrics_emit = 1,
    });

    pub const stack_bases = array: {
        var array = std.enums.EnumArray(Event.EventTag, u32).initDefault(0, .{});
        var next: u32 = 0;
        for (std.enums.values(Event.EventTag)) |event_type| {
            array.set(event_type, next);
            next += stack_limits.get(event_type);
        }
        break :array array;
    };

    pub const stack_count = count: {
        var count: u32 = 0;
        for (std.enums.values(Event.EventTag)) |event_type| {
            count += stack_limits.get(event_type);
        }
        break :count count;
    };

    // Unlike with EventTracing, which neatly organizes related events underneath one another, the
    // order here does not matter.
    pub fn stack(event: *const EventTiming) u32 {
        switch (event.*) {
            // Single payload: CommitStage
            inline .replica_commit => |data| {
                // FIXME:Can we assert this at comptime?
                // FIXME: The enum logic is actually broken. We kinda want to remap the enum from 0 -> limit.... At the moment
                // hack around it with +1 for trees etc.
                const stage = @intFromEnum(data.stage);
                assert(stage < stack_limits.get(event.*));

                return stack_bases.get(event.*) + @as(u32, @intCast(stage));
            },
            // Single payload: TreeEnum
            inline .compact_mutable, .compact_mutable_suffix, .lookup, .lookup_worker, .scan_tree => |data| {
                const tree_id = @intFromEnum(data.tree);
                assert(tree_id < stack_limits.get(event.*));

                return stack_bases.get(event.*) + @as(u32, @intCast(tree_id));
            },
            // Double payload: TreeEnum + level_b
            inline .compact_beat, .compact_beat_merge => |data| {
                const tree_id = @intFromEnum(data.tree);
                const level_b = data.level_b;
                const offset = tree_id * constants.lsm_levels + level_b;
                assert(offset < stack_limits.get(event.*));

                return stack_bases.get(event.*) + @as(u32, @intCast(offset));
            },
            // Double payload: TreeEnum + level
            inline .scan_tree_level => |data| {
                const tree_id = @intFromEnum(data.tree);
                const level = data.level;
                const offset = tree_id * constants.lsm_levels + level;
                assert(offset < stack_limits.get(event.*));

                return stack_bases.get(event.*) + @as(u32, @intCast(offset));
            },
            inline else => |data, event_tag| {
                comptime assert(@TypeOf(data) == void);
                comptime assert(stack_limits.get(event_tag) == 1);

                return comptime stack_bases.get(event_tag);
            },
        }
    }

    pub fn format(
        event: *const EventTiming,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        switch (event.*) {
            inline else => |data| {
                try writer.print("{}", .{event_equals_format(data)});
            },
        }
    }
};

pub const EventMetric = union(enum) {
    const EventTag = std.meta.Tag(EventMetric);

    table_count_visible: struct { tree: TreeEnum, level: u8 },
    table_count_visible_max: struct { tree: TreeEnum, level: u8 },

    // FIXME: Exhaustively test these with a test. Easy enough!
    pub const stack_limits = std.enums.EnumArray(EventTag, u32).init(.{
        .table_count_visible = (std.meta.fields(TreeEnum).len + 1) * @as(u32, constants.lsm_levels),
        .table_count_visible_max = (std.meta.fields(TreeEnum).len + 1) * @as(u32, constants.lsm_levels),
    });

    pub const stack_bases = array: {
        var array = std.enums.EnumArray(EventTag, u32).initDefault(0, .{});
        var next: u32 = 0;
        for (std.enums.values(EventTag)) |event_type| {
            array.set(event_type, next);
            next += stack_limits.get(event_type);
        }
        break :array array;
    };

    pub const stack_count = count: {
        var count: u32 = 0;
        for (std.enums.values(EventTag)) |event_type| {
            count += stack_limits.get(event_type);
        }
        break :count count;
    };

    pub fn stack(event: *const EventMetric) u32 {
        switch (event.*) {
            // Double payload: TreeEnum + level
            inline .table_count_visible, .table_count_visible_max => |data| {
                const tree_id = @intFromEnum(data.tree);
                const level = data.level;
                const offset = tree_id * constants.lsm_levels + level;
                assert(offset < stack_limits.get(event.*));

                return stack_bases.get(event.*) + @as(u32, @intCast(offset));
            },
            // inline else => |data, event_tag| {
            //     comptime assert(@TypeOf(data) == void);
            //     comptime assert(stack_limits.get(event_tag) == 1);

            //     return comptime stack_bases.get(event_tag);
            // },
        }
    }
};

/// Format EventTiming and EventMetric's payload (ie, the tags) with a space separated k=v format.
fn EventEqualsFormatter(comptime Data: type) type {
    assert(@typeInfo(Data) == .Struct or @typeInfo(Data) == .Void);

    if (@typeInfo(Data) == .Void) {
        return struct {
            data: Data,
            pub fn format(
                _: *const @This(),
                comptime _: []const u8,
                _: std.fmt.FormatOptions,
                _: anytype,
            ) !void {}
        };
    }

    return struct {
        data: Data,

        pub fn format(
            formatter: *const @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;

            const fields = std.meta.fields(Data);
            inline for (fields, 0..) |data_field, i| {
                assert(data_field.type == bool or
                    @typeInfo(data_field.type) == .Int or
                    @typeInfo(data_field.type) == .Enum or
                    @typeInfo(data_field.type) == .Union);

                const data_field_value = @field(formatter.data, data_field.name);
                try writer.writeAll(data_field.name);
                try writer.writeByte('=');

                if (@typeInfo(data_field.type) == .Enum or
                    @typeInfo(data_field.type) == .Union)
                {
                    try writer.print("{s}", .{@tagName(data_field_value)});
                } else {
                    try writer.print("{}", .{data_field_value});
                }

                if (i != fields.len - 1) {
                    try writer.writeByte(' ');
                }
            }
        }
    };
}

pub fn event_equals_format(
    data: anytype,
) EventEqualsFormatter(@TypeOf(data)) {
    return EventEqualsFormatter(@TypeOf(data)){ .data = data };
}

pub const EventTimingAggregate = struct {
    event: EventTiming,
    values: struct {
        duration_min_us: u64,
        duration_max_us: u64,
        duration_sum_us: u64,

        count: u64,
    },
};

pub const EventMetricAggregate = struct {
    event: EventMetric,
    value: u64,
};
