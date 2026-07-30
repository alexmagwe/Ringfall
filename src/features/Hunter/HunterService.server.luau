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

local MazeNav = require(ReplicatedStorage.Features.Maze.MazeNav)
-- Cross-feature server require for the drop-on-catch path (dropHaul/
-- dropVault), the same pattern EscapeService already uses for MazeService.
local SalvageService = require(ServerScriptService.Features.Salvage.SalvageService)

local HunterService = {}
HunterService.Priority = 15

local HUNTER_COUNT = 6
local BASE_SPEED = 17 -- outer rings: just above walk (16), below sprint (26)
local MAX_SPEED = 29 -- near the centre: harder as you go deeper
local SPEED_PER_BAND = 1.0
local CATCH_DIST = 7
local REPATH = 0.7
local EVAC_ALERT_SECONDS = 4 -- window after any escape where every hunter sprints for the centre
local EYE_COLOR = Color3.fromRGB(255, 40, 30)

-- Combat: 10 gunshots kill a hunter. On death it explodes and drags anyone
-- caught in the blast to their checkpoint (reuses catchPlayer — no player-HP
-- model). It respawns at a far cell so the maze never empties.
local HUNTER_HITS = 10
local BLAST_RADIUS = 14
local RESPAWN_DELAY = 4
-- HP drained per second while a hunter is within CATCH_DIST. The catch (loom +
-- checkpoint) only fires once Health hits 0, so a hunter has to *stay* on you —
-- you can break away and stop the bleed. ~4s of sustained contact = a catch.
local HEALTH_DRAIN = 25
local BLAST_SOUND_ID = "" -- user may supply a boom sound later; silent until set

-- Summon: a hunter that gets shot alerts nearby hunters to the shooter's
-- position (GunService sets these attributes on a hit; this file only
-- consumes them, mirroring the existing EvacAlert idiom above).
local SUMMON_WINDOW = 5 -- seconds other hunters beeline to the alert
local SUMMON_RADIUS = 200 -- only hunters within this of the alert respond
local SIREN_SOUND_ID = "" -- user supplies; siren plays on the shot hunter

-- Pack behaviour. Every hunter runs the same decision loop against the same
-- deterministic shortest path (MazeNav.nextStep is a plain BFS, so identical
-- start + identical goal = identical first step), which made the whole pack
-- travel nose-to-tail down one corridor and read as a single animal. These four
-- break the symmetry; none of them changes HUNTER_COUNT or the speeds.
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

-- The body is the classic duck mesh, scaled up to loom and tinted near-black so
-- it reads as a silhouette rather than a bath toy. Scale is on a 2x2x2 host
-- part; 7 renders ~7.5 studs tall against a 5-stud player.
local DUCK_MESH = "rbxassetid://9419831"
local DUCK_TEXTURE = "rbxassetid://268365500"
local DUCK_SCALE = 7
-- This texture is NOT the yellow bath duck — it's already a dark mechanical duck
-- with red eyes painted on. So the tint only knocks it down; going much below
-- this flattens the panel detail and teal beak into a featureless black blob.
local DUCK_TINT = Vector3.new(0.6, 0.58, 0.66) -- multiplies the texture
local DUCK_LIFT = 0.8 -- sits the mesh's feet on the collider's base

-- The neon eyes sit directly over the texture's painted eye sockets, measured in
-- Studio against a 5-stud reference at a level camera (the gameplay angle). The
-- head surface at this line is ~2.65 deep, so 2.80 clears it by a hair — enough
-- to render, tight enough that parallax doesn't drag the glow off the socket
-- when you look up at it. Re-measure all three if DUCK_SCALE changes: these are
-- studs, not proportions.
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

