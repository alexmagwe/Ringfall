# Gun

Scavenged retaliation: once a player has picked up the Gun pickup (see
[Pickups.md](Pickups.md)), clicking damages hunters. 10 hits kills one. Ammo is
scarce and never regenerates — hiding stays the primary verb; the gun is a
rare, costly "I have to fight now" option.

Files:

- `src/features/Gun/Net.luau` — the `Shoot` packet (client request only).
- `src/features/Gun/GunService.server.luau` — validates and applies damage.
  Server-authoritative; the sole place ammo is decremented and hits are judged.
- `src/features/Gun/GunController.client.luau` — crosshair + ammo HUD, input,
  sends the fire request. Raw HUD (no React), gated on `HasGun`.
- `src/features/Gun/Controls.luau` — registers "MOUSE 1 — Shoot (when armed)"
  in the key legend.

## Studio assets

**None required.** The crosshair and ammo counter are code-built. A muzzle
flash / tracer / siren sound are optional and left as `""` seams (see below).

## Client-request / server-authority split

The client's `Shoot` packet (`origin`, `direction` — both `Vector3`, via
ByteNet's `vec3` type) is a **request, never a source of truth**:

1. `GunController` sends `origin = camera position`, `direction = camera look
   vector` when the player left-clicks, gated on local `HasGun` + `Ammo > 0` +
   a local cooldown (feel only).
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

## The damage seam

On a hit, `GunService` walks up from `RaycastResult.Instance` to the nearest
ancestor `Model`, checks `Name == "Hunter"` **generically** (no `require` of
`HunterService`), finds its `Humanoid`, and calls `Humanoid:TakeDamage(1)`.
This is the entire cross-feature contract — the Gun feature never touches
Hunter's source, and Hunter never touches Gun's. See
[Hunter.md](Hunter.md#combat) for the health bar / death / explosion side.

## Summon trigger

On a successful hunter hit, `GunService` sets two `workspace` attributes that
`HunterService` polls (mirroring the existing `EvacAlert` idiom):

- `workspace.HunterAlert` — `os.clock()` timestamp of the hit.
- `workspace.HunterAlertPos` — the shooter's `HumanoidRootPart.Position`
  (`Vector3`; workspace attributes accept `Vector3` directly, no need to split
  into X/Z components).

Any hunter within `SUMMON_RADIUS` (200 studs) of that position, for
`SUMMON_WINDOW` (5s) after the hit, beelines toward it instead of its normal
chase/search/wander decision. Retaliating has a cost. `HunterService` clears
both attributes on every `MazeGeneration` rebuild so a stale alert can't carry
into a new round.

## Ammo economy

| Constant | Value | Where |
| -------- | ----- | ----- |
| `GUN_START_AMMO` | 12 | `Pickups/Constants.luau` — granted when the Gun pickup is grabbed |
| Ammo pickup amount | 6 | `Pickups/Constants.luau` — 4 scattered per round |
| `GUN_RANGE` | 300 studs | `GunService.server.luau` |
| `FIRE_COOLDOWN` | 0.2s | `GunService.server.luau`, server-enforced |
| `HUNTER_HITS` | 10 | `HunterService.server.luau` — shots to kill a hunter |

Ammo is found, never regenerates. A kill costs most of a full magazine.

## Sound seams (not yet wired to an asset)

- `GunService.SIREN_SOUND_ID = ""` — plays on the hit hunter once a player
  supplies an asset id. Silent until then.
- `HunterService.BLAST_SOUND_ID = ""` — optional boom on hunter death/explosion.

## Dependencies

`GunController` reads `HasGun` / `Ammo` attributes and sends `Gun.Net.Shoot`.
`GunService` reads/writes `HasGun` / `Ammo`, raycasts against `workspace`, and
writes `workspace.HunterAlert` / `HunterAlertPos`. `Priority = 12`, matching
`PickupsService` (no ordering dependency between them).
