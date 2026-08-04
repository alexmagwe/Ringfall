--!strict
-- Client side of the EMP: the key, the aim vector, and a charge readout.
-- Everything that decides anything — whether you had a charge, where the burst
-- lands, what it hits — is EMPService's. This sends one request and draws two
-- server-owned attributes.
--
-- Auto-loaded: name ends in `Controller`.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.EMP.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Features.EMP.Constants)
local Net = require(ReplicatedStorage.Features.EMP.Net)

local EMPController = {}

local FIRE_ACTION = "EmpFire"
local FIRE_KEY = Enum.KeyCode.F

function EMPController.Start()
	local player = Players.LocalPlayer
	local camera = workspace.CurrentCamera

	local gui = Instance.new("ScreenGui")
	gui.Name = "EmpHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	-- The charge readout moved to the shared carried-kit strip (Features.Loadout,
	-- declared in this feature's Loadout.luau). Five features each choosing their
	-- own bottom-screen offset had produced four overlapping pairs.

	-- What the burst actually did. Driven by the server's one-shot signal rather
	-- than by the charge count, because "NOTHING IN RANGE" and "3 DISABLED" both
	-- spend exactly one charge and have to read differently.
	local result = Instance.new("TextLabel")
	result.Size = UDim2.fromOffset(420, 34)
	result.Position = UDim2.new(0.5, 0, 1, -164)
	result.AnchorPoint = Vector2.new(0.5, 1)
	result.BackgroundTransparency = 1
	result.TextColor3 = Constants.COLOR
	result.TextTransparency = 1
	result.TextSize = 24
	result.Font = Enum.Font.GothamBold
	result.Text = ""
	result.Parent = gui
	local resultStroke = Instance.new("UIStroke")
	resultStroke.Thickness = 2
	resultStroke.Color = Color3.fromRGB(0, 0, 0)
	resultStroke.Transparency = 1
	resultStroke.Parent = result

	player:GetAttributeChangedSignal("EmpResult"):Connect(function()
		local value = player:GetAttribute("EmpResult")
		if typeof(value) ~= "string" then
			return
		end
		result.Text = string.match(value, "^(.-)|") or value
		local fadeIn = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local fadeOut = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(result, fadeIn, { TextTransparency = 0 }):Play()
		TweenService:Create(resultStroke, fadeIn, { Transparency = 0 }):Play()
		task.delay(1.2, function()
			TweenService:Create(result, fadeOut, { TextTransparency = 1 }):Play()
			TweenService:Create(resultStroke, fadeOut, { Transparency = 1 }):Play()
		end)
	end)

	-- Aim off the CURSOR, exactly like the gun — the pointer is the aiming
	-- device in this game's third-person camera, and two weapons that aimed
	-- differently would be a worse problem than either one aiming badly.
	local function aimDirection(): Vector3?
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not root then
			return nil
		end
		local cursor = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(cursor.X, cursor.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local hit = workspace:Raycast(ray.Origin, ray.Direction * Constants.RANGE, params)
		local aimPoint = if hit then hit.Position else ray.Origin + ray.Direction * Constants.RANGE
		local delta = aimPoint - (root.Position + Vector3.new(0, 2, 0))
		if delta.Magnitude < 0.001 then
			return nil
		end
		return delta.Unit
	end

	ContextActionService:BindAction(FIRE_ACTION, function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		local direction = aimDirection()
		if direction then
			Net.Fire.send({ direction = direction })
		end
		return Enum.ContextActionResult.Sink
	end, false, FIRE_KEY)
end

return EMPController
