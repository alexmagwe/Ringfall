--!strict
-- Visual-only client side of Pickups: spins the balls in workspace.Pickups and
-- flashes a toast when the local player picks one up. All grant logic lives
-- server-side (PickupsService); this just reacts to the resulting attributes.
--
-- Auto-loaded: name ends in `Controller`.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Pickups.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Features.Pickups.Constants)

local PickupsController = {}

local function spinPickups(dt: number)
	local folder = workspace:FindFirstChild(Constants.FOLDER)
	if not folder then
		return
	end
	local delta = math.rad(Constants.SPIN_DPS) * dt
	local spin = CFrame.Angles(0, delta, 0)
	for _, pickup in folder:GetChildren() do
		if pickup:IsA("BasePart") then
			pickup.CFrame *= spin
		elseif pickup:IsA("Model") then
			pickup:PivotTo(pickup:GetPivot() * spin)
		end
	end
end

function PickupsController.Start()
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "PickupsHud"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromOffset(420, 40)
	label.Position = UDim2.new(0.5, 0, 1, -70)
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 230, 160)
	label.TextTransparency = 1
	label.TextSize = 24
	label.Font = Enum.Font.GothamBold
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Transparency = 1
	stroke.Parent = label

	local function flash(message: string)
		label.Text = message
		local fadeIn = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local fadeOut = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(label, fadeIn, { TextTransparency = 0 }):Play()
		TweenService:Create(stroke, fadeIn, { Transparency = 0 }):Play()
		task.delay(1.2, function()
			TweenService:Create(label, fadeOut, { TextTransparency = 1 }):Play()
			TweenService:Create(stroke, fadeOut, { Transparency = 1 }):Play()
		end)
	end

	-- Driven by the server's one-shot `PickupToast` signal ("kind|nonce"), not by
	-- the granted attributes: Health and Ammo change constantly (drain, firing),
	-- so listening on those would flash spuriously.
	local LABELS = {
		Gun = "GUN",
		Ammo = "AMMO",
		Flashlight = "FLASHLIGHT",
		Stamina = "STAMINA UPGRADE",
		HealthKit = "MEDKIT",
	}
	player:GetAttributeChangedSignal("PickupToast"):Connect(function()
		local value = player:GetAttribute("PickupToast")
		if typeof(value) ~= "string" then
			return
		end
		local kind = string.match(value, "^(.-)|") or value
		flash("PICKED UP: " .. (LABELS[kind] or kind))
	end)

	RunService.Heartbeat:Connect(spinPickups)
end

return PickupsController
