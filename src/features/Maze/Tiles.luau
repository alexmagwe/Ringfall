--!strict
-- Greybox tile kit for the Maze feature. Every tile is a declarative part list
-- built into a Model at runtime — no hand-placed Studio geometry in this slice.
--
-- Canonical socket order is {N, E, S, W}; each tile is authored in its
-- canonical orientation (rotation = 0). `Tiles.Build` applies `rotation`
-- (0-3 quarter-turns clockwise) as `cframe * CFrame.Angles(0, -rotation *
-- math.pi/2, 0)`. `Tiles.RotateSockets` mirrors that same clockwise rotation
-- on the socket table so MazeService can find the matching rotation for a
-- carved cell's opening mask using the exact same rotation semantics used
-- here to place geometry — one source of truth, per the plan's warning that
-- a failed assert means the socket table is wrong, not a special case.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Maze.Tiles.

local Constants = require(script.Parent.Constants)

local TILE_SIZE = Constants.TILE_SIZE
local WALL_HEIGHT = Constants.WALL_HEIGHT
local WALL_THICKNESS = Constants.WALL_THICKNESS

local HALF = TILE_SIZE / 2

local WALL_COLOR = Color3.fromRGB(70, 84, 90)
local FLOOR_COLOR = Color3.fromRGB(50, 60, 64)

export type Socket = "Open" | "Wall"
export type Sockets = { Socket } -- indices 1=N, 2=E, 3=S, 4=W

local Tiles = {}

-- Canonical (rotation = 0) socket tables, keyed by tile name. Order is
-- {N, E, S, W}. This is the single source of truth MazeService reads to
-- decide which tile a cell's opening mask maps to.
Tiles.CanonicalSockets = {
	DeadEnd = { "Open", "Wall", "Wall", "Wall" },
	Corridor = { "Open", "Wall", "Open", "Wall" },
	Corner = { "Open", "Open", "Wall", "Wall" },
	TJunction = { "Open", "Open", "Open", "Wall" },
	Cross = { "Open", "Open", "Open", "Open" },
	StairCourt = { "Open", "Open", "Wall", "Wall" },
} :: { [string]: Sockets }

-- Rotates a canonical socket table `k` quarter-turns clockwise (same
-- direction Tiles.Build applies to the physical geometry: N -> E -> S -> W).
-- newSockets[i] = oldSockets[the side that ends up at i after k clockwise turns].
function Tiles.RotateSockets(sockets: Sockets, k: number): Sockets
	local rotated = table.create(4)
	for i = 1, 4 do
		local sourceIndex = ((i - k - 1) % 4) + 1
		rotated[i] = sockets[sourceIndex]
	end
	return rotated :: Sockets
end

-- side: 1=N, 2=E, 3=S, 4=W. Local (unrotated) CFrame for that wall slot.
-- Every tile that wants a wall on a given side uses this same slot, so
-- rotation behaves identically regardless of tile type.
local WALL_SIZE = Vector3.new(TILE_SIZE, WALL_HEIGHT, WALL_THICKNESS)
local WALL_LOCAL_CFRAME = {
	CFrame.new(0, WALL_HEIGHT / 2, -HALF), -- N
	CFrame.new(HALF, WALL_HEIGHT / 2, 0) * CFrame.Angles(0, math.rad(90), 0), -- E
	CFrame.new(0, WALL_HEIGHT / 2, HALF), -- S
	CFrame.new(-HALF, WALL_HEIGHT / 2, 0) * CFrame.Angles(0, math.rad(90), 0), -- W
}
local WALL_NAMES = { "WallN", "WallE", "WallS", "WallW" }

-- Exported so MazeService can punch the exit gap out of an already-built
-- tile: it knows which canonical side (1-4) a world-facing exit direction
-- maps back to (via the same rotation math as RotateSockets), finds that
-- wall part by name, removes it, and places ExitGate at WallLocalCFrame[side]
-- transformed by the same finalCFrame used to build the tile.
Tiles.WallLocalCFrame = WALL_LOCAL_CFRAME
Tiles.WallNames = WALL_NAMES
Tiles.WallSize = WALL_SIZE

local function newPart(size: Vector3, cframe: CFrame, color: Color3, parent: Instance, name: string): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.Material = Enum.Material.Concrete
	part.Color = color
	part.Parent = parent
	return part
end

-- Invisible, non-colliding anchor at the tile's local origin (0,0,0), used as
-- the Model's PrimaryPart so Model:PivotTo places the tile by its logical
-- origin rather than an off-center bounding-box centroid (StairCourt's
-- rooftop pushes the bbox center way above floor level).
local function buildOrigin(model: Model): BasePart
	local origin = Instance.new("Part")
	origin.Name = "Origin"
	origin.Size = Vector3.new(1, 1, 1)
	origin.CFrame = CFrame.new(0, 0, 0)
	origin.Anchored = true
	origin.CanCollide = false
	origin.CanQuery = false
	origin.Transparency = 1
	origin.Parent = model
	return origin
