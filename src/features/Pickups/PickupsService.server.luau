--!strict
-- Scavenged pickups: ammo, stamina upgrade, MedKits. (The gun is
-- rented from the staging shelf, not scattered — see Constants.SPAWNS.)
-- Scattered at random maze cells every round; touching one grants a per-run
-- PLAYER ATTRIBUTE (never PlayerData — this is ephemeral, cleared by
-- EscapeService at round end). The compass is standard equipment now, not a
-- pickup — see docs/game/Salvage.md.
--
-- Auto-loaded (name ends in `Service`). Priority after MazeService (5), so
-- MazeNav is populated by the time this scatters.
-- .server.luau => splitter routes to ServerScriptService.Features.Pickups.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local MazeNav = require(ReplicatedStorage.Features.Maze.MazeNav)
local Constants = require(ReplicatedStorage.Features.Pickups.Constants)
local Scatter = require(ReplicatedStorage.Features.Pickups.Scatter)

local PickupsService = {}
PickupsService.Priority = 12

local function playerFromPart(part: BasePart): Player?
	local model = part:FindFirstAncestorWhichIsA("Model")
	if not model then
		return nil
	end
	return Players:GetPlayerFromCharacter(model)
end

local function grant(player: Player, kind: string, amount: number?)
	-- A registered spawn (Scatter.luau in some other feature) brings its own
	-- grant. Checked FIRST so a feature can own a kind outright without this
	-- function ever learning what it is.
	local registered = Scatter.byKind(kind)
	if registered then
		registered.grant(player, amount)
		return
	end

	if kind == "Gun" then
		player:SetAttribute("HasGun", true)
		player:SetAttribute("Ammo", (player:GetAttribute("Ammo") or 0) + Constants.GUN_START_AMMO)
	elseif kind == "Ammo" then
		player:SetAttribute("Ammo", (player:GetAttribute("Ammo") or 0) + (amount or 0))
	elseif kind == "Stamina" then
		player:SetAttribute("StaminaBonus", (player:GetAttribute("StaminaBonus") or 0) + (amount or 0))
	elseif kind == "HealthKit" then
		local max = player:GetAttribute("MaxHealth") or 100
		player:SetAttribute("Health", math.min(max, (player:GetAttribute("Health") or 0) + (amount or 0)))
	end
end

-- One-shot pickup toast. Health/Ammo change constantly (drain, firing), so we
-- can't drive the "PICKED UP" flash off those attributes — the client reacts to
-- this dedicated signal instead. The nonce forces a change even on the same kind
-- twice in a row.
local toastNonce = 0
local function toast(player: Player, kind: string)
	toastNonce += 1
	player:SetAttribute("PickupToast", string.format("%s|%d", kind, toastNonce))
end

-- The art template named `modelName` under ServerStorage.PickupModels, if the
-- user placed one; nil otherwise (caller falls back to a neon ball). Accepts a
-- Model, a Tool, or a single BasePart (Union / MeshPart / Part) — whatever shape
-- the art happens to be.
local function pickupTemplate(modelName: string?): Instance?
	if not modelName then
		return nil
	end
	local folder = ServerStorage:FindFirstChild(Constants.MODELS_FOLDER)
	local template = folder and folder:FindFirstChild(modelName)
	if template and (template:IsA("Model") or template:IsA("Tool") or template:IsA("BasePart")) then
		return template
	end
	return nil
end

-- A grab fires from any BasePart of the pickup, so a multi-part model can't
-- double-grant: the `grabbed` flag closes the window before the Destroy lands.
local function attachTouch(pickup: Instance, kind: string)
	local grabbed = false
	local function onTouch(hit: BasePart)
		if grabbed or not pickup.Parent then
			return
		end
		local player = playerFromPart(hit)
		if not player then
			return
		end
		grabbed = true
		grant(player, kind, pickup:GetAttribute("PickupAmount") :: number?)
		toast(player, kind)
		pickup:Destroy() -- consumed; one grab
	end
	if pickup:IsA("BasePart") then
		pickup.Touched:Connect(onTouch)
	end
	for _, d in pickup:GetDescendants() do
		if d:IsA("BasePart") then
			d.Touched:Connect(onTouch)
		end
	end
end

