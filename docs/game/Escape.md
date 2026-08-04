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

`workspace.RoundState` is a string attribute: `"Staging"`, `"Active"` or
`"Summary"`.
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
   - `RoundState = "Summary"` immediately (blocks any further extraction).
   - Snapshot every connected player's `Haul`, bank it into permanent `Cash`,
     and broadcast `Net.RoundEnded { winnerName, hauls }`.
   - **Freeze everyone**: `Escaped = true` and anchor each character.
   - **`waitForContinue()` — the round stops here.** See below.
   - `workspace.Drops:ClearAllChildren()` — unrecovered haul/vault drops die
     with the round (see [Salvage.md](Salvage.md#nothing-carries-between-rounds)).
   - `MazeService.rebuild(<fresh random seed>)` — a brand new maze, staging
     room, and Vault.
   - For every connected player: `resetState`, clear the per-run attributes
     (below), unanchor, and teleport back to the (new) `SpawnLocation`.
   - `runStaging()` — the loop repeats — then the `extracting` debounce
     clears.

## Testing the end of a round

Descending three districts, finding the vault and carrying it back out is
several minutes to reach a screen that takes seconds to check. `EscapeService`
exposes a dev entry point for that:

```lua
-- Studio command bar, server-side
require(game.ServerScriptService.Features.Maze.EscapeService).forceEndRound()
```

It ends the round immediately, crediting the given player (or the first one
connected) as the carrier — the same path a real extraction takes, board and
hold included. It shares the `extracting` debounce, so a second call during a
teardown is a no-op rather than two overlapping rebuilds, and it returns whether
it actually started one.

**It is not a packet, deliberately.** Nothing a client sends can reach it, so it
cannot become a way to end rounds from an exploit. A Cmdr command could call it
later; note that a Cmdr command's `Run` must live in a **server-only** module,
because a replicated definition carrying `Run` executes on the *client*
(`Cmdr/Shared/Command.lua`), which for a server-authoritative round end would do
nothing at all.

## The round waits on the summary board

**The round used to restart on its own, and that made the results unreadable.**
`endRound` set `RoundState = "Staging"` and ran straight into `runStaging()`,
whose first `Net.RoundState` broadcast is exactly what `UIController` treats as
"clear last round's board". The board appeared and was wiped roughly a frame
later.

`"Summary"` exists to break that. It is a state where the board is up, the maze
still stands, and nothing has been rebuilt — so no client is ever told to clear
a board it just put up.

**`waitForContinue` holds until every player has sent `Net.Continue`,** which
the board's CONTINUE button sends, **or until `SUMMARY_TIMEOUT` (60s).**

**The timeout is not optional.** Without it, one player who alt-tabs,
disconnects mid-teardown or simply walks away freezes every other player in the
server indefinitely, with no way for them to do anything about it. Waiting for a
real answer is worth a minute; it is not worth a hostage.

Three details that are easy to get wrong:

- **The `Net.Continue` listener is subscribed once, at `Start`** — not per
  round. ByteNet's `listen` has no unsubscribe, so a listener registered inside
  the wait would leak one subscription per round for the life of the server.
- **The roster is snapshotted** when the wait begins. A player who joins while
  the board is up is not waited on: they have no round to read about, and
  including them would restart the wait every time anyone connected. A player
  who *leaves* stops being waited on (`plr.Parent == Players`).
- **Freezing is two separate things**, because they fail differently.
  `Escaped = true` takes players out of `HunterService` targeting and
  `CheckpointService` tracking — without it a hunter keeps hunting through the
  summary and can catch someone reading a scoreboard. Anchoring stops them
  wandering into a maze that is about to be destroyed under them. `resetState`
  clears `Escaped` and `teleportToStaging` unanchors, so both undo themselves on
  the way out.

### Joining mid-round must not freeze you

`onCharacterAdded` anchors a spawning character **only while `RoundState ==
"Summary"`**. It used to anchor during `"Active"` as well, and that shipped as a
softlock: a player joining a live round was frozen mid-spawn-drop, floating a
few studs above the staging floor, unable to move or do anything.

The reasoning behind it was that a late joiner should wait the round out rather
than drop into a live maze, and that `endRound`'s teleport-everyone step would
free them. Both true — and both irrelevant, because **nothing ends a round on
its own.** There is no run timer; the only exit from `"Active"` is somebody
carrying the vault to the pad. The freeze therefore lasted until a stranger
completed a full extraction, and on a server where nobody managed it, forever.
The worse the players, the longer the punishment for joining.

A joiner is safe unfrozen. They spawn in the staging room, which is a sanctuary
hunters cannot enter, and the door is already open — so they can browse the
shelf, wait, or walk into the maze and join late. Starting behind is a fair
cost; being a statue is not.

`"Summary"` still anchors and that one is safe, because it is **bounded**: the
hold ends on `SUMMARY_TIMEOUT` at the latest, and it ends by teleporting and
unanchoring every player in the server. Anchoring is only ever safe where
something guarantees the release.

Reproduced and fixed with a two-client playtest — join during `"Active"` and
compare the joiner against a player who was already there:

| | before | after |
| --- | --- | --- |
| established player | `anchored=false`, y=2.9 | `anchored=false`, y=2.9 |
| mid-round joiner | `anchored=true`, y=7.5 | `anchored=false`, y=2.9 |

`onCharacterAdded` anchors during `"Summary"` — a
player who dies and respawns mid-board would otherwise be the only one free to
move.

## What the board shows

`WinScreen.ui.luau` is built around **one hero number: your take**. A scoreboard
answers "who won"; the board is held open for "what did I get", so that is the
biggest thing on it and the only thing in colour.

The first version had no hierarchy at all — eight lines between 18 and 28px, all
centred, in three near-identical greys. It read as a paragraph, with nothing to
look at first. Three rules fixed it, and they are worth keeping:

- **One size per role**, stepping hard: 64 hero / 34 title / 22 row / 16 caption
  / 13 heading. Sizes that differ by 4px do not establish an order.
- **One coloured thing.** The take is green; everything else is a grey ramp from
  bright rows down to dim headings.
- **Say it once.** The ranking is hidden when there is only one player, where it
  repeated the hero number two lines below it under a heading saying so. Store's
  section lost its "You can now unlock:" line, since the `THE SHELF` heading
  above it already said that — a heading followed by a heading.

`MazeRoot` sets **`DisplayOrder = 90`**. `ZIndex` only orders within a single
`ScreenGui`, so without it the shelf window drew straight through the board
whenever a round ended with the shelf open: the board dimmed the world, and the
shelf sat on top of the dim anyway. 90 keeps it under the catch cutscene
(`HunterController`, 100), which is the one thing that should cover it.

**Everything below that is contributed by other features**, through
`Maze/Summary.luau`. A feature declares a section from a sibling
`RoundSummary.luau` returning `function(Summary) … end`, exactly like
`Store.luau` / `Settings.luau` / `PlayerData.luau` / `Controls.luau`. Maze owns
the board; it owns none of the content beyond its own run numbers.

A section is `{ id, title, order?, lines(profile) -> { string } }`. `lines` runs
**client-side** and is handed the whole `Ringfall` profile slice, so a section
costs no packet and no server work, and can report on anything the profile
holds. Returning an empty table hides the section — that is how a feature stays
quiet on a round it has nothing to say about.

`src/features/Store/RoundSummary.luau` is the first one: it lists what the
shelf will now sell you that it would not have before, or how far off the next
unlock is. **It unlocks nothing** — unlocks are still bought by hand at the
shelf — so the board never claims a purchase the player did not make.

## Per-run attribute clears

`EscapeService.resetRunAttributes`, run on every player at round end:

`Checkpoint`, `CheckpointRing`, `SafeUntil`, `HasGun`, `Ammo`,
`StaminaBonus`, **`Haul`, `HasVault`** (new this pass —
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
- **`RoundState` (same condition)** → the **mission briefing**, stacked directly
  above that countdown: `OBJECTIVE` / `TAKE THE VAULT AT THE CENTRE` / *"…then
  carry it back to this room. Nothing counts until you're home."* Nothing else in
  the game ever states the objective — the compass gives a direction, not a goal —
  and the second half is the part nobody guesses: taking the vault isn't the win,
  carrying it home is. It rides the staging countdown because that is the one
  window where the player has nothing to do and cannot be killed, so the briefing
  costs them no play time and never has to interrupt a run to be read.
- **`RoundEnded`** → `EscapeCinematicController` plays its camera pull-back over
  the maze, then `WinScreen.ui.luau` shows the results board: who got out with
  the vault, and every player's banked haul ranked highest-first with the local
  player's row highlighted.

`WinScreen` was repurposed from the old personal escape screen. It now carries a
**CONTINUE** button: the round is held in `"Summary"` until every player has sent
`Net.Continue` (see `waitForContinue` above), so the board no longer dismisses
itself on a timer. Once *this* player has pressed it, `onContinue` is passed as
`nil` and the button becomes a "waiting for the others" line — a pressed button
never reads as an unresponsive one. It stays a dumb view: props in, nothing else
(`tools/check-views` enforces this).

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
