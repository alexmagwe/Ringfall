--!strict
-- Escape round state machine: tracks each player's run timer, fires the
-- start/escape network events, and freezes/resets characters at the exit.
--
-- Depends on MazeService having already positioned SpawnLocation and built
-- ExitGate. Loader.SpawnAll's Priority field only orders the *call* order of
-- each module's Start(), not completion order (task.spawn hands control back
-- to the scheduling loop at the first yield) — so instead of assuming
-- MazeService finished first, this waits on the workspace.MazeReady
-- attribute MazeService sets at the very end of its Start().

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Net = require(ReplicatedStorage.Features.Maze.Net)
local MazeService = require(ServerScriptService.Features.Maze.MazeService)
local PlayerDataService = require(ServerScriptService.Features.PlayerData.PlayerDataService)

local EscapeService = {}

-- After MazeService (5); the maze must exist before round state can track
-- players moving through it.
EscapeService.Priority = 10

local ZONE_RADIUS = 25

type PlayerState = {
	startedAt: number?,
	escaped: boolean,
}

local state: { [Player]: PlayerState } = {}

local function getState(player: Player): PlayerState
	local existing = state[player]
	if existing then
		return existing
	end
	local fresh: PlayerState = { startedAt = nil, escaped = false }
	state[player] = fresh
	return fresh
end

-- Called on first spawn and every respawn/death: a new life starts the round
-- fresh (not yet left the zone, not escaped). The `Escaped` attribute is the
-- shared signal other features read (HunterService ignores escaped players).
local function resetState(player: Player)
	state[player] = { startedAt = nil, escaped = false }
	player:SetAttribute("Escaped", false)
end

local function playerFromPart(part: BasePart): Player?
	local model = part:FindFirstAncestorWhichIsA("Model")
	if not model then
		return nil
	end
	return Players:GetPlayerFromCharacter(model)
end

local function setCharacterAnchored(character: Model, anchored: boolean)
	local primary = character.PrimaryPart
	if primary then
		primary.Anchored = anchored
	end
end

