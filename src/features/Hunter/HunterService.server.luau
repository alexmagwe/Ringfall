--!strict
-- Hunters: several creatures that stalk the maze. Each independently chases the
-- nearest player it can "sense" — but a player who CROUCHES with a wall breaking
-- line-of-sight goes unseen, so the hunter loses the lock and falls back to
-- SEARCHING their last-known spot, then WANDERING. Faster the deeper the target
-- is; catch drags you to your last checkpoint with a looming red-out.
--
-- Auto-loaded (name ends in `Service`). Priority after MazeService (5).
-- .server.luau => splitter routes to ServerScriptService.Features.Hunter.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MazeNav = require(ReplicatedStorage.Features.Maze.MazeNav)

local HunterService = {}
HunterService.Priority = 15

local HUNTER_COUNT = 3
local BASE_SPEED = 17 -- outer rings: just above walk (16), below sprint (26)
local MAX_SPEED = 29 -- near the centre: harder as you go deeper
local SPEED_PER_BAND = 1.0
local CATCH_DIST = 7
local REPATH = 0.7
local EYE_COLOR = Color3.fromRGB(255, 40, 30)

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
	hum.Parent = model

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

local function outOfRound(plr: Player): boolean
	if plr:GetAttribute("Escaped") or plr:GetAttribute("Caught") then
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
	local maxBand = MazeNav.maxBand()

	local cellKeys: { number } = {}
	for key in MazeNav.cellPos do
		table.insert(cellKeys, key)
	end
	local rng = Random.new()
	local function randomCell(): number
		return cellKeys[rng:NextInteger(1, #cellKeys)]
	end

	-- Nearest player this hunter can currently SENSE (crouched-behind-cover = unseen).
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
			if plr:GetAttribute("Crouched") and not canSee(pos, hrp.Position) then
				continue -- hidden from this hunter
			end
			local d = (hrp.Position - pos).Magnitude
			if d < bestDist then
				bestP, bestC, bestDist = plr, char, d
			end
		end
		return bestP, bestC
	end

	-- Nearest player within physical reach (used for the catch — no LOS/crouch, so
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

	-- The catch sequence (shared by all hunters): freeze the player, loom, red-out,
	-- then ~1.4s later drop them at their last checkpoint and warp this hunter away.
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
			hunter:PivotTo(CFrame.new(farSpawn(spawnLocation.Position)))
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

		local lastKnownCell: number? = nil
		local wanderTarget: number? = nil

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
				hum:MoveTo(Vector3.new(c.X, root.Position.Y, c.Z))
			end
			return false
		end

		task.spawn(function()
			while hunter.Parent do
				if MazeNav.ready then
					local _, target = nearestSensed(root.Position)
					local thrp = target and target:FindFirstChild("HumanoidRootPart") :: BasePart?
					if thrp then
						-- CHASE
						local pcell = MazeNav.nearestCell(thrp.Position)
						lastKnownCell = pcell
						wanderTarget = nil
						if pcell then
							hum.WalkSpeed = math.clamp(BASE_SPEED + (maxBand - MazeNav.bandOf(pcell)) * SPEED_PER_BAND, BASE_SPEED, MAX_SPEED)
							if not stepToward(pcell) then
								-- moving
							else
								hum:MoveTo(thrp.Position) -- same cell: close in
							end
						end
					elseif lastKnownCell then
						-- SEARCH the last place it sensed you
						hum.WalkSpeed = BASE_SPEED
						if stepToward(lastKnownCell) then
							lastKnownCell = nil -- reached, gave up
						end
					else
						-- WANDER
						hum.WalkSpeed = BASE_SPEED
						if not wanderTarget or stepToward(wanderTarget) then
							wanderTarget = randomCell()
						end
					end
				end
				task.wait(REPATH)
			end
		end)

		RunService.Heartbeat:Connect(function()
			local player, char, dist = nearestReachable(root.Position)
			if player and char and dist < CATCH_DIST then
				catchPlayer(player, char, hunter, root, growl)
			end
		end)

		local function watchRestart(plr: Player)
			plr:GetAttributeChangedSignal("Escaped"):Connect(function()
				if plr:GetAttribute("Escaped") == false then
					hunter:PivotTo(CFrame.new(farSpawn(spawnLocation.Position)))
					lastKnownCell = nil
					wanderTarget = nil
				end
			end)
		end
		Players.PlayerAdded:Connect(watchRestart)
		for _, plr in Players:GetPlayers() do
			watchRestart(plr)
		end
	end

	for _ = 1, HUNTER_COUNT do
		spawnHunter()
	end
end

return HunterService
