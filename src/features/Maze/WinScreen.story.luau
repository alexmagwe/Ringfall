--!nonstrict
-- UI Labs story for the round-results board. Slide the hauls to check the
-- ranking sorts highest-first and that the local player's row highlights
-- (WinScreen is a dumb view — see docs/game/headless-core.md).
--
-- `cash` drives the feature-registered sections, which read the profile rather
-- than props: slide it past a shelf item's unlockCost and Store's section
-- should switch from "N to go" to listing what you can now unlock. That is the
-- cheapest way to check a section without playing a whole round.
--
-- `pressed` fakes the state after CONTINUE: the button becomes a waiting line,
-- because the server holds the round until every player has pressed it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UILabs = require(ReplicatedStorage.Packages.UILabs)
local WinScreen = require(ReplicatedStorage.Features.Maze.WinScreen)

return {
	summary = "Round-results board — winner, your take, feature sections, CONTINUE.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		yourHaul = UILabs.Slider(320, 0, 2000, 10),
		rivalHaul = UILabs.Slider(880, 0, 2000, 10),
		cash = UILabs.Slider(280, 0, 2000, 10),
		youWon = false,
		pressed = false,
	},

	story = function(props)
		local c = props.controls
		return React.createElement(WinScreen, {
			winnerName = if c.youWon then "You" else "Runner_47",
			hauls = {
				{ name = "You", haul = c.yourHaul },
				{ name = "Runner_47", haul = c.rivalHaul },
				{ name = "Runner_12", haul = 90 },
			},
			localName = "You",
			profile = { Cash = c.cash, BestHaul = 640, Unlocked = {} },
			onContinue = if c.pressed
				then nil
				else function()
					print("[WinScreen.story] CONTINUE")
				end,
		})
	end,
}
