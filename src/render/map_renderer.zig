//! Map renderer — renders the hex grid terrain with textured quads.
//!
//! Each terrain tile is drawn as a diamond (like the original Settlers).
//! Uses the original Settlers isometric coordinate projection:
//!   screen_x = col * TileWidth  - row * (TileWidth/2)
//!   screen_y = row * TileHeight
//!
//! In the original C++ code, terrain sprites (AssetMapGround) are fully
//! opaque solid rectangles (SpriteTypeSolid). The diamond shape comes from
//! a separate mask system (AssetMapMaskUp/AssetMapMaskDown) that clips each
//! rectangular sprite to a triangle. Here we replicate that effect by
//! rendering each tile as two explicit triangles with axis-aligned UV
//! coordinates, so the sprite content maps correctly without a mask texture.

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

/// First PAK index of the 32×20 terrain sprites (C++ AssetMapGround base).
pub const TERRAIN_SPRITE_BASE: u16 = 260;

/// Height-mask lookup table for the up-pointing triangle (from C++ viewport.cc tri_mask[]).
/// Index = 4 + (m - left) + 9 * (4 + (m - right)), clamped to [0,8] each axis.
/// Returns sprite variant 0-7, or -1 for invalid combinations.
const TRI_MASK_UP = [81]i8{
     0,  1,  3,  6,  7, -1, -1, -1, -1,
     0,  1,  2,  5,  6,  7, -1, -1, -1,
     0,  1,  2,  3,  5,  6,  7, -1, -1,
     0,  1,  2,  3,  4,  5,  6,  7, -1,
     0,  1,  2,  3,  4,  4,  5,  6,  7,
    -1,  0,  1,  2,  3,  4,  5,  6,  7,
    -1, -1,  0,  1,  2,  4,  5,  6,  7,
    -1, -1, -1,  0,  1,  2,  5,  6,  7,
    -1, -1, -1, -1,  0,  1,  4,  6,  7,
};

/// Compute the height-variant sprite index (0-7) for a tile given its center
/// height `m` and the heights of its lower (`left`) and lower-right (`right`)
/// neighbors. Matches the C++ up-triangle mask formula. Returns 4 (flat) on
/// invalid/edge combinations.
fn heightVariant(m: i32, left: i32, right: i32) u16 {
    const dl = @max(-4, @min(4, m - left));
    const dr = @max(-4, @min(4, m - right));
    const idx: usize = @intCast(4 + dl + 9 * (4 + dr));
    if (idx < 81 and TRI_MASK_UP[idx] >= 0) return @intCast(TRI_MASK_UP[idx]);
    return 4; // fallback: flat-terrain sprite
}

