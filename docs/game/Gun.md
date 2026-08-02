# Gun

Scavenged retaliation: once a player has picked up the Gun pickup (see
[Pickups.md](Pickups.md)), clicking damages hunters. 10 hits kills one. Ammo is
scarce and never regenerates — hiding stays the primary verb; the gun is a
rare, costly "I have to fight now" option.

Files:

- `src/features/Gun/Net.luau` — the `Shoot` packet (client request only).
- `src/features/Gun/GunService.server.luau` — validates and applies damage.
  Server-authoritative; the sole place ammo is decremented and hits are judged.
- `src/features/Gun/GunController.client.luau` — cursor reticle + ammo HUD, input,
  sends the fire request. Raw HUD (no React), gated on `HasGun`.
- `src/features/Gun/Controls.luau` — registers "MOUSE 1 — Shoot (when armed)"
  in the key legend.

## Studio assets

**None required.** The reticle, ammo counter and the gun itself are all
code-built. A muzzle flash / tracer / siren sound are optional and left as `""`
seams (see below).

**Optional gun art:** anything named **`GunModel`** (or just `Gun`) under
**ServerStorage**. Drop it in and it replaces the code-built blaster with no
code change — e.g. a copy of the `GatlingLaser` Tool already sitting in
`ServerStorage.PickupModels`. Three shapes are accepted, same normalize-any-art
contract as `buildPickup` and Salvage's `buildObject`:

- **A `Tool`** — kept whole, since it already has a `Handle` and often a tuned
  `Grip`. One with no `Handle` still equips (`RequiresHandle = false`) rather
  than failing outright, but you won't see it.
- **A `Model`** — flattened into a Tool. Every part is `WeldConstraint`ed to the
  handle *before* reparenting, while the clone still holds its authored offsets;
  art assembled with no welds would otherwise come apart the moment it's
  unanchored.
- **A single `BasePart`** (Union / MeshPart / Part) — wrapped and treated as the
  Model case.

Loose art (Model or part, not a Tool) is scaled so its longest axis measures
`GUN_TARGET_LENGTH` (3 studs); Creator Store weapons are authored at any size
and one four times too big reads as a bug. Scripts are stripped and every part
is unanchored, de-collided, `CanQuery = false` and `CanTouch = false` on the way
in — unanchoring is the load-bearing one, since an anchored `Handle` can't be
moved by the grip `Motor6D` and the character would walk off leaving the gun
hanging in the air.

### Where the hand goes

Roblox grips a Tool by the `Handle` part's **own origin** — for a pistol whose
mesh origin sits mid-frame, that floats the whole gun above the fist, pointing
the right way but held nowhere near the grip. `Tool.Grip` is the correction, and
free-model Tools routinely ship with it left at identity.

