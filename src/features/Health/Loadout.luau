--!strict
-- Health's row in the carried-kit strip. Picked up by the Loadout feature's
-- auto-discovery; Loadout never names Health.
--
-- This row used to be a bespoke label at the bottom LEFT — directly underneath
-- the controls legend, which sizes to its content. Every new keybind grew the
-- legend downward until the medkit line was drawn inside its panel and could
-- not be read at all. Carrying a medkit was unknowable.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Health.Loadout.

return function(Loadout)
	Loadout.registerSlot({
		id = "health.medkit",
		order = 20,
		watch = { "MedCharges" },
		color = Color3.fromRGB(235, 120, 120),
		flashOn = "MedCharges",
		text = function(player: Player): string?
			local charges = player:GetAttribute("MedCharges")
			local count = if typeof(charges) == "number" then charges else 0
			-- nil hides the row: with no charges there is nothing to say.
			return if count > 0 then string.format("MEDKIT x%d   [H]", count) else nil
		end,
	})
end
