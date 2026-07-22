# PLAYTEST-notes — Ringfall first playable slice

Studio MCP is connected. The slice was verified in a live solo playtest (Opus,
2026-07-20). Server generation, client UI, the stair fix, and the full escape
loop are confirmed working. Four subjective feel questions still want a human.

## Verified in Studio (automated / scripted)

- **Rojo + splitter sync**: all 7 Maze scripts land in the right realms
  (`ServerScriptService/ReplicatedStorage/StarterPlayerScripts.Features.Maze`).
- **Generation**: `[Maze] generated seed=1001 spawn=(4,4) exit=(1,4) dist=11`,
  no asserts, zero server errors. Deterministic (same seed → same layout).
- **Tile tally at seed 1001**: `Corner=19 Corridor=18 Cross=2 DeadEnd=5
  StairCourt=9 TJunction=11` — **all 6 tiles present** (Cross=2, so the earlier
  "Cross may never appear" risk is resolved for this seed). 64 tiles, 381 parts
  total — very light, StreamingEnabled on.
- **StairCourt climb**: after the switchback rebuild (see below), a character
  climbs floor → flight A (y0.9→33) → flight B (y30→57) → rooftop, mounting
  from flat ground. From the rooftop (y63) you can see out over the 60-stud
  walls into the maze.
- **Escape loop end-to-end**: leave the 25-stud spawn zone → timer starts
  (RunStarted) → touch ExitGate → **ESCAPED** WinScreen with correct time
  (0:02.4) → Restart teleports back to spawn and unfreezes. Zero errors.

## Bugs found and fixed this session

1. **UIController required `WinScreen` as a sibling** — but `.ui.luau` routes
   to ReplicatedStorage, so the client threw on load. Fixed to
   `require(ReplicatedStorage.Features.Maze.WinScreen)`.
2. **EscapeService used `.send(data, player)` for server→client** — ByteNet's
   `.send` is client-only (nil on server → "attempt to call a nil value").
   Fixed to `.sendTo(data, player)` for both RunStarted and Escaped. (Boil's
   other features never send server→client via ByteNet, so this was untested.)
3. **ExitGate floated at y20–40** — the wall slot centers geometry at mid-wall
   height, so a walking player passed under it and never fired `.Touched`.
   MazeService now drops the gate to sit on the floor (base y=0, 30 tall).
4. **StairCourt stairs were unclimbable** — the original 11 solid steps rose
   ~5.4 studs each (humanoids auto-step only ~2.5). Rebuilt as a **switchback**:
   two ~34° invisible collidable ramps with a mid-landing, non-colliding visible
   treads on top, landing on a rooftop platform at wall height. Verified
   walkable from flat ground (a single straight ramp to y60 in a 50-stud tile
   is too steep to *mount*, even though it's climbable once you're on it).

## Still NEEDS HUMAN PLAYTEST (subjective feel — the fun gate)

1. Do the 60-stud canyons feel imposing at street level (no bad camera clip,
   sightlines blocked)?
2. From a StairCourt rooftop, does seeing the neon ExitGate / other rooftops
   create an "aha, that way" moment?
3. First-attempt time-to-escape in the 5–12 min band? (If <3 min: raise GRID to
   10. If >15: raise EXTRA_LOOPS for shortcuts, or drop GRID to 7.)
4. Any spot where you were hard-*stuck* (not lost)? The switchback stairs are
   the thing to watch — confirm they read as climbable and a player naturally
   turns at the mid-landing.

## Notes / cleanup backlog (not blocking)

- Boil's demo features (Coin Clicker, sidebar, HealthSystem with a failing
  animation asset) still ship in `src/features/` and clutter the screen /
  spam one client warning. Delete the unwanted demo feature folders when we
  start dressing the real game.
- Verifying UI clicks via `simulate_mouse_input` needs screenshot-matched
  coordinates (the viewport was retina-scaled 2260px); the Restart button was
  confirmed via firing its packet, which is exactly what the button does.
