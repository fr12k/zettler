//! RoadBuilder — handles road construction between flags.
//!
//! The player clicks a flag to start, then either clicks another flag to
//! auto-pathfind a road, or builds segment-by-segment. Roads enable serf
//! transport of resources along the flag network.
//!
//! Uses the `Road` struct (src/core/Road.zig) for the under-construction
//! road state. The preview path is still found via a greedy walker for now
//! (the A* Pathfinder path reconstruction is broken — see Phase 2).

const std = @import("std");
const core = @import("core");

const Map = core.map.Map;
const Direction = core.Direction;
const MapPos = core.types.MapPos;
const Road = core.road.Road;

/// Greedy chebyshev-style distance, matching Pathfinder.heuristic.
fn hexDist(a: MapPos, b: MapPos) i32 {
    const dx = @as(i32, a.x) - @as(i32, b.x);
    const dy = @as(i32, a.y) - @as(i32, b.y);
    return @intCast(@max(@abs(dx), @abs(dy)));
}

/// Pick the step direction from `from` that gets closest to `to`, skipping
/// water and buildings. Uses WRAPPING so roads can be built across map edges.
fn bestStep(from: MapPos, to: MapPos, map: *Map) ?Direction {
    var best_dir: ?Direction = null;
    var best_d: i32 = std.math.maxInt(i32);
    inline for (std.meta.tags(Direction)) |d| {
        const np = map.getNeighborWrapped(from, d);
        if (np.eql(to)) return d;
        const t = map.getTile(np);
        if (!t.has_building and !t.terrain.isWater()) {
            const dd = hexDist(np, to);
            if (dd < best_d) {
                best_d = dd;
                best_dir = d;
            }
        }
    }
    return best_dir;
}

/// Road building tool state.
pub const RoadBuilder = struct {
    /// Whether road building mode is active.
    active: bool = false,
    /// The first flag selected (start of road).
    start_flag_pos: MapPos = .{ .x = 0, .y = 0 },
    /// Whether the first flag has been selected.
    has_start: bool = false,
    /// The current cursor position (for preview).
    cursor_pos: MapPos = .{ .x = 0, .y = 0 },
    /// The calculated path (direction steps as u8) from start to cursor.
    /// Kept for backward compatibility with app.zig which passes it to
    /// Game.buildRoad. The authoritative state is in `road`.
    path: [128]u8 = undefined,
    path_len: usize = 0,
    /// Whether a valid road path exists.
    has_path: bool = false,

    /// The under-construction road (authoritative state).
    road: Road = .{},

    pub fn init() RoadBuilder {
        return RoadBuilder{};
    }

    pub fn activate(self: *RoadBuilder) void {
        self.active = true;
        self.has_start = false;
        self.path_len = 0;
        self.has_path = false;
        self.road.clear();
    }

    pub fn deactivate(self: *RoadBuilder) void {
        self.active = false;
        self.has_start = false;
        self.path_len = 0;
        self.has_path = false;
        self.road.clear();
    }

    /// Try to start a road from a flag at the given map position.
    /// Returns true if a flag was found there.
    pub fn tryStartAt(self: *RoadBuilder, pos: MapPos, map: *Map) bool {
        if (!self.active) return false;
        if (!map.getTile(pos).has_flag) return false;
        self.start_flag_pos = pos;
        self.has_start = true;
        self.path_len = 0;
        self.has_path = false;
        self.road.start(pos);
        return true;
    }

    /// Update the path preview from the start flag to the cursor tile.
    /// Uses a greedy walker (to be replaced by A* in Phase 2).
    pub fn updatePath(self: *RoadBuilder, cursor_pos: MapPos, map: *Map) void {
        if (!self.active or !self.has_start) return;
        self.cursor_pos = cursor_pos;
        self.path_len = 0;
        self.has_path = false;
        self.road.clear();
        self.road.start(self.start_flag_pos);
        if (cursor_pos.eql(self.start_flag_pos)) return;

        var p = self.start_flag_pos;
        var steps: usize = 0;
        while (steps < self.path.len) {
            if (p.eql(cursor_pos)) {
                self.path_len = steps;
                self.has_path = steps > 0;
                // Sync the road struct with the found path.
                self.road.clear();
                self.road.start(self.start_flag_pos);
                for (self.path[0..steps]) |d| {
                    _ = self.road.extend(@enumFromInt(d));
                }
                return;
            }
            const d = bestStep(p, cursor_pos, map) orelse return;
            self.path[steps] = @intFromEnum(d);
            p = map.wrapPos(p.move(d));
            steps += 1;
        }
    }

    /// Try to extend the road by one segment in the given direction.
    /// Returns true if the segment was added (valid + no self-crossing).
    pub fn extendSegment(self: *RoadBuilder, dir: Direction, map: *Map) bool {
        if (!self.active or !self.has_start) return false;
        // Undo: if the direction is opposite to the last segment, remove it.
        if (self.road.isUndo(dir)) {
            return self.road.undo();
        }
        // Check segment validity + no self-crossing.
        if (!map.isRoadSegmentValid(self.road.getEnd(map.*), dir)) return false;
        if (!self.road.isValidExtension(map.*, dir)) return false;
        return self.road.extend(dir);
    }

    /// Remove the last segment (undo / backspace). Returns false if empty.
    pub fn undoSegment(self: *RoadBuilder) bool {
        if (!self.active or !self.has_start) return false;
        return self.road.undo();
    }

    /// Compute a 6-bit mask of valid extension directions from the road's
    /// current end. Bit i is set if direction i is a valid next segment
    /// (isRoadSegmentValid + isValidExtension). Ports freeserf's
    /// `determine_map_cursor_type_road` (interface.cc:331).
    pub fn validDirMask(self: RoadBuilder, map: Map) u6 {
        if (!self.active or !self.has_start) return 0;
        const end = self.road.getEnd(map);
        var mask: u6 = 0;
        inline for (std.meta.tags(Direction)) |d| {
            if (map.isRoadSegmentValid(end, d) and self.road.isValidExtension(map, d)) {
                mask |= @as(u6, 1) << @intCast(@intFromEnum(d));
            }
        }
        return mask;
    }

    /// Cancel road building.
    pub fn cancel(self: *RoadBuilder) void {
        self.deactivate();
    }
};