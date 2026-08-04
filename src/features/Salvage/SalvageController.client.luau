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


function SalvageController.Start()
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "SalvageHud"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- The HAUL readout moved to the shared carried-kit strip (Features.Loadout,
	-- declared in this feature's Loadout.luau), which also owns the flash-on-rise
	-- that used to live here. It shared the bottom-right corner with the gun's
	-- ammo line and the two overlapped.

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
