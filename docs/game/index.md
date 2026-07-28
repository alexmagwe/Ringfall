# Game docs

Per-feature and cross-cutting documentation. Start with the conventions, then the
feature you're touching.

## Conventions (cross-cutting)

These describe the four seams the framework is built around — read the relevant
one before changing UI or feature structure. [framework-boundary.md](framework-boundary.md)
sits above them: what's framework vs. feature, the `Shared.Boil` contract, and the
one-way dependency rule that keeps the framework updatable.

| Doc | Seam | What it covers |
| --- | ---- | -------------- |
| [framework-boundary.md](framework-boundary.md) | — | Framework vs. feature, the `Boil` public surface, the no-naming-a-feature rule (enforced by `tools/check-framework-boundary`). |
| [skin-contract.md](skin-contract.md) | #1 skin | The component contract, `SkinProvider`, gem + flat skins. How a primitive *looks*, swappably. |
| [layout-surfaces.md](layout-surfaces.md) | #2 layout | `Stack`/`Row`/`Grid`/`Slot` code primitives + the deferred Studio-extract pipeline. How a screen is *arranged*. |
| [headless-core.md](headless-core.md) | #3 view | Cores are presentation-agnostic; views are dumb; actions are intent. Enforced by `tools/check-views`. |
| [presentations.md](presentations.md) | #4 presentation | Self-registering screen / world / command surfaces and the de-hardcoded entry files. How a feature *shows up*. |

## Features

| Doc | Feature |
| --- | ------- |
| [Maze.md](Maze.md) | The circular maze — per-round seed, the `MazeGeneration` rebuild contract, the staging room + corridor, the Vault |
| [Escape.md](Escape.md) | The round loop — staging countdown, the Door, extraction-by-vault-carrier, banking, and what the old per-player win left behind |
| [Hunter.md](Hunter.md) | Maze stalkers — sensing, chase/search/wander, the catch (now spilling Haul/Vault), combat (health/death/explosion/respawn), the gunshot summon and the vault alarm, and the (now-dead) evac-alert convergence |
| [Checkpoint.md](Checkpoint.md) | Sealed-district gate checkpoints — district (not band) tracking, respawn-at-gate, the floor-level stand CFrame, and why a checkpoint is a recovery point rather than a progress save post-extraction-loop |
| [Salvage.md](Salvage.md) | The extraction loop's prize layer — depth-scaled scatter, the Vault + alarm, drop/steal/recover, nothing-carries-between-rounds, and the compass as standard equipment |
| [Pickups.md](Pickups.md) | Per-run scavenge — gun, ammo, flashlight, stamina upgrade; scatter/grant/clear lifecycle + the model-clone convention |
| [Flashlight.md](Flashlight.md) | Camera-cone light, gated on the `HasFlashlight` scavenge attribute |
| [Health.md](Health.md) | Player HP — hunter-contact drain, MedKit heal, the top health bar, death-at-0 |
| [Gun.md](Gun.md) | Client-request/server-authority gun — ammo economy, the `Humanoid.TakeDamage` seam, the summon trigger |
| [LookBack.md](LookBack.md) | Hold-Q glance behind, and how it avoids inverting movement |
| [Controls.md](Controls.md) | Key legend + the `Controls.luau` registration convention |
| [Clicker.md](Clicker.md) | Coin Clicker — server-authoritative currency loop (practice game) |
| [PlayerData.md](PlayerData.md) | Profile persistence + the `registerTemplate` discovery convention |
| [Settings.md](Settings.md) | Settings registry, server validation, the `Settings.luau` discovery convention |
| [Notes.md](Notes.md) | Persisted per-player note (full-stack reference feature) |
| [Music.md](Music.md) | Settings-driven background music |
| [PickupFX.md](PickupFX.md) | Client-side pickup animation system |
| [Sidebar.md](Sidebar.md) | HUD navigation chrome |
| [UIShell.md](UIShell.md) | Global frame open/close system |
| [UIShowcase.md](UIShowcase.md) | Demo HUD / entry surface |
