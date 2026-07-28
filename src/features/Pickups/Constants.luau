--!strict
-- Plain .luau => ReplicatedStorage.Features.Pickups.Constants (shared realms).
return {
	FOLDER = "Pickups", -- workspace folder the feature owns
	-- Optional real models the user places in Studio, one child per kind named
	-- "Gun" / "Ammo" / "Stamina" / "Flashlight" / "Emergency MedKit". A neon ball
	-- stands in per kind that has no model, so the feature works before any art
	-- exists. (The Compass is standard equipment now, not a pickup — see
	-- docs/game/Salvage.md — so it's no longer in SPAWNS.)
	MODELS_FOLDER = "PickupModels", -- under ServerStorage
	FLOAT_Y = 3, -- studs above the floor cell centre
	SPIN_DPS = 60, -- visual spin, client-side
	-- What each round scatters. `count` distinct random cells per kind.
	-- `model` names the child under ServerStorage.PickupModels to clone for this
	-- kind (decoupled from `kind` so the art can be named anything). Missing model
	-- => neon-ball fallback. `minBand`/`maxBand` (inclusive) and `minSpawnDist`
	-- (studs from SpawnLocation) are optional placement constraints — see
	-- PickupsService.scatter for how they're applied (falls back to the
	-- unconstrained pool if the constraint leaves no candidate cells, so a kind
	-- never fails to place).
	SPAWNS = {
		{ kind = "Gun", model = "GatlingLaser", count = 1, color = Color3.fromRGB(230, 180, 60) },
		{ kind = "Ammo", model = "Ammo", count = 4, color = Color3.fromRGB(240, 130, 60), amount = 6 },
		{ kind = "Stamina", model = "StaminaBoost", count = 1, color = Color3.fromRGB(120, 230, 150), amount = 50 },
		{ kind = "Flashlight", model = "Flashlight", count = 1, color = Color3.fromRGB(255, 245, 200) },
		{ kind = "HealthKit", model = "Emergency MedKit", count = 3, color = Color3.fromRGB(230, 70, 70), amount = 50 },
	},
	GUN_START_AMMO = 12, -- the Gun pickup also grants this much ammo
}
