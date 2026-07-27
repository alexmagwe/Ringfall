--!strict
-- District checkpoints. The maze is sealed into three districts (see
-- docs/game/Maze.md); as a player crosses INWARD through a gate into a deeper
-- district, that gate becomes their respawn point (the hunter drops caught
-- players here, not back at the drop-in), grants a brief safe window, and
-- pings the client. Ordinary band boundaries *within* a district do nothing —
-- getting caught costs you the whole district, not a few seconds of corridor.
-- The hub (district 0) is the final one — reaching it ends the run
-- (EscapeService's EvacPad handles that win).
--
-- State is shared via player attributes so the Hunter stays decoupled:
--   Checkpoint    (CFrame)  — where a caught player respawns (a gate's floor
--                             position, or the drop-in point before any gate)
--   SafeUntil     (number)  — os.clock() until which the hunter ignores them
--   CheckpointRing(number)  — district just entered (client toast reads this)
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

-- Floor-level stand height for a gate respawn, matching MazeService's spawn
-- convention (floor at y=0, characters dropped ~4 studs above it). The gate
-- parts themselves (pillars/lintel) sit well above floor height, so respawning
-- at a gate part's own CFrame would land the player mid-air or inside the
-- lintel — HunterService.catchPlayer already adds +3 on top of this.
local GATE_STAND_Y = 4

-- [player] -> deepest district reached this life (smaller = deeper). nil = fresh.
local deepest: { [Player]: number } = {}

-- The gate whose EntersDistrict attribute matches `district`, or nil if the
-- Gates folder isn't built yet. A gate is 3 parts (2 pillars + a lintel, see
-- MazeService.buildGate) sharing the same EntersDistrict; any one gives the
-- right X/Z, so the first match found is used.
local function gateForDistrict(district: number): BasePart?
	local gates = workspace:FindFirstChild("Gates")
	if not gates then
		return nil
	end
	for _, part in gates:GetChildren() do
		if part:IsA("BasePart") and part:GetAttribute("EntersDistrict") == district then
			return part
		end
	end
	return nil
end

-- A floor-level CFrame in the middle of the gate's OPENING, facing the centre.
-- Uses the `GateCenter` attribute MazeService publishes on every gate part, NOT
-- the part's own Position: the pillars sit on the opening's edges where the arc
-- wall resumes, so respawning at one would drop the player half inside a wall.
local function gateStandCFrame(gate: BasePart): CFrame
	local centre = gate:GetAttribute("GateCenter")
	local pos = if typeof(centre) == "Vector3" then centre :: Vector3 else gate.Position
	local standPos = Vector3.new(pos.X, GATE_STAND_Y, pos.Z)
	return CFrame.lookAt(standPos, Vector3.new(0, standPos.Y, 0))
end

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

	-- A rebuild re-carves the maze, so every player must re-baseline their
	-- deepest band against the new layout.
	workspace:GetAttributeChangedSignal("MazeGeneration"):Connect(function()
		table.clear(deepest)
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
			local district = MazeNav.districtOf(MazeNav.bandOf(cell))
			local prev = deepest[player]

			if prev == nil then
				-- First read this life: baseline is the drop-in district; respawn =
				-- here, no gate crossed yet, no checkpoint fanfare.
				deepest[player] = district
				player:SetAttribute("Checkpoint", hrp.CFrame)
			elseif district < prev then
				-- Crossed inward through a gate into a deeper district: a real
				-- checkpoint, at the gate itself (not the player's position) — being
				-- caught should throw you back to re-solve the district, not to
				-- wherever inside it you happened to get caught.
				deepest[player] = district
				local gate = gateForDistrict(district)
				if gate then
					player:SetAttribute("Checkpoint", gateStandCFrame(gate))
				end
				player:SetAttribute("SafeUntil", os.clock() + SAFE_SECONDS)
				player:SetAttribute("CheckpointRing", district)
			end
		end
	end)
end

return CheckpointService
