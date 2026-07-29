--!nonstrict
-- UI Labs story for the shelf. Slide the balance to watch buttons enable and
-- disable, flip the toggles to see the three row states (locked / rentable /
-- already in the loadout) and the staging-only lockout.
--
-- StoreUI is a dumb view (see docs/game/headless-core.md), so mock items are
-- enough — no live replica, no server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UILabs = require(ReplicatedStorage.Packages.UILabs)
local StoreUI = require(ReplicatedStorage.Features.Store.StoreUI)

local noop = function() end

local MOCK_ITEMS = {
	{
		id = "gun.sidearm",
		label = "Sidearm",
		description = "A gun and twelve rounds. Hunters take one damage a hit.",
		unlockCost = 0,
		rentCost = 60,
		order = 10,
		apply = noop,
		clear = noop,
	},
	{
		id = "gun.ammo",
		label = "Ammo box",
		description = "Twelve more rounds. Stacks — buy as many as you can fund.",
		unlockCost = 0,
		rentCost = 30,
		order = 20,
		repeatable = true,
		apply = noop,
		clear = noop,
	},
	{
		id = "flashlight.floodlight",
		label = "Floodlight",
		description = "A far wider, brighter beam for the run.",
		unlockCost = 250,
		rentCost = 40,
		order = 30,
		apply = noop,
		clear = noop,
	},
	{
		id = "health.medkit",
		label = "Medkit",
		description = "One stored charge. Press H to spend it.",
		unlockCost = 300,
		rentCost = 80,
		order = 40,
		repeatable = true,
		apply = noop,
		clear = noop,
	},
}

return {
	summary = "The staging-room shelf — permanent unlocks, per-run rentals.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		cash = UILabs.Slider(320, 0, 3000, 10),
		floodlightUnlocked = false,
		sidearmRented = false,
		inStaging = true,
		showRejection = false,
	},

	story = function(props)
		local c = props.controls
		return React.createElement(StoreUI, {
			items = MOCK_ITEMS,
			cash = c.cash,
			unlocked = { ["flashlight.floodlight"] = c.floodlightUnlocked },
			rented = { ["gun.sidearm"] = c.sidearmRented },
			canBuy = c.inStaging,
			notice = if c.showRejection then "Not enough cash" else nil,
			onUnlock = noop,
			onRent = noop,
			onClose = noop,
		})
	end,
}
