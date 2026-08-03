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

local PANEL_SIZE = UDim2.fromOffset(520, 560)
local PANEL_PADDING = 28

-- One size per ROLE, with real gaps between them. The first version ran every
-- line at 18-28px, centred, in three near-identical greys — eight lines with no
-- reason to look at any of them first. Sizes here step 64 / 34 / 22 / 16 / 13 so
-- the eye lands on the take, then the outcome, then the detail.
local HERO_TEXT_SIZE = 64
local TITLE_TEXT_SIZE = 34
local ROW_TEXT_SIZE = 22
local CAPTION_TEXT_SIZE = 16
local HEADING_TEXT_SIZE = 13
local ROW_HEIGHT = 28
local GAP = 6 -- between lines within a group
local GROUP_GAP = 22 -- extra height under a group's last line, to separate groups

-- Colour carries hierarchy too: exactly ONE thing is coloured (the take), the
-- rest is a grey ramp from bright rows down to dim headings.
local CASH_COLOR = Color3.fromRGB(126, 232, 156)
local YOU_COLOR = Color3.fromRGB(255, 220, 130)
local ROW_COLOR = Color3.fromRGB(206, 214, 222)
local MUTED_COLOR = Color3.fromRGB(146, 158, 172)
local HEADING_COLOR = Color3.fromRGB(112, 124, 138)

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
	-- Defaulted, not assumed. The profile arrives by replica, so it is legitimately
	-- absent for the first frames of a session — and a board that throws takes the
	-- whole React tree down with it, losing the timer and the countdown too. A
	-- results screen is the last place that should be able to break the HUD.
	local profile = props.profile or {}
	local cash = if typeof(profile.Cash) == "number" then profile.Cash else 0

	-- Highest haul first; the scoreboard reads as a ranking.
	local rows = table.clone(props.hauls)
	table.sort(rows, function(a, b)
		return a.haul > b.haul
	end)

	local yourHaul = 0
	for _, row in rows do
		if row.name == props.localName then
			yourHaul = row.haul
		end
	end

	local children: { [string]: any } = {
		UIListLayout = React.createElement("UIListLayout", {
			Padding = UDim.new(0, GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			FillDirection = Enum.FillDirection.Vertical,
		}),
		Padding = React.createElement("UIPadding", {
			PaddingLeft = UDim.new(0, PANEL_PADDING),
			PaddingRight = UDim.new(0, PANEL_PADDING),
		}),
	}

	-- 1. OUTCOME — small, and deliberately not the loudest thing on the board.
	-- Which of these two lines is the headline was the whole problem with the
	-- first version: every line was 22-28px and centred, so the eye had nowhere
	-- to land and the screen read as a paragraph.
	children.Title = React.createElement(ui.Text, {
		text = "VAULT EXTRACTED",
		textSize = TITLE_TEXT_SIZE,
		weight = Enum.FontWeight.Heavy,
		shadow = true,
		size = UDim2.new(1, 0, 0, TITLE_TEXT_SIZE + 4),
		layoutOrder = 1,
	})
	children.Winner = React.createElement(ui.Text, {
		text = `{props.winnerName} got out with it`,
		textSize = CAPTION_TEXT_SIZE,
		color = MUTED_COLOR,
		size = UDim2.new(1, 0, 0, CAPTION_TEXT_SIZE + GROUP_GAP),
		layoutOrder = 2,
	})

	-- 2. THE TAKE — the hero. This is the question the board is held open for,
	-- so it is the biggest thing on it and the only thing in colour.
	children.Take = React.createElement(ui.Text, {
		text = `+{yourHaul}`,
		textSize = HERO_TEXT_SIZE,
		weight = Enum.FontWeight.Heavy,
		color = CASH_COLOR,
		shadow = true,
		size = UDim2.new(1, 0, 0, HERO_TEXT_SIZE + 4),
		layoutOrder = 3,
	})
	children.TakeCaption = React.createElement(ui.Text, {
		text = `BANKED  ·  {cash} TOTAL`,
		textSize = CAPTION_TEXT_SIZE,
		color = MUTED_COLOR,
		size = UDim2.new(1, 0, 0, CAPTION_TEXT_SIZE + GROUP_GAP),
		layoutOrder = 4,
	})

	-- 3. RANKING — only with someone to rank against. Solo, it repeated the
	-- hero number two lines under it and added a heading to say so.
	local order = 10
	if #rows > 1 then
		children.RankHeading = React.createElement(ui.Text, {
			text = "THIS ROUND",
			textSize = HEADING_TEXT_SIZE,
			weight = Enum.FontWeight.Bold,
			color = HEADING_COLOR,
			size = UDim2.new(1, 0, 0, HEADING_TEXT_SIZE + 8),
			layoutOrder = order,
		})
		for index, row in rows do
			order += 1
			local isYou = row.name == props.localName
			children[`Row{index}`] = React.createElement(ui.Text, {
				text = `{row.name}   {row.haul}`,
				textSize = ROW_TEXT_SIZE,
				color = if isYou then YOU_COLOR else ROW_COLOR,
				weight = if isYou then Enum.FontWeight.Bold else Enum.FontWeight.Regular,
				size = UDim2.new(1, 0, 0, ROW_HEIGHT),
				layoutOrder = order,
			})
		end
		order += 1
	end

	-- 4. FEATURE SECTIONS. A section that returns no lines is skipped entirely
	-- rather than rendered as an empty heading.
	order = 100
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
			textSize = HEADING_TEXT_SIZE,
			weight = Enum.FontWeight.Bold,
			color = HEADING_COLOR,
			size = UDim2.new(1, 0, 0, HEADING_TEXT_SIZE + 8),
			layoutOrder = order,
		})
		for lineIndex, line in lines do
			order += 1
			children[`Section_{section.id}_{lineIndex}`] = React.createElement(ui.Text, {
				text = line,
				textSize = ROW_TEXT_SIZE,
				color = ROW_COLOR,
				size = UDim2.new(1, 0, 0, ROW_HEIGHT),
				layoutOrder = order,
			})
		end
	end

	-- 5. THE ACTION.
	children.Continue = if props.onContinue
		then React.createElement(ui.Button, {
			text = "CONTINUE",
			size = UDim2.fromOffset(220, 46),
			layoutOrder = 900,
			onClick = props.onContinue,
		})
		else React.createElement(ui.Text, {
			text = "waiting for the others…",
			textSize = CAPTION_TEXT_SIZE,
			color = MUTED_COLOR,
			size = UDim2.new(1, 0, 0, 46),
			layoutOrder = 900,
		})

	return React.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 100,
	}, {
		Panel = React.createElement(ui.Panel, {
			size = PANEL_SIZE,
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
			-- Near-opaque. At the default the maze read straight through the
			-- middle of the board, and the sky behind it competed with the text.
			transparency = 0.08,
		}, children),
	})
end
