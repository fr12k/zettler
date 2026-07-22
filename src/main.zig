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
const MapMinSize = core.map.MIN_SIZE;
const MapMaxSize = core.map.MAX_SIZE;

/// Default map dimensions (the classic Settlers map size).
const DEFAULT_MAP_W: u16 = 64;
const DEFAULT_MAP_H: u16 = 64;

/// Search paths for game data files.
const data_paths = [_][]const u8{
    "data/spae.pa",
    "data/SPAE.PA",
    "../data/spae.pa",
    "../data/SPAE.PA",
    "SPAE.PA",
};

/// Parsed startup options.
const Options = struct {
    map_w: u16 = DEFAULT_MAP_W,
    map_h: u16 = DEFAULT_MAP_H,
};

/// Parse command-line arguments for map dimensions.
/// Supported forms:
///   --map-size <W> <H>    e.g. --map-size 256 256
///   --map-size=WxH          e.g. --map-size=256x256
///   --map-w <W> --map-h <H>
fn parseArgs(args: std.process.Args, allocator: std.mem.Allocator) !Options {
    var opts = Options{};
    var args_it = try std.process.Args.Iterator.initAllocator(args, allocator);
    defer args_it.deinit();
    _ = args_it.next(); // skip program name
    while (args_it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--map-size")) {
            const w_str = args_it.next() orelse {
                std.debug.print("--map-size requires <width> <height>\n", .{});
                return opts;
            };
            const h_str = args_it.next() orelse {
                std.debug.print("--map-size requires <width> <height>\n", .{});
                return opts;
            };
            opts.map_w = std.fmt.parseInt(u16, w_str, 10) catch {
                std.debug.print("Invalid map width '{s}'\n", .{w_str});
                return opts;
            };
            opts.map_h = std.fmt.parseInt(u16, h_str, 10) catch {
                std.debug.print("Invalid map height '{s}'\n", .{h_str});
                return opts;
            };
        } else if (std.mem.startsWith(u8, arg, "--map-size=")) {
            const rest = arg["--map-size=".len..];
            if (std.mem.indexOfScalar(u8, rest, 'x')) |sep| {
                opts.map_w = std.fmt.parseInt(u16, rest[0..sep], 10) catch {
                    std.debug.print("Invalid map size '{s}'\n", .{rest});
                    return opts;
                };
                opts.map_h = std.fmt.parseInt(u16, rest[sep + 1 ..], 10) catch {
                    std.debug.print("Invalid map size '{s}'\n", .{rest});
                    return opts;
                };
            } else {
                std.debug.print("--map-size=WxH: missing 'x' separator in '{s}'\n", .{rest});
                return opts;
            }
        } else if (std.mem.eql(u8, arg, "--map-w")) {
            const w_str = args_it.next() orelse {
                std.debug.print("--map-w requires a width\n", .{});
                return opts;
            };
            opts.map_w = std.fmt.parseInt(u16, w_str, 10) catch {
                std.debug.print("Invalid map width '{s}'\n", .{w_str});
                return opts;
            };
        } else if (std.mem.eql(u8, arg, "--map-h")) {
            const h_str = args_it.next() orelse {
                std.debug.print("--map-h requires a height\n", .{});
                return opts;
            };
            opts.map_h = std.fmt.parseInt(u16, h_str, 10) catch {
                std.debug.print("Invalid map height '{s}'\n", .{h_str});
                return opts;
            };
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            std.process.exit(0);
        } else {
            std.debug.print("Unknown argument '{s}' (ignored)\n", .{arg});
        }
    }

    // Clamp to the supported range and report when the requested size was
    // adjusted.
    const orig_w = opts.map_w;
    const orig_h = opts.map_h;
    opts.map_w = @max(MapMinSize, @min(MapMaxSize, opts.map_w));
    opts.map_h = @max(MapMinSize, @min(MapMaxSize, opts.map_h));
    if (opts.map_w != orig_w or opts.map_h != orig_h) {
        std.debug.print(
            "Map size {d}x{d} is outside the supported range, clamped to {d}x{d}\n",
            .{ orig_w, orig_h, opts.map_w, opts.map_h },
        );
    }
    return opts;
}

fn printUsage() void {
    std.debug.print(
        \\Usage: freeserf [options]
        \\
        \\Options:
        \\  --map-size <W> <H>   Set the map size (e.g. --map-size 256 256)
        \\  --map-size=WxH        Set the map size (e.g. --map-size=256x256)
        \\  --map-w <W>           Set the map width
        \\  --map-h <H>           Set the map height
        \\  --help, -h            Show this help
        \\
        \\Map sizes from {d}x{d} to {d}x{d} are supported.
        \\
    , .{ MapMinSize, MapMinSize, MapMaxSize, MapMaxSize });
}

pub fn main(init: std.process.Init.Minimal) !void {
    std.debug.print("Freeserf Zig — First Playable Build\n", .{});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const opts = try parseArgs(init.args, allocator);
    std.debug.print("Map size: {d}x{d}\n", .{ opts.map_w, opts.map_h });

    // Try GLFW first, fall back to terminal demo
    const app_result = runGlfwDemo(allocator, opts.map_w, opts.map_h);
    if (app_result) |_| {} else |_| {
        try runTerminalDemo(allocator, opts.map_w, opts.map_h);
    }
}

fn runGlfwDemo(allocator: std.mem.Allocator, map_w: u16, map_h: u16) !void {
    std.debug.print("Initializing...\n", .{});

    var app = try App.init(allocator, map_w, map_h);
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
    // Place the starter cluster around the map center so it is visible no
    // matter what map size was selected at startup.
    const cx: u16 = app.game.state.map.width / 2;
    const cy: u16 = app.game.state.map.height / 2;
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

fn runTerminalDemo(allocator: std.mem.Allocator, map_w: u16, map_h: u16) !void {
    const out = std.debug.print;
    out("No display — terminal demo.\n", .{});

    var game = try Game.init(allocator, map_w, map_h, 1);
    defer game.deinit();

    const cx: u16 = map_w / 2;
    const cy: u16 = map_h / 2;
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
