-- The Ringfall game profile slice. Discovered by
-- src/features/PlayerData/init.luau at load time.
--
-- Everything in here is PERMANENT. Banked `Cash` and `Unlocked` store items
-- survive death, a lost round, and a rejoin — only per-run *attributes* (Haul,
-- HasVault, rented kit) are ever at risk. That split is the whole economy:
-- "banked is safe, carried is at risk". See docs/game/Store.md.
--
-- The Store feature reads Cash/Unlocked through this same key
-- (Store/Constants.PROFILE_KEY) without requiring anything from Maze; the key
-- name is the only thing the two share.

return function(PlayerData)
	PlayerData.registerTemplate("Ringfall", {
		BestTimeSeconds = 0,
		-- Biggest single-round haul banked. Stat only; nothing spends it.
		BestHaul = 0,
		Cash = 0,
		-- store item id -> true. Permanent *access*, not power: you still rent
		-- the item into each run and still lose it when you die.
		Unlocked = {},
	})
end
