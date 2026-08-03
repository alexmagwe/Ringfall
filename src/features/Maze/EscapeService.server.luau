--!strict
-- Round state machine: staging countdown -> door opens -> descend -> vault ->
-- extract -> maze rebuild -> staging, repeating with no manual button press.
-- Free-for-all: there is no per-player win anymore. Extraction only ends the
-- round for whoever is carrying the vault (`HasVault`); everyone banks their
-- Haul when that happens. See docs/game/Escape.md.
--
-- Depends on MazeService having already positioned SpawnLocation and built
-- the Staging room (Door, ExtractPad) + the Vault. Loader.SpawnAll's Priority
-- field only orders the *call* order of each module's Start(), not
-- completion order (task.spawn hands control back to the scheduling loop at
-- the first yield) — so instead of assuming MazeService finished first, this
-- waits on the workspace.MazeReady attribute MazeService sets at the very
-- end of its Start().

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Net = require(ReplicatedStorage.Features.Maze.Net)
local MazeService = require(ServerScriptService.Features.Maze.MazeService)
-- Cross-feature server require, same shape as HunterService -> SalvageService.
-- Banking is the one moment a per-run number becomes permanent, and it has to
-- happen here because this is the only place that knows the round just ended.
local PlayerDataService = require(ServerScriptService.Features.PlayerData.PlayerDataService)

local EscapeService = {}

-- After MazeService (5); the maze must exist before round state can track it.
EscapeService.Priority = 10

local ZONE_RADIUS = 25
local ROUND_COUNTDOWN = 15 -- seconds in Staging before the door opens
-- Longest the world will hold on the summary board waiting for a player who is
-- never going to press CONTINUE. Generous, because reading the board is the
-- point; bounded, because one idle player must not be able to freeze a server.
local SUMMARY_TIMEOUT = 60
-- The door SLIDES INTO THE FLOOR to open. Toggling CanCollide alone is not
-- enough: the part stays fully opaque and in place, so the door never appears to
-- open and players just phase through what still looks like a solid wall.
local DOOR_SLIDE_TIME = 1.4
-- Extra drop past the door's own height. Sliding down by exactly Size.Y leaves
-- the door's top face at y=0 — coplanar with the staging floor's top face — and
-- two coplanar surfaces z-fight, which reads in game as a shimmering coloured
-- line across the floor where the door went down. The staging floor is 2 studs
-- thick (spans y=-2..0), so 4 clears it entirely.
local DOOR_SLIDE_CLEARANCE = 4

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

-- Called on first spawn and every respawn/death: a new life starts fresh.
-- `Escaped` is a legacy per-player signal (Hunter/Checkpoint still read it
-- defensively) — nothing sets it true anymore, since extraction is now
-- server-wide rather than a personal win.
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

-- Profile key holding the permanent side of the economy (Cash, BestHaul,
-- Unlocked). Registered by src/features/Maze/PlayerData.luau.
local PROFILE_KEY = "Ringfall"

-- Converts a player's per-run Haul into permanent Cash and returns the amount
-- banked (which is also what the round-end board reports). Cash is the only
-- thing that crosses a round boundary — the Haul attribute itself is wiped a
-- few lines later by resetRunAttributes, along with the rest of the run.
local function bankHaul(player: Player): number
	local haul = player:GetAttribute("Haul")
	local amount = if typeof(haul) == "number" then haul else 0
	if amount <= 0 then
		return 0
	end

	local data = PlayerDataService.GetData(player)
	local slice = if data then data[PROFILE_KEY] else nil
	if slice == nil then
		-- Profile still loading, or the player is mid-leave. Report the haul on
		-- the board but don't persist it; a missing profile is not an error
		-- worth failing the whole round over.
		return amount
	end

	PlayerDataService.SetValue(player, { PROFILE_KEY, "Cash" }, (slice.Cash or 0) + amount)
	if amount > (slice.BestHaul or 0) then
		PlayerDataService.SetValue(player, { PROFILE_KEY, "BestHaul" }, amount)
	end
	return amount
end

