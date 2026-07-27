--!strict
-- A flashlight that follows the camera, cutting a cone through the fog. An
-- invisible emitter part is re-CFramed to the camera each frame; the SpotLight
-- points along the camera's look direction.
--
-- A weak baseline cone is always on so you're never fully blind; scavenging the
-- flashlight pickup (the `HasFlashlight` per-run attribute, see Pickups) boosts
-- it to full reach and brightness. Cleared on RUN IT BACK, so each round starts
-- dim again and the flashlight is worth hunting for.
--
-- Auto-loaded: name ends in `Controller`.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Flashlight.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Dim, short baseline vs the full scavenged beam.
local BASELINE_RANGE, BASELINE_BRIGHTNESS = 60, 1.0
local FULL_RANGE, FULL_BRIGHTNESS = 140, 3.5

local FlashlightController = {}

function FlashlightController.Start()
	local player = Players.LocalPlayer
	local camera = workspace.CurrentCamera

	local emitter = Instance.new("Part")
	emitter.Name = "FlashlightEmitter"
	emitter.Size = Vector3.new(0.2, 0.2, 0.2)
	emitter.Transparency = 1
	emitter.CanCollide = false
	emitter.CanQuery = false
	emitter.CanTouch = false
	emitter.Anchored = true
	emitter.Parent = workspace

	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Front
	light.Angle = 55
	light.Color = Color3.fromRGB(240, 238, 220)
	light.Shadows = true
	light.Parent = emitter

	local function applyBeam()
		local hasFlashlight = player:GetAttribute("HasFlashlight") == true
		light.Range = if hasFlashlight then FULL_RANGE else BASELINE_RANGE
		light.Brightness = if hasFlashlight then FULL_BRIGHTNESS else BASELINE_BRIGHTNESS
	end
	player:GetAttributeChangedSignal("HasFlashlight"):Connect(applyBeam)
	applyBeam()

	RunService.RenderStepped:Connect(function()
		-- Front face points along +LookVector once we orient the part to the camera.
		local cf = camera.CFrame
		emitter.CFrame = CFrame.lookAt(cf.Position, cf.Position + cf.LookVector)
	end)
end

return FlashlightController
