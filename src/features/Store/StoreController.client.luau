--!strict
-- Client surface for the shelf. Owns the window's open/closed state and the two
-- purchase intents; sends both as requests and applies nothing locally — the
-- server is the only thing that moves cash, and the replica diff is what the UI
-- re-renders from.
--
-- Every presentation routes through here: the terminal's ProximityPrompt
-- (StoreWorldInteraction) opens the window, the window (StoreView) spends.
--
-- Auto-loaded: name ends in `Controller`.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Store.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Packages.Signal)

-- Required for its side effect: see StoreService.server.luau for the full
-- explanation. Submodule requires alone don't run Store/init.luau's
-- auto-discovery, so the client's catalogue would otherwise be empty.
require(ReplicatedStorage.Features.Store)

local Packets = require(ReplicatedStorage.Features.Store.Packets)

local StoreController = {}

-- Fires with the new open state whenever the window opens or closes.
StoreController.OpenChanged = Signal.new()
-- Fires with (id, reason) when the server bounces a purchase.
StoreController.Rejected = Signal.new()

local open = false

function StoreController.isOpen(): boolean
	return open
end

function StoreController.setOpen(next: boolean)
	if typeof(next) ~= "boolean" or open == next then
		return
	end
	open = next
	StoreController.OpenChanged:Fire(open)
end

-- Intent: pay the permanent unlock price for an item.
function StoreController.unlock(id: string)
	if typeof(id) ~= "string" then
		return
	end
	Packets.Buy.send({ id = id, rent = false })
end

-- Intent: pay the per-run rent and take the item into this round.
function StoreController.rent(id: string)
	if typeof(id) ~= "string" then
		return
	end
	Packets.Buy.send({ id = id, rent = true })
end

function StoreController.Start()
	Packets.BuyRejected.listen(function(payload: { id: string, reason: string })
		StoreController.Rejected:Fire(payload.id, payload.reason)
	end)

	-- No round-state close: the shelf trades mid-run too. Walking away from the
	-- terminal is what closes it (StoreWorldInteraction watches the distance),
	-- which is the right signal either way — you can't be running the maze
	-- behind a centred window if the window shuts when you leave the room.
end

return StoreController
