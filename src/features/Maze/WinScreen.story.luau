--!nonstrict
-- UI Labs story for the escape win screen. Toggle `isNewBest` and slide the
-- times to check both stamp states render without the layout jumping or text
-- clipping (WinScreen is a dumb view — see docs/game/headless-core.md).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UILabs = require(ReplicatedStorage.Packages.UILabs)
local WinScreen = require(ReplicatedStorage.Features.Maze.WinScreen)

return {
	summary = "Escape win screen — time, personal best, and the NEW BEST stamp.",
	react = React,
	reactRoblox = ReactRoblox,

	controls = {
		isNewBest = false,
		timeSeconds = UILabs.Slider(42.3, 0, 300, 0.1),
		bestSeconds = UILabs.Slider(38.1, 0, 300, 0.1),
	},

	story = function(props)
		local c = props.controls
		return React.createElement(WinScreen, {
			timeSeconds = c.timeSeconds,
			bestSeconds = c.bestSeconds,
			isNewBest = c.isNewBest,
			onRestart = function() end,
		})
	end,
}
