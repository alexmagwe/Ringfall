--!strict
-- Per-district set dressing: the thing that stops all twelve bands looking like
-- one room. The maze carves itself in a single wall colour on a single floor
-- disc, so before this every cell in a district was pixel-identical to every
-- other one — which is not only flat to look at, it breaks the district's own
-- core activity. Sweeping a ring for its one gate needs landmarks you can
-- remember, and identical cells give you none: you cannot tell an arc you
-- already searched from one you did not.
--
-- OUTERMOST DISTRICT = OVERGROWN RUIN. Vines hang off the walls, shoots climb
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
	wallColor: Color3?,
	wallMaterial: Enum.Material?,

	-- Fraction of wall segments that grow anything at all. Below 1 the district
	-- reads as patchy and organic; at 1 every segment looks the same, which is
	-- the uniformity this module exists to remove.
	growthChance: number,
	strandsPerWall: NumberRange, -- hanging vines on a wall that grows any
	shootsPerWall: NumberRange, -- climbers out of the base of that same wall

	stemColors: { Color3 }, -- one is drawn per strand, so no two runs match
	growthMaterial: Enum.Material,

	-- A flat count, not a per-wall multiplier. The outermost district carries
	-- roughly 620 wall segments once the perimeter is chopped into chords, so
	-- anything multiplied per wall runs to four figures of parts on a ring that
	-- gets rebuilt every round.
	floorPatchCount: number,
	floorColor: Color3,
	floorPatchRadius: NumberRange,
}

-- The abandoned outer ring. Greens are desaturated and grey-leaning on
-- purpose: a bright garden green next to concrete reads as a different game,
-- not as a ruin.
Dressing.OVERGROWN = {
	wallColor = Color3.fromRGB(78, 92, 76),
	wallMaterial = Enum.Material.Slate, -- older, rougher stone than the Concrete inward
	-- Budget: ~620 wall segments x 0.32 x ~2.5 pieces each, plus the floor
	-- patches, lands around 700 extra parts for the district. Raise these and
	-- check the count before you ship it — this rebuilds on every round.
	growthChance = 0.32,
	strandsPerWall = NumberRange.new(1, 2),
	shootsPerWall = NumberRange.new(0, 2),
	stemColors = {
		Color3.fromRGB(56, 84, 48),
		Color3.fromRGB(72, 100, 56),
		Color3.fromRGB(94, 116, 64),
		Color3.fromRGB(48, 68, 44),
	},
	growthMaterial = Enum.Material.Grass,
	floorPatchCount = 220,
	floorColor = Color3.fromRGB(72, 104, 58),
	floorPatchRadius = NumberRange.new(3, 9),
} :: Look

-- Wall parts the maze carves. Anything else in the folder (the Floor disc, the
-- EscapeZone that EscapeService parents in here) must be left alone — the Floor
-- spans every district, so repainting it would repaint the whole map.
local WALL_NAMES = { Arc = true, Spoke = true, Perimeter = true }

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
	part.CastShadow = false
	part.Parent = parent
	return part
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
		local length = halfHeight * rng:NextNumber(0.35, 1.15)
		local thickness = rng:NextNumber(0.35, 0.9)
		local alongX = rng:NextNumber(-halfLength * 0.85, halfLength * 0.85)
		local side = if rng:NextNumber() < 0.5 then 1 else -1
		local offZ = side * (faceZ + thickness / 2)
		-- A slight lean and twist per strand. Dead-straight vines read as pipes.
		local lean = CFrame.Angles(0, 0, rng:NextNumber(-0.12, 0.12))

		newGrowth(
			Vector3.new(thickness, length, thickness),
			wall.CFrame * CFrame.new(alongX, halfHeight - length / 2, offZ) * lean,
			pick(rng, look.stemColors),
			look.growthMaterial,
			parent,
			"Vine"
		)
	end

	local shoots = rng:NextInteger(look.shootsPerWall.Min, look.shootsPerWall.Max)
	for _ = 1, shoots do
		-- Climbers: shorter, thinner, and leaning harder than the hanging
		-- strands, so the two read as different growth rather than one effect
		-- mirrored top and bottom.
		local length = halfHeight * rng:NextNumber(0.2, 0.6)
		local thickness = rng:NextNumber(0.25, 0.6)
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

-- Flat discs of growth over the floor of the district.
--
-- Scattered rather than laid as one continuous ring: the maze floor is a single
-- disc spanning every district, so a solid annulus over part of it would need
-- to be exactly coplanar and would z-fight along every seam. Patches sit a hair
-- proud of the floor instead, and they read as growth breaking through rather
-- than as a recoloured tile. Landing half under a wall is fine — that is where
-- growth collects anyway.
local function scatterFloor(innerR: number, outerR: number, count: number, look: Look, rng: Random, parent: Instance)
	for _ = 1, count do
		local radius = randomIn(rng, look.floorPatchRadius)
		-- sqrt keeps the scatter even by AREA. Sampling the radius uniformly
		-- would crowd everything against the inner edge, where each ring of
		-- radius covers far less ground.
		local t = math.sqrt(rng:NextNumber())
		local r = innerR + (outerR - innerR) * t
		local a = rng:NextNumber(0, math.pi * 2)

		local patch = newGrowth(
			Vector3.new(0.2, radius * 2, radius * 2),
			CFrame.new(r * math.cos(a), 0.08, r * math.sin(a)) * CFrame.Angles(0, 0, math.rad(90)),
			look.floorColor,
			look.growthMaterial,
			parent,
			"FloorGrowth"
		)
		patch.Shape = Enum.PartType.Cylinder
	end
end

-- Dresses every wall between `innerR` and `outerR`, and scatters floor growth
-- across the same ring. Call it after the geometry exists and before the nav
-- graph publishes; it reads the walls it finds and adds only scenery, so it can
-- never change what was carved.
--
-- `rng` is the build's own seeded Random, so a seed reproduces its dressing
-- exactly like it reproduces its layout.
function Dressing.apply(mazeFolder: Instance, look: Look, innerR: number, outerR: number, rng: Random)
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

	for _, wall in walls do
		if look.wallColor then
			wall.Color = look.wallColor
		end
		if look.wallMaterial then
			wall.Material = look.wallMaterial
		end
		if rng:NextNumber() > look.growthChance then
			continue
		end
		growOnWall(wall, look, rng, folder)
	end

	scatterFloor(innerR, outerR, look.floorPatchCount, look, rng, folder)

	-- Matches MazeService's own build line. The part count is the number worth
	-- watching: this rebuilds every round, so a raised density shows up here
	-- before it shows up as a frame-rate complaint.
	local added = #folder:GetChildren()
	print(`[Maze] dressed {#walls} wall(s) with {added} scenery part(s)`)
end

return Dressing
