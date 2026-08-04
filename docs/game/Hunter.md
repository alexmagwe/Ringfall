# Hunter

Creatures that stalk the maze — **one kind per district**. Each independently
chases the nearest player it can *sense*, loses the lock when a wall breaks
line-of-sight, then falls back to searching their last-known spot and finally to
wandering. Catching a player drags them back to their last checkpoint behind a
red-out.

Files:

- `src/features/Hunter/HunterService.server.luau` — builds the hunters and owns
  all chase / search / wander / catch behaviour. Server-authoritative.
- `src/features/Hunter/HunterController.client.luau` — the "caught" cutscene:
  takes the camera, stares up at the nearest hunter, red flash + shake + fade.

## The three kinds

`HUNTER_KINDS` holds one entry per district, indexed the way
`MazeNav.DISTRICT_BANDS` is — `HUNTER_KINDS[i]` lives in district `i`.

| | Warden (inner) | Stalker (middle) | Stray (outer) |
| --- | --- | --- | --- |
| Count | 3 | 3 | 4 |
| Shots to kill | 16 | 10 | 5 |
| Sight range | 220 | 140 | 90 |
| Contact drain | 34 /s | 25 /s | 18 /s |
| Speed scale | ×1.06 | ×1.0 | ×0.88 |
| Body | duck, scale 8 | duck, scale 7 | **art** (a drone) |
| Attack | contact | contact | **spotter** |
| Eyes | violet | red | amber |
| Drone pitch | 0.7 | 1.0 | 1.35 |
| Hover | grounded | grounded | 4.5 studs |

**They share one AI.** What differs is what they can do, and the escalation is
the point: outward they are many, weak and half-blind; inward they are few,
tough and see a long way. Crossing a gate should change the rules, not the
wallpaper. The **Stalker is the untouched original**, so the middle district
still plays exactly as the game was tuned, and the other two are read against it.

**`sightRange` is the stat that changes a district most.** Sensing used to be
line-of-sight with no limit at all — any hunter saw any player down the whole
length of a corridor. A Stray at 90 studs can be walked past once you know what
you're doing; a Warden at 220 owns the corridor it stands in. The distance test
runs *before* the raycast, since `canSee` costs a raycast per candidate per
repath.

**`speedScale` multiplies the depth ramp rather than replacing it**, so the
existing "faster the deeper you are" curve still shapes all three and only the
type's character layers on top. It is applied alongside the per-hunter
`SPEED_VARIANCE` jitter, which does a different job — that one strings a pack
out, this one separates the kinds.

**The drone is pitched per kind**, so you can hear *which* one is near before you
see it.

### Home districts

`spawnHunter(kind, district)` records `HomeDistrict` on the model. It decides
only where a hunter **enters** the maze — they roam freely after that, and a
Warden wandering out into the middle district is working as intended.

Carrying the district through death and rebuild is what stops the spread
collapsing: respawns and re-homes both use it, so each district holds the same
population at the end of a round as at the start. `farSpawn` picks a random
**cell from `MazeNav`** in that district rather than rolling a radius and angle —
the old version used one fixed band (180–480) that straddled the middle district
and clipped the other two, so the outer ring players spawn in and the deep inner
ring both started nearly empty however many hunters existed. It could also land
inside a wall or in the hub sanctuary, where a hunter does nothing but walk out.

## Studio assets

**One model, and only one: `Stray`.**

The **ducks are the enemy**. Warden and Stalker have `model = nil` on purpose —
they are the code-built duck at different scales and tints (violet at 8, red at
7), which is the look the whole game was built around. Only the Stray carries
art, because a drone has to look like a machine: it *behaves* like neither of the
others, reporting you instead of attacking, and that has to be readable on sight.

**Where art goes:** a `Folder` named **`HunterModels`** under **ServerStorage**,
with a child named by a kind's `model` field. A Model, Tool, bare BasePart,
`Accessory` or legacy `Hat` all work — everything is normalised into a Model
first, and a Tool is *unwrapped* rather than nested (the same trap that had
pickups auto-equipping onto players).

