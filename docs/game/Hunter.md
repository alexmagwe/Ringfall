# Hunter

Several creatures that stalk the maze. Each one independently chases the nearest
player it can *sense*, loses the lock if that player crouches behind cover, then
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

Sensing is line-of-sight: `canSee` raycasts against the `Maze` model and treats
`Arc`, `Spoke` and `Perimeter` parts as blockers. A player who is **crouched**
(the `Crouched` attribute, set by the Stealth feature) *and* behind one of those
is skipped entirely.

The catch runs on `Heartbeat` at `CATCH_DIST` (7 studs) and deliberately
**ignores line-of-sight and crouch** — blundering into a hidden player still
catches them. It freezes the player, turns the hunter to face them, swells the
drone, then after 1.4s drops them at their `Checkpoint` attribute and warps the
hunter far away.

Players with `Escaped`, `Caught`, or an unexpired `SafeUntil` attribute are
ignored by both sensing and catching.

## Sound

A looping `HunterDrone` (`rbxassetid://137974203982962`) on the root, rolling off
between 10 and 170 studs on `InverseTapered`. Volume rises from 0.8 to 1.6 during
the catch. This is the main distance cue the player has — be careful raising the
rolloff minimum, since it's what makes a hunter audible before it's visible.

## Dependencies

Reads `ReplicatedStorage.Features.Maze.MazeNav` for the navigation graph and
`workspace.MazeReady` / `workspace.SpawnLocation`. Reads the `Crouched` attribute
published by Stealth, and the `Checkpoint` / `Escaped` / `SafeUntil` attributes.
`Priority = 15`, so it starts after `MazeService` (5).