function EscapeService.Start()
	if not workspace:GetAttribute("MazeReady") then
		workspace:GetAttributeChangedSignal("MazeReady"):Wait()
	end

	-- spawnLocation stays captured: MazeService repositions the *same* instance
	-- rather than recreating it on rebuild, so its CFrame reads live and stays
	-- correct. Only the folder, gate and zone are destroyed by ClearAllChildren
	-- and need re-fetching.
	local spawnLocation = workspace:WaitForChild("SpawnLocation") :: SpawnLocation

	local gateConnection: RBXScriptConnection? = nil
	local zonePart: BasePart? = nil

	-- Escape: debounced per player via playerState.escaped, checked and set
	-- synchronously before any yield so re-entrant Touched firings (multiple
	-- character parts overlapping the gate in the same frame) can't double-fire.
	local function onGateTouched(hit: BasePart)
		local player = playerFromPart(hit)
		if not player then
			return
		end
		local character = player.Character
		if not character then
			return
		end
		local playerState = getState(player)
		if playerState.escaped then
			return
		end
		playerState.escaped = true
		player:SetAttribute("Escaped", true) -- tells the hunter to stop chasing this player
		-- Every hunter sprints for the centre for a few seconds — converging on
		-- the pad in shot for the escape cinematic, arriving too late.
		workspace:SetAttribute("EvacAlert", os.clock())

		local elapsed = if playerState.startedAt then os.clock() - (playerState.startedAt :: number) else 0

		-- Personal best. Guard `data` being nil (profile still loading) as no
		-- best; send the packet after SetValue so the payload and the replica
		-- agree.
		local data = PlayerDataService.GetData(player)
		local previous = if data and data.Ringfall then data.Ringfall.BestTimeSeconds else 0
		local isNewBest = previous <= 0 or elapsed < previous
		if isNewBest then
			PlayerDataService.SetValue(player, { "Ringfall", "BestTimeSeconds" }, elapsed)
		end
		Net.Escaped.sendTo({
			timeSeconds = elapsed,
			bestSeconds = if isNewBest then elapsed else previous,
			isNewBest = isNewBest,
		}, player)
		setCharacterAnchored(character, true)
	end

	-- (Re)binds to the current maze geometry. Called once at Start and again
	-- after every rebuild, because ClearAllChildren destroys both the gate and
	-- the zone.
	local function bindToMaze()
		local mazeFolder = workspace:WaitForChild("Maze")
		local exitGate = mazeFolder:WaitForChild("ExitGate") :: BasePart

		if gateConnection then
			gateConnection:Disconnect()
		end
		if zonePart then
			zonePart:Destroy()
		end

		local newZonePart = Instance.new("Part")
		newZonePart.Name = "EscapeZone"
		newZonePart.Shape = Enum.PartType.Ball
		newZonePart.Size = Vector3.new(ZONE_RADIUS * 2, ZONE_RADIUS * 2, ZONE_RADIUS * 2)
		newZonePart.CFrame = spawnLocation.CFrame
		newZonePart.Anchored = true
		newZonePart.CanCollide = false
		newZonePart.CanTouch = false
		newZonePart.CanQuery = false
		newZonePart.Transparency = 1
		newZonePart.Parent = mazeFolder
		zonePart = newZonePart

		gateConnection = exitGate.Touched:Connect(onGateTouched)
	end

	local function respawnCharacter(player: Player, character: Model)
		resetState(player)
		setCharacterAnchored(character, false)
	end

	local function onCharacterAdded(player: Player, character: Model)
		respawnCharacter(player, character)
	end

	local function onPlayerAdded(player: Player)
		resetState(player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			onCharacterAdded(player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		state[player] = nil
	end)

	-- Timer start: first time a player's character leaves the spawn zone.
	RunService.Heartbeat:Connect(function()
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if not character then
				continue
			end
			local playerState = getState(player)
			if playerState.startedAt ~= nil or playerState.escaped then
				continue
			end
			local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hrp then
				continue
			end
			if not zonePart then
				continue
			end
			local distance = (hrp.Position - zonePart.Position).Magnitude
			if distance > ZONE_RADIUS then
				playerState.startedAt = os.clock()
				Net.RunStarted.sendTo(nil, player)
			end
		end
	end)

	bindToMaze()
	workspace:GetAttributeChangedSignal("MazeGeneration"):Connect(bindToMaze)

	-- Restart: a server-wide new round — new walls, new far spawn, everyone
	-- reset. Per-player mazes would need instancing and are out of scope.
	Net.Restart.listen(function(_payload, player)
		-- Only a player who actually escaped may start a new round. Restart is a
		-- client-sent packet and now rebuilds the world for EVERYONE, so without
		-- this guard any client could spam it and re-carve the maze under other
		-- players mid-run. Never trust the client to have earned the call.
		if not getState(player).escaped then
			return
		end

		MazeService.rebuild(Random.new(os.clock() * 1000):NextInteger(1, 2 ^ 31 - 1))

		for _, plr in Players:GetPlayers() do
			resetState(plr)
			-- Checkpoint stores a raw world-space CFrame; after a re-carve that
			-- exact point may be inside a new wall, and HunterService.catchPlayer
			-- teleports caught players straight to it. Must clear, not optional.
			plr:SetAttribute("Checkpoint", nil)
			plr:SetAttribute("CheckpointRing", nil)
			plr:SetAttribute("SafeUntil", nil)
			-- Per-run scavenge (Pickups feature): ephemeral, not PlayerData, wiped
			-- on RUN IT BACK same as the checkpoint state above.
			plr:SetAttribute("HasGun", nil)
			plr:SetAttribute("Ammo", nil)
			plr:SetAttribute("HasCompass", nil)
			plr:SetAttribute("HasFlashlight", nil)
			plr:SetAttribute("StaminaBonus", nil)
			-- Fresh round = full bar (RUN IT BACK only teleports, so HealthService's
			-- CharacterAdded refill doesn't fire).
			plr:SetAttribute("Health", plr:GetAttribute("MaxHealth") or 100)
			local character = plr.Character
			if not character then
				continue
			end
			setCharacterAnchored(character, false)
			character:PivotTo(spawnLocation.CFrame + Vector3.new(0, 3, 0))
		end
	end)
end

return EscapeService
