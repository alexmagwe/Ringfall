# TASKPLAN — The extraction loop

Supersedes the earlier `TASKPLAN-salvage-loop.md` (deleted). Build the phases in
order; each one leaves the game in a playable state.

## Context

The current flow has no decision in it. The goal is the hub — which is also the
deepest and most dangerous point — so *"how far do I push?"* can never be asked.
You always push all the way, because that's where the door is. Nothing tempts you
off the optimal line, nothing escalates, and being caught costs nothing because a
checkpoint hands your position straight back.

**The fix is structural: the prize is at the centre, and the way out is back the
way you came.**

The run becomes:

1. Everyone starts in a **staging room** outside the maze. The extraction pad is
   in that room, in plain sight, *before* anyone leaves — so the return trip is
   taught wordlessly.
2. Doors open. Descend through the three sealed districts. **Salvage** is
   scattered everywhere, worth more the deeper it spawns.
3. The **Vault** at the hub is the prize. Taking it **trips the alarm**: every
   hunter in the maze converges on the carrier, and every player's compass swings
   round to point at them.
4. Carry it out. Back through the same three gates, loaded and hunted.
5. **Vault reaches the extraction pad → the round ends.** Everyone banks whatever
   they were carrying; the winner also banks the vault.
6. Caught at any point → your haul spills where you died, and if you had the
   vault it drops as its own object that **anyone** can pick up.

## Architecture decisions (settled — do not revisit)

- **Free-for-all, and solo is the degenerate case.** One player is simply a race
  with nobody else in it. **Build no team system**: no `Teams` service, no team
  assignment, no second extraction point. Teams are a later layer if the game
  earns one, and building them now would block solo play.
- **Round-based, server-wide.** Staging → run → vault extracted → maze rebuilds →
  staging. The existing `MazeGeneration` rebuild and the server-wide restart in
  `EscapeService` already do half of this.
- **Banked is safe, carried is at risk.** Cash, once banked, can never be lost.
  Haul and your bought loadout are lost on death.
- **Permanent unlocks, per-run rentals.** Cash permanently unlocks *access* to an
  item — buy the laser rifle once and it is on the shelf forever — but you still
  **rent** it into each run, and you still lose it when you die. Progression is
  your options widening, not your raw power climbing. This keeps the FFA gap
  bounded (a fully-unlocked veteran must still fund and risk their kit every
  round, exactly like a newcomer) while keeping the sense of building something.
  It also stops cash going worthless once you own everything.
- **The compass is standard equipment**, not a pickup, and it points at *the next
  thing you need to reach* — see Phase 5.

---

## Out of scope / Do NOT

- **Do NOT** touch maze generation, the sealed districts, gates, the
  `MazeGeneration` rebuild contract, or `GateCenter`. All of it is correct.
- **Do NOT** delete `CheckpointService`. Checkpoints stop being "progress saved"
  and become "where you respawn to attempt a recovery" — the thing at risk moves
  from your *position* to your *cargo*. That is the point, not a regression.
- **Do NOT** add a global run countdown. The alarm after the vault is the only
  timer, and it only starts when a player chooses to start it.
- **Do NOT** add a team system, team colours, or a second extraction point.
- **Do NOT** add permanent stat upgrades to the store (see above).
- **Do NOT** add Studio art. Everything here is code-built. If the user later
  drops models into `ServerStorage.PickupModels`, `PickupsService`'s
  clone-or-fallback path is the pattern to copy.
- **Do NOT** change `HUNTER_COUNT`, `HEALTH_DRAIN`, the duck constants, or the
  gun's client-request/server-authority split.
- **Do NOT** disturb the top-centre HUD stack: timer y=12, health y=70,
  stamina y=94, compass y=116.

---

# PHASE 1 — Salvage and Haul

New `src/features/Salvage/`. Purely additive; the game still plays as it does now.

**Salvage is other runners' lost kit, not generic scrap** — spilled packs, a dead
runner's rig, a cracked-open case. That is the fiction; name and model things
accordingly rather than as ore or crystals. Mechanically it is still scattered
fresh every round and **nothing carries between rounds** (see the round-end wipe
in Step 4.3).

Within a round the fiction is literally true as well: anything a player drops
when they die is findable by everyone else, which is Phase 4.

## Step 1.1 — Constants

**File (new):** `src/features/Salvage/Constants.luau`

