# Pickups

Scavenged items scattered around the maze each round: a **gun**, **ammo**, a
**compass**, a **flashlight**, a **stamina upgrade**, and **MedKits**. Grabbing
one is a one-touch grant of a **per-run player attribute** — nothing here ever
reaches PlayerData. A fresh round (RUN IT BACK) wipes all of it and re-scatters to
new cells.

Files:

- `src/features/Pickups/Constants.luau` — the folder name, float height, spin
  speed, and the `SPAWNS` table (kind/count/color/amount per pickup type).
- `src/features/Pickups/PickupsService.server.luau` — scatters pickups at
  random maze cells and grants attributes on touch. Server-authoritative.
- `src/features/Pickups/PickupsController.client.luau` — spins the pickups
  and flashes a "PICKED UP: X" toast. Purely cosmetic; raw HUD (no React).
- `src/features/Pickups/CompassController.client.luau` — the compass arrow HUD.

## Studio assets

**Optional models.** Place a `Folder` named `PickupModels` under **ServerStorage**
with the art for each kind inside. The art's instance name is **not** matched to
the kind — instead each `SPAWNS` entry in `Constants.luau` carries a `model`
field naming the child to clone, so art can be named anything (current mapping:
Gun→`GatlingLaser`, Ammo→`Battery`, Compass→`Compass (by Artem Goyko)`,
Stamina→`StaminaBoost`).

The art can be a **Model, a Tool, or a single BasePart** (Union / MeshPart /
Part). `buildPickup` normalizes all three into a Model container, then:

- **strips every `LuaSourceContainer`** from the clone — a free-model Tool ships
  with its own scripts that would otherwise run the instant it enters the world
  (the spider-`Animate` hazard); a pickup is pure decoration and needs none.
- anchors + de-collides + `Massless`es every part, so it stays rigid regardless
  of the art's welds, never blocks a player, and — nested in the container, not a
  direct child of `workspace` — a **Tool can't auto-equip on touch**.
- floats it at the cell centre, spins it (`Model:PivotTo`, no `PrimaryPart`
  needed), and wraps it in an occluded `Highlight` (kind-colored outline) so it's
  findable in the fog without recoloring the mesh or glowing through walls.

Any kind whose `model` is missing from the folder falls back to a code-built Neon
ball, so the feature works before any art exists and you can add pieces one at a
time. `MODELS_FOLDER` in `Constants.luau` names the folder.

The grab hitbox is every `BasePart` in the container; a `grabbed` flag debounces
so a multi-part model can't double-grant.

## The per-run attributes

Set by `PickupsService` on pickup, read wherever they're consumed, cleared by
`EscapeService`'s `Net.Restart.listen` loop on RUN IT BACK (not on ordinary
respawn — a caught player keeps their loot within the same run).

| Attribute | Type | Meaning | Consumed by |
| --------- | ---- | ------- | ----------- |
| `HasGun` | bool | player owns the gun this run | `GunController` (HUD gate), `GunService` (fire gate) |
| `Ammo` | number | rounds remaining, authoritative | `GunController` (HUD), `GunService` (fire gate + decrement) |
| `HasCompass` | bool | compass HUD active | `CompassController` |
| `HasFlashlight` | bool | flashlight cone on | `FlashlightController` |
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

The **Compass** is the only constrained entry today (sealed districts made an
unfindable compass a real problem — see below):

```lua
{ kind = "Compass", model = "Compass (by Artem Goyko)", count = 1,
  color = Color3.fromRGB(80, 200, 255), minBand = 9, maxBand = 12, minSpawnDist = 150 },
```

`minBand = 9, maxBand = 12` is the OUTER district (see [Maze.md](Maze.md)) —
where the player always starts, so it's guaranteed reachable before the first
sealed boundary. `minSpawnDist = 150` keeps it off the straight-line inward
route from `SpawnLocation`, so grabbing it is still a real detour decision, not
a freebie sitting on the obvious path.

## Grant-on-touch

`attachTouch` wires `Touched` on **every** `BasePart` of the pickup (so a
multi-part model grabs from any part, not just a root). A per-pickup `grabbed`
flag debounces: the first valid touch sets it, grants, and `Destroy()`s the
pickup; every other `Touched` that frame — from other character parts or other
model parts — bails on the flag. One grab per pickup; ammo/stamina grants are
`(player:GetAttribute(x) or 0) + n` read-modify-writes.

- **Gun** → `HasGun = true`, `Ammo += GUN_START_AMMO` (12).
- **Ammo** → `Ammo += amount` (6 per ammo pickup).
- **Compass** → `HasCompass = true`.
- **Flashlight** → `HasFlashlight = true`.
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

## Compass HUD

Raw `TextLabel` arrow ("▲") pinned top-centre, visible only while
`HasCompass`. With sealed districts, pointing at world-centre would walk a
player straight into a wall whenever the next gate is elsewhere on the ring —
so each frame it instead targets **the gate with the largest radius that is
still smaller than the player's own radius**, i.e. the next gate inward, and
falls back to world-centre `(0,0,0)` once the player is past the innermost
gate. It reads `workspace.Gates` live every frame and compares radii only —
**no district math on the client** — so it retargets the instant a gate is
passed and self-heals across maze rebuilds without any extra wiring. The
bearing math itself (camera-flat-look vs. flat direction to target) is
unchanged from before; only what counts as "the target" changed.

This is a bearing, not a path: it ignores walls on purpose. Knowing the gate
is north-east still leaves you solving the ring to reach it — that's the point
of the sealed-district mechanic, not a limitation to fix.

## Dependencies

Reads `ReplicatedStorage.Features.Maze.MazeNav` for cell placement and
`workspace.MazeReady` / `workspace.MazeGeneration`. Written attributes are
read by `Sprint` (`StaminaBonus`) and `Gun` (`HasGun`, `Ammo`); cleared by
`Maze/EscapeService.server.luau`. `Priority = 12`.
