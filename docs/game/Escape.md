# Escape

The round state machine: staging countdown → door opens → descend → vault →
extract → maze rebuild → staging, repeating forever with **no manual button
press**. Free-for-all — there is no per-player win anymore. Extraction only
ends the round for whoever is carrying the vault; everyone banks their Haul
when that happens. See [Maze.md](Maze.md) for the staging room/Vault
geometry this drives, [Salvage.md](Salvage.md) for the Haul/Vault mechanics,
and [Hunter.md](Hunter.md) for the alarm.

Files:

- `src/features/Maze/EscapeService.server.luau` — the round state machine:
  `RoundState`, the staging countdown, the Door, extraction, banking, and the
  rebuild-and-reset loop.
- `src/features/Maze/EscapeCinematicController.client.luau` — the win-camera
  flight, played on `RoundEnded` before the results board.
- `src/features/Maze/UIController.client.luau` — owns the timer HUD; also
  the staging countdown, and mounts the results board on `RoundEnded`.
- `src/features/Maze/WinScreen.ui.luau` — dumb view: the round-results board
  (winner + every player's banked haul). No button; rounds restart automatically.
- `src/features/Maze/PlayerData.luau` — registers the `Ringfall` PlayerData
  template slice (`{ BestTimeSeconds = 0 }`) — no longer written to; see
  below.
- `src/features/Maze/Net.luau` — the `Maze` packet namespace: `RunStarted`
  (still live), `RoundState` and `RoundEnded` (new), `Escaped` and `Restart`
  (kept but unused — see below).

## Round state machine

`workspace.RoundState` is a string attribute: `"Staging"` or `"Active"`.
`EscapeService.Start()` kicks off the loop once; from there it's entirely
self-driving:

1. **Staging.** `runStaging()` sets `RoundState = "Staging"`, closes the
   staging room's `Door` (`CanCollide = true`), then counts down
   `ROUND_COUNTDOWN` (15s), broadcasting `Net.RoundState` every second
   (`{ state, secondsRemaining }`). `UIController` renders this as the
   on-screen `DOORS OPEN IN n` countdown.
2. **Active.** Once the countdown reaches 0, `RoundState = "Active"`, the
   Door opens (`CanCollide = false`), and `Net.RoundState` broadcasts once
   more with `state = "Active"`. **No timer runs here** — per the plan's
   explicit rule, the only timer in a round is the vault alarm
   (`SalvageService`, see [Salvage.md](Salvage.md#the-vault-and-the-alarm)),
   and that only starts once a player actually takes the vault.
3. **Extraction.** `ExtractPad.Touched` (the invisible pad inside the staging
   room by `MazeService`, see [Maze.md](Maze.md)) fires `onExtractTouched`,
   which does nothing unless the toucher has `HasVault == true` — everyone
   else touching the pad, at any point, is a no-op. The first valid touch
   sets a synchronous `extracting` debounce (guards against multiple
   character parts touching the same frame) and calls `endRound(winner)`.
4. **Round end (`endRound`).** In order:
   - `RoundState = "Staging"` immediately (blocks any further extraction).
   - Snapshot every connected player's `Haul` into a list and broadcast
     `Net.RoundEnded { winnerName, hauls }` — the round's "report" (Phase 6
     will convert this into persisted cash; until then this packet *is* the
     bank).
   - `workspace.Drops:ClearAllChildren()` — unrecovered haul/vault drops die
     with the round (see [Salvage.md](Salvage.md#nothing-carries-between-rounds)).
   - `MazeService.rebuild(<fresh random seed>)` — a brand new maze, staging
     room, and Vault.
   - For every connected player: `resetState`, clear the per-run attributes
     (below), unanchor, and teleport back to the (new) `SpawnLocation`.
   - `runStaging()` — the loop repeats — then the `extracting` debounce
     clears.

## Per-run attribute clears

`EscapeService.resetRunAttributes`, run on every player at round end:

`Checkpoint`, `CheckpointRing`, `SafeUntil`, `HasGun`, `Ammo`,
`HasFlashlight`, `StaminaBonus`, **`Haul`, `HasVault`** (new this pass —
nothing from a finished round survives into the next one), plus
`Health = MaxHealth` (a teleport doesn't fire `HealthService`'s
`CharacterAdded` refill, so this has to be explicit).

**`HasCompass` is gone from this list** — the compass is standard equipment
now, not a scavenged attribute; see [Salvage.md](Salvage.md#the-compass-is-standard-equipment).

## Late joiners

A player who joins (or respawns) while `RoundState == "Active"` is anchored
in place the instant their character spawns, rather than being free to walk
out through the (already-open) door mid-round — `onCharacterAdded` checks
`workspace:GetAttribute("RoundState")` and anchors accordingly. They aren't
explicitly unanchored anywhere else: the *next* round's `endRound` loop
unconditionally unanchors and teleports **every** connected player, which
naturally includes them the moment the current round ends. No separate
"waiting room" state is needed.

## Packets (`Net.luau`, namespace `Maze`)

| Packet | Direction | Payload | Purpose |
| ------ | --------- | ------- | ------- |
| `RunStarted` | S→C | none | Still fires the first time a player's character leaves the staging room. Purely a stat now — it drives the client's cosmetic timer display, not a win condition. |
| `RoundState` | S→C (broadcast) | `{ state, secondsRemaining }` | The round's Staging/Active state and the staging countdown. Rendered by `UIController` as the on-screen countdown; a `Staging` packet also clears the previous results board. |
| `RoundEnded` | S→C (broadcast) | `{ winnerName, hauls: { { name, haul } } }` | Fired the instant the vault reaches the extract pad: the winner and every player's haul for the round just ended. |
| `Escaped` | S→C | `{ timeSeconds, bestSeconds, isNewBest }` | **Unused.** Nothing sends or listens for this anymore; kept only so the namespace shape stays stable. |
| `Restart` | C→S | none | **Unused.** The round loop is fully automatic; kept only so the namespace shape stays stable. |

## Client feedback: countdown and the results board

The two moments that matter most in the round are both broadcast, and
`UIController.client.luau` renders them:

- **`RoundState`** → a `DOORS OPEN IN n` countdown centred on screen while
  `state == "Staging"`. Without it a player stands in a sealed room with no idea
  the door is about to open. Receiving a `Staging` packet is also the cue to
  clear the previous round's results board and reset the timer.
- **`RoundEnded`** → `EscapeCinematicController` plays its camera pull-back over
  the maze, then `WinScreen.ui.luau` shows the results board: who got out with
  the vault, and every player's banked haul ranked highest-first with the local
  player's row highlighted.

`WinScreen` was repurposed from the old personal escape screen. It is a passive
scoreboard with **no button** — rounds restart automatically, so it dismisses
itself when the next `Staging` packet arrives. It stays a dumb view: props in,
nothing else (`tools/check-views` enforces this).

## What's now dead

- **`Net.Escaped`** and **`Net.Restart`** have no producer or consumer. The
  per-player win they served was replaced by the server-wide round. They are kept
  in `Net.luau` only so the namespace shape stays stable; delete them in a later
  pass once nothing references them.
- **`workspace.EvacAlert`** was set by the old `onGateTouched` and consumed by
  `HunterService`'s "every hunter sprints for the centre" convergence. Nothing
  sets it now — the vault alarm (`HunterAlert` / `HunterAlertPos`) does that job
  better, since it tracks the carrier rather than a fixed point.
- **`PlayerData.Ringfall.BestTimeSeconds`** still exists in the template but is
  no longer written. `Cash` and `BestHaul` replaced it as the things worth
  keeping.

## Banking

`endRound` is the one moment a per-run number becomes permanent. For **every**
player in the server (not just the carrier who extracted), `bankHaul` adds their
`Haul` to `Ringfall.Cash` and raises `Ringfall.BestHaul` if the round beat it,
through `PlayerDataService.SetValue` so the replica diff and the ProfileStore
autosave stay in step.

The `RoundEnded` packet reports exactly what was banked. A player whose profile
hasn't loaded (or who is mid-leave) still appears on the board, but nothing is
persisted for them — a missing profile isn't worth failing the round over.

Banking runs **before** `resetRunAttributes` wipes `Haul`. Order matters: swap
the two and everyone banks zero.

Cash and unlocks are the only things that cross a round boundary. Everything
else — haul, vault, rented kit, checkpoints — is cleared here. See
[Store.md](Store.md).

## What's not built yet

- The **Map** store item. It needs the maze graph on the client, and
  `MazeNav.cellPos`/`adj` are populated server-side only, so a minimap needs
  graph replication first.

## Studio assets

**None new.** Everything here is code; `ExtractPad` / `Door` / the staging
room are built by `MazeService`, the Vault by `MazeService` with behaviour
from `SalvageService` (see [Maze.md](Maze.md) and [Salvage.md](Salvage.md)).