```lua
--!strict
return {
	FOLDER = "Salvage",
	DROPS_FOLDER = "Drops",
	FLOAT_Y = 3,
	-- Keyed by MazeNav district (3 = outer .. 1 = inner). Deeper = fewer, richer.
	PER_DISTRICT = {
		[3] = { count = 10, value = 10, color = Color3.fromRGB(150, 160, 170) },
		[2] = { count = 8, value = 30, color = Color3.fromRGB(120, 190, 220) },
		[1] = { count = 6, value = 75, color = Color3.fromRGB(200, 150, 255) },
	},
	-- A perfect sweep is 100+240+450 = 790, but that means visiting all 24 cells
	-- and the round ends when anyone extracts the vault, so nobody finishes one.
	-- 500 beats any realistic sweep while staying under the impossible maximum.
	VAULT_VALUE = 500,
	ALARM_REFRESH = 1.0,
}
```

## Step 1.2 — Scatter and carry

**File (new):** `src/features/Salvage/SalvageService.server.luau`, `Priority = 12`.

`Start()`: wait on `workspace.MazeReady`; create `workspace.Salvage` and
`workspace.Drops`; call `scatter()` once, then bind it to
`GetAttributeChangedSignal("MazeGeneration")`. **Both** — the first generation
fires before any listener can connect (same pattern as Hunter/Checkpoint/Escape/
Pickups).

`scatter()`: clear the folder; snapshot `MazeNav.cellPos` keys excluding band 0
(the hub belongs to the Vault); bucket by
`MazeNav.districtOf(MazeNav.bandOf(key))`; shuffle each bucket with an
**unseeded** `Random.new()` so placement differs every play even on the same maze
seed; take `count` distinct cells per district and build a piece at
`MazeNav.cellPos[key] + Vector3.new(0, FLOAT_Y, 0)`.

Each piece: small `Neon` part, `Anchored`, `CanCollide = false`,
`CanTouch = true`, coloured per district, with a `SalvageValue` attribute. Touch
→ `addHaul(player, value)` → `Destroy()`. Debounce with the same `grabbed` flag
pattern as `PickupsService.attachTouch`.

Expose `SalvageService.addHaul(player, n)` — sets
`player:SetAttribute("Haul", (existing or 0) + n)`. Other features call this.

## Step 1.3 — Haul HUD

**File (new):** `src/features/Salvage/SalvageController.client.luau`

Raw-instance HUD, **bottom-right** (`HAUL 320`), updated on
`GetAttributeChangedSignal("Haul")`, flashing briefly on increase — reuse the
`TweenService` fade from `PickupsController`. Not React, no `.ui.luau`, no story.

**Acceptance:** three lune checks pass. `workspace.Salvage` holds 24 pieces after
a rebuild; touching one raises `Haul` and the HUD updates.

---

# PHASE 2 — Staging room, round lifecycle, and the inverted win condition

The big structural phase. **Phases 2 and 3 renames must not be split** — see the
warning in Step 2.2.

## Step 2.1 — Build the staging room

**File:** `src/features/Maze/MazeService.server.luau`, inside `rebuild`.

The spawn currently lands at a random cell in bands 10–12. Replace that with a
room **outside the perimeter**:

- Pick a random sector of band `BANDS`; take its mid-angle.
- Build a walled box room centred at radius `RADII[13] + 40` on that angle,
  opening inward. Floor at `FLOOR_Y`, walls `WALL_H` tall, one side open toward
  the maze.
- Cut **one opening** in the `Perimeter` wall at that angle, and build a short
  corridor from the room to it. This is effectively a fourth gate — the mouth of
  the maze.
