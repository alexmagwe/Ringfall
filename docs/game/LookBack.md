# LookBack

Hold **Q** to glance behind you. The camera orbits around your character to look
back down the path you came from; release and it swings home. You keep running
in the same direction the whole time.

File: `src/features/LookBack/LookBackController.client.luau` (plus a sibling
`Controls.luau` registering the Q hint in the on-screen legend).

## Studio assets

None. Pure camera code.

## How it avoids inverting your movement

This is the part worth understanding before changing anything here.

Roblox movement input is **camera-relative** — the control module reads
`Camera.CFrame` and turns W into "away from the camera". Naively rotating the
camera 180° would therefore make W run you *backwards*, which is exactly the
opposite of what a look-back is for.

The fix is ordering. Two `BindToRenderStep` callbacks straddle the frame:

| Bind | Priority | Does |
| ---- | -------- | ---- |
| `LookBackRestore` | `Input.Value - 1` | Puts back the unflipped CFrame the default camera module produced |
| `LookBackApply` | `Camera.Value + 1` | Re-applies the flip, after the camera module has written its CFrame |

So each frame runs: restore → control module reads a **normal** camera → default
camera module updates → apply the flip → render. The player sees the flipped
camera; the input system never does.

**If you change either priority, re-test movement.** The check is: hold W, toggle
the glance, and compare `Humanoid.MoveDirection` before and after — the dot
product of the two must be `1.0`. Measured at `1.000` when this landed.

## Behaviour details

The camera **orbits the character** rather than spinning in place, so you sweep
past your own shoulder on the way round instead of cutting to a reversed shot.
`SWING_TIME` (0.16s) is the full 0→180 travel, eased with a smoothstep.

The swing puts the camera in *front* of the character, where it can push through
a wall — and in a stealth game that would let you see a hunter through cover. A
raycast from the character to the target camera position pulls it in to
`WALL_MARGIN` (0.5 studs) short of the first hit. The character itself is
excluded from the ray; everything else, including hunters, blocks.

The controller **bails entirely while the `Caught` attribute is set**, because
`HunterController` takes the camera over for the catch cutscene and the two would
fight. It also no-ops with no `HumanoidRootPart`.

Note the camera's look direction rotates by slightly less than 180° in practice
(measured 152.7°) — that's correct, not a bug. Rotating a pitched-down camera
about the world Y axis turns it by `180 - 2 × pitch`.

## Tuning

| Constant | Value | Notes |
| -------- | ----- | ----- |
| `LOOK_KEY` | `Q` | Hold, not toggle |
| `SWING_TIME` | `0.16` | Seconds for the full swing |
| `WALL_MARGIN` | `0.5` | Studs kept clear of geometry |

Keyboard only, matching the rest of the control scheme. Touch and gamepad are a
later pass.
