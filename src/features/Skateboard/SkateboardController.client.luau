--!strict
-- Client side of the skateboard: the ride key, and a readout that says whether
-- you are on it. Everything else — whether the toggle is allowed, where it
-- rolls, how fast you go — is SkateboardService's call. This is a dumb surface:
-- it sends one request and draws three server-owned attributes.
--
-- Auto-loaded: name ends in `Controller`.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Skateboard.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Features.Skateboard.Constants)
local Net = require(ReplicatedStorage.Features.Skateboard.Net)

local SkateboardController = {}

local RIDE_ACTION = "SkateboardToggleRide"
local RIDE_KEY = Enum.KeyCode.R
local RIDING_COLOR = Color3.fromRGB(235, 170, 60)

function SkateboardController.Start()
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "SkateboardHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	-- The ride readout moved to the shared carried-kit strip (Features.Loadout,
	-- declared in this feature's Loadout.luau). What stays here is the part that
	-- is not a label: the rig's pose.

	-- STOP THE LEGS. Roblox's default `Animate` script drives walk/run off
	-- `Humanoid.MoveDirection`, and riding does not change that — so a rider
	-- sprinted on the spot, on top of a board that was carrying them. The board
	-- read as scenery stuck to their feet rather than as the thing moving them.
	--
	-- Disabling `Animate` and stopping every track leaves the rig in its rest
	-- pose, which is exactly "standing on a board". Toggling `Disabled` back to
	-- false re-runs the script from the top, which re-registers its idle — that
	-- restart is what makes this reversible rather than a one-way trip.
	--
	-- Done CLIENT-SIDE, on the local character. Animation replicates outward from
	-- whoever is animating, so stopping it here is what every other player sees
	-- too; doing it from the server would fight the client that owns the rig.
	--
	-- `RIDE_ANIMATION` is the seam for a real skating pose. Empty by default,
	-- because inventing an animation asset is not something this file can do —
	-- see docs/game/Skateboard.md.
	local ridePose: AnimationTrack? = nil

	local function setRidePose(riding: boolean)
		local char = player.Character
		if not char then
			return
		end
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		local animate = char:FindFirstChild("Animate")

		if animate and animate:IsA("LuaSourceContainer") then
			animate.Disabled = riding
		end

		if ridePose then
			ridePose:Stop(0.15)
			ridePose = nil
		end

		if not animator or not riding then
			return
		end

		-- Stop AFTER disabling Animate, or it would start a fresh walk cycle on
		-- the very next frame and undo this.
		for _, track in animator:GetPlayingAnimationTracks() do
			track:Stop(0.1)
		end

		if Constants.RIDE_ANIMATION == "" then
			return
		end
		local anim = Instance.new("Animation")
		anim.AnimationId = Constants.RIDE_ANIMATION
		local ok, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if not ok or not track then
			return
		end
		ridePose = track
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Action
		track:Play(0.15)
	end

	local function update()
		setRidePose(player:GetAttribute(Constants.RIDING_ATTRIBUTE) == true)
	end

	player:GetAttributeChangedSignal(Constants.HAS_ATTRIBUTE):Connect(update)
	player:GetAttributeChangedSignal(Constants.RIDING_ATTRIBUTE):Connect(update)
	-- A respawn hands us a brand-new rig with a brand-new enabled `Animate`. The
	-- server drops the ride on CharacterAdded, but this side has to re-read
	-- against the new character rather than trusting the old one's state.
	player.CharacterAdded:Connect(function()
		ridePose = nil
		task.defer(update)
	end)
	update()

	-- Why the board just refused, or just threw you off. Driven by the server's
	-- one-shot "message|nonce" signal rather than by the riding attribute, so
	-- pressing R twice on grass explains itself twice.
	local notice = Instance.new("TextLabel")
	notice.Size = UDim2.fromOffset(420, 34)
	-- Directly above the readout, clear of the pickup toast (which sits at
	-- y = -70, 40 tall).
	notice.Position = UDim2.new(0.5, 0, 1, -206)
	notice.AnchorPoint = Vector2.new(0.5, 1)
	notice.BackgroundTransparency = 1
	notice.TextColor3 = RIDING_COLOR
	notice.TextTransparency = 1
	notice.TextSize = 22
	notice.Font = Enum.Font.GothamBold
	notice.Text = ""
	notice.Parent = gui
	local noticeStroke = Instance.new("UIStroke")
	noticeStroke.Thickness = 2
	noticeStroke.Color = Color3.fromRGB(0, 0, 0)
	noticeStroke.Transparency = 1
	noticeStroke.Parent = notice

	player:GetAttributeChangedSignal("SkateboardNotice"):Connect(function()
		local value = player:GetAttribute("SkateboardNotice")
		if typeof(value) ~= "string" then
			return
		end
		notice.Text = string.match(value, "^(.-)|") or value
		local fadeIn = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local fadeOut = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(notice, fadeIn, { TextTransparency = 0 }):Play()
		TweenService:Create(noticeStroke, fadeIn, { Transparency = 0 }):Play()
		task.delay(1.4, function()
			TweenService:Create(notice, fadeOut, { TextTransparency = 1 }):Play()
			TweenService:Create(noticeStroke, fadeOut, { Transparency = 1 }):Play()
		end)
	end)

	-- Request only. The server re-checks that you hold a board and that the
	-- ground under you takes wheels.
	ContextActionService:BindAction(RIDE_ACTION, function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		Net.ToggleRide.send()
		return Enum.ContextActionResult.Sink
	end, false, RIDE_KEY)
end

return SkateboardController
