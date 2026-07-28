--!strict
-- Salvage: other runners' lost kit — spilled packs, a dead runner's rig, a
-- cracked-open case — scattered fresh every round, worth more the deeper it
-- spawns. Touching a piece raises the toucher's `Haul`, a per-run attribute
-- the round banks at extraction (EscapeService) and the Hunter spills on
-- death (HunterService, via dropHaul below). Nothing here carries between
-- rounds — see docs/game/Salvage.md.
--
-- Auto-loaded (name ends in `Service`). Priority after MazeService (5), so
-- MazeNav is populated by the time this scatters.
-- .server.luau => splitter routes to ServerScriptService.Features.Salvage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MazeNav = require(ReplicatedStorage.Features.Maze.MazeNav)
local Constants = require(ReplicatedStorage.Features.Salvage.Constants)

local SalvageService = {}
SalvageService.Priority = 12

local function playerFromPart(part: BasePart): Player?
	local model = part:FindFirstAncestorWhichIsA("Model")
	if not model then
		return nil
	end
	return Players:GetPlayerFromCharacter(model)
end

-- Exposed for other features (HunterService's drop path, the round-end bank)
-- so nobody else has to poke the `Haul` attribute directly.
function SalvageService.addHaul(player: Player, amount: number)
	player:SetAttribute("Haul", (player:GetAttribute("Haul") or 0) + amount)
end

-- The player currently carrying the vault, or nil if it's dropped/not taken.
local function findCarrier(): Player?
	for _, plr in Players:GetPlayers() do
		if plr:GetAttribute("HasVault") then
			return plr
		end
	end
	return nil
end

-- Where the vault currently is: the carrier's character if someone holds it,
-- otherwise the dropped vault object (see SalvageService.dropVault), or nil
-- if neither exists (shouldn't happen while VaultTaken is true, but a dead
-- carrier's character not yet respawned is a real transient case).
local function currentVaultPosition(): Vector3?
	local carrier = findCarrier()
	local character = carrier and carrier.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		return hrp.Position
	end
	local dropsFolder = workspace:FindFirstChild(Constants.DROPS_FOLDER)
	local dropped = dropsFolder and dropsFolder:FindFirstChild("DroppedVault")
	if dropped and dropped:IsA("BasePart") then
		return dropped.Position
	end
	return nil
end

-- Every ALARM_REFRESH seconds while the vault is out, refresh the summon
-- alarm (HunterService's existing gunshot-summon consumer, unlocked
-- maze-wide by AlarmActive) at wherever the vault currently is, and publish
-- VaultPos for the compass. Keeps refreshing through a drop (nobody holding
-- it) using the dropped object's own position, so the alert never goes stale
-- mid-recovery — see docs/game/Salvage.md.
local function startAlarmLoop()
	task.spawn(function()
		while true do
			if workspace:GetAttribute("VaultTaken") then
				local pos = currentVaultPosition()
				if pos then
					workspace:SetAttribute("HunterAlert", os.clock())
					workspace:SetAttribute("HunterAlertPos", pos)
					workspace:SetAttribute("VaultPos", pos)
				end
			end
			task.wait(Constants.ALARM_REFRESH)
		end
	end)
end

-- Binds Vault.Touched. Called once at Start and again on every
-- MazeGeneration, because the Vault lives in workspace.Maze and
-- `mazeFolder:ClearAllChildren()` destroys it every rebuild.
local function bindVault()
	local mazeFolder = workspace:WaitForChild("Maze")
	local vault = mazeFolder:WaitForChild("Vault") :: BasePart

	vault.Touched:Connect(function(hit: BasePart)
		if workspace:GetAttribute("VaultTaken") then
			return
		end
		local player = playerFromPart(hit)
		if not player then
			return
		end
		workspace:SetAttribute("VaultTaken", true)
		player:SetAttribute("HasVault", true)
		workspace:SetAttribute("AlarmActive", true)
		-- Reads as emptied: dark and inert. No more Touched behaviour on this
		-- part until the next rebuild rebinds a fresh one.
		vault.Material = Enum.Material.Slate
		vault.Color = Color3.fromRGB(20, 20, 22)
	end)
end

-- A recoverable haul pile at a death position (HunterService.catchPlayer).
-- Touch -> addHaul -> destroy. Does not decay — the pressure is the maze
-- being hot, not a timer. Lives in workspace.Drops, a within-round folder
-- EscapeService clears at round end (nothing carries between rounds).
function SalvageService.dropHaul(position: Vector3, value: number)
	if value <= 0 then
		return
	end
	local dropsFolder = workspace:FindFirstChild(Constants.DROPS_FOLDER)
	if not dropsFolder then
		return
	end

	local pile = Instance.new("Part")
	pile.Name = "HaulDrop"
	pile.Size = Vector3.new(2, 2, 2)
	pile.Material = Enum.Material.Neon
	pile.Color = Color3.fromRGB(255, 200, 90)
	pile.Anchored = true
	pile.CanCollide = false
	pile.CanTouch = true
	pile.CFrame = CFrame.new(position + Vector3.new(0, 1, 0))
	pile:SetAttribute("SalvageValue", value)

	local light = Instance.new("PointLight")
	light.Color = pile.Color
	light.Range = 14
	light.Brightness = 2
	light.Parent = pile

	pile.Parent = dropsFolder

	local grabbed = false
	pile.Touched:Connect(function(hit: BasePart)
		if grabbed or not pile.Parent then
			return
		end
		local player = playerFromPart(hit)
		if not player then
			return
		end
		grabbed = true
		SalvageService.addHaul(player, value)
		pile:Destroy()
	end)
end

-- The vault, dropped as its own separate object at a death position
-- (HunterService.catchPlayer) — a distinct thing from a haul pile, and both
-- can land in the same spot. Touch -> the toucher becomes the new carrier
-- (HasVault = true) and the alarm re-points at them next tick (the alarm
-- loop above scans for whoever currently holds HasVault). Anyone can take
-- it, including the player who lost it.
function SalvageService.dropVault(position: Vector3)
	local dropsFolder = workspace:FindFirstChild(Constants.DROPS_FOLDER)
	if not dropsFolder then
		return
	end

	local vault = Instance.new("Part")
	vault.Name = "DroppedVault"
	vault.Size = Vector3.new(3, 3, 3)
	vault.Material = Enum.Material.Metal
	vault.Color = Color3.fromRGB(20, 20, 22)
	vault.Anchored = true
	vault.CanCollide = false
	vault.CanTouch = true
	vault.CFrame = CFrame.new(position + Vector3.new(0, 1.5, 0))

	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(255, 195, 60)
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = vault

	vault.Parent = dropsFolder

	local grabbed = false
	vault.Touched:Connect(function(hit: BasePart)
		if grabbed or not vault.Parent then
			return
		end
		local player = playerFromPart(hit)
		if not player then
			return
		end
		grabbed = true
		player:SetAttribute("HasVault", true)
		vault:Destroy()
	end)
end

function SalvageService.Start()
	if not workspace:GetAttribute("MazeReady") then
		workspace:GetAttributeChangedSignal("MazeReady"):Wait()
	end

	local folder = Instance.new("Folder")
	folder.Name = Constants.FOLDER
	folder.Parent = workspace

	-- Owned by this feature but never cleared on rebuild (only at round end,
	-- by EscapeService) — a within-round mechanic, not a per-generation one.
	local drops = Instance.new("Folder")
	drops.Name = Constants.DROPS_FOLDER
	drops.Parent = workspace

	local function attachTouch(piece: BasePart, value: number)
		local grabbed = false
		piece.Touched:Connect(function(hit: BasePart)
			if grabbed or not piece.Parent then
				return
			end
			local player = playerFromPart(hit)
			if not player then
				return
			end
			grabbed = true
			SalvageService.addHaul(player, value)
			piece:Destroy()
		end)
	end

	local function buildPiece(position: Vector3, value: number, color: Color3)
		local piece = Instance.new("Part")
		piece.Name = "Salvage"
		piece.Size = Vector3.new(1.5, 1.5, 1.5)
		piece.Material = Enum.Material.Neon
		piece.Color = color
		piece.Anchored = true
		piece.CanCollide = false
		piece.CanTouch = true
		piece.CFrame = CFrame.new(position)
		piece:SetAttribute("SalvageValue", value)

		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 12
		light.Brightness = 1.5
		light.Parent = piece

		piece.Parent = folder
		attachTouch(piece, value)
	end

	-- Unseeded on purpose: placement differs every play, even on the same
	-- maze seed (see Pickups' scatter for the same idiom).
	local rng = Random.new()

	local function scatter()
		folder:ClearAllChildren()

		-- Bucket every cell (excluding band 0 — the hub belongs to the Vault)
		-- by district, then shuffle each bucket independently.
		local byDistrict: { [number]: { number } } = { [1] = {}, [2] = {}, [3] = {} }
		for key in MazeNav.cellPos do
			if MazeNav.bandOf(key) == 0 then
				continue
			end
			local district = MazeNav.districtOf(MazeNav.bandOf(key))
			local bucket = byDistrict[district]
			if bucket then
				table.insert(bucket, key)
			end
		end

		for district, bucket in byDistrict do
			for i = #bucket, 2, -1 do
				local j = rng:NextInteger(1, i)
				bucket[i], bucket[j] = bucket[j], bucket[i]
			end

			local spec = Constants.PER_DISTRICT[district]
			for i = 1, math.min(spec.count, #bucket) do
				local key = bucket[i]
				local position = MazeNav.cellPos[key] + Vector3.new(0, Constants.FLOAT_Y, 0)
				buildPiece(position, spec.value, spec.color)
			end
		end
	end

	-- Both the immediate call and the listener: the first MazeGeneration bump
	-- fires before any listener can connect (same pattern as
	-- Hunter/Checkpoint/Escape/Pickups).
	scatter()
	workspace:GetAttributeChangedSignal("MazeGeneration"):Connect(scatter)

	-- Same both-immediate-and-listener pattern for the Vault, which also
	-- lives inside the Maze folder and is destroyed every rebuild.
	bindVault()
	workspace:GetAttributeChangedSignal("MazeGeneration"):Connect(bindVault)

	startAlarmLoop()
end

return SalvageService
