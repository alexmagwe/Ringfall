--!strict
-- Hunters: several creatures that stalk the maze. Each independently chases the
-- nearest player it can "sense". Any wall breaking line-of-sight hides you, so
-- the hunter loses the lock and falls back to SEARCHING your last-known spot,
-- then WANDERING. Faster the deeper the target is; catch drags you to your last
-- checkpoint with a looming red-out.
--
-- Auto-loaded (name ends in `Service`). Priority after MazeService (5).
-- .server.luau => splitter routes to ServerScriptService.Features.Hunter.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local MazeNav = require(ReplicatedStorage.Features.Maze.MazeNav)
-- Cross-feature server require for the drop-on-catch path (dropHaul/
-- dropVault), the same pattern EscapeService already uses for MazeService.
local SalvageService = require(ServerScriptService.Features.Salvage.SalvageService)

local HunterService = {}
HunterService.Priority = 15

-- ONE ENEMY PER DISTRICT, indexed the way MazeNav.DISTRICT_BANDS is:
-- 1 = inner, up to #DISTRICT_BANDS = outermost.
--
-- The three share one AI. What differs is what they can do, and the shape of the
-- escalation is deliberate: OUTWARD they are many, weak and short-sighted;
-- INWARD they are few, tough and see a long way. A player crossing a gate should
-- feel the rules change, not just the wallpaper.
--
-- `speedScale` multiplies the depth ramp rather than replacing it, so the
-- existing "faster the deeper you are" curve still applies underneath and only
-- the type's character is layered on top.
--
-- `sightRange` is the one that changes play the most. It used to be unlimited —
-- any hunter saw any player with line of sight, the whole length of a corridor.
-- A Stray that can only see 90 studs can be walked past; a Warden at 220 owns
-- the corridor it stands in.
export type HunterKind = {
	name: string,
	count: number,
	-- Optional art: a child of ServerStorage.HunterModels with this name. Missing
	-- => the code-built duck, tinted per type.
	model: string?,
	-- Fallback look. `tint` multiplies the duck texture; `scale` is the mesh
	-- scale on a 2x2x2 host; `eye` colours the neon eyes and the catch-cam glow.
	tint: Vector3,
	scale: number,
	eye: Color3,
	dronePitch: number, -- PlaybackSpeed on the loop, so the three sound apart
	hits: number, -- gunshots to kill
	speedScale: number, -- multiplies the depth-scaled speed
	sightRange: number, -- studs; beyond this it cannot sense you at all
	drain: number, -- player HP per second in contact
}

local HUNTER_KINDS: { HunterKind } = {
	-- INNER — the vault's guard. Slowest to kill, sees furthest, hits hardest,
	-- and already runs at MAX_SPEED this deep. Three is heavier pressure than
	-- four of anything else.
	{
		name = "Warden",
		count = 3,
		model = "Warden",
		tint = Vector3.new(0.42, 0.44, 0.62),
		scale = 8,
		eye = Color3.fromRGB(120, 90, 255),
		dronePitch = 0.7,
		hits = 16,
		speedScale = 1.06,
		sightRange = 220,
		drain = 34,
	},
	-- MIDDLE — the original hunter, unchanged. It is the baseline the other two
	-- are read against, so it keeps every value the game was tuned on.
	{
		name = "Stalker",
		count = 3,
		model = "Stalker",
		tint = Vector3.new(0.6, 0.58, 0.66),
		scale = 7,
		eye = Color3.fromRGB(255, 40, 30),
		dronePitch = 1,
		hits = 10,
		speedScale = 1,
		sightRange = 140,
		drain = 25,
	},
	-- OUTER — where players spawn and where they learn the game. Many, weak,
	-- and half-blind: something you can be caught by while careless, and walk
	-- past once you know what you are doing.
	{
		name = "Stray",
		count = 4,
		model = "Stray",
		tint = Vector3.new(0.5, 0.62, 0.5),
		scale = 6,
		eye = Color3.fromRGB(255, 170, 60),
		dronePitch = 1.35,
		hits = 5,
		speedScale = 0.88,
		sightRange = 90,
		drain = 18,
	},
}

-- Optional art, one child per kind named by its `model` field. Same
-- normalize-any-shape contract as PickupModels: see attachArt.
local MODELS_FOLDER = "HunterModels"
local BASE_SPEED = 18.7 -- outer rings: just above walk (17.6), below sprint (28.6)
local MAX_SPEED = 31.9 -- near the centre: harder as you go deeper
-- Scaled with the two above (all three +10% alongside player speed) so the
-- band-to-speed ramp keeps the same shape rather than flattening.
local SPEED_PER_BAND = 1.1
local CATCH_DIST = 7
local REPATH = 0.7
local EVAC_ALERT_SECONDS = 4 -- window after any escape where every hunter sprints for the centre

