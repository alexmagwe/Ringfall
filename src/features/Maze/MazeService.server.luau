--!strict
-- Circular (theta) maze: concentric ring-bands around a central evac hub. The
-- player spawns at a gate in the outer wall and runs INWARD through gaps in each
-- ring wall to reach the glowing EvacPad at the centre (the win trigger).
-- Deterministic from Constants.SEED.
--
-- Cells are polar regions (band, sector). Band 0 is the central hub (1 cell).
-- Sector counts only ever double outward, so neighbour mapping across bands is
-- clean: an inner cell fans out to `ratio` outer cells; an outer cell folds back
-- to one inner cell. Walls are radial spokes (between sectors) + arc segments
-- (between bands); a wall exists wherever there is NO carved passage.
--
-- .server.luau => splitter routes to ServerScriptService.Features.Maze.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Features.Maze.Constants)
local MazeNav = require(ReplicatedStorage.Features.Maze.MazeNav)

local MazeService = {}

-- Before EscapeService (10); the maze must exist before round state tracks it.
MazeService.Priority = 5

-- Polar layout. RADII are band boundaries; band b spans RADII[b]..RADII[b+1].
-- SECTORS[b] is how many wedges band b is divided into. Band 0 = hub.
local RADII = {
	[0] = 0, [1] = 30, [2] = 72, [3] = 114, [4] = 156, [5] = 198, [6] = 240,
	[7] = 282, [8] = 324, [9] = 366, [10] = 408, [11] = 450, [12] = 492, [13] = 534,
}
local SECTORS = {
	[0] = 1, [1] = 6, [2] = 12, [3] = 12, [4] = 24, [5] = 24, [6] = 24,
	[7] = 24, [8] = 48, [9] = 48, [10] = 48, [11] = 48, [12] = 48,
}
local BANDS = 12 -- outermost band index

local WALL_H = 40
local WALL_T = 3
local ARC_SEG = 20 -- approx chord length for arc-wall segmentation
local EXTRA_LOOPS = 36
local FLOOR_Y = 0 -- top of the floor
local WALL_COLOR = Color3.fromRGB(70, 84, 90)
local FLOOR_COLOR = Color3.fromRGB(48, 57, 62)

local TWO_PI = math.pi * 2

local function sectorsOf(b: number): number
	return SECTORS[b]
end

-- Cartesian point at polar (r, theta), height y.
local function polar(r: number, theta: number, y: number): Vector3
	return Vector3.new(r * math.cos(theta), y, r * math.sin(theta))
end

-- Undirected passage set, keyed by an ordered cell-key pair.
local function cellKey(b: number, s: number): number
	return b * 1000 + s
end
local function pairKey(b1: number, s1: number, b2: number, s2: number): string
	local a, b = cellKey(b1, s1), cellKey(b2, s2)
	if a > b then
		a, b = b, a
	end
	return `{a}-{b}`
end

-- Neighbours of (b, s): CW/CCW within the band, one inward cell, and `ratio`
-- outward cells (ratio = 1 or 2 from the doubling schedule).
local function neighbours(b: number, s: number): { { number } }
	local nbrs = {}
	if b >= 1 then
		local sc = sectorsOf(b)
		table.insert(nbrs, { b, (s + 1) % sc })
		table.insert(nbrs, { b, (s - 1) % sc })
		local ratioIn = sectorsOf(b) / sectorsOf(b - 1)
		table.insert(nbrs, { b - 1, math.floor(s / ratioIn) })
	end
	if b < BANDS then
		local ratioOut = sectorsOf(b + 1) / sectorsOf(b)
		for i = 0, ratioOut - 1 do
			table.insert(nbrs, { b + 1, s * ratioOut + i })
		end
	end
	return nbrs
end

