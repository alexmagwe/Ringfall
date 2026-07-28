# TASKPLAN — Sealed districts and gates

## Context

Checkpoints are currently invisible and meaningless. `CheckpointService` fires
every time you cross inward into a deeper band — but **every band is only 42
studs deep**, so that's ~10 checkpoints per run, each worth about three seconds
of progress. Being caught costs nothing. The maze is also highly permeable
(`EXTRA_LOOPS = 36` on a 367-cell graph), so getting one ring deeper is never an
achievement — you walk inward and an opening appears.

This replaces that with **three sealed districts**. Each district's boundary is
walled except for a **single gate**, so getting inward means *searching the ring*
for the one way through. Gates are visible landmarks, they're where checkpoints
live, and being caught throws you back to the last gate — you re-solve a whole
district, not three seconds of corridor.

The compass is repointed to target the next gate, which turns it from a
near-useless "the middle is that way" arrow into the run's most valuable pickup.

**Out of this plan, deliberately deferred:** the wake-up opening / spawn chamber,
any objective text on the HUD (the user wants the run to stay mysterious — teach
through place, not labels), gate proximity glow, and all story/lore fragments.

---

## Layout (fixed — do not re-derive)

12 bands, 4 per district. Spawn is bands 10–12, so the player always starts in
the OUTER district.

| District | Bands | Enters via gate at |
| -------- | ----- | ------------------ |
| OUTER (3) | 9–12 | — (spawn here) |
| MIDDLE (2) | 5–8 | `RADII[9]` = 366 |
| INNER (1) | 1–4 | `RADII[5]` = 198 |
| HUB (0) | 0 (the exit pad) | `RADII[1]` = 30 |

```lua
-- band -> district
local function districtOf(band: number): number
	if band == 0 then
		return 0
	end
	return math.floor((band - 1) / 4) + 1
end
```

The three gate boundaries, each `{ outerBand, innerBand }`:
`{9, 8}`, `{5, 4}`, `{1, 0}`.

**Sector ratios are 1:1 at the first two boundaries** (`SECTORS[9]=SECTORS[8]=48`,
`SECTORS[5]=SECTORS[4]=24`), so cell `(9,s)` pairs with `(8,s)` and `(5,s)` with
`(4,s)`. The third is the hub: all six `(1,s)` cells touch `(0,0)`.

---

## Out of scope / Do NOT

- **Do NOT** change `RADII`, `SECTORS`, `BANDS`, `WALL_H`, `WALL_T`, `FLOOR_Y`,
  or `SPAWN_MIN_BAND`. The band geometry and far-spawn rule stay exactly as they
  are — only which *passages* get carved changes.
- **Do NOT** try to seal by carving the maze as it is now and then closing
  boundary passages. That **will disconnect the maze** — see the hazard note in
  Step 1. Build it correct by construction instead.
- **Do NOT** add HUD text, objective lines, gate counters, or tutorial messages.
  Mystery is the point.
- **Do NOT** touch the story/lore, the spawn chamber, or the wake-up sequence.
- **Do NOT** parent gates under `workspace.Maze`. They get their own
  `workspace.Gates` folder, rebuilt by `MazeService.rebuild`.
- **Do NOT** change `HEALTH_DRAIN`, the duck constants, the combat/pickup
  systems, or the round-loop work beyond what's specified here.
- **Do NOT** alter the top-centre HUD stack positions (timer y=12 → health y=70
  → stamina y=94 → compass y=116). They were just de-collided.

---

## Step 1 — Carve districts independently

**File:** `src/features/Maze/MazeService.server.luau`

### The hazard (read this before writing code)

The obvious approach — carve as now, then close all but one passage at each
boundary — **breaks connectivity**. The DFS spanning tree may cross a boundary
several times, and the sub-trees hanging off those crossings are often only
reachable *through* the boundary. Closing them orphans whole regions. The
existing `reachFrom` check would catch it, but only after the fact.

Build it correct instead: **carve each district as its own independent maze, then
open exactly one passage between adjacent districts.** Connectivity is then
guaranteed by construction — each district is internally spanned, and the
districts chain hub → inner → middle → outer.

### Do

Replace `carve(rng)` with a band-range-restricted version:

```lua
-- Recursive backtracker restricted to bands [bandLo, bandHi]. Never traverses
-- outside that range, so the result is a maze that spans exactly one district.
local function carveRange(rng: Random, passages: { [string]: boolean }, bandLo: number, bandHi: number)
	local visited: { [number]: boolean } = {}
	local startS = rng:NextInteger(0, sectorsOf(bandLo) - 1)
	local stack = { { bandLo, startS } }
	visited[cellKey(bandLo, startS)] = true

	while #stack > 0 do
		local cur = stack[#stack]
		local cb, cs = cur[1], cur[2]

		local candidates = {}
		for _, n in neighbours(cb, cs) do
			if n[1] >= bandLo and n[1] <= bandHi and not visited[cellKey(n[1], n[2])] then
				table.insert(candidates, n)
			end
		end

		if #candidates == 0 then
			table.remove(stack)
			continue
		end

		local n = candidates[rng:NextInteger(1, #candidates)]
		passages[pairKey(cb, cs, n[1], n[2])] = true
		visited[cellKey(n[1], n[2])] = true
		table.insert(stack, { n[1], n[2] })
	end
end
```

