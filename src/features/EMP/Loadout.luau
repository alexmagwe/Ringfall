--!strict
-- EMP's row in the carried-kit strip. Picked up by the Loadout feature's
-- auto-discovery; Loadout never names EMP.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.EMP.Loadout.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Features.EMP.Constants)

return function(Loadout)
	Loadout.registerSlot({
		id = "emp.charges",
		order = 30,
		watch = { Constants.CHARGES_ATTRIBUTE },
		color = Constants.COLOR,
		flashOn = Constants.CHARGES_ATTRIBUTE,
		text = function(player: Player): string?
			local charges = player:GetAttribute(Constants.CHARGES_ATTRIBUTE)
			local count = if typeof(charges) == "number" then charges else 0
			return if count > 0 then string.format("EMP x%d   [F]", count) else nil
		end,
	})
end
