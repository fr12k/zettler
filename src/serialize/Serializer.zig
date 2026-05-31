//! Binary serializer — writes game state to a byte buffer.
//!
//! Port of the C# dirty-tracking serialization system.
//! In Zig we avoid runtime reflection and instead use explicit
//! serialize methods on each state struct.
//!
//! Uses a simple buffer-based approach compatible with Zig's new I/O API.

const std = @import("std");

/// Binary serializer that writes to a fixed buffer.
pub const Serializer = struct {
    /// Fixed-size buffer for serialization.
    buf: []u8,
    /// Current write position.
    pos: usize = 0,

    pub fn init(buffer: []u8) Serializer {
        return .{ .buf = buffer };
    }

    /// Get the number of bytes written so far.
    pub fn bytesWritten(self: Serializer) usize {
        return self.pos;
    }

    /// Get a slice of the written bytes.
    pub fn getWritten(self: *Serializer) []const u8 {
        return self.buf[0..self.pos];
    }

    /// Write a single byte.
    pub fn writeU8(self: *Serializer, value: u8) !void {
        if (self.pos >= self.buf.len) return error.OutOfMemory;
        self.buf[self.pos] = value;
        self.pos += 1;
    }

    /// Write a little-endian u16.
    pub fn writeU16(self: *Serializer, value: u16) !void {
        if (self.pos + 2 > self.buf.len) return error.OutOfMemory;
        std.mem.writeInt(u16, self.buf[self.pos..][0..2], value, .little);
        self.pos += 2;
    }

    /// Write a little-endian u32.
    pub fn writeU32(self: *Serializer, value: u32) !void {
        if (self.pos + 4 > self.buf.len) return error.OutOfMemory;
        std.mem.writeInt(u32, self.buf[self.pos..][0..4], value, .little);
        self.pos += 4;
    }

    /// Write a little-endian u64.
    pub fn writeU64(self: *Serializer, value: u64) !void {
        if (self.pos + 8 > self.buf.len) return error.OutOfMemory;
        std.mem.writeInt(u64, self.buf[self.pos..][0..8], value, .little);
        self.pos += 8;
    }

    /// Write a little-endian i32.
    pub fn writeI32(self: *Serializer, value: i32) !void {
        if (self.pos + 4 > self.buf.len) return error.OutOfMemory;
        std.mem.writeInt(i32, self.buf[self.pos..][0..4], value, .little);
        self.pos += 4;
    }

    /// Write a little-endian f32.
    pub fn writeF32(self: *Serializer, value: f32) !void {
        const bits: u32 = @bitCast(value);
        try self.writeU32(bits);
    }

    /// Write a boolean as a single byte (0 or 1).
    pub fn writeBool(self: *Serializer, value: bool) !void {
        try self.writeU8(if (value) @as(u8, 1) else 0);
    }

    /// Write a raw byte slice.
    pub fn writeBytes(self: *Serializer, bytes: []const u8) !void {
        if (self.pos + bytes.len > self.buf.len) return error.OutOfMemory;
        @memcpy(self.buf[self.pos..][0..bytes.len], bytes);
        self.pos += bytes.len;
    }

    /// Write a length-prefixed string (u32 length + UTF-8 bytes).
    pub fn writeString(self: *Serializer, string: []const u8) !void {
        try self.writeU32(@intCast(string.len));
        try self.writeBytes(string);
    }
};

test "Serializer write integers" {
    var buf: [256]u8 = undefined;
    var s = Serializer.init(&buf);

    try s.writeU8(0xAB);
    try s.writeU16(0x1234);
    try s.writeU32(0xDEADBEEF);
    try s.writeBool(true);
    try s.writeBool(false);

    try std.testing.expectEqual(@as(usize, 1 + 2 + 4 + 1 + 1), s.bytesWritten());

    // Verify bytes
    var pos: usize = 0;
    try std.testing.expectEqual(@as(u8, 0xAB), buf[pos]); pos += 1;
    try std.testing.expectEqual(@as(u16, 0x1234), std.mem.readInt(u16, buf[pos..][0..2], .little)); pos += 2;
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), std.mem.readInt(u32, buf[pos..][0..4], .little)); pos += 4;
    try std.testing.expectEqual(@as(u8, 1), buf[pos]); pos += 1;
    try std.testing.expectEqual(@as(u8, 0), buf[pos]);
}
