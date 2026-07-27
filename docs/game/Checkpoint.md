# Checkpoint

Checkpoints are **gates**, not rings. The maze is sealed into three districts
(see [Maze.md](Maze.md)); crossing inward through a district's gate sets that
gate as the player's respawn point. Getting caught throws you back to
re-solve the whole district you were in, not back a few seconds of corridor —
ordinary band boundaries *within* a district do nothing.

File: `src/features/Checkpoint/CheckpointService.server.luau`. Auto-loaded
(name ends in `Service`), `Priority = 20` (after Hunter's 15).

## State (player attributes)

Shared via attributes so the Hunter stays decoupled from Checkpoint:

| Attribute | Type | Meaning |
| --------- | ---- | ------- |
| `Checkpoint` | CFrame | Where a caught player respawns — a gate's floor-level CFrame, or the drop-in position before any gate is crossed |
| `SafeUntil` | number | `os.clock()` deadline until which the hunter ignores this player |
| `CheckpointRing` | number | The district just entered; the client toast (`CheckpointController`) reacts to this changing, purely as a fire signal — it displays a generic "CHECKPOINT" flash, not the number |

`HunterService.catchPlayer` teleports a caught player to `Checkpoint + Vector3.new(0, 3, 0)`
and falls back to `SpawnLocation.CFrame + (0, 3, 0)` if `Checkpoint` is unset.

## District tracking, not band tracking

Every `Heartbeat`, for each connected player: find their nearest maze cell
(`MazeNav.nearestCell`), read its band (`MazeNav.bandOf`), and convert to a
**district** via `MazeNav.districtOf` — the single shared band→district
mapping (also used by `MazeService` for carving and gates; see
[Maze.md](Maze.md)). A per-player `deepest` table tracks the shallowest
(smallest-number) district reached this life; `nil` means no read yet.

- **First read of a life** (`prev == nil`): baseline `deepest[player]` to the
  drop-in district silently — `Checkpoint` is set to the player's own current
  position, since they haven't crossed a gate yet. No safe window, no toast.
- **District decreases** (`district < prev`): a real checkpoint. Look up the
  gate that leads into that district (`workspace.Gates`, matched by its
  `EntersDistrict` attribute — see [Maze.md](Maze.md#gates)) and set
  `Checkpoint` to a floor-level CFrame at that gate's position, facing the
  centre. Also bump `SafeUntil` (+3s grace) and `CheckpointRing`.
- **District unchanged, or increases** (backtracking, or moving within a
  district): nothing happens. This is what makes ordinary band crossings
  inside a district checkpoint-free — only a *gate* crossing counts.

`deepest` is cleared per-player on `CharacterAdded` (fresh life) and entirely
on `workspace.MazeGeneration` changing (a re-carve invalidates every baseline —
the district boundaries moved).

## Why the gate's CFrame, not the player's position

Respawning at the gate — not wherever inside the new district the player
happened to be caught — is the readable "you fell back to the gate" beat: the
player re-solves the district from its one known entrance, not from some
arbitrary point they'd already explored past.

A gate model (`MazeService.buildGate`) is three parts — two pillars and a
lintel — all carrying the same `EntersDistrict` attribute; `gateForDistrict`
returns the first match, whichever it is. Because the gate parts themselves
sit above floor height (the pillars run up to `GATE_HEIGHT`, the lintel higher
still), `CheckpointService` does **not** use a found gate part's own `.CFrame`
verbatim — that would drop a respawning player mid-air or embedded in the
lintel. Instead `gateStandCFrame` takes the gate's X/Z and rebuilds a
floor-level CFrame at a fixed stand height (`GATE_STAND_Y = 4`, matching
`MazeService`'s own spawn-height convention), facing the centre. Combined with
`HunterService`'s own `+3` stud Y offset on teleport, this is what keeps a
caught player standing on the floor instead of clipped into gate geometry.

## Dependencies

Requires `ReplicatedStorage.Features.Maze.MazeNav` (`nearestCell`, `bandOf`,
`districtOf`) and reads `workspace.Gates` (built by `MazeService.rebuild`, see
[Maze.md](Maze.md)). Waits on `workspace.MazeReady` before its Heartbeat loop
does anything. `CheckpointController.client.luau` is the purely-cosmetic
client half — a "CHECKPOINT" toast keyed off `CheckpointRing` changing; no
game logic there.
