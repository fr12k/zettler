//! Player — player logic (resource management, AI decisions).
//!
//! Port of the C# Player class (~2,200 lines). Handles:
//! - Resource balancing and distribution
//! - Building construction requests
//! - Serf assignment to buildings
//! - Military unit management
//! - Territory expansion

const std = @import("std");
const enums = @import("enums.zig");
const types = @import("types.zig");
const GameState = @import("GameState.zig").GameState;
const PlayerState = @import("PlayerState.zig").PlayerState;
const PlayerStates = @import("PlayerState.zig").PlayerStates;
const BuildingState = @import("BuildingState.zig").BuildingState;
const SerfStateData = @import("SerfState.zig").SerfStateData;
const SerfType = enums.SerfType;
const Resource = enums.Resource;
const Building = enums.Building;
const MapPos = types.MapPos;
const GameObjectIndex = types.GameObjectIndex;

/// Resource distribution strategy.
pub const DistributionStrategy = enum(u2) {
    /// Don't distribute this resource.
    none,
    /// Send resources away from stock to buildings.
    distribute,
    /// Collect resources to stock.
    collect,
};

/// Player update result.
pub const PlayerActionResult = enum(u8) {
    none,
    building_placed,
    serf_assigned,
    resource_distributed,
};

/// Player manager — provides functions for per-player logic.
pub const PlayerManager = struct {
    /// Update a player for one game tick.
    pub fn update(_player: *PlayerState, _state: *GameState, _player_index: u8, _tick: u64) PlayerActionResult {
        // Future: resource balancing, AI decisions
        _ = _player;
        _ = _state;
        _ = _player_index;
        _ = _tick;
        return .none;
    }

    /// Check if a player has enough resources to construct a building.
    pub fn canAfford(player: *PlayerState, building_type: Building) bool {
        const cost = switch (building_type) {
            .stonecutter => .{ .wood = 1, .stone = 0, .planks = 1 },
            .lumberjack => .{ .wood = 1, .stone = 0, .planks = 1 },
            .boatbuilder => .{ .wood = 2, .stone = 0, .planks = 2 },
            .sawmill => .{ .wood = 2, .stone = 0, .planks = 2 },
            .forester => .{ .wood = 1, .stone = 0, .planks = 1 },
            .stock => .{ .wood = 3, .stone = 2, .planks = 3 },
            .granite_mine => .{ .wood = 2, .stone = 0, .planks = 2 },
            .coal_mine => .{ .wood = 2, .stone = 0, .planks = 2 },
            .iron_mine => .{ .wood = 2, .stone = 0, .planks = 2 },
            .gold_mine => .{ .wood = 2, .stone = 0, .planks = 2 },
            .iron_smelter => .{ .wood = 2, .stone = 1, .planks = 2 },
            .gold_smelter => .{ .wood = 2, .stone = 1, .planks = 2 },
            .armory => .{ .wood = 2, .stone = 1, .planks = 2 },
            .toolmaker => .{ .wood = 2, .stone = 1, .planks = 2 },
            .bakery => .{ .wood = 1, .stone = 0, .planks = 1 },
            .mill => .{ .wood = 2, .stone = 1, .planks = 2 },
            .slaughterhouse => .{ .wood = 1, .stone = 0, .planks = 1 },
            .pig_farm => .{ .wood = 1, .stone = 0, .planks = 1 },
            .brewery => .{ .wood = 1, .stone = 0, .planks = 1 },
            .winery => .{ .wood = 1, .stone = 0, .planks = 1 },
            .farm => .{ .wood = 2, .stone = 0, .planks = 2 },
            .fisher => .{ .wood = 1, .stone = 0, .planks = 1 },
            .tower => .{ .wood = 2, .stone = 2, .planks = 2 },
            .fortress => .{ .wood = 4, .stone = 4, .planks = 4 },
            .none => .{ .wood = 0, .stone = 0, .planks = 0 },
        };
        return player.resources[@intFromEnum(Resource.wood)] >= cost.wood and
            player.resources[@intFromEnum(Resource.stone)] >= cost.stone and
            player.resources[@intFromEnum(Resource.planks)] >= cost.planks;
    }

    /// Deduct construction cost from player's resources.
    pub fn payFor(player: *PlayerState, building_type: Building) void {
        const cost = switch (building_type) {
            .stonecutter => .{ .wood = 1, .stone = 0, .planks = 1 },
            .lumberjack => .{ .wood = 1, .stone = 0, .planks = 1 },
            .boatbuilder => .{ .wood = 2, .stone = 0, .planks = 2 },
            .sawmill => .{ .wood = 2, .stone = 0, .planks = 2 },
            .forester => .{ .wood = 1, .stone = 0, .planks = 1 },
            .stock => .{ .wood = 3, .stone = 2, .planks = 3 },
            .granite_mine => .{ .wood = 2, .stone = 0, .planks = 2 },
            .coal_mine => .{ .wood = 2, .stone = 0, .planks = 2 },
            .iron_mine => .{ .wood = 2, .stone = 0, .planks = 2 },
            .gold_mine => .{ .wood = 2, .stone = 0, .planks = 2 },
            .iron_smelter => .{ .wood = 2, .stone = 1, .planks = 2 },
            .gold_smelter => .{ .wood = 2, .stone = 1, .planks = 2 },
            .armory => .{ .wood = 2, .stone = 1, .planks = 2 },
            .toolmaker => .{ .wood = 2, .stone = 1, .planks = 2 },
            .bakery => .{ .wood = 1, .stone = 0, .planks = 1 },
            .mill => .{ .wood = 2, .stone = 1, .planks = 2 },
            .slaughterhouse => .{ .wood = 1, .stone = 0, .planks = 1 },
            .pig_farm => .{ .wood = 1, .stone = 0, .planks = 1 },
            .brewery => .{ .wood = 1, .stone = 0, .planks = 1 },
            .winery => .{ .wood = 1, .stone = 0, .planks = 1 },
            .farm => .{ .wood = 2, .stone = 0, .planks = 2 },
            .fisher => .{ .wood = 1, .stone = 0, .planks = 1 },
            .tower => .{ .wood = 2, .stone = 2, .planks = 2 },
            .fortress => .{ .wood = 4, .stone = 4, .planks = 4 },
            .none => .{ .wood = 0, .stone = 0, .planks = 0 },
        };
        player.resources[@intFromEnum(Resource.wood)] -= cost.wood;
        player.resources[@intFromEnum(Resource.stone)] -= cost.stone;
        player.resources[@intFromEnum(Resource.planks)] -= cost.planks;
    }

    /// Count total serfs for a player across all types.
    pub fn totalSerfs(player: *PlayerState) u32 {
        var total: u32 = 0;
        for (player.serf_count) |count| {
            total += count;
        }
        return total;
    }

    /// Get total military strength for a player.
    pub fn militaryStrength(player: *PlayerState) u32 {
        var strength: u32 = 0;
        // Count knights with rank weighting
        for (21..27) |knight_type| {
            const rank = knight_type - 20; // 1-6
            strength += @as(u32, player.serf_count[knight_type]) * rank;
        }
        return strength;
    }
};

