--!strict
-- Circular (theta) maze: concentric ring-bands around a central Vault. Every
-- round starts in a staging room OUTSIDE the perimeter; the door opens and
-- players run INWARD through gaps in each ring wall to reach the Vault, then
-- carry it back out through the same wall the same way they came (see
-- docs/game/Escape.md for the round lifecycle and the win condition, which
-- now lives at the staging room's ExtractPad, not here).
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
local GATE_HEIGHT = WALL_H * 0.6 -- tall enough to read as a landmark, not full wall height
local GATE_COLOR = Color3.fromRGB(255, 195, 60)

-- Staging room + corridor: a walled box OUTSIDE the perimeter (radius
-- RADII[13] + 40 = 574), opening inward through a single cut in the
-- Perimeter wall. The extraction pad lives here (see docs/game/Maze.md and
-- docs/game/Escape.md).
local STAGING_CENTER_R = RADII[13] + 40 -- 574
local STAGING_HALF_WIDTH = 25 -- tangential half-width of the whole room+corridor
local STAGING_ROOM_HALF_DEPTH = 25 -- < 30: keeps the room clear of RADII[13] (534)
local STAGING_ROOM_FAR_R = STAGING_CENTER_R + STAGING_ROOM_HALF_DEPTH -- 599
local STAGING_ROOM_NEAR_R = STAGING_CENTER_R - STAGING_ROOM_HALF_DEPTH -- 549 (corridor ends here)
local STAGING_COLOR = Color3.fromRGB(60, 66, 74)
local DOOR_COLOR = Color3.fromRGB(200, 70, 60)
local EXTRACT_PAD_COLOR = Color3.fromRGB(80, 220, 160)
-- The round maze floor overhangs the perimeter wall by this much, so the world
-- doesn't end flush against it. The staging floor must START at that overhang's
-- outer edge, not at the perimeter — otherwise the two floors overlap for 30
-- studs with both top faces at y=0, which z-fights into a shimmering band right
-- where players walk out of the corridor.
local FLOOR_OVERHANG = 30
-- The staging floor is a BOX; the maze floor is a CYLINDER. Butting them at the
-- same radius leaves a seam, because a straight edge can't follow a curve — the
-- gap opens toward the sides and you can see down through it. So they OVERLAP
-- inward by this much...
local STAGING_FLOOR_OVERLAP = 8
-- ...and the staging floor sits this far below the maze floor, because two
-- overlapping surfaces at the SAME height z-fight into a shimmering band (the
-- original bug). Overlap fixes the gap, the depth offset fixes the shimmer;
-- 0.1 studs is far too small to feel as a step.
local STAGING_FLOOR_DROP = 0.1
local VAULT_COLOR = Color3.fromRGB(40, 40, 46)
local VAULT_OUTLINE_COLOR = Color3.fromRGB(255, 195, 60)

local TWO_PI = math.pi * 2

local function sectorsOf(b: number): number
	return SECTORS[b]
end

-- Cartesian point at polar (r, theta), height y.
local function polar(r: number, theta: number, y: number): Vector3
	return Vector3.new(r * math.cos(theta), y, r * math.sin(theta))
end

-- Like `polar`, but offset perpendicular to the radial direction (tangentially)
-- by `off` studs. Used for the staging room + corridor, which sit off-grid
-- outside the maze's polar wall pattern rather than on a band/sector boundary.
local function polarOffset(r: number, theta: number, off: number, y: number): Vector3
	local tangent = Vector3.new(-math.sin(theta), 0, math.cos(theta))
	return polar(r, theta, y) + tangent * off
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
-- `awayFrom` (radians) biases the cut toward the FAR side of the ring. Picking
-- each gate independently clusters them: you push through one and the next is a
-- few steps away, which collapses a district into a corridor and wastes the
-- whole sealed-ring idea. Chaining each gate roughly opposite the previous one
-- forces a real traverse of every district.
local function openGate(
	rng: Random,
	passages: { [string]: boolean },
	outerBand: number,
	innerBand: number,
	awayFrom: number?
): (number, number)
	local sc = sectorsOf(outerBand)
	local s
	if awayFrom then
		-- Opposite, plus a wide jitter so it isn't mechanically antipodal every
		-- round (which would be its own predictable pattern).
		local target = (awayFrom :: number) + math.pi + rng:NextNumber(-1, 1) * (math.pi / 4)
		s = math.floor((target % TWO_PI) / (TWO_PI / sc)) % sc
	else
		s = rng:NextInteger(0, sc - 1)
	end
	local ratioIn = sectorsOf(outerBand) / sectorsOf(innerBand)
	local innerS = math.floor(s / ratioIn)
	passages[pairKey(outerBand, s, innerBand, innerS)] = true
	return s, (s + 0.5) * (TWO_PI / sc)
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

-- A straight wall between two arbitrary XZ points, unlike buildRadial (which
-- always runs through the origin). Used for the staging room + corridor.
local function buildSegment(p0: Vector3, p1: Vector3, parent: Instance, name: string)
	local mid = (p0 + p1) / 2
	buildWallBox(mid, (p1 - p0).Unit, (p1 - p0).Magnitude + WALL_T, parent, name)
end

-- Builds (or rebuilds) the staging room + corridor at angle `theta`: a walled
-- box centred at STAGING_CENTER_R with one side open toward the maze (no near
-- wall — that opening is the corridor, which runs from the room's near edge
-- to the cut in the Perimeter wall at the same angle). Owns workspace.Staging
-- — its own folder, NOT under workspace.Maze, so `mazeFolder:ClearAllChildren()`
-- can't destroy it, but rebuilt every rebuild just like Gates. Returns the
-- CFrame SpawnLocation should use: near the room's far wall, facing back down
-- the corridor (which is also world-centre, since a polar angle is a straight
-- line through the origin) — the return trip is taught wordlessly before
-- anyone leaves.
local function buildStaging(theta: number): CFrame
	local stagingFolder = workspace:FindFirstChild("Staging")
	if stagingFolder then
		stagingFolder:ClearAllChildren()
	else
		stagingFolder = Instance.new("Folder")
		stagingFolder.Name = "Staging"
		stagingFolder.Parent = workspace
	end

	-- Floor: one flat plate out to the room's far wall, tucked slightly UNDER
	-- the maze floor's overhang rather than butted against it — see
	-- STAGING_FLOOR_OVERLAP / STAGING_FLOOR_DROP for why it must be both
	-- overlapping and lower.
	local floorInnerR = RADII[BANDS + 1] + FLOOR_OVERHANG - STAGING_FLOOR_OVERLAP
	local floorLen = STAGING_ROOM_FAR_R - floorInnerR
	local floorMidR = floorInnerR + floorLen / 2
	local floorDir = Vector3.new(math.cos(theta), 0, math.sin(theta))
	newPart(
		Vector3.new(floorLen, 2, STAGING_HALF_WIDTH * 2),
		CFrame.fromMatrix(polar(floorMidR, theta, FLOOR_Y - 1 - STAGING_FLOOR_DROP), floorDir, Vector3.yAxis),
		STAGING_COLOR,
		stagingFolder,
		"StagingFloor"
	)

	-- Side walls: run the full corridor+room length, flush with the perimeter
	-- cut on the near end — there is deliberately no wall there, that's the
	-- opening the corridor connects through.
	local leftNear = polarOffset(RADII[BANDS + 1], theta, STAGING_HALF_WIDTH, 0)
	local leftFar = polarOffset(STAGING_ROOM_FAR_R, theta, STAGING_HALF_WIDTH, 0)
	buildSegment(leftNear, leftFar, stagingFolder, "StagingWall")

	local rightNear = polarOffset(RADII[BANDS + 1], theta, -STAGING_HALF_WIDTH, 0)
	local rightFar = polarOffset(STAGING_ROOM_FAR_R, theta, -STAGING_HALF_WIDTH, 0)
	buildSegment(rightNear, rightFar, stagingFolder, "StagingWall")

	-- Far wall caps the room.
	buildSegment(leftFar, rightFar, stagingFolder, "StagingWall")

	-- Door: blocks the corridor partway between the perimeter cut and the
	-- room. EscapeService toggles CanCollide as RoundState changes.
	-- Sits at WALL_H/2 to match buildWallBox, which forces every wall to span
	-- y=0..WALL_H. Built at y=0 the door would be half-buried and leave a
	-- 20-stud gap above it — still unwalkable, but it reads as broken geometry
	-- rather than a door, and the slide-open would only clear half of it.
	local doorR = (RADII[BANDS + 1] + STAGING_ROOM_NEAR_R) / 2
	local doorLeft = polarOffset(doorR, theta, STAGING_HALF_WIDTH, WALL_H / 2)
	local doorRight = polarOffset(doorR, theta, -STAGING_HALF_WIDTH, WALL_H / 2)
	local door = newPart(
		Vector3.new((doorRight - doorLeft).Magnitude, WALL_H, WALL_T),
		CFrame.fromMatrix((doorLeft + doorRight) / 2, (doorRight - doorLeft).Unit, Vector3.yAxis),
		DOOR_COLOR,
		stagingFolder,
		"Door"
	)
	door.CanCollide = true

	-- Extraction pad: the round-end win trigger for whoever carries the vault
	-- (EscapeService binds Touched; this is geometry only).
	local pad = Instance.new("Part")
	pad.Name = "ExtractPad"
	pad.Shape = Enum.PartType.Cylinder
	pad.Size = Vector3.new(1, STAGING_HALF_WIDTH * 1.2, STAGING_HALF_WIDTH * 1.2)
	pad.CFrame = CFrame.new(polar(STAGING_CENTER_R, theta, FLOOR_Y + 0.6)) * CFrame.Angles(0, 0, math.rad(90))
	pad.Anchored = true
	pad.CanCollide = false
	-- Flat floor marking, NOT a glowing disc. It was Neon with a PointLight back
	-- when the room was unlit and the pad had to be a beacon; under daylight
	-- that just reads as a blinding puddle in the middle of the lobby. Still
	-- clearly a marked circle, and it is still the win trigger — do not delete
	-- it, EscapeService binds Touched to it.
	pad.Material = Enum.Material.SmoothPlastic
	pad.Color = EXTRACT_PAD_COLOR
	pad.Parent = stagingFolder

	-- No overhead lamps here. They existed only because Atmosphere used to run at
	-- ClockTime 0 with Ambient (18,22,28), which left this enclosed box pitch
	-- black. Under the current daylight the room lights itself, and the lamps
	-- were just glowing boxes floating over the entrance. If the game ever goes
	-- back to night, they come back with it — see AtmosphereController's header.

	local spawnPos = polar(STAGING_ROOM_FAR_R - 8, theta, 4)
	return CFrame.lookAt(spawnPos, Vector3.new(0, spawnPos.Y, 0))
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
	-- Placed OUTERMOST first so each gate lands opposite the one the player just
	-- came through, in the order they actually meet them. GATE_BOUNDARIES is
	-- ordered inner -> outer, hence the reverse walk.
	local gateSectors: { number } = {}
	local prevGateTheta: number? = nil
	for i = #GATE_BOUNDARIES, 1, -1 do
		local g = GATE_BOUNDARIES[i]
		local s, theta = openGate(rng, passages, g[1], g[2], prevGateTheta)
		gateSectors[i] = s
		prevGateTheta = theta
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
	local floorRadius = RADII[BANDS + 1] + FLOOR_OVERHANG
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

	-- Perimeter: sealed outer wall, except for one cut sector — the mouth of
	-- the staging room (a fourth "gate", picked with the same seeded `rng` so
	-- a seed fully determines the round). `stagingTheta` is used below to
	-- build the room itself, after the wall it opens into already exists.
	local stagingSector: number
	local stagingTheta: number
	do
		local sc = sectorsOf(BANDS)
		local step = TWO_PI / sc
		stagingSector = rng:NextInteger(0, sc - 1)
		stagingTheta = (stagingSector + 0.5) * step
		-- Cut an opening exactly as wide as the corridor, NOT a whole sector.
		-- A sector at this radius is ~70 studs of arc but the corridor is only
		-- 50 wide, so skipping the whole sector left ~10 studs of open wall
		-- either side of the corridor mouth — you could see (and walk) straight
		-- out of the maze past the staging room.
		local halfAngle = math.asin(STAGING_HALF_WIDTH / RADII[BANDS + 1])
		for s = 0, sc - 1 do
			local a0, a1 = s * step, (s + 1) * step
			if s ~= stagingSector then
				buildArc(RADII[BANDS + 1], a0, a1, mazeFolder, "Perimeter")
				continue
			end
			buildArc(RADII[BANDS + 1], a0, stagingTheta - halfAngle, mazeFolder, "Perimeter")
			buildArc(RADII[BANDS + 1], stagingTheta + halfAngle, a1, mazeFolder, "Perimeter")
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

	-- Staging room + corridor: outside the perimeter, opening through the cut
	-- made above. Also positions SpawnLocation (inside the room, facing back
	-- down the corridor) — every run is now a full descent from outside.
	local spawnCFrame = buildStaging(stagingTheta)
	local spawnLocationInstance = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	assert(spawnLocationInstance, "MazeService: no SpawnLocation found in workspace")
	local spawnLocation = spawnLocationInstance :: SpawnLocation
	spawnLocation.CFrame = spawnCFrame
	-- Hide the spawn pad itself: the staging room IS the waiting area, and a
	-- floating Roblox spawn plate with its star decal reads as leftover
	-- scaffolding sitting in the middle of it. It still functions — this only
	-- makes it invisible and non-solid, so players stand on the room's floor.
	spawnLocation.Transparency = 1
	spawnLocation.CanCollide = false
	for _, d in spawnLocation:GetChildren() do
		if d:IsA("Decal") or d:IsA("Texture") then
			d.Transparency = 1
		end
	end

	-- Vault at the centre: the prize. Container-ish look (greybox) — it has no
	-- behaviour yet, SalvageService gives it Touched behaviour and the alarm.
	-- Named "Vault" (was "ExitGate" pre-extraction-loop); EscapeService no
	-- longer looks it up at all — the win trigger moved to ExtractPad.
	-- Pedestal: a low dais marking the chamber. Decor only — it is NOT named
	-- "Vault", so SalvageService's Touched binding can't grab it by mistake.
	local dais = Instance.new("Part")
	dais.Name = "VaultDais"
	dais.Shape = Enum.PartType.Cylinder
	dais.Size = Vector3.new(2, RADII[1] * 1.4, RADII[1] * 1.4)
	-- Lifted just above the floor so its underside doesn't z-fight the floor top.
	dais.CFrame = CFrame.new(0, FLOOR_Y + 0.9, 0) * CFrame.Angles(0, 0, math.rad(90))
	dais.Anchored = true
	dais.CanCollide = false
	dais.Material = Enum.Material.Metal
	dais.Color = VAULT_COLOR
	dais.Parent = mazeFolder

	-- The artifact itself: a glowing container floating at chest height above
	-- the dais. It was previously a flat disc lying ON the floor, which read as
	-- decoration rather than a prize — players walked to the centre and saw
	-- nothing to take. It needs to be an OBJECT, lit, at eye level.
	local vault = Instance.new("Part")
	vault.Name = "Vault"
	vault.Size = Vector3.new(7, 7, 7)
	vault.CFrame = CFrame.new(0, FLOOR_Y + 6, 0) * CFrame.Angles(0, math.rad(35), math.rad(15))
	vault.Anchored = true
	vault.CanCollide = false
	vault.CanTouch = true
	vault.Material = Enum.Material.Neon
	vault.Color = VAULT_OUTLINE_COLOR
	vault.Parent = mazeFolder

	local vaultLight = Instance.new("PointLight")
	vaultLight.Color = VAULT_OUTLINE_COLOR
	vaultLight.Range = 60
	vaultLight.Brightness = 4
	vaultLight.Shadows = true
	vaultLight.Parent = vault

	-- Visible through the ring walls, so the centre reads as the destination
	-- from anywhere in the maze.
	local vaultHighlight = Instance.new("Highlight")
	vaultHighlight.FillTransparency = 1
	vaultHighlight.OutlineColor = VAULT_OUTLINE_COLOR
	vaultHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	vaultHighlight.Parent = vault

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

	print(`[Maze] circular seed={seed} bands={BANDS} cells={total} stagingSector={stagingSector}`)

	-- Vault/alarm reset so a fresh round re-arms cleanly. These attributes are
	-- conceptually owned by Salvage/Hunter, but cleared here (like every other
	-- per-run attribute EscapeService clears) since this is the one place a
	-- new round always passes through. See docs/game/Maze.md.
	workspace:SetAttribute("VaultTaken", nil)
	workspace:SetAttribute("AlarmActive", nil)
	workspace:SetAttribute("HunterAlert", nil)
	workspace:SetAttribute("HunterAlertPos", nil)

	workspace:SetAttribute("MazeSeed", seed)
	-- Monotonic rebuild counter. Downstream features re-wire to the new Maze
	-- geometry (Vault, Staging, EscapeZone, nav graph) whenever this changes;
	-- it must be incremented last, after MazeNav is fully repopulated, so
	-- listeners that react to it see a consistent graph.
	workspace:SetAttribute("MazeGeneration", (workspace:GetAttribute("MazeGeneration") or 0) + 1)
end

function MazeService.Start()
	MazeService.rebuild(Constants.SEED)
	-- Downstream features (EscapeService) wait on this before reading positions.
	-- Set exactly once and never cleared/reset — other services :Wait() on it.
	workspace:SetAttribute("MazeReady", true)
end

return MazeService
