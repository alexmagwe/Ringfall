--!strict
-- Plain .luau => ReplicatedStorage.Features.Health.Constants (shared realms).
return {
	MAX_HEALTH = 100,
	-- How much one stored medkit charge restores. Charges come from the shelf
	-- (src/features/Health/Store.luau) and live on the per-run `MedCharges`
	-- attribute, so they die with you like everything else carried.
	MEDKIT_HEAL = 50,
}
