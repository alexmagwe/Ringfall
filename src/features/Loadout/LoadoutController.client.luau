--!strict
-- Draws the carried-kit strip: one bottom-right column, one row per registered
-- slot, laid out so two features can never land on the same pixels.
--
-- BOTTOM RIGHT, and the choice matters. Bottom-left is the controls legend,
-- which sizes to its content and grows every time any feature registers a key —
-- anything parked near it is one new keybind away from being covered, which is
-- exactly how the medkit line ended up unreadable. Bottom-centre is where the
-- transient toasts flash. The right corner is the only one whose height this
-- strip alone decides.
--
-- Rows are hidden, not blanked, when their slot returns nil, and the
-- `UIListLayout` closes the gap — so the strip is always exactly as tall as the
-- number of things you are actually carrying.
--
-- Auto-loaded: name ends in `Controller`.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Loadout.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Required for its side effect as much as its value: requiring the feature root
-- runs the auto-discovery, so every sibling `Loadout.luau` has registered before
-- the list below is read. Same idiom as ControlsController.
local Loadout = require(ReplicatedStorage.Features.Loadout)

local LoadoutController = {}

local DEFAULT_COLOR = Color3.fromRGB(235, 240, 245)
local FLASH_COLOR = Color3.fromRGB(255, 240, 170)
local ROW_HEIGHT = 30
local TEXT_SIZE = 24

function LoadoutController.Start()
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "LoadoutHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local column = Instance.new("Frame")
	column.Name = "Column"
	column.AnchorPoint = Vector2.new(1, 1)
	column.Position = UDim2.new(1, -16, 1, -14)
	-- Sizes to its rows, both ways: the strip cannot know how many features are
	-- installed, and a fixed height would either clip the last row or reserve
	-- dead space above the first.
	column.Size = UDim2.fromOffset(0, 0)
	column.AutomaticSize = Enum.AutomaticSize.XY
	column.BackgroundTransparency = 1
	column.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = column

	for index, slot in Loadout.list() do
		local row = Instance.new("TextLabel")
		row.Name = slot.id
		-- Offset-only width growing with the text. A scale width would be
		-- circular here: the row would size to the column while the column
		-- sizes to the row.
		row.Size = UDim2.fromOffset(0, ROW_HEIGHT)
		row.AutomaticSize = Enum.AutomaticSize.X
		row.BackgroundTransparency = 1
		row.TextXAlignment = Enum.TextXAlignment.Right
		row.TextColor3 = slot.color or DEFAULT_COLOR
		row.TextSize = TEXT_SIZE
		row.Font = Enum.Font.GothamBold
		row.Text = ""
		row.Visible = false
		row.LayoutOrder = index
		row.Parent = column

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.fromRGB(0, 0, 0)
		stroke.Parent = row

		local base = slot.color or DEFAULT_COLOR
		local function flash()
			local fadeIn = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local fadeOut = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(row, fadeIn, { TextColor3 = FLASH_COLOR }):Play()
			task.delay(0.1, function()
				TweenService:Create(row, fadeOut, { TextColor3 = base }):Play()
			end)
		end

		local previous: number? = nil
		local function update()
			local ok, text = pcall(slot.text, player)
			if not ok then
				warn(`[Loadout] slot "{slot.id}" errored: {text}`)
				row.Visible = false
				return
			end
			row.Visible = text ~= nil
			row.Text = text or ""

			if not slot.flashOn then
				return
			end
			local value = player:GetAttribute(slot.flashOn)
			local current = if typeof(value) == "number" then value else 0
			-- Only a RISE flashes, and only against a value we have already seen.
			-- Firing on the first read would flash every slot on spawn.
			if previous ~= nil and current > previous then
				flash()
			end
			previous = current
		end

		for _, attribute in slot.watch do
			player:GetAttributeChangedSignal(attribute):Connect(update)
		end
		update()
	end
end

return LoadoutController
