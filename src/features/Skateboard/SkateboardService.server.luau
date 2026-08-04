--!strict
-- The skateboard: a maze pickup you ride for extra speed, but only where the
-- ground is hard.
--
-- The whole feature is one trade. The outer district is the longest leg of the
-- run and the one you cross twice, and it is also the grass one — so the board
-- is found out there and is useless out there. It starts paying the moment you
-- reach the flooded middle, and it pays again on the way back out with the
-- vault, right up to the gate where the turf starts.
--
-- SERVER-AUTHORITATIVE, deliberately. Riding is a speed multiplier, which is
-- precisely the thing a movement exploit wants to claim; the client may only
-- ask (Net.ToggleRide), and every grant is re-checked here against "do you hold
-- a board" and "where are you standing". The client re-derives nothing.
--
-- Auto-loaded (name ends in `Service`). Priority after PickupsService (12), so
-- the scatter has already placed the board by the time this binds.
-- .server.luau => splitter routes to ServerScriptService.Features.Skateboard.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local MazeNav = require(ReplicatedStorage.Features.Maze.MazeNav)
local PickupsConstants = require(ReplicatedStorage.Features.Pickups.Constants)
local Constants = require(ReplicatedStorage.Features.Skateboard.Constants)
local Net = require(ReplicatedStorage.Features.Skateboard.Net)

local SkateboardService = {}
SkateboardService.Priority = 13

local BOARD_NAME = "SkateboardRide"

------------------------------------------------------------------------------
-- Where the board rolls
------------------------------------------------------------------------------

-- District index at a world position, or nil for "not in the maze at all"
-- (the staging room and its corridor have no cells). Callers treat nil as
-- rideable: the run-up from the door out to the perimeter is flat plate, and
-- refusing to roll there would just make the feature feel broken at the one
-- moment the player is most likely to try it.
local function districtAt(pos: Vector3): number?
	if not MazeNav.ready then
		return nil
	end
	if MazeNav.perimeterR > 0 and Vector2.new(pos.X, pos.Z).Magnitude > MazeNav.perimeterR then
		return nil
	end
	local cell = MazeNav.nearestCell(pos)
	if not cell then
		return nil
	end
	return MazeNav.districtOf(MazeNav.bandOf(cell))
end