Add the district table and the gate opener:

```lua
local DISTRICT_BANDS = { { 1, 4 }, { 5, 8 }, { 9, 12 } } -- inner -> outer
local GATE_BOUNDARIES = { { 1, 0 }, { 5, 4 }, { 9, 8 } } -- { outerBand, innerBand }

-- Opens the single passage across one district boundary and returns the
-- (outerBand, sector) it was cut at, so the caller can place the gate model.
local function openGate(rng: Random, passages: { [string]: boolean }, outerBand: number, innerBand: number): number
	local s = rng:NextInteger(0, sectorsOf(outerBand) - 1)
	local ratioIn = sectorsOf(outerBand) / sectorsOf(innerBand)
	local innerS = math.floor(s / ratioIn)
	passages[pairKey(outerBand, s, innerBand, innerS)] = true
	return s
end
```

In `rebuild`, replace `local passages = carve(rng)` with:

```lua
local passages: { [string]: boolean } = {}
for _, range in DISTRICT_BANDS do
	carveRange(rng, passages, range[1], range[2])
end
local gateSectors = {}
for i, g in GATE_BOUNDARIES do
	gateSectors[i] = openGate(rng, passages, g[1], g[2])
end
addLoops(rng, passages)
```

**Account for:**
- The hub `(0,0)` is a single cell and needs no carve — `GATE_BOUNDARIES[1]`
  (`{1, 0}`) is what connects it.
- Delete the old `carve` function once nothing calls it; leaving a dead
  spanning-tree carve around invites someone reinstating it.
- Keep the existing `reachFrom` validation. It should now pass trivially, but it
  is the guard that catches a mistake in this step.

**Acceptance:** `lune run tools/split` clean. The existing connectivity assert in
`rebuild` must not fire across at least 20 different seeds (loop
`MazeService.rebuild(i)` for i = 1..20 in the Studio command bar).

---

## Step 2 — Keep loops inside districts

**File:** same, `addLoops`.

`addLoops` currently knocks out `EXTRA_LOOPS` random passages anywhere, which
would happily re-open a boundary and defeat the whole feature.

**Do:** skip any candidate whose two cells are in different districts.

```lua
local n = nbrs[rng:NextInteger(1, #nbrs)]
if districtOf(b) ~= districtOf(n[1]) then
	continue -- never re-open a sealed district boundary
end
```

**Account for:** the `continue` must still count toward `attempts` (it already
does — `attempts += 1` happens at the top of the loop) or a bad seed could spin.
The existing `attempts < 5000` bound stays.

**Acceptance:** after a rebuild, exactly **three** passages cross district
boundaries. Verify in the command bar by counting `pairKey`s whose two cells have
different `districtOf` — or more simply, confirm each gate radius has exactly one
gap in its arc wall.

---

## Step 3 — Build the gate models

**File:** same, in `rebuild`, after geometry is built.

Create a `workspace.Gates` folder (clear-and-rebuild each generation, same
pattern as `workspace.Maze`). For each of the three boundaries, build a lit arch
at the opening.

Position: radius `RADII[outerBand]`, angle
`(gateSector + 0.5) * (TWO_PI / sectorsOf(outerBand))`.

Shape: two vertical pillars flanking the passage plus a lintel across the top —
`WALL_H * 0.6` tall is enough to read without matching the wall height. Neon
accent colour plus a `PointLight` so it's visible through the fog when in line of
sight. Name each part `Gate`.

Each gate carries attributes:
- `EntersDistrict` (number) — the district on the **inner** side: `2`, `1`, `0`
  for the `{9,8}`, `{5,4}`, `{1,0}` boundaries respectively.

**Account for:**
- Gates are decoration and navigation only — **no `Touched` handler**. Checkpoint
  detection stays radius-based (Step 4).
- All parts `Anchored`, `CanCollide = false` so they never block the passage they
  mark.
- `workspace.Gates` must be rebuilt inside `rebuild` so it stays in sync with
  `MazeGeneration`; other features read it live.

**Acceptance:** after a rebuild, `workspace.Gates` holds 3 parts named `Gate`
with `EntersDistrict` 2, 1, 0, each sitting at the single opening in its arc wall.

---

## Step 4 — Checkpoint at the gate, not every ring

**File:** `src/features/Checkpoint/CheckpointService.server.luau`

It currently tracks the deepest **band** and re-checkpoints on every inward band
change.

**Do:** track the deepest **district** instead. Add the same `districtOf` helper
(or export it from `MazeNav` and require it — one definition, your call, but do
not copy-paste it into three files).

On a player's district decreasing:
1. Set `Checkpoint` to the **gate's CFrame** for the district they just entered
   (look it up in `workspace.Gates` by `EntersDistrict`), not the player's
   position. The gate is guaranteed to sit in an open passage, and respawning
   there is the readable "you fell back to the gate" beat.
