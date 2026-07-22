-- Crouch state channel. The client owns the input; it tells the server when the
-- player crouches so the Hunter (server) can treat a crouched-behind-cover player
-- as hidden. Server writes it to the `Crouched` player attribute.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Stealth.StealthNet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("Stealth", function()
	return {
		-- Client -> Server: the local player's crouch state changed.
		Crouch = ByteNet.definePacket({
			value = ByteNet.bool,
			reliabilityType = "reliable",
		}),
	}
end)
