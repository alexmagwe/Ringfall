# TASKPLAN — Verticality Routing (Districts + Rooftop Crossings)

Makes the maze a 3D routing puzzle: the street level is split into sealed
districts; the only way between them is up a tower, across a rooftop bridge over
the dividing wall, and down the far side. Knowing the exit *direction* (a sky-
beam) no longer gives you the *path*. This is the "make wandering fun" pass and
the first real challenge layer. Evolves `src/features/Maze/`.

## Design decisions (all settled — do not re-open)

- **Grid stays 8×8, 50-stud tiles, deterministic from `Constants.SEED`.**
- **4 districts = 2×2 quadrants.** `districtOf(x,z)`: `col = (x > 4) and 1 or 0`,
  `row = (z > 4) and 1 or 0`, `id = col + 2*row`. So 0=TL(x1–4,z1–4),
  1=TR(x5–8,z1–4), 2=BL(x1–4,z5–8), 3=BR(x5–8,z5–8).
- **Street mazes carve within a district only** — never across a district
  boundary. Each district is its own connected maze, isolated at street level.
- **Crossing topology = a fixed chain: 0–1, 1–3, 3–2** (three rooftop crossings).
  Spawn in district 0 (grid center cell (4,4)); exit in district 2. Do NOT
  connect 0–2 directly, even though they're adjacent — that's the point.
- **Heights** (`Constants`): `STREET_WALL_H = 36`, `DIVIDE_H = 54`,
  `TOWER_H = 60` (crossing-tower roof + bridge height), beam top `y = 260`.
- **Orientation aid: exit sky-beam only** (direction, never path). No minimap,
  no waypoints, no signs in this pass.
- **Rooftop-only.** No sewer layer in this pass.

## Out of scope / Do NOT

- NO sewer layer, NO fog, NO warden, NO economy/tools/shop, NO rings 1–3, NO
  checkpoints/persistence, NO EXIT signs / hum / map-fragments (later orientation
  passes), NO grapple-gated gaps, NO tile prop/decal variety pass.
- Do NOT add more than the 3 chain crossings. Do NOT make districts non-quadrant.
- Do NOT change networking, UI, or non-Maze features.
- Do NOT make generation non-deterministic — all randomness from one
  `Random.new(Constants.SEED)`.

---

## Step 1 — Constants

Edit `Constants.luau`: rename `WALL_HEIGHT` usage to street height and add the
new heights.

```luau
WALL_HEIGHT = 36,   -- street maze walls (was 60)
DIVIDE_H    = 54,   -- district-divide walls (tall, unclimbable)
TOWER_H     = 60,   -- crossing-tower roof + rooftop-bridge height
BEAM_TOP_Y  = 260,  -- exit sky-beam height
```
Keep `SEED=1001, GRID=8, TILE_SIZE=50, EXTRA_LOOPS, ROOF_TILE_CHANCE`.

**Accept:** `require` prints the table with the new keys; existing tiles still
build (walls now 36 tall) with no error in a Play test.

## Step 2 — District partition + per-district carve

In `MazeService`:
- Add `local function districtOf(x, z): number` per the formula above.
- Change `carve` so a neighbour in a **different district** is treated like
  out-of-bounds (never carved across). Because a single backtracker start won't
  reach sealed districts, carve **each district independently**: iterate the 4
  district ids, pick a start cell in that district, run the backtracker
  restricted to that district's cells. Union the openings.
- `addLoops` must also refuse cross-district edges.

**Accept:** run a debug print of per-district cell counts and confirm a BFS over
street openings reaches all 16 cells **within** each district but **zero** cells
in any other district (4 isolated components of 16).

## Step 3 — District-divide walls (tall)

After tiles are stamped, run a post-pass: for every grid edge whose two cells are
in different districts, build a `DIVIDE_H`-tall wall part spanning that edge
(50 long × `DIVIDE_H` × 3, base at floor), parented under `mazeFolder` in a
`Divides` folder. Colour slightly darker than street walls so the barrier reads.
These are continuous at street level (crossings pass *over* them at `TOWER_H`).