2. Keep the existing `SafeUntil` grace and `CheckpointRing` attribute.

On the first read of a life (`prev == nil`), baseline the district silently as it
does today, and leave `Checkpoint` at the player's position (they haven't
crossed a gate yet).

**Account for:**
- Clear `deepest` on `MazeGeneration` — already done, keep it.
- `HunterService.catchPlayer` teleports to `Checkpoint` and already offsets by
  `+3` studs on Y; the gate CFrame must be a floor-level position so that offset
  lands the player standing, not inside the lintel.

**Acceptance:** crossing a gate sets `Checkpoint` to that gate. Crossing a plain
band boundary within a district does **not** change it. Get caught → you respawn
at the last gate.

---

## Step 5 — Point the compass at the next gate

**File:** `src/features/Pickups/CompassController.client.luau`

It currently always points at world-centre, which in a sealed maze walks you into
a wall when the gate is round the ring.

**Do:** each frame, pick the target as **the gate with the largest radius that is
still smaller than the player's radius** — i.e. the next one inward. If there is
none (player is already inside the innermost gate), fall back to world-centre.

```lua
local playerR = Vector2.new(hrp.Position.X, hrp.Position.Z).Magnitude
local target, targetR = Vector3.zero, -1
local gates = workspace:FindFirstChild("Gates")
for _, gate in (gates and gates:GetChildren() or {}) do
	if not gate:IsA("BasePart") then continue end
	local r = Vector2.new(gate.Position.X, gate.Position.Z).Magnitude
	if r < playerR and r > targetR then
		target, targetR = gate.Position, r
	end
end
```

Then bearing to `target` exactly as it bearings to centre today.

**Account for:**
- This needs **no district maths on the client** — radii alone give the right
  answer, and it self-heals across rebuilds because the folder is re-read live.
- Keep it a bearing, not a path: it ignores walls on purpose. Knowing the gate is
  north-east still leaves you solving the ring to reach it. That is the feature.
- The HUD position (y=116) and the `HasCompass` visibility gate are unchanged.

**Acceptance:** without a compass, nothing changes. With one, the arrow points at
the next gate inward and flips to the next target the moment you pass through one.

---

## Step 6 — Guarantee a compass in the outer district

**File:** `src/features/Pickups/Constants.luau` and `PickupsService.server.luau`

Placement is uniformly random today, so a player may never find a compass — and
with sealed districts, the compass is the tool that teaches the mechanic.

**Do:** add optional placement constraints to a `SPAWNS` entry and set them on
the Compass:

```lua
{ kind = "Compass", model = "Compass (by Artem Goyko)", count = 1,
  color = Color3.fromRGB(80, 200, 255), minBand = 9, maxBand = 12, minSpawnDist = 150 },
```

In `scatter()`, when an entry has `minBand`/`maxBand`, filter the shuffled cell
list to cells in that band range; when it has `minSpawnDist`, additionally
require the cell to be at least that far from `SpawnLocation`. Fall back to the
unconstrained list if the filter leaves nothing (never fail to place).

**Account for:**
- Bands 9–12 is the outer district, so the player can always reach it before the
  first gate.
- `minSpawnDist` keeps it off the straight-line inward route, so grabbing it is
  still a real detour decision rather than a freebie.
- `HasCompass` already persists for the whole run, so one find covers all three
  districts.

**Acceptance:** across 10 rebuilds the compass always lands in bands 9–12 and
always more than 150 studs from `SpawnLocation`.

---

## Step 7 — Docs

- **`docs/game/Maze.md`**: the district layout table, the carve-per-district
  algorithm, and the connectivity hazard from Step 1 (why not to seal
  after-the-fact). This is the single most important thing to write down.
- **`docs/game/Checkpoint.md`** (create if absent): checkpoints are gates now;
  the district trigger; respawn-at-gate.
- **`docs/game/Pickups.md`**: the compass placement constraints and why.
- **`docs/game/Flashlight.md`** / **`Hunter.md`**: no change needed.
- Index anything new in `docs/game/index.md`.

---

## Definition of Done

1. `lune run tools/split`, `check-views`, `check-framework-boundary` all pass.
2. Every district boundary has **exactly one** opening; the rest of each boundary
   ring is solid wall.
3. The maze is fully connected on **20 consecutive seeds** — the `reachFrom`
   assert never fires.
4. `workspace.Gates` holds 3 gates with `EntersDistrict` 2/1/0, each at its
   boundary's single opening, rebuilt on every `MazeGeneration`.
5. Crossing a gate sets `Checkpoint` to that gate; crossing an ordinary band
   boundary does not. Being caught respawns you at the last gate, standing (not
   clipped into geometry).
6. The compass points at the next gate inward and retargets after each one, and
   points to centre only in the innermost district.
7. A compass always spawns in bands 9–12, >150 studs from spawn.
8. No HUD text, objective line or gate counter was added.
9. The top-centre HUD stack is untouched (timer 12 / health 70 / stamina 94 /
   compass 116).
10. No debug `print`s remain.