local function rootOf(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Split from `canRide` so the caller can tell the two refusals apart: "you have
-- no board" is silent, "not on grass" earns an explanation.
local function groundAllows(player: Player): boolean
	local root = rootOf(player)
	if not root then
		return false
	end
	local district = districtAt(root.Position)
	return district == nil or not Constants.BLOCKED_DISTRICTS[district]
end

------------------------------------------------------------------------------
-- The board underfoot
------------------------------------------------------------------------------

-- A built-from-code board, used when the user has placed no art. Same rule as
-- every other pickup: the feature has to work before anything exists in Studio.
local function fallbackBoard(): Model
	local model = Instance.new("Model")
	model.Name = BOARD_NAME

	local length = Constants.DECK_LENGTH
	local deck = Instance.new("Part")
	deck.Name = "Deck"
	deck.Size = Vector3.new(length * 0.36, 0.22, length)
	deck.Color = Constants.DECK_COLOR
	deck.Material = Enum.Material.SmoothPlastic
	deck.TopSurface = Enum.SurfaceType.Smooth
	deck.BottomSurface = Enum.SurfaceType.Smooth
	deck.Parent = model
	local corner = Instance.new("SpecialMesh")
	corner.MeshType = Enum.MeshType.Brick
	corner.Scale = Vector3.new(1, 1, 1)
	corner.Parent = deck
	model.PrimaryPart = deck

	local grip = Instance.new("Part")
	grip.Name = "Grip"
	grip.Size = Vector3.new(length * 0.30, 0.07, length * 0.88)
	grip.Color = Constants.TRIM_COLOR
	grip.Material = Enum.Material.SmoothPlastic
	grip.CFrame = deck.CFrame * CFrame.new(0, 0.14, 0)
	grip.Parent = model

	local wx, wz = length * 0.14, length * 0.31
	for _, offset in { Vector3.new(wx, -0.24, wz), Vector3.new(-wx, -0.24, wz), Vector3.new(wx, -0.24, -wz), Vector3.new(-wx, -0.24, -wz) } do
		local wheel = Instance.new("Part")
		wheel.Name = "Wheel"
		wheel.Shape = Enum.PartType.Cylinder
		wheel.Size = Vector3.new(0.26, 0.42, 0.42)
		wheel.Color = Constants.TRIM_COLOR
		wheel.Material = Enum.Material.SmoothPlastic
		wheel.CFrame = deck.CFrame * CFrame.new(offset)
		wheel.Parent = model
	end

	return model
end

-- The user's art if they made one, else the fallback. Accepts the same shapes
-- PickupsService does, and unwraps a Tool for the same load-bearing reason: a
-- Tool anywhere in Workspace auto-equips off a Handle touch, and this one is
-- welded to the player's feet.
local function boardModel(): Model
	local folder = ServerStorage:FindFirstChild(PickupsConstants.MODELS_FOLDER)
	local template = folder and folder:FindFirstChild(Constants.MODEL_NAME)
	if not template or not (template:IsA("Model") or template:IsA("Tool") or template:IsA("BasePart")) then
		return fallbackBoard()
	end

	local clone = template:Clone()
	local model: Model
	if clone:IsA("Tool") then
		model = Instance.new("Model")
		for _, child in clone:GetChildren() do
			child.Parent = model
		end
		clone:Destroy()
	elseif clone:IsA("Model") then
		model = clone
	else
		model = Instance.new("Model")
		clone.Parent = model
	end

	-- Free-model art can ship its own Scripts; this one is pure decoration.
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	-- NEUTRALISE SEATS. A `Seat` or `VehicleSeat` welds whoever touches it and
	-- takes over their movement — and free-model vehicles are built around one.
	-- This is the same class of bug as the Tool auto-equip that made picking up
	-- a health kit drop the player through the floor: an invisible weld to
	-- something this code is about to anchor or destroy.
	--
	-- `Disabled = true` rather than `:Destroy()`, because the seat is usually
	-- load-bearing GEOMETRY (the free-model board is a Part and a VehicleSeat,
	-- so destroying it removes half the deck). Disabling keeps the shape and
	-- removes only the behaviour.
	for _, d in model:GetDescendants() do
		if d:IsA("Seat") or d:IsA("VehicleSeat") then
			d.Disabled = true
		end
	end

	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
	end

	-- NORMALISE THE ART'S SIZE. Without this the board's scale is whatever the
	-- model happened to be exported at, so the feature looks right or wrong
	-- depending on someone else's export settings — and a board authored in
	-- metres swallows the rider. Longest horizontal axis becomes DECK_LENGTH;
	-- the model keeps its proportions.
	local extents = model:GetExtentsSize()
	-- Longest of all three axes, matching the Pickups scaler so the board the
	-- maze holds and the board under your feet cannot be measured differently.
	-- Identical for a skateboard, which is longest nose-to-tail regardless.
	local longest = math.max(extents.X, extents.Y, extents.Z)
	if longest > 0.01 then
-- `ScaleTo` is ABSOLUTE, not a multiplier. It sets the scale against the
	-- size the model was AUTHORED at, so it has to be composed with the scale
	-- the model already carries — `GetScale()` on this board is 2.67, and
	-- `ScaleTo(target / longest)` therefore shrank it to 1.5 studs instead of
	-- the 4 it was asked for. `GetScale() * ratio` is the relative form.
		model:ScaleTo(model:GetScale() * (Constants.DECK_LENGTH / longest))
	end

	model.Name = BOARD_NAME
	return model
end

local function unmountArt(player: Player)
	local char = player.Character
	local existing = char and char:FindFirstChild(BOARD_NAME)
	if existing then
		existing:Destroy()
	end
end

-- Welds the board under the character. Every part is massless and non-colliding
-- so it changes nothing about how the character moves — the speed comes from
-- the attribute, not from physics. It is decoration that says "you are riding".
local function mountArt(player: Player)
	local char = player.Character
	local root = rootOf(player)
	if not char or not root then
		return
	end
	unmountArt(player)

	local model = boardModel()
	local primary = model.PrimaryPart
	if not primary then
		model:Destroy()
		return
	end

	model:PivotTo(root.CFrame * CFrame.new(0, -Constants.DECK_DROP, 0))
	for _, d in model:GetDescendants() do
		if not d:IsA("BasePart") then
			continue
		end
		d.Anchored = false
		d.CanCollide = false
		d.CanQuery = false
		d.CanTouch = false
		d.Massless = true
	end

	-- Weld the whole model rigid to its own primary first, then the primary to
	-- the character, so the art keeps its shape whatever its own joints were.
	for _, d in model:GetDescendants() do
		if not d:IsA("BasePart") or d == primary then
			continue
		end
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = primary
		weld.Part1 = d
		weld.Parent = primary
	end
	local anchorWeld = Instance.new("WeldConstraint")
	anchorWeld.Part0 = root
	anchorWeld.Part1 = primary
	anchorWeld.Parent = primary

	model.Parent = char
end

------------------------------------------------------------------------------
-- Ride state
------------------------------------------------------------------------------

-- One-shot explanation channel, same "value|nonce" shape as PickupToast: the
-- nonce forces a change even when the same refusal fires twice in a row.
local noticeNonce = 0
local function notify(player: Player, message: string)
	noticeNonce += 1
	player:SetAttribute("SkateboardNotice", `{message}|{noticeNonce}`)
end

-- Deliberately UNGUARDED — no "already in that state, nothing to do" early
-- return. That guard existed and it hid a real bug: a catch clears attributes
-- through Pickups' clearOnCatch, so by the time this ran in response the
-- `RidingSkateboard` attribute had already been nil'd, the guard saw the state
-- as correct, and the speed multiplier and the welded board both survived the
-- catch. The parts below are all idempotent (setting an attribute to its
-- current value fires nothing; unmountArt is a no-op when there is no board),
-- and this only runs on a toggle or a teardown, so paying for it is free.
local function setRiding(player: Player, riding: boolean)
	player:SetAttribute(Constants.RIDING_ATTRIBUTE, riding or nil)
	-- Sprint owns WalkSpeed and applies this every heartbeat. Cleared to nil
	-- rather than 1 so nothing is left behind on a player who never rode.
	player:SetAttribute("SpeedMultiplier", if riding then Constants.SPEED_MULTIPLIER else nil)
	if riding then
		mountArt(player)
	else
		unmountArt(player)
	end
end

function SkateboardService.Start()
	if not workspace:GetAttribute("MazeReady") then
		workspace:GetAttributeChangedSignal("MazeReady"):Wait()
	end

	Net.ToggleRide.listen(function(_, player: Player)
		if player:GetAttribute(Constants.RIDING_ATTRIBUTE) == true then
			setRiding(player, false)
			return
		end
		if player:GetAttribute(Constants.HAS_ATTRIBUTE) ~= true then
			-- Nothing to get on. Silent: the HUD prompt only exists once you
			-- hold a board, so this is a stray keypress, not a mistake.
			return
		end
		if player:GetAttribute("Caught") == true or player:GetAttribute("Escaped") == true then
			return
		end
		if not groundAllows(player) then
			notify(player, "WHEELS WON'T ROLL ON GRASS")
			return
		end
		setRiding(player, true)
	end)

	-- Riding must not survive anything that ends the ride for you. Losing the
	-- board (a catch clears `HasSkateboard` through Pickups' clearCarriedKit)
	-- and dying both dismount, or the multiplier would outlive the board.
	local function bind(player: Player)
		player:GetAttributeChangedSignal(Constants.HAS_ATTRIBUTE):Connect(function()
			if player:GetAttribute(Constants.HAS_ATTRIBUTE) ~= true then
				setRiding(player, false)
			end
		end)
		player.CharacterRemoving:Connect(function()
			setRiding(player, false)
		end)
		player.CharacterAdded:Connect(function()
			-- A respawn drops the welded art with the old rig, so the state has
			-- to reset even though the attribute change above may not fire.
			setRiding(player, false)
		end)
	end

	Players.PlayerAdded:Connect(bind)
	for _, player in Players:GetPlayers() do
		bind(player)
	end

	-- A fresh round is a fresh maze: nothing carried, nothing ridden.
	workspace:GetAttributeChangedSignal("RoundState"):Connect(function()
		if workspace:GetAttribute("RoundState") ~= "Staging" then
			return
		end
		for _, player in Players:GetPlayers() do
			setRiding(player, false)
			player:SetAttribute(Constants.HAS_ATTRIBUTE, nil)
		end
	end)

	-- Auto-dismount on crossing into grass. Polled rather than event-driven
	-- because there is no "entered a district" signal — and polled only over
	-- players who are actually riding, which is usually nobody.
	local nextPoll = 0
	RunService.Heartbeat:Connect(function()
		if os.clock() < nextPoll then
			return
		end
		nextPoll = os.clock() + Constants.DISTRICT_POLL

		for _, player in Players:GetPlayers() do
			if player:GetAttribute(Constants.RIDING_ATTRIBUTE) ~= true then
				continue
			end
			if groundAllows(player) then
				continue
			end
			setRiding(player, false)
			notify(player, "WHEELS WON'T ROLL ON GRASS")
		end
	end)
end

return SkateboardService
