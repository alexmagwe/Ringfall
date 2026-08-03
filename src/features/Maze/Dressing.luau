--!strict
-- Per-district set dressing: the thing that stops all twelve bands looking like
-- one room. The maze carves itself in a single wall colour on a single floor
-- disc, so before this every cell in a district was pixel-identical to every
-- other one — which is not only flat to look at, it breaks the district's own
-- core activity. Sweeping a ring for its one gate needs landmarks you can
-- remember, and identical cells give you none: you cannot tell an arc you
-- already searched from one you did not.
--
-- OUTERMOST DISTRICT = OVERGROWN RUIN. MIDDLE DISTRICT = FLOODED INDUSTRY. Vines hang off the walls, shoots climb
-- out of their bases, growth spreads over the floor, and the stone is mossy and
-- weathered rather than clean concrete. Players spawn here, so it sets the
-- first impression, and it gives the run a gradient: a ruin at the edge, intact
-- structure in the middle, a sealed vault at the centre. Nature takes the
-- outside first, and the maze looks better defended the deeper you go.
--
-- LOOK ONLY, and that is a decision rather than an omission. Every piece this
-- adds is CanCollide/CanQuery/CanTouch false, so:
--   * the navigation graph is untouched — hunters still walk cell centres, and
--     no collider moved;
--   * a vine curtain is NOT cover. `HunterService.canSee` only counts a
--     raycast hit on a part named Arc / Spoke / Perimeter, and CanQuery false
--     keeps growth out of every raycast in the game anyway (hunter sight, the
--     gun's aim ray, the shot itself);
--   * nothing here can trip a pickup's Touched or block a corridor.
-- To make growth mechanical later, the change is deliberate: give the thick
-- strands query-visible colliders and name them into `canSee`.
--
-- Never cut a real gap in a wall to fake decay. The wall IS the maze: a hole
-- opens a passage the carve never made, which can strand a gate and break the
-- sealed-district rule. Decay is painted on; the collider stays whole.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Maze.Dressing.

local Dressing = {}

export type Look = {
	-- Repaints the district's walls. nil leaves them as carved.
	--
	-- KEEP THIS CLOSE TO STONE. The first attempt painted the walls green to
	-- match the grass, and the district turned into one flat green mass with
	-- nothing reading against anything. Growth is only visible when it contrasts
	-- with what it grows on, so the wall stays grey and the vines carry the
	-- colour.
	wallColor: Color3?,
	wallMaterial: Enum.Material?,
	wallJitter: number, -- fraction of lightness variation applied per wall part

	-- Fallen stone heaped where the wall meets the ground. Nothing in a real
	-- place meets the floor in a clean straight line, and that junction is at
	-- eye level for the whole run — breaking it is worth more than anything
	-- added out in the open.
	rubbleChance: number,
	rubblePerWall: NumberRange,
	rubbleColors: { Color3 },
	-- Yaw only, no pitch or roll. Fallen stone tumbles; a crate that has been
	-- set down does not, and tipping one reads as debris rather than as cargo.
	rubbleUpright: boolean?,

	-- Fraction of wall segments that grow anything at all. Below 1 the district
	-- reads as patchy and organic; at 1 every segment looks the same, which is
	-- the uniformity this module exists to remove.
	growthChance: number,
	strandsPerWall: NumberRange, -- hanging vines on a wall that grows any
	shootsPerWall: NumberRange, -- climbers out of the base of that same wall
	-- Boxes per strand. Above 1, each strand kinks partway down instead of
	-- running dead straight, which is most of the difference between a vine and
	-- a pipe.
	segmentsPerStrand: NumberRange,
	strandThickness: NumberRange,

	stemColors: { Color3 }, -- one is drawn per strand, so no two runs match
	growthMaterial: Enum.Material,
	-- Multiplier on `growthChance` at the district's INNER edge, ramping to 1 at
	-- its outer edge. This is what stops the three districts reading as three
	-- rooms: growth thins as you descend instead of stopping dead at a gate, so
	-- the maze reads as one world that changes. 1 (or nil) means no falloff.
	growthFalloff: number?,

	-- Pipes and conduits: horizontal runs along a wall, with the occasional drop
	-- to the floor. Same idea as a vine and deliberately the same generator
	-- shape, because a pipe IS a straight, rigid, metal vine — what separates
	-- them is thickness, colour, material, and the fact that a pipe does not
	-- kink.
	pipeChance: number?,
	pipesPerWall: NumberRange?,
	pipeThickness: NumberRange?,
	pipeColors: { Color3 }?,
	pipeMaterial: Enum.Material?,

	-- The district's ground: a solid ring laid over the maze floor.
	groundColor: Color3,
	groundMaterial: Enum.Material,
	-- Above 0 the ground reads as standing water rather than as a surface.
	groundTransparency: number?,
	-- Extra studs the ground reaches PAST `outerR`. The outermost district needs
	-- this: the maze floor overhangs its own perimeter wall, so a ground ring
	-- that stops at the wall leaves a band of bare floor showing in the one place
	-- the wall is cut — the corridor players walk in through. Overhanging tucks
	-- the seam under the staging room's own floor plate, where a change of
	-- surface is justified because you are stepping into a built room.
	groundOverhang: number?,

	-- Tufts with actual height, in clumps. A flat disc on a flat floor is a
	-- stain no matter what colour it is — only vertical geometry reads as
	-- growth. Counts are flat, not per-wall multipliers: the outermost district
	-- carries roughly 620 wall segments once the perimeter is chopped into
	-- chords, so anything multiplied per wall runs to four figures of parts on a
	-- ring that gets rebuilt every round.
	tuftClumps: number,
	tuftsPerClump: NumberRange,
	clumpSpread: number, -- studs from the clump centre
	tuftHeight: NumberRange,
	tuftWidth: NumberRange,
}

-- The abandoned outer ring. Greens are desaturated and grey-leaning on
-- purpose: a bright garden green next to concrete reads as a different game,
-- not as a ruin.
--
-- Budget: ~620 wall segments, x0.4 for vines at ~4 pieces each and x0.55 for
-- rubble at ~3, plus the loose tufts. Lands around 1900 extra parts. Raise any
-- of it and read the count the build prints before you ship — this rebuilds on
-- every round.
--
-- Spend it on the wall bases before anything else. A heap at the junction does
-- more for the district than the same parts scattered in the open, because that
-- line is at eye level for the whole run.
--
-- Broad tinted discs over the ground were tried here and removed. Whatever the
-- size or the tone, a circle lying on flat ground reads as a circle: the eye
-- finds the rim immediately, and nothing outdoors has one. Ground variation has
-- to come from geometry that breaks the silhouette, not from paint.
Dressing.OVERGROWN = {
	-- Dark, cool stone. It was (84,86,78) — a warm mid-grey that sat at almost
	-- exactly the lightness of the grass, so the two merged into one tone and
	-- the whole district read as mush. Neighbouring surfaces need to differ in
	-- LIGHTNESS, not only in hue; this is now clearly the darker of the two, and
	-- cool against the warm green.
	wallColor = Color3.fromRGB(58, 63, 70),
	wallMaterial = Enum.Material.Slate, -- older, rougher stone than the Concrete inward
	wallJitter = 0.05,
	rubbleChance = 0.55,
	rubblePerWall = NumberRange.new(1, 3),
	rubbleColors = {
		Color3.fromRGB(64, 68, 72),
		Color3.fromRGB(52, 56, 62),
		Color3.fromRGB(74, 76, 74),
	},
	growthChance = 0.4,
	strandsPerWall = NumberRange.new(1, 3),
	shootsPerWall = NumberRange.new(0, 2),
	segmentsPerStrand = NumberRange.new(1, 2),
	-- Thick. At 0.35 against a 40-stud wall the strands were threads and
	-- vanished at any distance.
	strandThickness = NumberRange.new(0.9, 2.2),
	stemColors = {
		Color3.fromRGB(56, 84, 48),
		Color3.fromRGB(72, 100, 56),
		Color3.fromRGB(94, 116, 64),
		Color3.fromRGB(48, 68, 44),
	},
	growthMaterial = Enum.Material.Grass,
	groundColor = Color3.fromRGB(72, 96, 58),
	groundMaterial = Enum.Material.Grass,
	-- Reaches 26 studs past the perimeter, to 560. The maze floor runs to 564
	-- and the staging plate starts at 556, so this covers the whole overhang and
	-- tucks 4 studs over the plate's inner edge — the same overlap trick
	-- MazeService uses there, for the same reason: a circular edge and a
	-- straight one cannot meet cleanly, and the sliver between them shows.
	-- Growth itself still stops at the perimeter; only the ground reaches out.
	groundOverhang = 26,
	-- Fewer loose clumps than before: the rubble now carries its own tufts, so
	-- the growth that matters is already against the walls where players walk.
	tuftClumps = 40,
	tuftsPerClump = NumberRange.new(3, 6),
	clumpSpread = 7,
	tuftHeight = NumberRange.new(1.2, 3.4),
	tuftWidth = NumberRange.new(0.5, 1.5),
} :: Look

-- The working middle: flooded industry. The ruin outside is what the maze
-- BECAME; this is what it was FOR. Pipes run the length of the walls, crates sit
-- where someone set them down, and standing water covers the floor.
--
-- Growth does not stop at the gate — it thins. `growthFalloff` ramps the vine
-- density from almost nothing at the inner edge up toward the outer one, so the
-- overgrowth outside bleeds a little way in and the two districts read as one
-- world rather than two rooms with a door between them.
--
-- Budget: ~350 wall segments here (120 cells, and only band 7 is 24-sector), so
-- the same per-wall chances cost roughly half what they do outside.
Dressing.FLOODED = {
	-- Colder and cleaner than the ruin: same family of grey, less warmth in it,
	-- and Concrete rather than the weathered Slate outside.
	wallColor = Color3.fromRGB(62, 68, 78),
	wallMaterial = Enum.Material.Concrete,
	wallJitter = 0.05,
	-- Crates, not fallen stone: fewer, blockier, and set down flat.
	rubbleChance = 0.4,
	rubblePerWall = NumberRange.new(1, 2),
	rubbleColors = {
		Color3.fromRGB(96, 82, 58),
		Color3.fromRGB(78, 70, 56),
		Color3.fromRGB(64, 74, 82),
	},
	rubbleUpright = true,
	-- Thin growth, thinning further as you descend.
	growthChance = 0.22,
	growthFalloff = 0.15,
	strandsPerWall = NumberRange.new(1, 2),
	shootsPerWall = NumberRange.new(0, 1),
	segmentsPerStrand = NumberRange.new(1, 2),
	strandThickness = NumberRange.new(0.7, 1.6),
	stemColors = {
		Color3.fromRGB(58, 78, 54),
		Color3.fromRGB(70, 88, 60),
		Color3.fromRGB(46, 62, 46),
	},
	growthMaterial = Enum.Material.Grass,
	pipeChance = 0.5,
	pipesPerWall = NumberRange.new(1, 3),
	pipeThickness = NumberRange.new(0.5, 1.4),
	pipeColors = {
		Color3.fromRGB(104, 96, 84),
		Color3.fromRGB(78, 84, 90),
		Color3.fromRGB(120, 92, 62), -- one rusted run per few, so they are not a set
	},
	pipeMaterial = Enum.Material.Metal,
	-- Standing water. Transparent enough to read as shallow, dark enough that the
	-- floor below it goes cold — the ruin outside is warm green, this is not.
	groundColor = Color3.fromRGB(56, 76, 88),
	groundMaterial = Enum.Material.SmoothPlastic,
	groundTransparency = 0.35,
	-- Almost no loose growth: it collects against the crates instead.
	tuftClumps = 14,
	tuftsPerClump = NumberRange.new(2, 4),
	clumpSpread = 6,
	tuftHeight = NumberRange.new(0.8, 2.2),
	tuftWidth = NumberRange.new(0.4, 1.1),
} :: Look

-- Wall parts the maze carves. Anything else in the folder (the Floor disc, the
-- EscapeZone that EscapeService parents in here) must be left alone — the Floor
-- spans every district, so repainting it would repaint the whole map.
local WALL_NAMES = { Arc = true, Spoke = true, Perimeter = true }

-- Every ground disc is this thin. They stack a few hundredths apart, so no two
-- faces are ever coplanar and nothing z-fights.
local DISC_THICKNESS = 0.2

-- Default when a Look asks for pipes without saying how many.
local ONE = NumberRange.new(1, 1)

local function pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function randomIn(rng: Random, range: NumberRange): number
	return rng:NextNumber(range.Min, range.Max)
end

-- Every piece of growth is scenery and nothing else. CanQuery is the important
-- one: it keeps vines out of hunter line-of-sight, out of the gun's aim ray,
-- and out of the shot itself.
local function newGrowth(size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance, name: string): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	-- Shadows ON, and this is not a detail. An object that casts no shadow does
	-- not touch anything — a tuft with no shadow hovers over the grass and a
	-- vine with none is a sticker on the wall. Contact shadow is most of what
	-- makes small scenery look placed rather than pasted. The flat ground discs
	-- turn it back off in newDisc, where it buys nothing and costs plenty.
	part.CastShadow = true
	part.Parent = parent
	return part
end

-- Nudges a colour's lightness without moving its hue. One exact colour repeated
-- across 600 wall parts reads as paint; a few percent of variation per part
-- reads as stone. Scaling all three channels together is what keeps the hue put.
local function jitter(color: Color3, amount: number, rng: Random): Color3
	local f = 1 + rng:NextNumber(-amount, amount)
	return Color3.new(math.clamp(color.R * f, 0, 1), math.clamp(color.G * f, 0, 1), math.clamp(color.B * f, 0, 1))
end

-- Heaps fallen stone and a little growth where the wall meets the ground.
--
-- This is the highest-value detail in the whole module, and it is worth saying
-- why. Every other piece here is scenery you look at; this one fixes a junction
-- you cannot stop looking at. A wall meeting a floor along a perfect straight
-- line is the single loudest tell that a place was generated, and that line
-- runs the length of every corridor at eye level for the whole run. Breaking it
-- costs a few boxes.
--
-- Pieces straddle the face rather than sitting beside it — half buried in the
-- wall — so the heap reads as stone that fell out of it, not as boxes parked
-- against it.
local function rubbleAtBase(wall: BasePart, look: Look, rng: Random, parent: Instance)
	local halfLength = wall.Size.X / 2
	local halfHeight = wall.Size.Y / 2
	local faceZ = wall.Size.Z / 2

	local count = rng:NextInteger(look.rubblePerWall.Min, look.rubblePerWall.Max)
	for _ = 1, count do
		local width = rng:NextNumber(1.6, 4.2)
		local height = rng:NextNumber(0.7, 2.4)
		local depth = rng:NextNumber(1.2, 2.8)
		local alongX = rng:NextNumber(-halfLength * 0.9, halfLength * 0.9)
		local side = if rng:NextNumber() < 0.5 then 1 else -1
		-- Half the depth sits inside the wall, so there is no gap to see down.
		local offZ = side * (faceZ + depth * 0.25)
		-- Tipped every which way. Axis-aligned boxes read as boxes — except when
		-- the pieces are meant to be cargo, which someone set down flat.
		local tilt = if look.rubbleUpright then 0 else 0.35
		local tumble = CFrame.Angles(rng:NextNumber(-tilt, tilt), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-tilt, tilt))

		newGrowth(
			Vector3.new(width, height, depth),
			wall.CFrame * CFrame.new(alongX, -halfHeight + height * 0.35, offZ) * tumble,
			pick(rng, look.rubbleColors),
			wall.Material,
			parent,
			"Rubble"
		)

		-- Growth collects against fallen stone. One tuft per piece ties the two
		-- together instead of leaving clean rock on clean grass.
		if rng:NextNumber() < 0.6 then
			local tuftHeight = randomIn(rng, look.tuftHeight)
			local tuftWidth = randomIn(rng, look.tuftWidth)
			newGrowth(
				Vector3.new(tuftWidth, tuftHeight, tuftWidth),
				wall.CFrame
					* CFrame.new(alongX + rng:NextNumber(-2.5, 2.5), -halfHeight + tuftHeight / 2, side * (faceZ + rng:NextNumber(0.5, 2.5)))
					* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				pick(rng, look.stemColors),
				look.growthMaterial,
				parent,
				"Tuft"
			)
		end
	end
