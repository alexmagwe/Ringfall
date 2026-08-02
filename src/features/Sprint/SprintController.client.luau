--!strict
-- Movement: hold Shift to sprint, draining stamina. Hiding from the hunters is
-- handled entirely by line-of-sight now (walls break their sensing) rather than
-- by a crouch verb — see docs/game/Hunter.md.
--
-- Auto-loaded: name ends in `Controller`.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Sprint.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local WALK_SPEED = 17.6 -- 16 +10%
local SPRINT_SPEED = 28.6 -- 26 +10%
local MAX_STAMINA = 100
local DRAIN = 26
local REGEN = 16

local SprintController = {}

function SprintController.Start()
	local player = Players.LocalPlayer

	-- Stamina bar (greybox HUD).
	local gui = Instance.new("ScreenGui")
	gui.Name = "MovementHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Stamina sits just under the health bar (Health feature), both top-centre,
	-- same 320px width so they align as a stacked pair.
	local back = Instance.new("Frame")
	back.Size = UDim2.fromOffset(320, 14)
	back.Position = UDim2.new(0.5, 0, 0, 94)
	back.AnchorPoint = Vector2.new(0.5, 0)
	back.BackgroundColor3 = Color3.fromRGB(20, 24, 30)
	back.BackgroundTransparency = 0.35
	back.BorderSizePixel = 0
	back.Parent = gui
	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0, 4)
	backCorner.Parent = back
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(120, 200, 140)
	fill.BorderSizePixel = 0
	fill.Parent = back
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill

	local stamina = MAX_STAMINA
	local prevMaxStamina = MAX_STAMINA
	local sprintHeld = false

	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			sprintHeld = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			sprintHeld = false
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then
			return
		end

		-- Stamina pickup (Pickups feature) raises the max live. If the bar was
		-- topped out under the old max, bump it to the new one so the upgrade is
		-- felt immediately instead of just widening unused headroom.
		local maxStamina = MAX_STAMINA + (player:GetAttribute("StaminaBonus") or 0)
		if maxStamina > prevMaxStamina and stamina >= prevMaxStamina - 0.5 then
			stamina = maxStamina
		end
		prevMaxStamina = maxStamina
		stamina = math.min(stamina, maxStamina)

		local moving = hum.MoveDirection.Magnitude > 0.1
		local sprinting = sprintHeld and moving and stamina > 0

		if sprinting then
			stamina = math.max(0, stamina - DRAIN * dt)
			hum.WalkSpeed = SPRINT_SPEED
		else
			stamina = math.min(maxStamina, stamina + REGEN * dt)
			hum.WalkSpeed = WALK_SPEED
		end

		fill.Size = UDim2.fromScale(stamina / maxStamina, 1)
		fill.BackgroundColor3 = if stamina < 25 then Color3.fromRGB(210, 120, 90) else Color3.fromRGB(120, 200, 140)
	end)
end

return SprintController
