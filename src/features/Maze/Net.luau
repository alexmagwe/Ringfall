-- Shared packet definitions for the Maze escape round. Both server
-- (EscapeService) and client (UIController) import this module. Follows the
-- same shape as the Notes/Settings features' Packets.luau — one packet per
-- event, ByteNet handles (de)serialization and reliability.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Maze.Net.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("Maze", function()
	return {
		-- Server -> Client: fired the first time a player's character leaves
		-- the spawn zone; tells the client to start its timer display.
		RunStarted = ByteNet.definePacket({
			value = ByteNet.nothing,
			reliabilityType = "reliable",
		}),

		-- Server -> Client: fired when the player touches ExitGate. Carries
		-- the authoritative elapsed time (server clock, not client-guessed).
		Escaped = ByteNet.definePacket({
			value = ByteNet.struct({
				timeSeconds = ByteNet.float32,
			}),
			reliabilityType = "reliable",
		}),

		-- Client -> Server: "RUN IT BACK" button. Server unanchors, teleports
		-- to spawn, and resets round state.
		Restart = ByteNet.definePacket({
			value = ByteNet.nothing,
			reliabilityType = "reliable",
		}),
	}
end)