**Accept:** in Play, the four quadrants are visibly walled off by tall barriers;
you cannot walk between quadrants at street level anywhere.

## Step 4 — Crossing towers + rooftop bridges

For each chain edge (0–1, 1–3, 3–2):
- Pick one boundary cell-pair `(a in A, b in B)` adjacent across that district
  line, chosen with `rng` (deterministic). 
- Stamp **both** cells as a crossing tower: reuse `StairCourt` (its switchback
  already climbs to `TOWER_H=60` with a full roof). Ensure each tower cell still
  has a street opening into its own district (so it's reachable by street).
- Build a **rooftop bridge**: a walkway part at `y = TOWER_H`, spanning from
  tower A's roof over the divide wall to tower B's roof (≈50 studs across, 8
  wide), plus low parapets. Parent under a `Bridges` folder. The bridge clears
  the `DIVIDE_H=54` wall by 6 studs.
- Confirm the two tower roofs + bridge form a continuous y=60 walkable surface
  from A's stair-top to B's stair-top.

**Accept:** in Play, teleport onto tower A's roof, walk across the bridge over
the divide, and reach tower B's roof — verified walkable end to end (scripted
climb/cross test, feet stay on the surface, no fall).

## Step 5 — Spawn, exit, and multi-layer solvability

- Spawn = grid center (4,4) (district 0), floor level.
- Exit = farthest **boundary cell in district 2** by BFS distance over the
  **combined** graph (street openings within districts ∪ the 3 crossing edges,
  where a crossing edge links tower cell `a`↔`b`). Punch its outer wall → door
  (existing door code; keep the muted-green door).
- **Validate**: BFS over the combined graph from spawn cell to exit cell must
  succeed (`assert`). Also assert each district is internally fully connected and
  the 3 crossings connect all 4 districts (spawn→exit crosses exactly the chain).

**Accept:** Play with zero errors; the solvability assert passes; a scripted BFS
over the combined graph confirms spawn→exit reachable and that removing any one
crossing bridge disconnects it (proving verticality is *required*).

## Step 6 — Exit sky-beam

At the exit door, add a thin tall emissive column (e.g. 4×`BEAM_TOP_Y`×4) rising
from the door to `BEAM_TOP_Y`, plus a soft `PointLight`/`Beam`. Visible over the
36 street walls and from the towers, giving direction only. Name it `ExitBeam`,
parent under `mazeFolder`. Must not block the doorway (offset just outside).

**Accept:** from a random street cell in district 0 you can see the beam over the
walls; from a tower roof it clearly marks the exit's direction across the maze.

## Step 7 — Fun-gate re-test (manual)

Playtest and record in `PLAYTEST-notes.md`:
1. Is it clear, when you hit a district wall, that you must go **up**? (Legible,
   not confusing.)
2. Does climbing a tower + crossing feel like a rewarding "aha", and can you spot
   the beam / next tower from up there?
3. Does knowing the beam direction still leave a real routing puzzle (you can't
   just walk toward it)?
4. First full escape time — is it in a satisfying band (~5–12 min)?
5. Any spot where you're hard-*stuck* (not puzzling — stuck)?

This is the gate: the next system (sewer / fog / tools) doesn't start until 1–3
read as "yes".

## Definition of Done

- [ ] Deterministic from `SEED`; same seed → identical districts, crossings, exit.
- [ ] 4 sealed street districts; no street path between quadrants.
- [ ] Exactly 3 rooftop crossings (chain 0-1-3-2); each is walkable up→across→down.
- [ ] Combined-graph BFS: spawn→exit reachable; removing any bridge disconnects it.
- [ ] Street walls 36, divides 54, towers/bridges 60; rooftops see over streets.
- [ ] Exit door (muted green) + visible sky-beam; door still fires the ESCAPED loop.
- [ ] Zero output errors in a full Play; StreamingEnabled still on; part budget sane.
- [ ] Only `src/features/Maze/` changed; `PLAYTEST-notes.md` updated with the 5 answers.
