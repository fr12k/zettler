//! Road — a road under construction, porting freeserf's `Road` class
//! (map.h:36, map.cc:953).
//!
//! A road is just a source position + an ordered list of direction steps.
//! Each step extends the road by one segment in that direction. The opposite
//! of the last step is an undo (backspace). Self-crossing is rejected.

const std = @import("std");
const enums = @import("enums.zig");
const types = @import("types.zig");
const map_mod = @import("Map.zig");

const Direction = enums.Direction;
const MapPos = types.MapPos;
const Map = map_mod.Map;

/// Maximum number of segments in a single road (matches freeserf).
pub const max_length: usize = 256;

/// A road under construction: a start position + an ordered list of
/// direction segments.
pub const Road = struct {
    begin: MapPos = MapPos.invalid,
    /// The direction steps, in order from `begin`.
    dirs: [max_length]Direction = @splat(.right),
    len: usize = 0,

    /// True if the road has a valid start position.
    pub fn isValid(self: Road) bool {
        return !self.begin.eql(MapPos.invalid);
    }

    /// Start a new road at position `s`.
    pub fn start(self: *Road, s: MapPos) void {
        self.begin = s;
        self.len = 0;
    }

    /// Clear the road (reset to invalid).
    pub fn clear(self: *Road) void {
        self.begin = MapPos.invalid;
        self.len = 0;
    }

    /// Append a direction step. Returns false if the road is full.
    pub fn extend(self: *Road, d: Direction) bool {
        if (self.len >= max_length) return false;
        self.dirs[self.len] = d;
        self.len += 1;
        return true;
    }

    /// Remove the last segment (undo / backspace). Returns false if empty.
    pub fn undo(self: *Road) bool {
        if (self.len == 0) return false;
        self.len -= 1;
        return true;
    }

    /// True if direction `d` would undo the last segment (i.e. `d` is the
    /// opposite of the last step). Returns false if the road is empty.
    pub fn isUndo(self: Road, d: Direction) bool {
        if (self.len == 0) return false;
        return self.dirs[self.len - 1] == d.opposite();
    }

    /// The end position of the road (walk all dirs from `begin` with wrapping).
    pub fn getEnd(self: Road, map: Map) MapPos {
        var pos = self.begin;
        for (self.dirs[0..self.len]) |d| {
            pos = map.getNeighborWrapped(pos, d);
        }
        return pos;
    }

    /// True if `pos` is already on the road (including `begin`), used to
    /// reject self-crossing extensions.
    pub fn hasPos(self: Road, map: Map, pos: MapPos) bool {
        if (self.begin.eql(pos)) return true;
        var p = self.begin;
        for (self.dirs[0..self.len]) |d| {
            p = map.getNeighborWrapped(p, d);
            if (p.eql(pos)) return true;
        }
        return false;
    }

    /// True if extending in direction `d` would not self-cross — i.e. the
    /// new end tile is not already on the road (excluding the current end,
    /// which would be an undo).
    pub fn isValidExtension(self: Road, map: Map, d: Direction) bool {
        if (self.isUndo(d)) return true; // undo is always valid
        const new_end = map.getNeighborWrapped(self.getEnd(map), d);
        // The new end must not already be on the road.
        return !self.hasPos(map, new_end);
    }

    /// Return the direction steps as a slice.
    pub fn dirsSlice(self: Road) []const Direction {
        return self.dirs[0..self.len];
    }
};

test "Road basic operations" {
    var map = try Map.init(std.testing.allocator, 64, 64);
    defer map.deinit();

    var road = Road{};
    try std.testing.expect(!road.isValid());

    road.start(.{ .x = 10, .y = 10 });
    try std.testing.expect(road.isValid());
    try std.testing.expectEqual(@as(usize, 0), road.len);

    try std.testing.expect(road.extend(.right));
    try std.testing.expect(road.extend(.right));
    try std.testing.expect(road.extend(.down));
    try std.testing.expectEqual(@as(usize, 3), road.len);

    // End should be at (12, 11).
    const end = road.getEnd(map);
    try std.testing.expectEqual(@as(u16, 12), end.x);
    try std.testing.expectEqual(@as(u16, 11), end.y);

    // Undo removes the last segment.
    try std.testing.expect(road.undo());
    try std.testing.expectEqual(@as(usize, 2), road.len);
    const end2 = road.getEnd(map);
    try std.testing.expectEqual(@as(u16, 12), end2.x);
    try std.testing.expectEqual(@as(u16, 10), end2.y);

    // isUndo: left is opposite of right (last segment).
    try std.testing.expect(road.isUndo(.left));
    try std.testing.expect(!road.isUndo(.down));
}

test "Road self-crossing detection" {
    var map = try Map.init(std.testing.allocator, 64, 64);
    defer map.deinit();

    var road = Road{};
    road.start(.{ .x = 10, .y = 10 });
    // Build a loop: right, down, left, up would return to start.
    _ = road.extend(.right);
    _ = road.extend(.down);
    _ = road.extend(.left);
    // Now the end is at (10, 11). Extending up would go to (10, 10) = begin.
    try std.testing.expect(!road.isValidExtension(map, .up));
    // Extending down (not crossing) is fine.
    try std.testing.expect(road.isValidExtension(map, .down));
}

test "Road undo on empty" {
    var road = Road{};
    road.start(.{ .x = 5, .y = 5 });
    try std.testing.expect(!road.undo());
    try std.testing.expect(!road.isUndo(.right));
}