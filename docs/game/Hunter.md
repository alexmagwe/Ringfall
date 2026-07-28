# Hunter

Several creatures that stalk the maze. Each one independently chases the nearest
player it can *sense*, loses the lock when a wall breaks line-of-sight, then
falls back to searching their last-known spot and finally to wandering. Catching
a player drags them back to their last checkpoint behind a red-out.

Files:

- `src/features/Hunter/HunterService.server.luau` — builds the hunters and owns
  all chase / search / wander / catch behaviour. Server-authoritative.
- `src/features/Hunter/HunterController.client.luau` — the "caught" cutscene:
  takes the camera, stares up at the nearest hunter, red flash + shake + fade.

## Studio assets

**None.** The hunter is built procedurally at runtime. Nothing needs to exist in
Workspace, ServerStorage, or ReplicatedStorage — the avatar is two asset IDs
baked into `HunterService`, so the whole enemy lives in version control and
survives a fresh clone of the place.

## The avatar

The body is the duck mesh, scaled up and darkened so it reads as a looming
silhouette, with two neon-red eyes over the texture's painted eye sockets.

**The texture is not the yellow bath duck.** `268365500` is already a dark
mechanical duck with red eyes and a teal beak painted on. `DUCK_TINT` only knocks
it down a little — pushing it much darker flattens the panel detail and the beak
into a featureless black blob, which reads worse, not scarier.

| Constant | Value | Why |
| -------- | ----- | --- |
| `DUCK_MESH` | `rbxassetid://9419831` | Duck mesh |
| `DUCK_TEXTURE` | `rbxassetid://268365500` | Dark mechanical duck texture |
| `DUCK_SCALE` | `7` | On a 2x2x2 host part this renders ~7.5 studs tall, against a 5-stud player |
| `DUCK_TINT` | `(0.6, 0.58, 0.66)` | `SpecialMesh.VertexColor`, multiplies the texture down |
| `DUCK_LIFT` | `0.8` | Puts the mesh's feet on the collider's base instead of through the floor |

The model is three parts:

- `HumanoidRootPart` — invisible, 3x6x3, the only colliding part. This is what
  actually moves and what the maze navigation is tuned against. **Keep it at
  3x6x3 when changing the look** — corridor clearance depends on it, and the
  visual mesh is deliberately allowed to overhang it.
- `Body` — a 2x2x2 host for the `SpecialMesh`, welded, non-colliding, massless.
- `Eye` / `Eye2` — neon spheres. Only `Eye` carries the `PointLight`; one is
  enough for the glow, and `HunterController` focuses its catch-cam on a part
  named `Eye` specifically, falling back to `PrimaryPart`.

### Eye placement

`EYE_X = 1.50`, `EYE_Y = 3.10`, `EYE_Z = 2.80` (studs from the root centre,
mirrored on X). These were **measured in Studio against a 5-stud reference slab
at a level camera, not derived** — if you change `DUCK_SCALE` they all need
re-measuring, since they're absolute studs rather than proportions.

Two traps make this fiddly enough to be worth documenting:

**The beak juts roughly 4 studs forward** and swallows anything placed at or
below beak height. Several arithmetically-correct placements rendered completely
invisible because of it. The mesh's rendered silhouette is also a poor guide to
where its surface actually is — probe with marker parts rather than trusting a
sphere approximation.

**The glow sits only ~0.15 studs proud of the surface**, which is deliberate.
Further out and it renders reliably but parallax drags it off the painted socket
when you look up at the duck — and since it's 7.5 studs tall, players usually
*are* looking up. Closer in and it disappears into the mesh. Verify any change
from a level camera, which is the angle that matters in play.

## Behaviour

`HUNTER_COUNT = 3` hunters spawn once `workspace.MazeReady` is set, each at a
`farSpawn` point well away from the player spawn.

Each runs a loop every `REPATH` (0.7s) picking one of three states:

- **Chase** — a player is sensed. Speed scales from `BASE_SPEED` (17, just above
  walk) to `MAX_SPEED` (29) the deeper into the maze the target is, via
  `SPEED_PER_BAND`. Steps cell-by-cell along `MazeNav` toward them.
- **Search** — lock lost. Walks to the last cell the player was sensed in at
  `BASE_SPEED`, then gives up.
- **Wander** — no lead. Picks random maze cells.

Sensing is pure line-of-sight: `canSee` raycasts against the `Maze` model and
treats `Arc`, `Spoke` and `Perimeter` parts as blockers. Any player behind one of
those is skipped entirely — **breaking line-of-sight is the whole stealth
mechanic**. There is no crouch; it was removed as a verb because it added an
input without adding a decision, and it required a Studio-authored animation to
look like anything. Cover alone now does the work.

