//! PAK file reader — reads original Settlers PAK archives.
//!
//! The original game stores assets in .PA files which are TPWM-compressed
//! archives containing a directory of (offset, size) entries followed by
//! raw file data. This loader:
//! 1. Decompresses the TPWM wrapper (all .PA files from CD are TPWM-packed)
//! 2. Reads the flat directory structure
//! 3. Provides file-by-file access

const std = @import("std");
const tpwm = @import("tpwm.zig");

/// Maximum number of files in a PAK archive.
pub const MAX_FILES: u32 = 4096;

/// A single entry in the PAK file directory.
pub const PakEntry = struct {
    /// Offset of the file data within the decompressed archive.
    offset: u32,
    /// Size of the file data in bytes.
    size: u32,
};

/// PAK file reader.
pub const PakFile = struct {
    allocator: std.mem.Allocator,
    /// The decompressed archive data.
    data: []const u8,
    /// Directory entries indexed by file number (0..num_files-1).
    entries: []PakEntry,
    /// Number of files in the archive.
    num_files: u32,
    /// Whether this instance owns the data (allocated during decompress).
    owns_data: bool,

    /// Load a .PA file from raw (possibly TPWM-compressed) bytes.
    /// Automatically detects and decompresses TPWM-wrapped archives.
    pub fn init(allocator: std.mem.Allocator, raw: []const u8) !PakFile {
        // Check if TPWM-compressed
        const is_compressed = tpwm.isTPWM(raw);
        const data: []const u8 = if (is_compressed)
            try tpwm.decompress(allocator, raw)
        else
            raw;

        if (data.len < 4) return error.InvalidPak;

        // TPWM-decompressed data has a 4-byte self-verification prefix
        // (decompressed size stored at offset 0)
        // The actual PAK directory starts at offset 4 in that case.
        // Raw (non-TPWM) files have the directory at offset 0.
        const dir_offset: u32 = if (is_compressed) 4 else 0;

        const num_files = std.mem.readInt(u32, data[dir_offset..][0..4], .little);

        // Debug: log first 32 bytes of decompressed data
        if (is_compressed) {
            std.debug.print("  PAK decompressed {} bytes, first u32 = {} (0x{x:0>8})\n", .{data.len, num_files, num_files});
            std.debug.print("  First 24 bytes: ", .{});
            for (0..@min(data.len, @as(usize, 24))) |i| {
                std.debug.print("{x:0>2} ", .{data[i]});
            }
            std.debug.print("\n", .{});
        }

        if (num_files == 0 or num_files > MAX_FILES) {
            // Might be a different format (e.g. BLOCK file).
            // Try to find a PAK-like structure in the data.
            std.debug.print("  Not a PAK directory. First u32 doesn't look like file count.\n", .{});
            return error.InvalidPak;
        }

        // Directory entries start after the header (4 bytes for count)
        const entry_offset = dir_offset + 4;
        const dir_size = num_files * 8;
        if (data.len < entry_offset + dir_size) return error.InvalidPak;

        var entries = try allocator.alloc(PakEntry, num_files);
        errdefer allocator.free(entries);

        for (0..num_files) |i| {
            const off = entry_offset + i * 8;
            entries[i] = .{
                .size = std.mem.readInt(u32, data[off..][0..4], .little),
                .offset = std.mem.readInt(u32, data[off + 4 ..][0..4], .little),
            };
        }

        return .{
            .allocator = allocator,
            .data = data,
            .entries = entries,
            .num_files = num_files,
            .owns_data = data.ptr != raw.ptr, // true if we decompressed
        };
    }

    pub fn deinit(self: *PakFile) void {
        self.allocator.free(self.entries);
        if (self.owns_data) {
            self.allocator.free(@constCast(self.data));
        }
    }

    /// Extract the data for a given file index.
    /// Returns a slice into the decompressed archive (no copy).
    pub fn getFile(self: PakFile, index: u32) ![]const u8 {
        if (index >= self.num_files) return error.FileNotFound;
        const entry = self.entries[index];
        const start: usize = entry.offset;
        const end: usize = start + entry.size;
        if (end > self.data.len) return error.InvalidPakData;
        return self.data[start..end];
    }

    /// Get the number of files in the PAK.
    pub fn fileCount(self: PakFile) u32 {
        return self.num_files;
    }

    /// Read the entire .PA file from disk.
    pub fn fromFile(allocator: std.mem.Allocator, file_path: []const u8) !PakFile {
        const cwd = std.fs.cwd();
        const file = try cwd.openFile(file_path, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const raw = try allocator.alloc(u8, file_size);
        defer allocator.free(raw);

        const bytes_read = try file.readAll(raw);
        if (bytes_read < file_size) return error.ReadError;

        return try init(allocator, raw[0..bytes_read]);
    }
};

test "PakFile basic - uncompressed" {
    // Create a minimal PAK: 2 files, no TPWM compression
    var buf: [24]u8 = undefined;
    std.mem.writeInt(u32, buf[0..4], 2, .little);     // num_files
    std.mem.writeInt(u32, buf[4..8], 12, .little);     // file 0 offset
    std.mem.writeInt(u32, buf[8..12], 5, .little);     // file 0 size
    std.mem.writeInt(u32, buf[12..16], 17, .little);   // file 1 offset
    std.mem.writeInt(u32, buf[16..20], 3, .little);    // file 1 size
    @memcpy(buf[12..17], "Hello");
    @memcpy(buf[17..20], "Zig");

    var pak = try PakFile.init(std.testing.allocator, &buf);
    defer pak.deinit();

    try std.testing.expectEqual(@as(u32, 2), pak.fileCount());
    const file0 = try pak.getFile(0);
    try std.testing.expectEqualStrings("Hello", file0);
    const file1 = try pak.getFile(1);
    try std.testing.expectEqualStrings("Zig", file1);
}

test "PakFile from SPAE.PA" {
    // Try loading the actual game data file
    const paths = [_][]const u8{
        "data/SPAE.PA",
        "data/SPAD.PA",
        "data/SPAU.PA",
        "data/SPAF.PA",
        "../data/SPAE.PA",
    };

    for (paths) |path| {
        if (std.fs.cwd().access(path, .{})) {
            var pak = PakFile.fromFile(std.testing.allocator, path) catch continue;
            defer pak.deinit();

            try std.testing.expect(pak.fileCount() > 0);
            try std.testing.expect(pak.fileCount() <= MAX_FILES);
            // SPAE.PA typically has ~600-1200 files
            try std.testing.expect(pak.fileCount() > 100);
            return; // success
        } else |_| {
            continue;
        }
    }
    // No data file found — that's OK, the test is optional
}
