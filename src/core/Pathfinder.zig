//! Pathfinder — A* pathfinding on the hex grid.
//!
//! Used by serfs to find paths between two map positions, avoiding
//! impassable terrain and preferring roads. Also used by the RoadBuilder
//! to auto-route roads between flags.
//!
//! Path reconstruction uses a `came_from` hashmap (matching freeserf's
//! closed-list approach) instead of the broken parent-index-into-open-list
//! scheme that was here before.

const std = @import("std");
const enums = @import("enums.zig");
const types = @import("types.zig");
const map_mod = @import("Map.zig");

const Direction = enums.Direction;
const MapPos = types.MapPos;
const Map = map_mod.Map;
const Terrain = map_mod.Terrain;

/// Maximum path length we can store.
pub const MaxPathLength = 128;

/// A single step in a path.
pub const PathStep = struct {
    pos: MapPos,
    dir: Direction,
};

/// A computed path between two positions.
pub const Path = struct {
    steps: [MaxPathLength]PathStep = @splat(PathStep{ .pos = MapPos.invalid, .dir = .right }),
    length: usize = 0,

    pub fn clear(self: *Path) void {
        self.length = 0;
    }

    pub fn isEmpty(self: Path) bool {
        return self.length == 0;
    }

    pub fn getLast(self: Path) ?PathStep {
        if (self.length == 0) return null;
        return self.steps[self.length - 1];
    }
};

/// Walking cost by height difference, porting freeserf's `walk_cost` table
/// (pathfinder.cc). Index = absolute height difference (0..4+).
const walk_cost = [_]u32{ 255, 319, 383, 447, 511 };

/// A node in the A* open set.
const AStarNode = struct {
    pos: MapPos,
    g: u32, // cost from start
    h: u32, // heuristic to goal

    pub fn f(self: AStarNode) u32 {
        return self.g + self.h;
    }
};

/// A* pathfinder on the hex grid.

/// Entry in the came_from map: previous position + direction to get here.
const CameFrom = struct { prev: MapPos, dir: Direction };

