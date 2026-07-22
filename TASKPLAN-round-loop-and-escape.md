# TASKPLAN — Round loop + escape payoff

## Context

Reaching the evac pad at the maze centre currently ends in a hard cut: the
character is anchored mid-stride and a static panel appears. There is no payoff
beat, and pressing RUN IT BACK drops you into the *same* maze at the *same*
spawn, so there is no reason to run it again.

This plan does three things:

1. **A cinematic escape.** The camera unhooks and pulls up and back over the maze
   you just crossed, hunters converging on the pad too late, then the win panel
   fades in over the shot.
2. **A real new round.** RUN IT BACK regenerates the maze with a new seed, so the
   walls change, and drops you at a new random spawn that is always far from the
   centre.
3. **A personal best**, persisted through PlayerData, with a NEW BEST stamp.

### The one thing that will bite you

`MazeService` rebuilds by calling `mazeFolder:ClearAllChildren()`. That destroys
`ExitGate` **and** the `EscapeZone` part that `EscapeService` parented in there.
`EscapeService` captured `exitGate` as a local at `Start()` and wired
`exitGate.Touched` to it once. After a rebuild those references point at
destroyed instances and **the win condition silently stops working**.

`workspace.MazeReady` cannot solve this: it is set to `true` once and never
cleared, so `GetAttributeChangedSignal("MazeReady")` will not fire again.

The fix used throughout this plan is a new monotonic counter attribute
**`workspace.MazeGeneration`**, incremented on every build including the first.
Services listen to it and re-wire. Do not invent a second mechanism.

---

## Out of scope / Do NOT

- **Do NOT** give each player their own maze. The maze is one shared world; a
  restart is a **server-wide new round** for everyone. Per-player instancing is
  not in scope.
- **Do NOT** touch `src/features/Sprint/SprintController.client.luau` or
  `CROUCH_ANIMATION_ID`. Crouch is a separate open thread.
- **Do NOT** touch the duck avatar constants in `HunterService` (`DUCK_*`,
  `EYE_*`). Eye placement was measured in Studio and must not be "tidied".
- **Do NOT** change `RADII`, `SECTORS`, `BANDS`, `WALL_H`, `WALL_T` or
  `FLOOR_Y`. Band geometry is fixed; only the *passage* pattern changes per seed.
- **Do NOT** clear or re-set `workspace.MazeReady` to false. Other services
  `:Wait()` on it and would deadlock. It stays a one-way latch.
- **Do NOT** add new Studio assets. Everything here is code.
- **Do NOT** write a UI Labs story for the cinematic (it is not a component).
  You **must** update the existing `WinScreen.story.luau` if one exists; if it
  does not, create one — see Step 7.
- **Do NOT** reassign `profile.Data`. Persist only via
  `PlayerDataService.SetValue`.

---

## Step 1 — Extract a re-runnable `rebuild(seed)` in MazeService

**File:** `src/features/Maze/MazeService.server.luau`

Today all generation is inline in `MazeService.Start()` (lines ~197-342).

**Do:** move the entire body of `Start()` from the `local rng = Random.new(...)`
line through the `MazeNav` population into a new module-level function:

```lua
-- Builds (or rebuilds) the whole maze from `seed`. Safe to call repeatedly:
-- clears the existing Maze folder, repositions the existing SpawnLocation,
-- and fully repopulates MazeNav.
function MazeService.rebuild(seed: number)
	local rng = Random.new(seed)
	-- ... existing generation body, unchanged ...
	workspace:SetAttribute("MazeSeed", seed)
	workspace:SetAttribute("MazeGeneration", (workspace:GetAttribute("MazeGeneration") or 0) + 1)
end
```

`Start()` becomes:

```lua
function MazeService.Start()
	MazeService.rebuild(Constants.SEED)
	workspace:SetAttribute("MazeReady", true)
end
```

**Account for:**
- `MazeGeneration` must be incremented **at the very end** of `rebuild`, after
  `MazeNav.ready = true`. Listeners re-read `MazeNav` the moment it changes.
