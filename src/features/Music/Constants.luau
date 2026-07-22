--!strict
-- Ambient music config for the maze. This is the ONE place to set the track.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Music.Constants.

return {
	-- rbxassetid of the looping ambient track. Must be audio this experience is
	-- allowed to play: owned by the game's creator, or a Roblox-provided /
	-- permission-granted asset. Audio you insert from the Studio Toolbox counts.
	-- Leave as "rbxassetid://0" to disable the loop (MusicController warns + skips).
	TRACK_ID = "rbxassetid://103950344109343", -- Dark Ambient Forest

	-- Low by design: music sits under the ambience/SFX layer (GDD 11.2).
	VOLUME = 0.15,
}
