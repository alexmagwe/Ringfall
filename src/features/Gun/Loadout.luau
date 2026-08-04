--!strict
-- Gun's row in the carried-kit strip. Picked up by the Loadout feature's
-- auto-discovery; Loadout never names Gun.
--
-- Hidden when unarmed rather than reading "AMMO 0": a readout of nothing spends
-- a row saying only that you did not rent a gun, which you know.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Gun.Loadout.

return function(Loadout)
	Loadout.registerSlot({
		id = "gun.ammo",
		order = 10,
		watch = { "Ammo", "HasGun" },
		flashOn = "Ammo",
		text = function(player: Player): string?
			if player:GetAttribute("HasGun") ~= true then
				return nil
			end
			local ammo = player:GetAttribute("Ammo")
			return string.format("AMMO %d", if typeof(ammo) == "number" then ammo else 0)
		end,
	})
end
