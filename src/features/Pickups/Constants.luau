--!strict
-- Plain .luau => ReplicatedStorage.Features.Pickups.Constants (shared realms).
return {
	FOLDER = "Pickups", -- workspace folder the feature owns
	-- Optional real models the user places in Studio, one child per kind named
	-- "Ammo" / "Stamina" / "Emergency MedKit". A neon ball stands
	-- in per kind that has no model, so the feature works before any art exists.
	-- Two things that were once pickups no longer appear in SPAWNS: the Compass
	-- is standard equipment (see docs/game/Salvage.md), and the gun is rented
	-- from the shelf (see below). Their art can stay in the folder unused.
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
	-- The GUN IS NOT SCATTERED. It used to be — one `GatlingLaser` per round — and
	-- that made the shelf's Sidearm a convenience rather than a decision: why
	-- rent one for 60 when the maze hands you the same attribute for free? Being
	-- armed is now something you pay for before the round starts, which is what
	-- the whole rent-and-lose-it economy is built around.
	--
	-- `PickupsService.grant` still handles `kind = "Gun"`, and `GUN_START_AMMO`
	-- is still here. That is the mechanism, not the content: re-scattering guns
	-- is one line back in this table, and gutting the grant would turn that line
	-- into a silent no-op instead.
	SPAWNS = {
		-- Ammo stays scattered. It is worth finding precisely BECAUSE the gun is
		-- rented — a magazine you did not pay for extends a weapon you did.
		{ kind = "Ammo", model = "Ammo", count = 4, color = Color3.fromRGB(240, 130, 60), amount = 6 },
		-- `scaleTo` because the art is a 0.2 x 0.4 x 0.2 union — a fifth of a stud,
		-- floating three studs up in a forty-stud corridor. It was not small, it
		-- was invisible. 3 puts it at about half a character's height, in the
		-- same family as the 6-stud ammo crate without pretending a cell is a box.
		{
			kind = "Stamina",
			model = "StaminaBoost",
			count = 1,
			color = Color3.fromRGB(120, 230, 150),
			amount = 50,
			scaleTo = 3,
		},
		{ kind = "HealthKit", model = "Emergency MedKit", count = 3, color = Color3.fromRGB(230, 70, 70), amount = 50 },
	},
	-- Granted alongside `HasGun` by `grant`. Unreferenced by SPAWNS today, since
	-- the gun is not scattered — kept because it is half of that grant, not a
	-- spawn setting.
	GUN_START_AMMO = 12,
}