end

-- Runs pipes along a wall face, with the occasional drop to the floor.
--
-- Deliberately the same shape as growOnWall, because a pipe IS a rigid metal
-- vine: the difference is that it runs HORIZONTALLY, holds one thickness for its
-- whole length, and never kinks. Those three things are the whole reason a
-- corridor reads as built rather than as overgrown.
local function pipesOnWall(wall: BasePart, look: Look, rng: Random, parent: Instance)
	local thickness = look.pipeThickness
	local colors = look.pipeColors
	if not thickness or not colors or #colors == 0 then
		return
	end

	local halfLength = wall.Size.X / 2
	local halfHeight = wall.Size.Y / 2
	local faceZ = wall.Size.Z / 2
	local material = look.pipeMaterial or Enum.Material.Metal

	local count = rng:NextInteger((look.pipesPerWall or ONE).Min, (look.pipesPerWall or ONE).Max)
	for _ = 1, count do
		local gauge = randomIn(rng, thickness)
		local color = pick(rng, colors)
		local side = if rng:NextNumber() < 0.5 then 1 else -1
		local offZ = side * (faceZ + gauge / 2)
		-- Runs the FULL length of the segment. A pipe that stops halfway along a
		-- wall reads as a broken prop; one that leaves at both ends reads as part
		-- of a system that continues past what you can see.
		local height = rng:NextNumber(-halfHeight * 0.45, halfHeight * 0.75)

		newGrowth(
			Vector3.new(halfLength * 2, gauge, gauge),
			wall.CFrame * CFrame.new(0, height, offZ),
			color,
			material,
			parent,
			"Pipe"
		)

		-- A drop to the floor every so often, so the runs are not all parallel
		-- lines at the same height.
		if rng:NextNumber() < 0.35 then
			local dropLength = height + halfHeight
			newGrowth(
				Vector3.new(gauge * 0.8, dropLength, gauge * 0.8),
				wall.CFrame * CFrame.new(rng:NextNumber(-halfLength * 0.8, halfLength * 0.8), height - dropLength / 2, offZ),
				color,
				material,
				parent,
				"Conduit"
			)
		end
	end
