//! Serf state — represents one serf on the map.
//!
//! Port of the C# SerfState class with dirty-tracking.
//! Serfs are the worker units that perform all game actions.

const std = @import("std");
const serialize = @import("serialize");
const enums = @import("enums.zig");
const types = @import("types.zig");

const SerfType = enums.SerfType;
const SerfStateEnum = enums.SerfState;
const Direction = enums.Direction;
const Resource = enums.Resource;
const MapPos = types.MapPos;
const GameObjectIndex = types.GameObjectIndex;

/// The state of a single serf instance.
pub const SerfStateData = struct {
    /// Game state tracking.
    base: serialize.State = .{},

    // --- Core fields ---
    pos: MapPos = MapPos.invalid,
    serf_type: SerfType = .none,
    player: u8 = 0xFF,

    // --- State machine ---
    state: SerfStateEnum = .idle_in_stock,
    /// Tick counter for the current state.
    tick: u16 = 0,
    /// Sub-state index (for multi-phase states).
    sub_state: u8 = 0,

    // --- Movement ---
    dest: MapPos = MapPos.zero,
    /// Road index being followed.
    road_index: u8 = 0,
    /// Progress along current road segment (0-255).
    road_progress: u8 = 0,

    // --- Resource transport ---
    /// Resource type being carried.
    carrying: Resource = .fish,
    /// Resource count.
    carrying_count: u8 = 0,

    // --- Building interactions ---
    /// Building this serf is assigned to.
    building_index: GameObjectIndex = GameObjectIndex.invalid,
    /// Flag this serf is assigned to (for transporters).
    flag_index: GameObjectIndex = GameObjectIndex.invalid,

    // --- Target references ---
    /// Target building (for delivery).
    target_building: GameObjectIndex = GameObjectIndex.invalid,
    /// Target flag (for transport).
    target_flag: GameObjectIndex = GameObjectIndex.invalid,
    /// Target serf (for interactions).
    target_serf: GameObjectIndex = GameObjectIndex.invalid,

    // --- Pathfinding ---
    /// Remaining path segments.
    path: [16]u8 = @splat(0),
    path_length: u8 = 0,
    path_index: u8 = 0,

    // --- Combat (for knights) ---
    hp: u8 = 0,
    attack: u8 = 0,
    defense: u8 = 0,

    // --- Animation ---
    animation_frame: u8 = 0,
    animation_tick: u16 = 0,

    pub fn markDirty(self: *SerfStateData, field_index: u6) void {
        self.base.markDirty(field_index);
    }

    pub fn isDirty(self: SerfStateData, field_index: u6) bool {
        return self.base.isDirty(field_index);
    }
};

/// Array of serf states.
pub const SerfStates = struct {
    serfs: std.ArrayList(SerfStateData),

    pub fn init(_: std.mem.Allocator) SerfStates {
        return .{ .serfs = .empty };
    }

    pub fn deinit(self: *SerfStates, allocator: std.mem.Allocator) void {
        self.serfs.deinit(allocator);
    }

    pub fn add(self: *SerfStates, allocator: std.mem.Allocator, state: SerfStateData) !GameObjectIndex {
        const index = self.serfs.items.len;
        try self.serfs.append(allocator, state);
        return GameObjectIndex{ .index = @intCast(index) };
    }

    pub fn get(self: *SerfStates, index: GameObjectIndex) *SerfStateData {
        return &self.serfs.items[index.index];
    }

    pub fn len(self: SerfStates) usize {
        return self.serfs.items.len;
    }

    /// Remove a serf at the given index (swap-remove for performance).
    pub fn remove(self: *SerfStates, index: GameObjectIndex) void {
        _ = self.serfs.swapRemove(index.index);
    }
};
