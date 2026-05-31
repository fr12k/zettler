//! Game — root aggregate that owns all subsystems and drives the game loop.
//!
//! Port of the C# Game class. Coordinates: GameState, Player logic,
//! Serf updates, Building production, Flag transport, AI, and victory conditions.

const std = @import("std");
const serialize = @import("serialize");
const enums = @import("enums.zig");
const types = @import("types.zig");
const GameState = @import("GameState.zig").GameState;
const Map = @import("Map.zig").Map;
const Terrain = @import("Map.zig").Terrain;
const PlayerState = @import("PlayerState.zig").PlayerState;
const PlayerStates = @import("PlayerState.zig").PlayerStates;
const BuildingState = @import("BuildingState.zig").BuildingState;
const FlagState = @import("FlagState.zig").FlagState;
const SerfStateData = @import("SerfState.zig").SerfStateData;
const Inventory = @import("Inventory.zig").Inventory;
const Pathfinder = @import("Pathfinder.zig").Pathfinder;

const Direction = enums.Direction;
const Resource = enums.Resource;
const Building = enums.Building;
const SerfType = enums.SerfType;
const MapPos = types.MapPos;
const GameObjectIndex = types.GameObjectIndex;
const PlayerIndex = types.PlayerIndex;

/// Game speed: how many const-ticks between game logic ticks.
pub const DEFAULT_GAME_SPEED: u8 = 2;
/// Milliseconds per const-tick (50 Hz).
pub const TICK_MS: u64 = 20;
/// Number of players in the game.
pub const MAX_PLAYERS: u8 = 6;

/// Ticks per resource cycle for each building type.
pub const ProductionTimes = struct {
    pub const stonecutter: u16 = 60;
    pub const lumberjack: u16 = 40;
    pub const fisher: u16 = 50;
    pub const farm: u16 = 120;
    pub const mill: u16 = 80;
    pub const bakery: u16 = 70;
    pub const sawmill: u16 = 60;
    pub const iron_smelter: u16 = 100;
    pub const gold_smelter: u16 = 100;
    pub const toolmaker: u16 = 120;
    pub const armory: u16 = 120;
    pub const boatbuilder: u16 = 200;
    pub const slaughterhouse: u16 = 60;
    pub const pig_farm: u16 = 80;
    pub const brewery: u16 = 100;
    pub const winery: u16 = 100;
    pub const forester: u16 = 60;
    pub const coal_mine: u16 = 80;
    pub const iron_mine: u16 = 80;
    pub const gold_mine: u16 = 80;
    pub const granite_mine: u16 = 60;
};