end

-- Hangs strands down one wall face and grows climbers up from its base.
--
-- The wall's own CFrame does all the work here. `buildWallBox` builds every
-- wall as CFrame.fromMatrix(pos, dir, Vector3.yAxis) with Size (length, height,
-- thickness), so in wall-local space X runs along the wall, Y is up, and Z is
-- the face normal. Growth positions are therefore plain local offsets, and this
-- stays correct for arcs, spokes and the perimeter alike without any of them
-- being special-cased.
local function growOnWall(wall: BasePart, look: Look, rng: Random, parent: Instance)
	local halfLength = wall.Size.X / 2
	local halfHeight = wall.Size.Y / 2
	local faceZ = wall.Size.Z / 2

	local strands = rng:NextInteger(look.strandsPerWall.Min, look.strandsPerWall.Max)
	for _ = 1, strands do
		-- Hangs from the top, down a random part of the wall's height. Kept
		-- clear of the very ends so a strand doesn't float in the gap where two
		-- arc chords meet at an angle.
		local total = halfHeight * rng:NextNumber(0.4, 1.3)
		local thickness = randomIn(rng, look.strandThickness)
		local alongX = rng:NextNumber(-halfLength * 0.85, halfLength * 0.85)
		local side = if rng:NextNumber() < 0.5 then 1 else -1
		local offZ = side * (faceZ + thickness / 2)
		local color = pick(rng, look.stemColors)

		-- Walk down the face in segments, drifting sideways and re-leaning at
		-- each one. One straight box is a pipe; two that meet at a slight angle
		-- read as something that grew.
		local segments = rng:NextInteger(look.segmentsPerStrand.Min, look.segmentsPerStrand.Max)
		local segLength = total / segments
		local y = halfHeight
		local x = alongX
		for _ = 1, segments do
			local lean = rng:NextNumber(-0.16, 0.16)
			newGrowth(
				Vector3.new(thickness, segLength, thickness),
				wall.CFrame * CFrame.new(x, y - segLength / 2, offZ) * CFrame.Angles(0, 0, lean),
				color,
				look.growthMaterial,
				parent,
				"Vine"
			)
			-- Overlap the joint slightly so the kink has no gap in it.
			y -= segLength * 0.94
			x += rng:NextNumber(-1.5, 1.5)
			thickness *= rng:NextNumber(0.7, 0.95) -- tapers toward the tip
		end
	end

	local shoots = rng:NextInteger(look.shootsPerWall.Min, look.shootsPerWall.Max)
	for _ = 1, shoots do
		-- Climbers: shorter, thinner, and leaning harder than the hanging
		-- strands, so the two read as different growth rather than one effect
		-- mirrored top and bottom.
		local length = halfHeight * rng:NextNumber(0.25, 0.7)
		local thickness = randomIn(rng, look.strandThickness) * 0.8
		local alongX = rng:NextNumber(-halfLength * 0.85, halfLength * 0.85)
		local side = if rng:NextNumber() < 0.5 then 1 else -1
		local offZ = side * (faceZ + thickness / 2)
		local lean = CFrame.Angles(0, 0, rng:NextNumber(-0.3, 0.3))

		newGrowth(
			Vector3.new(thickness, length, thickness),
			wall.CFrame * CFrame.new(alongX, -halfHeight + length / 2, offZ) * lean,
			pick(rng, look.stemColors),
			look.growthMaterial,
			parent,
			"Shoot"
		)
	end
