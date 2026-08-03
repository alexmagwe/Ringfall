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
- `src/features/Maze/Dressing.luau` — per-district set dressing (the outermost
  district's overgrowth). Scenery only; see below.

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

## District dressing

`src/features/Maze/Dressing.luau` gives a district a look of its own. Two are
dressed today, declared in `DISTRICT_LOOKS` in `MazeService`:

| District | Bands | Look | Reads as |
| -------- | ----- | ---- | -------- |
| OUTER | 10–12 | `Dressing.OVERGROWN` | An abandoned ruin — what the maze *became* |
| MIDDLE | 7–9 | `Dressing.FLOODED` | Working industry — what it was *for* |
| INNER | 1–6 | none | As carved; the vault's chamber carries the centre |

**The districts are laid outermost-first, and the order matters.** Each one lays
its ground as two discs — its own surface out to `outerR`, then a disc of the
original floor back out to `innerR` to hide the overspill. A district laid later
must therefore sit *above* the one outside it, which is what the rising
`FLOOR_Y + n` layer offset does. The steps are fractions of a stud, so none of it
is walkable or visible as a lip.

**Growth thins with depth rather than stopping at a gate.** `growthFalloff` is a
multiplier applied to `growthChance` at a district's inner edge, ramping to 1 at
its outer edge. Three districts each at a flat density read as three rooms; a
ramp reads as one world that changes as you descend. The middle district runs
`0.15`, so the overgrowth outside bleeds a little way in and then gives out.

**A pipe is a rigid metal vine, and shares its generator.** `pipesOnWall` is
`growOnWall` with three differences that are the whole reason a corridor reads as
built rather than overgrown: it runs *horizontally*, it holds one thickness for
its whole length, and it never kinks. Pipes span the full wall segment on
purpose — one that stops halfway reads as a broken prop, one that leaves at both
ends reads as part of a system continuing past what you can see.

`rubbleUpright` turns the rubble generator into crates: yaw only, no pitch or
roll. Fallen stone tumbles; cargo someone set down does not.

### The overgrown outer ring

The ground is grass,
thick vines hang off the walls, shoots climb out of their bases, tufts clump
across the floor, and the stone is weathered Slate instead of clean Concrete.

Three rules came out of the first version, which looked flat and wrong:

- **The walls stay grey.** Painting them green to match the grass turned the
  district into one green mass with nothing reading against anything. Growth is
  only visible where it contrasts with what it grows on, so the wall carries the
  stone and the vines carry the colour.
- **Growth needs height.** Flat discs on a flat floor are stains whatever colour
  they are. The tufts are boxes with real height, in clumps, because even
  spacing reads as a texture and clumps read as growth that took hold. Broad
  tinted discs were tried for ground variation and removed: whatever the size or
  tone, a circle on flat ground reads as a circle, because the eye finds the rim
  and nothing outdoors has one. Ground variation has to break the silhouette.
- **Neighbouring surfaces need different LIGHTNESS, not just different hue.**
  The stone was a warm mid-grey sitting at almost exactly the grass's lightness,
  and the two merged into one tone. It is now clearly darker and cooler than the
  grass it stands in.
- **One exact colour across 600 parts reads as paint.** `wallJitter` (0.05)
  varies each wall part's lightness a few percent, hue held still by scaling all
  three channels together.
- **Break the junction before anything else.** A wall meeting a floor along a
  perfect straight line is the loudest tell that a place was generated, and that
  line is at eye level for the whole run. `rubbleAtBase` heaps tipped stone
  there, half-buried in the wall so it reads as fallen out of it rather than
  parked against it, with a tuft against most pieces to tie stone to grass. It
  rolls separately from the vines, and more often (`rubbleChance` 0.55), because
  those parts buy more there than anywhere in the open.
- **Everything casts a shadow** except the flat ground discs. An object with no
  shadow does not touch anything: a tuft hovers, a vine becomes a sticker.
  Contact shadow is most of what makes small scenery look placed. This one is
  also why the light matters — see [Atmosphere.md](Atmosphere.md).
- **Vines need thickness and a kink.** At 0.35 studs against a 40-stud wall they
  were threads that vanished at any distance. They are now 0.9–2.2 thick, and a
  strand can run as two segments that meet at a slight angle — that kink is most
  of the difference between a vine and a pipe.

**This is a navigation fix as much as an art pass.** The maze carves itself in
one wall colour on one floor disc, so every cell in a district was identical to
every other. Sweeping a ring for its single gate needs landmarks you can
remember, and identical cells give you none — you cannot tell an arc you already
searched from one you have not.

The outer district gets it because players spawn there, so it sets the first
impression, and it gives the run a gradient: a ruin at the edge, intact
structure in the middle, a sealed vault at the centre. The maze reads as better
defended the deeper you go.

`MazeService` calls `Dressing.apply` after the gates are built, and derives the
radius range from `MazeNav.DISTRICT_BANDS[#DISTRICT_BANDS]` rather than naming
band 10 — retuning the district split cannot leave the dressing over the wrong
ring. It runs on the build's own seeded `rng`, so a seed reproduces its dressing
exactly as it reproduces its layout.

### Look only, on purpose

Every part `Dressing` adds is `CanCollide` / `CanQuery` / `CanTouch` false:

- The navigation graph is untouched. No collider moved, and hunters still walk
  cell centres.
- **A vine curtain is not cover.** `HunterService.canSee` only counts a raycast
  hit on a part named `Arc`, `Spoke` or `Perimeter`, and `CanQuery = false`
  keeps growth out of every raycast in the game regardless — hunter sight, the
  gun's aim ray, and the shot itself.
- Nothing can trip a pickup's `Touched` or block a corridor.

To make growth mechanical later, the change is deliberate rather than a tweak:
give the thick strands query-visible colliders and name them into `canSee`.

**Never cut a real gap in a wall to fake decay.** The wall *is* the maze. A hole
opens a passage the carve never made, which can strand a gate and break the
sealed-district rule. Decay is painted on; the collider stays whole.

### The ground is a ring made of two discs

The maze floor is **one disc spanning the whole map**, so a district's ground has
to be laid over part of it. The obvious build — an annulus chopped into wedge
quads — is the wrong one: neighbouring quads meet coplanar along every radial
seam and z-fight, and a chord across a 48-sector arc at this radius misses the
true curve by over a stud.

`layGround` uses two concentric discs instead, which have no seams at all:

1. a **grass disc** out to `outerR`, which also covers everything inside it;
2. a disc of the **original floor** back out to `innerR`, which hides the part
   of the grass that reached into the inner districts.

What stays visible is an exact ring, for two parts instead of ~150. The cover
disc reads its colour and material off the real `Floor` part rather than naming
them, so the inner districts cannot drift out of step with it if `FLOOR_COLOR`
changes. Every disc is `DISC_THICKNESS` (0.2) thin and they stack a few
hundredths apart, so no two faces are ever coplanar.

The discs are `CanCollide = false` like everything else here. Players walk on
the real floor and stand 0.05 studs deep in the grass, which reads as short
growth rather than as clipping.

### Budget

The outermost district holds roughly 620 wall segments once the perimeter is
chopped into chords. The `Look` table is therefore tuned to add ~1900 parts, and
`tuftClumps` is a **flat count, not a per-wall multiplier** — anything
multiplied per wall runs to four figures on a ring that rebuilds every round.
Spend any increase on the wall bases first.
`Dressing.apply` prints the wall and part counts on every build, so a raised
density shows up in the output before it shows up as a frame-rate complaint.

Adding a second district look is a `Look` table plus one `Dressing.apply` call.

## Dev shortcut: `DEV_DIRECT_PATH`

`Constants.DEV_DIRECT_PATH` cuts a **straight radial corridor from the staging
entrance to the vault**, so the centre — and the round-end board behind it — is
reachable in seconds instead of a full three-district descent.

**It must be `false` to ship.** It deliberately breaks the sealed-district rule
the whole run is built on: each district is meant to be crossable only through
its single gate, and this puts a hole through all three. `MazeService` warns to
the output on every build while it is on.

`carveDirectPath` walks inward from the staging sector, opening each band's
inward passage in turn — only inward ones, so the result is one clean radial
line. It runs after `addLoops` and before any geometry, since the arcs are built
from `passages`.

The staging sector is rolled **before the geometry** for this reason: the
corridor has to start where players actually walk in. Nothing between that roll
and the perimeter section draws from `rng`, so the draw order is unchanged and a
given seed still produces the same maze.

## Studio assets

**None.** Everything — floor, walls, the staging room, the Vault, the
overgrowth — is built procedurally.

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
     `ExtractPad` (the win trigger, now **invisible** — see
     [Escape.md](Escape.md)) and `SpawnLocation`, positioned near the room's
     far wall facing back down the corridor. Since a polar angle is a
     straight line through the origin, "facing down the corridor" and
     "facing world-centre" are the same direction — no separate look-at
     target needed.
   - **The pad is invisible, and must still exist.** `Transparency = 1` with
     `Touched` intact. **Never delete the part** — `EscapeService.bindToMaze`
     does `WaitForChild("ExtractPad")`, so removing it hangs that bind forever
     and takes the door, the escape zone and extraction down with it.

     It has been a glowing beacon, then a flat floor marking, and is now
     nothing you can see. As a disc it read as a teal puddle dropped in the
     middle of the lobby: the first thing a player looks at on spawn, saying
     nothing to anyone who isn't carrying the vault, and the loudest object in a
     room the round hasn't started in yet. The cost is that a carrier running
     home has no marked spot to stand on — the room is small and they must enter
     it anyway, but if extraction ever feels vague, add a thin ring at the pad's
     edge rather than filling the disc back in.
   - **Palette:** the room now carries no accent at all; walls, floor and `Door`
     are neutral grey. The door was a saturated red until it, the pad and the
     blue-grey shell added up to a three-hue lobby that read as noise; its state
     was never carried by colour anyway (the countdown says how long is left,
     and it slides into the floor to open). Tune via `DOOR_COLOR`,
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

The prize at the centre hub, previously named `ExitGate` (the old per-player win
trigger) and now named **`Vault`**. It is always a **`Model`** floating
`VAULT_Y_OFFSET` (6) studs above a decorative `VaultDais`, built one of two ways
by `buildVault`:

- **The user's art**, if `ServerStorage.MazeModels.Vault` exists. Anything that
  is or contains a `BasePart` works; scripts are stripped and every part is
  forced `Anchored` / `CanCollide = false` / `CanTouch = true` / `Massless`. The
  check is not a class whitelist, because rejecting usable art produces a silent
  fallback indistinguishable from "I never added it" — `vaultTemplate` warns
  instead. Two normalisations then make any Toolbox prop behave:
  - **`PrimaryPart` is cleared.** `ScaleTo` and `PivotTo` both work about the
    model's pivot, so an off-centre `PrimaryPart` would make the Vault swing
    through an arc instead of turning in place once it spins. With none set the
    pivot is the bounding-box centre.
  - **Scaled to `VAULT_TARGET_SIZE` (6) on its longest axis.** Toolbox props are
    authored at wildly different scales; a briefcase built for a character's
    hand is a couple of studs and reads as litter on the dais.
- **The built-in artifact** otherwise: a small bright `Neon` core inside a ring
  of `VAULT_FIN_COUNT` dark metal fins, with `VAULT_SHARD_COUNT` chunks orbiting
  further out at mixed heights. This replaced a single 7-stud Neon cube which
  was lit, centred, and *still* read as a placeholder — one solid glowing block
  has no internal detail for the eye to catch. Core + cage + debris gives the
  light something to slice through as it turns.

Either way `dressVault` adds the `PointLight` and the `AlwaysOnTop` gold
`Highlight`, so the centre reads as *the* destination through the ring walls
from anywhere in the maze.

Motion is client-side (`Salvage/VaultController.client.luau`): a slow spin plus a
small bob, rebound on `MazeGeneration`. See [Salvage.md](Salvage.md) for its
Touched behaviour and the alarm it trips. `MazeService` builds it with **no
behaviour** —
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