local function buildPickup(
	kind: string,
	modelName: string?,
	color: Color3,
	amount: number?,
	position: Vector3,
	scaleTo: number?
): Instance
	local template = pickupTemplate(modelName)
	local pickup: Instance

	if template then
		-- Always end up with a plain Model container, whatever shape the art is: a
		-- Model is used directly, a bare BasePart is nested, and a Tool is
		-- unwrapped. Uniform container => uniform spin (Model:PivotTo) and one
		-- touch/attribute host.
		--
		-- THE TOOL CASE IS LOAD-BEARING, not tidiness.
		--
		-- `Tool` inherits from `Model` in Roblox, so `clone:IsA("Model")` is TRUE
		-- for one. The nesting branch never ran, the pickup went into the world
		-- still a Tool, and Roblox auto-equips a Tool the moment a character
		-- touches its Handle — a Handle this code has just ANCHORED. The player
		-- was welded to an immovable part and dropped when the touch handler
		-- destroyed it a beat later. Reported twice as "I picked it up and fell".
		--
		-- Nesting a Tool inside a Model does not fix it: the auto-equip fires for
		-- any Workspace descendant, not only a direct child of it. The only
		-- reliable fix is for no Tool to exist, so the children are moved into a
		-- Model and the Tool itself is thrown away.
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

		-- Strip scripts. A free-model Tool can ship with its own
		-- server Scripts that would otherwise run the moment it enters the world —
		-- the same free-model hazard as the spider's Animate script. A pickup is
		-- pure decoration; it needs none of them.
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

		-- Anchor everything so the whole thing stays rigid in place regardless of
		-- the art's welds, never blocks a player, and (nested, not a direct child
		-- of workspace) it can never be picked up as a Tool — the unwrap above is
		-- what guarantees that, not this nesting.
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = true
				d.Massless = true
			end
		end
		-- Rescale imported art to the size the registering feature asked for.
		-- Applied BEFORE the pivot, so the move lands the finished size where it
		-- belongs rather than moving it and then growing it off the cell.
		if scaleTo then
			local extents = model:GetExtentsSize()
			-- Longest of ALL THREE axes, not just the horizontal pair. A board
			-- lying flat is longest horizontally either way, but an upright
			-- object is not: the stamina cell is 0.2 wide and 0.4 tall, so
			-- sizing off its width would have stretched it to twice the target
			-- height to make its width match.
			local longest = math.max(extents.X, extents.Y, extents.Z)
			if longest > 0.01 then
				if not model.PrimaryPart then
					model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
				end
		-- `ScaleTo` is ABSOLUTE, not a multiplier. It sets the scale against the
		-- size the model was AUTHORED at, so it has to be composed with the scale
		-- the model already carries — `GetScale()` on this board is 2.67, and
		-- `ScaleTo(target / longest)` therefore shrank it to 1.5 studs instead of
		-- the 4 it was asked for. `GetScale() * ratio` is the relative form.
				model:ScaleTo(model:GetScale() * (scaleTo / longest))
			end
		end

		model:PivotTo(CFrame.new(position))
		-- Occluded outline so it's findable in the fog without recoloring the
		-- mesh or glowing through walls.
		local hl = Instance.new("Highlight")
		hl.FillTransparency = 1
		hl.OutlineColor = color
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = model
		pickup = model
	else
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.new(2, 2, 2)
		ball.Material = Enum.Material.Neon
		ball.Color = color
		ball.Anchored = true
		ball.CanCollide = false
		ball.CanTouch = true
		ball.CFrame = CFrame.new(position)
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 16
		light.Brightness = 2
		light.Parent = ball
		pickup = ball
	end

	pickup.Name = "Pickup" .. kind
	pickup:SetAttribute("PickupKind", kind)
	if amount then
		pickup:SetAttribute("PickupAmount", amount)
	end
	attachTouch(pickup, kind)
	return pickup
end

