--!strict
-- Server authority for the shelf. Builds the staging-room terminal, validates
-- every purchase against the shared Registry, and owns the per-round record of
-- what each player rented.
--
-- Nothing here trusts the client: the Buy packet carries an id and a flag, and
-- this re-derives the price, the round state, whether the item is unlocked and
-- whether the player can afford it before a single value moves.
--
-- Auto-loaded (name ends in `Service`).
-- .server.luau => splitter routes to ServerScriptService.Features.Store.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Required for its side effect: loading Features.Store runs init.luau's
-- auto-discovery loop, which registers every feature's sibling `Store.luau`
-- item into the per-realm Registry. Submodule requires (Constants, Registry,
-- Packets) do NOT trigger this — they just index children of the Store
-- ModuleScript. Without this line the server's catalogue stays empty and every
-- incoming Buy is rejected.
require(ReplicatedStorage.Features.Store)

local Constants = require(ReplicatedStorage.Features.Store.Constants)
local Registry = require(ReplicatedStorage.Features.Store.Registry)
local Packets = require(ReplicatedStorage.Features.Store.Packets)
local PlayerDataService = require(ServerScriptService.Features.PlayerData.PlayerDataService)

local StoreService = {}

-- After PlayerData (1) so SetValue/GetData are ready, and after MazeService (5)
-- so workspace.Staging exists to hold the terminal.
StoreService.Priority = 12

-- Per-round record of what each player has rented. Never persisted: renting is
-- the disposable half of the economy.
local rented: { [Player]: { [string]: boolean } } = {}

------------------------------------------------------------------------------
-- Profile helpers
------------------------------------------------------------------------------

local function profileSlice(player: Player): { [string]: any }?
	local data = PlayerDataService.GetData(player)
	return if data then data[Constants.PROFILE_KEY] else nil
end

local function cashOf(player: Player): number
	local slice = profileSlice(player)
	if slice == nil then
		return 0
	end
	local cash = slice.Cash
	return if typeof(cash) == "number" then cash else 0
end

local function isUnlocked(player: Player, def: Registry.Item): boolean
	-- A zero unlock price means the item ships on the shelf; there is nothing
	-- to record in the profile for it.
	if def.unlockCost <= 0 then
		return true
	end
	local slice = profileSlice(player)
	if slice == nil then
		return false
	end
	local unlocked = slice.Unlocked
	return typeof(unlocked) == "table" and unlocked[def.id] == true
end

------------------------------------------------------------------------------
-- Rented bookkeeping
------------------------------------------------------------------------------

local function rentedSet(player: Player): { [string]: boolean }
	local existing = rented[player]
	if existing then
		return existing
	end
	local fresh = {}
	rented[player] = fresh
	return fresh
end

-- Republish the rented ids as a player attribute. Attributes replicate for
-- free, so the shelf UI can grey out a second buy without another packet.
local function publishRented(player: Player)
	local ids = {}
	for id in rentedSet(player) do
		table.insert(ids, id)
	end
	table.sort(ids)
	player:SetAttribute(Constants.RENTED_ATTRIBUTE, table.concat(ids, ","))
end

-- Strip every rented effect and forget the round's purchases. Called when the
-- player is caught (everything carried is lost, kit included) and again when a
-- new round enters Staging. Each item's clear() is idempotent, so running both
-- is harmless.
local function clearRented(player: Player)
	for id in rentedSet(player) do
		local def = Registry.getItem(id)
		if def == nil then
			continue
		end
		def.clear(player)
	end
	rented[player] = {}
	publishRented(player)
end

------------------------------------------------------------------------------
-- Purchases
------------------------------------------------------------------------------

local function reject(player: Player, id: string, reason: string)
	Packets.BuyRejected.sendTo({ id = id, reason = reason }, player)
end

local function spend(player: Player, amount: number): boolean
	local cash = cashOf(player)
	if cash < amount then
		return false
	end
	PlayerDataService.SetValue(player, { Constants.PROFILE_KEY, "Cash" }, cash - amount)
	return true
end

local function unlockItem(player: Player, def: Registry.Item)
	if def.unlockCost <= 0 then
		reject(player, def.id, "Already on the shelf")
		return
	end
	if isUnlocked(player, def) then
		reject(player, def.id, "Already unlocked")
		return
	end
	if not spend(player, def.unlockCost) then
		reject(player, def.id, "Not enough cash")
		return
	end
	-- Permanent: survives death, a lost round, and a rejoin.
	PlayerDataService.SetValue(player, { Constants.PROFILE_KEY, "Unlocked", def.id }, true)
end

local function rentItem(player: Player, def: Registry.Item)
	-- Renting something you never unlocked is the obvious client-side cheat, so
	-- it's the first thing checked.
	if not isUnlocked(player, def) then
		reject(player, def.id, "Not unlocked")
		return
	end
	local set = rentedSet(player)
	if set[def.id] and not def.repeatable then
		reject(player, def.id, "Already in your loadout")
		return
	end
	if not spend(player, def.rentCost) then
		reject(player, def.id, "Not enough cash")
		return
	end

	def.apply(player)
	set[def.id] = true
	publishRented(player)
