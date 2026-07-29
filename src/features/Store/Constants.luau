--!strict
-- Plain .luau => ReplicatedStorage.Features.Store.Constants (shared realms).
return {
	-- Profile key holding Cash + Unlocked. Registered into the template by
	-- src/features/Maze/PlayerData.luau — the Store requires nothing from Maze,
	-- the two just agree on this key name.
	PROFILE_KEY = "Ringfall",

	-- Defensive cap on inbound packet ids (the client is the source of these,
	-- so we don't trust their length).
	MAX_ITEM_ID_LENGTH = 128,

	-- The terminal StoreService builds inside workspace.Staging on every maze
	-- rebuild, and the CollectionService tag the client binds its prompt to.
	TERMINAL_NAME = "StoreTerminal",
	WORLD_TAG = "StoreTerminal",
	TERMINAL_SIZE = Vector3.new(4, 6, 1.5),
	-- Studs to the SpawnLocation's right. Well inside STAGING_HALF_WIDTH (25),
	-- so the terminal is beside you the moment you spawn rather than hunted for.
	TERMINAL_SIDE_OFFSET = 14,
	TERMINAL_COLOR = Color3.fromRGB(64, 74, 92),
	TERMINAL_SCREEN_COLOR = Color3.fromRGB(120, 220, 255),
	PROMPT_RANGE = 12,
	-- Walking this far from the terminal closes the window. A centred window
	-- blocks the view, so leaving it pinned open while you run is worse than
	-- making you re-trigger the prompt.
	CLOSE_RANGE = 18,

	-- Per-run player attribute: comma-joined ids the player has rented this
	-- round. Server-written, replicates for free, read by the UI to disable a
	-- second buy on non-repeatable items.
	RENTED_ATTRIBUTE = "StoreRented",

	-- How long a rejection message lingers in the window.
	NOTICE_SECONDS = 2.5,

	-- Which presentations are active: a screen (the shelf window) and a world
	-- surface (the terminal's ProximityPrompt that opens it).
	Presentations = {
		screen = true,
		world = true,
	},
}