end

-- A thin horizontal disc, built the way MazeService builds the maze floor: a
-- Cylinder's axis is its local X, so it is rotated 90 degrees about Z to stand
-- the axis upright and read as flat ground.
local function newDisc(x: number, z: number, radius: number, topY: number, color: Color3, material: Enum.Material, parent: Instance, name: string): BasePart
	local disc = newGrowth(
		Vector3.new(DISC_THICKNESS, radius * 2, radius * 2),
		CFrame.new(x, topY - DISC_THICKNESS / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		material,
		parent,
		name
	)
	disc.Shape = Enum.PartType.Cylinder
	-- A disc lying flat on the floor has nothing to cast a shadow onto, and one
	-- of these is 1000 studs across. Pure cost.
	disc.CastShadow = false
	return disc
end

-- Lays the district's ground as a RING, using two solid discs rather than a
-- ring of segments.
--
-- The obvious build — an annulus chopped into wedge quads — is the wrong one
-- here. Neighbouring quads meet coplanar along every radial seam, which
-- z-fights, and a chord across a 48-sector arc at this radius misses the true
-- curve by over a stud. Two concentric discs have no seams at all:
--
--   1. a grass disc out to `outerR`, which also covers everything inside it;
--   2. a disc of the ORIGINAL floor back out to `innerR`, which hides the part
--      of the grass that reached into the inner districts.
--
-- What is left visible is an exact ring. It costs two parts instead of ~150.
--
-- The cover disc reads its colour and material off the real floor rather than
-- naming them, so the inner districts cannot drift out of step with it if
-- `FLOOR_COLOR` ever changes. Both discs sit a hair proud of the floor and a
-- hair apart from each other, so no two faces are ever coplanar.
local function layGround(mazeFolder: Instance, innerR: number, outerR: number, floorTopY: number, look: Look, parent: Instance)
	local ground = newDisc(0, 0, outerR + (look.groundOverhang or 0), floorTopY + 0.05, look.groundColor, look.groundMaterial, parent, "Ground")
	ground.Transparency = look.groundTransparency or 0

	local floor = mazeFolder:FindFirstChild("Floor") :: BasePart?
	if not floor then
		return -- no floor to match; the grass disc alone is better than nothing
	end
	newDisc(0, 0, innerR, floorTopY + 0.12, floor.Color, floor.Material, parent, "GroundCover")
end

-- A random point in the district's ring.
--
-- sqrt keeps the scatter even by AREA. Sampling the radius uniformly would
-- crowd everything against the inner edge, where each ring of radius covers far
-- less ground.
local function pointInRing(innerR: number, outerR: number, rng: Random): (number, number)
	local t = math.sqrt(rng:NextNumber())
	local r = innerR + (outerR - innerR) * t
	local a = rng:NextNumber(0, math.pi * 2)
	return r * math.cos(a), r * math.sin(a)
end

-- Tufts of growth, in clumps.
--
-- These have HEIGHT, and that is the whole point. A flat disc lying on a flat
-- floor is a stain whatever colour it is — only vertical geometry reads as
-- something growing. They are clumped rather than evenly scattered for the same
-- reason the walls only grow on some segments: even spacing reads as a texture,
-- and clumps read as growth that took hold somewhere.
--
-- Landing half under a wall is fine. That is where growth collects anyway.
local function scatterTufts(innerR: number, outerR: number, floorTopY: number, look: Look, rng: Random, parent: Instance)
	for _ = 1, look.tuftClumps do
		local cx, cz = pointInRing(innerR, outerR, rng)
		local count = rng:NextInteger(look.tuftsPerClump.Min, look.tuftsPerClump.Max)
		for _ = 1, count do
			local height = randomIn(rng, look.tuftHeight)
			local width = randomIn(rng, look.tuftWidth)
			local x = cx + rng:NextNumber(-look.clumpSpread, look.clumpSpread)
			local z = cz + rng:NextNumber(-look.clumpSpread, look.clumpSpread)
			-- Random yaw and a slight tilt, so a clump is not a grid of
			-- identical posts.
			local spin = CFrame.Angles(rng:NextNumber(-0.14, 0.14), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.14, 0.14))

			newGrowth(
				Vector3.new(width, height, width),
				CFrame.new(x, floorTopY + height / 2, z) * spin,
				pick(rng, look.stemColors),
				look.growthMaterial,
				parent,
				"Tuft"
			)
		end
	end
