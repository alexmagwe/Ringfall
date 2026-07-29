--!strict
-- Health's entry on the staging-room shelf. Picked up by the Store feature's
-- auto-discovery; Store never names Health.
--
-- One stored charge, spent when you choose (see Controls.luau for the key).
-- Repeatable, so a rich round can go in with several — the ceiling is your
-- balance, not a rule.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Health.Store.

return function(Store)
	Store.registerItem({
		id = "health.medkit",
		label = "Medkit",
		description = "One stored charge. Press H to spend it.",
		unlockCost = 300,
		rentCost = 80,
		order = 40,
		repeatable = true,
		apply = function(player: Player)
			player:SetAttribute("MedCharges", (player:GetAttribute("MedCharges") or 0) + 1)
		end,
		clear = function(player: Player)
			player:SetAttribute("MedCharges", nil)
		end,
	})
end
