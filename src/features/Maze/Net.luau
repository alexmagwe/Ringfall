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

		-- Server -> Client: legacy per-player win packet. Nothing sends this
		-- anymore -- extraction is server-wide now (see RoundEnded below) --
		-- kept only so old client code referencing it doesn't error.
		Escaped = ByteNet.definePacket({
			value = ByteNet.struct({
				timeSeconds = ByteNet.float32,
				bestSeconds = ByteNet.float32, -- 0 = no previous best
				isNewBest = ByteNet.bool,
			}),
			reliabilityType = "reliable",
		}),

		-- Client -> Server: "CONTINUE" on the round-summary board. The round is
		-- held at the end of a run until every player has sent this (or the
		-- server's patience runs out) — see EscapeService. Sending it twice is
		-- harmless; the server tracks a set, not a count.
		Continue = ByteNet.definePacket({
			value = ByteNet.nothing,
			reliabilityType = "reliable",
		}),

		-- Server -> Client (broadcast): the round's Staging/Active state, so a
		-- future HUD can show the staging countdown. `secondsRemaining` is only
		-- meaningful during "Staging".
		RoundState = ByteNet.definePacket({
			value = ByteNet.struct({
				state = ByteNet.string,
				secondsRemaining = ByteNet.uint8,
			}),
			reliabilityType = "reliable",
		}),

		-- Server -> Client (broadcast): fired when the vault reaches the
		-- extract pad. Carries the winner (the carrier who extracted) and
		-- every player's banked haul for the round just ended.
		RoundEnded = ByteNet.definePacket({
			value = ByteNet.struct({
				winnerName = ByteNet.string,
				hauls = ByteNet.array(ByteNet.struct({
					name = ByteNet.string,
					haul = ByteNet.uint32,
				})),
			}),
			reliabilityType = "reliable",
		}),
	}
end)