end

local function buildFloor(model: Model)
	newPart(Vector3.new(TILE_SIZE, 1, TILE_SIZE), CFrame.new(0, 0, 0), FLOOR_COLOR, model, "Floor")
end

-- Builds the wall slots called for by `sockets` (canonical, unrotated).
local function buildWalls(model: Model, sockets: Sockets)
	local names = { "WallN", "WallE", "WallS", "WallW" }
	for side = 1, 4 do
		if sockets[side] == "Wall" then
			newPart(WALL_SIZE, WALL_LOCAL_CFRAME[side], WALL_COLOR, model, names[side])
		end
	end
end

-- Cross tile: no walls, just 4 corner pillars so the open crossing still
-- reads as a distinct space. 6x6x60 each.
local function buildCrossPillars(model: Model)
	local pillarSize = Vector3.new(6, WALL_HEIGHT, 6)
	local inset = HALF - 3
	local offsets = {
		Vector2.new(-inset, -inset),
		Vector2.new(inset, -inset),
		Vector2.new(-inset, inset),
		Vector2.new(inset, inset),
	}
	for i, offset in offsets do
		newPart(pillarSize, CFrame.new(offset.X, WALL_HEIGHT / 2, offset.Y), WALL_COLOR, model, `Pillar{i}`)
	end
end

-- StairCourt extra geometry. Locomotion is an invisible collidable ramp (the
-- character controller climbs a smooth ramp reliably but stalls on discrete
-- step risers, and can't mount a too-steep single ramp — hence a two-flight
-- switchback with a mid-landing). The *visible* steps are solid non-colliding
-- boxes whose tops sit on the ramp's walking surface at each step's LOWER edge,
-- so the player — standing on the ramp — is always on or just above every
-- visible step and never sinks through one. Lands on a rooftop platform at
-- wall-top height, from which you can see over the 60-stud walls.
local ROOF_Y = Constants.TOWER_H -- top walking surface of the rooftop strip
local MID_Y = Constants.TOWER_H / 2 -- mid-landing height (half the climb)
local STEPS_PER_FLIGHT = 20 -- more steps = visible treads hug the ramp closer

-- Builds one switchback flight climbing (xLow,yLow) -> (xHigh,yHigh) at fixed z:
-- an invisible collidable ramp for locomotion plus STEPS_PER_FLIGHT solid,
-- non-colliding visible steps aligned to the ramp's top surface. `baseCF`
-- transforms the whole flight within the tile (identity for a plain StairCourt;
-- a quarter-turn for a crossing tower so its roof strip faces the divide).
local function buildFlight(model: Model, prefix: string, xLow: number, yLow: number, xHigh: number, yHigh: number, z: number, width: number, baseCF: CFrame?)
	local base = baseCF or CFrame.identity
	local run = xHigh - xLow
	local rise = yHigh - yLow
	local length = math.sqrt(run * run + rise * rise)
	local angle = math.atan2(math.abs(rise), math.abs(run))
	local sign = if run >= 0 then 1 else -1 -- +X end high when climbing toward +X

	-- Collision ramp: invisible, and CanQuery=false so gameplay raycasts hit the
	-- visible steps rather than this hidden surface.
	local ramp = newPart(
		Vector3.new(length, 1, width),
		base * CFrame.new((xLow + xHigh) / 2, (yLow + yHigh) / 2, z) * CFrame.Angles(0, 0, sign * angle),
		FLOOR_COLOR,
		model,
		`{prefix}Ramp`
	)
	ramp.Transparency = 1
	ramp.CanQuery = false

	-- Height of the ramp's top walking surface above the centerline (the 1-stud
	-- slab is tilted, so the vertical offset is 0.5 / cos(angle)).
	local topOffset = 0.5 / math.cos(angle)
	local perStepRise = math.abs(rise) / STEPS_PER_FLIGHT
	local depth = math.abs(run) / STEPS_PER_FLIGHT + 0.15 -- overlap → no seams
	for i = 1, STEPS_PER_FLIGHT do
		-- A flat step top can't stay under a rising walking surface across its
		-- whole depth unless it sits a full riser below the surface at its
		-- downhill edge — otherwise the far half of the step pokes up through the
		-- player's feet (measured: ~1 riser of sink). So drop each top one
		-- perStepRise (plus a hair) below the ramp top at the step's lower edge;
		-- the player then stands just on top of each visible step.
		local tLow = (i - 1) / STEPS_PER_FLIGHT
		local xCenter = xLow + run * ((i - 0.5) / STEPS_PER_FLIGHT)
		local stepTop = (yLow + rise * tLow) + topOffset - perStepRise - 0.25
		local stepH = 4 -- solid body; overlaps its neighbour into a staircase mass
		local step = newPart(Vector3.new(width, stepH, depth), base * CFrame.new(xCenter, stepTop - stepH / 2, z), WALL_COLOR, model, `{prefix}{i}`)
		step.CanCollide = false
	end
