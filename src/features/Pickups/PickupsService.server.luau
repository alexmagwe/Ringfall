--!strict
-- Scavenged pickups: ammo, flashlight, stamina upgrade, MedKits. (The gun is
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
	if kind == "Gun" then
		player:SetAttribute("HasGun", true)
		player:SetAttribute("Ammo", (player:GetAttribute("Ammo") or 0) + Constants.GUN_START_AMMO)
	elseif kind == "Ammo" then
		player:SetAttribute("Ammo", (player:GetAttribute("Ammo") or 0) + (amount or 0))
	elseif kind == "Flashlight" then
		player:SetAttribute("HasFlashlight", true)
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

local function buildPickup(kind: string, modelName: string?, color: Color3, amount: number?, position: Vector3): Instance
	local template = pickupTemplate(modelName)
	local pickup: Instance

	if template then
		-- Always end up with a Model container, whatever shape the art is: a Model
		-- clone is used directly; a Tool or bare BasePart is nested in a fresh one.
		-- Uniform container => uniform spin (Model:PivotTo) and one touch/attr host.
		local clone = template:Clone()
		local model: Model
		if clone:IsA("Model") then
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

		-- Anchor everything so the whole thing stays rigid in place regardless of
		-- the art's welds, never blocks a player, and (nested, not a direct child
		-- of workspace) a Tool can't auto-equip on touch.
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = true
				d.Massless = true
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

		for _, spawn in Constants.SPAWNS do
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
				local pickup = buildPickup(spawn.kind, spawn.model, spawn.color, spawn.amount, position)
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
		player:SetAttribute("HasFlashlight", nil)
		player:SetAttribute("StaminaBonus", nil)
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
