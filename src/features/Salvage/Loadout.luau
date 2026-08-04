--!strict
-- Salvage's row in the carried-kit strip. Picked up by the Loadout feature's
-- auto-discovery; Loadout never names Salvage.
--
-- It shared the bottom-right corner with the gun's ammo readout and the two
-- overlapped: both were anchored to the same corner a few pixels apart, so a
-- player who was both armed and carrying read one line through the other.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Salvage.Loadout.

return function(Loadout)
	Loadout.registerSlot({
		id = "salvage.haul",
		order = 50, -- last: the number the run is actually about sits closest to the corner
		watch = { "Haul" },
		color = Color3.fromRGB(255, 214, 120),
		flashOn = "Haul",
		text = function(player: Player): string?
			local haul = player:GetAttribute("Haul")
			local amount = if typeof(haul) == "number" then haul else 0
			-- Hidden until the run starts paying; "HAUL 0" is a readout of nothing.
			return if amount > 0 then string.format("HAUL %d", amount) else nil
		end,
	})
end