That normalisation is not cosmetic. The scale-and-ground step can only measure a
Model, and it used to be skipped for anything that wasn't one — so a `Hat` or a
bare part would have been welded at whatever CFrame it carried in ServerStorage,
unscaled and nowhere near the hunter.

**A model with no `BasePart` in it falls back and warns.** That is worth knowing
because the failure is invisible: an empty `Hat` named `Warden` produced a
perfectly good-looking duck, since the fallback *is* a duck. Read the output:

```
[Hunter] "Warden" has no BasePart; falling back to the built-in body
```

Art is scaled to the kind's `scale` on its longest axis, **stood on the
collider's base**, and welded to the root **unanchored and massless**.

The grounding matters more than it sounds. `DUCK_LIFT` centres the body on the
collider, which works for the duck because the duck is about as tall as the
collider is — but a short or wide model centred the same way hangs several studs
off the floor with its legs dangling. That is exactly what the spider did. The
base rule is now "put the art's lowest point on the collider's lowest point",
whatever shape it is.

**`kind.hover` then lifts it back off the ground on purpose**, in studs to the
bottom of the art. Grounding is right for legs and wrong for a drone — and since
nothing here animates, that number is the entire difference between "flying" and
"prop someone left on the floor". The Stray is a drone and sits at 4.5, clearing a
5-stud character's head so you look *up* at it; the other two are grounded. That is the opposite of every other art path here:
a pickup and a salvage piece hang still, so anchoring is what keeps them put; a
hunter *moves*, and an anchored part welded to a moving root either drags it to a
halt or tears free. Massless matters for the same reason — walk speed should not
depend on how heavy someone's mesh is.

**The collider stays 3×6×3 whatever the art is.** Corridor navigation is tuned
against that box and a wider one wedges in the maze, so the visual body is
deliberately allowed to overhang it.

**The neon eyes are fallback-only.** Their offsets are absolute studs measured
against the duck's painted sockets, so on someone else's model they would be two
spheres floating at nothing. When art is attached the eyes are skipped and a
`KindGlow` `PointLight` in the kind's colour goes on the root instead, so the
colour tell survives. `HunterController`'s catch-cam looks for a part named
`Eye` and falls back to `PrimaryPart`, so it costs only a slightly wider framing.

### The Stray is a spotter, not a fighter

**It deals no damage at all.** A drone that bites makes no sense; a drone that
reports you does. Seeing you raises the same alert a gunshot raises —
`HunterAlert` + `HunterAlertPos` at your position — which pulls every hunter
within `SUMMON_RADIUS` (200) onto you for `SUMMON_WINDOW` (5s). It writes the
same two attributes rather than growing a second summon path, so nothing else in
the file had to learn about it.

That makes the outer district a **stealth problem** instead of a weaker version
of the same fight: being *seen* is the punishment, and what arrives is a Stalker.
It is also the right lesson for the district players start in, since the whole
maze runs on line of sight.

Three things keep it fair:

- **Throttled to `SPOT_REFRESH` (1s).** The alert is one shared workspace slot;
  rewriting it every tick would pin the district on you permanently. That is the
  cadence the vault alarm already refreshes at.
- **It flares and sounds an alarm while it holds the lock** — brightness 8 and
  range 60 on its light, plus a looping `SpotAlarm` on its root
  (`rbxassetid://9113865897`, Pro Sound Effects, whose own description reads
  *Tracker / Triangulate / Warning / Indicator*). Being reported is otherwise
  invisible: no damage, and the consequence arrives from off-screen seconds
  later, which reads as the game cheating rather than as a mistake you made.

  **A loop, not a sting, and that choice is the teaching.** The alarm starting
  says "seen"; the alarm *stopping* says "you broke line of sight" — so the
  escape rule is learned by ear, in the moment. A sting on acquire would announce
  the problem and leave you guessing whether you had solved it. Its roll-off is
  tighter than the body drone's (120 vs 170) so it tells you which way to break.

  **The lapse check runs at the top of the AI loop, above every `continue`.**
  It has to: the evac and summon branches both skip the rest of the tick, and a
  spotter answers its own alert — so with the reset further down, a drone raised
  the alarm once, summoned itself, and then either screamed for the whole
  `SUMMON_WINDOW` after losing you or never refreshed the lock at all. Sensing
  moved above those branches for the same reason, which also removed a duplicate
  `nearestSensed` raycast per tick.
