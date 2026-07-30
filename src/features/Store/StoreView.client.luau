--!strict
-- Stateful container that wires the pure StoreUI to live data:
--   • StoreController.OpenChanged  — whether the window is on screen at all
--   • Registry.Changed             — new items appear without a remount
--   • useReplica(…, "Ringfall")    — Cash + Unlocked (permanent, persisted)
--   • the StoreRented attribute    — what's already in this round's loadout
--   • StoreController.Rejected     — the server's reason a buy bounced
--
-- Mounted as a root by StorePresentation.client.luau. Dumb by the headless-core
-- rule: it reads state and calls StoreController intents, nothing else.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Boil = require(ReplicatedStorage.Shared.Boil)

local Constants = require(ReplicatedStorage.Features.Store.Constants)
local Registry = require(ReplicatedStorage.Features.Store.Registry)
local StoreUI = require(ReplicatedStorage.Features.Store.StoreUI)

-- Client-realm siblings (StarterPlayerScripts.Features tree).
local StoreController = require(script.Parent.StoreController)
local PlayerDataController = require(script.Parent.Parent.PlayerData.PlayerDataController)

-- Subscribes to the catalogue's Changed signal and returns its current list().
-- Forces a re-render via a version counter, same shape as SettingsView's
-- useRegistrySections.
local function useCatalogue(): { Registry.Item }
	local _, setVersion = React.useState(0)
	React.useEffect(function()
		local conn = Registry.Changed:Connect(function()
			setVersion(function(v: number): number
				return v + 1
			end)
		end)
		return function()
			conn:Disconnect()
		end
	end, {})
	return Registry.list()
end

-- The comma-joined StoreRented attribute, exploded into a set. Server-written
-- and replicated, so no packet is needed to know what's already in the loadout.
local function useRentedSet(): { [string]: boolean }
	local player = Players.LocalPlayer
	local raw, setRaw = React.useState(player:GetAttribute(Constants.RENTED_ATTRIBUTE))
	React.useEffect(function()
		local conn = player:GetAttributeChangedSignal(Constants.RENTED_ATTRIBUTE):Connect(function()
			setRaw(player:GetAttribute(Constants.RENTED_ATTRIBUTE))
		end)
		setRaw(player:GetAttribute(Constants.RENTED_ATTRIBUTE))
		return function()
			conn:Disconnect()
		end
	end, {})

	local set: { [string]: boolean } = {}
	if typeof(raw) ~= "string" or raw == "" then
		return set
	end
	for _, id in string.split(raw, ",") do
		if id ~= "" then
			set[id] = true
		end
	end
	return set
end

return function()
	local open, setOpen = React.useState(StoreController.isOpen())
	React.useEffect(function()
		local conn = StoreController.OpenChanged:Connect(function(next: boolean)
			setOpen(next)
		end)
		return function()
			conn:Disconnect()
		end
	end, {})

	local notice, setNotice = React.useState(nil :: string?)
	React.useEffect(function()
		local conn = StoreController.Rejected:Connect(function(_id: string, reason: string)
			setNotice(reason)
			-- Clear on the timeout, but only if the same message is still up —
			-- don't stomp a newer rejection with an older timer.
			task.delay(Constants.NOTICE_SECONDS, function()
				setNotice(function(current: string?): string?
					return if current == reason then nil else current
				end)
			end)
		end)
		return function()
			conn:Disconnect()
		end
	end, {})

	local items = useCatalogue()
	local rented = useRentedSet()
	local profile = Boil.useReplica(PlayerDataController, Constants.PROFILE_KEY) or {}

	-- Every hook above runs unconditionally; the window is simply not drawn when
	-- it's closed.
	if not open then
		return nil
	end

	return React.createElement(StoreUI, {
		items = items,
		cash = if typeof(profile.Cash) == "number" then profile.Cash else 0,
		unlocked = if typeof(profile.Unlocked) == "table" then profile.Unlocked else {},
		rented = rented,
		notice = notice,
		onUnlock = StoreController.unlock,
		onRent = StoreController.rent,
		onClose = function()
			StoreController.setOpen(false)
		end,
	})
end
