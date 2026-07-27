# TASKPLAN — Combat, pickups, and hunter abilities

## Context

Ringfall is currently pure evasion: hunters are unkillable and the only verb is
running/hiding. This adds a **retaliation loop** without abandoning the stealth
identity:

- **Scavenged pickups** scattered at random maze cells each round — a **gun**, a
  **compass**, a **stamina upgrade**, and **ammo**.
- A **gun** that damages hunters. 10 hits kills one; its health drains visibly on
  a bar over its head; on death it **explodes**, and a player caught in the blast
  is dragged to their checkpoint (reusing the existing catch — no new player-HP
  system).
- A **summon** ability: a hunter that gets shot alerts other nearby hunters to
  the shooter's position (with a siren the user will supply), so retaliating has
  a cost.

Two settled design decisions drive everything:

1. **Per-run scavenge.** Pickups and their effects are ephemeral: stored as
   **player attributes**, re-scattered every rebuild, wiped on RUN IT BACK.
   Nothing here goes in PlayerData — only the best time persists (already built).
2. **Scarce gun.** Ammo is found, never regenerates; a kill nearly empties you.
   Hiding stays the primary verb.

### Reused infrastructure (do not reinvent)

- **Hunters have a `Humanoid`** (`buildHunter`, `HunterService.server.luau`). The
  gun damages it via `Humanoid:TakeDamage`; Hunter reacts to `Humanoid.Died`.
  This is the whole cross-feature seam — the Gun feature never touches Hunter's
  source.
- **`workspace.MazeGeneration`** is the "maze changed" signal. Every world-placed
  thing re-scatters on it. First generation is set *inside* `MazeService.Start`
  before other services connect, so — exactly like Hunter/Checkpoint/Escape —
  each feature does an **initial placement in its own `Start()` after the
  `MazeReady` wait, then connects `GetAttributeChangedSignal("MazeGeneration")`
  for subsequent rounds.**
- **The catch sequence** `catchPlayer(player, char, hunter, root, growl)` is a
  closure inside `HunterService.Start`. The explosion catch lives in the same
  file, so it is in scope — do not export it.
- **`workspace.EvacAlert`** (an `os.clock()` timestamp attribute polled by every
  hunter loop) is the pattern the summon copies — see Phase 3.
- **Per-run attribute reset** already happens in one place: the `Net.Restart.listen`
  loop in `EscapeService.server.luau` that clears `Checkpoint`/`CheckpointRing`/
  `SafeUntil`. All new per-run attributes clear in that same loop.
- **Raw-instance HUDs**, not React: `SprintController` and `Controls` build their
  HUDs from plain `Instance.new`. The ammo counter, crosshair and compass follow
  that — **no `.ui.luau`, no UI Labs story, no `check-views` surface.**
- **Key legend**: register hints via a sibling `Controls.luau`
  (`function(Controls) Controls.registerControl{...} end`), never by editing the
  Controls feature.

---

## Out of scope / Do NOT

- **Do NOT** persist any pickup/ammo/upgrade state in PlayerData. Per-run only,
  via player attributes. Best-time persistence is already done and untouched.
- **Do NOT** add a player health/damage model. "Caught" stays a teleport to
  checkpoint. The explosion reuses `catchPlayer`; it does not deal HP damage.
- **Do NOT** build the gun's raycast on the client as authoritative. Client sends
  intent (a camera ray); the **server** re-raycasts from the character and
  applies damage. Never trust a client-reported hit.
- **Do NOT** make hunters killable without respawn — a dead hunter respawns at
  `farSpawn` after a delay so the maze never empties. `HUNTER_COUNT` stays 3.
- **Do NOT** parent pickups under `workspace.Maze` — `rebuild` calls
  `ClearAllChildren()` on it at an uncontrolled time. Use a separate
  `workspace.Pickups` folder the feature owns.
- **Do NOT** touch `SprintController`'s removed-crouch code, the `DUCK_*`/`EYE_*`
  constants, or the round-loop/cinematic work.
- **Do NOT** hardcode the siren asset id. Leave `SIREN_SOUND_ID = ""` (like the
  old crouch-anim seam); the summon works silently until the user supplies it.
- **Do NOT** build these HUDs in React / `.ui.luau`. Raw instances only.
- Reach hunters generically (iterate `workspace`, `IsA("Model")`,
  `Name == "Hunter"`) — the existing idiom in `HunterController` and
  `EscapeCinematicController`. Do not add a dependency on `HunterService`'s source.

---

