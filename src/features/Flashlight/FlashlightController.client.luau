--!strict
-- A flashlight that follows the camera, cutting a cone through the fog. An
-- invisible emitter part is re-CFramed to the camera each frame; the SpotLight
-- points along the camera's look direction.
--
-- Auto-loaded: name ends in `Controller`.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Flashlight.

local RunService = game:GetService("RunService")

local FlashlightController = {}

function FlashlightController.Start()
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
	light.Range = 140
	light.Brightness = 3.5
	light.Color = Color3.fromRGB(240, 238, 220)
	light.Shadows = true
	light.Parent = emitter

	RunService.RenderStepped:Connect(function()
		-- Front face points along +LookVector once we orient the part to the camera.
		local cf = camera.CFrame
		emitter.CFrame = CFrame.lookAt(cf.Position, cf.Position + cf.LookVector)
	end)
end

return FlashlightController
