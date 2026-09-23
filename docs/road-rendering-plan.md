# Road Placement & Rendering — Findings & Implementation Plan

Research into how the original Settlers 1 / freeserf places and renders roads,
and a concrete plan to bring zettler's road system up to parity.

---

## Part 1 — Findings: How freeserf does it

### 1.1 Data model: per-tile 6-bit `paths` bitmask

In freeserf every map tile stores a `paths` byte whose **low 6 bits are
direction flags** (`map.h`):

```cpp
struct GameTile {
  uint8_t paths;   // bit 0=Right, 1=DownRight, 2=Down, 3=Left, 4=UpLeft, 5=Up
  bool   idle_serf;
  ...
};

unsigned int paths(MapPos pos)      { return game_tiles[pos].paths & 0x3f; }
bool   has_path(MapPos pos, Dir d)  { return BIT_TEST(paths, d); }
void   add_path (MapPos pos, Dir d) { game_tiles[pos].paths |= BIT(d); }
void   del_path (MapPos pos, Dir d) { game_tiles[pos].paths &= ~BIT(d); }
```

**A road segment between tile A and tile B sets TWO bits**: the forward
direction on A and the reverse direction on B. So "is there a road leaving
this tile to the right?" is a single bit test — no neighbour lookup needed.

The 6 `Direction` values (map-geometry.h):
```
Right=0, DownRight=1, Down=2, Left=3, UpLeft=4, Up=5
reverse_direction(d) = (d + 3) % 6
```

### 1.2 The `Road` object (interface.h / map.cc)

A road under construction is just a **source position + a list of directions**:

```cpp
class Road {
  MapPos begin;            // source flag position
  std::list<Direction> dirs;  // the segments, in order
  static const size_t max_length = 256;

  bool is_valid() const;          // begin != bad_map_pos
  void start(MapPos s);           // begin = s
  bool extend(Direction d);       // dirs.push_back(d)
  bool undo();                    // dirs.pop_back(); invalidate if empty
  bool is_undo(Direction d) const;// dirs.back() == reverse(d)
  MapPos get_end(Map*) const;     // walk all dirs from begin
  bool is_valid_extension(Map*, Direction d) const;  // no self-crossing
};
```

- `is_undo(d)` — if the player pushes the direction opposite to the last
  segment, it's an undo (backspace), not a new segment.
- `is_valid_extension` — checks the extended end isn't already on the road
  (prevents self-intersection).

### 1.3 Placement validation — `Map::is_road_segment_valid` (map.cc:572)

A single segment from `pos` in direction `dir` is valid iff:

1. The destination tile has **no existing paths** (unless it's a flag):
   `(paths(other) != 0 && obj(other) != Flag)` → reject.
   *(A road may only merge into a flag, not into the middle of another road.)*
2. The destination's map-space is passable:
   `map_space_from_obj[obj] < SpaceSemipassable`.
3. **Same owner** on both tiles: `has_owner(other) && owner(other)==owner(pos)`.
4. **Water continuity**: if one tile is in water and the other isn't, at least
   one end must be a flag (`has_flag(pos) || has_flag(other)`).
   *(Prevents a road dipping into water mid-segment; water roads only connect
   flag-to-flag.)*

### 1.4 Road construction — `Map::place_road_segments` (map.cc:596)

Walks the road's direction list from the source, and for each segment:

```cpp
if (!is_road_segment_valid(pos, dir)) { /* backtrack & abort */ }
game_tiles[pos].paths                 |= BIT(dir);
game_tiles[move(pos, dir)].paths      |= BIT(reverse(dir));
pos = move(pos, dir);
```

If any segment fails, it backtracks clearing the bits already set and returns
false. **Both endpoints get a path bit** — this is what makes rendering and
serf pathfinding O(1) per tile.

### 1.5 Full road build — `Game::can_build_road` + `Game::build_road`

`can_build_road` (game.cc:806) re-validates the *whole* road from the player's
flag to the destination and classifies it:

- Source must be owned by the player and have a flag.
- Every segment passes `is_road_segment_valid`.
- Owner must be the player on every tile.
- **Only the destination may have a flag** (no mid-road flags).
- Tracks whether the road goes through **water** (bit 1) or **ground**
  (bit 0); rejects if it goes through *both* (a road can't mix land & water).

`build_road` (game.cc:858) then:
1. Calls `can_build_road` → gets `dest` + `water_path`.
2. Requires `has_flag(dest)`.
3. `map->place_road_segments(road)` — sets the path bits.
4. `src_flag->link_with_flag(dest_flag, water_path, length, in_dir, out_dir)`
   — connects the two flags in the transport graph (direction + length +
   water flag, used by the transporter-serf scheduling).

### 1.6 Interactive construction (interface.cc)

The player drives road building one segment at a time:

- **`build_road_begin()`** — `building_road.start(cursor_pos)`.
- **`build_road_segment(dir)`** — `building_road.extend(dir)`; if the road is
  now complete (reaches a flag), call `game->build_road()`; otherwise just
  keep extending for preview.
- **`remove_road_segment()`** — `building_road.undo()`; abort if invalid.
- **`extend_road(road)`** — apply a whole found path (from the pathfinder) one
  segment at a time via `build_road_segment`.
- **`build_road()`** — finalise: `game->build_road(building_road, player)`.
- **`determine_map_cursor_type_road()`** — for each of the 6 directions from
  the road's current end, compute `is_road_segment_valid` &&
  `is_valid_extension` → a 6-bit `building_road_valid_dir` mask telling the UI
  which directions are clickable.

**Click-to-pathfind** (viewport.cc event handler): if the player clicks a
flag while building a road, `pathfinder_map(map, end, click_pos,
&building_road)` is run and the resulting `Road` is fed to `extend_road`.
The pathfinder is A* with terrain-height walking cost, respecting
`is_road_segment_valid` and avoiding the in-progress road's own tiles.

### 1.7 Rendering — `Viewport::draw_paths_and_borders` (viewport.cc:544)

For every visible tile, for each of the **3 forward directions**
(Right, DownRight, Down — to avoid drawing each segment twice):

```cpp
if (map->has_path(pos, d))      draw_path_segment(lx, y_base, pos, d);
else if (owner differs)         draw_border_segment(lx, y_base, pos, d);
```

**`draw_path_segment` (viewport.cc:394)** — this is the heart of road
rendering. For the segment from `pos` in direction `dir`:

1. **Compute height-difference geometry.** `h_diff = h(pos) - h(move(pos,dir))`.
   Depending on `dir` it also computes a second height difference `h_diff_2`
   from the *cross-slope* tiles (the two triangles adjacent to the edge the
   road crosses). This gives the road its 3D slope.
2. **Pick a mask sprite index:**
   `mask = h_diff + 4 + dir*9`  →  an index 0..44 into `AssetPathMask`.
   The mask is a 1-bit-per-pixel shape that *stencils* the road strip so it
   follows the triangle-edge silhouette at that slope/direction.
3. **Pick a ground-texture sprite index** based on the cross-slope
   (`h_diff_2`) and the **terrain type** of the two triangles the road
   crosses:
   - `h_diff_2 > 4`  → sprite 0 (steep)
   - `h_diff_2 > -6` → sprite 1 (gentle)
   - else            → sprite 2 (flat)
   - water terrain   → sprite 9 (always the water-road texture)
   - snow            → sprite += 6
   - desert          → sprite += 3
   This selects which of the 9 `AssetPathGround` textures to use
   (grass/desert/snow × steep/gentle/flat).
4. **Draw masked:**
   `frame->draw_masked_sprite(lx, ly, AssetPathMask, mask,
                              AssetPathGround, sprite)`
   — the mask sprite's alpha *gates* the ground sprite's pixels, so only the
   road-shaped part of the ground texture shows.

**Construction preview:** if `is_building_road()`, the temporarily-placed
segments (the `building_road` dirs, not yet committed) are drawn the same way
— `draw_path_segment` is called for each pending segment so the player sees
the actual road shape before confirming.

### 1.8 Sprite assets (confirmed present in SPAE.PA)

| Asset | PAK base | Type | Count | Size | Role |
|-------|----------|------|-------|------|------|
| `AssetPathMask`  | **230** | Mask (1-bit) | 16 | 32×5..32×37 | road-shape stencils per slope/dir |
| `AssetPathGround`| **300** | Solid       | 9  | 32×20       | road surface textures (grass/desert/snow × slopes) |

Dumped from the actual file: PAK 230-245 are the masks (varying heights
because the mask is the triangle-edge strip), PAK 300-308 are the 9 solid
32×20 ground textures. `draw_masked_sprite` (gfx.cc:226) composites them at
draw time: `ground.get_masked(mask)` produces a cached combined image.

### 1.9 Border rendering (adjacent owners)

When two neighbouring tiles have **different owners** and no road, freeserf
draws a `draw_border_segment` — a thin coloured line marking territory. This
shares the loop with road drawing. (Out of scope for the first road PR but
noted for completeness.)

---

## Part 2 — Zettler's current state

| Aspect | Zettler now | freeserf | Gap |
|--------|-------------|----------|-----|
| Tile road storage | `has_road: bool` (single flag) | `paths: u8` 6-bit bitmask | **Must add `paths` field** |
| Road object | none (just `path[128]u8` in RoadBuilder) | `Road{begin, dirs[]}` with extend/undo/valid | Add a proper `Road` struct |
| Segment validity | "not a building" | 4-rule `is_road_segment_valid` | Port the 4 rules |
| Placement | `Game.buildRoad` sets `has_road=true` on intermediates, no per-direction bits | `place_road_segments` sets 2 bits/segment | Rewrite to use `paths` |
| Flag linking | sets `next[dir]`/`length[dir]` (both ends) ✓ | `link_with_flag` + water flag | Add `water_path` tracking |
| Pathfinder | A* exists but **path reconstruction is broken** (acknowledged in RoadBuilder comment) | A* with height cost, road-segment-valid, avoids in-progress road | **Fix or port** |
| Rendering | `addLine` brown lines between road/flag tile centers (flat, no slope, no sprites) | masked sprite compositing with 3D slope | **Replace with sprite rendering** |
| Path sprites | not loaded | PAK 230 + 300 | Load into atlas |
| Masked draw | not implemented | `draw_masked_sprite` | Implement mask compositing |
| Construction preview | single green/red straight line | per-segment masked preview | Use same draw_path_segment |
| Valid-direction feedback | none | `building_road_valid_dir` 6-bit mask | Compute & show |

### Key blockers

1. **`Tile.has_road: bool` cannot represent which directions a road goes.**
   This makes correct rendering (which edge?), serf pathfinding (which way
   can I walk?), and merge-into-flag impossible. This is the foundational
   change everything else depends on.
2. **Pathfinder path reconstruction is broken** — the `parent` index logic
   in `Pathfinder.zig:180` stores an invalid index. Road building currently
   works around this with a greedy walker, but greedy can't route around
   obstacles/mountains and produces ugly roads.
3. **No masked-sprite compositing** in the renderer — `SpriteBatcher` only
   does textured quads. Roads need a mask×ground composite.

---

## Part 3 — Implementation Plan

Sequenced so each phase is independently testable and the game stays
buildable throughout. Estimates assume the franky-agent fork's existing
patterns (build.zig steps, `tools/` inspection exes, `src/core/` + `src/render/`).

### Phase 0 — Data model: `Tile.paths` bitmask  *(core, ~1-2h)*

**Files:** `src/core/Map.zig`, `src/core/types.zig` (none), all callers.

- [ ] Add `paths: u6 = 0` to `Tile` (replace `has_road: bool`).
      Keep a computed `hasRoad()` helper: `paths != 0`.
- [ ] Add `Map.hasPath(pos, dir)`, `addPath(pos, dir)`, `delPath(pos, dir)`,
      `paths(pos)` mirroring freeserf. Bit index = `@intFromEnum(dir)`.
- [ ] Add `Map.isRoadSegmentValid(pos, dir)` porting the 4 rules from
      `map.cc:572` (dest paths empty unless flag; passable space; same owner;
      water-continuity). Needs `Map.spaceFromObj` / `Space` enum (can be a
      simplified `isPassable(pos)` initially).
- [ ] Update `Game.buildRoad` to call a new `Map.placeRoadSegments(from, dirs)`
      that sets both bits per segment (port `place_road_segments`), replacing
      the `has_road = true` loop. Backtrack-on-failure.
- [ ] Update `renderRoads` and any `has_road` readers to use `paths`/`hasPath`.
- [ ] Update serialize (`Savegame.zig` / `State.zig`) for the field rename.
- [ ] **Test:** `buildRoad` sets exactly the right bits on a 3-segment road;
      `hasPath` true on both ends of each segment; water-segment rejection.

### Phase 1 — `Road` struct + segment-by-segment building  *(core, ~1-2h)*

**Files:** new `src/core/Road.zig`, `src/render/ui/RoadBuilder.zig`, `src/core/Game.zig`.

- [ ] Port freeserf `Road` to `src/core/Road.zig`: `begin: MapPos`,
      `dirs: std.ArrayList(Direction)` (or fixed `[256]u8` + len),
      `extend/undo/isUndo/isValidExtension/getEnd/hasPos`.
- [ ] Rewrite `RoadBuilder` to hold a `Road` instead of a raw `path[]`:
      - `tryStartAt` → `road.start(pos)`.
      - `updatePath` stays (for the preview pathfinder) but feeds
        `road.extend` per step.
      - Add `canExtend(dir)` → `isRoadSegmentValid && isValidExtension`.
      - Add `undo()` for backspace.
- [ ] Add `Game.canBuildRoad(road, player)` (port the whole-road validation +
      water/ground classification). `buildRoad` calls it before
      `placeRoadSegments`.
- [ ] Add `water_path` to flag linking (`FlagState` already has `next`/`length`;
      add a `water: [6]bool` or a bit in `length`).
- [ ] **Test:** undo removes the last segment; self-crossing rejected;
      mid-road flag rejected; mixed water/ground rejected.

### Phase 2 — Fix the pathfinder  *(core, ~2-3h)*

**Files:** `src/core/Pathfinder.zig`.

- [ ] Fix the A* parent tracking: store `parent: ?u32` as a valid index into
      `open_list` at insertion time, or use a separate `came_from:
      AutoHashMap(MapPos, MapPos)` + `came_dir: AutoHashMap(MapPos, Direction)`.
      The hashmap approach is simpler and matches freeserf's closed-list.
- [ ] Use freeserf's cost model: `walk_cost[h_diff] = {255,319,383,447,511}`
      + `heuristic` with `dist_x`/`dist_y`/`height`.
- [ ] Neighbour validity = `isRoadSegmentValid(pos, d)` (not just
      terrain-walkable) so the pathfinder only proposes valid road segments.
- [ ] Support the `building_road` exclusion (don't route through the
      in-progress road's tiles except endpoints).
- [ ] Return a `Road` (dirs list), not `Path` steps.
- [ ] Wire into `RoadBuilder.updatePath`: replace the greedy `bestStep` with
      `pathfinder_map(map, start, cursor, &road)`.
- [ ] **Test:** routes around a water tile; routes around a mountain;
      prefers shorter over longer; broken reconstruction fixed (path actually
      connects start→end).

### Phase 3 — Path sprite loading + masked compositing  *(render, ~2-3h)*

**Files:** `src/render/texture_atlas.zig`, `src/data/bmp.zig`,
          `src/render/sprite_batcher.zig`, `src/render/Renderer.zig`.

- [ ] **Decode mask sprites.** `bmp.zig` `BmpDecoder` currently handles Solid
      and Transparent. Add `decodeMask(data) → Sprite` (1-bit alpha-only,
      matches freeserf `SpriteDosMask`: RLE drop/fill but pixels are
      alpha=255, the rest alpha=0). PAK 230-245.
- [ ] **Load path sprites into the atlas:** `atlas.loadRange(&pak, &decoder,
      230, 246)` (masks) and `300, 309` (ground, solid). Store mask entries
      with a flag so the batcher knows to composite.
- [ ] **Implement masked compositing.** Two options:
  - **(A) Pre-composite at load time** (freeserf's approach): for each
    (mask, ground) pair the renderer will request, call
    `ground.get_masked(mask)` → one RGBA sprite → cache in atlas under a
    synthetic id like `0xC000 | (mask<<6) | ground`. Pro: zero per-frame
    cost, fits the existing `SpriteBatcher`. Con: up to 45 masks × 9 grounds
    = 405 composites, but only a subset is used (3 dirs × ~5 slopes × 3
    terrains ≈ 45).
  - **(B) Per-frame mask in shader:** add a `mask_texture` + `mask_uv` to the
    batcher vertex and discard fragments where mask alpha = 0 in the fragment
    shader. Pro: no pre-composite. Con: shader change + second texture bind.
  - **Recommend (A)** — matches freeserf, keeps the batcher simple, 45
    sprites is tiny.
- [ ] Add `Atlas.getRoadSprite(mask_index, ground_index) → ?AtlasEntry` that
      lazily composites & caches.
- [ ] **Test (visual):** dump one composite to BMP via the existing
      screenshot tool to confirm the mask×ground looks like a road strip.

### Phase 4 — Road rendering with slope  *(render, ~2-3h)*

**Files:** `src/render/app.zig` (`renderRoads`).

- [ ] Replace `addLine` road drawing with a port of
      `Viewport::draw_path_segment`:
      - For each visible tile, for each of the 3 forward dirs, if
        `hasPath(pos, d)`: compute `h_diff`, `h_diff_2` (cross-slope),
        `mask = h_diff + 4 + dir*9`, `ground = terrainSprite(t1, t2, h_diff_2)`.
      - Look up `atlas.getRoadSprite(mask, ground)`.
      - Compute `lx, ly` with the per-direction height lift (matching
        freeserf's switch: Right subtracts `4*max(h1,h2)+2`, DownRight
        subtracts `4*h1+2`, Down shifts `lx -= 16` and subtracts `4*h1+2`).
      - Queue the composite sprite via `addSprite`.
- [ ] Keep the torus-offset replication (existing `frame_offsets` loop).
- [ ] Render the construction preview using the *same* `draw_path_segment`
      over the pending `Road.dirs` (so the preview looks like the real road,
      not a straight line).
- [ ] Remove the brown `addLine` road code and the green/red preview line.
- [ ] **Test (visual):** roads on flat terrain render as proper strips;
      sloped roads follow the terrain; water-road uses sprite 9; roads wrap
      across map edges.

### Phase 5 — Valid-direction feedback + UX polish  *(render/ui, ~1-2h)*

**Files:** `src/render/ui/RoadBuilder.zig`, `src/render/app.zig`.

- [ ] Compute `valid_dir: u6` mask each frame from the road's current end
      (`isRoadSegmentValid && isValidExtension` for each of 6 dirs).
- [ ] Draw small arrow indicators (or highlight the 3 forward triangle-edges)
      on the end tile for the valid directions, green; invalid ones dim.
- [ ] Backspace / right-click → `road.undo()`.
- [ ] Esc → cancel (already exists).
- [ ] Clicking a flag while building → run pathfinder → `extend_road`.
      (Replaces the current "click second flag = build immediately".)
- [ ] **Test:** can build a road around a mountain; undo works; can't build
      into water without a flag at the far end.

### Phase 6 — (Optional) Border rendering  *(render, ~1h)*

- [ ] Port `draw_border_segment` for the owner-difference case in the same
      loop. Low priority; mostly cosmetic.

---

## Sequencing & dependencies

```
Phase 0 (paths bitmask) ──┬─→ Phase 1 (Road struct + build)
                          │
                          └─→ Phase 2 (pathfinder fix) ──→ Phase 5 (UX)
                          
Phase 3 (sprites + mask) ──→ Phase 4 (slope rendering) ──→ Phase 5
```

- Phase 0 is the prerequisite for everything.
- Phases 1+2 (core logic) and Phase 3 (render data) can proceed in parallel
  after Phase 0.
- Phase 4 needs Phase 3.
- Phase 5 needs Phases 1, 2, 4.

**Total estimate:** ~10-14 hours of focused work, deliverable as 3-4 PRs
(0+1+2 as one "core roads" PR, 3+4 as "road rendering", 5 as "UX polish").

---

## References (freeserf source, master branch)

- `src/map.h:281` — `GameTile.paths` + `has_path/add_path/del_path`.
- `src/map.h:36` — `Road` class declaration.
- `src/map.cc:572` — `is_road_segment_valid` (4 rules).
- `src/map.cc:596` — `place_road_segments` (bit setting + backtrack).
- `src/map.cc:953` — `Road::get_end/is_valid_extension/is_undo/extend/undo`.
- `src/map-geometry.h:50` — `Direction` enum + `reverse_direction`.
- `src/game.cc:806` — `can_build_road` (whole-road validation + water).
- `src/game.cc:858` — `build_road` (place + link flags).
- `src/interface.cc:331` — `determine_map_cursor_type_road` (valid_dir mask).
- `src/interface.cc:518-620` — `build_road_begin/segment/end/extend`.
- `src/viewport.cc:394` — `draw_path_segment` (mask + ground + slope math).
- `src/viewport.cc:544` — `draw_paths_and_borders` (iteration + preview).
- `src/gfx.cc:226` — `draw_masked_sprite` (mask×ground compositing).
- `src/pathfinder.cc` — A* with `walk_cost[h_diff]`, road-segment validity.
- `src/data-source-dos.cc:64-66` — `path_mask` (230) / `path_ground` (300).