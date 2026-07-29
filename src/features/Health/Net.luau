-- Shared packet definitions for the Health feature. Mirrors Gun/Net.luau's
-- shape: one packet per event, ByteNet handles (de)serialization.
--
-- The client packet is a REQUEST only — HealthService re-checks that the player
-- actually holds a charge and is actually hurt before spending anything. Never
-- trust the client to say it healed.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Health.Net.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("Health", function()
	return {
		-- Client -> Server: spend one stored medkit charge.
		UseMedkit = ByteNet.definePacket({
			value = ByteNet.nothing,
			reliabilityType = "reliable",
		}),
	}
end)
