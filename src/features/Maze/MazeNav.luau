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

function MazeNav.cellKey(band: number, sector: number): number
	return band * 1000 + sector
end

-- Band (ring) index of a cellKey. Smaller = deeper (0 = centre hub).
function MazeNav.bandOf(cellKey: number): number
	return cellKey // 1000
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
