--!strict
-- The "caught" sequence. When the server flags the local player Caught (the
-- hunter reached them), take over the camera to stare up at the looming hunter,
-- flash red, shake, and fade to black — then fade back in when the server has
-- moved them to their checkpoint (Caught cleared).
--
-- Auto-loaded: name ends in `Controller`.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Hunter.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local HunterController = {}

function HunterController.Start()
	local player = Players.LocalPlayer
	local camera = workspace.CurrentCamera

	local gui = Instance.new("ScreenGui")
	gui.Name = "CaughtOverlay"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100
	gui.Parent = player:WaitForChild("PlayerGui")

	local black = Instance.new("Frame")
	black.Size = UDim2.fromScale(1, 1)
	black.BackgroundColor3 = Color3.new(0, 0, 0)
	black.BackgroundTransparency = 1
	black.BorderSizePixel = 0
	black.Parent = gui

	local red = Instance.new("Frame")
	red.Size = UDim2.fromScale(1, 1)
	red.BackgroundColor3 = Color3.fromRGB(120, 0, 0)
	red.BackgroundTransparency = 1
	red.BorderSizePixel = 0
	red.Parent = gui

	local shakeConn: RBXScriptConnection? = nil

	local function stopShake()
		if shakeConn then
			shakeConn:Disconnect()
			shakeConn = nil
		end
	end

	player:GetAttributeChangedSignal("Caught"):Connect(function()
		if player:GetAttribute("Caught") then
			-- Look up at the hunter looming over you, with a jittery shake.
			camera.CameraType = Enum.CameraType.Scriptable
			stopShake()
			shakeConn = RunService.RenderStepped:Connect(function()
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				-- Look at whichever hunter is nearest (the one that got you).
				local look: BasePart? = nil
				if hrp then
					local bestD = math.huge
					for _, m in workspace:GetChildren() do
						if m:IsA("Model") and m.Name == "Hunter" then
							local eye = (m:FindFirstChild("Eye") or m.PrimaryPart) :: BasePart?
							if eye then
								local d = (eye.Position - hrp.Position).Magnitude
								if d < bestD then
									bestD, look = d, eye
								end
							end
						end
					end
				end
				if hrp and look then
					local base = hrp.Position + Vector3.new(0, 2.5, 0)
					local shake = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 0.9
					camera.CFrame = CFrame.lookAt(base + shake, look.Position)
				end
			end)
			-- Red hit-flash, then sink to black.
			red.BackgroundTransparency = 0.35
			TweenService:Create(red, TweenInfo.new(0.9), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(black, TweenInfo.new(1.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 0 }):Play()
		else
			-- Recovered at the checkpoint: hand the camera back and fade in.
			stopShake()
			camera.CameraType = Enum.CameraType.Custom
			TweenService:Create(black, TweenInfo.new(0.55), { BackgroundTransparency = 1 }):Play()
		end
	end)
end

return HunterController
