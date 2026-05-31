//! Asset manager — loads and caches game assets.
//!
//! Provides a unified interface for loading sprites, sounds, and
//! other game data from PAK archives or bundled data files.
//!
//! Port of the C# AssetManager from Freeserf.

const std = @import("std");
const pak = @import("pak.zig");
const bmp = @import("bmp.zig");
const font = @import("font.zig");

const PakFile = pak.PakFile;
const Sprite = bmp.Sprite;
const BitmapFont = font.BitmapFont;

/// Maximum number of cached sprites.
pub const MAX_CACHED_SPRITES: usize = 4096;

/// Asset manager — main entry point for loading game data.
pub const AssetManager = struct {
    allocator: std.mem.Allocator,
    /// The main PAK archive containing game data.
    pak_file: ?PakFile = null,
    /// Sprite decoder.
    decoder: bmp.BmpDecoder,
    /// Bitmap font.
    font: font.BitmapFont,
    /// Cached sprites (indexed by sprite ID).
    sprites: std.AutoHashMap(u16, Sprite),

    pub fn init(allocator: std.mem.Allocator) AssetManager {
        return .{
            .allocator = allocator,
            .decoder = bmp.BmpDecoder.init(allocator),
            .font = font.BitmapFont.init(allocator),
            .sprites = std.AutoHashMap(u16, Sprite).init(allocator),
        };
    }

    pub fn deinit(self: *AssetManager) void {
        // Free cached sprites
        var it = self.sprites.iterator();
        while (it.next()) |entry| {
            const sprite = entry.value_ptr;
            self.allocator.free(sprite.pixels);
        }
        self.sprites.deinit();
        self.font.deinit();

        if (self.pak_file) |*pf| {
            pf.deinit();
        }
    }

    /// Load a PAK file from raw data.
    pub fn loadPak(self: *AssetManager, data: []const u8) !void {
        if (self.pak_file) |*pf| {
            pf.deinit();
        }
        self.pak_file = try PakFile.init(self.allocator, data);
    }

    /// Load a sprite from the PAK by its file index.
    /// Caches the sprite for subsequent calls.
    pub fn loadSprite(self: *AssetManager, sprite_id: u16) !*Sprite {
        // Check cache first
        if (self.sprites.getPtr(sprite_id)) |cached| {
            return cached;
        }

        const pak_file = self.pak_file orelse return error.NoPakLoaded;
        const raw_data = try pak_file.getFile(sprite_id);
        const sprite = try self.decoder.decode(raw_data);

        // Store in cache
        try self.sprites.put(sprite_id, sprite);
        return self.sprites.getPtr(sprite_id).?;
    }

    /// Check if a sprite is already cached.
    pub fn isCached(self: AssetManager, sprite_id: u16) bool {
        return self.sprites.contains(sprite_id);
    }

    /// Get the number of cached sprites.
    pub fn cachedCount(self: AssetManager) usize {
        return self.sprites.count();
    }
};

test "AssetManager init" {
    var am = AssetManager.init(std.testing.allocator);
    defer am.deinit();

    try std.testing.expectEqual(@as(usize, 0), am.cachedCount());
}
