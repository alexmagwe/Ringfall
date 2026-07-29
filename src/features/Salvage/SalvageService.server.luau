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
local ServerStorage = game:GetService("ServerStorage")

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

------------------------------------------------------------------------------
-- Building salvage objects (art if the user placed any, neon block if not)
------------------------------------------------------------------------------

-- How one kind of salvage object looks. `model` names an optional child under
-- ServerStorage.SalvageModels; everything else describes the fallback block and
-- the glow that survives either way.
type Look = {
	name: string,
	model: string?,
	color: Color3,
	size: number,
	-- Fallback block only; a real model keeps its own materials. Default Neon.
	material: Enum.Material?,
	-- PointLight tint/range. nil = no light.
	lightColor: Color3?,
	lightRange: number?,
	-- Occluded outline colour. nil = no Highlight. Used sparingly: Roblox
	-- degrades past roughly 31 Highlights on screen, and a round can have 24
	-- salvage pieces out at once, so pieces use light and the vault uses this.
	outlineColor: Color3?,
}

-- Does this instance actually have geometry to render? The check is "is or
-- contains a BasePart" rather than a class whitelist, because Studio art
-- arrives in more shapes than a whitelist ever anticipates — a Model, a bare
-- MeshPart, a Tool, and (the case that caught us) an **Accessory**, which a
-- Model/Tool/BasePart check silently rejected so the piece fell back to a white
-- block with no warning. Anything holding a BasePart can be anchored, lit and
-- touched, which is all this feature needs.
local function hasGeometry(instance: Instance): boolean
	if instance:IsA("BasePart") then
		return true
	end
	return instance:FindFirstChildWhichIsA("BasePart", true) ~= nil
end

-- The art template named `modelName` under ServerStorage.SalvageModels, if the
-- user placed one; nil otherwise (caller falls back to a neon block). Warns
-- rather than failing silently when a name is configured but unusable — a
-- missing model looks exactly like a working one that fell back, and that
-- ambiguity costs more debugging time than the warning costs to read.
local function salvageTemplate(modelName: string?): Instance?
	if not modelName then
		return nil
	end
	local folder = ServerStorage:FindFirstChild(Constants.MODELS_FOLDER)
	if folder == nil then
		return nil -- no art placed at all; the fallback is the expected path
	end
	local template = folder:FindFirstChild(modelName)
	if template == nil then
		warn(`[Salvage] no "{modelName}" under ServerStorage.{Constants.MODELS_FOLDER}; using the fallback block`)
		return nil
	end
	if not hasGeometry(template) then
		warn(`[Salvage] "{modelName}" has no BasePart to render; using the fallback block`)
		return nil
	end
	return template
end

local function addGlow(object: Instance, host: BasePart?, look: Look)
	if look.lightColor and host then
		local light = Instance.new("PointLight")
		light.Color = look.lightColor
		light.Range = look.lightRange or 12
		light.Brightness = 1.5
		light.Parent = host
	end
	if look.outlineColor then
		local highlight = Instance.new("Highlight")
		highlight.FillTransparency = 1
		highlight.OutlineColor = look.outlineColor
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = object
	end
end