- `MazeReady` stays in `Start()`, set exactly once, and is never cleared.
- The `spawnRng` currently declared separately (line ~268) must be **deleted**;
  spawn placement now uses the same seeded `rng` so a seed fully determines the
  round. Step 2 changes the band it picks.
- Keep the `mazeFolder:ClearAllChildren()` behaviour — it is what makes rebuild
  work.

**Acceptance:** `lune run tools/split` completes without throwing. In Studio,
run on the server: `print(workspace:GetAttribute("MazeGeneration"))` → `1`.

---

## Step 2 — Spawn far from the centre

**File:** `src/features/Maze/MazeService.server.luau`, inside `rebuild`.

The spawn band is currently `rng:NextInteger(3, math.max(3, BANDS - 2))`, which
can land mid-maze. The round must always start a long way out.

**Replace with:**

```lua
-- Always start in the outer rings — a run should be a long haul inward.
local SPAWN_MIN_BAND = BANDS - 2 -- 10
local spawnBand = rng:NextInteger(SPAWN_MIN_BAND, BANDS) -- 10..12
```

Declare `SPAWN_MIN_BAND` with the other constants at the top of the file, not
inline.

**Account for:**
- `BANDS = 12` and `RADII[13] = 534`, so bands 10-12 sit at roughly radius
  450-534 — the outermost usable rings.
- Keep the existing random-sector pick, mid-radius/mid-angle positioning, `y = 4`
  and `CFrame.lookAt` toward the centre. Only the band range changes.

**Acceptance:** in Studio, run on the server:
```lua
local sl = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
print((Vector3.new(sl.Position.X, 0, sl.Position.Z)).Magnitude)
```
→ a value **greater than 430** on every rebuild. Rebuild 5 times with different
seeds and confirm it never drops below that.

---

## Step 3 — Re-wire EscapeService on rebuild

**File:** `src/features/Maze/EscapeService.server.luau`

This is the footgun step. `exitGate`, `mazeFolder` and `EscapeZone` are captured
once and destroyed by a rebuild.

**Do:** extract the zone-creation and gate-wiring into a function that can re-run,
and call it whenever `MazeGeneration` changes.

```lua
local gateConnection: RBXScriptConnection? = nil
local zonePart: BasePart? = nil

-- (Re)binds to the current maze geometry. Called once at Start and again after
-- every rebuild, because ClearAllChildren destroys both the gate and the zone.
local function bindToMaze()
	local mazeFolder = workspace:WaitForChild("Maze")
	local exitGate = mazeFolder:WaitForChild("ExitGate") :: BasePart

	if gateConnection then
		gateConnection:Disconnect()
	end
	if zonePart then
		zonePart:Destroy()
	end

	zonePart = <existing EscapeZone creation, parented to mazeFolder,
	             positioned from spawnLocation.CFrame>
	gateConnection = exitGate.Touched:Connect(onGateTouched)
end
```

Move the existing `exitGate.Touched:Connect(function(hit) ... end)` body into a
named `onGateTouched(hit: BasePart)` declared **above** `bindToMaze`.

Then in `Start()`, after the `MazeReady` wait:

```lua
bindToMaze()
workspace:GetAttributeChangedSignal("MazeGeneration"):Connect(bindToMaze)
```

**Account for:**
- `spawnLocation` may stay captured — `MazeService` repositions the *same*
  instance rather than recreating it, so `spawnLocation.CFrame` reads live and
  stays correct. Only the folder, gate and zone need re-fetching.
- Disconnect the old `Touched` before connecting the new one, or a stale
  connection leaks per round.
- The zone must be recreated because it is parented into `mazeFolder` and gets
  cleared.

**Acceptance:** in Studio, call `MazeService.rebuild(2002)` on the server, then
walk onto the new centre pad. The `Escaped` packet must still fire and the win
screen must still appear. Before this step it will not.

---

## Step 4 — Restart triggers a new round

**File:** `src/features/Maze/EscapeService.server.luau`, in `Net.Restart.listen`.

Currently it unanchors, resets state and teleports the caller to the old spawn.

**Replace the handler body with:**