**The fix is a `Grip` attribute of type `CFrame` on the art in Studio.** It's
deliberately the only mechanism for authored Tools: a `Grip` marker under the
Handle *looks* like the answer, but the pistol this was built against ships an
`Attachment` named `Grip` at `(0, -0.325, 0)` with a -90° yaw, and neither half
was usable — the yaw turned a correctly-pointing gun a quarter-turn off, and the
offset named the wrong axis entirely (the working value is `0.35` on the
Handle's **X**). A marker records whatever the original scripts needed, which is
not the same question as "where does a hand go". Guessing from it produced a
worse result than doing nothing, so nothing is what happens.

**Tuning it takes seconds and no restarts.** `GunService` watches the art's
`Grip` attribute and re-applies it to every held gun the moment it changes, and
`Tool.Grip` updates an equipped tool live — so you drag the numbers in the
Properties panel mid-playtest and watch the gun move in the character's hand.
Set the final value in **edit mode**, though: changes made during a playtest are
discarded when you stop.

Every part is also welded to the Handle, **authored Tools included**. Everything
gets unanchored on the way in (an anchored Handle can't be gripped), so a part
that was holding its place purely by being anchored — a marker, a shell
template, a detail the original scripts moved — would otherwise drop out of the
gun and fall through the world the moment it's held. Redundant welds on parts
that were already joined are harmless.

For **loose art** (Model or bare part) there's no authored Handle, so one is
chosen best-evidence-first:

1. **A part named `Handle` or `Grip`** (case-insensitive). Most gun art has one,
   and it names the exact spot a hand belongs.
2. **The model's `PrimaryPart`** — the other explicit statement of intent.
3. **The largest part.** That's the frame, so the grip at least lands on the
   mass rather than on some tiny greeble.

Case 3 is a guess, not a statement, so it gets a correction: `Tool.Grip` is set
to the model's bounding-box centre expressed in Handle-local space, which
balances the whole weapon on the hand instead of hanging it off the frame's
centre point. (`Grip` is C1 of the `RightGrip` Motor6D, so it applies inverted —
`Handle.CFrame = hand.CFrame * C0 * Grip:Inverse()`.) Cases 1 and 2 are trusted
and left alone.

The `Grip` attribute overrides all of it, loose art included.

**`DEFAULT_ART_GRIP` = `CFrame.new(0.35, 0, 0)`** is applied to any authored
Tool whose own `Grip` is identity — identity means the author never set one,
not that they wanted the Handle's mesh origin in the palm. The value is tuned
against the pistol currently in `ServerStorage.Gun`.

A per-model number in code is the wrong home for a grip, and it's there anyway
for a specific reason: the attribute lives in the `.rbxl`, which this repo
doesn't track. Without the constant, a fresh clone — or a value tuned during a
playtest and lost when the test stopped — puts the gun back in mid-air with no
clue why. Setting the attribute makes it irrelevant; swapping in art that
carries its own grip makes it irrelevant. It is a floor, not a policy.

## The gun you can see

`HasGun` is an attribute, and for a while it was *only* an attribute — a
reticle appeared and your hands stayed empty, so nothing distinguished an
armed player from an unarmed one, to themselves or to anyone watching.
`GunService` now mirrors the attribute into a real held `Tool`:

- **A Tool, not a hand-welded model**, so Roblox's grip puts it in the right
  hand and plays the tool-hold pose — the character presents the weapon instead
  of letting it dangle through an animation that knows nothing about it.
- **`syncGun` is bound to the attribute and to `CharacterAdded`**, so it tracks
  both directions and survives a respawn: a fresh character starts
  empty-handed, and a catch (which clears `HasGun` in `PickupsService`) takes
  the visible gun with it.
- **It can't be put away.** Number keys and the backpack slot both unequip a
  Tool, which would leave a player registering as armed while holding nothing,
  so `Unequipped` re-equips it (deferred, and only while `HasGun` still holds).
  `CanBeDropped = false` covers Backspace.
- Every part is `CanQuery = false` / `CanTouch = false`, so the held gun never
  blocks an aim raycast and never trips a pickup's `Touched`.
- **The Roblox backpack hotbar is hidden** (`GunController`, via
  `SetCoreGuiEnabled`). A Tool existing makes it appear, but the slot can't be
  acted on — the gun can't be dropped, swapped or put away — so it's dead UI
  sitting under the ammo readout that carries the real information. It lives in
  the Gun feature rather than a shared UI file because no other feature spawns
  a Tool, and it's wrapped in a `pcall`: `SetCoreGuiEnabled` throws if the
  CoreGui isn't up yet, and losing the reticle and aiming over a cosmetic
  call would be a bad trade.

## Client-request / server-authority split

The client's `Shoot` packet (`origin`, `direction` — both `Vector3`, via
ByteNet's `vec3` type) is a **request, never a source of truth**:

1. `GunController` sends `origin = camera position` (informational) and
   `direction`, gated on local `HasGun` + `Ammo > 0` + a local cooldown (feel
   only). See "Where the shot actually goes" below — `direction` is *not* the
   camera's look vector.
2. `GunService.Net.Shoot.listen` re-validates everything server-side:
   - Rejects unless `player:GetAttribute("HasGun")` and `Ammo > 0`.
   - Enforces `FIRE_COOLDOWN` (0.2s) per player via a `{[Player]: number}`
     last-shot table — a spoofed client cannot machine-gun past this.
   - Decrements `Ammo` before raycasting (a shot is spent whether or not it
     connects).
   - **Re-raycasts from the character's own `HumanoidRootPart.Position +
     HEAD_OFFSET`**, using the *server's* copy of the player's position — never
     the client-claimed `origin`. Direction is normalized server-side too.
   - `RaycastParams` excludes the shooter's own character.

A client can never fire without `HasGun`, past 0 ammo, or faster than
`FIRE_COOLDOWN` — all three gates are server-side, not merely mirrored.

## Targeting

**The reticle rides the cursor, not the centre of the screen.** Roblox's default
third-person camera leaves the mouse free — moving it moves a pointer, it does
not turn the camera — so a crosshair pinned to screen centre points wherever the
camera happens to face and *nothing the player does with the mouse moves it*.
There was no way to pick a target at all. Drawing on the cursor makes the
pointer the aiming device, which is what a player is already trying to use it
as.

It's a ring, and the system cursor stays visible underneath it: the staging-room
shelf is used while armed, so hiding the pointer to draw our own would break
clicking on the shop. Over a hunter the ring turns red and tightens
(`RETICLE_TARGET_SIZE`). That feedback *is* the targeting: the maze is dark and
a hunter at range is a silhouette, so "am I actually pointed at it?" is a
question the render alone can't answer.

`isHunter` in the controller is a named-`Model` check, the cosmetic half of the
same contract `GunService` uses to judge a hit — the Gun feature never requires
`HunterService`. The reticle and the fire request share one `resolveAim` call,
so the ring can't promise a hit the shot doesn't take.

## Where the shot actually goes

The server fires from the character's head; the reticle sits under the cursor,
which is the *camera's* view of the world. Those are two different points, and
reconciling them is the whole of the aiming problem.

`GunController.resolveAim` resolves it by aiming at a **point**, not along a
direction: it raycasts from `camera:ViewportPointToRay(cursor)` to find what the
cursor is covering (falling back to `AIM_RANGE` down that ray when the shot goes
into open space), then sends the unit vector from `HumanoidRootPart +
HEAD_OFFSET` — the server's own firing point — to that point. Both rays converge
on the same spot at every distance.

Sending `camera.CFrame.LookVector` instead, which is what this did originally,
is the bug that made the gun feel broken rather than merely hard: in third
person the camera sits several studs behind and above the character, so a ray
cast from the head along the camera's direction is offset by that whole
displacement — two near-parallel lines that only converge at infinity, missing
by most of the camera offset at exactly the ranges a fight happens at.

Two constants have to be kept in step by hand, and are commented as such in both
files: `HEAD_OFFSET` (the firing point) and `AIM_RANGE` / `GUN_RANGE`.

`GunHud` is also the one HUD with **`IgnoreGuiInset = false`**. Both
`GetMouseLocation` and `ViewportPointToRay` work in a coordinate space that
excludes the topbar inset, so a reticle ignoring the inset would sit half an
inset above where the gun really aims.

**Aim assist.** A raycast is a zero-width line, hunters move, and the client's
view of them trails the server. If the exact ray misses, the server takes one
more pass with a `Spherecast` of radius `ASSIST_RADIUS` (1.5) down the same
line. A swept sphere still returns the *first* thing it hits, so a wall between
you and a hunter blocks the shot exactly as before — this widens the shot, it
doesn't shoot through anything.

## The damage seam

On a hit, `GunService` walks up from `RaycastResult.Instance` to the nearest
ancestor `Model`, checks `Name == "Hunter"` **generically** (no `require` of
`HunterService`), finds its `Humanoid`, and calls `Humanoid:TakeDamage(1)`.
This is the entire cross-feature contract — the Gun feature never touches
Hunter's source, and Hunter never touches Gun's. See
[Hunter.md](Hunter.md#combat) for the health bar / death / explosion side.

## Summon trigger

On **every shot — hit or miss** — `GunService` sets two `workspace` attributes
that `HunterService` polls (mirroring the existing `EvacAlert` idiom):

- `workspace.HunterAlert` — `os.clock()` timestamp of the shot.
- `workspace.HunterAlertPos` — the shooter's `HumanoidRootPart.Position`
  (`Vector3`; workspace attributes accept `Vector3` directly, no need to split
  into X/Z components).

Any hunter within `SUMMON_RADIUS` (200 studs) of that position, for
`SUMMON_WINDOW` (5s) after the shot, beelines toward it instead of its normal
chase/search/wander decision. `HunterService` clears both attributes on every
`MazeGeneration` rebuild so a stale alert can't carry into a new round.

**This used to fire only on a landed hit**, which made missing free — the honest
read of the Sidearm was "spray at range, it costs nothing unless you connect",
while the shelf sold it as *"hunters hear every shot"*. A gunshot is loud
whether or not it finds anything, and that noise is the price the whole weapon
is balanced around: firing trades a hunter's health for your position.

**The Silencer buys that price off.** A player carrying `HasSilencer` sets
neither attribute, so they shoot without summoning anyone — and the shot clip
plays at `SILENCED_VOLUME` (0.35 of the art's own). It keeps a report on
purpose: you still need to know the trigger registered, and a genuinely silent
gun reads as a broken one.

## Ammo economy

| Constant | Value | Where |
| -------- | ----- | ----- |
| `GUN_START_AMMO` | 12 | `Pickups/Constants.luau` — granted when the Gun pickup is grabbed |
| Ammo pickup amount | 6 | `Pickups/Constants.luau` — 4 scattered per round |
| `GUN_RANGE` | 300 studs | `GunService.server.luau` (mirrored as `AIM_RANGE` in the controller) |
| `FIRE_COOLDOWN` | 0.2s | `GunService.server.luau`, server-enforced |
| `ASSIST_RADIUS` | 1.5 studs | `GunService.server.luau` — the miss-retry sphere |
| `HUNTER_HITS` | 10 | `HunterService.server.luau` — shots to kill a hunter |

Ammo is found, never regenerates. A kill costs most of a full magazine.

## Shelf items

Registered from `src/features/Gun/Store.luau`, picked up by the Store feature's
auto-discovery — Store never names Gun. See [Store.md](Store.md).

| Item | Unlock | Rent | Effect |
| ---- | ------ | ---- | ------ |
| Sidearm | 0 | 60 | `HasGun` + 12 rounds |
| Silencer | 400 | 90 | `HasSilencer` — shots summon nobody, clip plays at 0.35 volume |
| Ammo box | 0 | 30 | +12 rounds, repeatable |

The **Silencer is the priciest thing on the shelf** (above the Medkit's 300/80)
because it removes the one cost that makes shooting a decision at all. Unarmed,
firing trades a hunter's health for your position; silenced, that trade
disappears. It should never be cheap, and `unlockCost = 400` keeps it off the
first round entirely.

## Sound

**The shot sound comes from the art.** Gun models ship their own fire clip — the
pistol in `ServerStorage.Gun` carries a `Sounds` folder — and their own scripts
were what played it, so stripping those (which we must) leaves a sound nothing
will ever trigger. `shotSoundOf` finds it by substring match against
`SHOT_SOUND_NAMES` (`fire` / `shoot` / `shot` / `gunshot` / `blast`), since the
clip is called `Fire`, `FireSound`, `Handgun_Shoot` or similar depending on who
built the model.

If no name matches, a lone `Sound` in the tool is taken as unambiguous — but
several unnamed ones are left alone. Guessing wrong there plays a reload or
magazine-drop clip on every trigger pull, which is worse than silence.

It fires **before the raycast and unconditionally**: the bang belongs to pulling
the trigger, not to connecting, and a silent trigger reads as an input that
didn't register. Played server-side so every player hears it — being heard is
the cost of shooting in this game.

### Seams (not wired to an asset)

- `GunService.SHOT_SOUND_ID = ""` — used **only** when the art brought no clip
  of its own, so setting it can never fight with real gun art. Parented to the
  `Handle` at equip time so it plays positionally.
- `GunService.SIREN_SOUND_ID = ""` — plays on the hit hunter once a player
  supplies an asset id. Silent until then.
- `HunterService.BLAST_SOUND_ID = ""` — optional boom on hunter death/explosion.

## Dependencies

`GunController` reads `HasGun` / `Ammo` attributes and sends `Gun.Net.Shoot`.
`GunService` reads/writes `HasGun` / `Ammo`, raycasts against `workspace`, and
writes `workspace.HunterAlert` / `HunterAlertPos`. `Priority = 12`, matching
`PickupsService` (no ordering dependency between them).
