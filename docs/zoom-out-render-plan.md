# Plan: Render All Visible Objects When Zoomed Out

## Problem

When the player zooms out far enough that the visible viewport is larger
than one full map period, the terrain (hex tiles) keeps rendering correctly
but **trees, rocks, buildings, roads, flags, and waves disappear** from
every part of the screen except the single copy of the map anchored near
the world origin.

## Symptoms

- Terrain (hex tiles): renders at up to 9 torus-wrapped offsets — always
  visible, even when fully zoomed out.
- Map objects (trees/rocks), buildings, roads, flags, waves: rendered via
  the CPU-side `culling.visibleTiles` iterator, which emits each tile **at
  most once** at its wrapped `[0,map)` position. When the viewport spans
  more than one map period, only the origin-anchored copy is drawn; all the
  other visible repeated copies of the map show terrain but no objects.

## Root-cause analysis

The rendering pipeline has two independent object-drawing paths:

1. **Terrain** (`map_renderer.render`): a static VBO built once in
   `rebuild`, drawn at up to 9 world-space offsets
   `{-mw,-mh … +mw,+mh}`. The 3×3 offset grid + per-offset visible-bounds
   culling means terrain is always covered wherever the camera looks,
   including the repeated copies that appear when zoomed out past one map
   period. This is why terrain survives a full zoom-out.

2. **Sprites** (`renderMapObjects`, `renderBuildings`, `renderRoads`,
   `renderWaves`): CPU-side passes that call
   `culling.visibleTiles(min_x,min_y,max_x,max_y,map,cull_visited)` and
   draw one sprite per yielded tile. The iterator:

   - computes a row/col range from the visible world rectangle,
   - **clamps the range to at most one full period**
     (`culling.zig:120-123`: `if (r_span >= map_h) clamped_row_lo = 0;
     clamped_row_hi = map_h-1`; same for columns),
   - emits each wrapped tile at most once (via the `visited` bitmap).

   The clamping is correct for *deduplication* (we never want to draw the
   same tile twice), but it means **only the `[0,map) × [0,map)` copy of
   the world ever receives sprites**. When the camera is zoomed out so the
   viewport covers, say, a 3×3 arrangement of repeated maps, the terrain
   fills all 9 copies but the sprites only fill the centre one — the other
   8 appear empty.

   This is the core bug: the sprite passes have no concept of the
   world-space **offset copies** that the terrain renderer uses.

### Secondary observations (not the primary cause)

- **No screen-space size culling.** When zoomed out to 0.25×, each tile is
  ~5×8 px and a tree sprite is ~10×15 px. These are sub-pixel-ish but the
  batcher still queues one quad per tile. On a 1024×1024 map fully zoomed
  out, that is up to ~1 M sprite submissions. The auto-flush path handles
  the `MAX_SPRITES` overflow (auto-flushes at 65 536), so sprites are not
  *dropped* — they are just drawn at the wrong (single) copy location and
  are tiny. This is a performance concern, not the disappearance cause.

- **`renderBuildings` does not use `visibleTiles` at all** — it iterates
  the buildings list and culls each building against `visibleWorldBounds`
  with a margin. So buildings at the origin copy are drawn, but like
  objects, they are not replicated at the other visible offset copies.
  Same root cause, different code path.

## Design

The fix must make the sprite passes replicate each visible tile/building
at **every world-space offset copy that intersects the viewport**, exactly
the way the terrain renderer does — while still drawing each (tile,
offset) pair at most once and keeping the back-to-front sort correct.

### Key insight

`visibleTiles` already computes the right set of *unique* tiles (one
period). What is missing is the **offset loop** around the sprite passes:
for each of the up-to-9 torus offsets that intersect the viewport, draw
the visible tiles translated by that offset. Because the tiles are
already deduplicated to one period, drawing them again at a different
offset is exactly the "repeated copy" we want — and it is cheap because
the same deduplicated tile set is reused per offset.

This mirrors the terrain renderer: static VBO (one period) drawn at up to
9 offsets.

### Approach: offset loop + offset-aware sprite submission

1. **Compute the active offset set once per frame** (shared by all sprite
   passes), identical to `map_renderer.render`'s 3×3 offset culling:
   `offsets = {(-mw,-mh)…(+mw,+mh)}` filtered against
   `camera.visibleWorldBounds()`. Typically 1–4 offsets; up to 9 when the
   viewport is larger than one map (the zoomed-out case we are fixing).

