//! Data module — re-exports all data types.

pub const DataSource = @import("DataSource.zig").DataSource;
pub const Asset = @import("DataSource.zig").Asset;
pub const DataSizes = @import("DataSource.zig").DataSizes;
pub const pak = @import("pak.zig");
pub const bmp = @import("bmp.zig");
pub const font = @import("font.zig");
pub const asset_manager = @import("asset_manager.zig");
pub const tpwm = @import("tpwm.zig");

pub const sprite_ids = @import("sprite_ids.zig");

pub const PakFile = pak.PakFile;
pub const Sprite = bmp.Sprite;
pub const ColorRGBA = bmp.ColorRGBA;
pub const BmpDecoder = bmp.BmpDecoder;
pub const BitmapFont = font.BitmapFont;
pub const AssetManager = asset_manager.AssetManager;
pub const Tpwm = tpwm;
