--!strict
-- Compass HUD: an arrow pinned top-centre that points toward the next sealed-
-- district gate inward (largest-radius gate still closer to the centre than
-- the player), falling back to world-centre (0,0,0) once inside the innermost
-- gate. Only visible once the local player has HasCompass (the Compass pickup
-- grants it, per-run, server-side).
--
-- It's a bearing, not a path: this ignores walls on purpose. Knowing the gate
-- is north-east still leaves you solving the ring to reach it — that's the
-- feature, not a bug. Needs no district maths on the client: radii alone give
-- the right answer, and the folder is re-read live every frame so it self-
-- heals across maze rebuilds.
--
-- Auto-loaded: name ends in `Controller`.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Pickups.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CompassController = {}

function CompassController.Start()
	local player = Players.LocalPlayer
	local camera = Workspace.CurrentCamera

	local gui = Instance.new("ScreenGui")
	gui.Name = "CompassHud"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(48, 48)
	-- Just below the stacked health/stamina bars (top-centre), not overlapping.
	frame.Position = UDim2.new(0.5, 0, 0, 116)
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = gui

	local arrow = Instance.new("TextLabel")
	arrow.Size = UDim2.fromScale(1, 1)
	arrow.BackgroundTransparency = 1
	arrow.Text = "▲"
	arrow.TextColor3 = Color3.fromRGB(80, 200, 255)
	arrow.TextSize = 36
	arrow.Font = Enum.Font.GothamBold
	arrow.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Parent = arrow

	RunService.Heartbeat:Connect(function()
		local hasCompass = player:GetAttribute("HasCompass") == true
		frame.Visible = hasCompass
		if not hasCompass then
			return
		end

		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then
			return
		end

		-- Next gate inward: the largest-radius gate still smaller than the
		-- player's own radius. None found (already past the innermost gate) =>
		-- fall back to world-centre.
		local playerR = Vector2.new(hrp.Position.X, hrp.Position.Z).Magnitude
		local target, targetR = Vector3.zero, -1
		local gates = Workspace:FindFirstChild("Gates")
		for _, gate in (gates and gates:GetChildren() or {}) do
			if not gate:IsA("BasePart") then
				continue
			end
			-- Aim at the opening's centre, not the part: a gate is pillars + a
			-- lintel, and the pillars sit on the gap's edges. Up close, pointing at
			-- a pillar aims you at the wall beside the way through.
			local centre = gate:GetAttribute("GateCenter")
			local pos = if typeof(centre) == "Vector3" then centre :: Vector3 else gate.Position
			local r = Vector2.new(pos.X, pos.Z).Magnitude
			if r < playerR and r > targetR then
				target, targetR = pos, r
			end
		end

		local toTarget = Vector3.new(target.X - hrp.Position.X, 0, target.Z - hrp.Position.Z)
		if toTarget.Magnitude < 0.01 then
			return
		end

		local camLook = camera.CFrame.LookVector
		local camFlat = Vector3.new(camLook.X, 0, camLook.Z)
		if camFlat.Magnitude < 0.01 then
			return
		end

		local targetYaw = math.atan2(toTarget.X, toTarget.Z)
		local camYaw = math.atan2(camFlat.X, camFlat.Z)
		local bearing = targetYaw - camYaw

		arrow.Rotation = math.deg(bearing)
	end)
end

return CompassController
