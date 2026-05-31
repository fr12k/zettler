//! Savegame — save/load game state using buffer serialization.
//!
//! In the C# version, savegames use the dirty-tracking serialization
//! framework. In Zig we use explicit serializers with a buffer-based
//! approach for now. File I/O will be added when the full save/load
//! system is implemented in Phase 2.

const std = @import("std");
const Serializer = @import("Serializer.zig").Serializer;
const Deserializer = @import("Deserializer.zig").Deserializer;

/// Header written at the start of every save buffer.
pub const SaveHeader = struct {
    magic: [8]u8 = "FRFSRF".* ++ [_]u8{ 0x0D, 0x0A },
    version: u32 = 1,
};

/// Maximum save buffer size.
pub const MaxSaveSize = 1024 * 1024; // 1 MB

/// Savegame reader/writer.
pub const Savegame = struct {
    header: SaveHeader = .{},

    /// Serialize game state into a buffer.
    /// Returns a slice of the written bytes from the internal buffer.
    pub fn serialize(self: *const Savegame, writeFn: anytype, buf: []u8) ![]const u8 {
        var s = Serializer.init(buf);

        // Write header
        try s.writeBytes(&self.header.magic);
        try s.writeU32(self.header.version);

        // Write state via callback
        try writeFn(&s);

        return s.getWritten();
    }

    /// Deserialize game state from a buffer.
    pub fn deserialize(data: []const u8, readFn: anytype) !void {
        var d = Deserializer.init(data);

        // Read and validate header
        var magic: [8]u8 = undefined;
        try d.readBytes(&magic);
        const expected_magic = "FRFSRF".* ++ [_]u8{ 0x0D, 0x0A };
        if (!std.mem.eql(u8, &magic, &expected_magic)) {
            return error.InvalidSaveFile;
        }

        const version = try d.readU32();
        _ = version; // Future: version migration

        // Read state via callback
        try readFn(&d);
    }

    /// Save state to a file using the OS file API.
    /// `io` is the process I/O handle, `writeFn` receives a Serializer.
    pub fn saveToFile(io: std.Io, file_path: []const u8, writeFn: anytype, allocator: std.mem.Allocator) !void {
        var buf: [MaxSaveSize]u8 = undefined;
        var s = Serializer.init(&buf);

        const header = SaveHeader{};
        try s.writeBytes(&header.magic);
        try s.writeU32(header.version);
        try writeFn(&s);

        const written = s.getWritten();
        const dir = try io.vtable.cwd(io.userdata);
        const file = try std.Io.File.create(dir, file_path, .{});
        defer std.Io.File.close(file, io);

        try std.Io.File.writeStreamingAll(file, io, written);
        _ = allocator;
    }
};

test "Savegame serialize/deserialize round-trip" {
    var buf: [MaxSaveSize]u8 = undefined;

    // Serialize
    var sg = Savegame{};
    const written = try sg.serialize(struct {
        fn write(s: *Serializer) !void {
            try s.writeU32(42);
            try s.writeString("hello");
        }
    }.write, &buf);

    // Deserialize and verify
    try Savegame.deserialize(written, struct {
        fn read(d: *Deserializer) !void {
            const allocator = std.testing.allocator;
            const val = try d.readU32();
            const str = try d.readString(allocator);
            defer allocator.free(str);
            try std.testing.expectEqual(@as(u32, 42), val);
            try std.testing.expectEqualStrings("hello", str);
        }
    }.read);
}
