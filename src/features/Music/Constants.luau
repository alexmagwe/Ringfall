--!strict
-- Music config. Ringfall is scored as a HEIST THRILLER, not horror: the maze is
-- sunlit and the enemies are giant robot ducks, so dread scoring would fight the
-- art. Play the tension straight and let the absurdity land on its own.
--
-- Four cues matched to the round's phases (see MusicController for the state
-- machine that picks between them).
--
-- ROBLOX AUDIO PRIVACY: you can only play audio owned by this experience's
-- creator (or group), or licensed audio from the Creator Store. A random asset
-- id off the web silently fails to load — the same trap as the crouch animation.
-- Any cue left as "" is simply skipped, so the game runs fine part-scored.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Music.Constants.

return {
	-- Anticipation, over the staging countdown. Rhythmic, building, tightening
	-- as the timer drops. The one place the mix can be loud and confident.
	-- WARNING: this clip is 1.0s long. Looped across a 15s countdown that is
	-- fifteen repeats of a one-second phrase, which will grate badly. Replace it
	-- with a 20s+ bed when you find one; the wiring is fine either way.
	STAGING = { id = "rbxassetid://117751546358455", volume = 0.22 },

	-- The descent: searching a district for its one gate. SPARSE ON PURPOSE —
	-- the hunter drone is the player's only proximity cue, so a dense mix here
	-- deafens them to the single signal that keeps hunters threatening. Low
	-- pulse, texture, lots of space.
	-- 1:34 long — long enough that the loop point isn't obvious across a descent.
	DESCENT = { id = "rbxassetid://105135449947797", volume = 0.12 },

	-- Vault taken: every hunter turns and the goal flips from "go in" to "get
	-- out". Driving and relentless. This is the round's payoff moment and it
	-- currently happens in near-silence.
	-- 33s; loops a couple of times across a return trip, which is fine.
	ALARM = { id = "rbxassetid://7084812679", volume = 0.28 },

	-- Round over. A short resolving sting (~4-5s), NOT a loop.
	-- 3.8s — right in the 4-5s window, and short enough not to smear into the
	-- staging loop that comes up behind it.
	ROUND_END_STING = { id = "rbxassetid://105847593843900", volume = 0.3 },

	-- Seconds to fade a newly-started loop up from silence. ALARM deliberately
	-- ignores this and cuts in hard — the drop should hit, not ease in.
	FADE_TIME = 1.5,

	-- The old single ambient track, kept so nothing silently regresses to it:
	-- "rbxassetid://103950344109343" (Dark Ambient Forest). It was scored for
	-- the night-horror version of the game and no longer fits daylight.
}
