# Salvage

Other runners' lost kit — spilled packs, a dead runner's rig, a cracked-open
case — scattered fresh every round, worth more the deeper it spawns. This is
the feature that turns "reach the centre" into a real risk/reward decision:
the **Vault** at the hub is the prize, taking it **trips the alarm** (every
hunter converges on the carrier), and the whole loop resets every round —
nothing here carries forward. See [Escape.md](Escape.md) for the round
lifecycle this plugs into and [Hunter.md](Hunter.md) for the alarm's
consumer side.

Files:

- `src/features/Salvage/Constants.luau` — folder names, float height,
  `PER_DISTRICT` scatter table, `VAULT_VALUE`, `ALARM_REFRESH`.
- `src/features/Salvage/SalvageService.server.luau` — scatters salvage,
  binds the Vault's `Touched`, runs the alarm-refresh loop, and exposes
  `addHaul` / `dropHaul` / `dropVault` for other features.
- `src/features/Salvage/SalvageController.client.luau` — the bottom-right
  Haul HUD. Raw instances, no React (see CLAUDE.md: gameplay HUDs are raw
  instances).
- `src/features/Salvage/CompassController.client.luau` — the compass arrow
  HUD, moved here from Pickups now that it's standard equipment rather than
  a pickup (see "The compass" below).

## Depth-scaled scatter

`PER_DISTRICT` (keyed by `MazeNav` district — `3` = outer .. `1` = inner)
gives each district a `count`, a `value`, and a `color`:

| District | Count | Value each | Total |
| -------- | ----- | ---------- | ----- |
| OUTER (3) | 10 | 10 | 100 |
| MIDDLE (2) | 8 | 30 | 240 |
| INNER (1) | 6 | 75 | 450 |
| **Vault** | 1 | 500 | one touch, at the hub |

Deeper districts scatter **fewer, richer** pieces — fewer things to grab, but
each one is worth more, so pushing inward is a real value trade, not a free
upgrade.

**On the Vault being 500 against a 790 theoretical maximum.** A perfect sweep of
all 24 pieces is worth 790, so the Vault is deliberately *not* the largest number
on the board. But a perfect sweep means visiting every cell of all three
districts, and **the round ends the moment anyone extracts the Vault** — so
nobody ever finishes one. 500 in a single touch beats any *realistic* sweep while
staying under the impossible maximum, which is what keeps committing to the
centre tempting rather than automatic. If you retune `PER_DISTRICT`, re-check
this relationship: the Vault should stay comfortably above what a good player
actually collects in a round, and comfortably below the theoretical total.

`SalvageService.scatter()`, run once at `Start()` and again on every
`workspace.GetAttributeChangedSignal("MazeGeneration")` (the first generation
fires before any listener can connect — same pattern as
Hunter/Checkpoint/Escape/Pickups):

1. Snapshot `MazeNav.cellPos` keys, **excluding band 0** — the hub belongs to
   the Vault, not to scattered salvage.
2. Bucket every remaining key by `MazeNav.districtOf(MazeNav.bandOf(key))`.
3. Shuffle each bucket independently with an **unseeded** `Random.new()`, so
   placement differs every play even on the same maze seed.
4. Take `count` distinct cells per district and build a small Neon block
   (`SalvageValue` attribute, `PER_DISTRICT[district].color`) floated
   `FLOAT_Y` studs above each cell centre.

Touch → `SalvageService.addHaul(player, value)` → `Destroy()`. Debounced with
the same `grabbed`-flag-checked-before-any-yield pattern
`PickupsService.attachTouch` uses.

## `Haul`

A per-run player attribute, exposed through one function so nothing else has
to poke it directly:

```lua
function SalvageService.addHaul(player: Player, amount: number)
	player:SetAttribute("Haul", (player:GetAttribute("Haul") or 0) + amount)
end
```

