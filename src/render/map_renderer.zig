//! Map renderer — renders the hex grid terrain with textured quads.
//!
//! Each terrain tile is an axis-aligned 32×20 rectangle. The terrain sprite
//! contains the diamond shape within it; transparent corners are discarded by
//! alpha blending. Tiles overlap in painter's order (top row first).

const std = @import("std");
const gl = @import("gl.zig");
const core = @import("core");
const Shader = @import("Shader.zig").Shader;
const Camera = @import("Camera.zig").Camera;
const TextureAtlas = @import("texture_atlas.zig").TextureAtlas;

const Map = core.map.Map;
const MapPos = core.MapPos;
const Terrain = core.map.Terrain;

/// Tile dimensions in world pixels (match actual 32×20 terrain sprites).
pub const TileWidth: f32 = 32.0;
pub const TileHeight: f32 = 20.0;

/// First PAK index of the 32×20 terrain sprites.
pub const TERRAIN_SPRITE_BASE: u16 = 259;

/// Map terrain type to a PAK sprite index.
fn terrainSpriteId(t: Terrain) u16 {
    // Settlers 1 terrain sprites at 259-308.
    // Empirical mapping: 0=water, 1=grass, 2=tundra, 3=snow, 4=swamp,
    // 5=lava, 6=desert, 7-10=mountain variants.
    const offset: u16 = switch (t) {
        .water => 0,
        .grass => 4,
        .tundra => 8,
        .snow => 12,
        .swamp => 16,
        .lava => 20,
        .desert => 24,
        .mountain => 28,
        .mountain2 => 32,
        .mountain_mined => 36,
        .mountain_flagged => 40,
    };
    return TERRAIN_SPRITE_BASE + offset;
}

/// Fallback solid color when no atlas sprite is available.
fn terrainColor(t: Terrain) [4]f32 {
    return switch (t) {
        .water => .{ 0.2, 0.4, 0.8, 1.0 },
        .grass => .{ 0.3, 0.7, 0.2, 1.0 },
        .tundra => .{ 0.5, 0.6, 0.4, 1.0 },
        .snow => .{ 0.9, 0.9, 1.0, 1.0 },
        .swamp => .{ 0.3, 0.4, 0.2, 1.0 },
        .lava => .{ 0.8, 0.3, 0.0, 1.0 },
        .desert => .{ 0.8, 0.7, 0.2, 1.0 },
        .mountain => .{ 0.5, 0.4, 0.3, 1.0 },
        .mountain2 => .{ 0.55, 0.45, 0.35, 1.0 },
        .mountain_mined => .{ 0.6, 0.4, 0.2, 1.0 },
        .mountain_flagged => .{ 0.5, 0.3, 0.1, 1.0 },
    };
}

