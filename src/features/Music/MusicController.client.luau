--!strict
-- Phase-driven music. Ringfall's round has hard turns — a staging countdown, a
-- long quiet descent, the alarm when the vault is taken, then resolution — and
-- the single looping ambient bed this used to be flattens all of them.
--
-- Reads the SAME attributes the gameplay already publishes, so this feature
-- imports nothing from Maze, Salvage or Hunter:
--   workspace.RoundState   "Staging" | "Active"   (EscapeService)
--   workspace.AlarmActive  bool                   (SalvageService)
--   player.HasVault        bool                   (SalvageService)
--
-- Auto-loaded: name ends in `Controller`, so the client entry Start()s it.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Music.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Reach the shared audio system through the framework's public surface, not a
-- deep Shared.audio path (enforced by tools/check-framework-boundary).
local Boil = require(ReplicatedStorage.Shared.Boil)
-- Constants is a plain .luau, so the splitter routes it to ReplicatedStorage,
-- not alongside this client script in PlayerScripts.
local Constants = require(ReplicatedStorage.Features.Music.Constants)

local MusicController = {}

-- Which cue the current world state calls for.
local function currentCue(player: Player): string
	if workspace:GetAttribute("RoundState") ~= "Active" then
		return "STAGING"
	end
	-- Either the alarm is up globally, or this player is the one carrying it.
	if workspace:GetAttribute("AlarmActive") == true or player:GetAttribute("HasVault") == true then
		return "ALARM"
	end
	return "DESCENT"
end

function MusicController.Start()
	local player = Players.LocalPlayer
	local playing: string? = nil

	local function apply()
		local cue = currentCue(player)
		if cue == playing then
			return
		end

		-- Active -> Staging means the round just ended: sting over the results
		-- board, before the staging loop comes back up.
		if playing ~= nil and cue == "STAGING" then
			local sting = Constants.ROUND_END_STING
			if sting.id ~= "" then
				Boil.audio.playSoundId(sting.id, sting.volume)
			end
		end
		playing = cue

		local track = Constants[cue]
		if track.id == "" then
			-- Unscored cue: stop, rather than leave the previous phase's music
			-- running underneath it — wrong music is worse than silence.
			Boil.audio.stopMusic()
			return
		end

		local sound = Boil.audio.playLoop(track.id, track.volume, cue)
		if not sound then
			return
		end
		-- The alarm cuts in hard on purpose; everything else eases up.
		if cue == "ALARM" then
			sound.Volume = track.volume
			return
		end
		sound.Volume = 0
		TweenService:Create(sound, TweenInfo.new(Constants.FADE_TIME), { Volume = track.volume }):Play()
	end

	workspace:GetAttributeChangedSignal("RoundState"):Connect(apply)
	workspace:GetAttributeChangedSignal("AlarmActive"):Connect(apply)
	player:GetAttributeChangedSignal("HasVault"):Connect(apply)
	apply()
end

return MusicController