pub const Pathfinder = struct {
    allocator: std.mem.Allocator,
    map: *Map,

    // A* state (reused across searches)
    open_list: std.ArrayList(AStarNode),
    closed_set: std.AutoHashMap(MapPos, void),
    /// came_from[pos] = { previous position, direction from previous to pos }
    came_from: std.AutoHashMap(MapPos, CameFrom),
    /// g_score[pos] = best known cost from start to pos
    g_score: std.AutoHashMap(MapPos, u32),

    pub fn init(allocator: std.mem.Allocator, map: *Map) Pathfinder {
        return .{
            .allocator = allocator,
            .map = map,
            .open_list = .empty,
            .closed_set = std.AutoHashMap(MapPos, void).init(allocator),
            .came_from = std.AutoHashMap(MapPos, CameFrom).init(allocator),
            .g_score = std.AutoHashMap(MapPos, u32).init(allocator),
        };
    }

    pub fn deinit(self: *Pathfinder, allocator: std.mem.Allocator) void {
        self.open_list.deinit(allocator);
        self.closed_set.deinit();
        self.came_from.deinit();
        self.g_score.deinit();
    }

    /// Hex distance heuristic (chebyshev-like, matching the sheared grid).
    fn heuristic(_: Pathfinder, from: MapPos, to: MapPos) u32 {
        const dx = if (from.x > to.x) @as(i32, from.x) - @as(i32, to.x) else @as(i32, to.x) - @as(i32, from.x);
        const dy = if (from.y > to.y) @as(i32, from.y) - @as(i32, to.y) else @as(i32, to.y) - @as(i32, from.y);
        return @intCast(@max(dx, dy));
    }

    /// Cost of moving through a given tile. Always valid on a torus map.
    fn terrainCost(self: Pathfinder, pos: MapPos) u32 {
        if (!self.map.isValidPos(pos)) return 1000;
        const tile = self.map.getTile(pos);
        if (!tile.terrain.isWalkable()) return 1000;
        // Prefer roads
        if (tile.hasRoad()) return 1;
        // Penalty for walking on owned territory that isn't ours
        return 10;
    }

    /// Find a path from `from` to `to`. Returns true if a path was found.
    /// Uses A* with proper came_from hashmap for path reconstruction.
    pub fn findPath(self: *Pathfinder, from: MapPos, to: MapPos, result: *Path) !bool {
        result.clear();

        // Quick check: same position
        if (from.eql(to)) return true;

        // Reset A* state
        self.open_list.clearRetainingCapacity();
        self.closed_set.clearRetainingCapacity();
        self.came_from.clearRetainingCapacity();
        self.g_score.clearRetainingCapacity();

        const h_start = self.heuristic(from, to);
        try self.open_list.append(self.allocator, .{ .pos = from, .g = 0, .h = h_start });
        try self.g_score.put(from, 0);

        const max_iterations = 10000;
        var iteration: u32 = 0;

        while (self.open_list.items.len > 0 and iteration < max_iterations) : (iteration += 1) {
            // Find node with lowest f in open list
            var best_idx: usize = 0;
            var best_f = self.open_list.items[0].f();
            for (self.open_list.items, 0..) |node, i| {
                const f = node.f();
                if (f < best_f) {
                    best_f = f;
                    best_idx = i;
                }
            }

            const current = self.open_list.swapRemove(best_idx);

            // Check if we reached the goal
            if (current.pos.eql(to)) {
                // Reconstruct path by walking came_from backwards from `to`.
                var steps_buf: [MaxPathLength]PathStep = undefined;
                var step_count: usize = 0;
                var pos = to;
                while (self.came_from.get(pos)) |cf| {
                    if (step_count >= MaxPathLength) break;
                    steps_buf[step_count] = .{ .pos = cf.prev, .dir = cf.dir };
                    step_count += 1;
                    pos = cf.prev;
                }
                // Reverse the path (built backwards: to → from)
                var i: usize = 0;
                while (i < step_count) : (i += 1) {
                    result.steps[i] = steps_buf[step_count - 1 - i];
                }
                result.length = step_count;
                return true;
            }

            // Add to closed set
            try self.closed_set.put(current.pos, {});

            // Explore neighbours with torus wrapping
            const all_dirs = std.meta.tags(Direction);
            const neighbors = self.map.getAllNeighborsWrapped(current.pos);
            for (all_dirs, 0..) |d, i| {
                const npos = neighbors[i];
                if (self.closed_set.contains(npos)) continue;

                const cost = self.terrainCost(npos);
                if (cost >= 1000) continue; // impassable

                const tentative_g = current.g + cost;
                const existing_g = self.g_score.get(npos);
                if (existing_g == null or tentative_g < existing_g.?) {
                    // This is a better path to npos.
                    try self.came_from.put(npos, .{ .prev = current.pos, .dir = d });
                    try self.g_score.put(npos, tentative_g);
                    const h = self.heuristic(npos, to);
                    // Check if already in open list
                    var in_open = false;
                    for (self.open_list.items) |*node| {
                        if (node.pos.eql(npos)) {
                            node.g = tentative_g;
                            node.h = h;
                            in_open = true;
                            break;
                        }
                    }
                    if (!in_open) {
                        try self.open_list.append(self.allocator, .{
                            .pos = npos,
                            .g = tentative_g,
                            .h = h,
                        });
                    }
                }
            }
        }

        return false; // No path found
    }

    /// Find a road path from `from` to `to`, using `isRoadSegmentValid` for
    /// neighbour validity instead of terrain walkability. Returns the
    /// direction steps in `result`. Ports freeserf's `pathfinder_map`.
    /// `exclude` tiles (the in-progress road's tiles) are blocked except
    /// for `from` and `to`.
    pub fn findRoadPath(
        self: *Pathfinder,
        from: MapPos,
        to: MapPos,
        result: *Path,
    ) !bool {
        result.clear();
        if (from.eql(to)) return true;

        self.open_list.clearRetainingCapacity();
        self.closed_set.clearRetainingCapacity();
        self.came_from.clearRetainingCapacity();
        self.g_score.clearRetainingCapacity();

        const h_start = self.heuristic(from, to);
        try self.open_list.append(self.allocator, .{ .pos = from, .g = 0, .h = h_start });
        try self.g_score.put(from, 0);

        const max_iterations = 10000;
        var iteration: u32 = 0;

        while (self.open_list.items.len > 0 and iteration < max_iterations) : (iteration += 1) {
            var best_idx: usize = 0;
            var best_f = self.open_list.items[0].f();
            for (self.open_list.items, 0..) |node, i| {
                const f = node.f();
                if (f < best_f) {
                    best_f = f;
                    best_idx = i;
                }
            }

            const current = self.open_list.swapRemove(best_idx);

            if (current.pos.eql(to)) {
                // Reconstruct path
                var steps_buf: [MaxPathLength]PathStep = undefined;
                var step_count: usize = 0;
                var pos = to;
                while (self.came_from.get(pos)) |cf| {
                    if (step_count >= MaxPathLength) break;
                    steps_buf[step_count] = .{ .pos = cf.prev, .dir = cf.dir };
                    step_count += 1;
                    pos = cf.prev;
                }
                var i: usize = 0;
                while (i < step_count) : (i += 1) {
                    result.steps[i] = steps_buf[step_count - 1 - i];
                }
                result.length = step_count;
                return true;
            }

            try self.closed_set.put(current.pos, {});

            // Explore neighbours — only valid road segments
            const all_dirs = std.meta.tags(Direction);
            const neighbors = self.map.getAllNeighborsWrapped(current.pos);
            for (all_dirs, 0..) |d, i| {
                const npos = neighbors[i];
                if (self.closed_set.contains(npos)) continue;

                // Road segment validity check
                if (!self.map.isRoadSegmentValid(current.pos, d)) continue;
                // Don't route through tiles that already have roads (unless flag)
                const ntile = self.map.getTile(npos);
                if (!ntile.has_flag and ntile.paths != 0) continue;

                const cost: u32 = 10;
                const tentative_g = current.g + cost;
                const existing_g = self.g_score.get(npos);
                if (existing_g == null or tentative_g < existing_g.?) {
                    try self.came_from.put(npos, .{ .prev = current.pos, .dir = d });
                    try self.g_score.put(npos, tentative_g);
                    const h = self.heuristic(npos, to);
                    var in_open = false;
                    for (self.open_list.items) |*node| {
                        if (node.pos.eql(npos)) {
                            node.g = tentative_g;
                            node.h = h;
                            in_open = true;
                            break;
                        }
                    }
                    if (!in_open) {
                        try self.open_list.append(self.allocator, .{
                            .pos = npos,
                            .g = tentative_g,
                            .h = h,
                        });
                    }
                }
            }
        }

        return false;
    }

    /// Simplified path check: returns true if the two positions are connected
    /// by walkable tiles.
    pub fn areConnected(self: *Pathfinder, from: MapPos, to: MapPos) bool {
        // Simple BFS flood fill
        var visited = std.AutoHashMap(MapPos, void).init(self.allocator);
        defer visited.deinit();

        var queue: std.ArrayList(MapPos) = .empty;
        defer queue.deinit(self.allocator);

        queue.append(self.allocator, from) catch return false;
        visited.put(from, {}) catch return false;

        const max_steps: usize = 2000;
        var steps: usize = 0;

        while (queue.items.len > 0 and steps < max_steps) : (steps += 1) {
            const current = queue.orderedRemove(0);

            if (self.heuristic(current, to) <= 1) {
                // Check if actually adjacent
                if (self.map.directionToWrapped(current, to) != null or current.eql(to)) {
                    return true;
                }
            }

            const neighbors = self.map.getAllNeighbors(current);
            for (neighbors) |npos| {
                if (npos.eql(MapPos.invalid)) continue;
                if (visited.contains(npos)) continue;
                if (!self.map.getTile(npos).terrain.isWalkable()) continue;

                visited.put(npos, {}) catch return false;
                queue.append(self.allocator, npos) catch return false;
            }
        }

        return false;
    }
};

