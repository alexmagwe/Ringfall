--!strict
-- Top-of-screen health bar. Pure presentation: reads the server-owned `Health` /
-- `MaxHealth` player attributes (they replicate automatically) and draws a bar.
-- No logic, no networking — the drain/heal all happen server-side.
--
-- Auto-loaded: name ends in `Controller`.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Health.

local Players = game:GetService("Players")

local HealthController = {}

local FULL_COLOR = Color3.fromRGB(80, 200, 100)
local LOW_COLOR = Color3.fromRGB(225, 55, 55)

function HealthController.Start()
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "HealthHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Top-centre vitals stack, in screen order: run timer (UIController, y=12,
	-- 50 tall) -> health -> stamina (Sprint) -> compass (Pickups). Keep these
	-- four in sync if any one of them moves; they share the same column.
	local back = Instance.new("Frame")
	back.Size = UDim2.fromOffset(320, 20)
	back.Position = UDim2.new(0.5, 0, 0, 70)
	back.AnchorPoint = Vector2.new(0.5, 0)
	back.BackgroundColor3 = Color3.fromRGB(20, 22, 26)
	back.BackgroundTransparency = 0.25
	back.BorderSizePixel = 0
	back.Parent = gui
	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0, 5)
	backCorner.Parent = back

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = FULL_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = back
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 5)
	fillCorner.Parent = fill

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextSize = 12
	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.Text = ""
	text.Parent = back
	local textStroke = Instance.new("UIStroke")
	textStroke.Thickness = 1.5
	textStroke.Color = Color3.fromRGB(0, 0, 0)
	textStroke.Transparency = 0.4
	textStroke.Parent = text

	local function update()
		local hp = player:GetAttribute("Health")
		local max = player:GetAttribute("MaxHealth")
		if typeof(hp) ~= "number" or typeof(max) ~= "number" or max <= 0 then
			return
		end
		local frac = math.clamp(hp / max, 0, 1)
		fill.Size = UDim2.fromScale(frac, 1)
		fill.BackgroundColor3 = if frac < 0.3 then LOW_COLOR else FULL_COLOR
		text.Text = string.format("%d / %d", math.max(0, math.floor(hp + 0.5)), math.floor(max))
	end

	player:GetAttributeChangedSignal("Health"):Connect(update)
	player:GetAttributeChangedSignal("MaxHealth"):Connect(update)
	update()
end

return HealthController
