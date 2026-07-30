# Music

Phase-driven scoring for the round. Client-side — each player drives their own
playback through `SoundService`, so no server replication is involved.

Ringfall is scored as a **heist thriller, not horror**: the maze is sunlit and
the enemies are giant robot ducks, so dread scoring fights the art. Play the
tension straight and let the absurdity land on its own.

## Files

- `Constants.luau` — the cue table, the sting timings, and `FADE_TIME`.
- `MusicController.client.luau` — auto-loaded; the state machine below.

## Two different things

The distinction is the whole design of this feature, and it's easy to collapse
them by accident:

| | Driven by | Shape |
| --- | --- | --- |
| **Beds** (`STAGING`, `DESCENT`) | `workspace.RoundState` | Looping. Exactly one plays at a time; swapping one destroys the other. |
| **Stings** (`ALARM`, `ROUND_END_STING`) | an event | One-shot, layered *over* whichever bed is running. The bed keeps playing underneath. |

`currentCue()` therefore only ever returns `STAGING` or `DESCENT`. The alarm is
deliberately not a cue.

### Why the alarm is a sting

`ALARM` used to be a third bed, selected whenever `AlarmActive` was set or the
local player held the vault. Two problems:

- Taking the vault **permanently replaced** the descent bed for the entire
  return trip, so the biggest turn in the round read as a new *phase* rather
  than as an event.
- It buried `DESCENT`, which is sparse on purpose — the hunter drone is the
  player's only proximity cue, and a dense mix deafens them to the one signal
  that keeps hunters threatening.

Now `AlarmActive` fires a siren for `ALARM_STING_SECONDS` (3) over the top and
the bed carries on uninterrupted. The clip is 33s, so it is **cut short, not
played out** — `ALARM_STING_FADE` (0.5s) fades the tail, because a hard cut on a
sustained siren clicks. Swap in a genuinely short siren and the wiring is
unchanged.

The sting fires for **every** player, not just the carrier: the vault going is a
maze-wide event — every compass swings, every hunter turns. It's guarded on the
attribute's value because the changed-signal also fires when `MazeService`
clears it on rebuild.

## Attributes read

This feature imports nothing from Maze, Salvage or Hunter — it reads the same
attributes gameplay already publishes:

| Attribute | Set by | Drives |
| --------- | ------ | ------ |
| `workspace.RoundState` | `EscapeService` | Which bed loops |
| `workspace.AlarmActive` | `SalvageService` | The siren sting |

`Active -> Staging` also fires `ROUND_END_STING` over the results board, before
the staging loop comes back up.

## Setting a track

Paste an audio asset id into the matching entry in `Constants.luau`. **Roblox
audio privacy**: you can only play audio owned by this experience's creator (or
group), or licensed audio from the Creator Store. A random library id silently
fails to load — the same trap as the crouch animation.

Any cue left as `""` is skipped, so the game runs fine part-scored. An unscored
*bed* stops the music rather than leaving the previous phase's loop running
underneath — wrong music is worse than silence.

## Shared audio slot

Beds go through `Boil.audio.playLoop(id, volume, key)`, which shares one
background-music slot with `playMusic`, so only one loop can ever play. Stings
go through `Boil.audio.playSoundId(id, volume)`, which returns the `Sound` so a
caller can fade or cut it short.

## No Studio asset required

Just asset ids — no tagged parts or pre-built instances.
