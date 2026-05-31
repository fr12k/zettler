//! Font loader — bitmap font for rendering text.
//!
//! The original game uses a bitmap font stored in the game data files.
//! Each character is stored as a small sprite in a sprite sheet.
//!
//! Port of the C# Font class from Freeserf.

const std = @import("std");
const bmp = @import("bmp.zig");

/// A single character glyph in the bitmap font.
pub const Glyph = struct {
    /// Pixel data (grayscale or RGBA) for this character.
    pixels: []u8,
    /// Width of the glyph in pixels.
    width: u8,
    /// Height of the glyph in pixels.
    height: u8,
    /// Horizontal advance (how many pixels to advance after drawing).
    advance: u8,
};

/// Bitmap font with a fixed set of glyphs.
pub const BitmapFont = struct {
    allocator: std.mem.Allocator,
    /// Glyphs for characters 0x20..0x7F (printable ASCII).
    glyphs: [96]Glyph,
    /// Height of all glyphs (typically 14 pixels).
    glyph_height: u8,

    pub fn init(allocator: std.mem.Allocator) BitmapFont {
        return .{
            .allocator = allocator,
            .glyphs = @splat(Glyph{ .pixels = &.{}, .width = 0, .height = 0, .advance = 0 }),
            .glyph_height = 14,
        };
    }

    pub fn deinit(self: *BitmapFont) void {
        for (0..96) |i| {
            if (self.glyphs[i].pixels.len > 0) {
                self.allocator.free(self.glyphs[i].pixels);
            }
        }
    }

    /// Get the glyph for a given ASCII character.
    /// Returns null for non-printable characters.
    pub fn getGlyph(self: *BitmapFont, char: u8) ?*const Glyph {
        if (char < 0x20 or char > 0x7E) return null;
        return &self.glyphs[char - 0x20];
    }

    /// Get the width of a text string in pixels.
    pub fn textWidth(self: *BitmapFont, text: []const u8) u32 {
        var width: u32 = 0;
        for (text) |char| {
            if (self.getGlyph(char)) |glyph| {
                width += glyph.advance;
            }
        }
        return width;
    }

    /// Get the font height.
    pub fn height(self: BitmapFont) u8 {
        return self.glyph_height;
    }
};