function PickupsService.Start()
	if not workspace:GetAttribute("MazeReady") then
		workspace:GetAttributeChangedSignal("MazeReady"):Wait()
	end

	local folder = Instance.new("Folder")
	folder.Name = Constants.FOLDER
	folder.Parent = workspace

	local rng = Random.new()

	local function scatter()
		folder:ClearAllChildren()

		local cellKeys: { number } = {}
		for key in MazeNav.cellPos do
			if MazeNav.bandOf(key) > 0 then
				table.insert(cellKeys, key)
			end
		end
		-- Fisher-Yates: every play scatters differently, even on the same seed.
		for i = #cellKeys, 2, -1 do
			local j = rng:NextInteger(1, i)
			cellKeys[i], cellKeys[j] = cellKeys[j], cellKeys[i]
		end

		local spawnLocationInstance = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
		local spawnPos = if spawnLocationInstance then (spawnLocationInstance :: SpawnLocation).Position else nil

		-- `available` shrinks as cells are claimed, so no two pickups (of any
		-- kind) share a cell. A kind with placement constraints
		-- (minBand/maxBand/minSpawnDist) filters this pool down first; an
		-- unconstrained kind just takes off the front, preserving shuffle order
		-- (unchanged behaviour from before constraints existed).
		local available = cellKeys

		-- Pickups' own kinds first (unchanged order, so their placement is
		-- exactly what it was), then whatever other features registered.
		local allSpawns: { Scatter.Spawn } = {}
		for _, spawn in Constants.SPAWNS :: any do
			table.insert(allSpawns, spawn)
		end
		for _, spawn in Scatter.list() do
			table.insert(allSpawns, spawn)
		end

		for _, spawn in allSpawns do
			local pool = available
			if spawn.minBand or spawn.maxBand or spawn.minSpawnDist then
				local filtered: { number } = {}
				for _, key in available do
					local band = MazeNav.bandOf(key)
					if spawn.minBand and band < spawn.minBand then
						continue
					end
					if spawn.maxBand and band > spawn.maxBand then
						continue
					end
					if spawn.minSpawnDist and spawnPos then
						local cellCenter = MazeNav.cellPos[key]
						local dist = Vector2.new(cellCenter.X - spawnPos.X, cellCenter.Z - spawnPos.Z).Magnitude
						if dist < spawn.minSpawnDist then
							continue
						end
					end
					table.insert(filtered, key)
				end
				-- Never fail to place: fall back to the unconstrained pool if the
				-- constraint leaves no candidate cells.
				if #filtered > 0 then
					pool = filtered
				end
			end

			for _ = 1, spawn.count do
				if #pool == 0 then
					break
				end
				local key = table.remove(pool, 1) :: number
				if pool ~= available then
					-- Claimed from a filtered subset: also drop it from `available`
					-- so a later, unconstrained kind can't double-claim the cell.
					for i, k in available do
						if k == key then
							table.remove(available, i)
							break
						end
					end
				end
				local cellCenter = MazeNav.cellPos[key]
				local position = cellCenter + Vector3.new(0, Constants.FLOAT_Y, 0)
				local pickup =
					buildPickup(spawn.kind, spawn.model, spawn.color, spawn.amount, position, spawn.scaleTo)
				pickup.Parent = folder
			end
		end
	end

	scatter()
	workspace:GetAttributeChangedSignal("MazeGeneration"):Connect(scatter)

	-- Everything you were carrying dies with you, kit included.
	--
	-- Pickup-granted kit used to survive a catch (only round end cleared it),
	-- which made what you lost depend on where it came from: the same gun was
	-- kept if you found it and stripped if you rented it. Worse, the two write
	-- the SAME attributes, so a rented item's clear() took found kit with it —
	-- rent one 30-cash ammo box and a catch wiped your whole stock, while a
	-- player who rented nothing kept all of it. Spending cash made your losses
	-- bigger, which is backwards.
	--
	-- One rule for everything removes the asymmetry, and it makes a catch cost
	-- something inside the run rather than only at round end. This feature grants
	-- these attributes, so this feature clears them; StoreService does the same
	-- for what it rented, off the same signal. Both nil-ing the same attribute is
	-- harmless.
	local function clearCarriedKit(player: Player)
		player:SetAttribute("HasGun", nil)
		player:SetAttribute("Ammo", nil)
		player:SetAttribute("StaminaBonus", nil)
		-- Registered spawns name their own attributes; the rule that everything
		-- carried dies with you is Pickups', the list of what that means for a
		-- given kind is the granting feature's.
		for _, spawn in Scatter.list() do
			for _, attribute in spawn.clearOnCatch or {} do
				player:SetAttribute(attribute, nil)
			end
		end
	end

	local function bindCatch(player: Player)
		player:GetAttributeChangedSignal("Caught"):Connect(function()
			-- Caught flips back to false 1.4s later, at the checkpoint teleport.
			if player:GetAttribute("Caught") ~= true then
				return
			end
			clearCarriedKit(player)
		end)
	end

	Players.PlayerAdded:Connect(bindCatch)
	for _, player in Players:GetPlayers() do
		bindCatch(player)
	end
end

return PickupsService