```lua
Net.Restart.listen(function(_payload, player)
	-- A restart is a server-wide new round: new walls, new far spawn, everyone
	-- reset. Per-player mazes would need instancing and are out of scope.
	MazeService.rebuild(Random.new(os.clock() * 1000):NextInteger(1, 2 ^ 31 - 1))

	for _, plr in Players:GetPlayers() do
		resetState(plr)
		plr:SetAttribute("Checkpoint", nil)
		plr:SetAttribute("CheckpointRing", nil)
		plr:SetAttribute("SafeUntil", nil)
		local character = plr.Character
		if not character then
			continue
		end
		setCharacterAnchored(character, false)
		character:PivotTo(spawnLocation.CFrame + Vector3.new(0, 3, 0))
	end
end)
```

Add at the top of the file:
```lua
local MazeService = require(game:GetService("ServerScriptService").Features.Maze.MazeService)
```

**Account for:**
- Clearing `Checkpoint` is **required**, not optional. It stores a raw world-space
  `CFrame`; after a re-carve that exact point may be inside a new wall, and
  `HunterService.catchPlayer` teleports caught players straight to it.
- `+ Vector3.new(0, 3, 0)` prevents spawning inside the floor.
- `resetState` already sets `Escaped = false`, which re-arms the hunters.
- Use `Players` — already required at the top of the file.

**Acceptance:** escape, press RUN IT BACK, and confirm: the wall layout visibly
differs, you are standing far from the centre, the timer is reset, and
`print(workspace:GetAttribute("MazeSeed"))` differs from the previous round.

---

## Step 5 — Refresh HunterService and CheckpointService on rebuild

**File A:** `src/features/Hunter/HunterService.server.luau`

`Start()` snapshots `cellKeys` and `maxBand` once (lines ~175-180). After a
rebuild the adjacency graph has changed.

**Do:** hoist those two into upvalues and add a refresh function:

```lua
local cellKeys: { number } = {}
local maxBand = 0

local function refreshNav()
	cellKeys = {}
	for key in MazeNav.cellPos do
		table.insert(cellKeys, key)
	end
	maxBand = MazeNav.maxBand()
end
```

Call `refreshNav()` where the snapshot used to happen, then:
```lua
workspace:GetAttributeChangedSignal("MazeGeneration"):Connect(function()
	refreshNav()
	-- old wander/search targets refer to the previous layout
	for _, hunter in workspace:GetChildren() do
		if hunter:IsA("Model") and hunter.Name == "Hunter" then
			hunter:PivotTo(CFrame.new(farSpawn(spawnLocation.Position)))
		end
	end
end)
```

**Account for:** per-hunter `lastKnownCell` and `wanderTarget` are closure locals
inside `spawnHunter`. Re-homing the model is enough — `stepToward` re-reads
`MazeNav` live each step and will re-path within one `REPATH` tick (0.7s).

**File B:** `src/features/Checkpoint/CheckpointService.server.luau`

Add, after the `MazeReady` wait:

```lua
workspace:GetAttributeChangedSignal("MazeGeneration"):Connect(function()
	table.clear(deepest)
end)
```

So every player re-baselines their deepest band against the new layout.

**Acceptance:** rebuild mid-run with hunters active. They must resume chasing
within ~1 second and must not walk through walls or freeze.

---

## Step 6 — Persist a personal best

**File A (new):** `src/features/Maze/PlayerData.luau`

```lua
-- Maze's slice of the PlayerData profile template. Discovered by
-- src/features/PlayerData/init.luau at load time.

return function(PlayerData)
	PlayerData.registerTemplate("Ringfall", { BestTimeSeconds = 0 })
end
```

Use `0` for "no best yet", not `nil` — ProfileStore templates do not keep nil
keys.

**File B:** `src/features/Maze/Net.luau` — extend the `Escaped` packet:

```lua
Escaped = ByteNet.definePacket({
	value = ByteNet.struct({
		timeSeconds = ByteNet.float32,
		bestSeconds = ByteNet.float32, -- 0 = no previous best
		isNewBest = ByteNet.bool,
	}),
	reliabilityType = "reliable",
}),
```

**File C:** `src/features/Maze/EscapeService.server.luau`, in `onGateTouched`,
replacing the current `Net.Escaped.sendTo({ timeSeconds = elapsed }, player)`:

```lua
local data = PlayerDataService.GetData(player)
local previous = if data and data.Ringfall then data.Ringfall.BestTimeSeconds else 0
local isNewBest = previous <= 0 or elapsed < previous
if isNewBest then
	PlayerDataService.SetValue(player, { "Ringfall", "BestTimeSeconds" }, elapsed)
end
Net.Escaped.sendTo({
	timeSeconds = elapsed,
	bestSeconds = if isNewBest then elapsed else previous,
	isNewBest = isNewBest,
}, player)
```

Require `PlayerDataService` from the server realm:
```lua
local PlayerDataService = require(game:GetService("ServerScriptService").Features.PlayerData.PlayerDataService)
```

**Account for:** send the packet **after** `SetValue` so the payload and the
replica agree. Guard `data` being nil (profile still loading) — treat as no best.

**Acceptance:** escape twice, second run slower. First shows NEW BEST, second
shows the first run's time as the best and no stamp. Rejoin and confirm the best
survives.

---

## Step 7 — Win screen: best time + NEW BEST

**File:** `src/features/Maze/WinScreen.ui.luau`

Extend `Props`:
```lua
type Props = {
	timeSeconds: number,
	bestSeconds: number,
	isNewBest: boolean,
	onRestart: () -> (),
}
```

Add, between `Time` (layoutOrder 2) and `RestartButton` (bump it to 4):

- When `props.isNewBest` is true, a `ui.Text` reading `NEW BEST`, `layoutOrder = 3`,
  `textSize = 28`, `weight = Enum.FontWeight.Heavy`,
  colour `Color3.fromRGB(120, 230, 150)`.
- Otherwise, when `props.bestSeconds > 0`, a `ui.Text` reading
  `"BEST " .. formatTime(props.bestSeconds)`, `layoutOrder = 3`,
  `textSize = 24`, colour `Color3.fromRGB(170, 180, 190)`.
- When neither applies, render `nil` for that slot.

Grow `PANEL_SIZE` from `UDim2.fromOffset(520, 320)` to
`UDim2.fromOffset(520, 380)` to fit the extra row.

**This file is a view.** It must stay dumb — no networking, no persistence, no
`os.clock`. It receives everything through props. `tools/check-views` enforces
this and will fail the build otherwise.

**Also:** create `src/features/Maze/WinScreen.story.luau` if absent, with
`UILabs.Checkbox` for `isNewBest` and `UILabs.Slider` for `timeSeconds` and
`bestSeconds`. Follow the pattern in `src/shared/ui/*.story.luau`.

**File:** `src/features/Maze/UIController.client.luau` — store the new fields
alongside `winTime` in the `Escaped` listener and pass all three into
`WinScreen`.

**Acceptance:** open UI Labs, toggle `isNewBest`, and confirm both states render
without the layout jumping or text clipping.

---

## Step 8 — The cinematic

**File (new):** `src/features/Maze/EscapeCinematicController.client.luau`

Auto-loaded (name ends in `Controller`). Exposes one intent action.

```lua
local RISE = Vector3.new(0, 220, 260) -- offset from the character at the end
local FLIGHT_TIME = 1.8
local HOLD_TIME = 0.5

-- Detaches the camera and flies it up and back over the maze. Resolves when the
-- shot has settled, so the caller can bring the win panel up over it.
function EscapeCinematicController.play(): ()
```

Body:
1. `local char = player.Character`; bail immediately (return) if absent.
2. Fade every hunter drone locally so the shot lands in silence:
   ```lua
   for _, m in workspace:GetChildren() do
       if m:IsA("Model") and m.Name == "Hunter" then
           local s = m.PrimaryPart and m.PrimaryPart:FindFirstChild("HunterDrone")
           if s then TweenService:Create(s, TweenInfo.new(0.3), { Volume = 0 }):Play() end
       end
   end
   ```
3. `camera.CameraType = Enum.CameraType.Scriptable`.
4. Tween a `NumberValue` 0→1 over `FLIGHT_TIME` with
   `Enum.EasingStyle.Quart, Enum.EasingDirection.Out`; on each change set
   `camera.CFrame = CFrame.lookAt(startPos:Lerp(endPos, t), charPos)` where
   `endPos = charPos + RISE` and `charPos` is captured once at the start.