# PHASE 1 — Pickups (gun grant, ammo, compass, stamina upgrade)

A new `src/features/Pickups/` feature. Scatters world pickups at random maze
cells each round; touching one grants a **per-run player attribute**; the
compass and stamina upgrade are consumed by small client/existing pieces.

## Per-run attributes (the contract)

Set by the server on pickup, read everywhere else, cleared on restart:

| Attribute | Type | Meaning |
| --------- | ---- | ------- |
| `HasGun` | bool | player owns the gun this run |
| `Ammo` | number | rounds remaining (authoritative, server-owned) |
| `HasCompass` | bool | compass HUD active |
| `StaminaBonus` | number | added to max stamina (studs of bar), 0 default |

## Step 1.1 — Constants + folder

**File (new):** `src/features/Pickups/Constants.luau`

```lua
--!strict
-- Plain .luau => ReplicatedStorage.Features.Pickups.Constants (shared realms).
return {
	FOLDER = "Pickups", -- workspace folder the feature owns
	FLOAT_Y = 3,        -- studs above the floor cell centre
	SPIN_DPS = 60,      -- visual spin, client-side
	-- What each round scatters. `count` distinct random cells per kind.
	SPAWNS = {
		{ kind = "Gun", count = 1, color = Color3.fromRGB(230, 180, 60) },
		{ kind = "Ammo", count = 4, color = Color3.fromRGB(240, 130, 60), amount = 6 },
		{ kind = "Compass", count = 1, color = Color3.fromRGB(80, 200, 255) },
		{ kind = "Stamina", count = 1, color = Color3.fromRGB(120, 230, 150), amount = 50 },
	},
	GUN_START_AMMO = 12, -- the Gun pickup also grants this much ammo
}
```

## Step 1.2 — Server: scatter + grant

**File (new):** `src/features/Pickups/PickupsService.server.luau`

`PickupsService.Priority = 12` (after MazeService = 5, so `MazeNav` is populated).

`Start()`:
1. Wait on `workspace.MazeReady` (same guard as EscapeService).
2. `local folder = Instance.new("Folder"); folder.Name = Constants.FOLDER; folder.Parent = workspace`.
3. Define `local function scatter()` — see below — and call it once.
4. `workspace:GetAttributeChangedSignal("MazeGeneration"):Connect(scatter)`.
5. Grant-on-touch (see below).

`scatter()`:
- `folder:ClearAllChildren()`.
- Snapshot cell keys from `MazeNav.cellPos` (same loop `HunterService` uses),
  **excluding band 0** (the hub/exit) via `MazeNav.bandOf(key) > 0`.
- Shuffle with `Random.new()` (unseeded — placement differs every play even on
  the same maze seed, satisfying "items in different locations each time").
- Walk `Constants.SPAWNS`, drawing `count` distinct cells per kind (pop from the
  shuffled list so no two pickups share a cell), and build a part at
  `MazeNav.cellPos[key] + Vector3.new(0, FLOAT_Y, 0)`.

Each pickup part: a 2×2×2 `Part`, `Neon`, `Anchored`, `CanCollide = false`,
`CanTouch = true`, colored per kind, `Shape = Ball`, plus a `PointLight`. Set a
string attribute `PickupKind` and (for Ammo/Stamina) a number attribute
`PickupAmount`. Parent to `folder`.

Grant-on-touch — one `Touched` connection per part:
```lua
part.Touched:Connect(function(hit)
	local player = playerFromPart(hit) -- copy the helper from EscapeService
	if not player or not part.Parent then return end
	local kind = part:GetAttribute("PickupKind")
	grant(player, kind, part:GetAttribute("PickupAmount"))
	part:Destroy() -- consumed; one grab
end)
```

`grant(player, kind, amount)`:
- `"Gun"` → `player:SetAttribute("HasGun", true)`; add `GUN_START_AMMO` to `Ammo`.
- `"Ammo"` → `Ammo += amount`.
- `"Compass"` → `HasCompass = true`.
- `"Stamina"` → `StaminaBonus += amount`.

Read-modify-write `Ammo`/`StaminaBonus` via `(player:GetAttribute(x) or 0) + n`.

**Account for:** `part.Parent` nil-check guards the double-fire (multiple body
parts touching in one frame) — first touch `Destroy()`s it, the rest bail. Same
reasoning as EscapeService's `escaped` debounce.

## Step 1.3 — Clear per-run state on restart

**File:** `src/features/Maze/EscapeService.server.luau`, in the `Net.Restart.listen`
loop, alongside the existing `Checkpoint` clears:

```lua
plr:SetAttribute("HasGun", nil)
plr:SetAttribute("Ammo", nil)
plr:SetAttribute("HasCompass", nil)
plr:SetAttribute("StaminaBonus", nil)
```

Do **not** clear these in `resetState` — that runs on every respawn, and a caught
player teleported to their checkpoint must keep their loot (same run).

## Step 1.4 — Client spin + pickup toast

**File (new):** `src/features/Pickups/PickupsController.client.luau`

- `RunService.Heartbeat`: spin every part under `workspace.Pickups` by
  `SPIN_DPS * dt` about Y (visual only, `part.CFrame *= CFrame.Angles(0, d, 0)`).
  Guard the folder existing (`workspace:FindFirstChild(Constants.FOLDER)`).
- A **toast**: a raw ScreenGui label (bottom-centre) that fades a short message
  when a relevant attribute changes on the local player — connect
  `GetAttributeChangedSignal` for `HasGun` / `HasCompass` / `StaminaBonus` /
  `Ammo` and flash e.g. "PICKED UP: COMPASS". Follow `SprintController`'s raw-HUD
  + `TweenService` fade style.

## Step 1.5 — Stamina upgrade consumer

**File:** `src/features/Sprint/SprintController.client.luau`

`MAX_STAMINA` is currently a fixed local. Inside the heartbeat, compute the
effective max live:
```lua
local maxStamina = MAX_STAMINA + (player:GetAttribute("StaminaBonus") or 0)
```
and use `maxStamina` in the clamp, the regen `math.min`, and the bar-fill ratio
(`stamina / maxStamina`). Clamp current `stamina` up to the new max so a mid-run
upgrade is felt immediately.

## Step 1.6 — Compass HUD

**File (new):** `src/features/Pickups/CompassController.client.luau`

Raw HUD, only visible when `player:GetAttribute("HasCompass")`. An arrow (a
rotated `ImageLabel` with a simple triangle, or a `TextLabel` "▲") pinned
top-centre that points toward world-centre `(0,0,0)` — the exit. Each frame:
compute the bearing from the camera's look direction to the flat direction
`(-charPos)` and rotate the arrow by that yaw difference. Hide the frame when the
attribute is false/nil.

**File (new):** `src/features/Pickups/Controls.luau` — register nothing yet
(pickups are touch-based, no key). Skip this file. The gun adds its own in Phase 3.

## Phase 1 acceptance

- `lune run tools/split` / `check-views` / `check-framework-boundary` all pass.
- In Studio (manual): after spawn, `workspace.Pickups` holds glowing balls at
  random cells; touching the Gun ball sets `HasGun`/`Ammo`, Compass shows the
  arrow, Stamina raises the bar. RUN IT BACK re-scatters to new cells and clears
  all four attributes.

---

# PHASE 2 — Hunter combat response (health, death, explosion, summon)

All in `src/features/Hunter/HunterService.server.luau`. No new feature — the
hunter owns everything about being a hunter.

## Step 2.1 — Health + bar

In `buildHunter`, after the `Humanoid`:
```lua
hum.MaxHealth = HUNTER_HITS -- new constant = 10
hum.Health = HUNTER_HITS
```
So each 1-damage shot is one hit; 10 kills it.

Add a `BillboardGui` over the head (parented to `root`, `StudsOffset` ~ (0, 4,
0), `Size` `UDim2.fromOffset(120, 12)`, `AlwaysOnTop = true`) containing a dark
background `Frame` and a red fill `Frame`. Start it hidden
(`billboard.Enabled = false`).

Connect `hum.HealthChanged`:
```lua
hum.HealthChanged:Connect(function(health)
	billboard.Enabled = health < hum.MaxHealth
	fill.Size = UDim2.fromScale(math.clamp(health / hum.MaxHealth, 0, 1), 1)
end)
```
Property changes on the GUI replicate to clients, so the draining bar is visible
to everyone without any client code.

**Account for:** `HUNTER_HITS` is a new top-of-file constant. Keep the drone/eye
build unchanged.

## Step 2.2 — Death → explosion → catch → respawn

Still in `spawnHunter` (so `catchPlayer`, `farSpawn`, `spawnLocation` are in
scope), connect death once:
```lua
hum.Died:Connect(function()
	explodeAt(root.Position)          -- see below
	-- Catch anyone in the blast (reuses the existing catch/checkpoint flow).
	for _, plr in Players:GetPlayers() do
		if outOfRound(plr) then continue end
		local c = plr.Character
		local phrp = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
		if phrp and (phrp.Position - root.Position).Magnitude < BLAST_RADIUS then
			catchPlayer(plr, c, hunter, root, growl)
		end
	end
	hunter:Destroy()
	task.delay(RESPAWN_DELAY, spawnHunter) -- keep the maze populated
end)
```