- **It sets `SpottedAt` on the player**, a timestamp any HUD can read later.

A spotter still chases, because following you is how it keeps you in sight — it
just never converts the lock into damage.

**One shared slot, one caveat.** The vault alarm also refreshes `HunterAlert`,
so a Stray spotting someone while the alarm rings will briefly redirect hunters
from the vault to that player. In practice the vault's own refresh targets
whoever carries it, so the two usually agree.

### How a player actually touches a hunter

Three separate systems, and a hovering kind pulls them apart — worth knowing
before setting `hover` on anything else.

- **Shooting** hits the **art**, which is `CanQuery = true`. That is the opposite
  of pickup and dressing art, and deliberate: being shootable is the whole point
  of an enemy. With it false a bullet passed straight through the body you can
  see, and the only hittable part was the invisible collider — which for the
  Stray sits on the floor, entirely below its art. It cannot block a sightline
  either way, because `canSee` filters `Include {maze}` and has never considered
  anything but walls.
- **The catch** works off the **collider**, not the art. `nearestReachable`
  measures to the root, so contact happens when a player comes within
  `CATCH_DIST` (7) of that 3×6×3 box on the ground. Contact kinds only: a
  spotter returns before the drain and can never catch you by touch.
- **Walking** is blocked by the collider too, so **you cannot walk under a
  hovering hunter** even though it looks like you could. The drone occupies its
  whole column. Raising the collider for fliers is not an option: corridor
  navigation is tuned against 3×6×3.

**Pick art that has no legs to animate.** Parts are welded *rigidly* to the root
— nothing here plays an animation, and a rigged R15 character would slide around
the maze frozen in its T-pose. Anything that reads as floating or gliding works
with that instead of against it: drones, orbs, hovering machines, wisps.

## The fallback avatar

Used for any kind with no art in `ServerStorage.HunterModels`: the duck mesh,
scaled and tinted **per kind** so the three still read apart with zero assets.

**The texture is not the yellow bath duck.** `268365500` is already a dark
mechanical duck with red eyes and a teal beak painted on. A kind's `tint` only
knocks it down — pushing it much below ~0.4 on every channel flattens the panel
detail and the beak into a featureless black blob, which reads worse, not
scarier.

| Constant | Value | Why |
| -------- | ----- | --- |
| `DUCK_MESH` | `rbxassetid://9419831` | Duck mesh |
| `DUCK_TEXTURE` | `rbxassetid://268365500` | Dark mechanical duck texture |
| `DUCK_LIFT` | `0.8` | Puts the mesh's feet on the collider's base instead of through the floor |
| `kind.scale` | 6 / 7 / 8 | On a 2x2x2 host part, 7 renders ~7.5 studs tall against a 5-stud player |
| `kind.tint` | per kind | `SpecialMesh.VertexColor`, multiplies the texture down |

Scale and tint moved onto the kind when the districts got their own enemies —
there is no single `DUCK_SCALE` or `DUCK_TINT` any more, and nothing to tune
globally.

