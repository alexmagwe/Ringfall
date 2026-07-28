--!strict
-- Haul HUD: a bottom-right readout of the local player's Haul, flashing
-- briefly on increase. Purely cosmetic — SalvageService owns the Haul
-- attribute; this only reacts to it changing. Raw instances, not React (see
-- CLAUDE.md: gameplay HUDs are raw instances).
--
-- Auto-loaded: name ends in `Controller`.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Salvage.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local SalvageController = {}

local BASE_COLOR = Color3.fromRGB(255, 230, 160)
local FLASH_COLOR = Color3.fromRGB(255, 255, 255)

function SalvageController.Start()
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "SalvageHud"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromOffset(240, 40)
	label.Position = UDim2.new(1, -12, 1, -12)
	label.AnchorPoint = Vector2.new(1, 1)
	label.BackgroundTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.TextColor3 = BASE_COLOR
	label.TextSize = 28
	label.Font = Enum.Font.GothamBold
	label.Text = "HAUL 0"
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Parent = label

	-- Same fade idiom PickupsController uses for its toast: a quick tween in,
	-- a slower tween back to rest.
	local function flash()
		local fadeIn = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local fadeOut = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(label, fadeIn, { TextColor3 = FLASH_COLOR }):Play()
		task.delay(0.1, function()
			TweenService:Create(label, fadeOut, { TextColor3 = BASE_COLOR }):Play()
		end)
	end

	local lastHaul = 0
	player:GetAttributeChangedSignal("Haul"):Connect(function()
		local haul = player:GetAttribute("Haul")
		local amount = if typeof(haul) == "number" then haul else 0
		label.Text = "HAUL " .. tostring(amount)
		if amount > lastHaul then
			flash()
		end
		lastHaul = amount
	end)

	-- Objective callout on taking the vault. Without it the biggest turn in the
	-- round — you now hold the thing everyone wants, every hunter is coming, and
	-- the goal has flipped from "go in" to "get out" — happens silently, and a
	-- new player has no idea what changed or where to go.
	local callout = Instance.new("TextLabel")
	callout.Size = UDim2.fromOffset(720, 56)
	callout.Position = UDim2.fromScale(0.5, 0.3)
	callout.AnchorPoint = Vector2.new(0.5, 0.5)
	callout.BackgroundTransparency = 1
	callout.TextColor3 = Color3.fromRGB(255, 205, 90)
	callout.TextSize = 34
	callout.Font = Enum.Font.GothamBold
	callout.TextTransparency = 1
	callout.Text = "VAULT SECURED — GET IT BACK TO THE POD"
	callout.Parent = gui
	local calloutStroke = Instance.new("UIStroke")
	calloutStroke.Thickness = 2
	calloutStroke.Color = Color3.fromRGB(0, 0, 0)
	calloutStroke.Transparency = 1
	calloutStroke.Parent = callout

	player:GetAttributeChangedSignal("HasVault"):Connect(function()
		if player:GetAttribute("HasVault") ~= true then
			return
		end
		local fadeIn = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local fadeOut = TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(callout, fadeIn, { TextTransparency = 0 }):Play()
		TweenService:Create(calloutStroke, fadeIn, { Transparency = 0 }):Play()
		task.delay(4, function()
			TweenService:Create(callout, fadeOut, { TextTransparency = 1 }):Play()
			TweenService:Create(calloutStroke, fadeOut, { Transparency = 1 }):Play()
		end)
	end)
end

return SalvageController