- Reposition the existing `SpawnLocation` inside the room.
- Build the **extraction pad** inside the room: a lit `Neon` pad named
  `ExtractPad`, in a new `workspace.Staging` folder (its own folder, **not**
  under `workspace.Maze`, which gets `ClearAllChildren`'d).
- Rebuild `workspace.Staging` on every `rebuild` alongside `Gates`.

**Account for:**
- `SPAWN_MIN_BAND` and the old random-band spawn logic are now dead — remove
  them. Every run is a full descent from outside, which is more consistent.
- The perimeter opening must be carved *after* the perimeter wall is built, or it
  will be walled over.
- The room must not overlap the maze: `RADII[13]` is 534, so radius 574 for the
  room centre with a room half-depth under 30 studs is clear.

## Step 2.2 — The hub part becomes the Vault

Same file (~line 399). The hub currently builds a part named `ExitGate`, which is
the win trigger. Rename it to **`Vault`** and keep it in `workspace.Maze`. Give
it a container-ish look (colour change + `Highlight` is enough — this is
greybox). It has no behaviour yet; Phase 3 gives it one.

> **WARNING:** `EscapeService.bindToMaze` currently does
> `mazeFolder:WaitForChild("ExitGate")` and wires the win to its `Touched`. If you
> rename the part without doing Step 2.3 in the same pass, `bindToMaze` will yield
> forever and the round will never be able to end. Do both together.

## Step 2.3 — Round lifecycle and extraction

**File:** `src/features/Maze/EscapeService.server.luau`

Replace the per-player escape with a **server-wide round state machine**. Add a
`workspace.RoundState` string attribute: `"Staging"` | `"Active"`.

- **Staging:** players are in the room. Run a countdown (`ROUND_COUNTDOWN = 15`),
  broadcast via a new `RoundState` packet so the client can show it. The corridor
  is blocked by a `Door` part (`CanCollide = true`).
- **Active:** door goes `CanCollide = false`; timers start; the run is live.
- Remove the `ExitGate` lookup and `gateConnection` from `bindToMaze` entirely.
  Keep the zone-rebuild half — it still must re-run on `MazeGeneration`.
- Extraction is now `ExtractPad.Touched`, and it only ends the round for the
  player **carrying the vault** (`player:GetAttribute("HasVault")`). Everyone else
  touching it does nothing.

On vault extraction:
1. Set `RoundState = "Staging"`.
2. **Bank every player's haul** (Phase 6 converts this to cash; until then just
   report it), then clear `Haul` on all players.
3. Send a round-end packet with the winner and a per-player haul list.
4. `MazeService.rebuild(<fresh seed>)`, teleport everyone back into the room,
   reset per-run attributes, restart the countdown.

Keep the existing per-run attribute clears and **add `Haul`, `HasVault`**.

**Account for:**
- The old `Restart` packet and its escaped-only guard are replaced by this
  automatic loop. Keep the packet if a manual "skip to next round" is useful, but
  the round no longer waits on a button.
- The old `RunStarted`-on-leaving-the-zone timer can stay as a stat; it is no
  longer the score.
- Late joiners spawn into the room; if `RoundState == "Active"` they wait for the
  next round rather than dropping into a live maze.

**Acceptance:** a round begins with a countdown in the room, the door opens, and
touching the extract pad *without* the vault does nothing.

---

# PHASE 3 — The Vault and the alarm

**File:** `src/features/Salvage/SalvageService.server.luau`

Bind `Vault.Touched` in `Start()` **and** re-bind on `MazeGeneration` (it lives in
`workspace.Maze`, so `ClearAllChildren` destroys it every rebuild).

On touch, if `workspace:GetAttribute("VaultTaken")` is not already true:
1. `workspace:SetAttribute("VaultTaken", true)`.
2. `player:SetAttribute("HasVault", true)`.
3. Make the Vault part inert/dark so it reads as emptied.
4. Start the alarm.

**The alarm reuses the existing gunshot summon — write no new hunter logic.**
`HunterService` already beelines hunters to `workspace.HunterAlertPos` while
`workspace.HunterAlert` is recent. Every `ALARM_REFRESH` seconds while a carrier
exists, set both to the carrier's live position.

**File:** `src/features/Hunter/HunterService.server.luau` — the summon branch is
gated on `SUMMON_RADIUS` (200), correct for a gunshot but wrong for a maze-wide
alarm. Add a `workspace.AlarmActive` boolean (set by SalvageService) and **skip
the radius check when it is true**. Leave `SUMMON_RADIUS` itself alone.

Clear `VaultTaken`, `AlarmActive`, `HunterAlert` and `HunterAlertPos` in
`MazeService.rebuild` so a new round re-arms cleanly.

**Acceptance:** touching the Vault sets `HasVault`, and every hunter in the maze
changes course toward the carrier within ~1s regardless of distance.

---

# PHASE 4 — Drop, steal, and recover

**File:** `src/features/Hunter/HunterService.server.luau`, inside `catchPlayer`.

In the `task.delay(1.4, ...)` block, **before** the checkpoint teleport:

1. If `Haul > 0`, spill it as a recoverable pile at the death position, then zero
   `Haul`.
2. If `HasVault`, drop the **vault as its own separate object** at the death
   position and clear `HasVault`. Two distinct things can drop in the same spot —
   they mean different things.