-- Builds one salvage object at `position` and parents it to `parent`: the
-- user's model if they placed one, else the coloured block this feature shipped
-- with. Either way it comes out anchored, non-colliding, touchable and glowing
-- in its tier colour — swapping neon boxes for realistic props in an unlit maze
-- makes them invisible, and losing the colour costs the player the "is this
-- worth the detour?" read at distance.
local function buildObject(look: Look, position: Vector3, parent: Instance): Instance
	local template = salvageTemplate(look.model)

	if template == nil then
		local piece = Instance.new("Part")
		piece.Name = look.name
		piece.Size = Vector3.new(look.size, look.size, look.size)
		piece.Material = look.material or Enum.Material.Neon
		piece.Color = look.color
		piece.Anchored = true
		piece.CanCollide = false
		piece.CanTouch = true
		piece.CFrame = CFrame.new(position)
		addGlow(piece, piece, look)
		piece.Parent = parent
		return piece
	end

	-- Always end up with a Model container, whatever shape the art is: a Model
	-- clone is used directly; a Tool or bare BasePart is nested in a fresh one.
	-- Uniform container => uniform pivot, one attribute host, one grab.
	local clone = template:Clone()
	local model: Model
	if clone:IsA("Model") then
		model = clone
	else
		model = Instance.new("Model")
		clone.Parent = model
	end
	model.Name = look.name

	-- Strip scripts. A free-model Tool can ship its own server Scripts that
	-- would run the moment it enters the world — the same free-model hazard
	-- PickupsService guards against. Salvage is pure decoration.
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end

	-- Anchored so it hangs where it's placed regardless of the art's welds,
	-- non-colliding so it never blocks a corridor, and nested in a Model (not a
	-- direct child of workspace) so a Tool can't auto-equip on touch.
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = true
			d.Massless = true
		end
	end

	model:PivotTo(CFrame.new(position))
	addGlow(model, model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true), look)
	model.Parent = parent
	return model
end

-- One grab fires from ANY BasePart of the object, so a multi-part model can't
-- double-grant: the shared `grabbed` flag closes the window before the caller's
-- Destroy lands. Without it a player brushing a model with several limbs in the
-- same frame would be paid once per limb.
local function attachGrab(object: Instance, onGrab: (Player) -> ())
	local grabbed = false
	local function onTouch(hit: BasePart)
		if grabbed or not object.Parent then
			return
		end
		local player = playerFromPart(hit)
		if not player then
			return
		end
		grabbed = true
		onGrab(player)
	end

	if object:IsA("BasePart") then
		object.Touched:Connect(onTouch)
	end
	for _, d in object:GetDescendants() do
		if d:IsA("BasePart") then
			d.Touched:Connect(onTouch)
		end
	end
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
	-- Either shape: a bare fallback block, or a Model once the user drops real
	-- art into ServerStorage.SalvageModels.
	if dropped and dropped:IsA("BasePart") then
		return dropped.Position
	end
	if dropped and dropped:IsA("Model") then
		return dropped:GetPivot().Position
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

	-- No `model`: a spill is deliberately the code-built block, so it never
	-- shares a silhouette with scattered salvage (see Constants.DROP_COLOR).
	local pile = buildObject({
		name = "HaulDrop",
		color = Constants.DROP_COLOR,
		size = Constants.DROP_SIZE,
		lightColor = Constants.DROP_COLOR,
		lightRange = Constants.DROP_LIGHT_RANGE,
	}, position + Vector3.new(0, 1, 0), dropsFolder)
	pile:SetAttribute("SalvageValue", value)

	attachGrab(pile, function(player: Player)
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

	-- No `model` either: the vault must never be mistaken for loot.
	local vault = buildObject({
		name = "DroppedVault",
		color = Constants.VAULT_DROP_COLOR,
		size = Constants.VAULT_DROP_SIZE,
		material = Enum.Material.Metal,
		outlineColor = Constants.VAULT_DROP_OUTLINE,
	}, position + Vector3.new(0, 1.5, 0), dropsFolder)

	attachGrab(vault, function(player: Player)
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

	local function buildPiece(position: Vector3, spec: { value: number, model: string?, color: Color3 })
		local piece = buildObject({
			name = "Salvage",
			model = spec.model,
			color = spec.color,
			size = Constants.PIECE_SIZE,
			lightColor = spec.color,
			lightRange = Constants.PIECE_LIGHT_RANGE,
		}, position, folder)
		piece:SetAttribute("SalvageValue", spec.value)

		attachGrab(piece, function(player: Player)
			SalvageService.addHaul(player, spec.value)
			piece:Destroy()
		end)
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
				buildPiece(position, spec)
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
