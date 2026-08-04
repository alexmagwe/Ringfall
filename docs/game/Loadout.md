# Loadout

The **carried-kit strip**: one bottom-right column that answers "what am I
holding?" — ammo, medkit charges, EMP charges, the skateboard, the haul.

## Why it exists

Every feature that had something to tell you drew its own label and picked its
own corner. By the time the eighth arrived there were **eight bottom-anchored
labels chosen independently**, and four collisions:

| Collision | Effect |
| --------- | ------ |
| Medkit `(0,16,1,-16)` under the Controls legend `(0,18,1,-18)` | **The medkit line was drawn inside the legend's panel.** Carrying a medkit was unknowable. |
| EMP readout `-52` vs Skateboard notice `-56` | Half-overlapped |
| Pickup toast `-70` vs EMP result `-90` | Half-overlapped |
| Gun ammo `(1,-20)` vs Salvage haul `(1,-12)` | Both anchored to the same corner; armed *and* carrying read one line through the other |

The medkit one is the instructive failure. It wasn't a bad offset when it was
written — it went bad later, because **the legend sizes to its content and grows
every time any feature registers a key**. Adding the skateboard's `R` and the
EMP's `F` pushed it over a line that had been fine for months. Nothing warns you;
a label just quietly stops being readable.

**No offset is the right offset when every feature is guessing.** So this is the
same trade `Controls` already makes for keys: features declare *what* to say, one
owner decides *where*, and a layout stacks them so two rows cannot occupy the
same pixels however many features are installed.

Files:

- `src/features/Loadout/init.luau` — the registry + auto-discovery.
- `src/features/Loadout/LoadoutController.client.luau` — draws the column.

## Registering a row

A feature drops a sibling `Loadout.luau` returning `function(Loadout) … end` —
the same convention as `Store.luau`, `Settings.luau`, `Controls.luau`,
`Scatter.luau` and `RoundSummary.luau`. Adding a row is **zero edits to this
folder**.

```lua
-- src/features/EMP/Loadout.luau
return function(Loadout)
    Loadout.registerSlot({
        id = "emp.charges",
        order = 30,
        watch = { "EmpCharges" },      -- re-read when these attributes change
        color = Color3.fromRGB(120, 210, 255),
        flashOn = "EmpCharges",        -- flash the row when this number rises
        text = function(player)
            local n = player:GetAttribute("EmpCharges") or 0
            return if n > 0 then string.format("EMP x%d   [F]", n) else nil
        end,
    })
end
```

| Field | Meaning |
| ----- | ------- |
| `id` | Unique; also the row instance's name. |
| `order` | Low to high, top of the strip down. Ties break by `id`, so the order is stable across sessions rather than following hash iteration. |
| `watch` | Player attributes that re-read the slot. A slot watching nothing never updates. |
| `text` | Returns the line, or **`nil` to hide the row entirely**. |
| `color` | Row tint. Defaults to near-white. |
| `flashOn` | Attribute whose numeric *rise* flashes the row. Shared behaviour, so it lives in the strip rather than being re-tweened per feature. |

**`nil` hiding is the common case, not an edge case.** `AMMO 0` and `HAUL 0` are
readouts of nothing — they sat in the corner for the whole first leg of every run
saying only that it hadn't started paying yet. Rows are hidden rather than
blanked and the `UIListLayout` closes the gap, so the strip is always exactly as
tall as the number of things you're actually carrying.

The flash only fires on a **rise against a value already seen**. Firing on the
first read would flash every row on spawn.

## Current rows

| Order | Slot | Feature | Shown when |
| ----- | ---- | ------- | ---------- |
| 10 | `gun.ammo` | Gun | armed |
| 20 | `health.medkit` | Health | charges > 0 |
| 30 | `emp.charges` | EMP | charges > 0 |
| 40 | `skateboard.ride` | Skateboard | holding a board (text changes when riding) |
| 50 | `salvage.haul` | Salvage | haul > 0 |

## Why bottom-right

Bottom-**left** is the controls legend, which grows with every registered key —
anything parked near it is one new keybind away from being covered, which is
exactly how the medkit line died. Bottom-**centre** is the transient toast band
(pickup toast, EMP result, skateboard notice). The right corner is the only one
whose height this strip alone decides.

The toasts that remain in the centre band are spaced a full row apart (−120,
−164, −206) rather than the few pixels they'd drifted to. They're momentary and
rarely simultaneous, so they don't need a registry — but they did need to stop
half-overlapping each other.

## Dependencies

Reads only player attributes, all of them owned by the feature that registered
the slot. Nothing depends on Loadout. Deleting the folder removes the strip and
leaves every `Loadout.luau` inert — features keep working, they just stop having
anywhere to say so.
