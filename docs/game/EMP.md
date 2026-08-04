# EMP

A shelf-bought burst that **switches hunters off instead of killing them**.
Aim, press `F`, and everything within 45 studs of where it lands stops dead for
6 seconds — no damage, no kills, no permanent change.

## Why it isn't just a better gun

The Sidearm answers **"this one is in my way"**: one hunter, permanently, at the
price of every hunter in earshot hearing the shot. It has no answer at all for
**"three of these have me in a dead end"** — sixteen hits to drop a Warden is
not a plan when you are already cornered.

The EMP is that answer, and it deliberately kills nothing. What you buy is a
**window to leave through**, not a cleared route. Every number is set to keep it
that way:

| Constant | Value | Why |
| -------- | ----- | --- |
| `RADIUS` | 45 | A bit over one cell (40): the corridor you're in and the mouth of the next. A group, not an individual. |
| `SECONDS` | 6 | Long enough to walk past a pack or break a lock and turn a corner. Too short to cross a district. |
| `RANGE` | 90 | Shorter than the gun's aim range on purpose. Disabling a pack from across the district and strolling in unopposed would make this a way to *delete* encounters rather than survive them. |
| `COOLDOWN` | 1.5 s | Two charges back to back would just be one 12-second stun — the "clear route" this is priced not to be. |

Aiming at your own feet is legal and deliberate: that's the panic button.

Files:

- `src/features/EMP/Constants.luau` — every number above.
- `src/features/EMP/EMPService.server.luau` — the authority: charges, cooldown,
  the raycast, the burst, the pulse.
- `src/features/EMP/EMPController.client.luau` — the `F` key, the cursor aim,
  the charge readout and the result flash.
- `src/features/EMP/Net.luau` — one packet, `Fire { direction }` (C→S, request).
- `src/features/EMP/Store.luau` — the shelf item.
- `src/features/EMP/Controls.luau` — the key-legend entry.

## Studio assets

**None required.** `FIRE_SOUND_ID` is empty by default and the burst is silent;
set it to an `rbxassetid://` for a discharge sound. The visual — an expanding
neon sphere that fades over `RING_SECONDS` — is built in code.

## On the shelf

`emp.pulse` — **350 to unlock, 75 a round, 2 charges, repeatable.**

Priced between the Sidearm (60) and the Silencer (90) to rent, and unlocked
*under* the Silencer's 400: the Silencer permanently removes a cost from every
shot for a whole round, and this is two moments.

Repeatable like the ammo box, and unlike the stamina cell — there's no runaway,
because more charges is **more windows, not a longer one**, and the cooldown
stops them being chained into one long stun.

## How the stun works

The Hunter feature owns the **mechanism** and this feature owns the **reason**.
`src/features/Hunter/Stun.luau` exposes:

```lua
Stun.pulse(position, radius, seconds) -> number  -- how many were hit
Stun.isStunned(model) -> boolean
```

EMPService calls `pulse` and never touches a hunter directly; HunterService
reads `isStunned` and never learns what an EMP is. **This is the same seam
`HunterAlert` already is** — GunService raises the alert on every unsilenced
shot and HunterService consumes it, with neither file naming the other's
feature. A stun is the mirror image of that, so it gets the same treatment
rather than an EMP-shaped branch inside the AI loop.

State lives in a **`StunnedUntil` attribute on the hunter model**, not a table
inside the module, so it survives being required from either realm and is
visible in the Explorer while you debug a stun that didn't land. Hunters carry
an `IsHunter` attribute so `pulse` never has to guess from names — `Hunter` is a
name anything in the place could take, and a silently-missed stun would be very
hard to see.

**Times are `workspace:GetServerTimeNow()`, not `os.clock()`.** The value rides
on a replicated attribute, and `os.clock` is wall time since each peer's own
process started — a client comparing the server's number against its own would
be wrong by however long the two have been running.

**Pulses only ever extend a stun, never shorten one.** Two overlapping bursts
must not leave a hunter *less* disabled than the first one did.

### What "switched off" means

A stunned hunter does not path, sense, spot, summon, answer a summon, drain you,
or catch you. Its beam and both its sounds go dead. It is a statue that happens
to still be shootable.

Two places enforce it, and both are needed:

- **The AI loop bails out of the whole tick**, above even the `MazeNav.ready`
  guard — rather than threading an `if stunned` through the nine branches below
  it, every one of which would have to remember.
- **The catch loop returns early.** It runs on its own `Heartbeat`, so stopping
  the hunter *moving* is not enough: it would happily keep draining a player
  pressed up against a statue.

### The tell

Cold electric blue (`STUN_COLOR`) against every kind's warm eye colour, on both
the body glow and the eyes themselves — a hunter whose lights are out is not
looking. A stunned spotter's cone drops to `SPOT_BEAM_DEAD` (0.96) rather than
being hidden outright: a beam that vanished would read as *dead* rather than as
temporarily down, and the player needs to see it about to come back.

## Player attributes

| Attribute | Owner | Meaning |
| --------- | ----- | ------- |
| `EmpCharges` | Store's `apply` / this service's spend | Bursts remaining. Per-run; lost on a catch and at round start like everything carried. |
| `EmpResult` | `EMPService` | One-shot `"message\|nonce"`. `3 DISABLED` or `NOTHING IN RANGE` — both spend a charge and have to read differently, or a wasted burst is indistinguishable from a bug. |
| `StunnedUntil` | `Stun.pulse` (on the **hunter**, not the player) | Server time the stun expires. |
| `IsHunter` | `HunterService` (on the hunter) | What makes a model findable by `Stun.pulse`. |

## Dependencies

| Depends on | For |
| ---------- | --- |
| `Hunter/Stun` | The entire effect. The only cross-feature call this makes. |
| `Store` | The shelf item, via `Store.luau` |
| `Controls` | The key legend, via `Controls.luau` |

Nothing depends on EMP. Deleting the folder removes the item from the shelf and
the key from the legend, and leaves `Stun` unused but working.
