--!strict
-- Skateboard's row in the carried-kit strip. Picked up by the Loadout feature's
-- auto-discovery; Loadout never names Skateboard.
--
-- Two states in one row rather than two slots: you cannot be riding a board you
-- do not hold, so a second row would only ever be a duplicate of this one.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Skateboard.Loadout.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Features.Skateboard.Constants)

return function(Loadout)
	Loadout.registerSlot({
		id = "skateboard.ride",
		order = 40,
		watch = { Constants.HAS_ATTRIBUTE, Constants.RIDING_ATTRIBUTE },
		color = Color3.fromRGB(235, 170, 60),
		text = function(player: Player): string?
			if player:GetAttribute(Constants.HAS_ATTRIBUTE) ~= true then
				return nil
			end
			local riding = player:GetAttribute(Constants.RIDING_ATTRIBUTE) == true
			return if riding then "RIDING   [R] STEP OFF" else "SKATEBOARD   [R]"
		end,
	})
end