end

------------------------------------------------------------------------------
-- The terminal
------------------------------------------------------------------------------

-- Builds (or rebuilds) the shelf terminal beside the SpawnLocation. Lives in
-- workspace.Staging, which MazeService ClearAllChildren's on every rebuild —
-- hence the MazeGeneration rebind in Start().
--
-- Positioned off the SpawnLocation's own CFrame rather than off any Maze
-- constant, so the Store stays agnostic to how the staging room is laid out.
local function buildTerminal()
	local staging = workspace:FindFirstChild("Staging")
	local spawnLocation = workspace:FindFirstChild("SpawnLocation") :: BasePart?
	if staging == nil or spawnLocation == nil then
		return
	end

	local existing = staging:FindFirstChild(Constants.TERMINAL_NAME)
	if existing then
		existing:Destroy()
	end

	local base = spawnLocation.CFrame
	local sidePos = base.Position + base.RightVector * Constants.TERMINAL_SIDE_OFFSET
	-- The staging floor's top face is y=0 (MazeService's FLOOR_Y), so half the
	-- terminal's height puts it standing on the floor rather than sunk into it.
	local pos = Vector3.new(sidePos.X, Constants.TERMINAL_SIZE.Y / 2, sidePos.Z)

	local part = Instance.new("Part")
	part.Name = Constants.TERMINAL_NAME
	part.Size = Constants.TERMINAL_SIZE
	-- Faces back toward the spawn point, so it reads as something to walk up to.
	part.CFrame = CFrame.lookAt(pos, Vector3.new(base.Position.X, pos.Y, base.Position.Z))
	part.Anchored = true
	part.CanCollide = true
	part.Material = Enum.Material.Metal
	part.Color = Constants.TERMINAL_COLOR
	part.Parent = staging

	-- Greybox screen: a thin lit face so the terminal isn't an anonymous slab.
	local screen = Instance.new("Part")
	screen.Name = "Screen"
	screen.Size = Vector3.new(Constants.TERMINAL_SIZE.X - 1, 2.4, 0.2)
	screen.CFrame = part.CFrame * CFrame.new(0, 1.2, -(Constants.TERMINAL_SIZE.Z / 2) - 0.1)
	screen.Anchored = true
	screen.CanCollide = false
	screen.Material = Enum.Material.Neon
	screen.Color = Constants.TERMINAL_SCREEN_COLOR
	screen.Parent = part

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = "Shelf"
	prompt.MaxActivationDistance = Constants.PROMPT_RANGE
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	-- Tagged rather than looked up by path: the client binds to the tag, so a
	-- rebuilt terminal re-binds itself with no rebuild hook on the client side.
	CollectionService:AddTag(part, Constants.WORLD_TAG)
end

------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------

function StoreService.Start()
	if not workspace:GetAttribute("MazeReady") then
		workspace:GetAttributeChangedSignal("MazeReady"):Wait()
	end

	-- Both: the first generation fires before any listener can connect (same
	-- pattern as Hunter/Checkpoint/Escape/Pickups/Salvage).
	buildTerminal()
	workspace:GetAttributeChangedSignal("MazeGeneration"):Connect(buildTerminal)

	-- A new round entering Staging wipes last round's loadout. EscapeService has
	-- already nil'd the per-run attributes by the time the run actually starts;
	-- this drops the matching bookkeeping so the shelf offers everything again.
	workspace:GetAttributeChangedSignal("RoundState"):Connect(function()
		if workspace:GetAttribute("RoundState") ~= "Staging" then
			return
		end
		for _, player in Players:GetPlayers() do
			clearRented(player)
		end
	end)

	local function bind(player: Player)
		rented[player] = {}
		publishRented(player)
		-- Caught means everything you were carrying is gone — haul, vault, and
		-- the kit you rented. Watching the attribute keeps this rule inside the
		-- Store instead of making HunterService know the shelf exists.
		player:GetAttributeChangedSignal("Caught"):Connect(function()
			if player:GetAttribute("Caught") ~= true then
				return
			end
			clearRented(player)
		end)
	end

	Players.PlayerAdded:Connect(bind)
	for _, player in Players:GetPlayers() do
		bind(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		rented[player] = nil
	end)

	Packets.Buy.listen(function(payload: { id: string, rent: boolean }, player: Player)
		local id = payload.id
		if typeof(id) ~= "string" or #id == 0 or #id > Constants.MAX_ITEM_ID_LENGTH then
			return
		end

		local def = Registry.getItem(id)
		if def == nil then
			warn(`[Store] {player.Name} tried to buy unregistered item "{id}"`)
			return
		end

		-- Staging only. Buying mid-run would let a cornered player conjure a gun
		-- out of nothing, which is exactly the decision the maze is supposed to
		-- have already taken away from them.
		if workspace:GetAttribute("RoundState") ~= "Staging" then
			reject(player, id, "The shelf is closed once the doors open")
			return
		end

		if payload.rent then
			rentItem(player, def)
		else
			unlockItem(player, def)
		end
	end)
end

return StoreService
