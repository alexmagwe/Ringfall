# TASKPLAN — Ringfall: First Playable Slice

Implements GDD build-order steps 1–4 (`RINGFALL-GDD.md` §15): scaffold, greybox tile kit, seeded maze generator, escape round loop, win screen. The output is a playtestable 8×8 tall maze — the "fun gate" build. Move this file into the repo root after step 1.

## Context you must know (do not skip)

- **Template**: https://github.com/REALEncryptal/Boil — Rojo + Wally + React (jsdotlua), feature-sliced. Features live in `src/features/<Feature>/`. A Lune splitter routes files by suffix into `build/`, which Rojo syncs alongside `src/`:
  - `*.server.luau` → `ServerScriptService.Features.<Feature>`
  - `*.client.luau` → `StarterPlayerScripts.Features.<Feature>`
  - `*.ui.luau` and plain `*.luau` → `ReplicatedStorage.Features.<Feature>`
- Modules named `*Service` / `*Controller` are auto-loaded and `Start()`ed by entry scripts, sorted by optional `Priority` (lower = earlier).
- Roblox Studio is already connected via MCP. "Run in Studio" below means: execute Luau via the Studio MCP run-code tool (or command bar).
- **Tiles are code-defined greyboxes** in this slice — declarative part lists built into Models at runtime. No manual Studio modeling. Art pass is a later, separate task.
- Units: 1 tile = **50×50 studs** footprint, walls **60 studs** tall (5 storeys × 12).

## Out of scope / Do NOT

- NO fog, NO warden, NO scrap/economy, NO shop, NO tools (grapple/ladder/zipline), NO checkpoints/persistence, NO rings 1–3, NO sewer layer, NO interiors beyond the single stair tile, NO minimap, NO mobile UI work, NO ProfileStore usage.
- Do NOT add packages beyond what Boil ships. Do NOT restructure Boil's folders or entry scripts. Do NOT hand-place any maze geometry in Studio.
- Do NOT make the generator non-deterministic: all randomness flows from one `Random.new(SEED)` instance.

---

## Step 1 — Scaffold the project

1. `cd /Users/kepla/Desktop/games`
2. `git clone https://github.com/REALEncryptal/Boil ringfall && cd ringfall && rm -rf .git && git init`
3. `rokit install` then `wally install`
4. Terminal 1: `lune run tools/split -- --watch`. Terminal 2: `rojo serve`
5. In Studio (via MCP): connect the Rojo plugin; confirm `ServerScriptService.Features`, `ReplicatedStorage.Features` exist after sync.
6. In Studio: set `Workspace.StreamingEnabled = true`. Delete any baseline/spawn parts the template places except one `SpawnLocation` (we reposition it in step 4).
7. Move this TASKPLAN into `ringfall/`.

**Accept:** `rojo serve` runs without error; Studio shows the Features folders; an empty Play session starts with no output errors.

## Step 2 — Maze constants

Create `src/features/Maze/Constants.luau` (shared module, plain `.luau`):

```luau
return {
	SEED = 1001,          -- season seed; changing it must change the whole maze
	GRID = 8,             -- 8x8 cells for the slice
	TILE_SIZE = 50,       -- studs, square footprint
	WALL_HEIGHT = 60,     -- studs
	WALL_THICKNESS = 3,
	EXTRA_LOOPS = 6,      -- internal walls knocked out after carving (GDD pillar: lost, not stuck)
	ROOF_TILE_CHANCE = 0.35, -- fraction of StairCourt-eligible cells
}
```

**Accept:** `require` it from the Studio command bar; prints a table with these keys.

## Step 3 — Greybox tile kit

Create `src/features/Maze/Tiles.luau`. It exports `Tiles.Build(tileName: string, rotation: number, cframe: CFrame, parent: Instance): Model`.

Canonical socket order is `{N, E, S, W}`, values `"Open" | "Wall"`. Author every tile in its canonical orientation; `rotation` is 0–3 quarter-turns clockwise applied as `cframe * CFrame.Angles(0, -rotation * math.pi/2, 0)`.

Tile set (exactly these 6; canonical sockets shown):

| Name | Sockets (N,E,S,W) | Geometry |
|---|---|---|
| `DeadEnd` | Open, Wall, Wall, Wall | 3 full walls |
| `Corridor` | Open, Wall, Open, Wall | 2 side walls |
| `Corner` | Open, Open, Wall, Wall | 2 walls forming an L |
| `TJunction` | Open, Open, Open, Wall | 1 wall |
| `Cross` | Open, Open, Open, Open | 4 corner pillars only (6×6×60 each) |
| `StairCourt` | Open, Open, Wall, Wall | Corner variant + interior stair (11 steps of 5×5 parts rising to y=59) + a 10-stud-wide rooftop walkway slab at y=59 spanning the tile, with 2-stud parapet lips |

Build rules:
- Each wall: one Part, `Size = Vector3.new(TILE_SIZE, WALL_HEIGHT, WALL_THICKNESS)` (rotate per side), `Anchored = true`, `Material = Enum.Material.Concrete`, `Color = Color3.fromRGB(70, 84, 90)`.
- Each tile: one floor Part `TILE_SIZE × 1 × TILE_SIZE` at y=0, same material, slightly darker color.
- All parts in a `Model` named `<tileName>_r<rotation>`, `Model.Parent = parent`. Set `ModelStreamingMode = PersistentPerPlayer`? **No** — leave default (streaming handles it).
- Part count per tile must stay under 30 in this slice.

**Accept:** In Studio run `Tiles.Build("StairCourt", 1, CFrame.new(0, 0, 0), workspace)` — model appears, stair is climbable in Play mode, rooftop walkable, part count ≤ 30.

## Step 4 — MazeService (generator)

