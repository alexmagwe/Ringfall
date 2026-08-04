--!strict
-- Shared packet definitions for the Skateboard feature. Same shape as
-- Health/Net.luau: one packet, and it is a REQUEST only.
--
-- The client asks to get on or off; SkateboardService decides. It re-checks
-- that the player actually holds a board and is actually standing somewhere the
-- board rolls before granting the speed — the client is never trusted to say it
-- is riding, because riding is a speed multiplier and that is exactly what a
-- speed exploit would want to claim.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Skateboard.Net.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("Skateboard", function()
	return {
		-- Client -> Server: toggle the ride. No payload — the server owns the
		-- current state, so it knows which way the toggle goes.
		ToggleRide = ByteNet.definePacket({
			value = ByteNet.nothing,
			reliabilityType = "reliable",
		}),
	}
end)
