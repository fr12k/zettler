//! Font — bitmap text rendering using sprite batcher.
//!
//! Takes the decoded BitmapFont glyphs from data/font.zig and renders
//! text strings via the SpriteBatcher. Each glyph becomes a textured quad
//! sampled from a glyph texture that we upload once at init.

const std = @import("std");
const gl = @import("gl.zig");
const Shader = @import("Shader.zig").Shader;
const Camera = @import("Camera.zig").Camera;
const Texture = @import("Texture.zig");
const SpriteBatcher = @import("sprite_batcher.zig").SpriteBatcher;

const data = @import("data");
const BitmapFontData = data.font.BitmapFont;

/// Fallback ASCII-only bitmap font for when no game data is loaded.
/// Packed as a 96×14 texture (rows of 16 glyphs, each 6 wide = 96 total width).
pub const GLYPH_W: u8 = 6;
pub const GLYPH_H: u8 = 14;
pub const GLYPHS_PER_ROW: u8 = 16;
pub const FONT_TEXTURE_W: u16 = GLYPH_W * GLYPHS_PER_ROW; // 96
pub const FONT_TEXTURE_H: u16 = GLYPH_H * 6; // 84 (6 rows of 16)
/// Bytes per pixel in the fallback atlas (RGBA8).
const FALLBACK_BPP: usize = 4;

/// 4×6 bitmap font for ASCII 0x20..0x7E (95 glyphs + 1 unused).
/// Each entry is 6 rows of 4 bits (MSB = leftmost pixel).
/// 0 = transparent, 1 = opaque white.
const Glyph4x6 = struct {
    /// 6 rows, each a u8 with the lower 4 bits used (bit 3 = leftmost).
    rows: [6]u8,
};

