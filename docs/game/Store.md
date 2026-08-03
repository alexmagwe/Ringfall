# Store

The staging-room shelf. Cash earned in the maze buys two different things, and
keeping them separate is the whole point of the feature.

| | Unlock | Rent |
| --- | ------ | ---- |
| Paid | once, permanently | every round you take the item in |
| Stored in | `Ringfall.Unlocked[id]` (profile) | a per-run player attribute |
| Lost on death | never | yes, like everything you carry |
| What it buys | *access* to the item | the item, for one run |

Progression is your options widening, not your raw power climbing. A
fully-unlocked veteran still has to fund and risk their kit every round exactly
like a newcomer, which keeps the free-for-all gap bounded — and it stops cash
going worthless once you own everything, because rent never stops.

## The loop

1. Round ends. `EscapeService` banks **every** player's `Haul` into
   `Ringfall.Cash` (see [Escape.md](Escape.md)) and updates `Ringfall.BestHaul`.
   Cash is permanent from that moment: death can't take it, a lost round can't
   take it, a rejoin restores it.
2. Staging begins. The terminal in the staging room opens the shelf.
3. You unlock what you can afford, and rent what you want to take in. Rented
   effects apply immediately as per-run attributes.
4. The doors open. **The shelf keeps trading** — see below.
5. Caught in the maze → your rented kit is stripped along with your haul. Your
   cash and unlocks are untouched.

### Why trading isn't restricted to Staging

It was, briefly, on the theory that buying mid-run would let a cornered player
conjure a gun out of nothing. Two facts make that not a risk, and the
restriction cost more than it bought:

- **You can't earn mid-run.** Haul only becomes cash at round end, so the moment
  the doors open your budget for that round is fixed. Nothing you find in the
  maze can be spent in it.
- **The terminal is in the staging room.** Re-kitting means running back out
  through three districts and in again. A cornered player is precisely the one
  player who can't reach it — the geography enforces the rule the check was
  trying to.

Against that, a 15-second countdown is not enough time to spawn, find the
terminal, read four items and decide, so the staging-only rule mostly meant
new players never used the shelf at all.

The shelf still closes when you walk away from the terminal (`CLOSE_RANGE`),
which is what stops a centred window following you into the maze.

## The catalogue is not the Store's

`src/features/Store/` owns the *mechanism*: prices, validation, the terminal, the
window. It owns **no content**. Every item is declared by the feature whose
effect it applies, through a sibling `Store.luau`:

```lua
-- src/features/Health/Store.luau
return function(Store)
	Store.registerItem({
		id = "health.medkit",
		label = "Medkit",
		description = "One stored charge. Press H to spend it.",
		unlockCost = 300,
		rentCost = 80,
		order = 40,
		repeatable = true,
		apply = function(player) player:SetAttribute("MedCharges", (player:GetAttribute("MedCharges") or 0) + 1) end,
		clear = function(player) player:SetAttribute("MedCharges", nil) end,
	})
end
```

`Store/init.luau` auto-discovers those at load time on **both realms** — same
convention as `Settings.luau` and `PlayerData.luau`. Adding an item is zero edits
to `src/features/Store/`, and the Store never names Gun, Health or Sprint.

Registration is **sealed** after discovery. Register only from shared code: the
server validates purchases against this registry, so a server-only or
client-only registration would let the two realms' catalogues diverge.

### Item fields

| Field | Meaning |
| ----- | ------- |
| `id` | Stable key. Also the `Unlocked` map key, so don't rename it after shipping. |
| `label` / `description` | Shelf row text. |
| `unlockCost` | Paid once. **0 = on the shelf from day one** (nothing is written to the profile for it). |
| `rentCost` | Paid every round. |
| `order` | Shelf sort order, low → high. Ties break by label. |
| `repeatable` | Can it be rented twice in one round? Ammo stacks; a gun doesn't. Default `false`. |
| `apply(player)` | **Server only.** Sets the per-run attributes. |
| `clear(player)` | **Server only.** Strips them. Must be idempotent — it runs on catch *and* at round end. |

`apply`/`clear` live in a shared module because the catalogue has to be
identical on both realms, but only `StoreService` ever calls them. The client
never applies anything.

## The round-summary section

