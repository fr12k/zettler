# Terrain Rendering Analysis — How Freeserf Renders Smooth Terrain

> Investigation into how the original **freeserf** (C++) and **freeserf.net** (C#)
> render the smooth, continuous, 2.5D terrain seen in the Settlers reference
> screenshot, and how the Zettler (Zig) port replicates it.
>
> Reference image:
> https://raw.githubusercontent.com/Pyrdacor/freeserf.net/master/images/Settlers_3.png

---

## TL;DR

The original game **does not blur or blend anything**. Its smooth look comes from
three exact, pixel-perfect mechanisms:

1. **Hard binary masks** clip each terrain sprite to a triangle (no anti-aliasing).
2. **Tiled 1:1 ground textures** sampled with wraparound, phase-aligned to screen,
   so same-terrain regions are seamlessly continuous.
3. **2.5D height relief** — every vertex is pushed up the screen by `4 × height`.

Terrain-*type* boundaries (grass→desert) stay **crisp diagonal lines**. What reads
as "smooth" is the relief plus perfect tiling — never softness.

---

## 1. The map is a triangle mesh, not a tile grid

Each map position `(col, row)` is a **mesh vertex**. Four neighboring positions
form a rhombus split into two triangles (`MapGeometry.cs`):

```
   A ______ B        A = (col,   row)
    /\    /          B = (col+1, row)
   /  \  /           C = (col,   row+1)
C /____\/ D          D = (col+1, row+1)

  up triangle   = A, C, D
  down triangle = A, B, D
```

Tile dimensions (`viewport.cc:40-41`, C# `RenderMap.cs`):

| Constant | Value |
|---|---|
| `MAP_TILE_WIDTH` | 32 px |
| `MAP_TILE_HEIGHT` | 20 px |
| `TILE_RENDER_MAX_HEIGHT` (C#) | 41 px (tallest slope mask) |

### Coordinate projection (`viewport.cc:2595`, `map_pix_from_map_coord`)

```
mx = TILE_WIDTH  * col - (TILE_WIDTH/2) * row
my = TILE_HEIGHT * row - 4 * height
```

The `-4*height` term is the entire 2.5D effect: higher ground is drawn higher on
the screen.

---

## 2. The sprite banks (`data.cc:58-61`, `data-source-dos.cc:62-65`)

| Asset | PAK base | Count | Type | Purpose |
|---|---|---|---|---|
| `map_mask_up` | **60** | **81** | Mask | up-triangle slope stencils (PAK 60–140) |
| `map_mask_down` | **141** | **81** | Mask | down-triangle slope stencils (PAK 141–221) |
| `path_mask` | 230 | 27 | Mask | path overlays |
| `map_ground` | **260** | **33** | Solid | terrain textures (PAK 260–292) |

The 33 `map_ground` sprites are the `tri_spr[]` set: 8 slope variants × 4 terrain
bands (grass/tundra/snow/desert) + 1 water sprite (offset 32 = PAK 292).

There are **81 masks per direction** — one per legal slope combination, indexed by
the height differences to the two base neighbors.

---

## 3. The mask is a hard binary stencil (`data-source.cc:109-135`)

`SpriteBase::get_masked` combines ground and mask with a bitwise AND:

```cpp
*pos++ = *s_pos++ & *m_pos++;     // masked_pixel = ground & mask
```

The mask pixels are only ever `0x00000000` (transparent) or `0xFFFFFFFF` (opaque),
so the result is either the ground pixel unchanged or fully transparent. **No alpha
blending, no anti-aliasing, no dithered edge.** The mask is a pure 1-bit stencil
defining the triangle/slope shape.

### Mask decode format (`data-source-dos.cc:364`, `SpriteDosMask`)

Run-length encoded, alternating transparent/opaque runs:

```cpp
while (readable()) {
  drop = pop<uint8_t>();  push 0x00000000 × drop   // transparent run
  fill = pop<uint8_t>();  push 0xFFFFFFFF × fill   // opaque run
}
```

---

## 4. The ground texture tiles with wraparound (`data-source.cc:124-133`)

The same `get_masked` loop reads the ground sprite with **wraparound**, so a small
ground texture fills a (taller) slope mask by repeating:

```cpp
if (s_pos >= s_end) { s_pos = s_beg; }   // wrap to top of ground sprite
...
s_pos += s_delta;                         // s_delta = ground_w - mask_w
```

Because every triangle starts reading at ground-pixel 0 at its mask origin, and
triangles are exactly 32 px wide = ground sprite width, ground-pixel 0 lands every
32 px across the screen. The texture therefore tiles **continuously and phase-
aligned** across all triangles of the same terrain — no seams.

---

## 5. The render walk (`viewport.cc:148-265`)

`draw_up_tile_col` / `draw_down_tile_col` walk **columns** of triangles. Two
interleaved sub-columns are offset by half a tile:

```
x_base = -(TILE_WIDTH/2)                       // -16
for col in 0..TILE_COLS+1:
    draw_up_tile_col  (pos, x_base,    ...)    // up   at col*32 - 16
    draw_down_tile_col(pos, x_base+16, ...)    // down at col*32
    x_base += TILE_WIDTH
```

Each triangle call computes the slope mask index and ground sprite, then blits the
masked ground at the integer screen position offset by `-4*height`:

```cpp
// draw_triangle_up (viewport.cc:69)
int mask  = 4 + m - left + 9*(4 + m - right);          // 0..80
Terrain t = type_up(move_up(pos));
int sprite = tri_spr[(t << 3) | tri_mask[mask]];        // ground sprite
draw_masked_sprite(lx, ly, MaskUp, mask, MapGround, sprite);

// draw_triangle_down (viewport.cc:108) — symmetric, +TILE_HEIGHT, MaskDown
```

`tri_mask[]` (two 81-entry tables) maps the raw slope index to one of 8 ground
slope variants; `tri_spr[]` (the 33-entry table) maps `terrain<<3 | variant` to a
ground sprite. Both tables are reproduced in `map_renderer.zig`.

---

## 6. freeserf.net (C#) — same idea on the GPU

`MaskedTriangleShader` samples a **terrain texture** and a **mask texture** and
multiplies them in the fragment shader (`varTexCoord`, `varMaskTexCoord`,
`RenderBuffer.cs`, `MaskedTriangleShader.cs`). Triangles are submitted as
axis-aligned quads with two texture-coordinate sets; the mask provides the
triangle alpha. Filtering is nearest — the look stays crisp pixel art.

---

## 7. How Zettler (this port) replicates it

| Mechanism | Original | Zettler |
|---|---|---|
| Mesh | per-position triangle mesh | per-tile 2 triangles (6 verts) |
| Tile size | 32×20 px | `TileWidth=32`, `TileHeight=20` |
| Projection | `col*32 - row*16`, `row*20 - 4h` | same (`map_renderer.zig`) |
| 2.5D relief | `-4*height` per vertex | `HEIGHT_SCALE=4` per corner, per grid pos |
| Ground sprites | `tri_spr[]`, PAK 260–292 | `terrainSpriteId()` + `TRI_MASK_UP` |
| Slope variant | `tri_mask[]` 0–80 → 0–7 | `heightVariant()` (up-triangle table) |
| Triangle shape | binary mask stencil | true-triangle geometry (equivalent — see §7.1); mask decoder available |
| Texture sampling | 1:1 tiled, wraparound | axis-aligned 1:1 UV per triangle |

### Architecture A (ours) vs B (original) — and why they're equivalent

There are two self-consistent ways to render this terrain:

| | **A — our GPU approach** | **B — original CPU approach** |
|---|---|---|
| Triangle shape | real 3-vertex triangle | axis-aligned 32×H quad + **binary mask stencil** |
| Slope | per-vertex `-4*height` geometry | mask shape encodes slope; quad offset by `-4*m` (center only) |
| Gaps between tiles | none — shared grid vertices align | none — the 81 slope masks tessellate exactly |
| Ground texture | sampled 1:1 over the 32×20 triangle | sampled 1:1, tiled with wraparound |

**Measured fact:** the `map_ground` sprites are exactly **32×20 px** (PAK entry =
10-byte header + 32×20 = 650 bytes, offset (0,0)). That is exactly the tile
bounding box, so our axis-aligned 1:1 UV already samples the ground at native
resolution — there is no scaling/squashing to correct.

**Conclusion:** the binary masks exist in the original *because it blits
axis-aligned rectangles on the CPU and needs a stencil to carve out the
triangle and its slope*. On the GPU we draw real triangles whose shared vertices
carry per-position heights, so the slope and gap-free tessellation come for free.

### 7.2 Implemented: masked-terrain shader (port of `MaskedTriangleShader`)

The terrain now renders through a faithful port of the C# masked-triangle pipeline
while keeping the gap-free per-vertex-height geometry (a deliberate hybrid that
takes the best of both architectures):

- **Mask decoder** — `bmp.zig: decodeMask` decodes the RLE `(drop, fill)` mask
  format into a white/transparent 1-bit stencil.
- **Mask loading** — `texture_atlas.zig: loadMaskRange` packs `AssetMapMaskUp`
  (PAK 60-140) and `AssetMapMaskDown` (PAK 141-221) into the atlas with edge
  padding; `AtlasEntry` now also stores the sprite hotspot offset.
- **Shader** — `Shader.createMaskedTerrain` mirrors the C# GLSL:
  ```glsl
  vec2 g  = fract(v_ground_local);                       // tile the 32x20 ground
  vec4 px = texture2D(tex, v_ground_region.xy + g*v_ground_region.zw);
  vec4 mk = texture2D(tex, v_mask_uv);                   // binary stencil
  if (px.a * mk.a < 0.5) discard;                        // carve the triangle
  gl_FragColor = vec4(px.rgb, 1.0);
  ```
- **Geometry** — each tile emits its two triangles (6 verts). The DOWN triangle
  uses the down mask (flat slope idx 40 = PAK 181), the UP triangle the up mask
  (PAK 100). Ground is sampled with `fract` (native-res, phase-aligned, tiling),
  not stretched.

### 7.3 Key finding: the masks are DITHERED, and need architecture B

Inspecting the flat up-mask (PAK 100) revealed it is **32×25 px** with a
**dithered** opaque region — per-row opaque counts are jagged (2, 2, 6, 5, 6, 10,
8, 12, …), not a clean triangle. This dithering is how the original softens
terrain-type transitions: a triangle's dithered edge lets the **previously drawn,
overlapping** neighbor triangle show through (the masks are 25 px tall but tiles
are 20 px apart, so quads overlap by 5 px, drawn back-to-front).

Applying such a mask as a hard `discard` on our **non-overlapping** true-triangle
geometry punches the dither holes straight through to the framebuffer clear color
(a light-blue `0.4,0.6,0.8`), producing a blue speckle over the whole map
(screenshot 16).

**Resolution:** our per-vertex-height geometry already clips each triangle
cleanly and gap-free, so the dithered stencil is not only redundant but harmful
here. The shader now samples the ground 1:1 over the triangle (clamped, no `fract`
wrap → no edge seam) and discards only on the ground's own alpha. Result:
pixel-exact NEAREST terrain, gap-free relief, no blue artifact. The mask decoder,
loader, and atlas entries remain in place.

**To actually use the dithered masks** (faithful dithered transitions) one must
switch terrain to **architecture B**: render each triangle as an overlapping
axis-aligned 32×25 quad, offset by `-4*centre_height`, selecting the slope-correct
mask index (0-80) so quads tessellate, and draw **back-to-front with alpha test**
so the dither blends into the neighbor rather than the background. That is a
self-contained future change; the mask infrastructure built here is exactly what
it needs.

### Height field matters most

The single biggest fidelity fix was **terrain generation**: the original height
field is smooth, so neighbors share heights and mostly use the flat ground variant,
tiling seamlessly. Fully random per-tile heights made `heightVariant()` pick a
different slope sprite for every tile — the chaotic checkerboard seen in early
screenshots. `Map.generateTerrain` now box-blurs the height field
(`src/core/Map.zig`).

---

## 7.4 Water and the dithered transition effect

Two related findings (measured + confirmed against `RenderMap.cs`):

**Water has no ground sprite.** PAK 292 (ground offset 32) is **empty** (`len = 0`).
The 32 real ground sprites are PAK 260–291 (grass/tundra/snow/desert × 8 slopes).
Water is instead drawn as **animated wave sprites** — `AssetMapWaves`, PAK 630+,
48×19 px, 16 animation frames selected by `((pos ^ 5) + (tick >> 3)) & 0xf` and
drawn from a separate atlas on top of a blue base. Our renderer now gives water a
solid blue fallback colour (`a_color.a = 0` path) since it has no sprite; the
animated waves overlay is a future addition.

**The dithered transitions are the masks, not blending.** Confirmed from C#:
each triangle samples a *single* terrain type — `TypeUp(MoveUp(pos))` for up
triangles, `TypeDown(MoveUpLeft(pos))` for down — there is **no** max() blend of
two terrains. The soft snow↔grass / water↔land bands in the reference come purely
from:

1. the **dithered 32×25 masks** (§7.3) carving each triangle with a stippled edge, and
2. triangles **overlapping** (25 px mask vs 20 px tile pitch) and drawn
   **back-to-front** (column traversal), so one terrain's dithered edge interleaves
   pixel-by-pixel over its neighbour.

That stipple where two different-terrain triangles meet *is* the transition effect.

### 7.6 Final approach: clean base + procedural dithered transition

The PAK dithered masks (32×25, overlapping) could not be made to tessellate
cleanly on a zoomed GPU framebuffer — they left either background-bleed holes or a
messy scattered transition band. Replaced with a controllable procedural dither:

- **Base pass** (`u_use_mask=0`, all tiles) — each tile is a clean, gap-free
  **parallelogram** (4 verts P,R,Dn,DR; UP=P,Dn,DR / DOWN=P,R,DR) with per-vertex
  height relief and the flat uniform ground sprite. No overlap → crisp diagonal
  terrain boundaries, smooth interiors, water = blue fallback.
- **Overlay pass** (`u_use_mask=1`, **boundary tiles only**) — each boundary tile's
  two triangles are **expanded ~1.45× from their centroid** so they bleed into the
  neighbour, tagged with barycentric coords. The shader computes an edge-fade
  (`coverage = min(bary)/0.16`, 1 in the core → 0 at the rim) and an **ordered
  dither** (interleaved gradient noise on `gl_FragCoord`); fragments are discarded
  where `coverage < dither`, revealing the base (neighbour) behind. Both terrains'
  expanded triangles interleave → a clean stippled transition, fully under our
  control (no PAK masks). The `MapRenderer` now keeps separate base and overlay
  VBO/IBO pairs.

  **Smoothness tuning.** The C# `MaskedTriangleShader` is confirmed to be a *hard*
  `discard` on the mask (no anti-aliasing) — its smooth-looking transitions come
  entirely from the **density gradient baked into the dithered mask sprites**
  (sparse near a triangle's tip, dense toward its base). We reproduce that with a
  wide bleed (`EXPAND = 1.7`) and a `smoothstep(0, 0.30, e)` density ramp on the
  edge-fade, so the ordered dither dissolves gradually instead of as a thin band.
  Two dials: `EXPAND` (band width) and the smoothstep upper bound (density falloff).

### 7.5 (superseded) architecture B + waves overlay

The terrain path is now full architecture B:

- **Geometry** (`map_renderer.zig`) — each tile emits two axis-aligned **32×25
  quads** (UP + DOWN), 8 verts / 12 indices. The UP quad sits at `lx-16`, the
  DOWN at `lx`, both offset `-4*height(P)` for the relief. Quads overlap (25 px
  mask vs 20 px pitch) and are emitted row-major = **back-to-front**.
- **Mask index** — `maskIndex()` computes the slope index 0-80 from the rhombus
  vertex heights (`TRI_MASK_UP`/`TRI_MASK_DOWN` give the 0-7 ground variant); the
  mask sprite is `PAK 60+idx` (up) / `141+idx` (down), falling back to the flat
  mask (100/181).
- **Shader** (`createMaskedTerrain`) — samples the dithered mask, `discard`s where
  `mk.a < 0.5`. Ground is tiled with `fract`; water (no sprite) uses the `a_color`
  blue fallback.
- **Two-pass, boundary-only overlay.** The C# reference draws masks on every
  triangle in a *single* pass because its up/down masks are exact complements —
  *every pixel belongs to exactly one triangle, no overlap*. Our quads instead
  **overlap** (32×25 vs 20 px pitch), so two problems appeared:
  (a) aligned dithers left pixels no quad covered → blue clear-colour speckle
  (screenshot 18); (b) within a uniform region the overlapping dithers mixed the
  texture → grainy snow/tundra interiors (screenshot 19).
  Fixed with two passes over the VBO:
  - **Pass 1** (`u_use_mask=0`, IBO = all tiles): solid base, no discard, fills
    every pixel → no blue bleed.
  - **Pass 2** (`u_use_mask=1`, IBO = **boundary tiles only**): the dithered
    overlay, drawn only where a tile borders a different terrain
    (`isTerrainBoundary`). Its discard reveals the solid base → stippled
    transitions. Uniform interiors are skipped, so they show only the clean base —
    no overlapping-dither grain.
- **Waves** (`app.zig renderWaves`) — `AssetMapWaves` PAK 630-645 loaded into the
  atlas; water tiles draw the frame `((pos^5)+(tick>>3))&0xf`, animated, as a
  transparent overlay. Only **interior** water animates (a tile whose right / down /
  down-right footprint neighbours are also water) so the 48 px wave sprite never
  spills onto shoreline grass.
- **Uniform ground texture** — the ground sprite uses the **flat variant (4)** for
  every tile, so each terrain region is one tiled texture. Driving the ground
  sprite by per-tile slope variant made snow/tundra interiors *grainy* (those bands
  sit at the renormalised height extremes, so neighbours picked different sprites
  that the dither then mixed). Relief still comes from the quad Y offset and the
  slope MASK shape — just not the ground texture.

## 8. Key source references

**freeserf (C++)** — `/tmp/freeserf/src/`
- `viewport.cc:40-41` — tile dimensions
- `viewport.cc:50-67` — `tri_spr[]` ground sprite table
- `viewport.cc:69-146` — `draw_triangle_up` / `draw_triangle_down` + `tri_mask[]`
- `viewport.cc:148-265` — column render walk
- `viewport.cc:2595` — `map_pix_from_map_coord` (projection + `-4*h`)
- `data.cc:58-61` — sprite bank counts (81/81/27/33)
- `data-source-dos.cc:62-65` — PAK bases (60/141/230/260)
- `data-source-dos.cc:364` — `SpriteDosMask` RLE decode
- `data-source.cc:109-135` — `get_masked` (binary AND + ground wraparound)
- `gfx.cc:226` — `draw_masked_sprite`

**freeserf.net (C#)** — github.com/Pyrdacor/freeserf.net
- `Freeserf.Core/Render/RenderMap.cs` — terrain render logic
- `Freeserf.Core/MapGeometry.cs` — rhombus/triangle layout
- `Freeserf.Renderer/MaskedTriangleShader.cs` — terrain×mask fragment shader
- `Freeserf.Renderer/RenderBuffer.cs` — vertex/UV/mask-UV buffers
- `Freeserf/CoordinateSpace.cs` — map↔screen transforms

---

## 9. Iteration history (Zettler)

| Screenshot | State | Problem |
|---|---|---|
| 7 | solid color diamonds | water/mountain had no sprites; flat color fallback |
| 11 | 32×40 diamonds | wrong tile shape (diamond, double height) |
| 12 | screen-space tiled | up/down triangles used different terrains → triangle look |
| 13 | parallelogram 1:1 | random heights → every tile a different slope sprite |
| 14 | smooth heights + stretch UV | sheared sprite caused faint diagonal seams |
| 15 | axis-aligned 1:1 UV | seams gone; flat (no relief) |
| 16 | + 2.5D relief + bilinear terrain | rolling hills; bilinear softens (non-original) |
| 17 | masked shader, NEAREST (geometry-clipped) | clean but water lost (color fallback dropped) |
| (current) | **architecture B** + waves overlay | overlapping dithered masked quads, back-to-front, animated water |

---

## 10. 2.5D fake perspective and building shadows

The isometric "fake 2.5D" is three things (confirmed in C# `freeserf.net` and C++
`/tmp/freeserf`): (1) a height offset `screen_y = row*20 - 4*height`, (2)
back-to-front painter's order, (3) a semi-transparent shadow sprite under each
object.

**Height offset (1)** was already present — terrain (`map_renderer.zig`, per-vertex
`ly - 4*h`) and buildings (`app.zig`, `wy = row*20 - 4*height`).

**Building shadows (3)** — implemented:
- `bmp.zig: decodeOverlay` decodes `SpriteTypeOverlay` shadow sprites (RLE
  `(drop,fill)` like masks, fill → flat black at alpha 128 ≈ 50%). The original
  fills with `palette[0x80]` at alpha `0x80`.
- `texture_atlas.zig: loadOverlaySprites` packs them.
- Shadow PAK id = building PAK id + 250 (`AssetMapObject` base 1250 vs
  `AssetMapShadow` base 1500; both share the per-building offsets).
- `app.zig drawBuilding` draws the shadow first then the building, each at the
  building's map pixel + the sprite's own hotspot offset (`off_x/off_y`, matching
  the original `use_off`) so shadow and building align.

**Back-to-front order (2)** — `renderBuildings` now sorts completed buildings by
screen baseline (`wy` ascending) before batching, so nearer (lower) buildings and
their shadows occlude farther ones. (The original uses
`baseline = y + height + offset`; sorting by the tile screen-Y is the practical
equivalent here.)

Out of scope (future): map objects (trees/stones) + their shadows (need object
data in `Map.Tile`), serfs/flags + `AssetSerfShadow` (PAK 4), and
unfinished-building construction frames.
