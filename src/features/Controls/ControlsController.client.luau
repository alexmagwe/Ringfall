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
	list.Size = UDim2.fromOffset(280, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
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
		row.Size = UDim2.new(1, 0, 0, 26)
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
		text.Position = UDim2.new(0, 92, 0.5, 0)
		text.Size = UDim2.new(1, -92, 1, 0)
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
