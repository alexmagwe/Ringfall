--!strict
-- Movement: hold Shift to sprint (drains stamina), hold C to crouch (slower,
-- lowered view, and — behind a wall — hidden from the hunter). Crouch and sprint
-- are mutually exclusive. Crouch state is sent to the server (StealthNet) so the
-- Hunter can treat a crouched-behind-cover player as unseen.
--
-- Auto-loaded: name ends in `Controller`.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Sprint.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StealthNet = require(ReplicatedStorage.Features.Stealth.StealthNet)

local WALK_SPEED = 16
local SPRINT_SPEED = 26
local CROUCH_SPEED = 8
local CROUCH_CAMERA_DROP = 2.2
local CROUCH_LERP = 0.25

-- Crouch pose. Set this to a published crouch animation to get a real crouch;
-- while it's empty the crouch is camera-and-speed only and the avatar stays
-- upright. See docs/game/Stealth.md for how to author one.
--
-- Do NOT go back to lowering Humanoid.HipHeight to fake this. It sinks the whole
-- rig, so the feet end up below the floor — the legs are rigid and won't bend
-- without an animation. Humanoid.BodyHeightScale is also a dead end: this place's
-- avatar settings clamp it, and 0.6 shortened the character by only ~5%. The
-- character is on Roblox's constraint-based rig (AnimationConstraint /
-- BallSocketConstraint, no Motor6D), so posing joints via C0 isn't available
-- either. An animation is the only mechanism that actually works here.
local CROUCH_ANIMATION_ID = ""
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

	local back = Instance.new("Frame")
	back.Size = UDim2.fromOffset(220, 10)
	back.Position = UDim2.new(0.5, 0, 1, -28)
	back.AnchorPoint = Vector2.new(0.5, 1)
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
	local sprintHeld = false
	local crouchHeld = false
	local crouchedSent = false
	-- Re-loaded whenever the character respawns (a fresh Humanoid instance).
	local trackedHum: Humanoid? = nil
	local crouchTrack: AnimationTrack? = nil

	local function loadCrouchTrack(hum: Humanoid): AnimationTrack?
		if CROUCH_ANIMATION_ID == "" then
			return nil
		end
		local animator = hum:FindFirstChildOfClass("Animator")
		if not animator then
			return nil
		end
		local anim = Instance.new("Animation")
		anim.AnimationId = CROUCH_ANIMATION_ID
		local track = animator:LoadAnimation(anim)
		-- Action priority so it wins over the default idle/walk tracks.
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		return track
	end

	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			sprintHeld = true
		elseif input.KeyCode == Enum.KeyCode.C or input.KeyCode == Enum.KeyCode.LeftControl then
			crouchHeld = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			sprintHeld = false
		elseif input.KeyCode == Enum.KeyCode.C or input.KeyCode == Enum.KeyCode.LeftControl then
			crouchHeld = false
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then
			return
		end
		if hum ~= trackedHum then
			trackedHum = hum
			crouchTrack = loadCrouchTrack(hum)
		end

		local moving = hum.MoveDirection.Magnitude > 0.1
		local crouching = crouchHeld
		local sprinting = not crouching and sprintHeld and moving and stamina > 0

		if crouchTrack then
			if crouching and not crouchTrack.IsPlaying then
				crouchTrack:Play(0.15)
			elseif not crouching and crouchTrack.IsPlaying then
				crouchTrack:Stop(0.15)
			end
		end

		if crouching then
			hum.WalkSpeed = CROUCH_SPEED
			hum.CameraOffset = hum.CameraOffset:Lerp(Vector3.new(0, -CROUCH_CAMERA_DROP, 0), CROUCH_LERP)
			stamina = math.min(MAX_STAMINA, stamina + REGEN * dt)
		else
			hum.CameraOffset = hum.CameraOffset:Lerp(Vector3.zero, CROUCH_LERP)
			if sprinting then
				stamina = math.max(0, stamina - DRAIN * dt)
				hum.WalkSpeed = SPRINT_SPEED
			else
				stamina = math.min(MAX_STAMINA, stamina + REGEN * dt)
				hum.WalkSpeed = WALK_SPEED
			end
		end

		-- Tell the server on crouch-state changes (not every frame).
		if crouching ~= crouchedSent then
			crouchedSent = crouching
			StealthNet.Crouch.send(crouching)
		end

		fill.Size = UDim2.fromScale(stamina / MAX_STAMINA, 1)
		fill.BackgroundColor3 = if stamina < 25 then Color3.fromRGB(210, 120, 90) else Color3.fromRGB(120, 200, 140)
		back.Visible = stamina < MAX_STAMINA - 0.5
	end)
end

return SprintController
