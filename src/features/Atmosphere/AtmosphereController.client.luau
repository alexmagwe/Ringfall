--!strict
-- Sets the maze's mood on the client. Currently DAYLIGHT: hazy distance so the
-- maze still feels vast, but readable at every range.
--
-- History, so this isn't "fixed" back: the original was ClockTime 0 with
-- Ambient (18,22,28), FogEnd 130 and Atmosphere Density 0.42. That was set when
-- a run was "walk inward, avoid hunters" and visibility barely mattered. Sealed
-- districts made SEARCHING A RING for its one gate the core activity, and
-- searching in the dark isn't tense, it's tedious. The decisive problem was
-- ClockTime 0: the maze is open-topped, so the sky is its light source, and at
-- midnight there is no sun or moon at all — Ambient was doing 100% of the work,
-- which is why raising Ambient alone never fixed it.
--
-- Fog and Atmosphere colours must track the time of day. Dark-blue fog under a
-- daylight sky reads as a rendering fault, not as distance.
--
-- NOTE: daylight is why there is no light source in the game. The Flashlight
-- feature and its Floodlight shelf item were deleted rather than left on sale,
-- because a 250-cash unlock that buys nothing is worse than no option at all.
-- If the game moves back toward horror, change ClockTime (try 5.1 for blue
-- hour) and darken FogColor/Atmosphere.Color to match — not Ambient on its own
-- — and bring a light source back with it.
--
-- Auto-loaded: name ends in `Controller`.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Atmosphere.

local Lighting = game:GetService("Lighting")

local AtmosphereController = {}

function AtmosphereController.Start()
	-- Daylight. The maze is open-topped, so the sky IS the light source: at the
	-- old ClockTime 0 there was no sun or moon at all and Ambient was doing 100%
	-- of the work, which is why raising Ambient alone never fixed the darkness.
	-- 14.0 is mid-afternoon — sun high enough to reach the maze floor between
	-- 40-stud walls, but off vertical so the walls still cast readable shadows.
	Lighting.ClockTime = 14
	-- CONTRAST, NOT BRIGHTNESS. Ambient used to be (120,128,140) with
	-- OutdoorAmbient at (140,150,165), which is a lot of fill light. Fill light
	-- lands on every face of every part equally, so nothing has a lit side and a
	-- shadowed side, and every surface reads as flat plastic. That — not the
	-- geometry, and not the material — is what made the maze look cheap.
	--
	-- The fix is to take light AWAY from the fill and leave it in the sun. The
	-- maze is open-topped and the sun does the real work at ClockTime 14, so
	-- corridors and the floor stay just as readable; what changes is that walls
	-- now have a bright face and a dark face, and everything standing on the
	-- floor sits in its own shadow.
	--
	-- Do not "fix" darkness by raising these two. That is the same mistake the
	-- header describes, one step further on: the reason the old midnight setting
	-- failed was no sun, and the reason the daylight setting looked flat was too
	-- much fill. Raise Brightness, or move ClockTime, and leave the fill low.
	Lighting.Brightness = 3.5
	Lighting.Ambient = Color3.fromRGB(40, 44, 52)
	Lighting.OutdoorAmbient = Color3.fromRGB(95, 105, 122)
	-- Sky-derived diffuse is fill light too, by another name. At 1 it was
	-- undoing part of the cut above.
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true
	-- ~5 bands of sight (a band is 42 studs) rather than ~2. Walls still block
	-- most sightlines, so this mostly opens up long corridors and the floor.
	-- Pale haze, not the old dark-blue murk — dark fog in daylight reads as a
	-- rendering fault rather than distance.
	Lighting.FogStart = 45
	Lighting.FogEnd = 240
	Lighting.FogColor = Color3.fromRGB(168, 178, 190)

	local atmos = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmos then
		atmos = Instance.new("Atmosphere")
		atmos.Parent = Lighting
	end
	-- Atmosphere density stacks ON TOP of the distance fog above; at the old
	-- 0.42 with Haze 2.4 the two together were most of the murk.
	atmos.Density = 0.18
	atmos.Offset = 0.1
	atmos.Haze = 1.2
	atmos.Glare = 0.1
	atmos.Color = Color3.fromRGB(190, 198, 208)
	atmos.Decay = Color3.fromRGB(150, 165, 185)

	-- Roblox ships a default DepthOfField in Lighting. Its far-blur compounds
	-- with the fog above and reads as yet more murk, so neutralise it rather
	-- than fighting it with brightness. Left in place (not destroyed) so it can
	-- be re-tuned from Studio if a deliberate DoF look is ever wanted.
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if dof then
		dof.Enabled = false
	end
end

return AtmosphereController
