//! Flag state — represents a flag on the road network.
//!
//! Flags are nodes in the transport network where serfs pick up
//! and drop off resources.

const std = @import("std");
const serialize = @import("serialize");
const enums = @import("enums.zig");
const types = @import("types.zig");

const Resource = enums.Resource;
const MapPos = types.MapPos;
const GameObjectIndex = types.GameObjectIndex;

/// Maximum queue length at a flag (incoming/outgoing).
pub const FlagQueueCapacity = 4;

/// The state of a single flag instance.
pub const FlagState = struct {
    /// Game state tracking.
    base: serialize.State = .{},

    // --- Core fields ---
    pos: MapPos = MapPos.invalid,
    player: u8 = 0xFF,

    // --- Road connections ---
    /// Index of the next flag on each of 6 directions (0xFFFFFFFF = none).
    next: [6]GameObjectIndex = @splat(GameObjectIndex.invalid),
    /// Length (in map positions) of the road segment in each direction.
    length: [6]u8 = @splat(0),

    // --- Transport queues ---
    /// Incoming resource queue (resources waiting at the flag).
    incoming_queue: [FlagQueueCapacity]u8 = @splat(0),
    /// Outgoing resource queue (resources waiting for a transporter).
    outgoing_queue: [FlagQueueCapacity]u8 = @splat(0),
    /// Number of items in each queue.
    incoming_count: u8 = 0,
    outgoing_count: u8 = 0,

    // --- Serf assignment ---
    /// Index of the transporter assigned to this flag (if any).
    transporter_index: GameObjectIndex = GameObjectIndex.invalid,

    // --- Building reference ---
    /// Index of the building attached to this flag (if any).
    building_index: GameObjectIndex = GameObjectIndex.invalid,

    pub fn markDirty(self: *FlagState, field_index: u6) void {
        self.base.markDirty(field_index);
    }

    pub fn isDirty(self: FlagState, field_index: u6) bool {
        return self.base.isDirty(field_index);
    }
};

/// Array of flag states.
pub const FlagStates = struct {
    flags: std.ArrayList(FlagState),

    pub fn init(_: std.mem.Allocator) FlagStates {
        return .{ .flags = .empty };
    }

    pub fn deinit(self: *FlagStates, allocator: std.mem.Allocator) void {
        self.flags.deinit(allocator);
    }

    pub fn add(self: *FlagStates, allocator: std.mem.Allocator, state: FlagState) !GameObjectIndex {
        const index = self.flags.items.len;
        try self.flags.append(allocator, state);
        return GameObjectIndex{ .index = @intCast(index) };
    }

    pub fn get(self: *FlagStates, index: GameObjectIndex) *FlagState {
        return &self.flags.items[index.index];
    }

    pub fn len(self: FlagStates) usize {
        return self.flags.items.len;
    }
};
