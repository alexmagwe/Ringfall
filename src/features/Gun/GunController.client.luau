--!strict
-- Gun input + HUD: crosshair and ammo counter, only shown while the local
-- player has HasGun. Fires a Shoot request on click — the server is the sole
-- authority on ammo, range, cooldown and whether a hunter was actually hit.
-- Local cooldown here is feel only.
--
-- Auto-loaded: name ends in `Controller`.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Gun.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Features.Gun.Net)

local LOCAL_FIRE_COOLDOWN = 0.2 -- feel only; server enforces the real cooldown

local GunController = {}

function GunController.Start()
	local player = Players.LocalPlayer
	local camera = Workspace.CurrentCamera

	local gui = Instance.new("ScreenGui")
	gui.Name = "GunHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local crosshair = Instance.new("Frame")
	crosshair.Size = UDim2.fromOffset(6, 6)
	crosshair.Position = UDim2.fromScale(0.5, 0.5)
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	crosshair.BackgroundTransparency = 0.2
	crosshair.BorderSizePixel = 0
	crosshair.Visible = false
	crosshair.Parent = gui
	local crosshairCorner = Instance.new("UICorner")
	crosshairCorner.CornerRadius = UDim.new(1, 0)
	crosshairCorner.Parent = crosshair

	local ammoLabel = Instance.new("TextLabel")
	ammoLabel.Size = UDim2.fromOffset(160, 36)
	ammoLabel.Position = UDim2.new(1, -20, 1, -20)
	ammoLabel.AnchorPoint = Vector2.new(1, 1)
	ammoLabel.BackgroundTransparency = 1
	ammoLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	ammoLabel.TextSize = 26
	ammoLabel.Font = Enum.Font.GothamBold
	ammoLabel.TextXAlignment = Enum.TextXAlignment.Right
	ammoLabel.Text = "AMMO 0"
	ammoLabel.Visible = false
	ammoLabel.Parent = gui
	local ammoStroke = Instance.new("UIStroke")
	ammoStroke.Thickness = 2
	ammoStroke.Color = Color3.fromRGB(0, 0, 0)
	ammoStroke.Parent = ammoLabel

	local function updateAmmoLabel()
		local ammo = player:GetAttribute("Ammo")
		ammoLabel.Text = `AMMO {if typeof(ammo) == "number" then ammo else 0}`
	end

	player:GetAttributeChangedSignal("Ammo"):Connect(updateAmmoLabel)
	updateAmmoLabel()

	RunService.Heartbeat:Connect(function()
		local hasGun = player:GetAttribute("HasGun") == true
		crosshair.Visible = hasGun
		ammoLabel.Visible = hasGun
	end)

	local lastLocalShot = 0
	UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
		if gameProcessedEvent then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if not player:GetAttribute("HasGun") then
			return
		end
		local ammo = player:GetAttribute("Ammo")
		if typeof(ammo) ~= "number" or ammo <= 0 then
			return
		end
		local now = os.clock()
		if now - lastLocalShot < LOCAL_FIRE_COOLDOWN then
			return
		end
		lastLocalShot = now

		Net.Shoot.send({
			origin = camera.CFrame.Position,
			direction = camera.CFrame.LookVector,
		})
	end)
end

return GunController
