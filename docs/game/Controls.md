# Controls

The on-screen key legend, bottom-left. Prominent on spawn, then dims to a subtle
reminder after nine seconds.

Files:

- `src/features/Controls/init.luau` — the registry and its auto-discovery loop.
- `src/features/Controls/ControlsController.client.luau` — renders the legend.

## Studio assets

None.

## Adding your key to the legend

Drop a `Controls.luau` in your own feature folder returning
`function(Controls) ... end`:

```lua
return function(Controls)
	Controls.registerControl({ key = "F", label = "Toggle flashlight", order = 50 })
end
```

That's the whole integration. Controls discovers it at load time — **you never
edit anything under `src/features/Controls/`** to add a key, and Controls never
mentions your feature. Same convention as `PlayerData.luau` and `Settings.luau`.

`key` is the chip text and must stay short — **it is the one thing here with a
hard limit.** The chips sit in a fixed 92px column so every label starts on the
same line down the panel; a key wider than that overlaps its own label.
`"MOUSE 1"` is the widest in play and `"W A S D"` is about the practical
maximum.

**`label` has no limit.** The panel sizes itself to its content in both
directions, so a long label widens the whole legend rather than spilling out of
it. It used to be a fixed 280 wide, which left 164px for the label after padding
and the key column — and `"Use medkit (when carrying one)"` is wider than that,
so it drew straight past the panel edge. A `TextLabel` neither wraps nor
truncates by default; it just overflows. A wider fixed number would only have
moved the failure, because this list is built from whatever features register,
and the panel cannot know the longest label in advance.

`order` sorts low → high, ties broken by label.
Current allocations: Sprint uses 10–20, LookBack uses 40.

## Sealing

The registry **seals after discovery**. A `registerControl` call from controller
or service code that runs after load raises an error naming the offending key.

That's deliberate. The legend is built once when the HUD mounts, so a late
registration would silently never appear — a bug you'd only notice by squinting
at the corner of the screen. Erroring at the call site is the better failure.

## History

This started as a hardcoded `CONTROLS` list inside the controller, which meant
Controls named Sprint's keys — a violation of the registration rule in
`CLAUDE.md` ("adding a new feature must not require touching another feature's
files"). It was converted to a registry when LookBack was added, and the existing
Move / Sprint entries moved to `src/features/Sprint/Controls.luau`,
which is the feature that actually owns those keys.
