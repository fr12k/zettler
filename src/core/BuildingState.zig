//! Building state — represents one building on the map.
//!
//! Port of the C# BuildingState class with dirty-tracking fields.

const std = @import("std");
const serialize = @import("serialize");
const enums = @import("enums.zig");
const types = @import("types.zig");

const Building = enums.Building;
const MapPos = types.MapPos;
const GameObjectIndex = types.GameObjectIndex;

/// The state of a single building instance.
pub const BuildingState = struct {
    /// Game state tracking.
    base: serialize.State = .{},

    // --- Core fields ---
    pos: MapPos = MapPos.invalid,
    building_type: Building = .none,
    player: u8 = 0xFF,

    // --- Construction ---
    is_burning: bool = false,
    is_done: bool = false,
    progress: u16 = 0,

    // --- Serf assignment ---
    serf_index: GameObjectIndex = GameObjectIndex.invalid,

    // --- Resource stock (for production buildings) ---
    /// Resources stored inside the building.
    resources: [4]u16 = @splat(0),
    resource_types: [4]u8 = @splat(0),

    // --- Production timing ---
    /// Tick counter for production cycles.
    production_tick: u16 = 0,
    /// Number of resources produced per cycle.
    production_count: u8 = 0,

    // --- Military (for towers/fortresses) ---
    knight_count: u8 = 0,
    knight_capacity: u8 = 0,

    // --- Flag reference ---
    flag_index: GameObjectIndex = GameObjectIndex.invalid,

    // --- Animation state ---
    animation_frame: u8 = 0,
    animation_tick: u16 = 0,

    pub fn markDirty(self: *BuildingState, field_index: u6) void {
        self.base.markDirty(field_index);
    }

    pub fn isDirty(self: BuildingState, field_index: u6) bool {
        return self.base.isDirty(field_index);
    }
};

/// Array of building states. The C# version uses a List<BuildingState>.
/// In Zig we use a dense array with a max capacity.
pub const BuildingStates = struct {
    buildings: std.ArrayList(BuildingState),

    pub fn init(_: std.mem.Allocator) BuildingStates {
        return .{ .buildings = .empty };
    }

    pub fn deinit(self: *BuildingStates, allocator: std.mem.Allocator) void {
        self.buildings.deinit(allocator);
    }

    pub fn add(self: *BuildingStates, allocator: std.mem.Allocator, state: BuildingState) !GameObjectIndex {
        const index = self.buildings.items.len;
        try self.buildings.append(allocator, state);
        return GameObjectIndex{ .index = @intCast(index) };
    }

    pub fn get(self: *BuildingStates, index: GameObjectIndex) *BuildingState {
        return &self.buildings.items[index.index];
    }

    pub fn len(self: BuildingStates) usize {
        return self.buildings.items.len;
    }
};
