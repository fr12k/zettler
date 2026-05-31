//! Texture — OpenGL texture management.
//!
//! Handles uploading sprite pixel data to the GPU,
//! managing texture atlases, and texture caching.

const std = @import("std");
const gl = @import("gl.zig");

/// An OpenGL texture object.
pub const Texture = struct {
    /// OpenGL texture ID.
    id: gl.GLuint = 0,
    /// Width of the texture in pixels.
    width: u32 = 0,
    /// Height of the texture in pixels.
    height: u32 = 0,

    /// Create a texture from RGBA pixel data.
    pub fn init(pixels: []const u8, w: u32, h: u32) Texture {
        const tex_id = gl.genTextures(1);
        gl.bindTexture(gl.GL_TEXTURE_2D, tex_id);

        // Upload pixel data
        gl.texImage2D(
            gl.GL_TEXTURE_2D,
            0, @intCast(gl.GL_RGBA8),
            @intCast(w), @intCast(h),
            gl.GL_RGBA, gl.GL_UNSIGNED_BYTE,
            pixels.ptr,
        );

        // Set filtering (bilinear for smooth scaling)
        gl.texParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
        gl.texParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
        gl.texParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
        gl.texParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);

        return .{
            .id = tex_id,
            .width = w,
            .height = h,
        };
    }

    pub fn deinit(self: *Texture) void {
        if (self.id != 0) {
            const ids = [_]gl.GLuint{self.id};
            gl.deleteTextures(1, &ids);
            self.id = 0;
        }
    }

    /// Bind this texture for rendering.
    pub fn bind(self: *Texture) void {
        gl.bindTexture(gl.GL_TEXTURE_2D, self.id);
    }

    /// Get normalized texture coordinates (u, v, w, h) for a sub-rectangle.
    pub fn getSubTexCoords(self: Texture, x: u32, y: u32, w: u32, h: u32) struct { u: f32, v: f32, uw: f32, vh: f32 } {
        return .{
            .u = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(self.width)),
            .v = @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(self.height)),
            .uw = @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(self.width)),
            .vh = @as(f32, @floatFromInt(h)) / @as(f32, @floatFromInt(self.height)),
        };
    }
};

/// A texture atlas — packs many small sprites into a single large texture.
pub const TextureAtlas = struct {
    allocator: std.mem.Allocator,
    /// The atlas texture.
    texture: Texture = .{},
    /// Size of the atlas.
    atlas_size: u32 = 0,
    /// Whether the atlas has been initialized.
    initialized: bool = false,

    pub fn init(allocator: std.mem.Allocator) TextureAtlas {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *TextureAtlas) void {
        if (self.initialized) {
            self.texture.deinit();
        }
    }

    /// Create the atlas texture with given size.
    pub fn create(self: *TextureAtlas, size: u32) !void {
        if (self.initialized) self.texture.deinit();

        // Create empty RGBA texture
        const pixel_count = size * size;
        const pixels = try self.allocator.alloc(u8, pixel_count * 4);
        defer self.allocator.free(pixels);
        @memset(pixels, 0); // transparent

        self.texture = Texture.init(pixels, size, size);
        self.atlas_size = size;
        self.initialized = true;
    }

    /// Upload a sprite into the atlas at the given position.
    pub fn uploadSprite(_self: *TextureAtlas, _pixels: []const u8, _x: u32, _y: u32, _w: u32, _h: u32) void {
        _ = _self;
        _ = _pixels;
        _ = _x;
        _ = _y;
        _ = _w;
        _ = _h;

        // Future: use glTexSubImage2D to upload sub-rectangle
    }
};