2. **Refactor `visibleTiles` to return a single-period tile iterator that
   does NOT depend on the camera bounds for clamping.** Instead:
   - The caller passes the *camera* visible bounds.
   - `visibleTiles` computes the row/col range, clamps to one period as
     today (dedup), and returns both the iterator and the active offset
     list (or the caller computes the offset list itself).
   - The iterator yields wrapped `(x,y)` tiles exactly once, as today.
   - Keep the existing tests passing.

3. **Sprite passes loop over offsets.** In `renderMapObjects`,
   `renderRoads`, `renderWaves`: for each active offset, translate every
   sprite's world position by `(off_x, off_y)` before submitting to the
   batcher. Because the tile set is one period and deduplicated, this
   draws each visible copy exactly once. The sort baseline must include
   the offset y so back-to-front order stays correct across copies.

   Concretely, the world position used for sprite submission and sort
   baseline becomes:
   ```
   wx = col*tw - row*hw + off_x
   wy = row*th - HEIGHT_SCALE*height + off_y
   ```

4. **`renderBuildings`**: same offset loop. For each active offset,
   translate each visible building's world position by `(off_x,off_y)`
   and draw. The existing per-building margin cull against
   `visibleWorldBounds` already determines visibility per offset (a
   building at offset `(mw,0)` is only visible if
   `wx+mw` is in bounds), so the offset loop naturally culls buildings
   whose offset copy is off-screen.

5. **Sort correctness.** `renderMapObjects` and `renderBuildings` sort by
   `baseline = row*th - HEIGHT_SCALE*height` (screen y). With offsets,
   `baseline` must become `row*th - HEIGHT_SCALE*height + off_y` so
   copies are ordered correctly relative to each other and to the
   terrain. The sort is per-offset-group or across all collected items;
   collecting all items across all offsets then sorting once is simplest
   and keeps the existing single-sort structure.

6. **Sort cache.** The existing `obj_cache_*` / `bld_cache_*` caches key
   on exact `visibleWorldBounds` equality. With the offset loop the
   cached sorted list must also be offset-aware. Simplest: cache the
   collected+sorted list keyed on `(bounds, offset_count, offsets)` — or
   invalidate whenever bounds or the active offset set changes. Since the
   offset set is derived purely from bounds + map size, keying on bounds
   alone remains correct as long as the cached items store their offset.
   Store `off_x, off_y` in `SceneItem`/`BldEntry` and bake it into the
   cached baseline.

7. **`drawMapObject` / `drawBuilding` / `drawShadowedSprite`**: add an
   `off_x, off_y` parameter (or pass via a thread-local / struct field)
   so the sprite is placed at the translated world position. Minimal
   signature change.

8. **`renderRoads` / `renderWaves`**: these already iterate
   `visibleTiles`; add the same offset loop. Road segments connect
   tiles, so both endpoints of each segment must be translated by the
   same offset. Waves are independent sprites per tile.

### LOD / quality reduction when zoomed out (optional, phase 2)

The primary goal is *correctness*: render the visible part of the map at
every zoom level. Once correct, we can reduce render cost when zoomed
out, since each tile is only a few pixels:

- **Sprite LOD skip**: when `camera.zoom` is below a threshold (e.g.
  0.5), skip sprites whose on-screen size would be < 1 px (trees/rocks
  become invisible anyway). This is a cheap early-out in the tile loop.
- **Wave skip**: waves are animated 48×19 sprites; at very low zoom they
  are noise. Skip the wave pass entirely when `zoom < 0.4`.
- **Road line width**: scale line width with zoom so roads remain
  visible (currently fixed 4 px world-space → sub-pixel at low zoom).
  Use `max(1, 4*zoom)` screen-space width.
- **Minimap-style aggregation** (future): at extreme zoom-out, draw the
  map as a coloured downsampled texture instead of per-tile sprites.
  This is a larger change and out of scope for this PR.

Phase 2 items are guarded by `camera.zoom` thresholds and do not change
the correctness of phase 1.

## Implementation phases

### Phase 1 — Correctness: render all visible copies when zoomed out

Files touched:

- `src/render/culling.zig`
  - Add `activeOffsets(visible_bounds, map_pixel_w, map_pixel_h)` helper
    returning the up-to-9 offsets that intersect the viewport (factored
    out of `map_renderer.render`).
  - `visibleTiles` unchanged in behaviour (still one-period dedup). Add a
    doc note that callers must loop offsets.
  - New tests:
    - `activeOffsets` returns 1 offset when viewport < one map.
    - `activeOffsets` returns 4–9 when viewport spans multiple periods.

