--!strict
-- Ring checkpoints. As a player crosses INWARD into a deeper ring, that ring's
-- checkpoint activates: it becomes their respawn point (the hunter drops caught
-- players here, not back at the drop-in), grants a brief safe window, and pings
-- the client. The centre (band 0) is the final one — reaching it ends the run
-- (EscapeService's EvacPad handles that win).
--
-- State is shared via player attributes so the Hunter stays decoupled:
--   Checkpoint    (CFrame)  — where a caught player respawns
--   SafeUntil     (number)  — os.clock() until which the hunter ignores them
--   CheckpointRing(number)  — band just reached (client toast reads this)
--
-- Auto-loaded (name ends in `Service`). Priority after Hunter (15).
-- .server.luau => splitter routes to ServerScriptService.Features.Checkpoint.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MazeNav = require(ReplicatedStorage.Features.Maze.MazeNav)

local CheckpointService = {}
CheckpointService.Priority = 20

local SAFE_SECONDS = 3

-- [player] -> deepest band reached this life (smaller = deeper). nil = fresh.
local deepest: { [Player]: number } = {}

function CheckpointService.Start()
	if not workspace:GetAttribute("MazeReady") then
		workspace:GetAttributeChangedSignal("MazeReady"):Wait()
	end

	local function fresh(player: Player)
		deepest[player] = nil
	end

	local function bind(player: Player)
		fresh(player)
		player.CharacterAdded:Connect(function()
			fresh(player)
		end)
	end
	Players.PlayerAdded:Connect(bind)
	for _, player in Players:GetPlayers() do
		bind(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		deepest[player] = nil
	end)

	RunService.Heartbeat:Connect(function()
		if not MazeNav.ready then
			return
		end
		for _, player in Players:GetPlayers() do
			if player:GetAttribute("Escaped") then
				continue
			end
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hrp then
				continue
			end
			local cell = MazeNav.nearestCell(hrp.Position)
			if not cell then
				continue
			end
			local band = MazeNav.bandOf(cell)
			local prev = deepest[player]

			if prev == nil then
				-- First read this life: baseline is the drop-in; respawn = here,
				-- no checkpoint fanfare.
				deepest[player] = band
				player:SetAttribute("Checkpoint", hrp.CFrame)
			elseif band < prev then
				-- Crossed inward into a deeper ring: a real checkpoint.
				deepest[player] = band
				player:SetAttribute("Checkpoint", hrp.CFrame)
				player:SetAttribute("SafeUntil", os.clock() + SAFE_SECONDS)
				player:SetAttribute("CheckpointRing", band)
			end
		end
	end)
end

return CheckpointService
