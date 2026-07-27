# Maze

The circular (theta) maze: concentric ring-bands around a central evac hub. The
player spawns in the outer district and runs INWARD, searching each district's
ring for the single gate through to the next, to reach the EvacPad at the
centre (the win trigger, see [Escape.md](Escape.md)).

Files:

- `src/features/Maze/MazeService.server.luau` — carves the maze (per-district,
  see below), builds its geometry and the `Gates` landmarks, positions
  `SpawnLocation`, and publishes the navigation graph (`MazeNav`).
- `src/features/Maze/MazeNav.luau` — shared nav graph (cell centres + open
  adjacency) other features (Hunter, Checkpoint) read, and `MazeNav.districtOf`
  — the single shared band-to-district mapping (see below).
- `src/features/Maze/Constants.luau` — `SEED`, the season/default seed.

## Sealed districts

The 12 bands are grouped into three **sealed districts**, each walled off from
its neighbour except for a single gate. Reaching the next district means
searching the whole ring for that one opening — getting caught costs you the
district you were solving, not a few seconds of corridor (see
[Checkpoint.md](Checkpoint.md)).

| District | Bands | Enters via gate at |
| -------- | ----- | ------------------ |
| OUTER (3) | 9–12 | — (spawn here) |
| MIDDLE (2) | 5–8 | `RADII[9]` = 366 |
| INNER (1) | 1–4 | `RADII[5]` = 198 |
| HUB (0) | 0 (the exit pad) | `RADII[1]` = 30 |

`MazeNav.districtOf(band)` is the one place this mapping lives — band 0 is
district 0, otherwise `math.floor((band - 1) / 4) + 1`. Both `MazeService`
(carving, gates) and `CheckpointService` (respawn tracking) require it from
there rather than each keeping their own copy.

The three gate boundaries, each `{ outerBand, innerBand }`: `{9, 8}`, `{5, 4}`,
`{1, 0}`. The first two boundaries are 1:1 on sector counts
(`SECTORS[9]=SECTORS[8]=48`, `SECTORS[5]=SECTORS[4]=24`); the third is the hub,
where all six `(1,s)` cells fold onto the single `(0,0)` cell.

### Carve-per-district, not carve-then-seal

**The maze is built correct by construction, not sealed after the fact.** The
obvious approach — carve the whole maze with one spanning-tree walk (as it used
to, hub outward), then close all-but-one passage at each district boundary —
**disconnects the maze**. A single spanning tree crosses a boundary as many
times as the walk happens to wander back and forth across it, and the
sub-trees hanging off those extra crossings are often only reachable *through*
the boundary. Closing them orphans whole rings, silently, deep in the middle
of a run.

Instead, `MazeService.rebuild` carves each district as its **own independent
maze** (`carveRange`, a recursive backtracker restricted to a `[bandLo, bandHi]`
band range), then opens **exactly one** passage between each pair of adjacent
districts (`openGate`). Connectivity then follows by construction: each
district is internally spanned, and hub → inner → middle → outer chain through
their single gates. `addLoops` (which knocks out extra passages for shortcuts)
skips any candidate whose two cells are in different districts
(`MazeNav.districtOf`), so it can never silently re-open a sealed boundary —
the `attempts` counter still increments on the skip so a bad seed can't spin
forever inside the 5000-attempt bound.

The existing `reachFrom` connectivity assert in `rebuild` stays as the
guard that would catch a mistake here — it should now pass trivially on every
seed, not do the disconnection-preventing work itself.

## Gates

Each district boundary gets a lit archway (two neon pillars + a lintel) at the
single opening `openGate` cut, built in its own `workspace.Gates` folder — kept
separate from `workspace.Maze` because `MazeService.rebuild` calls
`mazeFolder:ClearAllChildren()` on the Maze folder, which would destroy the
gates too if they lived there. `Gates` is cleared and rebuilt every generation,
same pattern.

Each gate part carries two attributes:

- `EntersDistrict` (number) — the district on the **inner** side of that
  boundary: `2`, `1`, `0` for the `{9,8}`, `{5,4}`, `{1,0}` boundaries
  respectively (computed via `MazeNav.districtOf(innerBand)`, not hardcoded).
- `GateCenter` (Vector3) — the floor-level centre of the **opening**.

**Always read `GateCenter`, never a gate part's own `Position`.** A gate is three
parts (two pillars + a lintel) all named `Gate` and all carrying the same
attributes, and the pillars stand on the opening's two *edges* — exactly where
the arc wall resumes. A consumer that grabs whichever part it finds first and
uses its `Position` lands half inside that wall: `CheckpointService` would
respawn caught players clipped into geometry, and the compass would aim at a
pillar rather than the gap. `GateCenter` is the same on all three parts, so it
doesn't matter which one you find.

