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

local Net = require(ReplicatedStorage.Features.Maze.Net)

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

	local spawnLocation = workspace:WaitForChild("SpawnLocation") :: SpawnLocation
	local mazeFolder = workspace:WaitForChild("Maze")
	local exitGate = mazeFolder:WaitForChild("ExitGate") :: BasePart

	local zonePart = Instance.new("Part")
	zonePart.Name = "EscapeZone"
	zonePart.Shape = Enum.PartType.Ball
	zonePart.Size = Vector3.new(ZONE_RADIUS * 2, ZONE_RADIUS * 2, ZONE_RADIUS * 2)
	zonePart.CFrame = spawnLocation.CFrame
	zonePart.Anchored = true
	zonePart.CanCollide = false
	zonePart.CanTouch = false
	zonePart.CanQuery = false
	zonePart.Transparency = 1
	zonePart.Parent = mazeFolder

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
			local distance = (hrp.Position - zonePart.Position).Magnitude
			if distance > ZONE_RADIUS then
				playerState.startedAt = os.clock()
				Net.RunStarted.sendTo(nil, player)
			end
		end
	end)

	-- Escape: debounced per player via playerState.escaped, checked and set
	-- synchronously before any yield so re-entrant Touched firings (multiple
	-- character parts overlapping the gate in the same frame) can't double-fire.
	exitGate.Touched:Connect(function(hit)
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

		local elapsed = if playerState.startedAt then os.clock() - (playerState.startedAt :: number) else 0
		Net.Escaped.sendTo({ timeSeconds = elapsed }, player)
		setCharacterAnchored(character, true)
	end)

	-- Restart: unanchor, teleport to spawn, reset round state.
	Net.Restart.listen(function(_payload, player)
		local character = player.Character
		if not character then
			return
		end
		resetState(player)
		setCharacterAnchored(character, false)
		character:PivotTo(spawnLocation.CFrame)
	end)
end

return EscapeService
