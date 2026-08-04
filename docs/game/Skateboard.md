# Skateboard

A board you find in the maze and ride for **+50% movement speed** — but only
where the ground is hard. The outer district is grass, so the board is dead
weight there.

That constraint is the whole feature. Without it a skateboard is a flat upgrade
with no decision in it: you find it, you're faster, forever. With it, the board
has a *shape* — it does nothing on the leg where you find it, starts paying at
the middle gate, and pays again on the way back out with the vault right up to
the point where the turf begins. You spend the outer district on foot in both
directions whether or not you have one.

Files:

- `src/features/Skateboard/Constants.luau` — the multiplier, the blocked
  district list, the attribute names, the art name, the poll cadence.
- `src/features/Skateboard/Scatter.luau` — registers the pickup into the
  Pickups feature. Pickups never names Skateboard; see
  [Pickups.md](Pickups.md#registered-spawns).
- `src/features/Skateboard/SkateboardService.server.luau` — the authority.
  Owns the ride state, the district check, the welded art, the teardown.
- `src/features/Skateboard/SkateboardController.client.luau` — the `R` key and
  the HUD readout. Sends one request; draws three attributes.
- `src/features/Skateboard/Net.luau` — one packet, `ToggleRide` (C→S, request).
- `src/features/Skateboard/Controls.luau` — the key-legend entry.

## Studio assets

**Optional.** A model named `Skateboard` under
`ServerStorage.PickupModels` is used for both the world pickup and the board
welded under your feet.

> **`ServerStorage.PickupModels` IS ROJO-MANAGED.** `default.project.json` maps
> it to `assets/PickupModels.rbxm`, so Rojo reconciles that folder against the
> file on every sync and **anything you drag in from Studio is pruned**. Cmd+S
> saves the place, but the place is not the authority for this folder — the
> `.rbxm` is. Art added in Studio survived until the next sync and then vanished,
> twice, before this was spotted.
>
> To make art here permanent: right-click `PickupModels` → **Save to File…** →
> overwrite `assets/PickupModels.rbxm`, and commit it.
>
> `ServerStorage.HunterModels` is **not** in the project file, which is why
> hunter art dragged into Studio does stick. `PickupModels` is the exception,
> and it is the one that looks like a bug. Without one, the feature builds a board in code (dark
deck, amber grip tape, four wheels) — the same "works before any art exists"
rule the rest of Pickups follows.

A `Tool` is accepted and **unwrapped into a plain Model**, for the same
load-bearing reason as every other pickup: a `Tool` anywhere in Workspace
auto-equips off a Handle touch, and this one gets welded to the player's feet.
See the comment in `PickupsService.buildPickup`.

**Your art is rescaled, so its authored size doesn't matter.** The model's
longest horizontal axis is scaled to `Constants.DECK_LENGTH`, proportions kept.
Without this the board's scale is whatever someone's export settings happened to
be — the art in this place arrives 13.33 studs long, nearly three times the
rider.

**It is rescaled in two places, from one number.** The board is drawn twice —
lying in the maze and welded under a rider — and those are different code paths.
The ridden one is `SkateboardService.boardModel`; the world pickup goes through
Pickups, which learns the target from the `scaleTo` field on the registered
spawn (see [Pickups.md](Pickups.md#registered-spawns)). Both read
`DECK_LENGTH`, because a pickup and the thing you pick up must not disagree
about how big a skateboard is. They did, for one commit: only the ridden board
was normalised, so the maze held a 13-stud board and your feet held a 4-stud one.

> **`Model:ScaleTo` is ABSOLUTE, not a multiplier.** It sets the scale against
> the size the model was *authored* at, so it must be composed with the scale the
> model already carries. This board's `GetScale()` is 2.67, so
> `ScaleTo(target / longest)` asked for "30% of authored" and produced 1.5 studs
> instead of the 4 requested. The relative form is
> `ScaleTo(model:GetScale() * (target / longest))`.

**Seats are neutralised, not destroyed.** A `Seat` or `VehicleSeat` welds
whoever touches it and takes over their movement — the same class of bug as the
Tool auto-equip that made picking up a health kit drop the player through the
floor. Free-model vehicles are built around one, and this board *is* a Part and
a VehicleSeat. `Disabled = true` rather than `:Destroy()`, because the seat here
is half the deck's geometry. Applied in both clone paths.

`DECK_LENGTH` is the one number that decides how big the board looks, and it is
**purely eye-tuned over four passes in both directions** — don't "correct" it
back toward realism. 5 (the first pass) is as long as the rider is tall and
reads as a surfboard. Real-world proportions say a bit under half the rider's
height — 3.2 — and that looked like a toy. 4 was still small underfoot.
**4.8** is where it sits right: about 0.8 of a character's height. Blocky avatars
have wide feet, a wide stance and a low camera, and need more board than a
person does.

## Where it rolls

`Constants.BLOCKED_DISTRICTS` is keyed by MazeNav district index:

| District | Dressing | Board |
| -------- | -------- | ----- |
| 0 — hub | bare | rolls |
| 1 — inner | bare | rolls |
| 2 — middle | `Dressing.FLOODED` (standing water) | rolls |
| 3 — outer | `Dressing.OVERGROWN` (**grass**) | blocked |
| outside the maze | staging room + corridor | rolls |

The grass is the outer district because `MazeService.DISTRICT_LOOKS` maps
district 3 to `Dressing.OVERGROWN`, whose `groundMaterial` is `Grass`.
**Nothing enforces that pair but a comment.** If the dressing ever moves to a
different district, `BLOCKED_DISTRICTS` has to move with it — the mapping lives
in MazeService and this feature only reads `MazeNav.districtOf`.

Anything outside `MazeNav.perimeterR` has no cell and so no district, and is
treated as **rideable**. The run-up from the door out to the perimeter is flat
plate; refusing to roll there would make the feature feel broken at the exact
moment a player is most likely to try it.

## Riding

Server-authoritative, deliberately. Riding *is* a speed multiplier, which is
precisely what a movement exploit would want to claim. The client may only ask:

1. `R` → `Net.ToggleRide` (no payload — the server owns the state, so it knows
   which way the toggle goes).
2. `SkateboardService` re-checks, in order: already riding (→ dismount), holds a
   board, not caught / not escaped, ground allows.
3. On success it sets `RidingSkateboard = true`, publishes
   `SpeedMultiplier = 1.5`, and welds the art under the character.

The client re-derives none of that. `SkateboardController` reads
`HasSkateboard`, `RidingSkateboard` and `SkateboardNotice` and draws them.

### The speed itself belongs to Sprint

`SprintController` writes `Humanoid.WalkSpeed` **every heartbeat**, so anything
that set the speed directly would be overwritten a frame later. Sprint therefore
owns a generic hook: it multiplies whichever speed is in force (walk *or*
sprint) by the `SpeedMultiplier` player attribute.

That attribute is **anonymous by design** — Sprint never learns which feature
set it, exactly like `StaminaBonus`. Any future feature that wants the player
faster or slower publishes it and lets the movement owner apply it.

| | on foot | riding |
| --- | --- | --- |
| walk | 17.6 | 26.4 |
| sprint | 28.6 | 42.9 |

### The rider stops running

Roblox's default `Animate` script drives walk/run off `Humanoid.MoveDirection`,
and riding doesn't change that — so a rider **sprinted on the spot** on top of a
board that was carrying them, and the board read as scenery stuck to their feet
rather than as the thing moving them.

`SkateboardController.setRidePose` disables `Animate` and stops every playing
track while riding, which leaves the rig in its rest pose — exactly "standing on
a board". Toggling `Disabled` back to `false` re-runs the script from the top and
re-registers its idle; that restart is what makes this reversible rather than a
one-way trip. **Order matters:** stop the tracks *after* disabling `Animate`, or
it starts a fresh walk cycle on the very next frame and undoes it.

Done **client-side**, on the local character. Animation replicates outward from
whoever is animating, so stopping it here is what every other player sees too;
driving it from the server would fight the client that owns the rig.

`Constants.RIDE_ANIMATION` is the seam for a real skating pose — an
`rbxassetid://` string, empty by default, loaded and looped at
`AnimationPriority.Action` while riding. Empty is a working default, not a
placeholder: inventing an animation asset isn't something this file can do.

### Where the HUD sits

**The readout moved out of this feature entirely** — it is a row in the shared
[Loadout](Loadout.md) strip now, declared in `Skateboard/Loadout.luau`. Only the
transient notice is still drawn here.

The history is worth keeping, because it is why that strip exists. It started
bottom-left,
"stacked above the medkit readout", which put it straight through the controls
legend — whose panel is 216px tall and **grows every time any feature registers
a key**. The readout landed on its own `Ride skateboard` row.

The legend ends at x=327 and the ammo/haul readouts start at x=1387, so the
middle of the bottom edge is the one uncontested strip down there. It is also
the project default for a new feature surface.

> The medkit readout has the same collision with the legend, latent only because
> it shows while you hold a charge. Not this feature's to move.

### Auto-dismount

Crossing a gate into grass throws you off, with a `WHEELS WON'T ROLL ON GRASS`
notice. Polled at `DISTRICT_POLL` (0.2 s) rather than event-driven — there is no
"entered a district" signal — and only over players who are actually riding,
which is usually nobody. At 0.2 s a rider at full speed covers ~9 studs, well
inside a 40-stud cell, so the board never keeps rolling a whole cell into turf.

### Teardown, and a bug worth remembering

Riding must not outlive the board. Three things end it: the `HasSkateboard`
attribute disappearing (a catch), `CharacterRemoving`, and `CharacterAdded` (a
respawn drops the welded art with the old rig).

`setRiding` is deliberately **unguarded** — no "already in that state, nothing
to do" early return. That guard existed and hid a real bug:

> A catch clears carried attributes through Pickups' `clearOnCatch`. The
> registration originally listed *both* `HasSkateboard` and `RidingSkateboard`,
> so by the time the service reacted, `RidingSkateboard` was already nil, the
> guard decided the state was correct, and **the speed multiplier and the welded
> board both survived the catch** — a permanent 1.5× for the rest of the round,
> from being caught.

Two fixes, both kept: `clearOnCatch` now names only `HasSkateboard` (the ride is
this service's state, not Pickups'), and `setRiding` always runs its teardown.
Every step in it is idempotent, and it only runs on a toggle or a teardown.

## Player attributes

| Attribute | Owner | Meaning |
| --------- | ----- | ------- |
| `HasSkateboard` | Pickups' grant (via this feature's registered `grant`) | You are carrying a board. Cleared on a catch and at round start. |
| `RidingSkateboard` | `SkateboardService` | You are on it right now. Drives the HUD colour and the welded art. |
| `SpeedMultiplier` | `SkateboardService` (consumed by `SprintController`) | Generic, feature-anonymous speed scale. `nil` when not riding — never left at 1. |
| `SkateboardNotice` | `SkateboardService` | One-shot `"message\|nonce"`, same shape as `PickupToast`. The nonce is what lets the same refusal flash twice in a row. |

## Dependencies

| Depends on | For |
| ---------- | --- |
| `Maze/MazeNav` | `nearestCell` / `bandOf` / `districtOf` / `perimeterR` — which district you're standing in |
| `Pickups/Scatter` | Registering the world pickup; `clearOnCatch` |
| `Pickups/Constants` | `MODELS_FOLDER`, so the ridden board and the world pickup share one art folder |
| `Sprint` (indirectly) | Applying `SpeedMultiplier` to `WalkSpeed` — via the attribute, no require either way |
| `Controls` | The key legend, via `Controls.luau` |
