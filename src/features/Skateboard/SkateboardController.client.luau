--!strict
-- Client side of the skateboard: the ride key, and a readout that says whether
-- you are on it. Everything else — whether the toggle is allowed, where it
-- rolls, how fast you go — is SkateboardService's call. This is a dumb surface:
-- it sends one request and draws three server-owned attributes.
--
-- Auto-loaded: name ends in `Controller`.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Skateboard.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Features.Skateboard.Constants)
local Net = require(ReplicatedStorage.Features.Skateboard.Net)

local SkateboardController = {}

local RIDE_ACTION = "SkateboardToggleRide"
local RIDE_KEY = Enum.KeyCode.R
local IDLE_COLOR = Color3.fromRGB(200, 208, 216)
local RIDING_COLOR = Color3.fromRGB(235, 170, 60)

function SkateboardController.Start()
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "SkateboardHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Bottom-left, stacked directly above the medkit readout (HealthController,
	-- y = -16, 34 tall) so the two carried-item lines read as one column and
	-- neither lands on the protected top-centre vitals or the bottom-right
	-- ammo/haul corner.
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromOffset(300, 30)
	label.Position = UDim2.new(0, 16, 1, -52)
	label.AnchorPoint = Vector2.new(0, 1)
	label.BackgroundTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = IDLE_COLOR
	label.TextSize = 22
	label.Font = Enum.Font.GothamBold
	label.Text = ""
	label.Visible = false
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Parent = label

	local function update()
		local has = player:GetAttribute(Constants.HAS_ATTRIBUTE) == true
		label.Visible = has
		if not has then
			return
		end
		local riding = player:GetAttribute(Constants.RIDING_ATTRIBUTE) == true
		label.Text = if riding then "RIDING   [R] STEP OFF" else "SKATEBOARD   [R]"
		label.TextColor3 = if riding then RIDING_COLOR else IDLE_COLOR
	end

	player:GetAttributeChangedSignal(Constants.HAS_ATTRIBUTE):Connect(update)
	player:GetAttributeChangedSignal(Constants.RIDING_ATTRIBUTE):Connect(update)
	update()

	-- Why the board just refused, or just threw you off. Driven by the server's
	-- one-shot "message|nonce" signal rather than by the riding attribute, so
	-- pressing R twice on grass explains itself twice.
	local notice = Instance.new("TextLabel")
	notice.Size = UDim2.fromOffset(420, 34)
	notice.Position = UDim2.new(0.5, 0, 1, -110)
	notice.AnchorPoint = Vector2.new(0.5, 1)
	notice.BackgroundTransparency = 1
	notice.TextColor3 = RIDING_COLOR
	notice.TextTransparency = 1
	notice.TextSize = 22
	notice.Font = Enum.Font.GothamBold
	notice.Text = ""
	notice.Parent = gui
	local noticeStroke = Instance.new("UIStroke")
	noticeStroke.Thickness = 2
	noticeStroke.Color = Color3.fromRGB(0, 0, 0)
	noticeStroke.Transparency = 1
	noticeStroke.Parent = notice

	player:GetAttributeChangedSignal("SkateboardNotice"):Connect(function()
		local value = player:GetAttribute("SkateboardNotice")
		if typeof(value) ~= "string" then
			return
		end
		notice.Text = string.match(value, "^(.-)|") or value
		local fadeIn = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local fadeOut = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(notice, fadeIn, { TextTransparency = 0 }):Play()
		TweenService:Create(noticeStroke, fadeIn, { Transparency = 0 }):Play()
		task.delay(1.4, function()
			TweenService:Create(notice, fadeOut, { TextTransparency = 1 }):Play()
			TweenService:Create(noticeStroke, fadeOut, { Transparency = 1 }):Play()
		end)
	end)

	-- Request only. The server re-checks that you hold a board and that the
	-- ground under you takes wheels.
	ContextActionService:BindAction(RIDE_ACTION, function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		Net.ToggleRide.send()
		return Enum.ContextActionResult.Sink
	end, false, RIDE_KEY)
end

return SkateboardController
