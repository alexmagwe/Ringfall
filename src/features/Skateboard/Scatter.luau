--!strict
-- Skateboard's entry in the maze scatter. Picked up by the Pickups feature's
-- auto-discovery (Pickups/Scatter.luau); Pickups never names Skateboard.
--
-- ONE PER ROUND, and deliberately out in the outer bands: the board is a reward
-- for the leg of the run you have to do on foot anyway, and finding it deep
-- would hand you a speed boost for a journey that is already nearly over.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Skateboard.Scatter.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Features.Skateboard.Constants)

return function(Scatter)
	Scatter.registerSpawn({
		kind = "Skateboard",
		model = Constants.MODEL_NAME,
		count = 1,
		color = Constants.TRIM_COLOR,
		label = "SKATEBOARD  [R] TO RIDE",
		-- Bands 7+ = the middle and outer districts. Not band 10+: the outer
		-- district is the grass one, so a board that only ever spawned out there
		-- would be found exactly where it cannot be used.
		minBand = 7,
		-- Far enough out that it is never sitting in sight of the door.
		minSpawnDist = 120,
		grant = function(player: Player)
			player:SetAttribute(Constants.HAS_ATTRIBUTE, true)
		end,
		-- Caught = you drop it, same as every other thing you were carrying.
		--
		-- ONLY the "do you hold one" attribute. The ride itself is
		-- SkateboardService's state, and it tears itself down off this
		-- attribute disappearing — clearing it from here as well meant Pickups
		-- won the race, the service saw nothing left to do, and the speed
		-- multiplier outlived the board.
		clearOnCatch = { Constants.HAS_ATTRIBUTE },
	})
end