/// The 4×6 bitmap font data. Indexed by (char - 0x20).
/// Covers space (0x20) through '~' (0x7E) = 95 characters.
const FONT_4x6 = blk: {
    @setEvalBranchQuota(100000);
    const N = 96; // 0x20..0x7F
    var glyphs: [N]Glyph4x6 = @splat(.{ .rows = @splat(0) });

    // Helper: build a glyph from 6 row patterns (each 4 bits wide).
    const g = struct {
        fn mk(r0: u8, r1: u8, r2: u8, r3: u8, r4: u8, r5: u8) Glyph4x6 {
            return .{ .rows = .{ r0, r1, r2, r3, r4, r5 } };
        }
    };

    // --- ASCII 0x20..0x3F: space, !, ", #, $, %, &, ', (, ), *, +, comma, -, ., /
    //                       0-9, :, ;, <, =, >, ? ---
    glyphs[0x20 - 0x20] = g.mk(0, 0, 0, 0, 0, 0); // space
    glyphs[0x21 - 0x20] = g.mk(0b0010, 0b0010, 0b0010, 0b0010, 0b0000, 0b0010); // !
    glyphs[0x22 - 0x20] = g.mk(0b0101, 0b0101, 0b0000, 0b0000, 0b0000, 0b0000); // "
    glyphs[0x23 - 0x20] = g.mk(0b0101, 0b0111, 0b0101, 0b0111, 0b0101, 0b0000); // #
    glyphs[0x24 - 0x20] = g.mk(0b0010, 0b0111, 0b0110, 0b0011, 0b0111, 0b0010); // $
    glyphs[0x25 - 0x20] = g.mk(0b1100, 0b1101, 0b0010, 0b0100, 0b1011, 0b0011); // %
    glyphs[0x26 - 0x20] = g.mk(0b0110, 0b1001, 0b1010, 0b0100, 0b1011, 0b0101); // &
    glyphs[0x27 - 0x20] = g.mk(0b0010, 0b0010, 0b0100, 0b0000, 0b0000, 0b0000); // '
    glyphs[0x28 - 0x20] = g.mk(0b0010, 0b0100, 0b0100, 0b0100, 0b0100, 0b0010); // (
    glyphs[0x29 - 0x20] = g.mk(0b0010, 0b0001, 0b0001, 0b0001, 0b0001, 0b0010); // )
    glyphs[0x2A - 0x20] = g.mk(0b0000, 0b0101, 0b0010, 0b0101, 0b0000, 0b0000); // *
    glyphs[0x2B - 0x20] = g.mk(0b0000, 0b0010, 0b0111, 0b0010, 0b0000, 0b0000); // +
    glyphs[0x2C - 0x20] = g.mk(0b0000, 0b0000, 0b0000, 0b0010, 0b0010, 0b0100); // ,
    glyphs[0x2D - 0x20] = g.mk(0b0000, 0b0000, 0b0111, 0b0000, 0b0000, 0b0000); // -
    glyphs[0x2E - 0x20] = g.mk(0b0000, 0b0000, 0b0000, 0b0000, 0b0010, 0b0010); // .
    glyphs[0x2F - 0x20] = g.mk(0b0001, 0b0010, 0b0100, 0b0010, 0b0001, 0b0000); // /
    // Digits 0-9
    glyphs[0x30 - 0x20] = g.mk(0b0110, 0b1001, 0b1011, 0b1101, 0b1001, 0b0110); // 0
    glyphs[0x31 - 0x20] = g.mk(0b0010, 0b0110, 0b0010, 0b0010, 0b0010, 0b0111); // 1
    glyphs[0x32 - 0x20] = g.mk(0b0110, 0b1001, 0b0010, 0b0100, 0b1000, 0b1111); // 2
    glyphs[0x33 - 0x20] = g.mk(0b1110, 0b0001, 0b0010, 0b0001, 0b1001, 0b0110); // 3
    glyphs[0x34 - 0x20] = g.mk(0b0010, 0b0110, 0b1010, 0b1111, 0b0010, 0b0010); // 4
    glyphs[0x35 - 0x20] = g.mk(0b1111, 0b1000, 0b1110, 0b0001, 0b1001, 0b0110); // 5
    glyphs[0x36 - 0x20] = g.mk(0b0110, 0b1000, 0b1110, 0b1001, 0b1001, 0b0110); // 6
    glyphs[0x37 - 0x20] = g.mk(0b1111, 0b0001, 0b0010, 0b0100, 0b0100, 0b0100); // 7
    glyphs[0x38 - 0x20] = g.mk(0b0110, 0b1001, 0b0110, 0b1001, 0b1001, 0b0110); // 8
    glyphs[0x39 - 0x20] = g.mk(0b0110, 0b1001, 0b0111, 0b0001, 0b0001, 0b0110); // 9
    glyphs[0x3A - 0x20] = g.mk(0b0000, 0b0010, 0b0000, 0b0000, 0b0010, 0b0000); // :
    glyphs[0x3B - 0x20] = g.mk(0b0000, 0b0010, 0b0000, 0b0010, 0b0010, 0b0100); // ;
    glyphs[0x3C - 0x20] = g.mk(0b0001, 0b0010, 0b0100, 0b0010, 0b0001, 0b0000); // <
    glyphs[0x3D - 0x20] = g.mk(0b0000, 0b0111, 0b0000, 0b0111, 0b0000, 0b0000); // =
    glyphs[0x3E - 0x20] = g.mk(0b0100, 0b0010, 0b0001, 0b0010, 0b0100, 0b0000); // >
    glyphs[0x3F - 0x20] = g.mk(0b0110, 0b1001, 0b0010, 0b0000, 0b0010, 0b0000); // ?

    // --- ASCII 0x40..0x5F: @, A-Z, [, \, ], ^, _ ---
    glyphs[0x40 - 0x20] = g.mk(0b0110, 0b1001, 0b1011, 0b1010, 0b1000, 0b0110); // @
    glyphs[0x41 - 0x20] = g.mk(0b0110, 0b1001, 0b1111, 0b1001, 0b1001, 0b1001); // A
    glyphs[0x42 - 0x20] = g.mk(0b1110, 0b1001, 0b1110, 0b1001, 0b1001, 0b1110); // B
    glyphs[0x43 - 0x20] = g.mk(0b0110, 0b1001, 0b1000, 0b1000, 0b1001, 0b0110); // C
    glyphs[0x44 - 0x20] = g.mk(0b1110, 0b1001, 0b1001, 0b1001, 0b1001, 0b1110); // D
    glyphs[0x45 - 0x20] = g.mk(0b1111, 0b1000, 0b1110, 0b1000, 0b1000, 0b1111); // E
    glyphs[0x46 - 0x20] = g.mk(0b1111, 0b1000, 0b1110, 0b1000, 0b1000, 0b1000); // F
    glyphs[0x47 - 0x20] = g.mk(0b0110, 0b1001, 0b1000, 0b1011, 0b1001, 0b0111); // G
    glyphs[0x48 - 0x20] = g.mk(0b1001, 0b1001, 0b1111, 0b1001, 0b1001, 0b1001); // H
    glyphs[0x49 - 0x20] = g.mk(0b0111, 0b0010, 0b0010, 0b0010, 0b0010, 0b0111); // I
    glyphs[0x4A - 0x20] = g.mk(0b0111, 0b0010, 0b0010, 0b0010, 0b1010, 0b0100); // J
    glyphs[0x4B - 0x20] = g.mk(0b1001, 0b1010, 0b1100, 0b1010, 0b1010, 0b1001); // K
    glyphs[0x4C - 0x20] = g.mk(0b1000, 0b1000, 0b1000, 0b1000, 0b1000, 0b1111); // L
    glyphs[0x4D - 0x20] = g.mk(0b1001, 0b1111, 0b1111, 0b1001, 0b1001, 0b1001); // M
    glyphs[0x4E - 0x20] = g.mk(0b1001, 0b1101, 0b1011, 0b1001, 0b1001, 0b1001); // N
    glyphs[0x4F - 0x20] = g.mk(0b0110, 0b1001, 0b1001, 0b1001, 0b1001, 0b0110); // O
    glyphs[0x50 - 0x20] = g.mk(0b1110, 0b1001, 0b1110, 0b1000, 0b1000, 0b1000); // P
    glyphs[0x51 - 0x20] = g.mk(0b0110, 0b1001, 0b1001, 0b1011, 0b1010, 0b0101); // Q
    glyphs[0x52 - 0x20] = g.mk(0b1110, 0b1001, 0b1110, 0b1010, 0b1010, 0b1001); // R
    glyphs[0x53 - 0x20] = g.mk(0b0111, 0b1000, 0b0110, 0b0001, 0b1001, 0b0110); // S
    glyphs[0x54 - 0x20] = g.mk(0b1111, 0b0010, 0b0010, 0b0010, 0b0010, 0b0010); // T
    glyphs[0x55 - 0x20] = g.mk(0b1001, 0b1001, 0b1001, 0b1001, 0b1001, 0b0110); // U
    glyphs[0x56 - 0x20] = g.mk(0b1001, 0b1001, 0b1001, 0b1001, 0b0101, 0b0010); // V
    glyphs[0x57 - 0x20] = g.mk(0b1001, 0b1001, 0b1111, 0b1111, 0b1001, 0b1001); // W
    glyphs[0x58 - 0x20] = g.mk(0b1001, 0b1001, 0b0101, 0b0010, 0b0101, 0b1001); // X
    glyphs[0x59 - 0x20] = g.mk(0b1001, 0b1001, 0b0101, 0b0010, 0b0010, 0b0010); // Y
    glyphs[0x5A - 0x20] = g.mk(0b1111, 0b0001, 0b0010, 0b0100, 0b1000, 0b1111); // Z
    glyphs[0x5B - 0x20] = g.mk(0b0110, 0b0100, 0b0100, 0b0100, 0b0100, 0b0110); // [
    glyphs[0x5C - 0x20] = g.mk(0b0100, 0b0010, 0b0001, 0b0010, 0b0100, 0b0000); // \
    glyphs[0x5D - 0x20] = g.mk(0b0110, 0b0010, 0b0010, 0b0010, 0b0010, 0b0110); // ]
    glyphs[0x5E - 0x20] = g.mk(0b0010, 0b0101, 0b0000, 0b0000, 0b0000, 0b0000); // ^
    glyphs[0x5F - 0x20] = g.mk(0b0000, 0b0000, 0b0000, 0b0000, 0b0000, 0b1111); // _

    // --- ASCII 0x60..0x7E: `, a-z, {, |, }, ~ ---
    glyphs[0x60 - 0x20] = g.mk(0b0100, 0b0010, 0b0000, 0b0000, 0b0000, 0b0000); // `
    glyphs[0x61 - 0x20] = g.mk(0b0000, 0b0000, 0b0110, 0b0001, 0b1011, 0b0111); // a
    glyphs[0x62 - 0x20] = g.mk(0b1000, 0b1000, 0b1110, 0b1001, 0b1001, 0b1110); // b
    glyphs[0x63 - 0x20] = g.mk(0b0000, 0b0000, 0b0111, 0b1000, 0b1000, 0b0111); // c
    glyphs[0x64 - 0x20] = g.mk(0b0001, 0b0001, 0b0111, 0b1001, 0b1001, 0b0111); // d
    glyphs[0x65 - 0x20] = g.mk(0b0000, 0b0000, 0b0110, 0b1001, 0b1110, 0b0111); // e
    glyphs[0x66 - 0x20] = g.mk(0b0010, 0b0101, 0b0100, 0b1100, 0b0100, 0b0100); // f
    glyphs[0x67 - 0x20] = g.mk(0b0000, 0b0111, 0b1001, 0b0111, 0b0001, 0b0110); // g
    glyphs[0x68 - 0x20] = g.mk(0b1000, 0b1000, 0b1110, 0b1001, 0b1001, 0b1001); // h
    glyphs[0x69 - 0x20] = g.mk(0b0010, 0b0000, 0b0110, 0b0010, 0b0010, 0b0111); // i
    glyphs[0x6A - 0x20] = g.mk(0b0010, 0b0000, 0b0110, 0b0010, 0b0010, 0b1010); // j
    glyphs[0x6B - 0x20] = g.mk(0b1000, 0b1000, 0b1010, 0b1100, 0b1010, 0b1010); // k
    glyphs[0x6C - 0x20] = g.mk(0b0110, 0b0010, 0b0010, 0b0010, 0b0010, 0b0111); // l
    glyphs[0x6D - 0x20] = g.mk(0b0000, 0b0000, 0b1010, 0b1111, 0b1111, 0b1010); // m
    glyphs[0x6E - 0x20] = g.mk(0b0000, 0b0000, 0b1110, 0b1001, 0b1001, 0b1001); // n
    glyphs[0x6F - 0x20] = g.mk(0b0000, 0b0000, 0b0110, 0b1001, 0b1001, 0b0110); // o
    glyphs[0x70 - 0x20] = g.mk(0b0000, 0b0000, 0b1110, 0b1001, 0b1110, 0b1000); // p
    glyphs[0x71 - 0x20] = g.mk(0b0000, 0b0111, 0b1001, 0b0111, 0b0001, 0b0001); // q
    glyphs[0x72 - 0x20] = g.mk(0b0000, 0b0000, 0b1010, 0b1100, 0b1000, 0b1000); // r
    glyphs[0x73 - 0x20] = g.mk(0b0000, 0b0000, 0b0111, 0b1100, 0b0011, 0b1110); // s
    glyphs[0x74 - 0x20] = g.mk(0b0100, 0b0100, 0b1100, 0b0100, 0b0101, 0b0010); // t
    glyphs[0x75 - 0x20] = g.mk(0b0000, 0b0000, 0b1001, 0b1001, 0b1001, 0b0111); // u
    glyphs[0x76 - 0x20] = g.mk(0b0000, 0b0000, 0b1001, 0b1001, 0b0101, 0b0010); // v
    glyphs[0x77 - 0x20] = g.mk(0b0000, 0b0000, 0b1001, 0b1111, 0b1111, 0b0101); // w
    glyphs[0x78 - 0x20] = g.mk(0b0000, 0b0000, 0b1001, 0b0101, 0b0010, 0b1001); // x
    glyphs[0x79 - 0x20] = g.mk(0b0000, 0b1001, 0b1001, 0b0111, 0b0010, 0b0100); // y
    glyphs[0x7A - 0x20] = g.mk(0b0000, 0b0000, 0b1111, 0b0010, 0b0100, 0b1111); // z
    glyphs[0x7B - 0x20] = g.mk(0b0010, 0b0101, 0b0100, 0b0101, 0b0010, 0b0000); // {
    glyphs[0x7C - 0x20] = g.mk(0b0010, 0b0010, 0b0010, 0b0010, 0b0010, 0b0010); // |
    glyphs[0x7D - 0x20] = g.mk(0b0100, 0b0101, 0b0010, 0b0101, 0b0100, 0b0000); // }
    glyphs[0x7E - 0x20] = g.mk(0b0000, 0b0101, 0b1010, 0b0000, 0b0000, 0b0000); // ~

    break :blk glyphs;
};