function EscapeService.Start()
	if not workspace:GetAttribute("MazeReady") then
		workspace:GetAttributeChangedSignal("MazeReady"):Wait()
	end

	-- spawnLocation stays captured: MazeService repositions the *same* instance
	-- rather than recreating it on rebuild, so its CFrame reads live and stays
	-- correct. The Staging folder's contents (Door, ExtractPad) and the Maze
	-- folder's EscapeZone are destroyed by ClearAllChildren and need re-fetching.
	local spawnLocation = workspace:WaitForChild("SpawnLocation") :: SpawnLocation

	local zonePart: BasePart? = nil
	local doorPart: BasePart? = nil
	-- Captured in bindToMaze: the door is rebuilt every round, so its shut
	-- position has to be re-read rather than remembered across rebuilds.
	local doorShutCFrame: CFrame? = nil

	-- Drops into the floor (local -Y is world down: the door is built with
	-- CFrame.fromMatrix(..., Vector3.yAxis), so its local Y is world up).
	local function setDoorOpen(open: boolean)
		local door, shut = doorPart, doorShutCFrame
		if not door or not shut then
			return
		end
		if not open then
			door.CFrame = shut
			door.CanCollide = true
			return
		end
		door.CanCollide = false
		TweenService
			:Create(
				door,
				TweenInfo.new(DOOR_SLIDE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ CFrame = shut * CFrame.new(0, -(door.Size.Y + DOOR_SLIDE_CLEARANCE), 0) }
			)
			:Play()
	end
	local extractConnection: RBXScriptConnection? = nil
	local extracting = false -- debounce: closes the instant a valid extraction lands

	local function resetRunAttributes(player: Player)
		player:SetAttribute("Checkpoint", nil)
		player:SetAttribute("CheckpointRing", nil)
		player:SetAttribute("SafeUntil", nil)
		player:SetAttribute("HasGun", nil)
		player:SetAttribute("Ammo", nil)
		player:SetAttribute("HasFlashlight", nil)
		player:SetAttribute("StaminaBonus", nil)
		player:SetAttribute("MedCharges", nil)
		player:SetAttribute("Haul", nil)
		player:SetAttribute("HasVault", nil)
		-- Fresh round = full bar (a teleport doesn't fire HealthService's
		-- CharacterAdded refill).
		player:SetAttribute("Health", player:GetAttribute("MaxHealth") or 100)
	end

	local function teleportToStaging(player: Player)
		local character = player.Character
		if not character then
			return
		end
		setCharacterAnchored(character, false)
		character:PivotTo(spawnLocation.CFrame + Vector3.new(0, 3, 0))
	end

	-- Staging: door blocked, a 15s countdown broadcasts every second. Active:
	-- door opens, no timer (see the plan's "no global run countdown" rule —
	-- the vault alarm is the only timer, and only a player taking the vault
	-- starts it). Defined before endRound (which calls it to loop back) so
	-- there's no forward reference to a not-yet-assigned local.
	-- Forward-declared: endRound calls it (to re-bind to the freshly rebuilt
	-- geometry) but it is defined further down, next to the other maze-binding
	-- code. Without this the call inside endRound would resolve as a nil global.
	local bindToMaze: () -> ()

	local function runStaging()
		workspace:SetAttribute("RoundState", "Staging")
		setDoorOpen(false)
		task.spawn(function()
			for remaining = ROUND_COUNTDOWN, 0, -1 do
				Net.RoundState.sendToAll({ state = "Staging", secondsRemaining = remaining })
				task.wait(1)
			end
			workspace:SetAttribute("RoundState", "Active")
			setDoorOpen(true)
			Net.RoundState.sendToAll({ state = "Active", secondsRemaining = 0 })
		end)
	end

	-- Holds the world at the end of a run while everyone reads the summary
	-- board, and returns once they have all pressed CONTINUE — or once patience
	-- runs out.
	--
	-- THE TIMEOUT IS NOT OPTIONAL. Without it a single player who alt-tabs,
	-- disconnects mid-teardown, or simply walks away freezes every other player
	-- in the server indefinitely, with no way for them to do anything about it.
	-- Waiting for a real answer is worth a minute; it is not worth a hostage.
	--
	-- Players who join DURING the hold are not waited on: they have no round to
	-- read about, and adding them to the set would restart the wait every time
	-- someone connected.
	-- Who has pressed CONTINUE on the board currently up. Subscribed ONCE, here,
	-- rather than per round: ByteNet's `listen` has no unsubscribe, so a
	-- listener registered inside the wait would leak one subscription every
	-- round for the life of the server.
	local continued: { [Player]: boolean } = {}
	Net.Continue.listen(function(_payload, player: Player)
		continued[player] = true
	end)

	local function waitForContinue()
		table.clear(continued)
		-- The roster is snapshotted, so someone joining mid-board is not waited
		-- on — they have no round to read about, and adding them would restart
		-- the wait every time anyone connected.
		local roster = Players:GetPlayers()
		local deadline = os.clock() + SUMMARY_TIMEOUT

		while os.clock() < deadline do
			local pending = false
			for _, plr in roster do
				-- A player who left is not coming back to press it.
				if plr.Parent == Players and not continued[plr] then
					pending = true
					break
				end
			end
			if not pending then
				return
			end
			task.wait(0.2)
		end
	end

	local function endRound(winner: Player)
		-- A state of its own, not "Staging". The board is up, the maze still
		-- stands, and nothing has been rebuilt yet — treating that as Staging
		-- would tell every client to clear the very board it just put up, which
		-- is exactly the bug this replaces: the results flashed for one frame
		-- and the round restarted underneath them.
		workspace:SetAttribute("RoundState", "Summary")

		-- Bank every player's haul into permanent Cash — everyone banks, not
		-- just the carrier who extracted. The packet is the report of what was
		-- just made permanent.
		local hauls = {}
		for _, plr in Players:GetPlayers() do
			table.insert(hauls, { name = plr.Name, haul = bankHaul(plr) })
		end
		Net.RoundEnded.sendToAll({ winnerName = winner.Name, hauls = hauls })

		-- Freeze everyone where they stand while the board is up. Two separate
		-- things have to stop, because they fail differently:
		--
		--   * `Escaped` takes players out of HunterService's targeting and out
		--     of CheckpointService's tracking. Without it a hunter carries on
		--     hunting through the summary and can catch someone who is reading a
		--     scoreboard with no way to react.
		--   * Anchoring stops them wandering off. The teleport at the end of the
		--     hold puts everyone in the staging room anyway, but an unanchored
		--     player can walk into a hunter, off a stair, or through the extract
		--     pad again in the meantime.
		--
		-- `resetState` clears `Escaped` at the end of the hold, and
		-- `teleportToStaging` unanchors — so both are undone on the way out
		-- without a second pass here.
		for _, plr in Players:GetPlayers() do
			plr:SetAttribute("Escaped", true)
			local character = plr.Character
			if character then
				setCharacterAnchored(character, true)
			end
		end

		waitForContinue()

		-- Nothing carries between rounds: unrecovered drops die with the round
		-- (workspace.Salvage re-scatters itself on the MazeGeneration this
		-- rebuild is about to fire).
		local drops = workspace:FindFirstChild("Drops")
		if drops then
			drops:ClearAllChildren()
		end

		MazeService.rebuild(Random.new(os.clock() * 1000):NextInteger(1, 2 ^ 31 - 1))

		-- Re-bind SYNCHRONOUSLY rather than waiting on the MazeGeneration
		-- listener below. Roblox signals are deferred, so that listener has not
		-- run yet at this point — everything after this line (teleporting to the
		-- new SpawnLocation, shutting the new Door) would otherwise be acting on
		-- the previous round's destroyed instances. bindToMaze is idempotent, so
		-- the deferred call landing again a moment later is harmless.
		bindToMaze()

		for _, plr in Players:GetPlayers() do
			resetState(plr)
			resetRunAttributes(plr)
			teleportToStaging(plr)
		end

		runStaging()
		extracting = false
	end

	local function onExtractTouched(hit: BasePart)
		if extracting then
			return
		end
		local player = playerFromPart(hit)
		if not player then
			return
		end
		if not player:GetAttribute("HasVault") then
			return -- everyone else touching the pad does nothing
		end
		extracting = true
		endRound(player)
	end

	-- Ends the round right now, as if `winner` had carried the vault onto the
	-- pad. Exists so the summary board can be tested without playing a whole run
	-- — descending three districts, finding the vault and carrying it back out
	-- is several minutes to reach a screen that takes seconds to check.
	--
	-- Server-side and deliberately NOT a packet: nothing a client sends can
	-- reach this. Call it from the Studio command bar, or from a Cmdr command if
	-- one is ever added:
	--
	--   require(game.ServerScriptService.Features.Maze.EscapeService).forceEndRound()
	--
	-- Takes the same `extracting` debounce as a real extraction, so calling it
	-- twice — or during a teardown already in progress — is a no-op rather than
	-- two overlapping rebuilds. Returns whether it actually started one.
	function EscapeService.forceEndRound(winner: Player?): boolean
		if extracting then
			return false
		end
		local target = winner or Players:GetPlayers()[1]
		if not target then
			return false -- an empty server has no one to credit or to show a board to
		end
		extracting = true
		endRound(target)
		return true
	end

	-- (Re)binds to the current maze geometry. Called once at Start and again
	-- after every rebuild, because ClearAllChildren destroys the Staging
	-- folder's Door/ExtractPad (and the Maze folder's EscapeZone) every time.
	function bindToMaze()
		local mazeFolder = workspace:WaitForChild("Maze")
		local stagingFolder = workspace:WaitForChild("Staging")
		local extractPad = stagingFolder:WaitForChild("ExtractPad") :: BasePart
		doorPart = stagingFolder:WaitForChild("Door") :: BasePart
		-- Re-read the shut position: MazeService rebuilds the Staging folder
		-- every round, so this is a brand new part each time.
		doorShutCFrame = (doorPart :: BasePart).CFrame

		if extractConnection then
			extractConnection:Disconnect()
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

		extractConnection = extractPad.Touched:Connect(onExtractTouched)
	end

	local function onCharacterAdded(player: Player, character: Model)
		resetState(player)
		-- A late joiner mid-round waits out the Active phase frozen in the
		-- staging room rather than dropping into a live maze — the next
		-- round's teleport-everyone step (endRound) unanchors them same as
		-- everyone else.
		-- Frozen during a live round AND while the summary board is up: a player
		-- who dies and respawns mid-board would otherwise be the one person free
		-- to wander a maze that is about to be destroyed under them.
		local roundState = workspace:GetAttribute("RoundState")
		setCharacterAnchored(character, roundState == "Active" or roundState == "Summary")
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

	-- Timer start: first time a player's character leaves the staging room.
	-- Cosmetic only now — it's a stat, not the score. See docs/game/Escape.md.
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

	runStaging()
end

return EscapeService
