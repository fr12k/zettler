//! Settlers 1 DOS sprite decoder.
//!
//! Sprites are stored in PAK archives (SPAE.PA, SPAD.PA, etc.).
//! Each sprite entry has a 10-byte header followed by pixel data.
//!
//! Header layout (10 bytes):
//!   s8  delta_x   -- draw offset x (often encodes palette index)
//!   s8  delta_y   -- draw offset y
//!   u16 width     -- sprite width in pixels
//!   u16 height    -- sprite height in pixels
//!   s16 offset_x  -- hotspot x offset
//!   s16 offset_y  -- hotspot y offset
//!
//! Two pixel-data encodings:
//!   Solid:       data.len == 10 + width*height  → raw palette indices, row-major
//!   Transparent: otherwise                       → RLE pairs (drop, fill, pixels[fill])

const std = @import("std");

/// A single pixel in 32-bit RGBA format.
/// Memory order: R, G, B, A (matches OpenGL GL_RGBA, GL_UNSIGNED_BYTE).
pub const ColorRGBA = packed struct(u32) {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

/// A decoded sprite.
pub const Sprite = struct {
    width: u32,
    height: u32,
    delta_x: i8,
    delta_y: i8,
    offset_x: i16,
    offset_y: i16,
    /// RGBA pixels, row-major (top-to-bottom, left-to-right).
    pixels: []ColorRGBA,

    pub fn deinit(self: *Sprite, allocator: std.mem.Allocator) void {
        allocator.free(self.pixels);
    }

    pub fn getPixel(self: Sprite, x: u32, y: u32) ColorRGBA {
        return self.pixels[y * self.width + x];
    }
};

/// Palette: 256 RGBA entries.
pub const Palette = [256]ColorRGBA;

/// Build a grayscale fallback palette (index i → gray value i, index 0 = transparent).
pub fn defaultPalette() Palette {
    var pal: Palette = undefined;
    for (0..256) |i| {
        const v: u8 = @intCast(i);
        pal[i] = .{ .r = v, .g = v, .b = v, .a = 255 };
    }
    pal[0].a = 0;
    return pal;
}

/// Parse a decompressed PAL file (4-byte size prefix + 256 × 3-byte VGA RGB entries).
/// VGA values are 0-63; multiply by 4 to get 0-252 range.
pub fn parsePalette(data: []const u8) ?Palette {
    // PAL files are 768 bytes plain (256 × 3-byte VGA RGB).
    // No 4-byte size prefix.
    const start: usize = 0;
    if (data.len < start + 768) return null;

    var pal: Palette = undefined;
    for (0..256) |i| {
        const off = start + i * 3;
        const r = data[off];
        const g = data[off + 1];
        const b = data[off + 2];
        pal[i] = .{
            // VGA palette values are 6-bit (0-63); scale to 8-bit
            .r = @as(u8, @min(r *% 4, 255)),
            .g = @as(u8, @min(g *% 4, 255)),
            .b = @as(u8, @min(b *% 4, 255)),
            .a = 255,
        };
    }
    pal[0].a = 0; // index 0 = transparent
    return pal;
}

/// Sprite decoder.
pub const BmpDecoder = struct {
    allocator: std.mem.Allocator,
    palette: Palette,

    pub fn init(allocator: std.mem.Allocator) BmpDecoder {
        return .{ .allocator = allocator, .palette = defaultPalette() };
    }

    pub fn setPalette(self: *BmpDecoder, pal: Palette) void {
        self.palette = pal;
    }

    /// Decode a single sprite from raw PAK entry data.
    pub fn decode(self: *BmpDecoder, data: []const u8) !Sprite {
        if (data.len < 10) return error.InvalidSprite;

        const delta_x: i8 = @bitCast(data[0]);
        const delta_y: i8 = @bitCast(data[1]);
        const width: u32 = std.mem.readInt(u16, data[2..4], .little);
        const height: u32 = std.mem.readInt(u16, data[4..6], .little);
        const offset_x: i16 = std.mem.readInt(i16, data[6..8], .little);
        const offset_y: i16 = std.mem.readInt(i16, data[8..10], .little);

        if (width == 0 or height == 0) return error.InvalidSpriteSize;
        if (width > 2048 or height > 2048) return error.InvalidSpriteSize;

        const pixel_count = width * height;
        const pixels = try self.allocator.alloc(ColorRGBA, pixel_count);
        errdefer self.allocator.free(pixels);
        @memset(pixels, ColorRGBA{ .r = 0, .g = 0, .b = 0, .a = 0 });

        const raw = data[10..];

        if (raw.len == pixel_count) {
            // Solid sprite: raw palette indices, row-major
            for (pixels, raw) |*px, idx| {
                px.* = self.palette[idx];
            }
        } else {
            // Transparent sprite: RLE (drop, fill, pixels[fill]) pairs
            var pos: usize = 0; // current pixel index (row-major)
            var i: usize = 0; // raw data index
            while (i + 1 < raw.len and pos < pixel_count) {
                const drop = raw[i];
                const fill = raw[i + 1];
                i += 2;
                pos += drop; // transparent pixels
                for (0..fill) |_| {
                    if (pos >= pixel_count or i >= raw.len) break;
                    pixels[pos] = self.palette[raw[i]];
                    pos += 1;
                    i += 1;
                }
            }
        }

        return .{
            .width = width,
            .height = height,
            .delta_x = delta_x,
            .delta_y = delta_y,
            .offset_x = offset_x,
            .offset_y = offset_y,
            .pixels = pixels,
        };
    }

    /// Decode an OVERLAY sprite (AssetMapShadow / AssetSerfShadow, SpriteTypeOverlay).
    /// Format (freeserf `SpriteDosOverlay`): after the 10-byte header, RLE pairs of
    /// (drop, fill) — `drop` transparent pixels then `fill` shadow pixels. The
    /// original fills with palette[0x80] at alpha 0x80; we emit a flat
    /// semi-transparent black (0,0,0,128), which under GL_SRC_ALPHA blending darkens
    /// the terrain underneath by ~50% — the shadow effect.
    pub fn decodeOverlay(self: *BmpDecoder, data: []const u8) !Sprite {
        if (data.len < 10) return error.InvalidSprite;

        const delta_x: i8 = @bitCast(data[0]);
        const delta_y: i8 = @bitCast(data[1]);
        const width: u32 = std.mem.readInt(u16, data[2..4], .little);
        const height: u32 = std.mem.readInt(u16, data[4..6], .little);
        const offset_x: i16 = std.mem.readInt(i16, data[6..8], .little);
        const offset_y: i16 = std.mem.readInt(i16, data[8..10], .little);

        if (width == 0 or height == 0) return error.InvalidSpriteSize;
        if (width > 2048 or height > 2048) return error.InvalidSpriteSize;

        const pixel_count = width * height;
        const pixels = try self.allocator.alloc(ColorRGBA, pixel_count);
        errdefer self.allocator.free(pixels);
        @memset(pixels, ColorRGBA{ .r = 0, .g = 0, .b = 0, .a = 0 });

        const raw = data[10..];
        var pos: usize = 0;
        var i: usize = 0;
        while (i + 1 < raw.len and pos < pixel_count) {
            const drop = raw[i];
            const fill = raw[i + 1];
            i += 2;
            pos += drop; // transparent run
            for (0..fill) |_| {
                if (pos >= pixel_count) break;
                pixels[pos] = .{ .r = 0, .g = 0, .b = 0, .a = 128 };
                pos += 1;
            }
        }

        return .{
            .width = width,
            .height = height,
            .delta_x = delta_x,
            .delta_y = delta_y,
            .offset_x = offset_x,
            .offset_y = offset_y,
            .pixels = pixels,
        };
    }

    /// Composite a mask sprite onto a ground sprite, producing a single RGBA
    /// sprite where the ground texture shows only where the mask is opaque.
    /// This is freeserf's `ground.get_masked(mask)` approach (gfx.cc:226).
    /// The result has the dimensions of the ground sprite; the mask is
    /// aligned by their offset_x/offset_y hotspots.
    pub fn compositeMasked(
        self: *BmpDecoder,
        mask: *const Sprite,
        ground: *const Sprite,
    ) !Sprite {
        const w = ground.width;
        const h = ground.height;
        const pixels = try self.allocator.alloc(ColorRGBA, w * h);
        errdefer self.allocator.free(pixels);

        // The mask is typically smaller than the ground sprite (e.g. 32x9 mask
        // on a 32x20 ground). Center the mask vertically within the ground so
        // the road strip aligns to the tile center (the terrain diamond's
        // vertical center is at row 10 of the 20px sprite).
        const mask_dx: i32 = @as(i32, mask.offset_x) - @as(i32, ground.offset_x);
        const mask_dy: i32 = @as(i32, mask.offset_y) - @as(i32, ground.offset_y) +
            @divTrunc(@as(i32, @intCast(h)) - @as(i32, @intCast(mask.height)), 2);

        for (0..h) |gy| {
            for (0..w) |gx| {
                const ground_px = ground.pixels[gy * w + gx];
                // Sample the mask at the corresponding position.
                const mx: i32 = @as(i32, @intCast(gx)) + mask_dx;
                const my: i32 = @as(i32, @intCast(gy)) + mask_dy;
                var mask_alpha: u8 = 0;
                if (mx >= 0 and my >= 0 and
                    mx < @as(i32, @intCast(mask.width)) and
                    my < @as(i32, @intCast(mask.height)))
                {
                    mask_alpha = mask.pixels[@as(usize, @intCast(my)) * mask.width +
                        @as(usize, @intCast(mx))].a;
                }
                // Where mask is opaque, show the ground pixel; else transparent.
                pixels[gy * w + gx] = .{
                    .r = ground_px.r,
                    .g = ground_px.g,
                    .b = ground_px.b,
                    .a = mask_alpha,
                };
            }
        }

        return .{
            .width = w,
            .height = h,
            .delta_x = ground.delta_x,
            .delta_y = ground.delta_y,
            .offset_x = ground.offset_x,
            .offset_y = ground.offset_y,
            .pixels = pixels,
        };
    }

    /// Decode a MASK sprite (AssetPathMask, SpriteTypeMask). These are 1-bit
    /// alpha masks used to stencil road shapes onto ground textures. Format
    /// after the 10-byte header: RLE pairs (drop, fill) where `drop` = transparent
    /// pixels and `fill` = opaque white pixels (alpha=255). The RGB is white
    /// so that when used as a mask×ground composite, the ground texture shows
    /// through where the mask is opaque.
    pub fn decodeMask(self: *BmpDecoder, data: []const u8) !Sprite {
        if (data.len < 10) return error.InvalidSprite;

        const delta_x: i8 = @bitCast(data[0]);
        const delta_y: i8 = @bitCast(data[1]);
        const width: u32 = std.mem.readInt(u16, data[2..4], .little);
        const height: u32 = std.mem.readInt(u16, data[4..6], .little);
        const offset_x: i16 = std.mem.readInt(i16, data[6..8], .little);
        const offset_y: i16 = std.mem.readInt(i16, data[8..10], .little);

        if (width == 0 or height == 0) return error.InvalidSpriteSize;
        if (width > 2048 or height > 2048) return error.InvalidSpriteSize;

        const pixel_count = width * height;
        const pixels = try self.allocator.alloc(ColorRGBA, pixel_count);
        errdefer self.allocator.free(pixels);
        @memset(pixels, ColorRGBA{ .r = 0, .g = 0, .b = 0, .a = 0 });

        const raw = data[10..];
        var pos: usize = 0;
        var i: usize = 0;
        while (i + 1 < raw.len and pos < pixel_count) {
            const drop = raw[i];
            const fill = raw[i + 1];
            i += 2;
            pos += drop; // transparent run
            for (0..fill) |_| {
                if (pos >= pixel_count) break;
                // Opaque white — the mask stencil.
                pixels[pos] = .{ .r = 255, .g = 255, .b = 255, .a = 255 };
                pos += 1;
            }
        }

        return .{
            .width = width,
            .height = height,
            .delta_x = delta_x,
            .delta_y = delta_y,
            .offset_x = offset_x,
            .offset_y = offset_y,
            .pixels = pixels,
        };
    }
};