-- Combat: `kind.hits` gunshots kill a hunter (5 / 10 / 16). On death it explodes
-- and drags anyone caught in the blast to their checkpoint (reuses catchPlayer —
-- no player-HP model). It respawns into its own district so the maze never
-- empties and never lopsides.
local BLAST_RADIUS = 14
local RESPAWN_DELAY = 4
-- Contact drain is `kind.drain` (18 / 25 / 34 HP per second within CATCH_DIST).
-- The catch (loom + checkpoint) only fires once Health hits 0, so a hunter has
-- to *stay* on you — you can break away and stop the bleed. Against a 100 HP
-- bar that is roughly 5.5s of contact for a Stray and 3s for a Warden.
local BLAST_SOUND_ID = "" -- user may supply a boom sound later; silent until set

-- Summon: a gunshot alerts nearby hunters to the shooter's position, whether
-- or not it hit anything — the noise is what carries (GunService sets these
-- attributes on every unsilenced shot; this file only consumes them, mirroring
-- the existing EvacAlert idiom above).
local SUMMON_WINDOW = 5 -- seconds other hunters beeline to the alert
local SUMMON_RADIUS = 200 -- only hunters within this of the alert respond
local SIREN_SOUND_ID = "" -- user supplies; siren plays on the shot hunter

-- Pack behaviour. Every hunter runs the same decision loop against the same
-- deterministic shortest path (MazeNav.nextStep is a plain BFS, so identical
-- start + identical goal = identical first step), which made the whole pack
-- travel nose-to-tail down one corridor and read as a single animal. These four
-- break the symmetry; none of them changes the kind counts or the speeds.
--
-- Beyond this distance a chaser claims a *neighbouring* cell of the target's
-- instead of the target's own, so the pack converges from several corridors.
-- Inside it, everyone commits — the catch needs CATCH_DIST (7 studs), which a
-- hunter loitering one cell away would never reach.
local FLANK_RANGE = 60
-- Peers closer than this shove each other sideways.
local SEPARATION_DIST = 12
local SEPARATION_STRENGTH = 8 -- studs of lateral offset at full crowding
-- ± fraction of REPATH, re-rolled every tick so two hunters that happen to
-- match can't stay in lockstep the way a fixed per-hunter offset would allow.
local REPATH_JITTER = 0.45
-- ± fraction applied to whatever speed the current state picked, fixed per
-- hunter, so a group chasing the same target strings out instead of arriving as
-- a wall.
local SPEED_VARIANCE = 0.12

-- Live hunter roots, for separation: a hunter has to know where its peers are to
-- avoid stacking on them. Keyed by model so a dead hunter drops out.
local activeRoots: { [Model]: BasePart } = {}

-- The FALLBACK body: the classic duck mesh, used whenever a kind has no art in
-- ServerStorage.HunterModels. Scale and tint come from the kind (see
-- HUNTER_KINDS), on a 2x2x2 host part — a scale of 7 renders ~7.5 studs tall
-- against a 5-stud player.
local DUCK_MESH = "rbxassetid://9419831"
local DUCK_TEXTURE = "rbxassetid://268365500"
-- This texture is NOT the yellow bath duck — it's already a dark mechanical duck
-- with red eyes painted on. A kind's `tint` only knocks it down; going much
-- below ~0.4 on every channel flattens the panel detail and teal beak into a
-- featureless black blob.
local DUCK_LIFT = 0.8 -- sits the mesh's feet on the collider's base

-- The neon eyes sit directly over the texture's painted eye sockets, measured in
-- Studio against a 5-stud reference at a level camera (the gameplay angle). The
-- head surface at this line is ~2.65 deep, so 2.80 clears it by a hair — enough
-- to render, tight enough that parallax doesn't drag the glow off the socket
-- when you look up at it. These are absolute studs, not proportions, so they are
-- measured against the Stalker's scale of 7 — a kind with a very different scale
-- will wear its eyes slightly off the socket.
local EYE_X = 1.50
local EYE_Y = 3.10
local EYE_Z = 2.80
local EYE_SIZE = 0.75

local function weldTo(root: BasePart, part: BasePart, offset: CFrame)
	part.CanCollide = false
	part.Massless = true
	part.CFrame = root.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
end

