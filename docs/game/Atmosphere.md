# Atmosphere

The maze's mood: one client-side pass over `Lighting` at startup. Currently
**daylight** — a high sun with low fill light, so the maze is readable at range
but every surface still has a lit side and a shadowed side.

Files:

- `src/features/Atmosphere/AtmosphereController.client.luau` — the whole
  feature. Sets `Lighting`, one `Atmosphere`, and neutralises Roblox's default
  `DepthOfField`.

## Studio assets

**None.** Everything is set from code at startup.

One property **cannot** be set from a script and is the user's to change:
`Lighting.Technology`. Set it to **Future** in Studio. Voxel lighting has no
real shadow detail, and no amount of tuning here compensates for it.

## Contrast, not brightness

This is the rule the whole file is built around, and it has now been got wrong
in both directions.

**Too little light (the original).** `ClockTime = 0` with `Ambient` doing all
the work. The maze is open-topped, so the sky *is* its light source — at
midnight there is no sun or moon at all. Raising `Ambient` never fixed it,
because ambient is not a light source, it is a floor under the darkness.

**Too much fill (the daylight rewrite).** `Ambient` at `(120, 128, 140)` and
`OutdoorAmbient` at `(140, 150, 165)`. Fill light lands on every face of every
part equally, so nothing had a lit side and a shadowed side and every surface
read as flat plastic. This is what made the maze look cheap — not the geometry,
and not the materials.

The current values keep the sun and cut the fill:

| Property | Value | Why |
| -------- | ----- | --- |
| `ClockTime` | 14 | Mid-afternoon. High enough to reach the floor between 40-stud walls, off vertical enough that walls cast readable shadows |
| `Brightness` | 3.5 | The sun. Raise **this** if the maze is too dark |
| `Ambient` | `(40, 44, 52)` | Fill. Low on purpose |
| `OutdoorAmbient` | `(95, 105, 122)` | Sky fill on anything open to the sky, which is most of the maze |
| `EnvironmentDiffuseScale` | 0.6 | Sky-derived diffuse is fill light by another name; at 1 it undid the cut above |

**Do not fix darkness by raising `Ambient` or `OutdoorAmbient`.** That is the
second mistake above. Raise `Brightness`, or move `ClockTime`, and leave the
fill low.

## Fog

`FogStart = 45`, `FogEnd = 240` — about five bands of sight, where a band is 42
studs. Walls block most sightlines anyway, so this mostly opens up long
corridors and the floor.

**Fog and `Atmosphere` colours must track the time of day.** Dark-blue fog under
a daylight sky reads as a rendering fault, not as distance. `FogColor` is a pale
haze at `(168, 178, 190)` for that reason.

`Atmosphere.Density` (0.18) stacks **on top of** the distance fog. At the old
0.42 with `Haze` 2.4, the two together were most of the murk.

Roblox ships a default `DepthOfField` in `Lighting` whose far-blur compounds
with the fog into yet more murk. It is neutralised rather than destroyed, so a
deliberate depth-of-field look can be re-tuned from Studio later.

## Consequences elsewhere

- **The Flashlight is close to worthless in daylight**, and the maze no longer
  contrasts with the lit staging room. If the game moves back toward horror,
  change `ClockTime` (try 5.1 for blue hour) and darken `FogColor` and
  `Atmosphere.Color` to match — not `Ambient` on its own.
- **District dressing depends on this lighting.** The overgrown outer district
  (see [Maze.md](Maze.md#district-dressing)) is built around surfaces having a
  lit and a shadowed face. Flatten the light again and the vines, rubble and
  tufts stop reading as separate objects.