/// Pre-built fallback glyph atlas (RGBA8).
/// Each glyph is GLYPH_W × GLYPH_H pixels in the atlas.
/// The 4×6 bitmap font is placed in the top-left 4×6 area of each 6×14
/// cell; the remaining columns/rows are transparent padding.
fn buildFallbackGlyphAtlas() [FONT_TEXTURE_W * FONT_TEXTURE_H * FALLBACK_BPP]u8 {
    @setEvalBranchQuota(50000);
    var atlas: [FONT_TEXTURE_W * FONT_TEXTURE_H * FALLBACK_BPP]u8 = @splat(0); // transparent

    // For each of the 96 glyphs (ASCII 0x20..0x7F), render its 4×6 bitmap
    // into the atlas at the appropriate position.
    for (0..96) |i| {
        const col = i % 16;
        const row = i / 16;
        const cell_x = col * GLYPH_W;
        const cell_y = row * GLYPH_H;
        const glyph = FONT_4x6[i];

        for (0..6) |gy| {
            const row_bits = glyph.rows[gy];
            for (0..4) |gx| {
                // bit 3 = leftmost pixel (x=0)
                const bit: u8 = @as(u8, 3) - @as(u8, @intCast(gx));
                const is_set = (row_bits >> bit) & 1;
                if (is_set != 0) {
                    const px = cell_x + gx;
                    const py = cell_y + gy;
                    const idx = (py * FONT_TEXTURE_W + px) * FALLBACK_BPP;
                    atlas[idx + 0] = 255; // R
                    atlas[idx + 1] = 255; // G
                    atlas[idx + 2] = 255; // B
                    atlas[idx + 3] = 255; // A (opaque)
                }
            }
        }
    }

    return atlas;
}