-- The user's art for this kind, welded onto the root — or nil if none is placed.
--
-- NOT ANCHORED, unlike every other art path in this codebase. A pickup and a
-- salvage piece hang still, so anchoring is what keeps them put; a hunter MOVES,
-- and an anchored part welded to a moving root either drags the root to a halt
-- or tears free. Massless matters for the same reason: the Humanoid's walk speed
-- should not depend on how heavy someone's mesh happens to be.
--
-- Scaled to `kind.scale` studs tall on its longest axis, for the same reason the
-- gun is: Creator Store art is authored at any size, and a hunter twice the
-- corridor's width cannot path through the maze it lives in.
local function attachArt(model: Model, root: BasePart, kind: HunterKind): boolean
	local folder = ServerStorage:FindFirstChild(MODELS_FOLDER)
	local template = kind.model and folder and folder:FindFirstChild(kind.model)
	if not template then
		return false
	end

	local clone = template:Clone()
	-- Tool inherits from Model, so a Tool must be unwrapped rather than nested —
	-- the same trap that had pickups auto-equipping onto players.
	local art: Instance = clone
	if clone:IsA("Tool") then
		local wrapper = Instance.new("Model")
		for _, child in clone:GetChildren() do
			child.Parent = wrapper
		end
		clone:Destroy()
		art = wrapper
	end

	for _, d in art:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy() -- free-model scripts would run the moment it enters the world
		end
	end

	local parts: { BasePart } = {}
	for _, d in art:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	if art:IsA("BasePart") then
		table.insert(parts, art :: BasePart)
	end
	if #parts == 0 then
		warn(`[Hunter] "{kind.model}" has no BasePart; falling back to the built-in body`)
		art:Destroy()
		return false
	end

	-- Fit and GROUND it, while it is still a Model with a bounding box to measure.
	--
	-- Scaling is to the kind's size on the longest axis, for the same reason the
	-- gun scales: Creator Store art is authored at any size, and a hunter wider
	-- than a corridor cannot path through the maze it lives in.
	--
	-- The lift is the part that is easy to get wrong. `DUCK_LIFT` centres the art
	-- on the collider, which suits the duck because the duck is as tall as the
	-- collider — but a short or wide model centred that way HOVERS, four studs
	-- off the floor, legs dangling. The general rule is to stand the art on the
	-- collider's base, whatever shape it is, so the thing the player sees is the
	-- thing touching the ground.
	if art:IsA("Model") then
		local model = art :: Model
		local extents = model:GetExtentsSize()
		local longest = math.max(extents.X, extents.Y, extents.Z)
		if longest > 0.01 then
			model:ScaleTo(model:GetScale() * (kind.scale / longest))
		end

		model:PivotTo(root.CFrame)
		local boxCF, boxSize = model:GetBoundingBox()
		local artBottom = boxCF.Position.Y - boxSize.Y / 2
		local colliderBase = root.Position.Y - root.Size.Y / 2
		model:PivotTo(model:GetPivot() + Vector3.new(0, colliderBase - artBottom, 0))
	end

	for _, part in parts do
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false -- never blocks a shot or another hunter's sightline
		part.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
		part.Parent = model
	end
	art:Destroy()
	return true
end

local function buildHunter(kind: HunterKind): Model
	local model = Instance.new("Model")
	model.Name = "Hunter"
	model:SetAttribute("HunterKind", kind.name)

	-- Invisible mover/collider. Kept at 3x6x3 for EVERY kind, however big the
	-- art is: corridor navigation is tuned against this box, and a wider one
	-- would wedge in the maze. The visual body is deliberately allowed to
	-- overhang it.
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(3, 6, 3)
	root.Transparency = 1
	root.CanCollide = true
	root.Parent = model
	model.PrimaryPart = root

	-- The duck is the FALLBACK, tinted and scaled per kind, so all three exist
	-- and read apart with no assets at all.
	local hasArt = attachArt(model, root, kind)
	if not hasArt then
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Size = Vector3.new(2, 2, 2)
		body.Parent = model
		weldTo(root, body, CFrame.new(0, DUCK_LIFT, 0))

		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = DUCK_MESH
		mesh.TextureId = DUCK_TEXTURE
		mesh.Scale = Vector3.new(kind.scale, kind.scale, kind.scale)
		mesh.VertexColor = kind.tint
		mesh.Parent = body
	end

	-- Twin eyes, FALLBACK BODY ONLY. Their offsets were measured in studs against
	-- the duck mesh's painted sockets, so on someone else's model they would be
	-- two neon spheres floating at nothing. Art brings its own face; all it needs
	-- from here is the kind's colour, which the light below carries.
	--
	-- HunterController's catch-cam looks for a part named "Eye" and falls back to
	-- PrimaryPart, so losing them costs nothing but a slightly wider framing.
	if hasArt then
		local glow = Instance.new("PointLight")
		glow.Name = "KindGlow"
		glow.Color = kind.eye
		glow.Range = 26
		glow.Brightness = 2.5
		glow.Parent = root
	end
	for i, sign in ipairs(if hasArt then {} else { -1, 1 }) do
		local eye = Instance.new("Part")
		eye.Name = if i == 1 then "Eye" else "Eye2"
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.new(EYE_SIZE, EYE_SIZE, EYE_SIZE)
		eye.Color = kind.eye
		eye.Material = Enum.Material.Neon
		eye.Parent = model
		weldTo(root, eye, CFrame.new(sign * EYE_X, EYE_Y, -EYE_Z))

		if i == 1 then
			local eyeLight = Instance.new("PointLight")
			eyeLight.Color = kind.eye
			eyeLight.Range = 26
			eyeLight.Brightness = 2.5
			eyeLight.Parent = eye
		end
	end

	local sound = Instance.new("Sound")
	sound.Name = "HunterDrone"
	sound.SoundId = "rbxassetid://137974203982962" -- robot 1
	sound.Looped = true
	sound.Volume = 0.8
	-- Pitched per kind, so you can hear WHICH one is near before you see it.
	sound.PlaybackSpeed = kind.dronePitch
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = 170
	sound.RollOffMinDistance = 10
	sound.Parent = root
	sound:Play()

	local hum = Instance.new("Humanoid")
	hum.WalkSpeed = BASE_SPEED
	hum.MaxSlopeAngle = 89
	hum.MaxHealth = kind.hits
	hum.Health = kind.hits
	hum.Parent = model

	-- Health bar: hidden while full, appears and drains as the gun hits land.
	-- Property changes on the GUI replicate to every client with no client code.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthBar"
	billboard.Size = UDim2.fromOffset(120, 12)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.Enabled = false
	billboard.Parent = root

	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	back.BorderSizePixel = 0
	back.Parent = billboard

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
	fill.BorderSizePixel = 0
	fill.Parent = back

	hum.HealthChanged:Connect(function(health)
		billboard.Enabled = health < hum.MaxHealth
		fill.Size = UDim2.fromScale(math.clamp(health / hum.MaxHealth, 0, 1), 1)
	end)

	return model
