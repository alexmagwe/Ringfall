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
4. Take `count` distinct cells per district and build one object
   (`SalvageValue` attribute) floated `FLOAT_Y` studs above each cell centre —
   the user's model if they placed one, else a coloured Neon block. See
   *Art* below.

Touch → `SalvageService.addHaul(player, value)` → `Destroy()`. Debounced by
`attachGrab`, which binds `Touched` on **every** `BasePart` of the object behind
one shared `grabbed` flag: a multi-part model would otherwise pay out once per
limb that brushed it in the same frame.

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

The Vault is a `Model` (a core-and-cage artifact, or the user's art from
`ServerStorage.MazeModels.Vault`), so the touch goes through the same
`attachGrab` the salvage pieces use: `Touched` on **every** `BasePart` inside it
behind one shared flag. Binding the container alone would never fire, and binding
each part independently would let a player brushing two fins in the same frame
trip it twice.

On a grab, guarded by `workspace.VaultTaken` (checked and set synchronously
before any yield):

1. `workspace:SetAttribute("VaultTaken", true)`.
2. `player:SetAttribute("HasVault", true)`.
3. `workspace:SetAttribute("AlarmActive", true)`.
4. `collapseVault` takes it off the dais. Every part goes `Slate` and near-black
   with `CanTouch = false`, its lights and its `AlwaysOnTop` outline are
   destroyed, and then it **shrinks into the pedestal** over `VAULT_SINK_TIME`
   (0.5s, eased out so most of the drop lands early) before being destroyed.

   It used to stay put as a dimmed husk. That read as loot worth grabbing —
   especially with real art, since a dark bag on a pedestal looks like a dark bag
   on a pedestal — and the only feedback that it was spent was walking into it
   and having nothing happen. The alarm and every compass swinging already carry
   the "someone got here first" signal the husk was there to send.

   Two things the collapse has to get right:
   - **Scale is relative to the model's current scale, not 1.** `buildVault` fits
     user art to `VAULT_TARGET_SIZE`, so a bare `ScaleTo(VAULT_SINK_SCALE)` would
     snap the model back to its authored size before shrinking it.
   - **`VaultController` stops driving it** once `VaultTaken` is set. It
     re-pivots every Heartbeat from a rest pose captured at bind, so it would
     snap the model back out of the dais each frame and the collapse would never
     visibly happen.

   The next rebuild rebinds a fresh Vault.

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

## Art

Every salvage object goes through `buildObject`, a clone-or-fallback path
modelled on `PickupsService.buildPickup`. It looks for a template under
**`ServerStorage.SalvageModels`** and falls back to the coloured block the
feature shipped with when one is missing — so the game works with zero art, and
each kind upgrades independently the moment its model appears.

| Child of `SalvageModels` | Used for | Fallback |
| ------------------------ | -------- | -------- |
| `Backpack` | District 3 salvage (outer, value 10) | green neon block |
| `Backpack` | District 2 salvage (mid, value 30) | cyan neon block |
| `Briefcase` | District 1 salvage (inner, value 75) | violet neon block |

The `DuffelBag` moved to the hub as the Vault
(`ServerStorage.MazeModels.Vault` — see [Maze.md](Maze.md)), leaving two
silhouettes for three tiers. The repeat sits on the two **cheap** tiers
deliberately: colour is the primary tier signal, and the find worth crossing a
district for is the one that most needs to be unmistakable, so the inner tier
keeps the sealed case to itself while outer and mid share the pack and differ
only by glow. Add a fourth model and give district 2 its own `model` name to
split them properly.

**Three models, and only three.** Death spills (`dropHaul`) and the dropped
vault (`dropVault`) deliberately stay code-built blocks — a spill must not share
a silhouette with scattered salvage ("someone died here" ≠ "nobody has been down
here yet"), and the vault must never be mistaken for loot at all. Neither has a
`model` field to set.

Names come from `Constants.PER_DISTRICT[n].model`, decoupled from the mechanic
so the art can be renamed without touching code. Anything that **is or contains
a `BasePart`** works — `Model`, `MeshPart`, `Tool`, `Accessory`, whatever the
Toolbox hands you — and the builder normalises it into a `Model` container. The
check is deliberately not a class whitelist: an earlier `Model`/`Tool`/`BasePart`
whitelist silently rejected an `Accessory` and fell back to a white block with no
warning, which is indistinguishable from art that simply wasn't placed.
`salvageTemplate` now warns on a configured-but-unusable name.

What `buildObject` does to a cloned template, and **why each step matters**:

- **Strips every `LuaSourceContainer`.** A free-model `Tool` can ship its own
  server `Script`s that run the instant it enters the world. Salvage is pure
  decoration.
- **Anchors every `BasePart`,** so the object hangs where it's placed regardless
  of the art's own welds or unanchored children.
- **`CanCollide = false`, `Massless = true`,** so a piece never blocks a
  corridor.
- **Unwraps a `Tool` template into a plain Model.** `Tool` inherits from `Model`
  in Roblox, so a Tool used as art stayed a Tool in the world — and Roblox
  auto-equips one the moment a character touches its `Handle`, welding the player
  to a part this code has just *anchored*. Nesting does not prevent it; only
  having no Tool does. See
  [Pickups.md](Pickups.md#studio-assets), where it was caught.
- **Re-applies the tier glow.** This is the one that bites: a realistic dark
  prop in an unlit maze is invisible, and the district colour *is* the value
  tier — it's how a player decides from down a corridor whether a piece is worth
  the detour. Pieces and spills get a `PointLight` in their tier colour; the
  dropped vault gets an occluded `Highlight` instead, so it's findable through
  the fog without lighting up the corridor and giving its position to everyone
  at once.

Highlights are used sparingly on purpose — Roblox degrades past roughly 31 on
screen, and a round can have 24 salvage pieces out at once.

**Keep the tier colours saturated.** `Neon` renders the raw `Color3` at full
brightness, so anything pale washes out to white. The first palette here was
grey / pale blue / lilac and every tier read as an identical white cube in game
— destroying the one signal the colour exists to carry. Green → cyan → violet
all survive Neon, and none of them collide with the amber of a death spill.

Keep models around **2–3 studs**; pieces float at `FLOAT_Y = 3`.

## Studio assets

**Optional.** Create a `Folder` named `SalvageModels` under `ServerStorage` and
put `Backpack`, `DuffelBag` and `Briefcase` inside it. Anything absent falls
back to its block (with a warning) — there is no required asset, and no code
change per model.

`ServerStorage.PickupModels` is a separate folder for the Pickups feature, so
salvage art and pickup art can be swapped without disturbing each other.
