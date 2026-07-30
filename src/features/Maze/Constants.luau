-- Shared constants for the Maze feature. Plain .luau => splitter routes to
-- ReplicatedStorage.Features.Maze.Constants.
--
-- All maze randomness (carve, loop-punching, StairCourt rolls) flows from one
-- Random.new(Constants.SEED) instance in MazeService — change SEED here to
-- reroll the whole layout deterministically.

return {
	SEED = 1001, -- season seed; changing it must change the whole maze

	-- Optional real art for the Vault, placed by the user in Studio as
	-- ServerStorage.MazeModels.Vault. Missing => MazeService builds its own
	-- artifact (glowing core in a broken cage), so the centre reads as a prize
	-- with zero assets. One folder per feature, matching PickupModels and
	-- SalvageModels.
	MODELS_FOLDER = "MazeModels", -- under ServerStorage
	VAULT_MODEL = "Vault",
	GRID = 8, -- 8x8 cells for the slice
	TILE_SIZE = 50, -- studs, square footprint
	WALL_HEIGHT = 36, -- street maze walls (3 storeys)
	WALL_THICKNESS = 3,
	DIVIDE_H = 54, -- district-divide walls: tall, unclimbable
	TOWER_H = 60, -- crossing-tower roof + rooftop-bridge height (5 storeys)
	BEAM_TOP_Y = 260, -- exit sky-beam height
	EXTRA_LOOPS = 6, -- internal walls knocked out after carving (GDD pillar: lost, not stuck)
	-- StairCourt random placement is off for the verticality-districts pass:
	-- rooftops only matter at crossing towers now, so non-crossing tiles stay street.
	ROOF_TILE_CHANCE = 0, -- fraction of StairCourt-eligible cells
}