/// RGBA pixel data for the font texture (built at comptime).
const FALLBACK_ATLAS: [FONT_TEXTURE_W * FONT_TEXTURE_H * FALLBACK_BPP]u8 = buildFallbackGlyphAtlas();

/// Text alignment.
pub const Align = enum(u2) {
    left,
    center,
    right,
};

/// Font renderer — draws text strings to the screen via SpriteBatcher.
pub const Font = struct {
    /// OpenGL texture ID for the glyph atlas.
    gl_texture: gl.GLuint = 0,
    /// Whether we have a real font loaded from game data.
    has_real_font: bool = false,
    /// The decoded bitmap font (for metrics).
    font_data: BitmapFontData = undefined,
    /// Width of each glyph in the atlas texture.
    glyph_tex_w: f32 = GLYPH_W,
    /// Height of each glyph in the atlas texture.
    glyph_tex_h: f32 = GLYPH_H,
    /// Atlas texture dimensions.
    atlas_w: f32 = FONT_TEXTURE_W,
    atlas_h: f32 = FONT_TEXTURE_H,

    /// Initialize with a fallback built-in font.
    pub fn init(allocator: std.mem.Allocator) !Font {
        const font = Font{
            .font_data = BitmapFontData.init(allocator),
        };
        return font;
    }

    /// Load a real bitmap font from game data and upload to GPU.
    pub fn loadFromData(self: *Font, font_data: *BitmapFontData) !void {
        // Build a texture atlas from the bitmap font glyphs.
        // The original font has 96 glyphs (0x20-0x7F), each ~6×14 pixels.
        // Pack them into a texture: 16 columns × 6 rows.
        const gw = font_data.glyphs[0].width;
        const gh = font_data.glyph_height;
        const cols: u16 = 16;
        const rows: u16 = 6;
        const tw: u16 = @as(u16, gw) * cols;
        const th: u16 = @as(u16, gh) * rows;

        var pixels = try font_data.allocator.alloc(u8, tw * th * 4);
        defer font_data.allocator.free(pixels);
        @memset(pixels, 0);

        for (0..96) |i| {
            const g = &font_data.glyphs[i];
            const col = i % cols;
            const row = i / cols;
            const dx = col * gw;
            const dy = row * gh;
            // Copy glyph pixels (assumed RGBA or grayscale)
            const src_w = @min(g.width, gw);
            const src_h = @min(g.height, gh);
            for (0..src_h) |sy| {
                for (0..src_w) |sx| {
                    const src_i = sy * g.width + sx;
                    const dst_x = dx + sx;
                    const dst_y = dy + sy;
                    const dst_i = (dst_y * tw + dst_x) * 4;
                    // If source is grayscale (1 byte per pixel), replicate to RGB
                    if (g.pixels.len >= (src_w * src_h)) {
                        const v = g.pixels[src_i];
                        pixels[dst_i + 0] = 255;
                        pixels[dst_i + 1] = 255;
                        pixels[dst_i + 2] = 255;
                        pixels[dst_i + 3] = v;
                    } else {
                        pixels[dst_i + 0] = 255;
                        pixels[dst_i + 1] = 255;
                        pixels[dst_i + 2] = 255;
                        pixels[dst_i + 3] = 255;
                    }
                }
            }
        }

        // Upload to GPU
        if (self.gl_texture == 0) {
            self.gl_texture = gl.genTextures(1);
        }
        gl.bindTexture(gl.GL_TEXTURE_2D, self.gl_texture);
        gl.texImage2D(gl.GL_TEXTURE_2D, 0, @intCast(gl.GL_RGBA8), @intCast(tw), @intCast(th), gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, pixels.ptr);
        gl.texParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
        gl.texParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
        gl.texParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
        gl.texParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);

        self.font_data = font_data.*;
        self.glyph_tex_w = @floatFromInt(gw);
        self.glyph_tex_h = @floatFromInt(gh);
        self.atlas_w = @floatFromInt(tw);
        self.atlas_h = @floatFromInt(th);
        self.has_real_font = true;
    }

    /// Upload the built-in fallback font texture to GPU.
    pub fn uploadFallback(self: *Font) void {
        if (self.gl_texture != 0) return;
        self.gl_texture = gl.genTextures(1);
        gl.bindTexture(gl.GL_TEXTURE_2D, self.gl_texture);
        gl.texImage2D(gl.GL_TEXTURE_2D, 0, @intCast(gl.GL_RGBA8), FONT_TEXTURE_W, FONT_TEXTURE_H, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, &FALLBACK_ATLAS);
        gl.texParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
        gl.texParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
        gl.texParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
        gl.texParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
    }

    pub fn deinit(self: *Font) void {
        if (self.gl_texture != 0) {
            gl.deleteTextures(1, &self.gl_texture);
            self.gl_texture = 0;
        }
    }

    /// Get the width of a text string in pixels at the given scale.
    pub fn textWidth(self: *Font, text: []const u8, scale: f32) f32 {
        var w: f32 = 0;
        for (text) |char| {
            if (char < 0x20 or char > 0x7E) {
                w += self.glyph_tex_w * scale * 0.5; // space
                continue;
            }
            w += self.glyph_tex_w * scale;
        }
        return w;
    }

    /// Draw a string of text into the sprite batcher.
    /// `x`, `y` is the top-left position in screen coordinates.
    /// `color` is the tint colour (r, g, b, a).
    /// `scale` controls glyph size (1.0 = original pixel size).
    pub fn drawText(self: *Font, batcher: *SpriteBatcher, text: []const u8, x: f32, y: f32, color: [4]f32, scale: f32) void {
        var cx = x;
        const gw = self.glyph_tex_w * scale;
        const gh = self.glyph_tex_h * scale;
        const inv_tw = 1.0 / self.atlas_w;
        const inv_th = 1.0 / self.atlas_h;

        for (text) |char| {
            if (char < 0x20 or char > 0x7E) {
                cx += gw * 0.5; // space
                continue;
            }
            const idx = char - 0x20;
            const col = @as(f32, @floatFromInt(idx % 16));
            const row = @as(f32, @floatFromInt(idx / 16));
            const u = col * self.glyph_tex_w * inv_tw;
            const v = row * self.glyph_tex_h * inv_th;
            const uw = self.glyph_tex_w * inv_tw;
            const vh = self.glyph_tex_h * inv_th;

            batcher.add(.{
                .x = cx,
                .y = y,
                .width = gw,
                .height = gh,
                .u = u,
                .v = v,
                .uw = uw,
                .vh = vh,
                .r = color[0],
                .g = color[1],
                .b = color[2],
                .a = color[3],
            });
            cx += gw;
        }
    }

    /// Draw a right-aligned string into the sprite batcher.
    pub fn drawTextRight(self: *Font, batcher: *SpriteBatcher, text: []const u8, right_x: f32, y: f32, color: [4]f32, scale: f32) void {
        const w = self.textWidth(text, scale);
        self.drawText(batcher, text, right_x - w, y, color, scale);
    }

    /// Draw a centered string into the sprite batcher.
    pub fn drawTextCenter(self: *Font, batcher: *SpriteBatcher, text: []const u8, cx: f32, y: f32, color: [4]f32, scale: f32) void {
        const w = self.textWidth(text, scale);
        self.drawText(batcher, text, cx - w / 2.0, y, color, scale);
    }

    /// Draw a formatted string (std.fmt) into the sprite batcher.
    /// Uses a 256-byte stack buffer for the formatted text.
    pub fn drawFmt(self: *Font, batcher: *SpriteBatcher, comptime fmt: []const u8, args: anytype, x: f32, y: f32, color: [4]f32, scale: f32) void {
        var buf: [256]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, fmt, args) catch return;
        self.drawText(batcher, text, x, y, color, scale);
    }

    /// Bind the font texture and render batched glyphs.
    pub fn render(self: *Font, batcher: *SpriteBatcher, shader: *Shader, camera: *Camera) void {
        if (self.gl_texture == 0) return;
        var tex = Texture{ .id = self.gl_texture, .width = @intFromFloat(self.atlas_w), .height = @intFromFloat(self.atlas_h) };
        batcher.render(shader, &tex, camera);
    }
};