`explodeAt(pos)` — a module-level helper: build a `Neon` ball at `pos`, tween its
`Size` up and `Transparency` to 1 over ~0.4s (`TweenService`), then `Destroy`. A
`PointLight` flash optional. No asset needed. (The user may later add a boom
sound; leave a `local BLAST_SOUND_ID = ""` seam and play it if set.)

New constants: `BLAST_RADIUS = 14`, `RESPAWN_DELAY = 4`.

**Account for:** `catchPlayer` early-returns if the player is already `Caught`, so
a multi-hunter chain can't double-catch. `spawnHunter` re-entrancy is fine — it's
already the function the startup loop calls `HUNTER_COUNT` times.

## Step 2.3 — Summon (alert nearby hunters to the shooter)

When a hunter takes damage, throttle-broadcast the shooter's position so nearby
hunters converge — the `EvacAlert` idiom, with a position and a radius.

Producer — add a module function the Gun feature's damage path will call
*indirectly via the Humanoid* won't work (Humanoid has no "who shot me"). So the
**server damage handler in Phase 3 sets the attributes**; Phase 2 only consumes.
Define the consumer here and the constants:

```lua
local SUMMON_WINDOW = 5      -- seconds other hunters beeline to the alert
local SUMMON_RADIUS = 200    -- only hunters within this of the alert respond
local SIREN_SOUND_ID = ""    -- user supplies; siren plays on the shot hunter
```

In the per-hunter decision loop, add a branch **after** the `EvacAlert` branch
and **before** CHASE:
```lua
local sAlert = workspace:GetAttribute("HunterAlert")
local sPos = workspace:GetAttribute("HunterAlertPos") -- Vector3 attribute
if typeof(sAlert) == "number" and os.clock() - sAlert < SUMMON_WINDOW
	and typeof(sPos) == "Vector3"
	and (root.Position - sPos).Magnitude < SUMMON_RADIUS then
	hum.WalkSpeed = MAX_SPEED
	stepToward(MazeNav.nearestCell(sPos))
	task.wait(REPATH)
	continue
end
```

(`workspace` attributes *do* accept `Vector3` directly — no need to split X/Z.)

Reset these on rebuild inside the existing `MazeGeneration` listener
(`workspace:SetAttribute("HunterAlert", nil)`), so a stale alert can't carry into
a new round.

## Phase 2 acceptance

- Checks pass. In Studio command bar, on a hunter's Humanoid:
  `hum:TakeDamage(1)` five times — the bar appears and drains; `hum.Health = 0`
  triggers the explosion, catches a nearby player (checkpoint teleport), and a
  replacement hunter appears at a far cell ~4s later.

---

# PHASE 3 — The gun (client aim/fire/HUD + server-validated hit)

A new `src/features/Gun/` feature. Client fires; server raycasts and damages.

## Step 3.1 — Net

**File (new):** `src/features/Gun/Net.luau` — namespace `"Gun"`, one packet:
```lua
Shoot = ByteNet.definePacket({
	value = ByteNet.struct({
		origin = ByteNet.vector3,     -- camera position (informational)
		direction = ByteNet.vector3,  -- unit aim direction
	}),
	reliabilityType = "reliable",
}),
```
(Match `ByteNet` type names to the version in `Maze/Net.luau`; if `vector3` isn't
exported, send three `float32`s and rebuild the `Vector3` server-side.)

## Step 3.2 — Server: validate + damage + summon trigger

**File (new):** `src/features/Gun/GunService.server.luau`, `Priority = 12`.

`Net.Shoot.listen(function(payload, player)`:
1. Reject unless `player:GetAttribute("HasGun")` and `(player:GetAttribute("Ammo") or 0) > 0`.
2. Decrement ammo: `player:SetAttribute("Ammo", ammo - 1)`.
3. Re-raycast **from the character**, not the client's claimed origin: origin =
   character `HumanoidRootPart.Position + headOffset`, direction = `payload.direction.Unit`,
   length `GUN_RANGE` (~300). `RaycastParams` excluding the player's own character.
4. If the hit instance's ancestor `Model.Name == "Hunter"`, find its `Humanoid`
   and `hum:TakeDamage(1)`.
