# Escape

The round state machine: tracks each player's run timer, fires the round's
network events, freezes/resets characters at the exit, and drives the
server-wide restart. See [Maze.md](Maze.md) for the maze itself and its
rebuild contract, and [Hunter.md](Hunter.md) for the evac-alert convergence.

Files:

- `src/features/Maze/EscapeService.server.luau` — round state machine, timer,
  win condition, restart, personal-best persistence.
- `src/features/Maze/EscapeCinematicController.client.luau` — the win-camera
  flight. Exposes `play()` / `stop()` intent actions only; no networking.
- `src/features/Maze/UIController.client.luau` — owns the timer HUD, mounts
  `WinScreen.ui.luau` on win, drives the cinematic.
- `src/features/Maze/WinScreen.ui.luau` — dumb view: time, personal best, the
  NEW BEST stamp, and the restart button.
- `src/features/Maze/PlayerData.luau` — registers the `Ringfall` PlayerData
  template slice (`{ BestTimeSeconds = 0 }`).
- `src/features/Maze/Net.luau` — the `Maze` packet namespace.

## Round state machine

Per player: `startedAt: number?`, `escaped: boolean` (module-local `state`
table in `EscapeService`, keyed by `Player`). Reset on join and on every
`CharacterAdded` (a new life starts the round fresh). The `Escaped` attribute
mirrors `escaped` and is the cross-feature signal — Hunter ignores escaped
players, LookBack stops fighting the cinematic for the camera.

1. **Idle** — player hasn't left the spawn zone (`EscapeZone`, `ZONE_RADIUS`
   studs around `SpawnLocation`) since spawning.
2. **Running** — `Heartbeat` detects the character left the zone; `startedAt`
   is set and `Net.RunStarted` fires (client starts its timer display).
3. **Escaped** — `ExitGate.Touched` fires `onGateTouched`: debounced
   synchronously (before any yield) against re-entrant `Touched` firings from
   multiple character parts overlapping in one frame. Sets `Escaped = true`,
   sets `workspace.EvacAlert` (see [Hunter.md](Hunter.md)), resolves the
   personal best, sends `Net.Escaped`, and anchors the character.
4. **Restart** — `Net.Restart.listen` rebuilds the maze with a fresh seed and
   resets every connected player (not just the requester) back to Idle.

## Packets (`Net.luau`, namespace `Maze`)

| Packet | Direction | Payload | Purpose |
| ------ | --------- | ------- | ------- |
| `RunStarted` | S→C | none | Start the client-side timer display. |
| `Escaped` | S→C | `{ timeSeconds, bestSeconds, isNewBest }` | Authoritative elapsed time (server clock) + personal-best result. `bestSeconds = 0` means no previous best. |
| `Restart` | C→S | none | "RUN IT BACK". Triggers the server-wide new round. |

## Restart is server-wide, not per-player

`Net.Restart.listen` calls `MazeService.rebuild` with a fresh random seed, then
loops **every** connected player: `resetState`, clears `Checkpoint` /
`CheckpointRing` / `SafeUntil`, unanchors, and teleports to the (new) spawn +
`Vector3.new(0, 3, 0)`. Per-player mazes are explicitly out of scope — the maze
is one shared world, and a restart is everyone's new round together.

**Because it is server-wide, the handler first checks the sender actually
escaped:**

```lua
if not getState(player).escaped then
	return
end
```

`Restart` is a client-sent packet, and it now re-carves the world for *everyone*.
Without this guard any client could spam it and rebuild the maze under other
players mid-run — a griefing vector that did not exist when restart only
teleported the sender. If you add another world-mutating packet, guard it the
same way: never trust the client to have earned the call.

**Clearing `Checkpoint` is required, not optional.** It stores a raw
world-space `CFrame`; after a re-carve that exact point may now be inside a
wall, and `HunterService.catchPlayer` teleports caught players straight to
whatever `Checkpoint` holds.

## Personal best

`PlayerData.luau` registers `Ringfall = { BestTimeSeconds = 0 }` (`0` = no best
yet — ProfileStore templates don't retain `nil` keys). In `onGateTouched`:

```lua
local data = PlayerDataService.GetData(player)
local previous = if data and data.Ringfall then data.Ringfall.BestTimeSeconds else 0
local isNewBest = previous <= 0 or elapsed < previous
if isNewBest then
    PlayerDataService.SetValue(player, { "Ringfall", "BestTimeSeconds" }, elapsed)
end
```

The `Escaped` packet is sent **after** the `SetValue` call, so the payload and
the replica always agree. A nil profile (still loading) is treated as no best,
never as an error.

## The cinematic

On `Net.Escaped`, `UIController` `task.spawn`s `EscapeCinematicController.play()`
and only calls `setWinState` (which mounts `WinScreen`) once it resolves — so
the panel appears over the settled shot, not mid-flight.

`play()`:

1. Bails immediately if the character is gone.
2. Fades every `Hunter` model's `HunterDrone` sound to 0 volume (0.3s tween) —
   the shot lands in silence.
3. Sets `camera.CameraType = Scriptable` (the character is already anchored
   server-side — the cinematic never anchors it again client-side).
4. Tweens a `NumberValue` 0→1 over `FLIGHT_TIME` (1.8s, `Quart`/`Out`); each
   step sets `camera.CFrame = CFrame.lookAt(startPos:Lerp(endPos, t), charPos)`
   where `endPos = charPos + RISE` (`Vector3.new(0, 220, 260)`, captured once
   at the start) and `charPos` is the character's position at flight start.
   Re-checks `player.Character` every step and aborts to `stop()` if it
   vanished mid-flight (death/leave).
5. Holds `HOLD_TIME` (0.5s) after the tween settles, then returns.

`stop()` restores `camera.CameraType = Custom` and drone volumes to `0.8`.
`UIController.onRestart` calls `stop()` **before** sending `Net.Restart`, so the
camera is back on the character before the round-restart teleport lands.

`LookBackController` guards its render-step against `Caught` **and**
`Escaped` attributes — without the `Escaped` half of that guard it would fight
the cinematic for `camera.CFrame` every frame.

## Studio assets

**None new.** Everything here is code; `ExitGate` / `EscapeZone` are built by
`MazeService` / `EscapeService` respectively (see [Maze.md](Maze.md)).
