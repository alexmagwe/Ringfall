# Music

Loops a single ambient background track for the local player from the moment
they join. Client-side — each player drives their own loop via `SoundService`,
so no server replication is involved.

## Files
- `Constants.luau` — `TRACK_ID` (the one place to set the track) and `VOLUME`.
- `MusicController.client.luau` — auto-loaded; on `Start()` plays the track via
  the shared audio system, or warns and skips if `TRACK_ID` is still the
  `rbxassetid://0` placeholder.

## Setting the track
Paste an audio asset id into `Constants.TRACK_ID`. The asset must be one this
experience is allowed to play: **owned by the game's creator, or Roblox-provided
/ permission-granted**. Post-2022 audio privacy blocks arbitrary library ids
from playing in other experiences — audio inserted from the Studio Toolbox
into this place is the easy path.

## Shared audio slot
Playback goes through `Shared.audio.playLoop(id, volume)`, which shares one
background-music slot with `playMusic`. That means a future fog-rise controller
can call `Boil.audio.playLoop(tenseTrackId)` to cross-swap to a tenser loop when the
fog cycle escalates (GDD §4.2 / §11.2) — only one music track ever plays.

## No Studio asset required
Music needs no tagged parts or pre-built instances — just the asset id.
