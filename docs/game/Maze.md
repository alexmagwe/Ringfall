# Maze

The circular (theta) maze: concentric ring-bands around a central **Vault**.
Every round starts in a **staging room** outside the perimeter; once the
door opens, players run INWARD, searching each district's ring for the
single gate through to the next, to reach the Vault — then carry it back out
the same way they came. The win trigger is no longer here: it's the
`ExtractPad` inside the staging room (see [Escape.md](Escape.md)).

Files:

- `src/features/Maze/MazeService.server.luau` — carves the maze (per-district,
  see below), builds its geometry, the `Gates` landmarks, and the staging
  room (`workspace.Staging`), positions `SpawnLocation`, and publishes the
  navigation graph (`MazeNav`).
- `src/features/Maze/MazeNav.luau` — shared nav graph (cell centres + open
  adjacency, plus `MazeNav.perimeterR`, the XZ radius of the perimeter wall —
  the maze's outer edge, which `HunterService` uses to keep hunters in and to
  treat the staging room as a sanctuary) other features (Hunter, Checkpoint)
  read, and `MazeNav.districtOf`
  — the single shared band-to-district mapping (see below).
- `src/features/Maze/Constants.luau` — `SEED`, the season/default seed.

## Sealed districts

The 12 bands are grouped into three **sealed districts**, each walled off from
its neighbour except for a single gate. Reaching the next district means
searching the whole ring for that one opening — getting caught costs you the
district you were solving, not a few seconds of corridor (see
[Checkpoint.md](Checkpoint.md)).

| District | Bands | Cells | Enters via gate at |
| -------- | ----- | ----- | ------------------ |
| OUTER (3) | 10–12 | 144 | — (spawn here) |
| MIDDLE (2) | 7–9 | 120 | `RADII[10]` = 408 |
| INNER (1) | 1–6 | 102 | `RADII[7]` = 282 |
| HUB (0) | 0 (the Vault) | 1 | `RADII[1]` = 30 |

**The districts deliberately do NOT hold equal ring counts.** Circumference grows
with radius, so equal rings give wildly unequal search areas: an even 4/4/4 split
put 192 cells in the outer district against 54 in the inner — meaning the
district you solve *first*, with no compass and not yet knowing gates exist, was
~4× the work of the one you solve last with both. That is an inverted difficulty
curve, and the outer district is exactly where a new player would quit. 6/3/3
bands gives 144/120/102 — still funnelling inward, but 1.4× rather than 3.6×.

The inner district is correspondingly *deeper* in radius (252 studs vs 126) since
its rings are narrow in cell terms — it reads as a long descent rather than a
wide sweep, which suits the approach to the exit.

`MazeNav.DISTRICT_BANDS` is the single source of truth, and
`MazeNav.districtOf(band)` derives from it by lookup (not arithmetic — the groups
are uneven). `MazeService` reads the ranges from there for carving, and derives
`GATE_BOUNDARIES` from them (each district's gate sits at its innermost band,
crossing into the band below) so a layout change can't strand a gate mid-district.
`CheckpointService` and the compass go through `districtOf`.

The compass is standard equipment now, not a pickup with its own
`minBand`/`maxBand` placement constraint (see [Salvage.md](Salvage.md)) — so
changing `DISTRICT_BANDS` no longer requires updating a matching pickup
constraint the way it once did.

The three gate boundaries, each `{ outerBand, innerBand }`: `{10, 9}`, `{7, 6}`,
`{1, 0}`. The first two are 1:1 on sector counts
(`SECTORS[10]=SECTORS[9]=48`, `SECTORS[7]=SECTORS[6]=24`); the third is the hub,
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
- **`CompassController`** (client, now in `src/features/Salvage/`) — targets
  the gate with the largest radius still smaller than the player's own,
  needing no district maths client-side, until the vault is taken (see
  [Salvage.md](Salvage.md)).

## Studio assets

**None.** Everything — floor, walls, the staging room, the Vault — is built
procedurally.

`MazeService` uses a `SpawnLocation`, and **creates one if the place has none**
(warning to the output as it does). If you place your own, that one is reused —
it is repositioned into the staging room every rebuild rather than recreated, so
any properties you set on it survive.

This used to be a hard `assert`, which meant a blank place — exactly what you
get from `git clone` plus a fresh Studio file, since the `.rbxl` is gitignored —
died on startup before anything else ran. Every other Studio asset the game
wants degrades gracefully; this was the one that stopped it dead.

## The staging room + corridor

Every round starts **outside the maze entirely**, in a walled room the
player sees the extraction pad in *before* anyone leaves — teaching the
return trip wordlessly. Built by `MazeService.rebuild` (a private
`buildStaging` helper), rebuilt fresh every generation into its own
`workspace.Staging` folder — **not** under `workspace.Maze`, since
`mazeFolder:ClearAllChildren()` would destroy it, but cleared and rebuilt on
every `MazeGeneration` just like `Gates`.

Geometry, all keyed off one random angle (`stagingTheta`, drawn from the same
seeded `rng` the carve/gates/loops use, so a seed still fully determines the
round):

1. **Perimeter cut.** A random outer-band sector (`stagingSector`, out of the
   48 sectors in band 12) is picked *before* the Perimeter wall loop runs,
   and that loop skips building the arc for exactly that sector — a
   ~70-stud-wide gap in the otherwise-sealed perimeter, at
   `stagingTheta`. **Order matters**: the sector must be chosen before the
   Perimeter loop executes, or there's no wall to leave a gap in.
