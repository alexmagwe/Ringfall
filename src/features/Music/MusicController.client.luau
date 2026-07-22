--!strict
-- Loops one ambient track for the local player from join, through the shared
-- audio system. Client-side: each player drives their own loop (SoundService),
-- independent of the server. Swap the track in Music/Constants.luau.
--
-- Auto-loaded: name ends in `Controller`, so the client entry Start()s it.
-- A later fog-rise controller can call `audio.playLoop(tenseId)` to cross-swap
-- this same music slot when the fog cycle escalates (GDD 4.2 / 11.2).
--
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Music.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Reach the shared audio system through the framework's public surface, not a
-- deep Shared.audio path (enforced by tools/check-framework-boundary).
local Boil = require(ReplicatedStorage.Shared.Boil)
-- Constants is a plain .luau, so the splitter routes it to ReplicatedStorage,
-- not alongside this client script in PlayerScripts.
local Constants = require(ReplicatedStorage.Features.Music.Constants)

local MusicController = {}

function MusicController.Start()
	local id = Constants.TRACK_ID
	if id == "rbxassetid://0" or id == "" then
		warn("[Music] no TRACK_ID set in Music/Constants.luau — ambient loop disabled")
		return
	end
	Boil.audio.playLoop(id, Constants.VOLUME)
end

return MusicController
