--!strict
-- Phase-driven music. Ringfall's round has hard turns — a staging countdown, a
-- long quiet descent, the alarm when the vault is taken, then resolution — and
-- the single looping ambient bed this used to be flattens all of them.
--
-- Reads the SAME attributes the gameplay already publishes, so this feature
-- imports nothing from Maze, Salvage or Hunter:
--   workspace.RoundState   "Staging" | "Active"   (EscapeService)  -> which loop
--   workspace.AlarmActive  bool                   (SalvageService) -> siren sting
--
-- Two different things: RoundState picks the looping bed, AlarmActive fires a
-- one-shot over the top of it. The alarm is an EVENT, not a phase.
--
-- Auto-loaded: name ends in `Controller`, so the client entry Start()s it.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Music.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Reach the shared audio system through the framework's public surface, not a
-- deep Shared.audio path (enforced by tools/check-framework-boundary).
local Boil = require(ReplicatedStorage.Shared.Boil)
-- Constants is a plain .luau, so the splitter routes it to ReplicatedStorage,
-- not alongside this client script in PlayerScripts.
local Constants = require(ReplicatedStorage.Features.Music.Constants)

local MusicController = {}

-- Which looping bed the current world state calls for. The alarm is deliberately
-- absent: it's a sting layered over whichever of these is running, so taking the
-- vault no longer swaps the bed out from under the return trip.
local function currentCue(): string
	if workspace:GetAttribute("RoundState") ~= "Active" then
		return "STAGING"
	end
	return "DESCENT"
end

function MusicController.Start()
	local playing: string? = nil

	-- Siren over the top of the running loop, cut to ALARM_STING_SECONDS with a
	-- short fade — the clip is far longer than the moment it scores, and a hard
	-- cut on a sustained siren clicks.
	local function playAlarmSting()
		local track = Constants.ALARM
		if track.id == "" then
			return
		end
		local sound = Boil.audio.playSoundId(track.id, track.volume)
		local holdFor = math.max(Constants.ALARM_STING_SECONDS - Constants.ALARM_STING_FADE, 0)
		task.delay(holdFor, function()
			if not sound.IsPlaying then
				return -- already ended on its own and cleaned itself up
			end
			TweenService:Create(sound, TweenInfo.new(Constants.ALARM_STING_FADE), { Volume = 0 }):Play()
			task.delay(Constants.ALARM_STING_FADE, function()
				sound:Destroy()
			end)
		end)
	end

	local function apply()
		local cue = currentCue()
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
		sound.Volume = 0
		TweenService:Create(sound, TweenInfo.new(Constants.FADE_TIME), { Volume = track.volume }):Play()
	end

	workspace:GetAttributeChangedSignal("RoundState"):Connect(apply)

	-- Fires for EVERY player, not just the carrier: the vault going is a
	-- maze-wide event (every compass swings, every hunter turns), so everyone
	-- should hear it. Guarded on the value because the signal also fires when
	-- MazeService clears the attribute on rebuild.
	workspace:GetAttributeChangedSignal("AlarmActive"):Connect(function()
		if workspace:GetAttribute("AlarmActive") ~= true then
			return
		end
		playAlarmSting()
	end)

	apply()
end

return MusicController