Contact is now a **drain, not an instant catch**. On `Heartbeat`, while a player
is within `CATCH_DIST` (7 studs) — line-of-sight ignored, so a blind corner still
counts — the hunter bleeds their `Health` attribute by `HEALTH_DRAIN` (25 HP/s).
A hunter has to *stay* on you; break contact and the bleed stops. Only when
`Health` reaches **0** does the catch proper fire: freeze the player, turn the
hunter to face them, swell the drone, then after 1.4s — after spilling any
`Haul`/`HasVault` the player was carrying (see below) — drop them at their
`Checkpoint` and **refill Health to full**. **The hunter itself no longer
warps away** — it lingers at the kill site, guarding the drops it just made
(see [Salvage.md](Salvage.md#drop-steal-recover)). This is safe because the
caught player respawns at their last *gate* checkpoint with `SafeUntil`
grace, not at the death site itself (see [Checkpoint.md](Checkpoint.md)).
Multiple hunters stack their drain, so being swarmed kills fast. See
[Health.md](Health.md).

### Spilling Haul and the Vault on catch

Immediately before the checkpoint teleport, `catchPlayer` captures the
player's death position (`phrp.Position` — still accurate, since `phrp` has
been anchored in place since the initial catch) and:

- If `Haul > 0`: `SalvageService.dropHaul(deathPos, haul)`, then zeroes
  `Haul`.
- If `HasVault`: `SalvageService.dropVault(deathPos)`, then clears
  `HasVault`.

`HunterService` requires `SalvageService` directly
(`ServerScriptService.Features.Salvage.SalvageService`) for this — the same
cross-feature server require `EscapeService` already uses for `MazeService`.
See [Salvage.md](Salvage.md) for what those two dropped objects do.

Players with `Escaped`, `Caught`, or an unexpired `SafeUntil` attribute are
ignored by both sensing and draining/catching.

The **explosion** (a shot-dead hunter) still catches instantly within
`BLAST_RADIUS` rather than draining — a point-blank blast is lethal regardless of
Health. Change the `catchPlayer` call in the `Died` handler to a `Health` hit if
you'd rather explosions be survivable.

## Sound

A looping `HunterDrone` (`rbxassetid://137974203982962`) on the root, rolling off
between 10 and 170 studs on `InverseTapered`. Volume rises from 0.8 to 1.6 during
the catch. This is the main distance cue the player has — be careful raising the
rolloff minimum, since it's what makes a hunter audible before it's visible.

## Combat

Hunters are killable (see [Gun.md](Gun.md) for the shooter side), but the maze
never empties — a dead hunter respawns at a far cell. No new player-HP model
was added; "caught" is still a teleport to checkpoint, and the explosion
below reuses that exact `catchPlayer` flow rather than dealing damage.

**Health bar.** `buildHunter` sets `hum.MaxHealth = hum.Health = HUNTER_HITS`
(10) — each gunshot is 1 damage, so 10 hits kill. A `BillboardGui` over the
root (`StudsOffset = (0, 4, 0)`) holds a dark background `Frame` and a red
`Fill` `Frame`; `hum.HealthChanged` toggles `billboard.Enabled = health <
MaxHealth` and resizes `Fill` to `health / MaxHealth`. Property changes on a
GUI replicate to every client, so the draining bar needs no client code.

**Death → explosion → catch → respawn.** `hum.Died` is connected once inside
`spawnHunter` (not exported — `catchPlayer` / `farSpawn` / `spawnLocation` are
only in scope inside that closure):

1. `explodeAt(root.Position)` — a module-level helper: a Neon ball tweens its
   `Size` up to `BLAST_RADIUS * 2` and `Transparency` to 1 over ~0.4s, then
   `Destroy()`s. No asset required; if `BLAST_SOUND_ID` is later set, a Sound
   plays alongside it.
2. Every player within `BLAST_RADIUS` (14 studs) who isn't already
   `outOfRound` gets `catchPlayer`'d — same freeze/loom/checkpoint-teleport
   flow as the normal bump-catch, just triggered by the blast instead of
   `Heartbeat` proximity. `catchPlayer`'s own `Caught` early-return means a
   multi-hunter chain can't double-catch the same player.
3. `hunter:Destroy()`, then `task.delay(RESPAWN_DELAY, spawnHunter)` (4s) —
   `HUNTER_COUNT` (3) stays constant over time.

**Connection teardown on death.** Every per-hunter connection — the `Heartbeat`
catch loop, the `PlayerAdded` hook, and each per-player `Escaped` watcher — is
collected into a `conns` table and disconnected in the `Died` handler. This is
not just hygiene: a destroyed part keeps returning its **frozen** `Position`, so
a live `Heartbeat` catch loop would go on checking the dead hunter's death spot
and drag any player who later walked within `CATCH_DIST` of it to their
checkpoint — an invisible trap left at every kill site. The decision-loop
`task.spawn` is the one exception: it self-terminates via its
`while hunter.Parent` guard and so isn't tracked in `conns`.

## Summon — retaliation has a cost

Shooting a hunter (see [Gun.md](Gun.md)) alerts other hunters to the shooter's
position, mirroring the `EvacAlert` pattern above but distinct from it:

- `GunService` (the producer, Gun feature) sets
  `workspace.HunterAlert` (an `os.clock()` timestamp) and
  `workspace.HunterAlertPos` (a `Vector3` — workspace attributes accept
  `Vector3` directly) on a successful hit.
- `HunterService` (the consumer, here) checks this branch **after** the
  `EvacAlert` branch and **before** the normal CHASE decision, each `REPATH`
  tick: any hunter within `SUMMON_RADIUS` (200 studs) of `HunterAlertPos`, for
  `SUMMON_WINDOW` (5s) after `HunterAlert`, sprints (`MAX_SPEED`) toward the
  nearest cell to that position instead of chasing/searching/wandering
  normally.
- **The vault alarm reuses this exact branch and shares its two attributes.**
  `SalvageService` sets `workspace.AlarmActive = true` the instant the vault
  is taken, and refreshes `HunterAlert` / `HunterAlertPos` every second at
  wherever the vault currently is (see
  [Salvage.md](Salvage.md#the-vault-and-the-alarm)) — no new hunter pathing
  was written for this. The one difference: `AlarmActive` **bypasses the
  `SUMMON_RADIUS` check entirely** —

  ```lua
  and (alarmActive or (root.Position - (sPos :: Vector3)).Magnitude < SUMMON_RADIUS)
  ```

  — a gunshot summon is local (only nearby hunters respond), but the vault
  alarm is a maze-wide siren (every hunter responds, regardless of distance).
  `SUMMON_RADIUS` itself is untouched; only the alarm skips it.
- Both attributes (plus `AlarmActive` and `VaultTaken`) are cleared (`nil`) by
  `MazeService.rebuild` directly on every generation — a stale alert or a
  stale "vault is out" state can never carry into a new round. See
  [Maze.md](Maze.md#the-rebuild-footgun--workspacemazegeneration).
- `SIREN_SOUND_ID = ""` is a seam here (unused until Gun's own copy plays a
  siren on the hit hunter — see [Gun.md](Gun.md)); silent until the user
  supplies an asset.

## Evac alert — converging on the pad (currently dead)

`workspace.EvacAlert` (a `os.clock()` timestamp) was set by `EscapeService`
the moment any player touched the old `ExitGate`. For `EVAC_ALERT_SECONDS`
(4s) afterward, **every** hunter would override its normal
chase/search/wander decision and sprint (`MAX_SPEED`) straight for the cell
nearest world-centre — the branch is checked first, before the CHASE state,
each `REPATH` tick.

**Nothing sets `EvacAlert` anymore.** The extraction-loop rework
(see [Escape.md](Escape.md)) removed the per-player win entirely — the win
trigger moved to the staging room's `ExtractPad`, and nothing there sets this
attribute. This branch is left in place (not removed) since the plan's
phases 1–5 don't specify a replacement trigger for it; it's dead code, not a
bug, and safe to leave — see [Escape.md](Escape.md#whats-now-dead-and-why-its-safe-to-leave-that-way).

## Rebuild refresh

`MazeService.rebuild` re-carves the maze on every round (see
[Maze.md](Maze.md)'s `MazeGeneration` contract). `HunterService` listens for
`workspace:GetAttributeChangedSignal("MazeGeneration")` and:

1. Re-snapshots `cellKeys` (from `MazeNav.cellPos`) and `maxBand` — these were
   captured once at `Start()` and go stale the instant the graph changes.
2. Re-homes every live `Hunter` model to a fresh `farSpawn` point.

Per-hunter `lastKnownCell` / `wanderTarget` closures are **not** explicitly
reset on rebuild — re-homing the model is enough, since `stepToward` reads
`MazeNav` live every step and will naturally re-path within one `REPATH` tick
(0.7s) once the hunter is somewhere valid in the new layout.

## Dependencies

Reads `ReplicatedStorage.Features.Maze.MazeNav` for the navigation graph and
`workspace.MazeReady` / `workspace.MazeGeneration` / `workspace.EvacAlert` /
`workspace.HunterAlert` / `workspace.HunterAlertPos` / `workspace.AlarmActive` /
`workspace.SpawnLocation`, and the `Checkpoint` / `Escaped` / `SafeUntil` /
`Haul` / `HasVault` player attributes. `workspace.HunterAlert` /
`HunterAlertPos` are written by both `Gun/GunService.server.luau` (see
[Gun.md](Gun.md)) and `Salvage/SalvageService.server.luau` (see
[Salvage.md](Salvage.md)) — Hunter only consumes them, and doesn't care which
producer set them. `HunterService` requires `SalvageService` directly
(`ServerScriptService.Features.Salvage.SalvageService`) for the drop-on-catch
path (`dropHaul`/`dropVault`). `Priority = 15`, so it starts after
`MazeService` (5).
