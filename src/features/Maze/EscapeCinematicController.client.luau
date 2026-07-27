--!strict
-- The escape cinematic: on win, the camera detaches from third-person and
-- flies up and back over the maze the player just crossed, hunters
-- converging on the pad too late (see HunterService's EvacAlert sprint),
-- then resolves so the caller can bring the win panel up over the shot.
--
-- Exposes intent actions only (play/stop) — UIController drives it from the
-- Escaped/Restart packets. No networking here.
--
-- Auto-loaded: name ends in `Controller`. No Start() — SpawnAll skips modules
-- without the method, so this is fine to sit idle until UIController calls it.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Maze.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local EscapeCinematicController = {}

local RISE = Vector3.new(0, 220, 260) -- offset from the character at the end
local FLIGHT_TIME = 1.8
local HOLD_TIME = 0.5
local DRONE_VOLUME = 0.8

local function setDroneVolumes(volume: number)
	for _, m in workspace:GetChildren() do
		if not (m:IsA("Model") and m.Name == "Hunter") then
			continue
		end
		local sound = m.PrimaryPart and m.PrimaryPart:FindFirstChild("HunterDrone")
		if sound then
			TweenService:Create(sound, TweenInfo.new(0.3), { Volume = volume }):Play()
		end
	end
end

-- Detaches the camera and flies it up and back over the maze. Resolves when
-- the shot has settled, so the caller can bring the win panel up over it.
function EscapeCinematicController.play(): ()
	local player = Players.LocalPlayer
	local char = player.Character
	if not char then
		return
	end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	setDroneVolumes(0)

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable

	local charPos = root.Position
	local startPos = camera.CFrame.Position
	local endPos = charPos + RISE

	local progress = Instance.new("NumberValue")
	progress.Value = 0
	local tween = TweenService:Create(
		progress,
		TweenInfo.new(FLIGHT_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Value = 1 }
	)

	local aborted = false
	local connection = progress:GetPropertyChangedSignal("Value"):Connect(function()
		-- Guard against the player dying or leaving mid-flight.
		if not player.Character then
			aborted = true
			tween:Cancel()
			return
		end
		local t = progress.Value
		camera.CFrame = CFrame.lookAt(startPos:Lerp(endPos, t), charPos)
	end)

	tween:Play()
	tween.Completed:Wait()
	connection:Disconnect()
	progress:Destroy()

	if aborted then
		EscapeCinematicController.stop()
		return
	end

	task.wait(HOLD_TIME)
end

function EscapeCinematicController.stop(): ()
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
	setDroneVolumes(DRONE_VOLUME)
end

return EscapeCinematicController
