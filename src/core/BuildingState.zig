//! Building state — represents one building on the map.
//!
//! Port of the C# BuildingState class with dirty-tracking fields.

const std = @import("std");
const serialize = @import("serialize");
const enums = @import("enums.zig");
const types = @import("types.zig");

const Building = enums.Building;
const Resource = enums.Resource;
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

    // --- Building-local resource stock helpers ---
    // The stock uses two parallel arrays: `resource_types[i]` holds the
    // Resource enum value (as u8) and `resources[i]` holds the count. A slot
    // is free when its count is 0 (so `fish` (value 0) is a valid resource
    // type — the count, not the type, marks emptiness).

    /// Find the slot index holding `res`, or null if not stocked.
    pub fn findStockSlot(self: *BuildingState, res: Resource) ?usize {
        const rt = @intFromEnum(res);
        for (0..4) |i| {
            if (self.resources[i] > 0 and self.resource_types[i] == rt) return i;
        }
        return null;
    }

    /// Find a free slot (count == 0), or null if all slots are occupied.
    pub fn findFreeSlot(self: *BuildingState) ?usize {
        for (0..4) |i| {
            if (self.resources[i] == 0) return i;
        }
        return null;
    }

    /// Count how many of `res` are currently stocked in the building.
    pub fn stockCount(self: BuildingState, res: Resource) u16 {
        if (self.findStockSlotConst(res)) |i| return self.resources[i];
        return 0;
    }

    fn findStockSlotConst(self: BuildingState, res: Resource) ?usize {
        const rt = @intFromEnum(res);
        for (0..4) |i| {
            if (self.resources[i] > 0 and self.resource_types[i] == rt) return i;
        }
        return null;
    }

    /// Add `count` of `res` to the building stock. Returns the number actually
    /// stored (may be less if all slots are full with other resources).
    pub fn addStock(self: *BuildingState, res: Resource, count: u16) u16 {
        const rt = @intFromEnum(res);
        // First, top up an existing slot for this resource.
        if (self.findStockSlot(res)) |i| {
            self.resources[i] +|= count;
            return count;
        }
        // Otherwise claim a free slot.
        if (self.findFreeSlot()) |i| {
            self.resource_types[i] = rt;
            self.resources[i] = count;
            return count;
        }
        return 0;
    }

    /// Remove up to `count` of `res` from the building stock. Returns the
    /// number actually removed.
    pub fn removeStock(self: *BuildingState, res: Resource, count: u16) u16 {
        if (self.findStockSlot(res)) |i| {
            const removed: u16 = @min(count, self.resources[i]);
            self.resources[i] -= removed;
            if (self.resources[i] == 0) self.resource_types[i] = 0;
            return removed;
        }
        return 0;
    }

    /// True if the building stocks at least `count` of `res`.
    pub fn hasStock(self: BuildingState, res: Resource, count: u16) bool {
        return self.stockCount(res) >= count;
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

test "BuildingState stock add/remove" {
    var b = BuildingState{};

    // Adding wood claims a free slot.
    try std.testing.expectEqual(@as(u16, 3), b.addStock(.wood, 3));
    try std.testing.expectEqual(@as(u16, 3), b.stockCount(.wood));
    try std.testing.expect(b.hasStock(.wood, 3));
    try std.testing.expect(!b.hasStock(.wood, 4));

    // Topping up an existing slot.
    try std.testing.expectEqual(@as(u16, 2), b.addStock(.wood, 2));
    try std.testing.expectEqual(@as(u16, 5), b.stockCount(.wood));

    // A second resource claims another slot.
    try std.testing.expectEqual(@as(u16, 1), b.addStock(.stone, 1));
    try std.testing.expectEqual(@as(u16, 1), b.stockCount(.stone));

    // Remove wood.
    try std.testing.expectEqual(@as(u16, 2), b.removeStock(.wood, 2));
    try std.testing.expectEqual(@as(u16, 3), b.stockCount(.wood));

    // Removing all of a resource frees the slot (count→0, type→0).
    try std.testing.expectEqual(@as(u16, 3), b.removeStock(.wood, 10));
    try std.testing.expectEqual(@as(u16, 0), b.stockCount(.wood));
    try std.testing.expectEqual(@as(u8, @intFromEnum(Resource.stone)), b.resource_types[b.findStockSlot(.stone).?]);
}

test "BuildingState stock full" {
    var b = BuildingState{};
    // Fill all 4 slots with different resources.
    _ = b.addStock(.wood, 1);
    _ = b.addStock(.stone, 1);
    _ = b.addStock(.planks, 1);
    _ = b.addStock(.iron, 1);
    // No free slot for a 5th resource type.
    try std.testing.expectEqual(@as(u16, 0), b.addStock(.coal, 1));
    // But topping up an existing resource still works.
    try std.testing.expectEqual(@as(u16, 1), b.addStock(.wood, 1));
    try std.testing.expectEqual(@as(u16, 2), b.stockCount(.wood));
}

test "BuildingState stock fish (enum value 0)" {
    var b = BuildingState{};
    // fish is Resource.fish = 0; make sure it is stored correctly and not
    // confused with an empty slot.
    try std.testing.expectEqual(@as(u16, 2), b.addStock(.fish, 2));
    try std.testing.expectEqual(@as(u16, 2), b.stockCount(.fish));
    try std.testing.expect(b.hasStock(.fish, 2));
    try std.testing.expectEqual(@as(u16, 1), b.removeStock(.fish, 1));
    try std.testing.expectEqual(@as(u16, 1), b.stockCount(.fish));
}