test "Player can afford simple building" {
    var player = PlayerState{};
    player.resources[@intFromEnum(Resource.wood)] = 5;
    player.resources[@intFromEnum(Resource.planks)] = 5;

    try std.testing.expect(PlayerManager.canAfford(&player, .lumberjack));
    try std.testing.expect(PlayerManager.canAfford(&player, .sawmill));

    // Not enough stone for tower
    try std.testing.expect(!PlayerManager.canAfford(&player, .tower));
}

test "Player pay for building" {
    var player = PlayerState{};
    player.resources[@intFromEnum(Resource.wood)] = 5;
    player.resources[@intFromEnum(Resource.planks)] = 5;

    PlayerManager.payFor(&player, .lumberjack);
    try std.testing.expectEqual(@as(u16, 4), player.resources[@intFromEnum(Resource.wood)]);
    try std.testing.expectEqual(@as(u16, 4), player.resources[@intFromEnum(Resource.planks)]);
}

test "Player serf count" {
    var player = PlayerState{};
    player.serf_count[@intFromEnum(SerfType.lumberjack)] = 3;
    player.serf_count[@intFromEnum(SerfType.farmer)] = 2;
    player.serf_count[@intFromEnum(SerfType.baker)] = 1;

    try std.testing.expectEqual(@as(u32, 6), PlayerManager.totalSerfs(&player));
}
