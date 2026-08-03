--!strict
-- Pure/dumb React component for the round-results board. Owns no networking —
-- UIController mounts this when it hears the RoundEnded packet and unmounts it
-- when the next round's countdown starts. Follows the Notes feature's
-- `.ui.luau` shape (createElement style, ui.* primitives, no data fetching).
--
-- IT HAS A BUTTON, and the round waits for it (see docs/game/Escape.md). Rounds
-- used to restart on their own, which meant this board appeared and was wiped
-- by the next countdown a frame later — a result nobody could read. Nothing
-- rebuilds until every player presses CONTINUE, so the board can take its time.
--
-- Sections below the scoreboard are NOT written here. Features declare their own
-- through Summary.registerSection (see Summary.luau) — Store contributes what
-- the shelf will now sell you — so this file never learns what another feature
-- considers worth reporting.
--
-- Full-screen dim overlay + a centered dark ui.Panel, per CLAUDE.md's
-- centre-by-default rule.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Summary = require(ReplicatedStorage.Features.Maze.Summary)
local ui = require(ReplicatedStorage.Shared.Boil).ui

local PANEL_SIZE = UDim2.fromOffset(560, 560)
local TITLE_TEXT_SIZE = 56
local WINNER_TEXT_SIZE = 28
local ROW_TEXT_SIZE = 22
local ROW_HEIGHT = 30
local WINNER_COLOR = Color3.fromRGB(120, 230, 150)
local YOU_COLOR = Color3.fromRGB(255, 220, 130)
local ROW_COLOR = Color3.fromRGB(200, 208, 216)
local SECTION_COLOR = Color3.fromRGB(150, 162, 176)
local CASH_COLOR = Color3.fromRGB(120, 230, 150)
local SECTION_TEXT_SIZE = 18

export type HaulRow = { name: string, haul: number }

type Props = {
	winnerName: string,
	hauls: { HaulRow },
	-- Local player's name, so their row can be picked out of the list.
	localName: string,
	-- The local player's `Ringfall` profile slice, read live. Sections are
	-- handed this whole table rather than a digest of it, so a feature can
	-- report on anything the profile holds without a packet or a prop for it.
	-- Optional: it arrives by replica and is legitimately absent for the first
	-- frames of a session.
	profile: { [string]: any }?,
	-- Sent to the server, which is what releases the round. nil while the local
	-- player has already pressed it and the server is still waiting on someone
	-- else — the button becomes a status line rather than disappearing, so the
	-- wait reads as "waiting for others" and not as a broken screen.
	onContinue: (() -> ())?,
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

	-- The local player's own take, stated as cash rather than as a row in a
	-- ranking. A scoreboard answers "who won"; this answers "what did I get",
	-- which is the question the board is actually held open for.
	local yourHaul = 0
	for _, row in rows do
		if row.name == props.localName then
			yourHaul = row.haul
		end
	end
	-- Defaulted, not assumed. The profile arrives by replica, so it is legitimately
	-- absent for the first frames of a session — and a board that throws takes the
	-- whole React tree down with it, losing the timer and the countdown too. A
	-- results screen is the last place that should be able to break the HUD.
	local profile = props.profile or {}
	local cash = if typeof(profile.Cash) == "number" then profile.Cash else 0
	children.YourTake = React.createElement(ui.Text, {
		text = `+{yourHaul} banked   ·   {cash} total`,
		textSize = WINNER_TEXT_SIZE,
		weight = Enum.FontWeight.Bold,
		color = CASH_COLOR,
		size = UDim2.new(1, 0, 0, WINNER_TEXT_SIZE + 8),
		layoutOrder = 3,
	})

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

	-- Feature-owned sections, in registration order. A section that returns no
	-- lines is skipped entirely rather than rendered as an empty heading.
	local order = 100
	for _, section in Summary.list() do
		local ok, lines = pcall(section.lines, profile)
		if not ok then
			warn(`[WinScreen] section "{section.id}" errored: {lines}`)
			continue
		end
		if typeof(lines) ~= "table" or #lines == 0 then
			continue
		end

		order += 1
		children[`Section_{section.id}`] = React.createElement(ui.Text, {
			text = section.title,
			textSize = ROW_TEXT_SIZE,
			color = ROW_COLOR,
			size = UDim2.new(1, 0, 0, ROW_TEXT_SIZE + 14),
			layoutOrder = order,
		})
		for lineIndex, line in lines do
			order += 1
			children[`Section_{section.id}_{lineIndex}`] = React.createElement(ui.Text, {
				text = line,
				textSize = SECTION_TEXT_SIZE,
				color = SECTION_COLOR,
				size = UDim2.new(1, 0, 0, SECTION_TEXT_SIZE + 6),
				layoutOrder = order,
			})
		end
	end

	children.Continue = if props.onContinue
		then React.createElement(ui.Button, {
			text = "CONTINUE",
			size = UDim2.fromOffset(220, 44),
			layoutOrder = 900,
			onClick = props.onContinue,
		})
		else React.createElement(ui.Text, {
			text = "waiting for the others…",
			textSize = SECTION_TEXT_SIZE,
			color = SECTION_COLOR,
			size = UDim2.new(1, 0, 0, 44),
			layoutOrder = 900,
		})

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