/// The root game object — holds all state and update logic.
pub const Game = struct {
    allocator: std.mem.Allocator,
    state: GameState,
    pathfinder: Pathfinder,

    /// Current constant tick (50 Hz counter, not slowed by game speed).
    const_tick: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, map_w: u16, map_h: u16, player_count: u8) !Game {
        var state = try GameState.init(allocator, map_w, map_h);
        errdefer state.deinit();

        state.players.setPlayerCount(@min(player_count, MAX_PLAYERS));

        // Player 0 is human, others are AI
        for (0..@min(player_count, MAX_PLAYERS)) |i| {
            state.players.players[i].inventory_dirty = true;
        }

        var game = Game{
            .allocator = allocator,
            .state = state,
            .pathfinder = Pathfinder.init(allocator, &state.map),
        };

        // Generate terrain
        game.state.map.generateTerrain(42);

        return game;
    }

    pub fn deinit(self: *Game) void {
        const a = self.allocator;
        self.pathfinder.deinit(a);
        self.state.deinit();
    }

    /// Game tick at 50 Hz. Every `gameSpeed` calls, run a logic tick.
    pub fn tick(self: *Game, current_const_tick: u64) void {
        self.const_tick = current_const_tick;

        if (self.state.is_paused or self.state.is_game_over) return;

        const speed: u64 = if (self.state.speed == 0) 1 else @intCast(self.state.speed);
        if (current_const_tick % speed != 0) return;

        self.state.tick += 1;
        self.processTick();
    }

    /// One logic tick of game simulation.
    fn processTick(self: *Game) void {
        const game_tick = self.state.tick;

        // Update buildings (production, construction)
        self.updateBuildings(game_tick);

        // Update flags (transporter scheduling, queue processing)
        self.updateFlags(game_tick);

        // Update serfs (FSM tick for all serfs)
        self.updateSerfs(game_tick);

        // Update players (AI decisions, resource balancing)
        self.updatePlayers(game_tick);

        // Update inventories (resource redistribution)
        self.updateInventories(game_tick);
    }

    /// Update all buildings.
    fn updateBuildings(self: *Game, game_tick: u64) void {
        for (self.state.buildings.buildings.items, 0..) |*building, i| {
            _ = i;
            if (!building.is_done) {
                // Construction in progress
                if (game_tick % 5 == 0) {
                    building.progress += 1;
                    if (building.progress >= 100) {
                        building.is_done = true;
                    }
                }
                continue;
            }

            if (building.is_burning) continue;

            // Production cycle for producer buildings
            if (building.building_type.isProducer()) {
                building.production_tick += 1;
                const prod_time = getProductionTime(building.building_type);
                if (prod_time > 0 and building.production_tick >= prod_time) {
                    building.production_tick = 0;
                    building.production_count += 1;
                }
            }
        }
    }

    /// Update all flags (transporter scheduling).
    fn updateFlags(self: *Game, _: u64) void {
        for (self.state.flags.flags.items, 0..) |*flag, i| {
            _ = i;
            if (flag.incoming_count > 0 and flag.outgoing_count < @import("FlagState.zig").FlagQueueCapacity) {
                const res = flag.incoming_queue[flag.incoming_count - 1];
                flag.outgoing_queue[flag.outgoing_count] = res;
                flag.outgoing_count += 1;
                flag.incoming_count -= 1;
            }
        }
    }

    /// Update all serfs (their FSM tick).
    fn updateSerfs(_: *Game, _: u64) void {
    }

    /// Update all players (AI + resource balancing).
    fn updatePlayers(_: *Game, _: u64) void {
    }

    /// Update inventories — redistribute resources between flags and buildings.
    fn updateInventories(_: *Game, _: u64) void {
    }

    /// Get the current game map.
    pub fn getMap(self: *Game) *Map {
        return &self.state.map;
    }

    /// Get production time for a building type.
    pub fn getProductionTime(building_type: Building) u16 {
        return switch (building_type) {
            .stonecutter => ProductionTimes.stonecutter,
            .lumberjack => ProductionTimes.lumberjack,
            .fisher => ProductionTimes.fisher,
            .farm => ProductionTimes.farm,
            .mill => ProductionTimes.mill,
            .bakery => ProductionTimes.bakery,
            .sawmill => ProductionTimes.sawmill,
            .iron_smelter => ProductionTimes.iron_smelter,
            .gold_smelter => ProductionTimes.gold_smelter,
            .toolmaker => ProductionTimes.toolmaker,
            .armory => ProductionTimes.armory,
            .boatbuilder => ProductionTimes.boatbuilder,
            .slaughterhouse => ProductionTimes.slaughterhouse,
            .pig_farm => ProductionTimes.pig_farm,
            .brewery => ProductionTimes.brewery,
            .winery => ProductionTimes.winery,
            .forester => ProductionTimes.forester,
            .coal_mine => ProductionTimes.coal_mine,
            .iron_mine => ProductionTimes.iron_mine,
            .gold_mine => ProductionTimes.gold_mine,
            .granite_mine => ProductionTimes.granite_mine,
            else => 0,
        };
    }

    /// Get the resource a building produces.
    pub fn getProducedResource(building_type: Building) ?Resource {
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
            .toolmaker => .shovel, // produces random tool
            .armory => .sword, // produces random equipment
            .boatbuilder => .boat,
            .slaughterhouse => .meat,
            .pig_farm => null, // produces serfs (pigs → meat)
            .brewery => .beer,
            .winery => .wine,
            .forester => .wood, // plants trees
            .coal_mine => .coal,
            .iron_mine => .iron_ore,
            .gold_mine => .gold, // gold ore
            .granite_mine => .stone,
            else => null,
        };
    }

    /// Get the resource a building consumes as input.
    pub fn getInputResource(building_type: Building) ?Resource {
        return switch (building_type) {
            .mill => .grain,
            .bakery => .flour,
            .sawmill => .wood,
            .iron_smelter => .iron_ore,
            .gold_smelter => null, // gold ore
            .toolmaker => .iron, // + coal
            .armory => .iron, // + coal
            .boatbuilder => .wood,
            .slaughterhouse => .meat, // from pig farm
            .pig_farm => .grain,
            .brewery => .grain,
            .winery => .fruit,
            .forester => null, // plants trees
            else => null,
        };
    }

    /// Place a building at the given position for the given player.
    /// Returns the building index, or null if placement fails.
    pub fn placeBuilding(self: *Game, pos: MapPos, building_type: Building, player: u8) !?GameObjectIndex {
        if (!self.state.map.isValidPos(pos)) return null;
        const tile = self.state.map.getTile(pos);
        if (tile.has_building) return null;
        if (!tile.terrain.isBuildable() and !tile.terrain.isMountain()) return null;

        // Mines require mountain terrain
        if (building_type.isMine() and !tile.terrain.isMountain()) return null;

        tile.has_building = true;
        tile.owner = player;

        const building = BuildingState{
            .pos = pos,
            .building_type = building_type,
            .player = player,
            .is_done = false,
            .progress = 0,
        };

        const idx = try self.state.buildings.add(self.allocator, building);
        tile.building_index = idx;

        return idx;
    }

    /// Place a flag at the given position for the given player.
    pub fn placeFlag(self: *Game, pos: MapPos, player: u8) !?GameObjectIndex {
        if (!self.state.map.isValidPos(pos)) return null;
        const tile = self.state.map.getTile(pos);
        if (tile.has_flag) return null;

        tile.has_flag = true;
        tile.owner = player;

        const flag = FlagState{
            .pos = pos,
            .player = player,
        };

        const idx = try self.state.flags.add(self.allocator, flag);
        tile.flag_index = idx;
        return idx;
    }
};

test "Game init and tick" {
    var game = try Game.init(std.testing.allocator, 32, 32, 1);
    defer game.deinit();

    try std.testing.expectEqual(@as(u64, 0), game.state.tick);
    game.tick(2); // speed=2, so this should tick once
    try std.testing.expectEqual(@as(u64, 1), game.state.tick);
}

test "Game place building" {
    var game = try Game.init(std.testing.allocator, 32, 32, 1);
    defer game.deinit();

    const pos = types.MapPos{ .x = 10, .y = 10 };
    const idx = try game.placeBuilding(pos, .lumberjack, 0);

    try std.testing.expect(idx != null);
    if (idx) |i| {
        const building = game.state.buildings.get(i);
        try std.testing.expectEqual(Building.lumberjack, building.building_type);
        try std.testing.expect(!building.is_done);
    }
}

test "Game production time" {
    try std.testing.expectEqual(@as(u16, 40), Game.getProductionTime(.lumberjack));
    try std.testing.expectEqual(@as(u16, 120), Game.getProductionTime(.farm));
    try std.testing.expectEqual(@as(u16, 0), Game.getProductionTime(.none));
}
