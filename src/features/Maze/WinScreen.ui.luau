--!strict
-- Pure/dumb React component for the escape win screen. Owns no networking —
-- UIController mounts this when it hears the Escaped packet and unmounts it
-- when the player restarts. Follows the Notes feature's `.ui.luau` shape
-- (createElement style, ui.* primitives, no data fetching in the component).
--
-- Full-screen dim overlay + a centered dark ui.Panel (CLAUDE.md: new feature
-- UIs anchor at screen center). No custom styling beyond that dark panel and
-- white text, per the plan — RUN IT BACK is a plain TextButton, not the
-- colorful gem ui.Button, since a win screen isn't the place for a gem-variant
-- accent color.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ui = require(ReplicatedStorage.Shared.Boil).ui

local PANEL_SIZE = UDim2.fromOffset(520, 320)
local TITLE_TEXT_SIZE = 72
local TIME_TEXT_SIZE = 56
local BUTTON_SIZE = UDim2.fromOffset(280, 72)

type Props = {
	timeSeconds: number,
	onRestart: () -> (),
}

-- "M:SS.d" — minutes (no leading zero), 2-digit seconds, 1 decimal digit.
local function formatTime(totalSeconds: number): string
	local minutes = math.floor(totalSeconds / 60)
	local remainder = totalSeconds - minutes * 60
	local wholeSeconds = math.floor(remainder)
	local tenths = math.floor((remainder - wholeSeconds) * 10)
	return string.format("%d:%02d.%d", minutes, wholeSeconds, tenths)
end

return function(props: Props)
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
		}, {
			UIListLayout = React.createElement("UIListLayout", {
				Padding = UDim.new(0, 24),
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				FillDirection = Enum.FillDirection.Vertical,
			}),

			Title = React.createElement(ui.Text, {
				text = "ESCAPED",
				textSize = TITLE_TEXT_SIZE,
				weight = Enum.FontWeight.Heavy,
				shadow = true,
				size = UDim2.new(1, 0, 0, TITLE_TEXT_SIZE + 10),
				layoutOrder = 1,
			}),

			Time = React.createElement(ui.Text, {
				text = formatTime(props.timeSeconds),
				textSize = TIME_TEXT_SIZE,
				weight = Enum.FontWeight.Bold,
				size = UDim2.new(1, 0, 0, TIME_TEXT_SIZE + 6),
				layoutOrder = 2,
			}),

			RestartButton = React.createElement("TextButton", {
				Size = BUTTON_SIZE,
				BackgroundColor3 = Color3.fromRGB(20, 20, 20),
				BackgroundTransparency = 0.1,
				BorderSizePixel = 0,
				Text = "RUN IT BACK",
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextSize = 32,
				FontFace = Font.new(
					"rbxasset://fonts/families/SourceSansPro.json",
					Enum.FontWeight.Bold,
					Enum.FontStyle.Normal
				),
				LayoutOrder = 3,
				[React.Event.Activated] = function()
					props.onRestart()
				end,
			}, {
				UIStroke = React.createElement("UIStroke", {
					Thickness = 2,
					Color = Color3.fromRGB(255, 255, 255),
				}),
				UICorner = React.createElement("UICorner", {
					CornerRadius = UDim.new(0, 8),
				}),
			}),
		}),
	})
end