A gate is decoration and navigation only: **no `Touched` handler**
— passing through it is exactly like passing through any other gap in a wall.
All parts are `Anchored`, `CanCollide = false`, so they never block the
passage they mark.

Gates are consumed by:

- **`CheckpointService`** — looks up the gate for a district by
  `EntersDistrict` and respawns a caught player at a floor-level CFrame there
  (see [Checkpoint.md](Checkpoint.md)).
- **`CompassController`** (client) — targets the gate with the largest radius
  still smaller than the player's own, needing no district maths client-side
  (see [Pickups.md](Pickups.md)).

## Studio assets

**None required beyond `workspace.SpawnLocation`.** The user must place one
`SpawnLocation` instance in Workspace; `MazeService` repositions it every
rebuild rather than recreating it. Everything else (floor, walls, `ExitGate`)
is built procedurally.

## Round-per-seed, not fixed

`MazeService.rebuild(seed: number)` builds (or rebuilds) the whole maze from a
seed: carve, add loops, build geometry, place the spawn, publish `MazeNav`. It
is safe to call repeatedly. `MazeService.Start()` is just
`MazeService.rebuild(Constants.SEED)` followed by setting `workspace.MazeReady`.

`EscapeService.Net.Restart.listen` (see [Escape.md](Escape.md)) calls
`MazeService.rebuild` with a fresh random seed on every "RUN IT BACK" — so the
wall layout genuinely changes each round, not just the spawn point.

## The rebuild footgun — `workspace.MazeGeneration`

`rebuild` calls `mazeFolder:ClearAllChildren()` to clear the previous maze. That
**destroys `ExitGate`** and anything another feature parented into the `Maze`
folder (e.g. EscapeService's `EscapeZone`). Any service holding a captured
reference to those instances from a previous build now holds a reference to a
destroyed instance, and a `.Touched` connection wired to the old instance will
never fire again — **silently**, with no error.

The fix: `rebuild` increments a monotonic `workspace.MazeGeneration` attribute
(a plain number) as the very last thing it does, after `MazeNav.ready = true`.
Any service that captures instances parented inside `Maze` (or that snapshots
`MazeNav` into upvalues) must listen for
`workspace:GetAttributeChangedSignal("MazeGeneration")` and re-fetch / re-wire
from scratch on every fire — not just once at `Start()`.

**`workspace.MazeReady` cannot be reused for this.** It's set to `true` once and
never cleared (other services `:Wait()` on it, so clearing it would deadlock
them) — `GetAttributeChangedSignal("MazeReady")` will not fire again after the
first build. `MazeGeneration` is the only rebuild-coordination mechanism; don't
add a second one (no signals, no BindableEvents, no direct cross-service calls
for this purpose).

Services currently re-wiring on `MazeGeneration`:

| Service | What it re-does |
| ------- | ---------------- |
| `EscapeService` | Recreates `EscapeZone`, re-fetches `ExitGate`, reconnects `Touched` |
| `HunterService` | Re-snapshots `MazeNav.cellPos` / `maxBand`, re-homes every live hunter |
| `CheckpointService` | Clears each player's `deepest`-district baseline |

`spawnLocation` itself does **not** need re-fetching anywhere — `MazeService`
repositions the same instance every rebuild rather than recreating it, so a
CFrame read off a captured reference stays live and correct.

## Far spawn rule

The spawn always lands in the outer 3 rings (`SPAWN_MIN_BAND = BANDS - 2`
through `BANDS`, i.e. bands 10–12 of 12), never mid-maze — a run is meant to be
a long haul inward. Spawns land at each band's **mid-radius**, so there are
exactly three possible distances from the centre:

| Band | Mid-radius | From `RADII` |
| ---- | ---------- | ------------ |
| 10 | **429** | (408 + 450) / 2 |
| 11 | **471** | (450 + 492) / 2 |
| 12 | **513** | (492 + 534) / 2 |

So the drop-in point is always **at least 429 studs** out, against an outer
perimeter of `RADII[13] = 534`. Use 429 as the assertion floor, not a rounder
number — band 10 sits just under 430 and a `> 430` check fails roughly a third
of the time.

Spawn placement uses the **same seeded `rng`** as the carve/loop steps (not a
separate unseeded `Random`), so a seed alone fully determines the whole round —
walls and spawn together.

## Band geometry (fixed)

`RADII`, `SECTORS`, `BANDS`, `WALL_H`, `WALL_T`, `FLOOR_Y` are fixed constants —
only the *passage* pattern (which walls exist) changes per seed. Don't tune
these; they're load-bearing for the maze reading as one consistent world across
seeds.
