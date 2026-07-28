# Ringfall

A Roblox extraction game. You drop in at the edge of a circular maze, descend
through three sealed districts to the vault at its centre, and carry it back out
the way you came — while six hunters, every one of them alerted the moment you
take it, come to meet you.

Built on [Boil](#framework) (Rojo + Wally + React, Feature-Sliced Design).

## The round

1. **Staging.** Everyone waits in a room outside the maze with the extraction pad
   in plain sight, so the return trip is taught without a word of tutorial. A
   countdown runs, the door drops.
2. **Descend.** Each district is walled off except for a **single gate**, so
   getting inward means searching a whole ring for one opening. Salvage is
   scattered throughout, worth more the deeper it spawns.
3. **The vault.** Taking it trips the alarm: every hunter in the maze converges
   on the carrier, and every player's compass swings round to point at them. The
   chamber itself is a sanctuary — nothing can touch you while you're standing in
   it. Leaving is your choice to make.
4. **Extract.** Back out through the same three gates, loaded and hunted. The
   vault reaching the pad ends the round for everyone; everyone banks whatever
   they were carrying.
5. **Caught?** Your haul spills where you died, and if you had the vault it drops
   as its own object that *anyone* can claim. You wake at the last gate you
   passed. Go back in for it, or walk out with nothing.

Free-for-all — one player is simply a race with nobody else in it, so it plays
solo. Nothing carries between rounds except your record, which is what keeps a
loss a loss.

## Assets

**Everything a clone needs is in the repo.** Open a blank place, sync, and you
get the real game — art included. There is no manual Studio setup.

| Asset | Where it lives | How it gets in |
| ----- | -------------- | -------------- |
| Pickup art | `assets/PickupModels.rbxm` | Rojo syncs it to `ServerStorage.PickupModels` |
| Music | ids in `Music/Constants.luau` | played by asset id at runtime |
| `SpawnLocation` | — | created by `MazeService` if the place has none |
| Maze, staging room, vault, hunters | — | all built procedurally in code |

### Changing the pickup art

`ServerStorage.PickupModels` is **Rojo-managed**, so edits made in Studio are
overwritten on the next sync. To change a model: edit it in Studio, then
re-export over the file —

```
Right-click ServerStorage.PickupModels → Save to File… → assets/PickupModels.rbxm
```

— and commit the result. Each child's name must match the `model` field of a
`SPAWNS` entry in `Pickups/Constants.luau`; a mismatch silently falls back to a
coloured neon ball rather than erroring, so a typo looks like "the model didn't
load". A `Model`, `Tool` or a single part all work.

`.rbxm` is binary, so it won't diff or merge — treat it as one indivisible file
and don't edit it from two branches at once.

Roblox audio and animation privacy applies: assets must be owned by the
experience's creator (or group), or licensed from the Creator Store. A random
asset id off the web silently fails to load.

## Getting started

```bash
rokit install                           # rojo, wally, lune
wally install                           # Packages/ and ServerPackages/
lune run tools/split -- --watch         # terminal 1: regenerate build/ on change
rojo serve                              # terminal 2: sync to Studio
```

Connect via the Rojo plugin **in Edit mode** — Rojo cannot sync during a
playtest, and trying produces `Http requests can only be executed by game server`.

`lune run tools/split` completing without throwing is the signal that matters.
`rojo build` does **not** validate Luau and will pass over syntax errors.

Two more checks worth running before a commit:

```bash
lune run tools/check-views              # views stay dumb (no net/persistence in UI)
lune run tools/check-framework-boundary # framework never names a feature
```

## Features

Gameplay lives in `src/features/`, one folder per feature, each removable.
Per-feature docs are in [`docs/game/`](docs/game/index.md).

| Feature | What it owns |
| ------- | ------------ |
| `Maze` | Maze generation, sealed districts and gates, the staging room, the round state machine |
| `Salvage` | Haul, the vault and its alarm, drop/steal/recover |
| `Hunter` | The stalkers: sensing, chase/search/wander, health, the catch |
| `Health` | Player HP — hunter-contact drain, medkits, death at 0 |
| `Gun` | Client-request / server-authoritative shooting |
| `Pickups` | Scavenged gear scattered per round |
| `Checkpoint` | Respawn points for recovery runs |
| `Sprint`, `LookBack`, `Flashlight`, `Atmosphere`, `Music`, `Controls` | Movement, camera, and presentation |
| `PlayerData`, `Settings`, `UIShell`, `Cmdr` | Framework-side plumbing |

## Not built yet

**The store.** Cash, permanent unlocks and per-run rentals are specced in
`.taskplans/TASKPLAN-extraction-loop.md` (Phase 6) but deliberately unbuilt — the prices are
unguessable until a typical run's payout is known. Haul is currently reported at
round end and then cleared, so there is no economy.

## Framework

Ringfall is built on Boil: **Rojo + Wally + React (jsdotlua)**, Feature-Sliced
Design, managed by **Rokit**, with a **Lune splitter** that colocates feature code
in one folder and routes it to the right Roblox service at sync time.

Filename suffix → destination:

| Source | Resulting Studio path |
| ------ | --------------------- |
| `*.server.luau` | `ServerScriptService.Features.<Feature>.<Name>` |
| `*.client.luau` | `StarterPlayerScripts.Features.<Feature>.<Name>` |
| `*.ui.luau`, `*.luau` | `ReplicatedStorage.Features.<Feature>.<Name>` |

Modules whose name ends in `Service` or `Controller` are auto-started; an
optional `Priority` (lower = earlier) orders them. Features extend each other
through registration and shared attributes, never by editing each other's source.

- [docs/getting-started.md](docs/getting-started.md) — install, dev loop, verification
- [docs/architecture.md](docs/architecture.md) — split model, entry flow, load ordering
- [docs/adding-a-feature.md](docs/adding-a-feature.md) — feature workflow, priority bands
- [docs/reference.md](docs/reference.md) — package table, sync map, filename rules
- [docs/game/index.md](docs/game/index.md) — per-feature game docs
