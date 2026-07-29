-- Shared packet definitions for the Store feature. Both server (StoreService)
-- and client (StoreController) import this module.
--
-- The Buy packet is a REQUEST only. StoreService re-checks the registry, the
-- round state, ownership and the balance before anything is spent — same
-- discipline as GunService validating shots. Never trust a client-sent buy.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Store.Packets.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage.Packages.ByteNet)

return ByteNet.defineNamespace("Store", function()
	return {
		-- Client -> Server: purchase request.
		Buy = ByteNet.definePacket({
			value = ByteNet.struct({
				id = ByteNet.string,
				-- false = pay the permanent unlock price.
				-- true  = pay the per-run rent and take the item into this round.
				rent = ByteNet.bool,
			}),
			reliabilityType = "reliable",
		}),

		-- Server -> Client: why a purchase bounced, so the shelf can say so
		-- instead of the button silently doing nothing.
		BuyRejected = ByteNet.definePacket({
			value = ByteNet.struct({
				id = ByteNet.string,
				reason = ByteNet.string,
			}),
			reliabilityType = "reliable",
		}),
	}
end)
