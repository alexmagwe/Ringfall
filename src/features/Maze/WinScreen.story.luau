--!nonstrict
-- UI Labs story for the round-results board. Slide the hauls to check the
-- ranking sorts highest-first and that the local player's row highlights
-- (WinScreen is a dumb view — see docs/game/headless-core.md).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UILabs = require(ReplicatedStorage.Packages.UILabs)
local WinScreen = require(ReplicatedStorage.Features.Maze.WinScreen)

return {
	summary = "Round-results board — winner and every player's banked haul.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		yourHaul = UILabs.Slider(320, 0, 2000, 10),
		rivalHaul = UILabs.Slider(880, 0, 2000, 10),
		youWon = false,
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
		})
	end,
}
