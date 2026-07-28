# Flashlight

A camera-following cone that cuts through the maze fog. An invisible emitter part
is re-CFramed to the camera every `RenderStepped`; a `SpotLight` on its front
face points along the look direction.

File: `src/features/Flashlight/FlashlightController.client.luau` (client only —
lighting is a purely local presentation concern).

## Dim baseline, boosted by the pickup

The cone is **always on** but weak — `BASELINE_RANGE = 60`,
`BASELINE_BRIGHTNESS = 1.0` — so you can shuffle around but can't see far.
Scavenging the **flashlight pickup** sets the `HasFlashlight` per-run attribute
(see [Pickups.md](Pickups.md)), which boosts it to `FULL_RANGE = 140`,
`FULL_BRIGHTNESS = 3.5`. `EscapeService` clears the attribute on RUN IT BACK, so
each round drops back to the dim baseline and the flashlight is worth finding.

The controller reacts to the attribute — it never toggles `Enabled`, only the
range/brightness:

```lua
local function applyBeam()
	local hasFlashlight = player:GetAttribute("HasFlashlight") == true
	light.Range = if hasFlashlight then FULL_RANGE else BASELINE_RANGE
	light.Brightness = if hasFlashlight then FULL_BRIGHTNESS else BASELINE_BRIGHTNESS
end
player:GetAttributeChangedSignal("HasFlashlight"):Connect(applyBeam)
applyBeam()
```

This is the same attribute-as-contract pattern the other scavenge consumers use
(`Sprint` reads `StaminaBonus`, `Gun` reads `HasGun`); the Flashlight feature
never imports Pickups.

## Studio assets

The pickup's art is a `Flashlight` Tool under `ServerStorage.PickupModels`
(cloned, script-stripped and de-toolified by `PickupsService` like any other
pickup). The in-world *light itself* is code-built (`SpotLight`), so the Tool is
only the thing you pick up, not the source of the beam.

## Balance note

The dim baseline keeps the start playable while still making the flashlight a
real upgrade (there is exactly **one** flashlight pickup per round). Tuning
dials: `BASELINE_*` / `FULL_*` in the controller for how dark the floor feels vs
how much the pickup matters, and the pickup `count` in `Pickups/Constants.luau`
for how findable it is.

## Constants (in the controller)

`Angle = 55`, warm `Color` (240, 238, 220), `Shadows = true`; beam strength is
`BASELINE_RANGE`/`BASELINE_BRIGHTNESS` (95 / 1.8) upgrading to
`FULL_RANGE`/`FULL_BRIGHTNESS` (190 / 4.0) on pickup — the pickup roughly
doubles both, which is what keeps a detour for it worth making.
