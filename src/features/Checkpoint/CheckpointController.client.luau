--!strict
-- Shows a brief "CHECKPOINT" toast when the local player crosses into a deeper
-- ring (CheckpointService bumps the CheckpointRing attribute). Purely feedback;
-- the respawn/safe logic lives server-side.
--
-- Auto-loaded: name ends in `Controller`.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Checkpoint.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local CheckpointController = {}

function CheckpointController.Start()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "CheckpointHud"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromOffset(360, 44)
	label.Position = UDim2.new(0.5, 0, 0.24, 0)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Text = "CHECKPOINT"
	label.TextColor3 = Color3.fromRGB(150, 235, 175)
	label.TextTransparency = 1
	label.TextSize = 34
	label.Font = Enum.Font.GothamBold
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Transparency = 1
	stroke.Parent = label

	player:GetAttributeChangedSignal("CheckpointRing"):Connect(function()
		local fadeIn = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local fadeOut = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(label, fadeIn, { TextTransparency = 0 }):Play()
		TweenService:Create(stroke, fadeIn, { Transparency = 0 }):Play()
		task.delay(1.1, function()
			TweenService:Create(label, fadeOut, { TextTransparency = 1 }):Play()
			TweenService:Create(stroke, fadeOut, { Transparency = 1 }):Play()
		end)
	end)
end

return CheckpointController