Both constructions live in `SalvageService` (`dropHaul` / `dropVault`);
`HunterService` requires it from
`ServerScriptService.Features.Salvage.SalvageService`, the same cross-feature
server require `EscapeService` already does for `MazeService`.

- A **haul pile**: touch → `addHaul` → destroy. Does **not** decay; the pressure
  comes from the maze being hot, not a timer.
- A **dropped vault**: touch → the toucher becomes the carrier (`HasVault = true`)
  and the alarm re-points at them. **Anyone** can take it, including the player
  who lost it.

**Also:** the hunter that catches a player currently warps to
`farSpawn(spawnLocation.Position)`. **Remove that warp** so it lingers guarding
the kill. Safe, because the player respawns at the last *gate* with `SafeUntil`
grace, not at the death site.

**Acceptance:** die carrying 200 and the vault → a 200 pile *and* a vault object
appear at the death spot, `Haul` = 0, `HasVault` = false, and the hunter is still
nearby. Another player touching the vault becomes the carrier and every compass
swings to them.

## Step 4.3 — Everything in the maze dies with the round

**Nothing carries between rounds.** Drops are a *within-round* mechanic only: if
nobody recovers a pile before the round ends, it is simply gone.

At round end (Phase 2's banking step, before `MazeService.rebuild`):

- `workspace.Drops:ClearAllChildren()` — unrecovered spills are destroyed, not
  banked, not carried forward.
- `workspace.Salvage` is cleared and re-scattered by the existing
  `MazeGeneration` hook, so uncollected salvage vanishes with the old maze.

**Account for:**
- Do **not** add any cross-round store of unclaimed value. A fresh round is a
  fresh maze with a freshly scattered baseline, every time.
- This is what keeps a loss a real loss. If value leaked forward, dying would
  cost you a detour rather than the haul.
- `workspace.Drops` must be recreated (or cleared, not destroyed) on rebuild —
  it is the feature's own folder and other code holds no reference to it, but
  the drop path must not fail on a missing parent.

**Acceptance:** die deep with 200 and let the round end without recovering it —
the next round contains no trace of it, and your cash is unchanged.

---

# PHASE 5 — The compass becomes standard equipment

**File:** `src/features/Pickups/CompassController.client.luau` — move it to
`src/features/Salvage/` or leave it in place, but change two things:

1. **Always visible.** Remove the `HasCompass` gate.
2. **Retarget by rule — "point at the next thing you need to reach":**
   - `VaultTaken == false` → the vault is at the centre and everyone knows where
     the centre is, so that is useless information. Point at the **next gate
     inward**, exactly as it does today.
   - `VaultTaken == true` → point at the **vault's current position**: the
     carrier's character if someone holds it, otherwise the dropped vault object.

Publish the vault's live position as `workspace.VaultPos` (a Vector3 attribute,
refreshed by `SalvageService` alongside the alarm) so the client needs no
character lookups or ownership logic.

**File:** `src/features/Pickups/Constants.luau` — remove the `Compass` entry from
`SPAWNS` (with its `minBand`/`maxBand`/`minSpawnDist`). Leave the constraint
machinery itself; it is general and other kinds may want it.

**Account for:** `HasCompass` is now unused — remove it from the `EscapeService`
clear loop and from `docs/game/Pickups.md`. The `Compass` model in
`ServerStorage.PickupModels` becomes unused; leave it there, it is the user's.

**Acceptance:** every player has a working arrow from spawn. Before the vault is
taken it points at the next gate; the instant anyone takes it, **every** player's
arrow swings to the carrier.

---

# PHASE 6 — Cash, the store, and loadouts

Only start this once Phases 1–5 are playable — the prices are unguessable until
you know what a typical run pays.

## Step 6.1 — Cash

**File:** `src/features/Maze/PlayerData.luau`

```lua
PlayerData.registerTemplate("Ringfall", {
	BestTimeSeconds = 0,
	BestHaul = 0,
	Cash = 0,
	Unlocked = {}, -- item id -> true; permanent, survives everything
})
```

