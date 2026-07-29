--!strict
-- Navigation graph for the current maze: cell-centre world positions + open-
-- passage adjacency. MazeService populates it after generating; AI (HunterService)
-- reads it to walk the corridors, since Roblox PathfindingService can't navigate
-- the thin curved ring walls. Server-side shared state (both requirers get the
-- same cached module instance in the server VM).
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Maze.MazeNav.

local MazeNav = {}

MazeNav.ready = false
MazeNav.cellPos = {} :: { [number]: Vector3 } -- [cellKey] -> floor-centre of the cell
MazeNav.adj = {} :: { [number]: { number } } -- [cellKey] -> connected cellKeys

-- XZ radius of the perimeter wall: the edge of the maze proper. Anything beyond
-- it is the staging room and its corridor, which are NOT part of the maze — no
-- cell exists out there, so nothing that navigates by this graph belongs there
-- either. HunterService uses it to keep hunters inside and to treat the staging
-- room as a sanctuary. Published by MazeService.rebuild alongside the graph; 0
-- until the first build.
MazeNav.perimeterR = 0

function MazeNav.cellKey(band: number, sector: number): number
	return band * 1000 + sector
end

-- Band (ring) index of a cellKey. Smaller = deeper (0 = centre hub).
function MazeNav.bandOf(cellKey: number): number
	return cellKey // 1000
end

-- Band ranges per district, inner -> outer. THE single source of truth for the
-- district layout: MazeService carves and gates off this, CheckpointService and
-- the compass read districts through `districtOf`.
--
-- Deliberately NOT four bands each. Circumference grows with radius, so equal
-- ring counts give wildly unequal search areas — at 4/4/4 the outer district
-- held 192 cells against the inner's 54, meaning the district you solve first
-- (no compass yet, mechanic not yet learned) was ~4x the work of the one you
-- solve last. 6/3/3 bands gives ~102/120/144 cells: still funnelling inward,
-- but the outer district is 1.4x the inner rather than 3.6x.
local DISTRICT_BANDS = { { 1, 6 }, { 7, 9 }, { 10, 12 } }
MazeNav.DISTRICT_BANDS = DISTRICT_BANDS

-- District index of a band: 0 = hub (band 0), then 1 = inner .. 3 = outer.
-- Shared here (not duplicated per-file) because MazeService (carving/gates) and
-- CheckpointService (respawn tracking) need the exact same mapping.
function MazeNav.districtOf(band: number): number
	if band == 0 then
		return 0
	end
	for i, range in DISTRICT_BANDS do
		if band >= range[1] and band <= range[2] then
			return i
		end
	end
	return #DISTRICT_BANDS
end

-- Outermost band index in the current maze (0 if empty).
function MazeNav.maxBand(): number
	local m = 0
	for key in MazeNav.cellPos do
		local b = key // 1000
		if b > m then
			m = b
		end
	end
	return m
end

function MazeNav.reset()
	MazeNav.cellPos = {}
	MazeNav.adj = {}
	MazeNav.perimeterR = 0
	MazeNav.ready = false
end

-- Nearest cell to a world position (XZ). Cheap enough at repath cadence.
function MazeNav.nearestCell(pos: Vector3): number?
	local best, bestDist = nil, math.huge
	for key, c in MazeNav.cellPos do
		local dx, dz = c.X - pos.X, c.Z - pos.Z
		local d = dx * dx + dz * dz
		if d < bestDist then
			best, bestDist = key, d
		end
	end
	return best
end

-- First cell to step to on the shortest open path from `fromKey` to `toKey`.
function MazeNav.nextStep(fromKey: number, toKey: number): number?
	if fromKey == toKey then
		return nil
	end
	local prev: { [number]: number } = { [fromKey] = fromKey }
	local queue = { fromKey }
	local head = 1
	while head <= #queue do
		local cur = queue[head]
		head += 1
		for _, nb in MazeNav.adj[cur] or {} do
			if not prev[nb] then
				prev[nb] = cur
				if nb == toKey then
					local step = nb
					while prev[step] ~= fromKey do
						step = prev[step]
					end
					return step
				end
				table.insert(queue, nb)
			end
		end
	end
	return nil
end

return MazeNav
