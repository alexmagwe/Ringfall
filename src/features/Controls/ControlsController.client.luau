--!strict
-- On-screen controls legend (bottom-left) so players know the keys. Shown clearly
-- on spawn, then dims to a subtle reminder so it doesn't clutter. Keyboard only
-- for now — touch/gamepad prompts are a later pass.
--
-- Auto-loaded: name ends in `Controller`.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Controls.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Required for its side effect as much as its value: requiring the feature root
-- is what runs Controls' auto-discovery, so every feature's sibling Controls.luau
-- has registered before we read the list below.
local Controls = require(ReplicatedStorage.Features.Controls)

local ControlsController = {}

function ControlsController.Start()
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "ControlsHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local list = Instance.new("Frame")
	list.AnchorPoint = Vector2.new(0, 1)
	list.Position = UDim2.new(0, 18, 1, -18)
	-- SIZES TO ITS CONTENT, both ways. It was a fixed 280 wide, which left the
	-- label column 164px after the padding and the key gutter — and "Use medkit
	-- (when carrying one)" is wider than that, so it drew straight out past the
	-- panel edge. A TextLabel neither wraps nor truncates by default; it just
	-- overflows.
	--
	-- A wider fixed number would only move the failure. This legend is built from
	-- `Controls.list()`, so any feature can register any label at any length, and
	-- the panel cannot know the longest one in advance. Measuring the content is
	-- the only thing that stays correct as features come and go.
	list.Size = UDim2.fromOffset(0, 0)
	list.AutomaticSize = Enum.AutomaticSize.XY
	list.BackgroundColor3 = Color3.fromRGB(14, 17, 22)
	list.BackgroundTransparency = 0.25
	list.BorderSizePixel = 0
	list.Parent = gui
	local listCorner = Instance.new("UICorner")
	listCorner.CornerRadius = UDim.new(0, 8)
	listCorner.Parent = list
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = list
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	for i, ctrl in Controls.list() do
		local row = Instance.new("Frame")
		-- Offset-only width, growing with its label. A scale width here would be
		-- circular: the row would size to the panel while the panel sizes to the
		-- row.
		row.Size = UDim2.fromOffset(0, 26)
		row.AutomaticSize = Enum.AutomaticSize.X
		row.BackgroundTransparency = 1
		row.LayoutOrder = i
		row.Parent = list

		local chip = Instance.new("TextLabel")
		chip.AnchorPoint = Vector2.new(0, 0.5)
		chip.Position = UDim2.new(0, 0, 0.5, 0)
		chip.AutomaticSize = Enum.AutomaticSize.X
		chip.Size = UDim2.new(0, 0, 0, 24)
		chip.BackgroundColor3 = Color3.fromRGB(36, 42, 52)
		chip.Text = ctrl.key
		chip.Font = Enum.Font.GothamBold
		chip.TextSize = 14
		chip.TextColor3 = Color3.fromRGB(235, 240, 245)
		chip.Parent = row
		local chipPad = Instance.new("UIPadding")
		chipPad.PaddingLeft = UDim.new(0, 8)
		chipPad.PaddingRight = UDim.new(0, 8)
		chipPad.Parent = chip
		local chipCorner = Instance.new("UICorner")
		chipCorner.CornerRadius = UDim.new(0, 5)
		chipCorner.Parent = chip
		local chipStroke = Instance.new("UIStroke")
		chipStroke.Color = Color3.fromRGB(70, 80, 92)
		chipStroke.Thickness = 1
		chipStroke.Parent = chip

		local text = Instance.new("TextLabel")
		text.AnchorPoint = Vector2.new(0, 0.5)
		-- 92 is the key column: wide enough for the longest chip in play
		-- ("MOUSE 1"), and fixed so every label starts on the same line down the
		-- panel. A key long enough to cross it would overlap its own label — keys
		-- are short by nature, but that is the constraint if one ever isn't.
		text.Position = UDim2.new(0, 92, 0.5, 0)
		text.Size = UDim2.new(0, 0, 1, 0)
		text.AutomaticSize = Enum.AutomaticSize.X
		text.BackgroundTransparency = 1
		text.Text = ctrl.label
		text.Font = Enum.Font.Gotham
		text.TextSize = 14
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextColor3 = Color3.fromRGB(200, 208, 216)
		text.Parent = row
	end

	-- Prominent on spawn, then dim to a subtle reminder after a few seconds.
	list.BackgroundTransparency = 0.25
	task.delay(9, function()
		TweenService:Create(list, TweenInfo.new(1.5), { BackgroundTransparency = 0.7 }):Play()
	end)
end

return ControlsController
