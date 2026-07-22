--!strict
-- Hold Q to glance behind you without changing where you're running. The camera
-- swings around the character to look back down your own path; release and it
-- swings home.
--
-- Auto-loaded: name ends in `Controller`.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.LookBack.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LOOK_KEY = Enum.KeyCode.Q
-- Seconds for a full 0 -> 180 swing. Fast enough to feel like a glance, slow
-- enough that you can read what's behind you on the way round.
local SWING_TIME = 0.16
-- How far in front of a wall the camera stops when the swing would push it
-- through geometry.
local WALL_MARGIN = 0.5

-- The flip is applied AFTER the default camera module has written its CFrame,
-- and undone BEFORE the control module reads it next frame. That ordering is
-- the whole trick: movement input is camera-relative, so if the control module
-- ever saw the flipped camera, holding W would run you backwards.
local APPLY_PRIORITY = Enum.RenderPriority.Camera.Value + 1
local RESTORE_PRIORITY = Enum.RenderPriority.Input.Value - 1

local LookBackController = {}

local function smoothstep(t: number): number
	return t * t * (3 - 2 * t)
end

function LookBackController.Start()
	local player = Players.LocalPlayer

	local held = false
	local alpha = 0 -- 0 = forward, 1 = fully turned around
	-- The unflipped CFrame, stashed so the next frame's control module reads
	-- the camera the default module actually produced.
	local saved: CFrame? = nil

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == LOOK_KEY then
			held = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == LOOK_KEY then
			held = false
		end
	end)

	RunService:BindToRenderStep("LookBackRestore", RESTORE_PRIORITY, function()
		if saved then
			workspace.CurrentCamera.CFrame = saved
			saved = nil
		end
	end)

	RunService:BindToRenderStep("LookBackApply", APPLY_PRIORITY, function(dt: number)
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?

		-- The catch cutscene takes the camera over entirely; don't fight it.
		if player:GetAttribute("Caught") or not root then
			alpha = 0
			return
		end

		local target = if held then 1 else 0
		local step = dt / SWING_TIME
		if alpha < target then
			alpha = math.min(alpha + step, target)
		elseif alpha > target then
			alpha = math.max(alpha - step, target)
		end
		if alpha <= 0 then
			return
		end

		local camera = workspace.CurrentCamera
		local current = camera.CFrame
		saved = current

		-- Orbit the camera around the character rather than spinning it in
		-- place, so you see past your own shoulder on the way round.
		local pivot = CFrame.new(root.Position)
		local swung = pivot * CFrame.Angles(0, math.pi * smoothstep(alpha), 0) * pivot:Inverse() * current

		-- Swinging in front of the character can push the camera through a wall,
		-- which in a stealth game would let you see a hunter through cover. Pull
		-- it in to the first thing it hits.
		rayParams.FilterDescendantsInstances = { char :: Instance }
		local offset = swung.Position - root.Position
		if offset.Magnitude > 0.05 then
			local hit = workspace:Raycast(root.Position, offset, rayParams)
			if hit then
				local pulled = hit.Position - offset.Unit * WALL_MARGIN
				swung = CFrame.new(pulled) * swung.Rotation
			end
		end

		camera.CFrame = swung
	end)
end

return LookBackController