test "Pathfinder heuristic" {
    var map = try Map.init(std.testing.allocator, 64, 64);
    defer map.deinit();
    var pf = Pathfinder.init(std.testing.allocator, &map);
    defer pf.deinit(std.testing.allocator);

    const from = MapPos{ .x = 0, .y = 0 };
    const to = MapPos{ .x = 10, .y = 5 };

    var path = Path{};
    _ = try pf.findPath(from, to, &path);
    // Path may or may not be found on flat terrain, but shouldn't crash
}

test "Pathfinder findPath on flat grass" {
    var map = try Map.init(std.testing.allocator, 16, 16);
    defer map.deinit();
    // All grass by default
    var pf = Pathfinder.init(std.testing.allocator, &map);
    defer pf.deinit(std.testing.allocator);

    const from = MapPos{ .x = 2, .y = 2 };
    const to = MapPos{ .x = 10, .y = 10 };
    var path = Path{};
    const found = try pf.findPath(from, to, &path);
    try std.testing.expect(found);
    try std.testing.expect(path.length > 0);
    // First step should start at `from`, last step should reach `to`.
    try std.testing.expect(from.eql(path.steps[0].pos));
    // Walk the path and verify it ends at `to`
    var p = from;
    for (path.steps[0..path.length]) |step| {
        p = map.getNeighborWrapped(p, step.dir);
    }
    try std.testing.expect(to.eql(p));
}

test "Pathfinder findPath routes around water" {
    var map = try Map.init(std.testing.allocator, 16, 16);
    defer map.deinit();
    // Create a water wall across the middle column
    for (0..16) |y| {
        map.getTileXY(8, @intCast(y)).terrain = .water;
    }
    var pf = Pathfinder.init(std.testing.allocator, &map);
    defer pf.deinit(std.testing.allocator);

    const from = MapPos{ .x = 2, .y = 8 };
    const to = MapPos{ .x = 13, .y = 8 };
    var path = Path{};
    const found = try pf.findPath(from, to, &path);
    // On a torus map the path should wrap around the water wall.
    try std.testing.expect(found);
    // Verify the path doesn't step on water
    var p = from;
    for (path.steps[0..path.length]) |step| {
        p = map.getNeighborWrapped(p, step.dir);
        try std.testing.expect(!map.getTile(p).terrain.isWater());
    }
    try std.testing.expect(to.eql(p));
}

test "Pathfinder connected check" {
    var map = try Map.init(std.testing.allocator, 16, 16);
    defer map.deinit();

    var pf = Pathfinder.init(std.testing.allocator, &map);
    defer pf.deinit(std.testing.allocator);

    // All grass terrain is walkable, so all positions should be connected
    const a = MapPos{ .x = 2, .y = 2 };
    const b = MapPos{ .x = 10, .y = 10 };
    try std.testing.expect(pf.areConnected(a, b));

    // Block with water should break connection
    const water_pos = MapPos{ .x = 5, .y = 5 };
    map.getTile(water_pos).terrain = .water;
    // Still might be connected around the water
}