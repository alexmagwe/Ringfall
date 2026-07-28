--!strict
-- Pure/dumb React component for the round-results board. Owns no networking —
-- UIController mounts this when it hears the RoundEnded packet and unmounts it
-- when the next round's countdown starts. Follows the Notes feature's
-- `.ui.luau` shape (createElement style, ui.* primitives, no data fetching).
--
-- There is no button: rounds restart automatically (see docs/game/Escape.md),
-- so this is a passive scoreboard that dismisses itself. Full-screen dim
-- overlay + a centered dark ui.Panel, per CLAUDE.md's centre-by-default rule.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui

local PANEL_SIZE = UDim2.fromOffset(560, 420)
local TITLE_TEXT_SIZE = 56
local WINNER_TEXT_SIZE = 28
local ROW_TEXT_SIZE = 22
local ROW_HEIGHT = 30
local WINNER_COLOR = Color3.fromRGB(120, 230, 150)
local YOU_COLOR = Color3.fromRGB(255, 220, 130)
local ROW_COLOR = Color3.fromRGB(200, 208, 216)

export type HaulRow = { name: string, haul: number }

type Props = {
	winnerName: string,
	hauls: { HaulRow },
	-- Local player's name, so their row can be picked out of the list.
	localName: string,
}

return function(props: Props)
	-- Highest haul first; the scoreboard reads as a ranking.
	local rows = table.clone(props.hauls)
	table.sort(rows, function(a, b)
		return a.haul > b.haul
	end)

	-- One children table: react-lua's createElement takes children as a single
	-- keyed table, so the rows are merged in here rather than passed separately.
	local children: { [string]: any } = {
		UIListLayout = React.createElement("UIListLayout", {
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			FillDirection = Enum.FillDirection.Vertical,
		}),

		Title = React.createElement(ui.Text, {
			text = "VAULT EXTRACTED",
			textSize = TITLE_TEXT_SIZE,
			weight = Enum.FontWeight.Heavy,
			shadow = true,
			size = UDim2.new(1, 0, 0, TITLE_TEXT_SIZE + 10),
			layoutOrder = 1,
		}),

		Winner = React.createElement(ui.Text, {
			text = props.winnerName .. " got out with it",
			textSize = WINNER_TEXT_SIZE,
			weight = Enum.FontWeight.Bold,
			color = WINNER_COLOR,
			size = UDim2.new(1, 0, 0, WINNER_TEXT_SIZE + 8),
			layoutOrder = 2,
		}),

		Banked = React.createElement(ui.Text, {
			text = "BANKED THIS ROUND",
			textSize = ROW_TEXT_SIZE,
			color = ROW_COLOR,
			size = UDim2.new(1, 0, 0, ROW_TEXT_SIZE + 14),
			layoutOrder = 9,
		}),
	}

	for i, row in rows do
		local isYou = row.name == props.localName
		children["Row" .. i] = React.createElement(ui.Text, {
			text = string.format("%s   %d", row.name, row.haul),
			textSize = ROW_TEXT_SIZE,
			color = if isYou then YOU_COLOR else ROW_COLOR,
			weight = if isYou then Enum.FontWeight.Bold else Enum.FontWeight.Regular,
			size = UDim2.new(1, 0, 0, ROW_HEIGHT),
			layoutOrder = 10 + i,
		})
	end

	return React.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 100,
	}, {
		Panel = React.createElement(ui.Panel, {
			size = PANEL_SIZE,
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
		}, children),
	})
end