end

-- Dresses every wall between `innerR` and `outerR`, lays the district's ground
-- over the same ring, and scatters clumps on top. Call it after the geometry
-- exists and before the nav graph publishes; it reads the walls it finds and
-- adds only scenery, so it can never change what was carved.
--
-- `floorTopY` is the walking surface of the maze floor. Everything this lays
-- sits just above it.
--
-- `rng` is the build's own seeded Random, so a seed reproduces its dressing
-- exactly like it reproduces its layout.
function Dressing.apply(mazeFolder: Instance, look: Look, innerR: number, outerR: number, floorTopY: number, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "Dressing"
	folder.Parent = mazeFolder

	-- Snapshot first: the loop parents new growth into the same folder tree, and
	-- iterating a list that is still growing would dress the vines.
	local walls: { BasePart } = {}
	for _, child in mazeFolder:GetChildren() do
		if not child:IsA("BasePart") or not WALL_NAMES[child.Name] then
			continue
		end
		local p = child.Position
		local r = Vector2.new(p.X, p.Z).Magnitude
		-- The perimeter sits exactly on outerR, so the bound has to include it.
		if r < innerR - 1 or r > outerR + 1 then
			continue
		end
		table.insert(walls, child)
	end

	local span = math.max(outerR - innerR, 1)
	for _, wall in walls do
		if look.wallColor then
			wall.Color = jitter(look.wallColor, look.wallJitter, rng)
		end
		if look.wallMaterial then
			wall.Material = look.wallMaterial
		end
		-- Rubble is rolled separately from growth, and more often. The junction
		-- it breaks is worth more than anything out in the open, so a wall can
		-- get a heap at its foot without also carrying vines.
		if rng:NextNumber() < look.rubbleChance then
			rubbleAtBase(wall, look, rng, folder)
		end
		if look.pipeChance and rng:NextNumber() < look.pipeChance then
			pipesOnWall(wall, look, rng, folder)
		end

		-- Growth thins with depth across the district's own width, rather than
		-- holding one density and then stopping dead at a gate. Three districts
		-- each at a flat density read as three rooms; a ramp reads as one world
		-- that changes as you go down.
		local p = wall.Position
		local depth = (Vector2.new(p.X, p.Z).Magnitude - innerR) / span
		local falloff = look.growthFalloff or 1
		local chance = look.growthChance * (falloff + (1 - falloff) * math.clamp(depth, 0, 1))
		if rng:NextNumber() > chance then
			continue
		end
		growOnWall(wall, look, rng, folder)
	end

	layGround(mazeFolder, innerR, outerR, floorTopY, look, folder)
	scatterTufts(innerR, outerR, floorTopY, look, rng, folder)

	-- Matches MazeService's own build line. The part count is the number worth
	-- watching: this rebuilds every round, so a raised density shows up here
	-- before it shows up as a frame-rate complaint.
	local added = #folder:GetChildren()
	print(`[Maze] dressed {#walls} wall(s) with {added} scenery part(s)`)
end

return Dressing
