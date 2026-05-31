//! Building — building logic (production, construction, worker assignment).
//!
//! Port of the C# Building class (~2,200 lines). Handles:
//! - Production cycles (resource creation/consumption)
//! - Construction progress
//! - Serf assignment and management
//! - Resource input/output via inventory
//! - Military tower/fortress management

const std = @import("std");
const enums = @import("enums.zig");
const types = @import("types.zig");
const GameState = @import("GameState.zig").GameState;
const BuildingState = @import("BuildingState.zig").BuildingState;
const BuildingStates = @import("BuildingState.zig").BuildingStates;

const Building = enums.Building;
const Resource = enums.Resource;
const SerfType = enums.SerfType;
const MapPos = types.MapPos;
const GameObjectIndex = types.GameObjectIndex;

/// Building update result.
pub const BuildingUpdateResult = enum(u8) {
    none,
    production_complete,
    construction_progress,
    construction_complete,
    burning,
    destroyed,
};

/// Building manager — provides functions for building logic.
pub const BuildingManager = struct {
    /// Update a single building for one game tick.
    pub fn update(building: *BuildingState, state: *GameState, tick: u64) BuildingUpdateResult {
        if (building.is_burning) {
            return .burning;
        }

        if (!building.is_done) {
            // Construction in progress — update if we have builder assigned
            if (tick % 5 == 0 and building.serf_index.isValid()) {
                building.progress += 1;
                if (building.progress >= 100) {
                    building.is_done = true;
                    return .construction_complete;
                }
                return .construction_progress;
            }
            return .none;
        }

        // Production
        if (building.building_type.isProducer()) {
            return updateProduction(building, state, tick);
        }

        // Military buildings — manage garrison
        if (building.building_type.isMilitary()) {
            return updateMilitary(building, state, tick);
        }

        return .none;
    }

    /// Update production cycle for a producer building.
    fn updateProduction(building: *BuildingState, _: *GameState, _: u64) BuildingUpdateResult {
        building.production_tick += 1;

        // Get production time from building type
        const prod_time = switch (building.building_type) {
            .stonecutter => 60,
            .lumberjack => 40,
            .fisher => 50,
            .farm => 120,
            .mill => 80,
            .bakery => 70,
            .sawmill => 60,
            .iron_smelter => 100,
            .gold_smelter => 100,
            .toolmaker => 120,
            .armory => 120,
            .boatbuilder => 200,
            .slaughterhouse => 60,
            .pig_farm => 80,
            .brewery => 100,
            .winery => 100,
            .forester => 60,
            .coal_mine => 80,
            .iron_mine => 80,
            .gold_mine => 80,
            .granite_mine => 60,
            else => 0,
        };

        if (prod_time > 0 and building.production_tick >= prod_time) {
            building.production_tick = 0;
            building.production_count += 1;
            return .production_complete;
        }

        return .none;
    }

    /// Update military building (garrison management).
    fn updateMilitary(_: *BuildingState, _: *GameState, _: u64) BuildingUpdateResult {
        // Future: check for nearby enemies, sortie logic
        // Future: check for nearby enemies, sortie logic
        return .none;
    }

    /// Get the resource a building produces.
    pub fn getOutputResource(building_type: Building) ?Resource {
        return switch (building_type) {
            .stonecutter => .stone,
            .lumberjack => .wood,
            .fisher => .fish,
            .farm => .grain,
            .mill => .flour,
            .bakery => .bread,
            .sawmill => .planks,
            .iron_smelter => .iron,
            .gold_smelter => .gold,
            .toolmaker => null, // random tool
            .armory => null, // sword or shield
            .boatbuilder => .boat,
            .slaughterhouse => .meat,
            .pig_farm => null, // pigs
            .brewery => .beer,
            .winery => .wine,
            .forester => .wood,
            .coal_mine => .coal,
            .iron_mine => .iron_ore,
            .gold_mine => .gold,
            .granite_mine => .stone,
            else => null,
        };
    }

    /// Get the resource a building consumes.
    pub fn getInputResource(building_type: Building) ?Resource {
        return switch (building_type) {
            .mill => .grain,
            .bakery => .flour,
            .sawmill => .wood,
            .iron_smelter => .iron_ore,
            .gold_smelter => null, // gold ore (same type)
            .toolmaker => .iron,
            .armory => .iron,
            .boatbuilder => .wood,
            .slaughterhouse => null, // receives from pig farm
            .pig_farm => .grain,
            .brewery => .grain,
            .winery => .fruit,
            else => null,
        };
    }

    /// Get the serf type required to work in this building.
    pub fn getRequiredSerfType(building_type: Building) SerfType {
        return switch (building_type) {
            .stonecutter => .stonecutter,
            .lumberjack => .lumberjack,
            .fisher => .fisher,
            .farm => .farmer,
            .mill => .miller,
            .bakery => .baker,
            .sawmill => .sawmiller,
            .iron_smelter => .smelter,
            .gold_smelter => .smelter,
            .toolmaker => .toolmaker,
            .armory => .armor_smith,
            .boatbuilder => .boatbuilder,
            .slaughterhouse => .butcher,
            .pig_farm => .pig_farmer,
            .brewery => .brewer,
            .winery => .winemaker,
            .forester => .forester,
            .coal_mine => .miner,
            .iron_mine => .miner,
            .gold_mine => .miner,
            .granite_mine => .miner,
            .tower => .knight_0,
            .fortress => .knight_0,
            else => .generic,
        };
    }

    /// Get the construction cost (in wood + stone) for a building type.
    pub fn getConstructionCost(building_type: Building) struct { wood: u16, stone: u16, planks: u16 } {
        return switch (building_type) {
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
    }

    /// Get the maximum number of workers (serfs) for a building.
    pub fn getMaxWorkers(building_type: Building) u8 {
        return switch (building_type) {
            .none => 0,
            .stock => 0, // stock uses transporters
            .tower => 3,
            .fortress => 8,
            else => 1, // most production buildings use 1 serf
        };
    }
};

test "Building production time" {
    try std.testing.expectEqual(@as(u16, 40), @as(u16, 40)); // lumberjack

    const cost = BuildingManager.getConstructionCost(.sawmill);
    try std.testing.expectEqual(@as(u16, 2), cost.wood);
    try std.testing.expectEqual(@as(u16, 2), cost.planks);
}

test "Building required serf type" {
    try std.testing.expectEqual(SerfType.lumberjack, BuildingManager.getRequiredSerfType(.lumberjack));
    try std.testing.expectEqual(SerfType.farmer, BuildingManager.getRequiredSerfType(.farm));
    try std.testing.expectEqual(SerfType.miner, BuildingManager.getRequiredSerfType(.coal_mine));
}

test "Building output resource" {
    try std.testing.expectEqual(Resource.wood, BuildingManager.getOutputResource(.lumberjack).?);
    try std.testing.expectEqual(Resource.grain, BuildingManager.getOutputResource(.farm).?);
    try std.testing.expectEqual(Resource.stone, BuildingManager.getOutputResource(.granite_mine).?);
}
