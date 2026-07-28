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

-- Dim, short baseline vs the full scavenged beam. The baseline is a floor for
-- playability, not a substitute: the pickup still roughly doubles your reach and
-- doubles the brightness, which is what keeps a detour for it worth making.
local BASELINE_RANGE, BASELINE_BRIGHTNESS = 95, 1.8
local FULL_RANGE, FULL_BRIGHTNESS = 190, 4.0
-- Studs ahead of the character's chest to place the bulb. Must clear the body
-- (a character is ~2 studs deep) or the player lights themselves up.
local MUZZLE_FORWARD = 3

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
		local cf = camera.CFrame
		-- Emit from just IN FRONT of the character, aimed where the camera looks.
		-- Two earlier placements both lit the player up like a lantern: at the
		-- camera, the character stands ~13 studs down the middle of its own
		-- 55-degree cone; at the chest, their own arms and legs sit right on top
		-- of the bulb. MUZZLE_FORWARD pushes it clear of the body so nothing of
		-- the player's is inside the cone.
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local origin = if root
			then (root :: BasePart).Position + Vector3.new(0, 1.5, 0) + cf.LookVector * MUZZLE_FORWARD
			else cf.Position
		emitter.CFrame = CFrame.lookAt(origin, origin + cf.LookVector)
	end)
end

return FlashlightController