- `src/render/app.zig`
  - `renderMapObjects`: collect `SceneItem` across all active offsets
    (store `off_x,off_y` in `SceneItem`), sort once, draw. Update
    `drawMapObject` to take `off_x,off_y`.
  - `renderBuildings`: loop offsets, translate building world pos, draw.
    Update `drawBuilding`/`drawShadowedSprite` signature.
  - `renderRoads`: loop offsets, translate both segment endpoints.
  - `renderWaves`: loop offsets, translate wave sprite.
  - Update sort caches to store offset and key on bounds (offset set is
    derived from bounds, so bounds-key remains valid).
  - Reuse the per-frame active offset list across all four passes
    (compute once in `renderFrame`).

- `src/render/map_renderer.zig`
  - Optionally refactor the 9-offset culling to call the shared
    `culling.activeOffsets` so the two paths cannot drift.

### Phase 2 — Quality/perf: LOD when zoomed out

- `src/render/app.zig`: add zoom thresholds to skip sub-pixel sprites,
  waves, and scale road line width.
- New tests for the skip thresholds (pure functions, no GL).

### Phase 3 — Tests & screenshots

- Add unit tests for `activeOffsets` and the offset-aware sprite
  collection (culling.zig).
- Add a screenshot test (via `--screenshot`) at minimum zoom (0.25) on a
  small map (64×64) and a large map (512×512) to capture the
  before/after. Compare object counts in the rendered region.
- Manual: run the game, zoom out fully, confirm trees/buildings/roads
  are visible in every repeated map copy.

## Risks & trade-offs

- **Sort cost**: collecting across all offsets means up to 9× the items
  to sort. In the zoomed-in case (1 offset) there is no change. In the
  zoomed-out case the per-tile work is already bounded by one period,
  so 9× a single period is still ≤ 9×map tiles — acceptable, and the
  sort is O(n log n) on the *visible* subset only.
- **Batcher throughput**: up to 9× sprites per frame when zoomed out.
  The auto-flush path already handles overflow; phase 2 LOD skip will
  bring this back down for the extreme case.
- **Sort cache correctness**: must verify the cached list includes
  offset info so a cache hit (camera idle) draws the same copies. Keying
  on `visibleWorldBounds` alone is safe because the offset set is a pure
  function of bounds + map size.
- **Torus wrap interaction**: the camera is wrapped to `[0,mw)×[0,mh)`
  every frame, so the visible bounds always straddle the origin; the
  3×3 offset grid already handles this for terrain. The sprite offset
  loop reuses the exact same logic, so wrapping stays consistent.

## Out of scope

- Changing the zoom range (currently 0.25–8.0). The fix should make 0.25
  fully usable; lowering the floor further can be a follow-up.
- Minimap-style extreme zoom-out rendering (phase 2+).
- Multithreaded sprite collection.

## Acceptance criteria

- [x] Zooming out to the minimum (0.25×) shows trees, rocks, buildings,
      roads, and flags in **every** visible copy of the map, not just the
      origin-anchored one. (Waves are skipped below zoom 0.40 by the LOD
      pass — terrain water colour still renders.)
- [x] No sprite is drawn twice at the same screen position (dedup via
      the single-period iterator + per-offset translation).
- [x] Zoomed-in rendering (1 offset) is unchanged in appearance and
      frame rate.
- [x] `zig build test` passes, including new `activeOffsets` and LOD tests.
- [x] Screenshot at 0.25× on 64×64 and 512×512 maps shows objects across
      the full viewport (see `docs/screenshots/zoom-out/`).

## Implementation notes

The fix was implemented in `feat/zoom-out-full-render`:

- `src/render/culling.zig`: added `OFFSET_GRID` + `activeOffsets()` helper
  (shared by terrain + sprite passes) with unit tests.
- `src/render/map_renderer.zig`: refactored the 9-offset culling to call
  `culling.activeOffsets` so terrain and sprites can never drift.
- `src/render/app.zig`:
  - `SceneItem`/`BldEntry` gained `off_x`/`off_y`; sort baselines now
    include the offset y so back-to-front order is correct across copies.
  - `renderMapObjects`/`renderBuildings`/`renderRoads`/`renderWaves` loop
    over `self.frame_offsets` (computed once per frame) and translate each
    sprite/segment to its offset copy.
  - `drawMapObject`/`drawBuilding` take `off_x,off_y`.
  - Sort caches key on `visibleWorldBounds` (the offset set is a pure
    function of bounds + map size, so bounds-key stays valid) and store
    the offset in each cached item.
  - LOD: `lodSkipObjects`/`lodSkipWaves` skip sub-pixel sprites and wave
    noise at extreme zoom-out (with unit tests).
- `src/main.zig` + `AppOptions`: added `--zoom <f32>` CLI flag and
  `initial_zoom` option so headless screenshots can capture a specific
  zoom level.
- `build.zig`: wired the render module tests into `zig build test`.