Written by: touching a salvage piece, touching a `HaulDrop` (below).
Read by: `SalvageController` (the HUD), `EscapeService` (banks it at round
end), `HunterService` (spills it on a catch). Cleared to `nil` by
`EscapeService` at round end and — because nothing carries between rounds —
never persisted anywhere. Phase 6 (not built yet) is what will convert a
round's Haul into permanent cash.

## The Vault and the alarm

`MazeService.rebuild` builds the Vault (see [Maze.md](Maze.md)) with no
behaviour of its own — `SalvageService.bindVault()` gives it one, called once
at `Start()` and again on every `MazeGeneration` (the Vault lives inside
`workspace.Maze`, so `ClearAllChildren()` destroys it every rebuild, same
footgun as the old `ExitGate`).

On `Vault.Touched`, guarded by `workspace.VaultTaken` (checked and set
synchronously before any yield, so a multi-part touch can't double-grant):

1. `workspace:SetAttribute("VaultTaken", true)`.
2. `player:SetAttribute("HasVault", true)`.
3. `workspace:SetAttribute("AlarmActive", true)`.
4. The Vault part goes dark and inert (`Slate` material, near-black) so it
   reads as emptied. No further `Touched` behaviour on that instance — the
   next rebuild rebinds a fresh one.

**The alarm reuses the existing gunshot summon — no new hunter pathing.**
`HunterService` already beelines every hunter within `SUMMON_RADIUS` to
`workspace.HunterAlertPos` while `workspace.HunterAlert` is recent (see
[Hunter.md](Hunter.md#summon--retaliation-has-a-cost)). `SalvageService.startAlarmLoop()` is a single
background loop, started once at `Start()`, that — every `ALARM_REFRESH`
(1s) while `VaultTaken` is true — refreshes `HunterAlert` / `HunterAlertPos`
to wherever the vault *currently* is, and also publishes `workspace.VaultPos`
(the same position) for the compass:

```lua
local function currentVaultPosition(): Vector3?
	local carrier = findCarrier() -- scans Players for HasVault == true
	local hrp = carrier and carrier.Character and carrier.Character:FindFirstChild("HumanoidRootPart")
	if hrp then
		return hrp.Position
	end
	local dropped = workspace.Drops:FindFirstChild("DroppedVault")
	return dropped and dropped.Position
end
```

Refreshing continuously (not just once, on pickup) is what keeps the alarm
from going stale: `HunterService`'s summon branch only honours `HunterAlert`
within `SUMMON_WINDOW` (5s) of the timestamp, and a dropped-but-unclaimed
vault (see below) would otherwise stop refreshing the moment nobody holds
it, letting hunters fall out of the alarm and back to normal
chase/search/wander after 5 seconds even though the vault is still very much
"out." Falling back to the `DroppedVault` object's own position closes that
gap.

**`HunterService`'s one change**: the summon branch is gated on
`SUMMON_RADIUS` (200 studs), correct for a local gunshot but wrong for a
maze-wide alarm. A `workspace.AlarmActive` boolean (set above) skips the
radius check entirely when true — `SUMMON_RADIUS` itself is untouched, and
still applies to the ordinary gunshot summon.

`VaultTaken`, `AlarmActive`, `HunterAlert`, and `HunterAlertPos` are all
cleared by `MazeService.rebuild` (see [Maze.md](Maze.md)) so a new round
re-arms cleanly, even though they're conceptually owned by Salvage/Hunter —
`rebuild` is the one place every round always passes through, same
reasoning as every other per-run attribute clear.

## Drop, steal, recover

`HunterService.catchPlayer` (see [Hunter.md](Hunter.md)), just before the
checkpoint teleport, at the death position:

- If `Haul > 0`: `SalvageService.dropHaul(deathPos, haul)`, then `Haul = 0`.
- If `HasVault`: `SalvageService.dropVault(deathPos)`, then `HasVault = false`.

Both can fire on the same death, landing in the same spot — they're two
distinct objects that mean different things:

| Object | Touch behaviour | Decays? |
| ------ | ---------------- | ------- |
| `HaulDrop` (in `workspace.Drops`) | `addHaul` the toucher, then destroy | No — the pressure is the maze being hot, not a timer |
| `DroppedVault` (in `workspace.Drops`) | Sets `HasVault = true` on the toucher, destroy | No — anyone can claim it, including the player who lost it |

The moment a `DroppedVault` is claimed, the alarm loop's next tick
(`findCarrier`) picks up the new carrier automatically — no extra wiring
needed to "re-point the alarm."

**The hunter that catches you no longer warps away** (see
[Hunter.md](Hunter.md#combat)) — it lingers guarding the kill (and the drops
it just made). This is safe because the caught player respawns at their last
*gate* checkpoint with `SafeUntil` grace, not at the death site itself — see
[Checkpoint.md](Checkpoint.md).

## Nothing carries between rounds

At round end (`EscapeService`, see [Escape.md](Escape.md)), **before**
`MazeService.rebuild`:

```lua
local drops = workspace:FindFirstChild("Drops")
if drops then
	drops:ClearAllChildren()
end
```

Unrecovered `HaulDrop` / `DroppedVault` objects are destroyed, not banked,
not carried forward. `workspace.Salvage` is cleared and re-scattered by the
existing `MazeGeneration` hook, so uncollected salvage vanishes with the old
maze too. **Do not add any cross-round store of unclaimed value** — a fresh
round is a fresh maze with a freshly scattered baseline, every time. This is
what keeps a loss a real loss: if value leaked forward, dying would cost you
a detour rather than the haul.

`workspace.Drops` itself is created once at `Start()` and never destroyed —
only cleared, by `EscapeService`, at round end. It is **not** re-created on
`MazeGeneration` the way `workspace.Salvage` is, since it's a within-round
mechanic, not a per-generation one; `dropHaul`/`dropVault` both no-op safely
if the folder is somehow missing rather than erroring.

## The compass is standard equipment

`CompassController` (moved here from `Pickups/`) has no `HasCompass` gate
anymore — every player has a working arrow from spawn. It retargets by one
rule, **"point at the next thing you need to reach"**:

- `workspace.VaultTaken == false` → the vault is at the centre and everyone
  already knows where the centre is, so that's useless information. Point at
  the **next gate inward**, exactly as before (largest-radius gate still
  smaller than the player's own radius, falling back to world-centre once
  past the innermost gate).
- `workspace.VaultTaken == true` → point at **`workspace.VaultPos`** — the
  carrier's character if someone holds it, otherwise the dropped vault
  object. The client does zero character lookups or ownership logic; it just
  reads the attribute `SalvageService`'s alarm loop already publishes.

`Pickups/Constants.luau` no longer lists a `Compass` entry in `SPAWNS` (the
placement-constraint machinery itself — `minBand`/`maxBand`/`minSpawnDist` —
stays, since other kinds may still want it). `HasCompass` is gone from
`EscapeService`'s per-run attribute clear. The `Compass` model under
`ServerStorage.PickupModels` is now unused but left in place — it's the
user's.

## Dependencies

Reads `ReplicatedStorage.Features.Maze.MazeNav` for cell placement and
districts, and `workspace.MazeReady` / `workspace.MazeGeneration` /
`workspace.VaultTaken`. Writes `workspace.HunterAlert` / `HunterAlertPos` /
`AlarmActive` / `VaultPos` (consumed by `HunterService`, see
[Hunter.md](Hunter.md), and `CompassController`). `HunterService` requires
`SalvageService` directly (`ServerScriptService.Features.Salvage.SalvageService`)
for the drop-on-catch path — the same cross-feature server require
`EscapeService` already uses for `MazeService`. `Priority = 12`, matching
`PickupsService` (no ordering dependency between them).

## Studio assets

**None.** Everything here is code-built, per the plan's "no Studio art" rule
for this pass. If the user later drops models into
`ServerStorage.PickupModels`, `PickupsService`'s clone-or-fallback path is
the pattern to copy for salvage pieces too.
