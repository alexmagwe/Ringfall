-- Shared packet definitions for the Gun feature. Mirrors Maze/Net.luau's shape:
-- one packet per event, ByteNet handles (de)serialization and reliability.
--
-- The client packet is a REQUEST only — GunService re-raycasts from the
-- character and validates HasGun/Ammo/cooldown server-side. Never trust the
-- client-reported origin or hit.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Gun.Net.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("Gun", function()
	return {
		-- Client -> Server: fire request. `origin` is informational only (the
		-- camera position at the moment of the click); the server raycasts from
		-- the character's own position, not this value.
		Shoot = ByteNet.definePacket({
			value = ByteNet.struct({
				origin = ByteNet.vec3, -- camera position (informational)
				direction = ByteNet.vec3, -- unit aim direction
			}),
			reliabilityType = "reliable",
		}),
	}
end)