5. `task.wait(HOLD_TIME)`, then return.

Add `EscapeCinematicController.stop()` which sets
`camera.CameraType = Enum.CameraType.Custom` and restores drone volumes to `0.8`.

**File:** `src/features/Maze/UIController.client.luau`

Require the sibling client module:
```lua
local EscapeCinematic = require(script.Parent.EscapeCinematicController)
```
In the `Escaped` listener, `task.spawn` the cinematic and set the win state only
after it resolves:
```lua
Net.Escaped.listen(function(payload)
	setRunning(false)
	task.spawn(function()
		EscapeCinematic.play()
		setWinState(payload)
	end)
end)
```
In `onRestart`, call `EscapeCinematic.stop()` **before** sending
`Net.Restart.send(nil)`, so the camera is back on the character before the
teleport.

**Account for:**
- The character is already anchored server-side, so it holds its pose. Do not
  anchor again client-side.
- Guard against the player dying or leaving mid-flight: re-check
  `player.Character` each tween step and abort to `stop()` if it vanishes.
- `LookBackController` also writes `camera.CFrame` every frame at
  `Camera.Value + 1`. It already bails when `Caught` is set, but **not** when
  escaped. Add `player:GetAttribute("Escaped")` to that same guard in
  `src/features/LookBack/LookBackController.client.luau`, or the two will fight
  for the camera. This is a one-line change to an existing early-return.

**Acceptance:** escape and watch. The camera must rise and pull back smoothly,
the maze must be visible below, hunter audio must fade out, and the panel must
appear only after the shot settles. Press RUN IT BACK — the camera must snap back
to normal third person with no drift.

---

## Step 9 — Hunters converge on the pad

**File:** `src/features/Maze/EscapeService.server.luau`, in `onGateTouched`,
after setting the `Escaped` attribute:

```lua
workspace:SetAttribute("EvacAlert", os.clock())
```

**File:** `src/features/Hunter/HunterService.server.luau`, in the per-hunter
decision loop, as a new branch **before** the existing CHASE check:

```lua
local alert = workspace:GetAttribute("EvacAlert")
if typeof(alert) == "number" and os.clock() - alert < 4 then
	hum.WalkSpeed = MAX_SPEED
	stepToward(MazeNav.nearestCell(Vector3.zero))
	task.wait(REPATH)
	continue
end
```

So for four seconds after any escape, every hunter sprints for the centre —
arriving in shot, and too late.

**Acceptance:** escape while a hunter is within a few rings of the centre. During
the pull-back it must visibly move toward the pad, not wander off.

---

## Step 10 — Docs

- Update `docs/game/Maze.md` (create if absent): the seed is now per-round, the
  `MazeGeneration` re-wire contract, the far-spawn rule, and the rebuild footgun
  from the top of this plan.
- Update `docs/game/Hunter.md`: the `EvacAlert` behaviour and the nav refresh.
- Create `docs/game/Escape.md`: the round state machine, the packets and their
  new fields, the cinematic timings, and the personal-best storage key.
- Add all of the above to `docs/game/index.md`.

---

## Definition of Done

All must be true. Stop when they are.

1. `lune run tools/split`, `lune run tools/check-views` and
   `lune run tools/check-framework-boundary` all pass.
2. Escaping plays the camera flight, then the panel appears over it.
3. RUN IT BACK produces a **visibly different wall layout** and a spawn more than
   430 studs from the centre, every time, across at least 5 consecutive rounds.
4. The win condition still fires on rounds 2, 3, 4 and 5 — i.e. `EscapeService`
   re-bound to the new `ExitGate` (this is the regression Step 3 exists to
   prevent; test it explicitly, not just on round 1).
5. Hunters resume chasing within ~1 second of a rebuild and do not path through
   walls.
6. A caught player after a rebuild respawns somewhere valid, never inside a wall.
7. Personal best persists across a rejoin, and NEW BEST shows only on an
   improvement.
8. The camera returns to normal third person after restart, and holding Q still
   works with movement unaffected.
9. No debug `print` statements remain.
