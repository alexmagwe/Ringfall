--!strict
-- Makes the Vault move. A prize that sits perfectly still reads as scenery, and
-- the hub is the one place in the maze a player has walked several minutes to
-- reach — it has to look like it was worth the trip.
--
-- Client-side, like PickupsController's spin: the server built the Vault
-- anchored and never touches its CFrame again, so rotating it locally costs no
-- replication and no server work. The tradeoff is that `Touched` still fires
-- against the server's CFrame, not this visual one — fine here, because the
-- motion is a spin about the object's own axis plus a small bob, so the touch
-- volume never meaningfully leaves where it was drawn.
--
-- Rebinds on MazeGeneration: the Vault lives in workspace.Maze, which
-- MazeService ClearAllChildren's on every rebuild.
--
-- Auto-loaded: name ends in `Controller`.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Salvage.

local RunService = game:GetService("RunService")

local VaultController = {}

local SPIN_DPS = 14 -- slow: a heavy object turning, not a coin flipping
local BOB_AMPLITUDE = 0.45 -- studs
local BOB_PERIOD = 3.4 -- seconds for a full rise-and-fall

function VaultController.Start()
	-- Captured on each bind so the bob oscillates around wherever the server
	-- actually placed it, rather than around a hardcoded height.
	local vault: Model? = nil
	local restPivot: CFrame? = nil
	local elapsed = 0

	local function bind()
		vault = nil
		restPivot = nil
		local mazeFolder = workspace:FindFirstChild("Maze")
		local found = mazeFolder and mazeFolder:WaitForChild("Vault", 10)
		if found == nil or not found:IsA("Model") then
			return
		end
		vault = found
		restPivot = found:GetPivot()
		elapsed = 0
	end

	task.spawn(bind)
	workspace:GetAttributeChangedSignal("MazeGeneration"):Connect(function()
		task.spawn(bind)
	end)

	RunService.Heartbeat:Connect(function(dt)
		local model, rest = vault, restPivot
		if model == nil or rest == nil then
			return
		end
		-- A destroyed-but-not-yet-rebound Vault (the window between
		-- ClearAllChildren and the MazeGeneration listener firing) would throw
		-- on PivotTo.
		if model.Parent == nil then
			vault = nil
			return
		end

		elapsed += dt
		local bob = math.sin(elapsed * (math.pi * 2) / BOB_PERIOD) * BOB_AMPLITUDE
		-- Rotate about the rest pivot, then lift: composing the other way round
		-- would swing the object through an arc instead of bobbing in place.
		model:PivotTo(
			(rest + Vector3.new(0, bob, 0)) * CFrame.Angles(0, math.rad(SPIN_DPS) * elapsed, 0)
		)
	end)
end

return VaultController