local function buildHunter(): Model
	local model = Instance.new("Model")
	model.Name = "Hunter"

	-- Invisible mover/collider. Kept at 3x6x3 so maze corridor navigation is
	-- unchanged by the swap to a wider-looking body.
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(3, 6, 3)
	root.Transparency = 1
	root.CanCollide = true
	root.Parent = model
	model.PrimaryPart = root

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2, 2, 2)
	body.Parent = model
	weldTo(root, body, CFrame.new(0, DUCK_LIFT, 0))

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = DUCK_MESH
	mesh.TextureId = DUCK_TEXTURE
	mesh.Scale = Vector3.new(DUCK_SCALE, DUCK_SCALE, DUCK_SCALE)
	mesh.VertexColor = DUCK_TINT
	mesh.Parent = body

	-- Twin eyes. Only the first carries the light (one PointLight is enough for
	-- the glow, and HunterController focuses its catch-cam on a part named "Eye").
	for i, sign in ipairs({ -1, 1 }) do
		local eye = Instance.new("Part")
		eye.Name = if i == 1 then "Eye" else "Eye2"
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.new(EYE_SIZE, EYE_SIZE, EYE_SIZE)
		eye.Color = EYE_COLOR
		eye.Material = Enum.Material.Neon
		eye.Parent = model
		weldTo(root, eye, CFrame.new(sign * EYE_X, EYE_Y, -EYE_Z))

		if i == 1 then
			local eyeLight = Instance.new("PointLight")
			eyeLight.Color = EYE_COLOR
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
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = 170
	sound.RollOffMinDistance = 10
	sound.Parent = root
	sound:Play()

	local hum = Instance.new("Humanoid")
	hum.WalkSpeed = BASE_SPEED
	hum.MaxSlopeAngle = 89
	hum.MaxHealth = HUNTER_HITS
	hum.Health = HUNTER_HITS
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

-- A far-ish random point on the maze floor (well away from `from`).
local function farSpawn(from: Vector3): Vector3
	local rng = Random.new()
	for _ = 1, 24 do
		local r = rng:NextNumber(180, 480)
		local a = rng:NextNumber(0, math.pi * 2)
		local p = Vector3.new(r * math.cos(a), 4, r * math.sin(a))
		if (Vector3.new(p.X, 0, p.Z) - Vector3.new(from.X, 0, from.Z)).Magnitude > 220 then
			return p
		end
	end
	return Vector3.new(0, 4, 400)
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

local function inSanctuary(plr: Player): boolean
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return false
	end
	local p = (hrp :: BasePart).Position
	return Vector2.new(p.X, p.Z).Magnitude < SANCTUARY_RADIUS
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
	local function nearestSensed(pos: Vector3): (Player?, Model?)
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
			if not canSee(pos, hrp.Position) then
				continue -- a wall is between us: hidden from this hunter
			end
			local d = (hrp.Position - pos).Magnitude
			if d < bestDist then
				bestP, bestC, bestDist = plr, char, d
			end
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

	local function spawnHunter()
		local hunter = buildHunter()
		local root = hunter.PrimaryPart :: BasePart
		local hum = hunter:FindFirstChildOfClass("Humanoid") :: Humanoid
		local growl = root:FindFirstChild("HunterDrone") :: Sound?
		hunter:PivotTo(CFrame.new(farSpawn(spawnLocation.Position)))
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
			task.delay(RESPAWN_DELAY, spawnHunter) -- keep the maze populated
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

		local function setSpeed(base: number)
			hum.WalkSpeed = base * speedScale
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

					local alert = workspace:GetAttribute("EvacAlert")
					if typeof(alert) == "number" and os.clock() - alert < EVAC_ALERT_SECONDS then
						-- An escape just happened: sprint for the centre so hunters
						-- converge on the pad in shot for the escape cinematic,
						-- arriving too late.
						setSpeed(MAX_SPEED)
						local centreCell = MazeNav.nearestCell(Vector3.zero)
						stepToward(centreCell)
						task.wait(nextRepath())
						continue
					end

					-- Summon: a hunter just got shot, OR the vault alarm is
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
						stepToward(MazeNav.nearestCell(sPos :: Vector3))
						task.wait(nextRepath())
						continue
					end

					local _, target = nearestSensed(root.Position)
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
							if stepToward(chaseCell(pcell, distToTarget)) and distToTarget < FLANK_RANGE then
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
			hp -= HEALTH_DRAIN * dt
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
					hunter:PivotTo(CFrame.new(farSpawn(spawnLocation.Position)))
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

	for _ = 1, HUNTER_COUNT do
		spawnHunter()
	end

	workspace:GetAttributeChangedSignal("MazeGeneration"):Connect(function()
		refreshNav()
		-- Old wander/search targets refer to the previous layout; re-homing the
		-- model is enough — stepToward re-reads MazeNav live each step and will
		-- re-path within one REPATH tick.
		for _, hunter in workspace:GetChildren() do
			if hunter:IsA("Model") and hunter.Name == "Hunter" then
				hunter:PivotTo(CFrame.new(farSpawn(spawnLocation.Position)))
			end
		end
		-- A stale summon alert must not carry into a new round.
		workspace:SetAttribute("HunterAlert", nil)
		workspace:SetAttribute("HunterAlertPos", nil)
	end)
end

return HunterService
