//! Dirty-tracking state base.
//!
//! In the C# version, State is an abstract class with MarkPropertyAsDirty()
//! and a DirtyProperties list. In Zig we use a struct with a dirty bitset
//! and manual `markDirty()` calls in setter functions.

const std = @import("std");

/// A fixed-size bitset for tracking which fields of a state struct
/// have been modified since the last serialization.
pub const DirtyFlags = struct {
    bits: u64 = 0,

    /// Mark a field as dirty by its index.
    pub fn mark(self: *DirtyFlags, field_index: u6) void {
        self.bits |= @as(u64, 1) << @intCast(field_index);
    }

    /// Check if a field is dirty.
    pub fn isDirty(self: DirtyFlags, field_index: u6) bool {
        return (self.bits >> @intCast(field_index)) & 1 == 1;
    }

    /// Clear all dirty bits.
    pub fn clear(self: *DirtyFlags) void {
        self.bits = 0;
    }

    /// Return true if any field is dirty.
    pub fn any(self: DirtyFlags) bool {
        return self.bits != 0;
    }

    /// Return the number of dirty fields.
    pub fn count(self: DirtyFlags) u6 {
        return @truncate(@popCount(self.bits));
    }
};

/// Base state type that provides dirty-tracking.
/// State structs should embed this and call markDirty() in their setter functions.
pub const State = struct {
    dirty: DirtyFlags = .{},

    pub fn markDirty(self: *State, field_index: u6) void {
        self.dirty.mark(field_index);
    }

    pub fn clearDirty(self: *State) void {
        self.dirty.clear();
    }

    pub fn isDirty(self: State, field_index: u6) bool {
        return self.dirty.isDirty(field_index);
    }
};

test "DirtyFlags basic operations" {
    var flags = DirtyFlags{};
    try std.testing.expect(!flags.any());
    try std.testing.expectEqual(@as(u6, 0), flags.count());

    flags.mark(3);
    try std.testing.expect(flags.any());
    try std.testing.expect(flags.isDirty(3));
    try std.testing.expect(!flags.isDirty(0));
    try std.testing.expect(!flags.isDirty(7));
    try std.testing.expectEqual(@as(u6, 1), flags.count());

    flags.mark(0);
    try std.testing.expect(flags.isDirty(0));
    try std.testing.expectEqual(@as(u6, 2), flags.count());

    flags.clear();
    try std.testing.expect(!flags.any());
    try std.testing.expectEqual(@as(u6, 0), flags.count());
}

test "State markDirty" {
    var s = State{};
    s.markDirty(5);
    try std.testing.expect(s.isDirty(5));
    s.clearDirty();
    try std.testing.expect(!s.isDirty(5));
}
