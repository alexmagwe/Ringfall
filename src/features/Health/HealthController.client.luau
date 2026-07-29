--!strict
-- Top-of-screen health bar, plus the medkit charge readout and its key. Reads
-- the server-owned `Health` / `MaxHealth` / `MedCharges` player attributes (they
-- replicate automatically) and draws them. The only thing it sends is a request
-- to spend a charge — HealthService decides whether one is actually spent, and
-- all draining/healing happens server-side.
--
-- Auto-loaded: name ends in `Controller`.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Health.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Features.Health.Net)

local HealthController = {}

local FULL_COLOR = Color3.fromRGB(80, 200, 100)
local LOW_COLOR = Color3.fromRGB(225, 55, 55)
local MEDKIT_COLOR = Color3.fromRGB(235, 120, 120)
local MEDKIT_ACTION = "HealthUseMedkit"
local MEDKIT_KEY = Enum.KeyCode.H

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

	-- Medkit charges. Bottom-left, deliberately clear of the protected
	-- top-centre vitals column and of the bottom-right ammo/haul readouts.
	local medkit = Instance.new("TextLabel")
	medkit.Size = UDim2.fromOffset(240, 34)
	medkit.Position = UDim2.new(0, 16, 1, -16)
	medkit.AnchorPoint = Vector2.new(0, 1)
	medkit.BackgroundTransparency = 1
	medkit.TextXAlignment = Enum.TextXAlignment.Left
	medkit.TextColor3 = MEDKIT_COLOR
	medkit.TextSize = 24
	medkit.Font = Enum.Font.GothamBold
	medkit.Text = ""
	medkit.Visible = false
	medkit.Parent = gui
	local medkitStroke = Instance.new("UIStroke")
	medkitStroke.Thickness = 2
	medkitStroke.Color = Color3.fromRGB(0, 0, 0)
	medkitStroke.Parent = medkit

	local function updateMedkit()
		local charges = player:GetAttribute("MedCharges")
		local count = if typeof(charges) == "number" then charges else 0
		medkit.Visible = count > 0
		medkit.Text = string.format("MEDKIT x%d   [H]", count)
	end

	player:GetAttributeChangedSignal("MedCharges"):Connect(updateMedkit)
	updateMedkit()

	-- Request only: the server re-checks the charge count and that you're
	-- actually hurt before anything is spent.
	ContextActionService:BindAction(MEDKIT_ACTION, function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		Net.UseMedkit.send()
		return Enum.ContextActionResult.Sink
	end, false, MEDKIT_KEY)
end

return HealthController
