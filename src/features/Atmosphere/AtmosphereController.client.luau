--!strict
-- Sets the maze's dark, foggy mood on the client. Fog is deliberately tight so
-- you can only see ~1-2 rings out — the maze feels vast, and a flashlight (and
-- later, a hunter you hear before you see) actually matters.
--
-- Auto-loaded: name ends in `Controller`.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Atmosphere.

local Lighting = game:GetService("Lighting")

local AtmosphereController = {}

function AtmosphereController.Start()
	Lighting.ClockTime = 0 -- night
	Lighting.Brightness = 1
	Lighting.Ambient = Color3.fromRGB(18, 22, 28)
	Lighting.OutdoorAmbient = Color3.fromRGB(24, 30, 40)
	Lighting.EnvironmentDiffuseScale = 0.25
	Lighting.EnvironmentSpecularScale = 0.1
	Lighting.GlobalShadows = true
	Lighting.FogStart = 20
	Lighting.FogEnd = 130
	Lighting.FogColor = Color3.fromRGB(14, 18, 26)

	local atmos = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmos then
		atmos = Instance.new("Atmosphere")
		atmos.Parent = Lighting
	end
	atmos.Density = 0.42
	atmos.Offset = 0.1
	atmos.Haze = 2.4
	atmos.Glare = 0
	atmos.Color = Color3.fromRGB(120, 132, 150)
	atmos.Decay = Color3.fromRGB(26, 34, 48)
end

return AtmosphereController
