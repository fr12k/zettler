//! Minimap — small overview of the full map in the corner.
//!
//! Renders a compressed view of the terrain as colored pixels.
//! Clicking on the minimap jumps the camera to that location.

const std = @import("std");
const core = @import("core");
const gl = @import("../gl.zig");
const Shader = @import("../Shader.zig").Shader;
const Camera = @import("../Camera.zig").Camera;
const Texture = @import("../Texture.zig");
const SpriteBatcher = @import("../sprite_batcher.zig").SpriteBatcher;
const Event = @import("Event.zig");
const Rect = Event.Rect;

const Map = core.map.Map;
const Game = core.game.Game;
const MapPos = core.types.MapPos;

/// Minimap size in pixels.
pub const MINIMAP_SIZE: f32 = 160.0;
/// Minimap padding from screen edge.
pub const MINIMAP_PAD: f32 = 8.0;

/// Terrain colors for minimap pixels.
fn terrainColor(t: core.map.Terrain) [3]u8 {
    return switch (t) {
        .water => .{ 40, 80, 160 },
        .grass => .{ 60, 140, 40 },
        .tundra => .{ 100, 120, 80 },
        .snow => .{ 180, 180, 200 },
        .swamp => .{ 60, 80, 40 },
        .lava => .{ 160, 60, 0 },
        .desert => .{ 160, 140, 40 },
        .mountain => .{ 100, 80, 60 },
        .mountain2 => .{ 110, 90, 70 },
        .mountain_mined => .{ 120, 80, 40 },
        .mountain_flagged => .{ 100, 70, 30 },
    };
}

/// Minimap overlay — rendered every frame.
pub const Minimap = struct {
    /// Screen position (top-right corner).
    x: f32 = 0,
    y: f32 = 0,
    /// Size in pixels.
    size: f32 = MINIMAP_SIZE,
    /// Cached GL texture of the minimap.
    gl_texture: gl.GLuint = 0,
    /// Whether the texture needs updating.
    dirty: bool = true,
    /// Map dimensions at last build (to detect map changes).
    last_map_w: u16 = 0,
    last_map_h: u16 = 0,
    /// Clickable region.
    region: Event.Rect = Event.Rect{ .x = 0, .y = 0, .width = MINIMAP_SIZE, .height = MINIMAP_SIZE },
    /// Whether the minimap is visible.
    visible: bool = true,

    pub fn init() Minimap {
        return Minimap{};
    }

    pub fn deinit(self: *Minimap) void {
        if (self.gl_texture != 0) {
            gl.deleteTextures(1, &self.gl_texture);
            self.gl_texture = 0;
        }
    }

    /// Set screen position (top-right corner).
    pub fn setPosition(self: *Minimap, screen_w: f32, screen_h: f32) void {
        _ = screen_h;
        self.x = screen_w - self.size - MINIMAP_PAD;
        self.y = MINIMAP_PAD + 28.0; // below top bar
        self.region = Event.Rect{
            .x = self.x,
            .y = self.y,
            .width = self.size,
            .height = self.size,
        };
    }

    /// Rebuild the minimap texture from the current map state.
    pub fn rebuild(self: *Minimap, map: *Map) void {
        const w = map.width;
        const h = map.height;
        if (w == 0 or h == 0) return;

        self.last_map_w = w;
        self.last_map_h = h;

        // Create a pixel buffer: 1 pixel per map tile, scaled to minimap size
        const mw: u32 = @intFromFloat(self.size);
        const mh: u32 = @intFromFloat(self.size);
        var pixels = std.heap.page_allocator.alloc(u8, mw * mh * 4) catch return;
        defer std.heap.page_allocator.free(pixels);
        @memset(pixels, 0);

        const scale_x = @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(mw));
        const scale_y = @as(f32, @floatFromInt(h)) / @as(f32, @floatFromInt(mh));

        for (0..mh) |py| {
            for (0..mw) |px| {
                const mx = @as(u16, @intFromFloat(@as(f32, @floatFromInt(px)) * scale_x));
                const my = @as(u16, @intFromFloat(@as(f32, @floatFromInt(py)) * scale_y));
                if (mx >= w or my >= h) continue;

                const tile = map.getTileXY(mx, my);
                const c = terrainColor(tile.terrain);
                const idx = (py * mw + px) * 4;
                pixels[idx + 0] = c[0];
                pixels[idx + 1] = c[1];
                pixels[idx + 2] = c[2];
                pixels[idx + 3] = 255;
            }
        }

        // Upload to GPU
        if (self.gl_texture == 0) {
            self.gl_texture = gl.genTextures(1);
        }
        gl.bindTexture(gl.GL_TEXTURE_2D, self.gl_texture);
        gl.texImage2D(gl.GL_TEXTURE_2D, 0, @intCast(gl.GL_RGBA8), @intCast(mw), @intCast(mh), gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, pixels.ptr);
        gl.texParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
        gl.texParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
        gl.texParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
        gl.texParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);

        self.dirty = false;
    }

    /// Convert a minimap pixel position to a map position.
    pub fn pixelToMap(self: *Minimap, mx: f32, my: f32, map_w: u16, map_h: u16) MapPos {
        const rel_x = mx - self.x;
        const rel_y = my - self.y;
        const nx = @as(u16, @intFromFloat(@max(0, rel_x / self.size * @as(f32, @floatFromInt(map_w)))));
        const ny = @as(u16, @intFromFloat(@max(0, rel_y / self.size * @as(f32, @floatFromInt(map_h)))));
        return .{ .x = @min(nx, map_w - 1), .y = @min(ny, map_h - 1) };
    }

    /// Check if a screen position is inside the minimap.
    pub fn contains(self: *Minimap, px: f32, py: f32) bool {
        return self.visible and self.region.contains(px, py);
    }

    /// Draw the minimap (background + texture overlay).
    pub fn draw(self: *Minimap, batcher: *SpriteBatcher, shader: *Shader) void {
        _ = shader;
        if (!self.visible) return;

        // Background
        batcher.add(.{
            .x = self.x - 1, .y = self.y - 1,
            .width = self.size + 2, .height = self.size + 2,
            .u = 0, .v = 0, .uw = 0, .vh = 0,
            .r = 0.2, .g = 0.2, .b = 0.2, .a = 0.8,
        });

        if (self.gl_texture != 0) {
            // The minimap texture is rendered via the batcher as a textured quad:
            batcher.add(.{
                .x = self.x, .y = self.y,
                .width = self.size, .height = self.size,
                .u = 0, .v = 0, .uw = 1.0, .vh = 1.0,
                .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0,
            });
        }
    }
};