5. On a hunter hit, **fire the summon**: `workspace:SetAttribute("HunterAlert", os.clock())`
   and `workspace:SetAttribute("HunterAlertPos", character.HumanoidRootPart.Position)`.
   Play the siren on the hit hunter if `SIREN_SOUND_ID ~= ""`.

**Account for:** all authority is here — ammo, range, and whether a hunter was
actually in the ray. The client packet is a *request*. Throttle server-side too:
ignore a player's shots that arrive faster than `FIRE_COOLDOWN` (~0.2s), tracked
in a per-player `{[Player]: number}` table, so a spoofed client can't machine-gun.

## Step 3.3 — Client: input, fire, crosshair, ammo HUD

**File (new):** `src/features/Gun/GunController.client.luau`

- Only active when `player:GetAttribute("HasGun")`.
- Raw HUD: a centre **crosshair** (small frame/“+”) and an **ammo counter**
  (bottom-right, "AMMO n") both shown only while `HasGun`. Update the counter on
  `GetAttributeChangedSignal("Ammo")`.
- `UserInputService.InputBegan` for `Enum.UserInputType.MouseButton1`
  (guard `gameProcessedEvent`): if `HasGun` and local `Ammo > 0` and past the
  local `FIRE_COOLDOWN`, send `Net.Shoot.send({ origin = camera.CFrame.Position,
  direction = camera.CFrame.LookVector })`. Local cooldown is feel only; the
  server enforces the real one.
- Optional muzzle/tracer: a brief `Beam` or a thin neon part from character to
  the client raycast hit — visual only, fine to skip in the greybox.

## Step 3.4 — Controls hint

**File (new):** `src/features/Gun/Controls.luau`:
```lua
return function(Controls)
	Controls.registerControl({ key = "MOUSE 1", label = "Shoot (when armed)", order = 25 })
end
```

## Phase 3 acceptance

- Checks pass. In a playtest: with no gun, clicking does nothing and no HUD shows.
  After grabbing the Gun pickup, the crosshair + ammo appear; clicking a hunter
  drains its bar; 10 hits kills it (explosion + far respawn); ammo decrements and
  clicking at 0 does nothing; other hunters within range converge on you after a
  hit.

---

## Studio assets the user must provide

- **Siren sound** — set `SIREN_SOUND_ID` in `HunterService` / `GunService`.
  Works silently until then.
- **(Optional) explosion sound** — `BLAST_SOUND_ID` in `HunterService`.
- No models required: pickups, crosshair, health bar, compass and explosion are
  all code-built.

## Docs (Phase 4)

- `docs/game/Pickups.md`: the four per-run attributes, the scatter/clear
  lifecycle, placement via `MazeNav.cellPos`.
- `docs/game/Gun.md`: client-request/server-authority split, ammo economy, the
  `Humanoid.TakeDamage` seam, `FIRE_COOLDOWN`.
- Update `docs/game/Hunter.md`: health/bar, death→explosion→catch→respawn, and
  the summon (`HunterAlert`/`HunterAlertPos`, distinct from `EvacAlert`).
- Add all to `docs/game/index.md`.

---

## Definition of Done

1. `split`, `check-views`, `check-framework-boundary` all pass after every phase.
2. Pickups scatter at **random cells that differ every round**, are one-grab, and
   all four per-run attributes clear on RUN IT BACK (verified across ≥3 rounds).
3. Stamina upgrade visibly raises the bar mid-run; compass arrow tracks the centre.
4. The gun is client-request / server-authoritative: ammo, range, fire-rate and
   hit validation are all server-side; a client cannot fire without `HasGun`,
   past 0 ammo, or faster than `FIRE_COOLDOWN`.
5. A hunter shows a draining health bar, dies on the 10th hit, explodes, catches a
   player in `BLAST_RADIUS` via the existing checkpoint flow, and is replaced at a
   far cell after `RESPAWN_DELAY`. `HUNTER_COUNT` hunters remain over time.
6. Shooting a hunter makes other hunters within `SUMMON_RADIUS` converge on the
   shooter for `SUMMON_WINDOW`; the alert clears on rebuild and never carries over.
7. The Gun feature never requires `HunterService`'s source — damage flows only
   through `Humanoid:TakeDamage`.
8. No PlayerData writes for any pickup/ammo/upgrade state.
9. `SIREN_SOUND_ID` / `BLAST_SOUND_ID` are `""` seams, not hardcoded ids.
10. No debug `print`s remain.
```
