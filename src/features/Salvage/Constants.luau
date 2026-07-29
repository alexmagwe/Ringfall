--!strict
-- Plain .luau => ReplicatedStorage.Features.Salvage.Constants (shared realms).
return {
	FOLDER = "Salvage",
	DROPS_FOLDER = "Drops",
	FLOAT_Y = 3,

	-- Optional real art the user places in Studio, one child per `model` name
	-- below. Anything missing falls back to the coloured neon block this feature
	-- shipped with, so the game works before any art exists and each tier
	-- upgrades independently. Separate from Pickups' MODELS_FOLDER so salvage
	-- art and pickup art can be swapped without disturbing each other.
	MODELS_FOLDER = "SalvageModels", -- under ServerStorage

	-- Keyed by MazeNav district (3 = outer .. 1 = inner). Deeper = fewer, richer.
	-- The colour is not decoration: it IS the value tier, and it's how a player
	-- decides from down a corridor whether a piece is worth the detour. A
	-- realistic model still gets lit in its district colour for exactly that
	-- reason — see buildObject in SalvageService.
	--
	-- KEEP THESE SATURATED. Neon renders the raw Color3 at full brightness, so
	-- anything pale washes out to white — the original grey/pale-blue/lilac ramp
	-- read as three identical white cubes in game, which is exactly the tier
	-- signal this is supposed to carry. Green -> cyan -> violet all survive Neon
	-- and stay distinct from the amber of a death spill (DROP_COLOR below).
	--
	-- `model` names a child of ServerStorage.SalvageModels. Cheapest to richest:
	-- a tactical backpack, a duffel, a sealed briefcase.
	PER_DISTRICT = {
		[3] = { count = 10, value = 10, model = "Backpack", color = Color3.fromRGB(90, 200, 110) },
		[2] = { count = 8, value = 30, model = "DuffelBag", color = Color3.fromRGB(60, 170, 235) },
		[1] = { count = 6, value = 75, model = "Briefcase", color = Color3.fromRGB(190, 90, 245) },
	},
	PIECE_SIZE = 1.5, -- fallback block edge, studs
	PIECE_LIGHT_RANGE = 12,

	-- A death spill (SalvageService.dropHaul). Deliberately NOT one of the three
	-- salvage models — it stays the code-built amber block so that "someone died
	-- here" never reads the same as "nobody has been down here yet". Reusing a
	-- pack model would collapse the two into the same silhouette.
	DROP_COLOR = Color3.fromRGB(255, 200, 90),
	DROP_SIZE = 2,
	DROP_LIGHT_RANGE = 14,

	-- The vault, dropped as its own object. Also stays code-built: it is the one
	-- thing in the maze that must never be mistaken for loot. No PointLight —
	-- an occluded outline instead, so it's findable through the fog without
	-- lighting up the corridor and handing its position to everyone at once.
	VAULT_DROP_COLOR = Color3.fromRGB(20, 20, 22),
	VAULT_DROP_SIZE = 3,
	VAULT_DROP_OUTLINE = Color3.fromRGB(255, 195, 60),
	-- A theoretically perfect sweep of every piece is 100+240+450 = 790, but that
	-- means visiting all 24 cells across all three districts, and the round ends
	-- the moment anyone extracts the vault — so nobody gets to finish one. The
	-- vault is a single touch worth 500, which beats any realistic sweep while
	-- staying under the impossible maximum: committing to it is tempting, not
	-- automatic. Re-check this against PER_DISTRICT if you retune either.
	VAULT_VALUE = 500,
	ALARM_REFRESH = 1.0,
}