On round end (Phase 2's banking step), for each player:
`PlayerDataService.SetValue(plr, { "Ringfall", "Cash" }, cash + haul)` and update
`BestHaul` if beaten. **Cash and unlocks are never lost** — not on death, not on
a lost round.

## Step 6.2 — Two-price store

New `src/features/Store/`. A terminal part in the staging room
(`workspace.Staging`), opened by proximity or a key. **This is the one UI in this
plan that should be React**, since it is a real screen rather than a HUD readout:
a `.ui.luau` view plus a `.story.luau`, per the repo's UI conventions. The view
must be **dumb** — props in, intents out; `tools/check-views` enforces it.

Every item has **two prices**:

- **Unlock** — paid once, permanent, stored in `Ringfall.Unlocked`. Widens what
  the shelf offers you forever.
- **Rent** — paid every round you take it in. The item is applied as a per-run
  attribute and is **lost on death** like everything else carried.

| Item | Unlock | Rent | Effect |
| ---- | ------ | ---- | ------ |
| Sidearm | 0 (starts unlocked) | 60 | `HasGun = true`, `Ammo = 12` |
| Ammo box | 0 | 30 | `Ammo += 12` |
| Floodlight | 250 | 40 | boosts the flashlight for the run (`HasFlashlight`) |
| Medkit | 300 | 80 | one stored charge |
| **Map** | 900 | 150 | reveals the maze layout for the run |

Tune freely — the shape matters more than the numbers, and the numbers are
unguessable until you know what a run pays. The intent: cheap things unlock
immediately and rent for pennies; the good stuff is a real investment to unlock
and still stings to take in.

The **Map** is the item worth building carefully: it directly attacks the
"searching is boring" problem, but as a *purchase*, so it is a choice the player
makes rather than a difficulty removed for everyone. Simplest version: a HUD
minimap drawn from `MazeNav.cellPos` + `adj`, showing carved passages and gate
positions for the current maze.

**Account for:**
- Renting an item you have not unlocked must be **rejected server-side**.
- Purchases (both kinds) only while `RoundState == "Staging"`, validated
  server-side. Never trust a client-sent buy — same discipline as `GunService`
  validating shots.
- A player who cannot afford a rent simply goes in without it. Never block a
  player from starting a round.

**Acceptance:** extract with 300 → cash rises by 300 and survives a rejoin.
Unlock the Floodlight → it stays unlocked after a rejoin. Rent a sidearm in
staging → spawn with `HasGun`; die with it → lose the gun, keep the cash balance
and the unlock.

---

# PHASE 7 — Docs

- **`docs/game/Salvage.md`** (new): the loop, depth-scaled scatter, the vault, the
  alarm, drop/steal/recover, the `Haul` / `HasVault` / `VaultPos` contracts.
- **`docs/game/Store.md`** (new): cash, per-run loadouts and *why* they are not
  permanent, server-side purchase validation.
- **`docs/game/Escape.md`**: rewrite for the round lifecycle, `RoundState`, the
  staging room, and extraction-by-vault-carrier.
- **`docs/game/Maze.md`**: the staging room and perimeter opening; `ExitGate` is
  now `Vault`; the dead `SPAWN_MIN_BAND` removal.
- **`docs/game/Hunter.md`**: hunters no longer warp away after a catch; the alarm
  ignores `SUMMON_RADIUS`.
- **`docs/game/Checkpoint.md`**: checkpoints are respawn points for recovery runs,
  not progress saves — say why explicitly.
- **`docs/game/Pickups.md`**: the Compass entry is gone; it is standard kit now.
- Index everything new in `docs/game/index.md`.

---

## Definition of Done

1. `lune run tools/split`, `check-views`, `check-framework-boundary` all pass.
2. A round runs: staging countdown → doors open → descend → vault → extract →
   rebuild → staging, with no manual button press.
3. Salvage scatters per district with depth-scaled value, at different cells every
   play, re-scattering on every `MazeGeneration`.
4. Taking the vault pulls **every** hunter toward the carrier regardless of
   distance, and swings **every** player's compass to them.
5. Only the vault carrier can end the round at the extract pad.
6. Being caught spills the haul *and* drops the vault as a separate object anyone
   can claim; the hunter that caught you stays near the drop.
7. Everyone banks their haul at round end, not just the winner.
8. **Nothing carries between rounds.** Unrecovered drops and uncollected salvage
   are destroyed at round end; the next round scatters a fresh baseline with no
   trace of the last one.
9. Cash and unlocks persist across a rejoin; rented kit does not survive death.
10. Renting an unowned item, or buying outside `RoundState == "Staging"`, is
    rejected server-side.
11. No team system, no permanent *stat/power* upgrades (unlocks widen options
    only), no global run countdown, and the top-centre HUD stack is untouched.
12. No debug `print`s remain.
