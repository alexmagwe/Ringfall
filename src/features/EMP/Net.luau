--!strict
-- Shared packet definitions for the EMP. Same shape as Gun/Net.luau, and a
-- REQUEST only for the same reason: the client says where it was pointing, and
-- EMPService re-raycasts from the character and re-checks the charge and the
-- cooldown. A client that could assert a burst could disable the whole district
-- for free.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.EMP.Net.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("EMP", function()
	return {
		-- Client -> Server: fire request. `direction` is the unit aim vector from
		-- the cursor; the server owns the origin and the range.
		Fire = ByteNet.definePacket({
			value = ByteNet.struct({
				direction = ByteNet.vec3,
			}),
			reliabilityType = "reliable",
		}),
	}
end)
