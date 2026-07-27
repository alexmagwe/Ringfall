# Health

A per-run health bar for the player. The game had no player-HP model before —
being caught was an instant checkpoint teleport. Now hunter contact **drains**
health, and you're only caught when it hits 0.

Files:

- `src/features/Health/Constants.luau` — `MAX_HEALTH` (100).
- `src/features/Health/HealthService.server.luau` — owns the `Health` /
  `MaxHealth` player attributes; refills them for a fresh life.
- `src/features/Health/HealthController.client.luau` — the top-of-screen health
  bar (raw HUD, presentation only).

## The attributes

| Attribute | Owner | Meaning |
| --------- | ----- | ------- |
| `MaxHealth` | HealthService | full-bar value (100) |
| `Health` | HealthService (init) + HunterService (drain) + PickupsService (heal) | current, server-authoritative |

Everything talks through these two attributes — HealthService imports none of the
features that read/write them, matching the `Crouched`/`HasGun`/`Checkpoint`
attribute-contract style.

## Rules

- **Down only, no passive regen.** Health never ticks back up on its own.
- **Drain:** a hunter within `CATCH_DIST` bleeds it at `HEALTH_DRAIN` (25 HP/s,
  a HunterService constant). Multiple hunters stack. See [Hunter.md](Hunter.md).
- **Refill happens on a fresh life, not over time:**
  - spawn / respawn → `HealthService` `CharacterAdded` sets it to `MAX_HEALTH`;
  - caught at 0 HP → the checkpoint respawn in `HunterService.catchPlayer` sets
    it back to `MaxHealth`;
  - RUN IT BACK → `EscapeService`'s restart loop resets it (that path only
    teleports, so `CharacterAdded` doesn't fire).
- **MedKit pickup** tops it up by 50, clamped to `MaxHealth` — the only *mid-life*
  restore. Three spawn per round; see [Pickups.md](Pickups.md).

## Death at 0

Reaching 0 HP triggers the existing `HunterService` catch: loom, red-out (client
`HunterController`), then a 1.4s teleport to the last `Checkpoint` with a full bar
again. So "death" is the same forgiving checkpoint setback it always was — the
health bar just gates *when* it happens (sustained contact) instead of a single
touch.

## HUD

Two stacked bars, top-centre, both 320px wide so they align:

- **Health** (`HealthController`) at y=14, reads `Health`/`MaxHealth`, green
  fading to red under 30%.
- **Stamina** (owned by `SprintController`) at y=40, always visible now.

Both are raw-instance HUDs (no React), consistent with the other gameplay HUDs.
The health bar is pure presentation — it reads the replicated attributes and
draws; all drain/heal logic is server-side.

## Tuning

`MAX_HEALTH` (Health/Constants), `HEALTH_DRAIN` (HunterService), MedKit heal
amount and `count` (Pickups/Constants). Health resets to full on every respawn to
avoid a death-spiral; if you want it to *persist* across catches (MedKit-only
recovery, harder), drop the refill in `catchPlayer` and the `EscapeService`
restart loop.