/// Map terrain type + height variant (0-7) to a PAK sprite index.
/// tri_spr[] groups (C++ AssetMapGround, base PAK 260):
///   Water  → offset 32 (PAK 292) — single sprite, variant ignored
///   Grass  → offsets  0-7  (PAK 260-267)
///   Tundra → offsets  8-15 (PAK 268-275)
///   Snow   → offsets 16-23 (PAK 276-283)
///   Desert → offsets 24-31 (PAK 284-291)
fn terrainSpriteId(t: Terrain, variant: u16) ?u16 {
    const base: u16 = switch (t) {
        .water  => return TERRAIN_SPRITE_BASE + 32,
        .grass  => 0,
        .tundra => 8,
        .snow   => 16,
        .desert => 24,
        // Not in original C++ terrain enum — no sprites available.
        .swamp, .lava, .mountain, .mountain2, .mountain_mined, .mountain_flagged => return null,
    };
    return TERRAIN_SPRITE_BASE + base + @min(variant, 7);
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

/// Vertical screen offset per unit of terrain height (original game: 4 px).
/// This is what produces the fake-2.5D relief: a vertex sitting on a tall tile
/// is pushed up the screen, so hills rise and valleys sink.
pub const HEIGHT_SCALE: f32 = 4.0;

/// Height (in tile units) at a map position, clamped to the map bounds so edge
/// tiles reuse the nearest in-bounds height instead of reading out of range.
fn heightAt(map: *Map, x: usize, y: usize) f32 {
    const xx: u16 = @intCast(@min(x, @as(usize, map.width) - 1));
    const yy: u16 = @intCast(@min(y, @as(usize, map.height) - 1));
    return @floatFromInt(map.getTileXY(xx, yy).height);
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

    // x, y, u, v, r, g, b, a  — standard sprite vertex layout.
    // u/v are direct atlas UV coordinates (pre-computed per vertex).
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
        // Each tile is a PARALLELOGRAM (32×20 px) rendered as two true triangles
        // (6 vertices, no sharing) with AXIS-ALIGNED 1:1 texture sampling.
        //
        //   A ────────── B        A = (lx,    ly)
        //    \  DOWN tri \        B = (lx+32, ly)
        //     \  (A,B,C) \        D = (lx-16, ly+20)
        //      D ──── C           C = (lx+16, ly+20)
        //       \ UP tri (A,D,C)
        //
        // The UVs (see below) reproduce the original renderer's behaviour of
        // blitting each 32×20 ground sprite axis-aligned and masking it to a
        // triangle. Because the sampling is axis-aligned 1:1 (not sheared onto
        // the parallelogram), adjacent same-terrain tiles continue the texture
        // seamlessly.
        const vertices = try allocator.alloc(Vertex, num_tiles * 6);
        defer allocator.free(vertices);
        const indices = try allocator.alloc(u16, num_tiles * 6);
        defer allocator.free(indices);

        const hw = TileWidth / 2.0; // 16

        for (0..map.height) |y| {
            for (0..map.width) |x| {
                const ti = y * map.width + x;

                // Screen-space top-left of this tile (C++: lx = col*32 - row*16).
                const lx = @as(f32, @floatFromInt(x)) * TileWidth -
                    @as(f32, @floatFromInt(y)) * hw;
                const ly = @as(f32, @floatFromInt(y)) * TileHeight;

                // Terrain and atlas lookup
                const tile = map.getTileXY(@intCast(x), @intCast(y));
                const m: i32 = @intCast(tile.height);
                const lh: i32 = if (y + 1 < map.height)
                    @intCast(map.getTileXY(@intCast(x), @intCast(y + 1)).height)
                else m;
                const rh: i32 = if (x + 1 < map.width and y + 1 < map.height)
                    @intCast(map.getTileXY(@intCast(x + 1), @intCast(y + 1)).height)
                else m;
                const variant = heightVariant(m, lh, rh);

                var eu: f32 = 0; var ev: f32 = 0;
                var euw: f32 = 0; var evh: f32 = 0;
                var has_tex = false;
                if (atlas) |a| {
                    if (terrainSpriteId(tile.terrain, variant)) |sid| {
                        if (a.get(sid)) |e| {
                            eu = e.u; ev = e.v; euw = e.uw; evh = e.vh;
                            has_tex = true;
                        }
                    }
                }
                const c: [4]f32 = if (has_tex) .{1,1,1,1} else terrainColor(tile.terrain);

                // AXIS-ALIGNED 1:1 texture mapping (matches the original masked-
                // sprite renderer). Each triangle samples the sprite as if it were
                // blitted axis-aligned at its own origin — NOT sheared onto the
                // parallelogram. This is what makes adjacent same-terrain tiles
                // tile seamlessly with no diagonal seams.
                //
                // Local UV = ((sx - origin_x)/32, (sy - origin_y)/20):
                //   DOWN triangle (origin = A=(lx,ly)):
                //     A(0,0)  B(1,0)  C(0.5,1)
                //   UP triangle   (origin = (lx-16, ly), i.e. shifted half-tile):
                //     A(0.5,0)  D(0,1)  C(1,1)
                // Atlas coords: actual = (eu + lu*euw, ev + lv*evh)
                // Each corner is a distinct grid vertex; offset its screen Y by
                // -HEIGHT_SCALE*height(that grid pos) for the 2.5D relief. Because
                // shared edges between tiles reference the SAME grid position,
                // their heights match and the mesh stays gap-free.
                //   A = (x,   y)    top-left
                //   B = (x+1, y)    top-right
                //   bottom-left  (lx-16) = (x,   y+1)
                //   bottom-right (lx+16) = (x+1, y+1)
                const hA = heightAt(map, x, y);
                const hB = heightAt(map, x + 1, y);
                const hBL = heightAt(map, x, y + 1);
                const hBR = heightAt(map, x + 1, y + 1);

                const xA = lx;             const yA = ly - HEIGHT_SCALE * hA;
                const xB = lx + TileWidth; const yB = ly - HEIGHT_SCALE * hB;
                const xD = lx - hw;        const yD = ly + TileHeight - HEIGHT_SCALE * hBL;
                const xC = lx + hw;        const yC = ly + TileHeight - HEIGHT_SCALE * hBR;

                const vi = ti * 6;
                const ii = ti * 6;

                // DOWN triangle A,B,C
                vertices[vi + 0] = .{ .x = xA, .y = yA,
                    .u = eu,             .v = ev,
                    .r = c[0], .g = c[1], .b = c[2], .a = c[3] };
                vertices[vi + 1] = .{ .x = xB, .y = yB,
                    .u = eu + euw,       .v = ev,
                    .r = c[0], .g = c[1], .b = c[2], .a = c[3] };
                vertices[vi + 2] = .{ .x = xC, .y = yC,
                    .u = eu + euw * 0.5, .v = ev + evh,
                    .r = c[0], .g = c[1], .b = c[2], .a = c[3] };

                // UP triangle A,D,C
                vertices[vi + 3] = .{ .x = xA, .y = yA,
                    .u = eu + euw * 0.5, .v = ev,
                    .r = c[0], .g = c[1], .b = c[2], .a = c[3] };
                vertices[vi + 4] = .{ .x = xD, .y = yD,
                    .u = eu,             .v = ev + evh,
                    .r = c[0], .g = c[1], .b = c[2], .a = c[3] };
                vertices[vi + 5] = .{ .x = xC, .y = yC,
                    .u = eu + euw,       .v = ev + evh,
                    .r = c[0], .g = c[1], .b = c[2], .a = c[3] };

                indices[ii + 0] = @intCast(vi + 0);
                indices[ii + 1] = @intCast(vi + 1);
                indices[ii + 2] = @intCast(vi + 2);
                indices[ii + 3] = @intCast(vi + 3);
                indices[ii + 4] = @intCast(vi + 4);
                indices[ii + 5] = @intCast(vi + 5);
            }
        }

        self.vertex_count = num_tiles * 6;
        self.index_count  = num_tiles * 6;

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

        // Vertex layout: x(0) y(4) u(8) v(12) r(16) g(20) b(24) a(28) — 8 floats, 32 bytes
        gl.bindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
        gl.bindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.ibo);
        const stride: i32 = @sizeOf(Vertex); // 8 * 4 = 32 bytes
        gl.enableVertexAttribArray(0); // a_position
        gl.vertexAttribPointer(0, 2, gl.GL_FLOAT, gl.GL_FALSE, stride, 0);
        gl.enableVertexAttribArray(1); // a_texcoord
        gl.vertexAttribPointer(1, 2, gl.GL_FLOAT, gl.GL_FALSE, stride, 8);
        gl.enableVertexAttribArray(2); // a_color
        gl.vertexAttribPointer(2, 4, gl.GL_FLOAT, gl.GL_FALSE, stride, 16);
        gl.drawElements(gl.GL_TRIANGLES, @intCast(self.index_count), gl.GL_UNSIGNED_SHORT, 0);
        gl.disableVertexAttribArray(0);
        gl.disableVertexAttribArray(1);
        gl.disableVertexAttribArray(2);
    }
};
