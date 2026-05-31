//! Freeserf — a free reimplementation of The Settlers (1993).
//!
//! First playable build: loads SPAE.PA game data, renders the map
//! with real terrain sprites, shows buildings, and handles input.

const std = @import("std");
const core = @import("core");
const render = @import("render");

const App = render.App;
const Game = core.game.Game;
const Resource = core.Resource;
const Building = core.Building;
const MapPos = core.types.MapPos;

/// Search paths for game data files.
const data_paths = [_][]const u8{
    "data/spae.pa",
    "data/SPAE.PA",
    "../data/spae.pa",
    "../data/SPAE.PA",
    "SPAE.PA",
};

pub fn main(init: std.process.Init.Minimal) !void {
    _ = init;

    std.debug.print("Freeserf Zig — First Playable Build\n", .{});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Try GLFW first, fall back to terminal demo
    const app_result = runGlfwDemo(allocator);
    if (app_result) |_| {} else |_| {
        try runTerminalDemo(allocator);
    }
}

fn runGlfwDemo(allocator: std.mem.Allocator) !void {
    std.debug.print("Initializing...\n", .{});

    var app = try App.init(allocator);
    errdefer app.deinit();

    // Load game data (before OpenGL context — just file reading)
    std.debug.print("Loading game data...\n", .{});
    const data_loaded = try app.loadGameData(&data_paths);
    if (!data_loaded) {
        std.debug.print("  No game data found — using fallback colors.\n", .{});
    }

    try setupDemoScene(&app);
    try app.createWindow();
    errdefer {
        app.deinit();
        render.glfw.terminate();
    }

    // Build texture atlas AFTER OpenGL context is created
    if (data_loaded) {
        std.debug.print("Building texture atlas...\n", .{});
        app.buildAtlas() catch |e| {
            std.debug.print("  Atlas build failed: {}\n", .{e});
        };
    }

    app.running = true;
    std.debug.print("Window created. Running game loop...\n", .{});
    app.run() catch |e| {
        std.debug.print("Game loop error: {}\n", .{e});
    };

    app.deinit();
    render.glfw.terminate();
    std.debug.print("Demo complete.\n", .{});
}

fn setupDemoScene(app: *App) !void {
    const p0: u8 = 0;
    const cx: u16 = 32;
    const cy: u16 = 32;
    const game = &app.game;

    const positions = [_]MapPos{
        .{ .x = cx + 3, .y = cy },
        .{ .x = cx, .y = cy + 3 },
        .{ .x = cx, .y = cy },
        .{ .x = cx + 2, .y = cy + 2 },
        .{ .x = cx - 3, .y = cy },
        .{ .x = cx + 1, .y = cy - 2 },
        .{ .x = cx - 2, .y = cy + 1 },
        .{ .x = cx + 2, .y = cy - 1 },
        .{ .x = cx - 1, .y = cy + 2 },
    };
    for (positions) |pos| {
        game.state.map.getTile(pos).terrain = .grass;
    }

    const building_types = [_]Building{
        .lumberjack, .fisher,     .stock,
        .sawmill,    .forester,   .farm,
        .tower,      .stonecutter, .mill,
    };

    for (building_types, 0..) |btype, i| {
        if (i < positions.len) {
            const idx = (try game.placeBuilding(positions[i], btype, p0)) orelse continue;
            const building = game.state.buildings.get(idx);
            building.is_done = true;
            if (btype.isProducer()) {
                building.serf_index = .{ .index = @intCast(i) };
            }
        }
    }

    const p = &game.state.players.players[0];
    p.resources[@intFromEnum(Resource.wood)] = 20;
    p.resources[@intFromEnum(Resource.stone)] = 10;
    p.resources[@intFromEnum(Resource.planks)] = 15;
    p.resources[@intFromEnum(Resource.fish)] = 8;
    p.resources[@intFromEnum(Resource.bread)] = 6;
    p.resources[@intFromEnum(Resource.iron)] = 4;
    p.resources[@intFromEnum(Resource.coal)] = 3;
    p.resources[@intFromEnum(Resource.beer)] = 2;

    std.debug.print("  Scene: {} buildings\n", .{building_types.len});
}

fn runTerminalDemo(allocator: std.mem.Allocator) !void {
    const out = std.debug.print;
    out("No display — terminal demo.\n", .{});

    var game = try Game.init(allocator, 64, 64, 1);
    defer game.deinit();

    const cx: u16 = 32;
    const cy: u16 = 32;
    const positions = [_]MapPos{
        .{ .x = cx + 3, .y = cy }, .{ .x = cx, .y = cy + 3 },
        .{ .x = cx, .y = cy }, .{ .x = cx + 2, .y = cy + 2 },
        .{ .x = cx - 3, .y = cy },
    };
    for (positions) |pos| game.state.map.getTile(pos).terrain = .grass;

    _ = try game.placeBuilding(positions[0], .lumberjack, 0);
    _ = try game.placeBuilding(positions[1], .fisher, 0);
    _ = try game.placeBuilding(positions[2], .stock, 0);
    _ = try game.placeBuilding(positions[3], .sawmill, 0);
    _ = try game.placeBuilding(positions[4], .forester, 0);

    const p = &game.state.players.players[0];
    p.resources[@intFromEnum(Resource.wood)] = 10;
    p.resources[@intFromEnum(Resource.stone)] = 5;
    p.resources[@intFromEnum(Resource.planks)] = 8;
    p.resources[@intFromEnum(Resource.fish)] = 6;

    var tick: u64 = 0;
    while (tick < 1000) : (tick += 1) {
        game.tick(tick);
        if (tick > 0 and tick % 50 == 0) {
            out("[T={}] Wood:{} Planks:{} Stone:{} Fish:{} Bldgs:{}\n", .{
                game.state.tick,
                p.resources[@intFromEnum(Resource.wood)],
                p.resources[@intFromEnum(Resource.planks)],
                p.resources[@intFromEnum(Resource.stone)],
                p.resources[@intFromEnum(Resource.fish)],
                game.state.buildings.buildings.items.len,
            });
        }
    }
    out("\nTerminal demo complete.\n", .{});
}