-- Recursive backtracker over the polar cell graph, from the hub outward.
local function carve(rng: Random): { [string]: boolean }
	local passages: { [string]: boolean } = {}
	local visited: { [number]: boolean } = {}
	local stack = { { 0, 0 } }
	visited[cellKey(0, 0)] = true

	while #stack > 0 do
		local cur = stack[#stack]
		local cb, cs = cur[1], cur[2]

		local candidates = {}
		for _, n in neighbours(cb, cs) do
			if not visited[cellKey(n[1], n[2])] then
				table.insert(candidates, n)
			end
		end

		if #candidates == 0 then
			table.remove(stack)
			continue
		end

		local n = candidates[rng:NextInteger(1, #candidates)]
		passages[pairKey(cb, cs, n[1], n[2])] = true
		visited[cellKey(n[1], n[2])] = true
		table.insert(stack, { n[1], n[2] })
	end

	return passages
end

-- Knock out extra passages so the maze has loops (shortcuts), not one solution.
local function addLoops(rng: Random, passages: { [string]: boolean })
	local added, attempts = 0, 0
	while added < EXTRA_LOOPS and attempts < 5000 do
		attempts += 1
		local b = rng:NextInteger(0, BANDS)
		local s = rng:NextInteger(0, sectorsOf(b) - 1)
		local nbrs = neighbours(b, s)
		local n = nbrs[rng:NextInteger(1, #nbrs)]
		local key = pairKey(b, s, n[1], n[2])
		if not passages[key] then
			passages[key] = true
			added += 1
		end
	end
end

local function newPart(size: Vector3, cframe: CFrame, color: Color3, parent: Instance, name: string): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.Material = Enum.Material.Concrete
	p.Color = color
	p.Parent = parent
	return p
end

-- A wall box whose length runs along horizontal `dir`, standing WALL_H tall.
local function buildWallBox(midXZ: Vector3, dir: Vector3, length: number, parent: Instance, name: string)
	local pos = Vector3.new(midXZ.X, WALL_H / 2, midXZ.Z)
	local cf = CFrame.fromMatrix(pos, dir, Vector3.yAxis)
	newPart(Vector3.new(length, WALL_H, WALL_T), cf, WALL_COLOR, parent, name)
end

-- Arc wall at radius r spanning [a0, a1], approximated by straight chords.
local function buildArc(r: number, a0: number, a1: number, parent: Instance, name: string)
	local arcLen = r * (a1 - a0)
	local segs = math.max(1, math.ceil(arcLen / ARC_SEG))
	for i = 0, segs - 1 do
		local t0 = a0 + (a1 - a0) * (i / segs)
		local t1 = a0 + (a1 - a0) * ((i + 1) / segs)
		local p0 = polar(r, t0, 0)
		local p1 = polar(r, t1, 0)
		local mid = (p0 + p1) / 2
		local dir = (p1 - p0)
		buildWallBox(mid, dir.Unit, dir.Magnitude + WALL_T, parent, name)
	end
end

-- Radial spoke at angle theta, from radius r0 to r1.
local function buildRadial(theta: number, r0: number, r1: number, parent: Instance, name: string)
	local p0 = polar(r0, theta, 0)
	local p1 = polar(r1, theta, 0)
	local mid = (p0 + p1) / 2
	buildWallBox(mid, (p1 - p0).Unit, (r1 - r0) + WALL_T, parent, name)
end

-- BFS over passages from (sb, ss); returns a reached-cell set.
local function reachFrom(passages: { [string]: boolean }, sb: number, ss: number): { [number]: boolean }
	local reached: { [number]: boolean } = { [cellKey(sb, ss)] = true }
	local queue = { { sb, ss } }
	local head = 1
	while head <= #queue do
		local cur = queue[head]
		head += 1
		for _, n in neighbours(cur[1], cur[2]) do
			if passages[pairKey(cur[1], cur[2], n[1], n[2])] and not reached[cellKey(n[1], n[2])] then
				reached[cellKey(n[1], n[2])] = true
				table.insert(queue, { n[1], n[2] })
			end
		end
	end
	return reached
end

function MazeService.Start()
	local rng = Random.new(Constants.SEED)
	local passages = carve(rng)
	addLoops(rng, passages)

	local mazeFolder = workspace:FindFirstChild("Maze")
	if mazeFolder then
		mazeFolder:ClearAllChildren()
	else
		mazeFolder = Instance.new("Folder")
		mazeFolder.Name = "Maze"
		mazeFolder.Parent = workspace
	end

	-- The maze provides its own ground, so remove the default Baseplate — its top
	-- sits at y=0 too and would z-fight the floor across the whole disc.
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	-- Floor: one thin cylinder disc, big enough to cover the spawn just outside
	-- the perimeter. A Cylinder's axis is local X; rotate it 90° about Z so the
	-- axis stands vertical and it reads as a flat round floor.
	local floorRadius = RADII[BANDS + 1] + 30
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Shape = Enum.PartType.Cylinder
	floor.Size = Vector3.new(2, floorRadius * 2, floorRadius * 2)
	floor.CFrame = CFrame.new(0, FLOOR_Y - 1, 0) * CFrame.Angles(0, 0, math.rad(90))
	floor.Anchored = true
	floor.Material = Enum.Material.Concrete
	floor.Color = FLOOR_COLOR
	floor.Parent = mazeFolder

	-- Walls: for each ring cell, its inner arc + CCW radial spoke where there's
	-- no passage; plus a fully sealed outer perimeter (you're dropped INSIDE).
	for b = 1, BANDS do
		local sc = sectorsOf(b)
		local step = TWO_PI / sc
		local ratioIn = sc / sectorsOf(b - 1)
		for s = 0, sc - 1 do
			local a0 = s * step
			local a1 = (s + 1) * step

			-- inner arc between (b,s) and its inward neighbour
			local inward = { b - 1, math.floor(s / ratioIn) }
			if not passages[pairKey(b, s, inward[1], inward[2])] then
				buildArc(RADII[b], a0, a1, mazeFolder, "Arc")
			end

			-- CCW radial spoke between (b,s) and (b, s-1)
			local ccw = (s - 1) % sc
			if not passages[pairKey(b, s, b, ccw)] then
				buildRadial(a0, RADII[b], RADII[b + 1], mazeFolder, "Spoke")
			end
		end
	end

	-- Perimeter: fully sealed outer wall (the maze is a closed circle).
	do
		local sc = sectorsOf(BANDS)
		local step = TWO_PI / sc
		for s = 0, sc - 1 do
			buildArc(RADII[BANDS + 1], s * step, (s + 1) * step, mazeFolder, "Perimeter")
		end
	end

	-- Spawn: dropped in at a random interior cell in an outer-ish band (a real
	-- journey inward remains), facing the centre. A separate unseeded Random so
	-- the drop location varies each session while the maze stays seed-deterministic.
	local spawnRng = Random.new()
	-- Middle rings only: not band 1-2 (right on the goal) nor the outermost band
	-- (which hugs the perimeter and reads as "the edge"). Clearly surrounded.
	local spawnBand = spawnRng:NextInteger(3, math.max(3, BANDS - 2))
	local spawnSector = spawnRng:NextInteger(0, sectorsOf(spawnBand) - 1)
	local spawnMidR = (RADII[spawnBand] + RADII[spawnBand + 1]) / 2
	local spawnAngle = (spawnSector + 0.5) * (TWO_PI / sectorsOf(spawnBand))
	local spawnPos = polar(spawnMidR, spawnAngle, 4)
	local spawnCFrame = CFrame.lookAt(spawnPos, Vector3.new(0, spawnPos.Y, 0))
	local spawnLocationInstance = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	assert(spawnLocationInstance, "MazeService: no SpawnLocation found in workspace")
	local spawnLocation = spawnLocationInstance :: SpawnLocation
	spawnLocation.CFrame = spawnCFrame

	-- EvacPad at the centre: the glowing win trigger. Named "ExitGate" so
	-- EscapeService (which listens on Maze.ExitGate.Touched) works unchanged.
	local evac = Instance.new("Part")
	evac.Name = "ExitGate"
	evac.Shape = Enum.PartType.Cylinder
	evac.Size = Vector3.new(1, RADII[1] * 1.4, RADII[1] * 1.4)
	-- Lifted just above the floor so its underside doesn't z-fight the floor top.
	evac.CFrame = CFrame.new(0, FLOOR_Y + 0.8, 0) * CFrame.Angles(0, 0, math.rad(90))
	evac.Anchored = true
	evac.CanCollide = false
	evac.Material = Enum.Material.Neon
	evac.Color = Color3.fromRGB(60, 220, 120)
	evac.Parent = mazeFolder
	local light = Instance.new("PointLight")
	light.Color = evac.Color
	light.Range = 40
	light.Brightness = 2
	light.Parent = evac

	-- Validate: the whole maze is connected (so any drop-in cell reaches the hub).
	local reached = reachFrom(passages, 0, 0)
	local total = 0
	for b = 0, BANDS do
		total += sectorsOf(b)
	end
	local reachedCount = 0
	for _ in reached do
		reachedCount += 1
	end
	assert(reachedCount == total, `circular maze: only {reachedCount}/{total} cells reachable`)

	-- Publish the navigation graph (cell centres + open adjacency) for AI.
	MazeNav.reset()
	for b = 0, BANDS do
		for s = 0, sectorsOf(b) - 1 do
			local key = MazeNav.cellKey(b, s)
			local center: Vector3
			if b == 0 then
				center = Vector3.new(0, 0, 0)
			else
				local midR = (RADII[b] + RADII[b + 1]) / 2
				local midA = (s + 0.5) * TWO_PI / sectorsOf(b)
				center = polar(midR, midA, 0)
			end
			MazeNav.cellPos[key] = center
			local list = {}
			for _, n in neighbours(b, s) do
				if passages[pairKey(b, s, n[1], n[2])] then
					table.insert(list, MazeNav.cellKey(n[1], n[2]))
				end
			end
			MazeNav.adj[key] = list
		end
	end
	MazeNav.ready = true

	print(`[Maze] circular seed={Constants.SEED} bands={BANDS} cells={total} spawn=(b{spawnBand},s{spawnSector})`)

	-- Downstream features (EscapeService) wait on this before reading positions.
	workspace:SetAttribute("MazeReady", true)
end

return MazeService