2. **The room + corridor**, a single 50-stud-wide walled hallway on that
   angle, split conceptually (not structurally — same width throughout) into
   two zones:
   - **Corridor** — from the perimeter cut (`RADII[13]` = 534) to the room's
     near edge (549), 15 studs long. A `Door` part sits partway along it
     (`CanCollide` toggled by `EscapeService` as `RoundState` changes — see
     [Escape.md](Escape.md)).
   - **Room** — centred at `RADII[13] + 40` = 574, half-depth 25 (kept
     under 30 studs so it can't overlap the sealed maze). Holds the
     `ExtractPad` (a flat marked disc, the win trigger — see
     [Escape.md](Escape.md)) and `SpawnLocation`, positioned near the room's
     far wall facing back down the corridor. Since a polar angle is a
     straight line through the origin, "facing down the corridor" and
     "facing world-centre" are the same direction — no separate look-at
     target needed.
   - **Palette:** the room gets exactly **one** accent, the `ExtractPad`, in a
     muted sea-green. Everything else — walls, floor, `Door` — stays neutral
     grey. The door was a saturated red until it, the pad and the blue-grey
     shell added up to a three-hue lobby that read as noise; its state was never
     carried by colour anyway (the countdown says how long is left, and it
     slides into the floor to open). Tune via `DOOR_COLOR`,
     `EXTRACT_PAD_COLOR` and `EXTRACT_PAD_SCALE`.
   - There is **no wall on the corridor's near end** — that opening is the
     perimeter cut itself, so the corridor's mouth lines up flush with it.
3. Floor, side walls, and the far wall are built via `polarOffset` (like
   `polar`, but offset tangentially by a fixed number of studs — needed
   because the staging room sits off the maze's own polar wall grid) and
   `buildSegment` (a straight wall between two arbitrary points, unlike
   `buildRadial` which always runs through the origin).

**The old random-band spawn (`SPAWN_MIN_BAND`, bands 10–12) is gone.** Every
round is now a full descent starting *outside* the perimeter — there's no
more "sometimes you drop in a bit deeper" variance; the staging room is the
only spawn point, every time.

## The Vault

The centre hub part, previously named `ExitGate` (the old per-player win
trigger) and now named **`Vault`**: same size and position
(`RADII[1] * 1.4` diameter, centred), but reskinned to read as a
container — dark `Metal` material, a gold `Highlight` outline, no light
emission (greybox; see [Salvage.md](Salvage.md) for its Touched behaviour and
the alarm it trips). `MazeService` builds it with **no behaviour** —
`SalvageService` binds `Touched` separately (see
[Salvage.md](Salvage.md#the-vault-and-the-alarm)), the same split
`MazeService`/`EscapeService` already used for the old `ExitGate`.
`EscapeService` no longer looks the Vault up at all; the win trigger moved
entirely to the staging room's `ExtractPad`.

## Round-per-seed, not fixed

`MazeService.rebuild(seed: number)` builds (or rebuilds) the whole maze from a
seed: carve, add loops, build geometry (including the staging room and
Vault), place the spawn, publish `MazeNav`. It is safe to call repeatedly.
`MazeService.Start()` is just `MazeService.rebuild(Constants.SEED)` followed
by setting `workspace.MazeReady`.

`EscapeService.endRound` (see [Escape.md](Escape.md)) calls
`MazeService.rebuild` with a fresh random seed every time the vault reaches
the extract pad — so the wall layout, staging room angle, and Vault all
genuinely change each round, not just the spawn point.

## The rebuild footgun — `workspace.MazeGeneration`

`rebuild` calls `mazeFolder:ClearAllChildren()` to clear the previous maze. That
**destroys the `Vault`** and anything another feature parented into the `Maze`
folder (e.g. EscapeService's `EscapeZone`). The `Staging` folder (Door,
ExtractPad) is separate from `Maze` but is rebuilt — cleared and repopulated
— on every generation too, for the same reason: the staging room's angle
changes every round. Any service holding a captured reference to instances
from a previous build now holds a reference to a destroyed instance, and a
`.Touched` connection wired to the old instance will never fire again —
**silently**, with no error.

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
| `EscapeService` | Recreates `EscapeZone`, re-fetches `Door`/`ExtractPad` from `Staging`, reconnects `ExtractPad.Touched` |
| `SalvageService` | Re-scatters salvage, re-fetches the `Vault`, reconnects its `Touched` |
| `HunterService` | Re-snapshots `MazeNav.cellPos` / `maxBand`, re-homes every live hunter, clears `HunterAlert`/`HunterAlertPos` |
| `CheckpointService` | Clears each player's `deepest`-district baseline |

`MazeService.rebuild` itself also clears `VaultTaken` / `AlarmActive` /
`HunterAlert` / `HunterAlertPos` directly (not via a listener) as part of
`rebuild` — conceptually Salvage/Hunter attributes, but cleared in the one
place every round always passes through, same reasoning as every other
per-run attribute reset. See [Salvage.md](Salvage.md).

`spawnLocation` itself does **not** need re-fetching anywhere — `MazeService`
repositions the same instance every rebuild rather than recreating it, so a
CFrame read off a captured reference stays live and correct.

## Band geometry (fixed)

`RADII`, `SECTORS`, `BANDS`, `WALL_H`, `WALL_T`, `FLOOR_Y` are fixed constants —
only the *passage* pattern (which walls exist) changes per seed. Don't tune
these; they're load-bearing for the maze reading as one consistent world across
seeds.
