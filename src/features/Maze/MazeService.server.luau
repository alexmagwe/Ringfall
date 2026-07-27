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
-- Always start in the outer rings — a run should be a long haul inward.
local SPAWN_MIN_BAND = BANDS - 2 -- 10

local WALL_H = 40
local WALL_T = 3
local ARC_SEG = 20 -- approx chord length for arc-wall segmentation
local EXTRA_LOOPS = 36
local FLOOR_Y = 0 -- top of the floor
local WALL_COLOR = Color3.fromRGB(70, 84, 90)
local FLOOR_COLOR = Color3.fromRGB(48, 57, 62)
local GATE_HEIGHT = WALL_H * 0.6 -- tall enough to read as a landmark, not full wall height
local GATE_COLOR = Color3.fromRGB(255, 195, 60)

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

-- Recursive backtracker restricted to bands [bandLo, bandHi]. Never traverses
-- outside that range, so the result is a maze that spans exactly one district.
-- Carving districts independently (then opening exactly one passage between
-- adjacent districts, see `openGate`) guarantees connectivity by construction —
-- carving the whole maze first and closing all-but-one boundary passage
-- afterward can orphan whole regions, since the single spanning tree may cross
-- a boundary more than once and the sub-trees hanging off those extra
-- crossings are then unreachable.
local function carveRange(rng: Random, passages: { [string]: boolean }, bandLo: number, bandHi: number)
	local visited: { [number]: boolean } = {}
	local startS = rng:NextInteger(0, sectorsOf(bandLo) - 1)
	local stack = { { bandLo, startS } }
	visited[cellKey(bandLo, startS)] = true

	while #stack > 0 do
		local cur = stack[#stack]
		local cb, cs = cur[1], cur[2]

		local candidates = {}
		for _, n in neighbours(cb, cs) do
			if n[1] >= bandLo and n[1] <= bandHi and not visited[cellKey(n[1], n[2])] then
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
end

-- District band ranges, inner -> outer (band 0/the hub needs no carve — the
-- {1,0} gate boundary is what connects it).
-- Owned by MazeNav so districtOf and the carve can never disagree.
local DISTRICT_BANDS = MazeNav.DISTRICT_BANDS
-- Sealed boundaries between adjacent districts, as { outerBand, innerBand }.
-- Derived, never hand-written: each district's single gate sits at its innermost
-- band, crossing into the band below. Keeps the gates pinned to DISTRICT_BANDS
-- so a layout change can't leave a gate stranded mid-district.
local GATE_BOUNDARIES = {}
for _, range in DISTRICT_BANDS do
	table.insert(GATE_BOUNDARIES, { range[1], range[1] - 1 })
end

-- Opens the single passage across one district boundary and returns the
-- (outerBand, sector) it was cut at, so the caller can place the gate model.
local function openGate(rng: Random, passages: { [string]: boolean }, outerBand: number, innerBand: number): number
	local s = rng:NextInteger(0, sectorsOf(outerBand) - 1)
	local ratioIn = sectorsOf(outerBand) / sectorsOf(innerBand)
	local innerS = math.floor(s / ratioIn)
	passages[pairKey(outerBand, s, innerBand, innerS)] = true
	return s
end

-- Knock out extra passages so the maze has loops (shortcuts), not one solution.
-- Never across a district boundary — that would silently re-open a sealed
-- district and defeat the whole feature.
local function addLoops(rng: Random, passages: { [string]: boolean })
	local added, attempts = 0, 0
	while added < EXTRA_LOOPS and attempts < 5000 do
		attempts += 1
		local b = rng:NextInteger(0, BANDS)
		local s = rng:NextInteger(0, sectorsOf(b) - 1)
		local nbrs = neighbours(b, s)
		local n = nbrs[rng:NextInteger(1, #nbrs)]
		if MazeNav.districtOf(b) ~= MazeNav.districtOf(n[1]) then
			continue -- never re-open a sealed district boundary
		end
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

-- A lit archway marking the single opening in a district boundary: two
-- vertical pillars flanking the passage plus a lintel across the top. Decor
-- and navigation only (compass targeting, checkpoint respawn) — no Touched
-- handler; passing through is exactly like passing through any other gap in a
-- wall. `entersDistrict` is the district on the inner side of this boundary.
local function buildGate(outerBand: number, gateSector: number, entersDistrict: number, parent: Instance)
	local sc = sectorsOf(outerBand)
	local step = TWO_PI / sc
	local a0 = gateSector * step
	local a1 = (gateSector + 1) * step
	local r = RADII[outerBand]

	local p0 = polar(r, a0, GATE_HEIGHT / 2)
	local p1 = polar(r, a1, GATE_HEIGHT / 2)

	-- Floor-level centre of the OPENING (mid-sector), published on every part of
	-- the gate. The pillars sit on the opening's two edges, where the arc wall
	-- resumes — so a consumer that just reads a gate part's own Position (and
	-- gets whichever child it found first) would land half inside that wall.
	-- CheckpointService respawns players here, so this must be the gap centre.
	local gateCentre = polar(r, (a0 + a1) / 2, 0)

	local function tagGate(part: BasePart)
		part.Material = Enum.Material.Neon
		part.CanCollide = false
		part:SetAttribute("EntersDistrict", entersDistrict)
		part:SetAttribute("GateCenter", gateCentre)
	end

	local function pillar(pos: Vector3)
		tagGate(newPart(Vector3.new(WALL_T, GATE_HEIGHT, WALL_T), CFrame.new(pos), GATE_COLOR, parent, "Gate"))
	end

	pillar(p0)
	pillar(p1)

	-- Lintel: spans the gap at the pillar tops.
	local lintelDir = p1 - p0
	local lintelMid = Vector3.new((p0.X + p1.X) / 2, GATE_HEIGHT, (p0.Z + p1.Z) / 2)
	local lintel = newPart(
		Vector3.new(lintelDir.Magnitude + WALL_T, WALL_T, WALL_T),
		CFrame.fromMatrix(lintelMid, lintelDir.Unit, Vector3.yAxis),
		GATE_COLOR,
		parent,
		"Gate"
	)
	tagGate(lintel)

	-- One light at the lintel is enough to read the archway through the fog
	-- from either side, in line of sight.
	local light = Instance.new("PointLight")
	light.Color = GATE_COLOR
	light.Range = 32
	light.Brightness = 2
	light.Parent = lintel
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

-- Builds (or rebuilds) the whole maze from `seed`. Safe to call repeatedly:
-- clears the existing Maze folder, repositions the existing SpawnLocation,
-- and fully repopulates MazeNav.
function MazeService.rebuild(seed: number)
	local rng = Random.new(seed)
	local passages: { [string]: boolean } = {}
	for _, range in DISTRICT_BANDS do
		carveRange(rng, passages, range[1], range[2])
	end
	local gateSectors: { number } = {}
	for i, g in GATE_BOUNDARIES do
		gateSectors[i] = openGate(rng, passages, g[1], g[2])
	end
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

	-- Gates: own folder (NOT under Maze — `mazeFolder:ClearAllChildren()` above
	-- would destroy them along with everything else). One lit archway per
	-- sealed district boundary, at the single passage `openGate` cut.
	local gatesFolder = workspace:FindFirstChild("Gates")
	if gatesFolder then
		gatesFolder:ClearAllChildren()
	else
		gatesFolder = Instance.new("Folder")
		gatesFolder.Name = "Gates"
		gatesFolder.Parent = workspace
	end
	for i, g in GATE_BOUNDARIES do
		local outerBand, innerBand = g[1], g[2]
		buildGate(outerBand, gateSectors[i], MazeNav.districtOf(innerBand), gatesFolder)
	end

	-- Spawn: dropped in at a random interior cell in the outer rings (a real
	-- journey inward remains), facing the centre. Uses the same seeded `rng` so
	-- a seed fully determines the round.
	local spawnBand = rng:NextInteger(SPAWN_MIN_BAND, BANDS) -- 10..12
	local spawnSector = rng:NextInteger(0, sectorsOf(spawnBand) - 1)
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

	print(`[Maze] circular seed={seed} bands={BANDS} cells={total} spawn=(b{spawnBand},s{spawnSector})`)

	workspace:SetAttribute("MazeSeed", seed)
	-- Monotonic rebuild counter. Downstream features re-wire to the new Maze
	-- geometry (ExitGate, EscapeZone, nav graph) whenever this changes; it must
	-- be incremented last, after MazeNav is fully repopulated, so listeners that
	-- react to it see a consistent graph.
	workspace:SetAttribute("MazeGeneration", (workspace:GetAttribute("MazeGeneration") or 0) + 1)
end

function MazeService.Start()
	MazeService.rebuild(Constants.SEED)
	-- Downstream features (EscapeService) wait on this before reading positions.
	-- Set exactly once and never cleared/reset — other services :Wait() on it.
	workspace:SetAttribute("MazeReady", true)
end

return MazeService
