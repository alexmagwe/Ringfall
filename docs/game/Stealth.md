# Stealth (crouch)

Hold **C** (or Left Ctrl) to crouch: slower, lower camera, and — with a wall
breaking line-of-sight — unseen by the Hunter.

Files:

- `src/features/Sprint/SprintController.client.luau` — owns the input, speed,
  camera drop and the crouch pose. Crouch and sprint are mutually exclusive.
- `src/features/Stealth/StealthNet.luau` — the `Crouch` ByteNet packet
  (client -> server, reliable, one bool).
- `src/features/Stealth/StealthService.server.luau` — mirrors it to the
  `Crouched` player attribute and resets on respawn.

The client sends only on *state change*, not per frame. The `Crouched` attribute
is the shared signal the Hunter reads; see [Hunter.md](Hunter.md).

## Studio assets

**A crouch animation, which you need to create.** Until one exists, crouching
changes your speed and camera but leaves the avatar standing upright.

Set `CROUCH_ANIMATION_ID` in `SprintController.client.luau` to the published
asset id (`rbxassetid://…`) and it starts working — the controller loads it onto
the character's `Animator` at `Action` priority, plays it on crouch with a 0.15s
fade and stops it on release, reloading on respawn.

To author one: open the **Animation Editor** (Avatar tab) on an R15 rig, build a
crouch pose (bend the hips and knees, lean the torso forward slightly), and it
only needs to be a single held keyframe since the controller loops it. Then
**Publish to Roblox** and copy the asset id. It must be owned by the same account
or group that owns the place, or it won't load.

## Why an animation and not a code trick

Three cheaper approaches were tried and all failed on this rig. They're recorded
here so nobody re-treads them:

**Lowering `Humanoid.HipHeight`** sinks the entire rig toward the ground. It does
lower the head — which is correct for stealth, since the Hunter's line-of-sight
ray traces from `HumanoidRootPart` — but the legs are rigid and don't bend, so
the feet end up below the floor. It reads as the player sinking into the ground.

**`Humanoid.BodyHeightScale`** is clamped by the place's avatar settings.
Measured live: setting it to `0.6` shortened the character by about 5%, not 40%.

**Posing joints via `Motor6D.C0`** doesn't apply. The character is on Roblox's
constraint-based rig — 15 `AnimationConstraint`s and 14 `BallSocketConstraint`s,
**zero `Motor6D`s** — so there are no joint `C0`s to offset.

**Offsetting the joint attachments** — the constraint-rig equivalent of the `C0`
trick — *does* work mechanically. Writing
`AnimationConstraint.Attachment0.CFrame = base * CFrame.Angles(x, 0, 0)` on
`LeftHip` / `LeftKnee` / `LeftAnkle` visibly bends the legs, and the offset
survives the Animator writing `Transform` each frame. It was still abandoned, for
two reasons. Hand-tuning angles numerically produced a hunched, half-buried
figure rather than a squat — bending the legs barely shortens them vertically, so
any `HipHeight` drop large enough to read as a crouch still pushes the feet
through the floor. And attachment writes are **client-local**: they don't
replicate, so other players and the server would see you standing upright.

An `AnimationTrack` is the only mechanism that both drives this rig and
replicates, which is why the asset is unavoidable.

## Tuning

| Constant | Value | Notes |
| -------- | ----- | ----- |
| `CROUCH_SPEED` | `8` | vs `WALK_SPEED` 16, `SPRINT_SPEED` 26 |
| `CROUCH_CAMERA_DROP` | `2.2` | studs, lerped on `CROUCH_LERP` |
| `CROUCH_LERP` | `0.25` | per-frame lerp factor (frame-rate dependent, matching the existing style) |
| `CROUCH_ANIMATION_ID` | `""` | empty = no pose |

Crouching regenerates stamina at the same rate as standing still.