end

-- Switchback stairs + rooftop strip. `rot` (0-3 quarter-turns) rotates the whole
-- assembly so the roof strip — canonically on the -Z (North) edge — faces a
-- chosen world side. `withParapet` adds the outer lip (off for crossing towers
-- so two towers' roof strips connect into a bridge over the divide).
local function buildStairExtras(model: Model, rot: number, withParapet: boolean)
	local base = CFrame.Angles(0, -rot * math.pi / 2, 0)

	-- Flight A hugs one lane, climbing +X from the floor to MID_Y.
	local zA = HALF - 13
	buildFlight(model, "StepA", -HALF + 2, 0.5, HALF - 8, MID_Y, zA, 8, base)

	-- Mid-landing at the +X end, spanning both lanes in Z, top at MID_Y.
	newPart(Vector3.new(12, 1, TILE_SIZE - 6), base * CFrame.new(HALF - 6, MID_Y - 0.5, 0), FLOOR_COLOR, model, "MidLanding")

	-- Flight B hugs the far lane, climbing -X, MID_Y -> ROOF_Y.
	local zB = -HALF + 13
	buildFlight(model, "StepB", HALF - 8, MID_Y, -HALF + 8, ROOF_Y, zB, 8, base)

	-- Rooftop strip at ROOF_Y, reaching the -Z tile edge (the divide edge once
	-- rotated); flight B lands on it.
	newPart(Vector3.new(TILE_SIZE, 2, 22), base * CFrame.new(0, ROOF_Y - 1, -HALF + 11), FLOOR_COLOR, model, "RooftopSlab")

	if withParapet then
		newPart(Vector3.new(TILE_SIZE, 4, 1), base * CFrame.new(0, ROOF_Y + 2, -HALF + 0.5), WALL_COLOR, model, "Parapet")
	end
end

local BUILDERS: { [string]: (model: Model) -> () } = {
	DeadEnd = function(model)
		buildFloor(model)
		buildWalls(model, Tiles.CanonicalSockets.DeadEnd)
	end,
	Corridor = function(model)
		buildFloor(model)
		buildWalls(model, Tiles.CanonicalSockets.Corridor)
	end,
	Corner = function(model)
		buildFloor(model)
		buildWalls(model, Tiles.CanonicalSockets.Corner)
	end,
	TJunction = function(model)
		buildFloor(model)
		buildWalls(model, Tiles.CanonicalSockets.TJunction)
	end,
	Cross = function(model)
		buildFloor(model)
		buildCrossPillars(model)
	end,
	StairCourt = function(model)
		buildFloor(model)
		buildWalls(model, Tiles.CanonicalSockets.StairCourt)
		buildStairExtras(model, 0, true)
	end,
}

-- The same rotation transform Tiles.Build applies to a canonical tile's
-- geometry, exposed so MazeService can compute e.g. the world CFrame of a
-- specific wall slot after the fact (for exit-gate punching) without
-- duplicating the formula.
function Tiles.FinalCFrame(rotation: number, cframe: CFrame): CFrame
	return cframe * CFrame.Angles(0, -rotation * math.pi / 2, 0)
end

-- Builds `tileName` at `rotation` (0-3 quarter-turns clockwise), parented
-- under `parent`, positioned/oriented by `cframe`. Returns the built Model.
function Tiles.Build(tileName: string, rotation: number, cframe: CFrame, parent: Instance): Model
	local builder = BUILDERS[tileName]
	assert(builder, `Tiles.Build: unknown tile "{tileName}"`)

	local model = Instance.new("Model")
	model.Name = `{tileName}_r{rotation}`

	local origin = buildOrigin(model)
	model.PrimaryPart = origin

	builder(model)

	local finalCFrame = Tiles.FinalCFrame(rotation, cframe)
	model:PivotTo(finalCFrame)
	model.Parent = parent

	return model
end

-- Builds a crossing tower at `cframe` (no rotation — `sockets` are already
-- world-oriented). Street walls per `sockets` (36-tall), plus a switchback stair
-- up to a rooftop strip on the `divideSide` (1=N,2=E,3=S,4=W) edge, so it meets
-- the neighbouring tower's strip over the divide wall. The divideSide is always
-- a wall in `sockets` (sealed boundary), so the stair/strip there never blocks a
-- street opening. No parapet on the strip edge — that's where you cross.
function Tiles.BuildCrossingTower(sockets: Sockets, divideSide: number, cframe: CFrame, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = `CrossingTower_d{divideSide}`

	local origin = buildOrigin(model)
	model.PrimaryPart = origin

	buildFloor(model)
	buildWalls(model, sockets)
	-- The strip is canonically on -Z (side 1); rotate so it faces divideSide.
	buildStairExtras(model, (divideSide - 1) % 4, false)

	model:PivotTo(cframe)
	model.Parent = parent
	return model
end

return Tiles
