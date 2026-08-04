--!strict
-- Plain .luau => ReplicatedStorage.Features.EMP.Constants (both realms).
return {
	-- Charges bought on the shelf. The attribute is per-run and lost on a catch
	-- like everything else you carry.
	CHARGES_ATTRIBUTE = "EmpCharges",

	-- How far the burst reaches from where it lands, and for how long.
	--
	-- 45 studs is a bit over a cell (40), so a well-placed burst takes the
	-- corridor you are in and the mouth of the next one — a group, not a
	-- individual. 6 seconds is long enough to walk past a pack or break a
	-- spotter's lock and get round a corner, and short enough that it buys a
	-- WINDOW rather than a clear route: you cannot cross a district on one.
	RADIUS = 45,
	SECONDS = 6,

	-- Max distance the burst can be placed from the player. Deliberately shorter
	-- than the gun's aim range: the EMP is a "get this off me" tool, and letting
	-- you disable a pack from across the district before walking in unopposed
	-- turns it into a way to delete encounters rather than survive them.
	RANGE = 90,

	-- Between shots. Two charges fired back to back would just be one 12-second
	-- stun, which is the "clear route" this is priced not to be.
	COOLDOWN = 1.5,

	-- The burst. A ring that expands to RADIUS and fades, so the area it covered
	-- is something you SAW rather than something you infer from which hunters
	-- stopped.
	COLOR = Color3.fromRGB(120, 210, 255),
	RING_SECONDS = 0.45,

	-- User-supplied, like SIREN_SOUND_ID in Hunter. Empty = silent, which works.
	FIRE_SOUND_ID = "",
	FIRE_SOUND_RANGE = 140,
}
