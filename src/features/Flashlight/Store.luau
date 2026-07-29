--!strict
-- Flashlight's entry on the staging-room shelf. Picked up by the Store
-- feature's auto-discovery; Store never names Flashlight.
--
-- The first item with a real unlock price: a genuine investment to put on the
-- shelf, and still a per-round cost to take in. It widens what you can see, not
-- what you can survive — options, not power.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Flashlight.Store.

return function(Store)
	Store.registerItem({
		id = "flashlight.floodlight",
		label = "Floodlight",
		description = "A far wider, brighter beam for the run.",
		unlockCost = 250,
		rentCost = 40,
		order = 30,
		apply = function(player: Player)
			player:SetAttribute("HasFlashlight", true)
		end,
		clear = function(player: Player)
			player:SetAttribute("HasFlashlight", nil)
		end,
	})
end
