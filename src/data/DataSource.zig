//! Data source interface — abstraction for loading game assets.
//!
//! In the C# version there is an IDataSource interface for loading
//! game data from various sources (original game files, bundled data, etc.).
//! Here we provide a minimal data-source that will be fleshed out later.

const std = @import("std");

/// Game data constants — sizes from original Settlers assets.
pub const DataSizes = struct {
    pub const MapObjectWidth: u32 = 40;
    pub const MapObjectHeight: u32 = 40;
    pub const MapObjectCount: u32 = 256;

    pub const SpriteWidth: u32 = 32;
    pub const SpriteHeight: u32 = 32;
    pub const SpriteCount: u32 = 4096;

    pub const FontCharWidth: u32 = 10;
    pub const FontCharHeight: u32 = 14;
    pub const FontCharCount: u32 = 128;
};

/// Represents a single asset (sprite, sound, etc.).
pub const Asset = struct {
    data: []u8,
    width: u32,
    height: u32,

    pub fn deinit(self: *Asset, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

/// Data source that provides game assets.
/// In the future this will load from original game files or bundled data.
pub const DataSource = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DataSource {
        return .{ .allocator = allocator };
    }

    /// Load a sprite by its index.
    pub fn loadSprite(self: *DataSource, index: u16) !Asset {
        _ = index;
        // Placeholder: return an empty asset
        // In the future: load from SPAD/SPAE sprite files
        return .{
            .data = try self.allocator.alloc(u8, DataSizes.SpriteWidth * DataSizes.SpriteHeight),
            .width = DataSizes.SpriteWidth,
            .height = DataSizes.SpriteHeight,
        };
    }

    /// Load a map object sprite by its index.
    pub fn loadMapObject(self: *DataSource, index: u16) !Asset {
        _ = index;
        return .{
            .data = try self.allocator.alloc(u8, DataSizes.MapObjectWidth * DataSizes.MapObjectHeight),
            .width = DataSizes.MapObjectWidth,
            .height = DataSizes.MapObjectHeight,
        };
    }
};
