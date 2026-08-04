--!strict
-- Plain .luau => ReplicatedStorage.Features.Skateboard.Constants (both realms).
return {
	-- What riding is worth. Applied to whichever speed is in force (walk OR
	-- sprint) via the `SpeedMultiplier` attribute that SprintController reads —
	-- 1.5 means half again as fast either way, ~26 walking and ~43 sprinting.
	SPEED_MULTIPLIER = 1.5,

	-- WHERE IT WON'T ROLL. Keyed by MazeNav district index: 0 = the centre hub,
	-- 1 = inner, 2 = middle (flooded), 3 = outer (overgrown).
	--
	-- District 3 is the grass ring — MazeService.DISTRICT_LOOKS maps it to
	-- Dressing.OVERGROWN, whose `groundMaterial` is Grass. Wheels don't roll on
	-- turf, so the board is dead weight for the whole outer district and the
	-- player has to run the longest leg on foot. If that dressing ever moves to
	-- another district, this moves with it — the mapping lives in MazeService,
	-- not here, so nothing enforces the pair but this comment.
	--
	-- The staging room and its corridor are outside the maze entirely (no cell,
	-- so no district); see SkateboardService.districtAt, which treats "not in
	-- the maze" as rideable so the run-up out of the door isn't dead.
	BLOCKED_DISTRICTS = { [3] = true },

	-- Player attributes this feature owns. `HasSkateboard` is the pickup grant;
	-- `Riding` is the live state, which the HUD and the welded art both follow.
	HAS_ATTRIBUTE = "HasSkateboard",
	RIDING_ATTRIBUTE = "RidingSkateboard",

	-- Art. Same convention as every other pickup: a child of
	-- ServerStorage.PickupModels, and a built-from-code board if it's absent, so
	-- the feature works before the user makes anything.
	-- The child of ServerStorage.PickupModels to clone, matched EXACTLY —
	-- FindFirstChild is case-sensitive, and this is spelled the way the art in
	-- this place is actually spelled (capital B). Naming the child is the whole
	-- point of the `model` field convention: the art can be called anything, and
	-- this is what says which anything.
	MODEL_NAME = "SkateBoard",
	DECK_COLOR = Color3.fromRGB(38, 42, 50),
	TRIM_COLOR = Color3.fromRGB(235, 170, 60),

	-- Nose-to-tail length in studs, and the ONE number that decides how big the
	-- board looks. An R15 character measures about 5.5 studs, so this is roughly
	-- 0.72 of the rider's height.
	--
	-- Tuned by eye, in both directions. The first pass was 5 — as long as the
	-- rider is tall, which read as a surfboard. Real-world proportions say a bit
	-- under half the rider's height, and 3.2 landed there and looked like a toy
	-- under a Roblox character. Blocky avatars have wide feet and a wide stance,
	-- so the realistic number is the wrong one here; 4 is what actually sits
	-- right underneath one.
	--
	-- User art is SCALED TO THIS TOO (see SkateboardService.boardModel), so a
	-- model authored at any size lands at the same footprint instead of the
	-- feature's look depending on how someone happened to export it.
	DECK_LENGTH = 4,

	-- How often the server re-checks which district a rider is standing in.
	-- Cheap but not free (a nearest-cell scan per rider), and a player crossing
	-- a gate at ~43 studs/s covers ~9 studs in this window — well inside a
	-- 40-stud cell, so the board never keeps rolling a whole cell into grass.
	DISTRICT_POLL = 0.2,

	-- Optional skating pose, played on a loop while riding. EMPTY BY DEFAULT:
	-- riding already stops the default walk/run cycle and leaves the rig in its
	-- rest pose, which reads as standing on a board. A real pose needs an
	-- animation uploaded to this game — the same "the user owns the assets" rule
	-- as every model and sound here. Set it to an `rbxassetid://` and the
	-- controller loads and plays it.
	RIDE_ANIMATION = "",

	-- Studs from the character's centre down to the deck's top face. Sized off
	-- the default R15 rig; the art is welded, not physical, so this is purely
	-- how it looks underfoot.
	DECK_DROP = 2.9,
}