end

-- A cell centre inside `district`, preferring one well away from `from`.
--
-- Picks from the NAV GRAPH rather than from polar maths. The old version rolled
-- a radius in one fixed band (180-480) and an angle, which straddled the middle
-- district and clipped the other two — so the outer ring players spawn in, and
-- the deep inner ring, both started nearly empty however many hunters existed.
-- It could also land inside a wall or in the hub sanctuary, where a hunter does
-- nothing but walk out. Every entry in `MazeNav.cellPos` is reachable by
-- construction, and band 0 is skipped because the hub is a sanctuary.
--
-- `from` is the player spawn: nothing should appear on top of the room players
-- are standing in during the countdown. That test is dropped rather than failed
-- if a district has no cell far enough, since the inner district is small and
-- entirely far from the rim anyway.
local function farSpawn(from: Vector3, district: number): Vector3
	local rng = Random.new()
	local far: { Vector3 } = {}
	local any: { Vector3 } = {}
	for key, pos in MazeNav.cellPos do
		local band = MazeNav.bandOf(key)
		if band == 0 or MazeNav.districtOf(band) ~= district then
			continue
		end
		table.insert(any, pos)
		if (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(from.X, 0, from.Z)).Magnitude > 220 then
			table.insert(far, pos)
		end
	end

	local pool = if #far > 0 then far else any
	if #pool == 0 then
		return Vector3.new(0, 4, 400) -- no graph yet; only before the first build
	end
	local pick = pool[rng:NextInteger(1, #pool)]
	return Vector3.new(pick.X, 4, pick.Z)
end

-- A dying hunter's blast: a bright Neon ball that expands and fades. No asset
-- needed; if the user later supplies BLAST_SOUND_ID this plays alongside it.
local function explodeAt(pos: Vector3)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanTouch = false
	ball.CanQuery = false
	ball.Material = Enum.Material.Neon
	ball.Color = Color3.fromRGB(255, 140, 40)
	ball.Size = Vector3.new(2, 2, 2)
	ball.CFrame = CFrame.new(pos)
	ball.Parent = workspace

	local light = Instance.new("PointLight")
	light.Color = ball.Color
	light.Range = 32
	light.Brightness = 5
	light.Parent = ball

	if BLAST_SOUND_ID ~= "" then
		local sound = Instance.new("Sound")
		sound.SoundId = BLAST_SOUND_ID
		sound.Parent = ball
		sound:Play()
	end

	local tween = TweenService:Create(
		ball,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(BLAST_RADIUS * 2, BLAST_RADIUS * 2, BLAST_RADIUS * 2), Transparency = 1 }
	)
	tween:Play()
	tween.Completed:Connect(function()
		ball:Destroy()
	end)
end

-- Is `toPos` visible from `fromPos`, i.e. no ring/spoke wall between them?
local function canSee(fromPos: Vector3, toPos: Vector3): boolean
	local maze = workspace:FindFirstChild("Maze")
	if not maze then
		return true
	end
	local origin = fromPos + Vector3.new(0, 2.5, 0)
	local dir = (toPos + Vector3.new(0, 2, 0)) - origin
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { maze }
	local hit = workspace:Raycast(origin, dir, params)
	if not hit then
		return true
	end
	local n = hit.Instance.Name
	return not (n == "Arc" or n == "Spoke" or n == "Perimeter")
end

-- The vault chamber at the centre is a sanctuary: hunters neither sense nor
-- harm you inside it. The run's whole shape is a long committed descent, and
-- arriving at the bottom with 20 HP and three hunters on you is a coin-flip
-- ending rather than a climax. This gives a breather at the turnaround — you
-- still have to carry the thing all the way back out, with every hunter alerted.
local SANCTUARY_RADIUS = 40 -- band 0 (the hub) ends at 30; a little margin past it

local function inSanctuaryPos(pos: Vector3): boolean
	return Vector2.new(pos.X, pos.Z).Magnitude < SANCTUARY_RADIUS
end

local function inSanctuary(plr: Player): boolean
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return false
	end
	return inSanctuaryPos((hrp :: BasePart).Position)
end

-- Sanctuary containment: hunters stay OUT of the vault chamber, not just
-- harmless inside it. Not sensing you while one paces the dais next to you
-- doesn't read as a breather — it reads as a bug. So any destination that lands
-- in the hub (band 0, the single centre cell) is redirected to the nearest cell
-- just outside it, and the hunter rings the gate instead of walking in.
--
-- This has to exist because several targets legitimately resolve to the hub:
-- the vault alarm summons every hunter to the vault's position, the evac alert
-- sends them at the centre, and a flank pick can choose the hub as a neighbour
-- of a band-1 cell. Returns nil when the hub has no open neighbour (never in a
-- built maze, since the hub is reachable) — callers treat that as "no target".
local function keepOutOfHub(key: number?, from: Vector3): number?
	if not key or MazeNav.bandOf(key) > 0 then
		return key
	end
	local best, bestDist = nil, math.huge
	for _, nb in MazeNav.adj[key] or {} do
		if MazeNav.bandOf(nb) == 0 then
			continue
		end
		local c = MazeNav.cellPos[nb]
		if not c then
			continue
		end
		local d = (c - from).Magnitude
		if d < bestDist then
			best, bestDist = nb, d
		end
	end
	return best
end

-- Beyond the perimeter wall: the staging room and its corridor. Hunters belong
-- to the maze and nothing out there is theirs — the room is where players are
-- parked during the countdown and where a carrier banks the round, so letting a
-- hunter follow someone through the perimeter cut would make the one guaranteed
-- safe space in the game not safe. The maze has no cells out there either, so a
-- hunter that wandered out would be navigating off the end of its own graph.
--
-- Reads the boundary off MazeNav rather than hardcoding it, so a retuned RADII
-- can't leave this stale. 0 before the first build; the guard is inert until then.
local function outsideMaze(pos: Vector3): boolean
	if MazeNav.perimeterR <= 0 then
		return false
	end
	return Vector2.new(pos.X, pos.Z).Magnitude > MazeNav.perimeterR
end

local function outOfRound(plr: Player): boolean
	if plr:GetAttribute("Escaped") or plr:GetAttribute("Caught") then
		return true
	end
	if inSanctuary(plr) then
		return true
	end
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp and outsideMaze((hrp :: BasePart).Position) then
		return true
	end
	local safeUntil = plr:GetAttribute("SafeUntil")
	return typeof(safeUntil) == "number" and safeUntil > os.clock()
end

function HunterService.Start()
	if not workspace:GetAttribute("MazeReady") then
		workspace:GetAttributeChangedSignal("MazeReady"):Wait()
	end
	local spawnLocation = workspace:WaitForChild("SpawnLocation") :: SpawnLocation

	local cellKeys: { number } = {}
	local maxBand = 0

	-- Re-snapshots the nav graph after a rebuild — the adjacency has changed.
	local function refreshNav()
		cellKeys = {}
		for key in MazeNav.cellPos do
			-- Band 0 is the sanctuary; it's never a wander destination (this pool
			-- feeds randomCell only). See keepOutOfHub for the other routes in.
			if MazeNav.bandOf(key) == 0 then
				continue
			end
			table.insert(cellKeys, key)
		end
		maxBand = MazeNav.maxBand()
	end
	refreshNav()

	local rng = Random.new()
	local function randomCell(): number
		return cellKeys[rng:NextInteger(1, #cellKeys)]
	end

	-- Nearest player this hunter can currently SENSE (behind cover = unseen).
	-- `range` is per kind, and it is the stat that most changes how a district
	-- plays. Sensing used to be line-of-sight with no limit at all: any hunter
	-- saw any player down the whole length of a corridor. A Stray at 90 studs can
	-- be walked past; a Warden at 220 owns the corridor it is standing in.
	--
	-- Distance is checked BEFORE the raycast, because the cheap test rejects most
	-- players and `canSee` is a raycast per candidate per repath.
	local function nearestSensed(pos: Vector3, range: number): (Player?, Model?)
		local bestP, bestC, bestDist = nil, nil, math.huge
		for _, plr in Players:GetPlayers() do
			if outOfRound(plr) then
				continue
			end
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hrp then
				continue
			end
			local d = (hrp.Position - pos).Magnitude
			if d > range or d >= bestDist then
				continue
			end
			if not canSee(pos, hrp.Position) then
				continue -- a wall is between us: hidden from this hunter
			end
			bestP, bestC, bestDist = plr, char, d
		end
		return bestP, bestC
	end

	-- Nearest player within physical reach (used for the catch — no LOS check, so
	-- bumping into a hidden player still catches; cheap, no raycast).
	local function nearestReachable(pos: Vector3): (Player?, Model?, number)
		local bestP, bestC, bestDist = nil, nil, math.huge
		for _, plr in Players:GetPlayers() do
			if outOfRound(plr) then
				continue
			end
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				local d = (hrp.Position - pos).Magnitude
				if d < bestDist then
					bestP, bestC, bestDist = plr, char, d
				end
			end
		end
		return bestP, bestC, bestDist
	end

	-- The catch sequence (shared by all hunters): freeze the player, loom,
	-- red-out, then ~1.4s later spill their haul/vault (if any) and drop them
	-- at their last checkpoint. The hunter itself stays put — it no longer
	-- warps away, so it lingers guarding the kill.
	local function catchPlayer(player: Player, char: Model, hunter: Model, root: BasePart, growl: Sound?)
		if player:GetAttribute("Caught") then
			return
		end
		player:SetAttribute("Caught", true)
		local phrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if phrp then
			phrp.Anchored = true
			root.CFrame = CFrame.lookAt(root.Position, Vector3.new(phrp.Position.X, root.Position.Y, phrp.Position.Z))
		end
		root.Anchored = true
		if growl then
			growl.Volume = 1.6
		end
		task.delay(1.4, function()
			-- Death position, captured before the checkpoint teleport moves the
			-- player away. `phrp` has been anchored (frozen) since the initial
			-- catch, so its Position still reads the exact death spot.
			local deathPos = if phrp then phrp.Position else root.Position

			-- Spill the haul as a recoverable pile — and the vault as its own
			-- separate object, if the player was carrying it — before the
			-- checkpoint teleport. Both can land in the same spot; they mean
			-- different things (see docs/game/Salvage.md).
			local haul = player:GetAttribute("Haul")
			if typeof(haul) == "number" and haul > 0 then
				SalvageService.dropHaul(deathPos, haul)
				player:SetAttribute("Haul", 0)
			end
			if player:GetAttribute("HasVault") then
				SalvageService.dropVault(deathPos)
				player:SetAttribute("HasVault", false)
			end

			local cp = player:GetAttribute("Checkpoint")
			local dest = if typeof(cp) == "CFrame"
				then (cp :: CFrame) + Vector3.new(0, 3, 0)
				else spawnLocation.CFrame + Vector3.new(0, 3, 0)
			if phrp then
				phrp.Anchored = false
			end
			char:PivotTo(dest)
			if growl then
				growl.Volume = 0.8
			end
			root.Anchored = false
			-- The hunter no longer warps away — it lingers guarding the kill
			-- (and the drops it just made). Safe: the player respawns at their
			-- last gate with SafeUntil grace, not at the death site itself (see
			-- docs/game/Checkpoint.md).
			-- Fresh life at the checkpoint = a full bar again (not regen — you only
			-- refill by dying back to a checkpoint or grabbing a MedKit).
			player:SetAttribute("Health", player:GetAttribute("MaxHealth") or 100)
			player:SetAttribute("Caught", false)
		end)
	end

	-- `district` is this hunter's HOME, not a leash: it decides only where the
	-- hunter enters the maze, and it roams freely from there. Carrying it through
	-- death and rebuild is what stops the spread collapsing over a round — every
	-- respawn would otherwise land wherever the old single band was, and the map
	-- would drift back to a clump in the middle.
	local function spawnHunter(kind: HunterKind, district: number)
		local hunter = buildHunter(kind)
		local root = hunter.PrimaryPart :: BasePart
		local hum = hunter:FindFirstChildOfClass("Humanoid") :: Humanoid
		local growl = root:FindFirstChild("HunterDrone") :: Sound?
		hunter:SetAttribute("HomeDistrict", district)
		hunter:PivotTo(CFrame.new(farSpawn(spawnLocation.Position, district)))
		hunter.Parent = workspace
		-- Visible to peers for separation from the moment it exists; removed in
		-- Died below, so a dead hunter stops repelling the living.
		activeRoots[hunter] = root

		-- Per-hunter connections torn down when this hunter dies. The Heartbeat
		-- catch loop below is the load-bearing one: without disconnecting it, it
		-- keeps firing against the destroyed root's *frozen* death position and
		-- phantom-catches anyone who later walks over that spot — an invisible
		-- 7-stud trap left at every kill site, forever. (The decision-loop
		-- task.spawn self-terminates via its `while hunter.Parent` guard, so it
		-- isn't tracked here.)
		local conns: { RBXScriptConnection } = {}

		-- Death -> explosion -> catch -> respawn. catchPlayer/farSpawn/spawnLocation
		-- are only in scope inside this closure, which is exactly why this wiring
		-- lives here rather than being exported.
		hum.Died:Connect(function()
			for _, c in conns do
				c:Disconnect()
			end
			activeRoots[hunter] = nil
			explodeAt(root.Position)
			for _, plr in Players:GetPlayers() do
				if outOfRound(plr) then
					continue
				end
				local c = plr.Character
				local phrp = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
				if phrp and (phrp.Position - root.Position).Magnitude < BLAST_RADIUS then
					catchPlayer(plr, c :: Model, hunter, root, growl)
				end
			end
			hunter:Destroy()
			-- Same kind, same district, so the population of each is identical at
			-- the end of a round and at the start.
			task.delay(RESPAWN_DELAY, function()
				spawnHunter(kind, district)
			end)
		end)

		local lastKnownCell: number? = nil
		local wanderTarget: number? = nil

		-- This hunter's fixed quirks. `flankSeed` picks which approach it claims
		-- (stable, so it doesn't swap every repath and dither in a doorway);
		-- `side` is which way it steps around a peer directly in its path;
		-- `speedScale` strings the pack out.
		local flankSeed = rng:NextInteger(0, 9999)
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local speedScale = 1 + rng:NextNumber(-SPEED_VARIANCE, SPEED_VARIANCE)

		-- Two multipliers, and they do different jobs. `speedScale` is this
		-- hunter's own ±12% jitter, which strings a pack out; `kind.speedScale`
		-- is the type's character, applied on top of the depth ramp so the
		-- "faster the deeper" curve still shapes all three.
		local function setSpeed(base: number)
			hum.WalkSpeed = base * speedScale * kind.speedScale
		end

		-- Lateral offset that keeps this hunter out of its peers' pockets.
		local function spread(travelDir: Vector3): Vector3
			local push = Vector3.zero
			for other, otherRoot in activeRoots do
				if other == hunter or otherRoot.Parent == nil then
					continue
				end
				local delta = root.Position - otherRoot.Position
				local flat = Vector3.new(delta.X, 0, delta.Z)
				local dist = flat.Magnitude
				if dist < 0.1 or dist > SEPARATION_DIST then
					continue
				end
				push += flat.Unit * ((SEPARATION_DIST - dist) / SEPARATION_DIST)
			end
			if push.Magnitude < 0.01 then
				return Vector3.zero
			end

			-- Keep only the component ACROSS the direction of travel. A peer
			-- directly ahead should make this hunter step around it, not brake
			-- behind it — braking is what produced the single file to begin with.
			local lateral = push - travelDir * push:Dot(travelDir)
			if lateral.Magnitude < 1 then
				-- Peer is dead ahead or dead behind, so there's no lateral
				-- information to use. Fall back to this hunter's own fixed side;
				-- peers that drew the other side go the other way, which is what
				-- splits the file in two.
				lateral = Vector3.new(-travelDir.Z, 0, travelDir.X) * side
			end
			return lateral.Unit * SEPARATION_STRENGTH
		end

		-- Step one cell along the graph toward destCell; returns true when reached.
		local function stepToward(destCell: number?): boolean
			if not destCell then
				return true
			end
			local hc = MazeNav.nearestCell(root.Position)
			if not hc then
				return false
			end
			if hc == destCell then
				return true
			end
			local step = MazeNav.nextStep(hc, destCell)
			local c = step and MazeNav.cellPos[step] or MazeNav.cellPos[destCell]
			if c then
				local goal = Vector3.new(c.X, root.Position.Y, c.Z)
				local delta = goal - root.Position
				local flat = Vector3.new(delta.X, 0, delta.Z)
				local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.zero
				hum:MoveTo(goal + spread(dir))
			end
			return false
		end

		-- Which cell a chaser actually walks to. Far out it claims a different
		-- open neighbour of the target's cell per hunter; close in it commits to
		-- the target's own cell. See FLANK_RANGE.
		local function chaseCell(targetCell: number, distToTarget: number): number
			if distToTarget < FLANK_RANGE then
				return targetCell
			end
			local neighbours = MazeNav.adj[targetCell]
			if neighbours == nil or #neighbours == 0 then
				return targetCell
			end
			return neighbours[(flankSeed % #neighbours) + 1]
		end

		-- Re-rolled per tick, not per hunter: a fixed offset lets two hunters with
		-- near-identical intervals drift back into step.
		local function nextRepath(): number
			return REPATH * (1 + rng:NextNumber(-REPATH_JITTER, REPATH_JITTER))
		end

		task.spawn(function()
			while hunter.Parent do
				if MazeNav.ready then
					-- Containment, checked before any behaviour. Targeting already
					-- ignores anyone past the perimeter, but a hunter can still
					-- drift out on MoveTo momentum near the cut, or be shoved by
					-- physics. If it's outside, the only thing it does is walk
					-- back to the nearest cell — no chase, no summon, no wander.
					if outsideMaze(root.Position) then
						setSpeed(BASE_SPEED)
						local backIn = MazeNav.nearestCell(root.Position)
						local c = backIn and MazeNav.cellPos[backIn]
						if c then
							hum:MoveTo(Vector3.new(c.X, root.Position.Y, c.Z))
						end
						task.wait(nextRepath())
						continue
					end

					-- Same containment for the sanctuary at the other end of the
					-- maze: no destination sends a hunter in, but momentum on a
					-- commit near the boundary, a blast shove, or a rebuild landing
					-- one there still can. Walking out is all it does — stepToward
					-- routes through the graph, so it leaves by a gate rather than
					-- grinding along the inside of the hub wall.
					if inSanctuaryPos(root.Position) then
						setSpeed(BASE_SPEED)
						stepToward(keepOutOfHub(MazeNav.nearestCell(root.Position), root.Position))
						task.wait(nextRepath())
						continue
					end

					local alert = workspace:GetAttribute("EvacAlert")
					if typeof(alert) == "number" and os.clock() - alert < EVAC_ALERT_SECONDS then
						-- An escape just happened: sprint for the centre so hunters
						-- converge on the pad in shot for the escape cinematic,
						-- arriving too late.
						setSpeed(MAX_SPEED)
						local centreCell = keepOutOfHub(MazeNav.nearestCell(Vector3.zero), root.Position)
						stepToward(centreCell)
						task.wait(nextRepath())
						continue
					end

					-- Summon: a shot was just fired, OR the vault alarm is
					-- ringing (SalvageService sets AlarmActive and refreshes
					-- these same attributes at the vault's position). Nearby
					-- hunters (within SUMMON_RADIUS) beeline to the position for
					-- SUMMON_WINDOW seconds — except the vault alarm is a
					-- maze-wide siren, not a local gunshot, so it bypasses the
					-- radius check entirely. Leave SUMMON_RADIUS itself alone;
					-- only the alarm skips it.
					local sAlert = workspace:GetAttribute("HunterAlert")
					local sPos = workspace:GetAttribute("HunterAlertPos")
					local alarmActive = workspace:GetAttribute("AlarmActive") == true
					if
						typeof(sAlert) == "number"
						and os.clock() - sAlert < SUMMON_WINDOW
						and typeof(sPos) == "Vector3"
						and (alarmActive or (root.Position - (sPos :: Vector3)).Magnitude < SUMMON_RADIUS)
					then
						setSpeed(MAX_SPEED)
						-- The alarm's position IS the vault, i.e. the hub — every
						-- summoned hunter converges on the gates around it instead.
						stepToward(keepOutOfHub(MazeNav.nearestCell(sPos :: Vector3), root.Position))
						task.wait(nextRepath())
						continue
					end

					local _, target = nearestSensed(root.Position, kind.sightRange)
					local thrp = target and target:FindFirstChild("HumanoidRootPart") :: BasePart?
					if thrp then
						-- CHASE
						local pcell = MazeNav.nearestCell(thrp.Position)
						lastKnownCell = pcell
						wanderTarget = nil
						if pcell then
							setSpeed(math.clamp(BASE_SPEED + (maxBand - MazeNav.bandOf(pcell)) * SPEED_PER_BAND, BASE_SPEED, MAX_SPEED))
							local distToTarget = (thrp.Position - root.Position).Magnitude
							-- Reached its claimed approach cell but still too far to
							-- commit? Hold it. That reads as cutting off an exit, and
							-- it resolves itself the moment the target moves cell.
							-- keepOutOfHub: a flank pick is a NEIGHBOUR of the target's
							-- cell, so chasing someone in band 1 can claim the hub.
							local approach = keepOutOfHub(chaseCell(pcell, distToTarget), root.Position)
							if stepToward(approach) and distToTarget < FLANK_RANGE then
								hum:MoveTo(thrp.Position) -- committed: close in
							end
						end
					elseif lastKnownCell then
						-- SEARCH the last place it sensed you
						setSpeed(BASE_SPEED)
						if stepToward(lastKnownCell) then
							lastKnownCell = nil -- reached, gave up
						end
					else
						-- WANDER
						setSpeed(BASE_SPEED)
						if not wanderTarget or stepToward(wanderTarget) then
							wanderTarget = randomCell()
						end
					end
				end
				task.wait(nextRepath())
			end
		end)

		table.insert(conns, RunService.Heartbeat:Connect(function(dt)
			local player, char, dist = nearestReachable(root.Position)
			if not (player and char and dist < CATCH_DIST) then
				return
			end
			-- Attacked: bleed the player's Health. Only a drop to 0 triggers the
			-- catch. `nearestReachable` already skips out-of-round players, so a
			-- mid-catch / freshly-checkpointed player isn't drained further.
			local hp = player:GetAttribute("Health")
			if typeof(hp) ~= "number" then
				return
			end
			hp -= kind.drain * dt
			if hp > 0 then
				player:SetAttribute("Health", hp)
				return
			end
			player:SetAttribute("Health", 0)
			catchPlayer(player, char, hunter, root, growl)
		end))

		local function watchRestart(plr: Player)
			table.insert(conns, plr:GetAttributeChangedSignal("Escaped"):Connect(function()
				if plr:GetAttribute("Escaped") == false then
					hunter:PivotTo(CFrame.new(farSpawn(spawnLocation.Position, district)))
					lastKnownCell = nil
					wanderTarget = nil
				end
			end))
		end
		table.insert(conns, Players.PlayerAdded:Connect(watchRestart))
		for _, plr in Players:GetPlayers() do
			watchRestart(plr)
		end
	end

	-- One kind per district, indexed to match: HUNTER_KINDS[i] lives in
	-- district i.
	for district, kind in HUNTER_KINDS do
		for _ = 1, kind.count do
			spawnHunter(kind, district)
		end
	end

	workspace:GetAttributeChangedSignal("MazeGeneration"):Connect(function()
		refreshNav()
		-- Old wander/search targets refer to the previous layout; re-homing the
		-- model is enough — stepToward re-reads MazeNav live each step and will
		-- re-path within one REPATH tick.
		for _, hunter in workspace:GetChildren() do
			if hunter:IsA("Model") and hunter.Name == "Hunter" then
				-- Re-homed into its own district on the NEW layout. Read back off
				-- the attribute rather than closed over, because this loop walks
				-- every hunter in the world, not one hunter's own scope.
				local home = hunter:GetAttribute("HomeDistrict")
				local district = if typeof(home) == "number" then home else #HUNTER_KINDS
				hunter:PivotTo(CFrame.new(farSpawn(spawnLocation.Position, district)))
			end
		end
		-- A stale summon alert must not carry into a new round.
		workspace:SetAttribute("HunterAlert", nil)
		workspace:SetAttribute("HunterAlertPos", nil)
	end)
end

return HunterService
