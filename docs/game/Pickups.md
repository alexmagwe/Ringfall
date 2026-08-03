# Pickups

Scavenged items scattered around the maze each round: **ammo**, a
**stamina upgrade**, and **MedKits**. Grabbing one is a
one-touch grant of a **per-run player attribute** — nothing here ever reaches
PlayerData. A fresh round wipes all of it and re-scatters to new cells.

**Two things that used to live here don't anymore.**

- **The compass** is standard equipment, not something you have to find; see
  [Salvage.md](Salvage.md#the-compass-is-standard-equipment).
- **The gun** is rented from the staging shelf (see [Store.md](Store.md)).
  Scattering one made the Sidearm a convenience rather than a decision — why
  pay 60 when the maze hands you the same attribute for free? Being armed is now
  something you commit to before the round starts, which is what the whole
  rent-and-lose-it economy is built on.

  **Ammo still scatters, and that is the point.** A magazine you didn't pay for
  extends a weapon you did. `PickupsService.grant` still handles
  `kind = "Gun"` and `GUN_START_AMMO` still exists: that is the mechanism, not
  the content. Re-scattering guns is one line back in `SPAWNS`, and gutting the
  grant would turn that line into a silent no-op instead.

Files:

- `src/features/Pickups/Constants.luau` — the folder name, float height, spin
  speed, and the `SPAWNS` table (kind/count/color/amount per pickup type).
- `src/features/Pickups/PickupsService.server.luau` — scatters pickups at
  random maze cells and grants attributes on touch. Server-authoritative.
- `src/features/Pickups/PickupsController.client.luau` — spins the pickups
  and flashes a "PICKED UP: X" toast. Purely cosmetic; raw HUD (no React).

## Studio assets

**Optional models.** Place a `Folder` named `PickupModels` under **ServerStorage**
with the art for each kind inside. The art's instance name is **not** matched to
the kind — instead each `SPAWNS` entry in `Constants.luau` carries a `model`
field naming the child to clone, so art can be named anything (current mapping:
Ammo→`Battery`, Stamina→`StaminaBoost`). Two models in
`ServerStorage.PickupModels` are unused now — `Compass` and `GatlingLaser` —
since neither is scattered any more. Left in place; they're the user's.

The art can be a **Model, a Tool, or a single BasePart** (Union / MeshPart /
Part). `buildPickup` normalizes all three into a Model container, then:

- **strips every `LuaSourceContainer`** from the clone — a free-model Tool ships
  with its own scripts that would otherwise run the instant it enters the world
  (the spider-`Animate` hazard); a pickup is pure decoration and needs none.
- anchors + de-collides + `Massless`es every part, so it stays rigid regardless
  of the art's welds, never blocks a player, and — nested in the container, not a
  direct child of `workspace`.

**A `Tool` template is unwrapped into a plain Model, and that is load-bearing.**
`Tool` inherits from `Model` in Roblox, so `clone:IsA("Model")` is true for one:
the nesting branch never ran, and the pickup went into the world *still a Tool*.
Roblox auto-equips a Tool the moment a character touches its `Handle` — a Handle
this code has just **anchored** — so the player was welded to an immovable part,
then dropped when the touch handler destroyed it a beat later. It was reported
twice as "I picked it up and fell", once fatally.

Nesting a Tool inside a Model does **not** fix it: the auto-equip fires for any
`Workspace` descendant, not only a direct child. The only reliable fix is for no
Tool to exist, so its children are moved into a Model and the Tool is discarded.
`ServerStorage.PickupModels` currently holds three Tools, so this is the normal
case rather than an edge one.
- floats it at the cell centre, spins it (`Model:PivotTo`, no `PrimaryPart`
  needed), and wraps it in an occluded `Highlight` (kind-colored outline) so it's
  findable in the fog without recoloring the mesh or glowing through walls.

Any kind whose `model` is missing from the folder falls back to a code-built Neon
ball, so the feature works before any art exists and you can add pieces one at a
time. `MODELS_FOLDER` in `Constants.luau` names the folder.

The grab hitbox is every `BasePart` in the container; a `grabbed` flag debounces
so a multi-part model can't double-grant.

## The per-run attributes

Set by `PickupsService` on pickup, read wherever they're consumed, and cleared
in **two** places:

- **On catch** — `PickupsService` watches the `Caught` attribute and strips
  `HasGun` / `Ammo` / `StaminaBonus`. Everything you were
  carrying dies with you.
- **At round end** — `EscapeService.resetRunAttributes`, which clears the same
  set plus everything else per-run.

Catch used to spare them, on the reasoning that a caught player keeps their loot
within the same run. That broke once the Store shipped, because rented kit
writes the *same attributes*: what you lost then depended on where it came from
— the same gun kept if found, stripped if rented — and a rented item's `clear()`
took found kit with it, so renting one 30-cash ammo box meant a catch wiped your
whole stock while a player who rented nothing kept all of theirs. Spending cash
made your losses bigger. One rule for everything removes that, and it gives a
catch a cost inside the run instead of only at round end.

The feature that grants an attribute is the feature that clears it, so
`StoreService` does the same for rented items off the same signal. Both nil-ing
the same attribute is harmless.

| Attribute | Type | Meaning | Consumed by |
| --------- | ---- | ------- | ----------- |
| `HasGun` | bool | player owns the gun this run | `GunController` (HUD gate), `GunService` (fire gate) |
| `Ammo` | number | rounds remaining, authoritative | `GunController` (HUD), `GunService` (fire gate + decrement) |
| `Health` / `MaxHealth` | number | player HP (see Health.md) | `HealthController` (bar), `HunterService` (drain) |
| `StaminaBonus` | number | added to max stamina (studs of bar), 0 default | `SprintController` |

## Scatter

`PickupsService.Priority = 12` (after `MazeService` = 5, so `MazeNav.cellPos`
is populated). On `Start()`, after the `MazeReady` wait:

1. Creates `workspace.Pickups` — a folder the feature owns. **Never** parented
   under `workspace.Maze`, since `MazeService.rebuild` calls `ClearAllChildren()`
   on that folder at an uncontrolled time.
2. Scatters once immediately, then again on every
   `workspace:GetAttributeChangedSignal("MazeGeneration")` — the same
   initial-placement-then-listen pattern Hunter/Checkpoint/Escape use, because
   the first `MazeGeneration` bump happens before any listener can connect.

Each scatter: snapshots `MazeNav.cellPos` keys, excludes band 0 (`MazeNav.bandOf(key) > 0`
— the centre hub/exit stays clear), Fisher-Yates shuffles them with an unseeded
`Random.new()` (so placement differs every play, even on the same maze seed),
then walks `Constants.SPAWNS` popping distinct cells per kind so no two
pickups share a cell.

### Placement constraints

A `SPAWNS` entry can optionally carry `minBand`/`maxBand` (inclusive band
range) and/or `minSpawnDist` (studs from `SpawnLocation`). `scatter()` filters
the shuffled cell pool down to cells matching all constraints present on that
entry before popping `count` cells from it; if the filter leaves no candidate
cells, it falls back to the unconstrained pool — a constrained kind can never
fail to place. Claimed cells (whether from the filtered or unconstrained pool)
are removed from the shared pool so no later kind can double-claim one.

No `SPAWNS` entry uses these constraints today — the Compass was the one
kind that needed them (sealed districts made an unfindable compass a real
problem), and it's no longer scattered at all now that it's standard
equipment (see [Salvage.md](Salvage.md)). The machinery stays here, general
and ready, for any future kind that needs a placement guarantee.

## Grant-on-touch

`attachTouch` wires `Touched` on **every** `BasePart` of the pickup (so a
multi-part model grabs from any part, not just a root). A per-pickup `grabbed`
flag debounces: the first valid touch sets it, grants, and `Destroy()`s the
pickup; every other `Touched` that frame — from other character parts or other
model parts — bails on the flag. One grab per pickup; ammo/stamina grants are
`(player:GetAttribute(x) or 0) + n` read-modify-writes.

- **Gun** → `HasGun = true`, `Ammo += GUN_START_AMMO` (12).
- **Ammo** → `Ammo += amount` (6 per ammo pickup).
- **Stamina** → `StaminaBonus += amount` (50).
- **HealthKit** → `Health = min(MaxHealth, Health + amount)` (50). The only
  mid-life heal; 3 spawn per round. See [Health.md](Health.md).

Each grab also bumps a one-shot `PickupToast` attribute (`"kind|nonce"`) that the
client reads to flash "PICKED UP: X". This is deliberately **not** driven off the
granted attributes — `Health` and `Ammo` change every frame (drain, firing), so a
toast keyed on those would fire spuriously (firing the gun used to flash "PICKED
UP: AMMO").

## Stamina upgrade consumer

`SprintController` computes `maxStamina = MAX_STAMINA + (StaminaBonus or 0)`
live every heartbeat and uses it for the drain/regen clamp and the bar-fill
ratio. If the player was topped out under the old max when the bonus lands,
current stamina jumps to the new max too — so the upgrade is felt immediately
instead of just widening unused headroom.

## Dependencies

Reads `ReplicatedStorage.Features.Maze.MazeNav` for cell placement and
`workspace.MazeReady` / `workspace.MazeGeneration`. Written attributes are
read by `Sprint` (`StaminaBonus`) and `Gun` (`HasGun`, `Ammo`); cleared by
`Maze/EscapeService.server.luau`. `Priority = 12`.