`src/features/Store/RoundSummary.luau` declares Store's section on the
round-end board, discovered by `src/features/Maze/Summary.luau` — Maze never
names Store, exactly like Store never names Gun (see
[Escape.md](Escape.md#what-the-board-shows)).

Banking a haul is abstract: a number goes up. The section turns it into what
that number is *for* — which shelf items your new balance can unlock that it
could not before, or how much more you need for the cheapest one still locked.
That is the whole progression loop, stated at the moment it changes.

**It unlocks nothing.** Unlocks are still bought by hand at the shelf, so the
board can never claim a purchase the player did not make. Items that ship
unlocked (`unlockCost = 0`) and items already owned are skipped, since neither
is news.

## What ships today

| Item | Feature | Unlock | Rent | Effect |
| ---- | ------- | ------ | ---- | ------ |
| Sidearm | Gun | 0 | 60 | `HasGun = true`, `Ammo += 12` |
| Silencer | Gun | 400 | 90 | `HasSilencer = true` — shots summon no hunters, clip plays at 0.35 volume |
| Ammo box | Gun | 0 | 30 | `Ammo += 12` (repeatable) |
| Medkit | Health | 300 | 80 | `MedCharges += 1` (repeatable), spent with **H** |

Prices are a first pass and are meant to be retuned once a typical run's payout
is known — a full district-3 sweep is 100, the vault alone is 500. See
`Salvage/Constants.luau`.

**The Floodlight was removed, along with the whole Flashlight feature.** The
game runs in daylight (`ClockTime 14`, see [Atmosphere.md](Atmosphere.md)), so a
light source buys nothing — and a 250-cash unlock plus 40 a round that changes
nothing is worse than no option at all, because it reads as a real choice. If the
game ever moves back toward darkness, bring a light source back with it.

The **Silencer is deliberately the dearest thing on the shelf.** Every other
item widens what you can do; that one deletes a cost. Firing normally trades a
hunter's health for your position — every shot summons whoever hears it (see
[Gun.md](Gun.md#summon-trigger)) — and silenced, that trade stops existing. A
400 unlock keeps it out of a first round entirely, which is the point: it should
read as something you graduate into, not a starting option.

The **Map** from the extraction-loop plan is not built yet. It needs the maze
graph on the client, and `MazeNav.cellPos`/`adj` are populated server-side only,
so it needs graph replication before a minimap can be drawn.

## Server authority

Every purchase is a request. `StoreService` re-derives everything before a value
moves — the client's packet carries only an id and a rent/unlock flag.

Rejections, each sent back as a `BuyRejected` reason the shelf displays:

- id absent, empty, or over `MAX_ITEM_ID_LENGTH`, or not in the registry → dropped silently (and warned server-side)
- renting an item you haven't unlocked → *"Not unlocked"*
- renting a non-`repeatable` item you already hold → *"Already in your loadout"*
- unlocking something already unlocked, or with `unlockCost` 0 → *"Already unlocked"* / *"Already on the shelf"*
- balance below the price → *"Not enough cash"*

A player who can't afford a rent simply goes in without it. Nothing ever blocks
you from starting a round.

## Contracts

| Name | Owner | Meaning |
| ---- | ----- | ------- |
| `Ringfall.Cash` | profile | Permanent balance. Only `EscapeService` (banking) and `StoreService` (spending) write it. |
| `Ringfall.Unlocked[id]` | profile | Permanent access. Only `StoreService` writes it. |
| `Ringfall.BestHaul` | profile | Biggest single-round haul. Stat only. |
| `StoreRented` (player attr) | `StoreService` | Comma-joined ids rented this round. Replicates for free; the shelf reads it to grey out a second buy. |
| `RoundState` (workspace attr) | `EscapeService` | Entering `"Staging"` is when `StoreService` clears the round's rented bookkeeping. It does **not** gate trading. |
| `Caught` (player attr) | `HunterService` | `StoreService` watches it and strips rented kit. This is why Hunter doesn't have to know the shelf exists. |

## The terminal

`StoreService` builds it — the Store does **not** ask `MazeService` to place it,
and `MazeService` doesn't know it exists. It's positioned off the
`SpawnLocation`'s own CFrame (14 studs to its right, standing on the floor at
y = 0), parented into `workspace.Staging`, and tagged `StoreTerminal`.

`workspace.Staging` is `ClearAllChildren`'d on every maze rebuild, so the
terminal is rebuilt on `MazeGeneration` — bound **both** at `Start()` and to the
attribute-changed signal, because the first generation fires before any listener
can connect.

The client binds by **tag**, not by path, so a rebuilt terminal re-binds itself
with no rebuild hook on the client side.

No Studio assets are required: the terminal, its lit screen and its
`ProximityPrompt` are all code-built.

## Presentations

Two, and they're peers — neither knows about the other, and both route through
`StoreController`:

- **World** (`StoreWorldInteraction.client.luau`) — the terminal's prompt calls
  `StoreController.setOpen(true)`. While the window is open it watches the
  player's distance and closes at `CLOSE_RANGE` (18 studs); a centred window
  blocks the view, so leaving it pinned open while you run is worse than making
  you re-trigger the prompt.
- **Screen** (`StorePresentation.client.luau` → `UIRegistry.registerRoot`) — the
  shelf window itself. A *root* rather than a UIShell screen because the shelf
  isn't reached through HUD navigation; you walk up to it.

Gate either one with `Constants.Presentations`.

`StoreUI.ui.luau` is dumb: props in, intents out, no networking, no validation,
no persistence (enforced by `tools/check-views`). `StoreView.client.luau` is the
container that reads the replica and the attributes. `StoreUI.story.luau` renders
the three row states in UI Labs without a server.
