//! Binary deserializer — reads game state from a byte buffer.
//!
//! Counterpart to Serializer.zig. Reads back data written by the
//! serializer in little-endian format.

const std = @import("std");

/// Binary deserializer that reads from a byte buffer.
pub const Deserializer = struct {
    /// Buffer to read from.
    buf: []const u8,
    /// Current read position.
    pos: usize = 0,

    pub fn init(buffer: []const u8) Deserializer {
        return .{ .buf = buffer };
    }

    /// Number of bytes read so far.
    pub fn bytesRead(self: Deserializer) usize {
        return self.pos;
    }

    /// Number of bytes remaining.
    pub fn remaining(self: Deserializer) usize {
        return self.buf.len - self.pos;
    }

    /// Read a single byte.
    pub fn readU8(self: *Deserializer) !u8 {
        if (self.pos >= self.buf.len) return error.EndOfStream;
        const value = self.buf[self.pos];
        self.pos += 1;
        return value;
    }

    /// Read a little-endian u16.
    pub fn readU16(self: *Deserializer) !u16 {
        if (self.pos + 2 > self.buf.len) return error.EndOfStream;
        const value = std.mem.readInt(u16, self.buf[self.pos..][0..2], .little);
        self.pos += 2;
        return value;
    }

    /// Read a little-endian u32.
    pub fn readU32(self: *Deserializer) !u32 {
        if (self.pos + 4 > self.buf.len) return error.EndOfStream;
        const value = std.mem.readInt(u32, self.buf[self.pos..][0..4], .little);
        self.pos += 4;
        return value;
    }

    /// Read a little-endian u64.
    pub fn readU64(self: *Deserializer) !u64 {
        if (self.pos + 8 > self.buf.len) return error.EndOfStream;
        const value = std.mem.readInt(u64, self.buf[self.pos..][0..8], .little);
        self.pos += 8;
        return value;
    }

    /// Read a little-endian i32.
    pub fn readI32(self: *Deserializer) !i32 {
        if (self.pos + 4 > self.buf.len) return error.EndOfStream;
        const value = std.mem.readInt(i32, self.buf[self.pos..][0..4], .little);
        self.pos += 4;
        return value;
    }

    /// Read a little-endian f32.
    pub fn readF32(self: *Deserializer) !f32 {
        const bits = try self.readU32();
        return @bitCast(bits);
    }

    /// Read a boolean (0 = false, nonzero = true).
    pub fn readBool(self: *Deserializer) !bool {
        const byte = try self.readU8();
        return byte != 0;
    }

    /// Read a raw byte slice.
    pub fn readBytes(self: *Deserializer, buffer: []u8) !void {
        if (self.pos + buffer.len > self.buf.len) return error.EndOfStream;
        @memcpy(buffer, self.buf[self.pos..][0..buffer.len]);
        self.pos += buffer.len;
    }

    /// Read a length-prefixed string (u32 length + UTF-8 bytes).
    /// Caller owns the returned memory (allocated with the provided allocator).
    pub fn readString(self: *Deserializer, allocator: std.mem.Allocator) ![]u8 {
        const len = try self.readU32();
        const string = try allocator.alloc(u8, len);
        errdefer allocator.free(string);
        try self.readBytes(string);
        return string;
    }
};

test "Deserializer round-trip" {
    var buf: [256]u8 = undefined;
    var s = @import("Serializer.zig").Serializer.init(&buf);

    try s.writeU8(0xAB);
    try s.writeU16(0x1234);
    try s.writeU32(0xDEADBEEF);
    try s.writeF32(3.1415);
    try s.writeBool(true);

    const written = s.getWritten();
    var d = Deserializer.init(written);

    try std.testing.expectEqual(@as(u8, 0xAB), try d.readU8());
    try std.testing.expectEqual(@as(u16, 0x1234), try d.readU16());
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), try d.readU32());

    const pi = try d.readF32();
    try std.testing.expectApproxEqAbs(3.1415, pi, 0.0001);

    try std.testing.expectEqual(true, try d.readBool());
}