Create `src/features/Maze/MazeService.server.luau` with `Priority = 5`.

Algorithm, in order, all using one `local rng = Random.new(Constants.SEED)`:

1. **Carve**: recursive backtracker over the `GRID × GRID` cell graph → per-cell openings bitmask (N=1, E=2, S=4, W=8).
2. **Loops**: pick `EXTRA_LOOPS` random interior cell-pairs that share an edge and are not yet connected; open both sides.
3. **Map cells → tile + rotation** by popcount of the openings mask:
   - 1 opening → `DeadEnd`; 2 opposite → `Corridor`; 2 adjacent → `Corner`; 3 → `TJunction`; 4 → `Cross`.
   - Rotation: find k in 0–3 such that rotating the tile's canonical socket list clockwise k times matches the cell's openings. Assert a k is found — a failed assert here means the socket table is wrong; fix the table, don't special-case.
   - Cells assigned `Corner` additionally become `StairCourt` with probability `ROOF_TILE_CHANCE` (same sockets, so no connectivity change).
4. **Stamp**: cell `(x, z)` → `CFrame.new((x-1) * TILE_SIZE, 0, (z-1) * TILE_SIZE)`, `Tiles.Build(...)` under a `workspace.Maze` folder.
5. **Spawn**: move the `SpawnLocation` to the center cell `(GRID/2, GRID/2)`, floor level.
6. **Exit**: pick the boundary cell farthest (by carved-path BFS distance, not euclidean) from spawn; punch its outer wall (skip building that wall segment) and place a 12×20×2 neon-green Part named `ExitGate` (`Anchored`, `CanCollide = false`) in the gap.
7. **Validate**: BFS from spawn cell to exit cell over the openings graph; `assert(reachable, "maze unsolvable")`. Also `assert` every cell has ≥1 opening.

**Accept:** Play in Studio: an 8×8 maze of 60-stud canyons exists, you spawn at center, BFS assert passes (no output errors), and changing `SEED` to 1002 and re-running produces a visibly different layout. Revert to 1001.

## Step 5 — EscapeService (round state)

Create `src/features/Maze/EscapeService.server.luau` (`Priority = 10`) and `src/features/Maze/Net.luau` (ByteNet namespace, plain `.luau`).

- `Net.luau`: ByteNet namespace `"Maze"` with packets `RunStarted {}` (server→client), `Escaped { timeSeconds: float32 }` (server→client), `Restart {}` (client→server). Follow the ByteNet packet-definition style already used in Boil's example feature — copy its shape exactly.
- EscapeService:
  - Per-player state: `startedAt: number?`.
  - A 25-stud-radius invisible zone Part around spawn; first time a player's character exits it, set `startedAt = os.clock()`, fire `RunStarted` to that player.
  - `ExitGate.Touched` (debounced per player): fire `Escaped` with `os.clock() - startedAt` (0 if never started), then anchor the player's character in place (`PrimaryPart.Anchored = true`).
  - On `Restart`: unanchor, teleport character to spawn, reset `startedAt`.
  - On respawn/death: reset `startedAt`.

**Accept:** Play, walk to the exit: touching `ExitGate` freezes you and (temporarily `print`) logs your time; a second touch does not double-fire.

## Step 6 — Win screen UI

Create `src/features/Maze/WinScreen.ui.luau` (React component) and `src/features/Maze/UIController.client.luau`.

- `WinScreen.ui.luau`: props `{ timeSeconds: number, onRestart: () -> () }`. Full-screen dim overlay, centered panel: title `ESCAPED`, the time as `M:SS.d`, and a `RUN IT BACK` TextButton calling `onRestart`. Follow the React component conventions of Boil's existing example `.ui.luau` exactly (createElement style, mounting, fonts). No custom styling beyond dark panel + white text.
- `UIController.client.luau`: listens for `Escaped` → mounts WinScreen; `onRestart` fires `Restart` and unmounts. Also a tiny always-on timer TextLabel (top-center) that starts on `RunStarted` — plain React state driven by `RunService.Heartbeat`-updated seconds.

**Accept:** Full loop in Play: spawn → timer starts when leaving the plaza zone → reach exit → win screen with correct time → RUN IT BACK returns you to spawn with timer reset. Zero errors in output.

## Step 7 — Fun-gate playtest checklist (manual)

Run through in Play mode; record answers in `PLAYTEST-notes.md` in the repo root:

1. Do the 60-stud canyons feel imposing at street level (camera doesn't clip badly, sightlines blocked)?
2. From a StairCourt rooftop, can you see the neon ExitGate glow / other rooftops, and does that create an "aha, that way" moment?
3. Time-to-escape for a first attempt: is it in the 5–12 min band? (If <3 min: raise GRID to 10. If >15: lower EXTRA_LOOPS is wrong — *raise* it to add shortcuts, or drop GRID to 7.)
4. Any spot where you were hard-stuck (not lost — stuck)? That's a tile-geometry bug; fix the tile.

This checklist is the gate: fog/warden/economy work does not start until 1, 2, 4 pass.

## Definition of Done

- [ ] `rojo serve` + splitter watch run clean; project opens and plays with zero output errors.
- [ ] `workspace.StreamingEnabled == true`.
- [ ] Maze is fully deterministic from `Constants.SEED` (same seed → identical layout across restarts).
- [ ] BFS solvability assert passes; no cell is sealed.
- [ ] All 6 tiles used somewhere in seed 1001's layout (print a tile-usage tally once and check; remove the print after).
- [ ] Full loop works: spawn → timer → escape → win screen → restart.
- [ ] No file outside `src/features/Maze/` was modified except moving the SpawnLocation and the StreamingEnabled flag.
- [ ] `PLAYTEST-notes.md` exists with the 4 checklist answers.