/// MapRenderer — draws terrain tiles.
pub const MapRenderer = struct {
    shader: Shader = .{},
    vbo: gl.GLuint = 0,
    ibo: gl.GLuint = 0,
    vertex_count: usize = 0,
    index_count: usize = 0,
    initialized: bool = false,
    has_atlas: bool = false,

    // x, y, u, v, r, g, b, a
    pub const Vertex = struct {
        x: f32,
        y: f32,
        u: f32,
        v: f32,
        r: f32,
        g: f32,
        b: f32,
        a: f32,
    };

    pub fn deinit(self: *MapRenderer) void {
        if (self.vbo != 0) {
            var v = self.vbo;
            gl.deleteBuffers(1, &v);
            self.vbo = 0;
        }
        if (self.ibo != 0) {
            var v = self.ibo;
            gl.deleteBuffers(1, &v);
            self.ibo = 0;
        }
        self.shader.deinit();
        self.initialized = false;
    }

    /// Build/rebuild the VBO. Pass null atlas for colored fallback.
    pub fn init(self: *MapRenderer, map: *Map) !void {
        try self.rebuild(map, null);
        self.shader = try Shader.createDefault();
    }

    /// Rebuild vertex data using atlas UV coordinates.
    pub fn rebuildWithAtlas(self: *MapRenderer, map: *Map, atlas: *TextureAtlas) !void {
        try self.rebuild(map, atlas);
        self.has_atlas = true;
    }

    fn rebuild(self: *MapRenderer, map: *Map, atlas: ?*TextureAtlas) !void {
        if (self.vbo == 0) self.vbo = gl.genBuffers(1);
        if (self.ibo == 0) self.ibo = gl.genBuffers(1);

        const num_tiles = map.tileCount();
        const allocator = std.heap.page_allocator;
        const vertices = try allocator.alloc(Vertex, num_tiles * 4);
        defer allocator.free(vertices);
        const indices = try allocator.alloc(u16, num_tiles * 6);
        defer allocator.free(indices);

        const hw = TileWidth / 2.0;
        const hh = TileHeight / 2.0;

        for (0..map.height) |y| {
            for (0..map.width) |x| {
                const ti = y * map.width + x;
                const tile = map.getTileXY(@intCast(x), @intCast(y));
                // Tile center in world space
                const cx = @as(f32, @floatFromInt(x)) * TileWidth +
                    @as(f32, @floatFromInt(y & 1)) * hw;
                const cy = @as(f32, @floatFromInt(y)) * hh;

                const vi = ti * 4;
                const ii = ti * 6;

                // UV coordinates — atlas slice if available, else full texture
                var uvx0: f32 = 0;
                var uvy0: f32 = 0;
                var uvx1: f32 = 1;
                var uvy1: f32 = 1;
                if (atlas) |a| {
                    const sid = terrainSpriteId(tile.terrain);
                    if (a.get(sid)) |entry| {
                        uvx0 = entry.u;
                        uvy0 = entry.v;
                        uvx1 = entry.u + entry.uw;
                        uvy1 = entry.v + entry.vh;
                    }
                }

                // Color: white when texturing, terrain color for fallback
                const c: [4]f32 = if (atlas != null) .{ 1, 1, 1, 1 } else terrainColor(tile.terrain);

                // Axis-aligned rectangle (sprite bounding box).
                // Top-left, top-right, bottom-right, bottom-left
                vertices[vi + 0] = .{ .x = cx - hw, .y = cy - hh, .u = uvx0, .v = uvy0, .r = c[0], .g = c[1], .b = c[2], .a = c[3] };
                vertices[vi + 1] = .{ .x = cx + hw, .y = cy - hh, .u = uvx1, .v = uvy0, .r = c[0], .g = c[1], .b = c[2], .a = c[3] };
                vertices[vi + 2] = .{ .x = cx + hw, .y = cy + hh, .u = uvx1, .v = uvy1, .r = c[0], .g = c[1], .b = c[2], .a = c[3] };
                vertices[vi + 3] = .{ .x = cx - hw, .y = cy + hh, .u = uvx0, .v = uvy1, .r = c[0], .g = c[1], .b = c[2], .a = c[3] };
                // Indices: two triangles (TL, TR, BR) and (TL, BR, BL)
                indices[ii + 0] = @intCast(vi + 0);
                indices[ii + 1] = @intCast(vi + 1);
                indices[ii + 2] = @intCast(vi + 2);
                indices[ii + 3] = @intCast(vi + 0);
                indices[ii + 4] = @intCast(vi + 2);
                indices[ii + 5] = @intCast(vi + 3);
            }
        }

        self.vertex_count = num_tiles * 4;
        self.index_count = num_tiles * 6;

        gl.bindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
        gl.bufferData(gl.GL_ARRAY_BUFFER, std.mem.sliceAsBytes(vertices[0..self.vertex_count]), gl.GL_STATIC_DRAW);
        gl.bindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.ibo);
        gl.bufferData(gl.GL_ELEMENT_ARRAY_BUFFER, std.mem.sliceAsBytes(indices[0..self.index_count]), gl.GL_STATIC_DRAW);
        self.initialized = true;
    }

    pub fn render(self: *MapRenderer, camera: *Camera) void {
        if (!self.initialized) return;
        self.shader.use();
        self.shader.setTexture(0);
        self.shader.setColor(1, 1, 1, 1);
        self.shader.setOffset(0, 0);
        camera.updateMatrices();
        self.shader.setProjection(&camera.projection);
        self.shader.setModelview(&camera.modelview);

        gl.bindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
        gl.bindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.ibo);
        const stride: i32 = @sizeOf(Vertex);
        gl.enableVertexAttribArray(0);
        gl.vertexAttribPointer(0, 2, gl.GL_FLOAT, gl.GL_FALSE, stride, 0);
        gl.enableVertexAttribArray(1);
        gl.vertexAttribPointer(1, 2, gl.GL_FLOAT, gl.GL_FALSE, stride, 8);
        gl.enableVertexAttribArray(2);
        gl.vertexAttribPointer(2, 3, gl.GL_FLOAT, gl.GL_FALSE, stride, 16);
        gl.drawElements(gl.GL_TRIANGLES, @intCast(self.index_count), gl.GL_UNSIGNED_SHORT, 0);
        gl.disableVertexAttribArray(0);
        gl.disableVertexAttribArray(1);
        gl.disableVertexAttribArray(2);
    }
};