With the fallback body, the model is three parts:

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
at a level camera, not derived** — they are absolute studs rather than
proportions, so they are measured against the Stalker's scale of 7. A kind with a
very different `scale` wears its eyes slightly off the socket, and art skips them
entirely (see [Studio assets](#studio-assets)).

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

Ten hunters spawn once `workspace.MazeReady` is set — 4 Strays, 3 Stalkers and
3 Wardens, each at a `farSpawn` cell inside its own district and away from the
player spawn (see [The three kinds](#the-three-kinds)).

Each runs a loop every `REPATH` (0.7s) picking one of three states:

- **Chase** — a player is sensed. Speed scales from `BASE_SPEED` (18.7, just
  above walk) to `MAX_SPEED` (31.9) the deeper into the maze the target is, via
  `SPEED_PER_BAND` (1.1). Steps cell-by-cell along `MazeNav` toward them.
  All three track player speed (`SprintController`'s walk 17.6 / sprint 28.6) —
  move one and scale the others by the same factor or the chase changes feel.
- **Search** — lock lost. Walks to the last cell the player was sensed in at
  `BASE_SPEED`, then gives up.
- **Wander** — no lead. Picks random maze cells.

### The pack must not move as one animal

`MazeNav.nextStep` is a plain BFS, so **identical start cell + identical goal
cell = identical first step**. Six hunters running the same decision loop against
the same target therefore picked the same route every tick and travelled
nose-to-tail down one corridor — six creatures reading as one. Four things break
that symmetry, none of which touches the kind counts, `BASE_SPEED` or `MAX_SPEED`:

| Mechanism | Constant | What it fixes |
| --------- | -------- | ------------- |
| **Flanking** | `FLANK_RANGE` (60) | Beyond 60 studs a chaser paths to a *different open neighbour* of the target's cell — `chaseCell` picks it by the hunter's fixed `flankSeed`, so it keeps claiming the same approach instead of dithering in a doorway. The pack converges from several corridors. Inside 60 studs everyone commits to the target's own cell, because the catch needs `CATCH_DIST` (7) and a hunter loitering one cell away never gets there. |
| **Separation** | `SEPARATION_DIST` (12), `SEPARATION_STRENGTH` (8) | `spread` offsets the `MoveTo` goal away from any peer within 12 studs, so they fan across a corridor's width rather than stacking. |
| **Repath jitter** | `REPATH_JITTER` (0.45) | `nextRepath` re-rolls the tick interval **every tick**, not once per hunter — a fixed per-hunter offset lets two hunters with near-identical intervals drift back into lockstep. |
| **Speed variance** | `SPEED_VARIANCE` (0.12) | A fixed ±12% per hunter, applied by `setSpeed` on top of whatever the current state chose, so a group chasing one target strings out instead of arriving as a wall. |

The subtle part is inside `spread`: it keeps only the component of the push
**across** the direction of travel. A peer directly ahead has to make this hunter
step *around* it, not brake behind it — braking is what produced the single file
in the first place. When the peer is dead ahead or dead behind there's no lateral
information to work with, so the hunter falls back to its own fixed `side`
(±1, drawn at spawn); peers that drew the other side go the other way, which is
what actually splits the file.

`activeRoots` is the module-level map of live hunter roots that makes separation
possible. Entries are added in `spawnHunter` and removed in `Died`, and `spread`
skips any root whose `Parent` is nil, so a hunter destroyed by some other path
can't repel the living from beyond the grave.

A chaser that reaches its claimed approach cell while still outside
`FLANK_RANGE` simply holds position. That reads as cutting off an exit, and it
resolves itself as soon as the target changes cell.

### Hunters cannot enter the vault chamber

The hub is a sanctuary — everything inside `SANCTUARY_RADIUS` (40; band 0 ends
at 30, so that's a little margin past the hub wall). Two halves, same shape as
the perimeter rule below:

- **Targeting.** `outOfRound` returns true for any player inside it, so they're
  invisible to `nearestSensed` and `nearestReachable`: no chase, no contact
  drain, no catch. The run is a long committed descent, and arriving at the
  bottom on 20 HP with three hunters on you is a coin-flip ending rather than a
  climax — this is the breather at the turnaround. You still have to carry the
  vault all the way back out with every hunter alerted.
- **Containment.** Hunters stay physically out, not just harmless inside. One
  pacing the dais next to an untouchable player reads as a bug, not as mercy.
  `keepOutOfHub` redirects any destination that resolves to band 0 to the
  nearest cell just outside it, so hunters ring the gates; and a hunter that
  ends up inside anyway (momentum on a commit near the boundary, a blast shove)
  does nothing but walk out, routed through the graph so it leaves by a gate.

Containment is needed because three targets legitimately resolve to the hub:
the **vault alarm** summons every hunter to the vault's position (which *is* the
hub), the **evac alert** sends them at the centre, and a **flank pick** is a
neighbour of the target's cell — so chasing someone in band 1 can claim band 0.
Wander is handled at the source: `refreshNav` leaves band 0 out of the pool
`randomCell` draws from.

### Hunters cannot leave the maze

Checked before any of the three states. **The staging room and its corridor are
off-limits** — everything past `MazeNav.perimeterR` (the perimeter wall's XZ
radius, published by `MazeService.rebuild`). Two halves, because either alone
leaks:

- **Targeting.** `outOfRound` now returns true for any player outside the
  perimeter, so they are invisible to `nearestSensed` *and* `nearestReachable` —
  no chase, no contact drain, no catch. Same mechanism as the hub
  `SANCTUARY_RADIUS`, just at the other end of the map.
- **Containment.** If a hunter is itself outside — drifted out on `MoveTo`
  momentum near the perimeter cut, or shoved by physics — its only behaviour is
  to walk back to the nearest cell. It doesn't chase, respond to a summon, or
  wander while out there.

Without the first half a hunter would follow a fleeing carrier straight through
the cut and camp the extraction pad, which would make the one guaranteed safe
space in the game unsafe — including during the staging countdown, when every
player is standing in that room unable to move. Without the second, a hunter
already outside would be pathing off the end of its own graph: the maze has no
cells out there.

`farSpawn` was never a leak — it picks a radius of 180–480, always well inside
the perimeter (534).

The boundary is read off `MazeNav`, not hardcoded, so retuning `RADII` can't
leave it stale. It reads 0 until the first build, and the guard is inert then.

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

### Kit dies on catch too — but not from here

`HunterService` clears **only** `Haul` and `HasVault`. Everything else you were
carrying is stripped by the feature that granted it, each watching the `Caught`
attribute independently:

- `PickupsService` → `HasGun`, `Ammo`, `StaminaBonus`
- `StoreService` → whatever was rented from the shelf this round

That's why `HunterService` doesn't name Gun, Sprint or the Store —
setting `Caught` is the whole of its involvement, and features subscribe to it.
Adding a new kind of carried thing means one listener in its own feature and no
edit here. See [Pickups.md](Pickups.md) for why catch stopped sparing found kit.

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

**Health bar.** `buildHunter` sets `hum.MaxHealth = hum.Health = kind.hits`
(5 Stray / 10 Stalker / 16 Warden) — each gunshot is 1 damage, so that is the
shot count to kill. A Warden costs more than a full magazine. A `BillboardGui` over the
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
3. `hunter:Destroy()`, then a `RESPAWN_DELAY` (4s) respawn of **the same kind
   into the same district**, so each district's population is constant over a
   round rather than decaying toward wherever things happened to die.

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

Firing a gun (see [Gun.md](Gun.md)) alerts other hunters to the shooter's
position, mirroring the `EvacAlert` pattern above but distinct from it:

- `GunService` (the producer, Gun feature) sets
  `workspace.HunterAlert` (an `os.clock()` timestamp) and
  `workspace.HunterAlertPos` (a `Vector3` — workspace attributes accept
  `Vector3` directly) on **every shot, hit or miss**. The noise is what
  carries, so missing costs the same as connecting. A player who rented the
  **Silencer** sets neither, and shoots without summoning anyone.
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
