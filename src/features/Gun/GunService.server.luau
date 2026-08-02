--!strict
-- Server authority for the gun: the client Shoot packet is only a REQUEST.
-- This re-raycasts from the character (never the client-claimed origin),
-- enforces HasGun + Ammo > 0 + a per-player fire cooldown, and only then
-- applies damage. Reaches hunters generically (Model named "Hunter", walk
-- workspace) — never requires HunterService's source; damage flows only
-- through Humanoid:TakeDamage.
--
-- Auto-loaded (name ends in `Service`).
-- .server.luau => splitter routes to ServerScriptService.Features.Gun.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Net = require(ReplicatedStorage.Features.Gun.Net)

local GunService = {}
GunService.Priority = 12

local GUN_RANGE = 300
local FIRE_COOLDOWN = 0.2 -- seconds; server-enforced, ignores anything faster
local HEAD_OFFSET = Vector3.new(0, 2, 0) -- roughly eye height above the root
-- Aim assist: a raycast is a zero-width line, hunters move, and the client's
-- view of them trails the server by a frame or two. A miss gets one more pass
-- with a small swept sphere. It still returns the FIRST thing hit, so a wall
-- between you and a hunter blocks the shot exactly as a plain ray does — this
-- widens the shot, it doesn't see through anything.
local ASSIST_RADIUS = 1.5
local SIREN_SOUND_ID = "" -- user supplies; siren plays on the hit hunter
-- Fired every shot, hit or miss — a gunshot makes noise regardless, and a
-- silent trigger pull reads as an input that didn't register.
--
-- Taken from the art wherever possible: gun models ship their own fire clip
-- (the pistol in ServerStorage carries a `Sounds` folder), and their scripts
-- were what played it, so stripping those leaves a sound nothing will ever
-- trigger. Substring match, because the clip is called Fire / FireSound /
-- Handgun_Shoot / anything in that family depending on who built it.
local SHOT_SOUND_NAMES = { "fire", "shoot", "shot", "gunshot", "blast" }
local SHOT_SOUND_ID = "" -- user supplies; used ONLY when the art brought none
-- Silenced shots keep a report — you still need to know the trigger registered,
-- and a genuinely silent gun reads as a broken one. It's the summon that the
-- Silencer actually buys off; this is the audible half of the same promise.
local SILENCED_VOLUME = 0.35 -- fraction of the art's own volume

-- Optional user art: a Tool named `GunModel` under ServerStorage, with a part
-- named `Handle` (Roblox grips a Tool by that part). Missing => the code-built
-- blaster below, same fallback contract as Pickups' neon ball.
local GUN_ART_NAME = "GunModel"
local GUN_TOOL_NAME = "Blaster"
-- Loose art (a Model or a bare part, i.e. not an authored Tool) is scaled so
-- its longest axis measures this. Creator Store weapons are authored at any
-- size, and one four times too big reads as a bug rather than as a gun.
local GUN_TARGET_LENGTH = 3
-- Where the hand sits on a Tool that doesn't say. Tuned against the pistol in
-- ServerStorage by dragging the live `Grip` attribute until it sat right: 0.35
-- along the Handle's own X.
--
-- A per-model number in code is the wrong home for this — grip is a property of
-- the art, and the `Grip` attribute is where it belongs. It's here because the
-- attribute lives in the .rbxl, which this repo does not track: a fresh clone,
-- or a value tuned during a playtest and lost on stop, would otherwise put the
-- gun back in mid-air with no clue why. Any art carrying its own grip — an
-- authored non-identity `Tool.Grip`, or the attribute — ignores this entirely.
local DEFAULT_ART_GRIP = CFrame.new(0.35, 0, 0)

local lastShot: { [Player]: number } = {}

-- Finds the Humanoid on a hunter model, generically, by name only — never a
-- require of HunterService.
local function hunterHumanoidFromHit(hitInstance: Instance): Humanoid?
	local model = hitInstance:FindFirstAncestorWhichIsA("Model")
	if not model or model.Name ~= "Hunter" then
		return nil
	end
	return model:FindFirstChildOfClass("Humanoid")
end

-- ---------------------------------------------------------------------------
-- The gun you can see
--
-- `HasGun` used to be an attribute and nothing else: a crosshair appeared and
-- your hands stayed empty, so there was no way to tell an armed player from an
-- unarmed one — not for the player holding it, not for anyone watching. This
-- builds it as a real Tool and keeps it equipped for exactly as long as the
-- attribute says you have one.
--
-- A Tool rather than a hand-welded model on purpose: Roblox's grip puts it in
-- the right hand and plays the tool-hold pose, so the character actually
-- presents the weapon instead of letting it hang off a limb through an
-- animation that knows nothing about it.
-- ---------------------------------------------------------------------------

local function newPiece(parent: Instance, name: string, size: Vector3, color: Color3, material: Enum.Material): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false -- never blocks the aim raycast or anyone else's shot
	part.CanTouch = false -- and never trips a pickup's Touched
	part.Massless = true
	part.Parent = parent
	return part
end

local function buildPlaceholderGun(): Tool
	local tool = Instance.new("Tool")
	tool.Name = GUN_TOOL_NAME
	tool.CanBeDropped = false
	tool.RequiresHandle = true

	local handle = newPiece(tool, "Handle", Vector3.new(0.4, 1, 0.6), Color3.fromRGB(35, 38, 44), Enum.Material.Metal)
	local body = newPiece(tool, "Body", Vector3.new(0.5, 0.7, 2.2), Color3.fromRGB(58, 64, 72), Enum.Material.Metal)
	local muzzle = newPiece(tool, "Muzzle", Vector3.new(0.28, 0.28, 0.5), Color3.fromRGB(255, 180, 70), Enum.Material.Neon)

	-- Positioned before the constraints exist: a WeldConstraint freezes whatever
	-- offset the parts hold at the moment it's created.
	handle.CFrame = CFrame.identity
	body.CFrame = handle.CFrame * CFrame.new(0, 0.55, -0.7)
	muzzle.CFrame = body.CFrame * CFrame.new(0, 0, -1.3)

	for _, pair in { { handle, body }, { body, muzzle } } do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = pair[1]
		weld.Part1 = pair[2]
		weld.Parent = pair[1]
	end

	-- The maze is dark and the flashlight is a separate pickup; without this the
	-- gun is a silhouette you can't read as a gun.
	local glow = Instance.new("PointLight")
	glow.Color = muzzle.Color
	glow.Range = 8
	glow.Brightness = 1.5
	glow.Parent = muzzle

	return tool
end

-- Makes a cloned part safe to hold. Unanchoring is the load-bearing one: an
-- anchored Handle can't be moved by the grip Motor6D, so the character would
-- walk away leaving the gun hanging in the air where it was cloned.
local function makeHoldable(part: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false -- never blocks the aim raycast
	part.CanTouch = false -- and never trips a pickup's Touched
	part.Massless = true
end

-- Free-model art can ship its own scripts, which would run the moment the clone
-- enters the world — the same hazard PickupsService guards against. A held gun
-- is decoration plus a Handle; it needs none of them.
local function stripScripts(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
end

-- Welds every other part to the handle, preserving the offsets they hold right
-- now — a WeldConstraint freezes whatever relationship exists when it's created,
-- so this must run before anything is moved or reparented.
--
-- Applied to authored Tools too, not just loose art. Everything gets unanchored
-- on the way in (an anchored Handle can't be gripped), and a part that was
-- holding its place purely by being anchored — a marker, a shell template, a
-- detail the original scripts moved — would otherwise drop out of the gun and
-- fall through the world the instant it's held. Redundant welds on parts that
-- were already joined are harmless: same parts, same offsets.
local function weldPartsTo(handle: BasePart, parts: { BasePart })
	for _, part in parts do
		if part == handle then
			continue
		end
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = handle
	end
end

-- Flattens loose art (a Model, or a single Union/MeshPart/Part) into a Tool:
-- one part becomes the `Handle` Roblox grips by, every other part is welded to
-- it. Accepting all three shapes rather than Tools only mirrors what
-- `buildPickup` and Salvage's `buildObject` already do — art is whatever shape
-- the user happened to build or take off the Creator Store, and the feature
-- normalizes it instead of making them re-author it.
local function toolFromLooseArt(art: Instance): Tool?
	-- Scale first, while it's still a Model and ScaleTo is available: a Creator
	-- Store rifle can be authored at any size, and one four times too big reads
	-- as a bug rather than as a gun.
	local container: Model
	if art:IsA("Model") then
		container = art:Clone() :: Model
	else
		container = Instance.new("Model")
		art:Clone().Parent = container
	end

	local extents = container:GetExtentsSize()
	local longest = math.max(extents.X, extents.Y, extents.Z)
	if longest > 0.01 then
		container:ScaleTo(container:GetScale() * (GUN_TARGET_LENGTH / longest))
	end

	-- Which part goes in the hand, best evidence first. Roblox grips the Handle
	-- by that part's OWN origin, so this choice is the difference between a gun
	-- held by its grip and a gun floating in front of a fist.
	--   1. A part the author already called Handle or Grip — most gun art has
	--      one, and it names the exact spot a hand belongs.
	--   2. The model's PrimaryPart, the other explicit statement of intent.
	--   3. Failing both, the largest part: that's the frame, so at least the
	--      grip lands on the mass rather than on some tiny greeble. Only this
	--      case gets the centring fallback below — the first two are trusted.
	local parts: { BasePart } = {}
	local named: BasePart? = nil
	local biggestPart: BasePart? = nil
	local biggestVolume = 0
	for _, d in container:GetDescendants() do
		if not d:IsA("BasePart") then
			continue
		end
		table.insert(parts, d)
		local lower = string.lower(d.Name)
		if not named and (lower == "handle" or lower == "grip") then
			named = d
		end
		local volume = d.Size.X * d.Size.Y * d.Size.Z
		if volume > biggestVolume then
			biggestPart, biggestVolume = d, volume
		end
	end

	local handle = named or container.PrimaryPart or biggestPart
	if not handle then
		container:Destroy()
		return nil -- no parts at all; caller falls back to the built-in blaster
	end
	local trustedGrip = named ~= nil or container.PrimaryPart ~= nil

	local tool = Instance.new("Tool")
	tool.Name = GUN_TOOL_NAME
	tool.CanBeDropped = false
	tool.RequiresHandle = true

	for _, part in parts do
		makeHoldable(part)
	end
	weldPartsTo(handle, parts)

	-- Fell back to "largest part": that part's origin is the centre of the
	-- frame, not a place a hand goes, so the gun ends up floating off the fist.
	-- Balancing the whole model's bounding box on the hand instead is a better
	-- guess. Measured while the parts are still in the container — reparenting
	-- first would leave nothing to measure.
	--
	-- Grip is C1 of the RightGrip Motor6D, so it applies inverted:
	-- Handle.CFrame = hand.CFrame * C0 * Grip:Inverse(). Feeding it the model
	-- centre expressed in Handle-local space puts that centre at the hand.
	if not trustedGrip then
		local boxCF = container:GetBoundingBox()
		tool.Grip = CFrame.new(handle.CFrame:PointToObjectSpace(boxCF.Position))
	end

	handle.Name = "Handle"
	for _, part in parts do
		part.Parent = tool
	end
	container:Destroy()
	return tool
end

-- How the art sits in the hand. The grip aligns the Handle's own axes to the
-- hand, and free-model guns are authored pointing any which way, so this is the
-- one thing that can need tuning per model — hence a CFrame attribute named
-- `Grip` set on the art in Studio, tunable by the person looking at it rather
-- than through a code edit and a rebuild.
local function applyGrip(tool: Tool, art: Instance)
	local grip = art:GetAttribute("Grip")
	if typeof(grip) == "CFrame" then
		tool.Grip = grip :: CFrame
	end
end

-- The user's art if they placed any. `GUN_ART_NAME` is the documented name;
-- `Gun` is accepted too because that's the obvious thing to call it, and a
-- silently-ignored model looks identical to a broken feature.
local function userGun(): Tool?
	local art = ServerStorage:FindFirstChild(GUN_ART_NAME) or ServerStorage:FindFirstChild("Gun")
	if not art then
		return nil
	end

	-- An authored Tool is already the right shape — it has its own Handle and
	-- (often) a tuned Grip, so it's used as-is rather than pulled apart.
	if art:IsA("Tool") then
		local clone = art:Clone()
		clone.Name = GUN_TOOL_NAME
		clone.CanBeDropped = false
		stripScripts(clone)

		local parts: { BasePart } = {}
		for _, d in clone:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
				makeHoldable(d)
			end
		end

		-- No Handle => Roblox refuses to equip it outright. Better a Tool that
		-- equips invisibly than one that silently never appears.
		local handle = clone:FindFirstChild("Handle") :: BasePart?
		clone.RequiresHandle = handle ~= nil
		if handle then
			weldPartsTo(handle, parts)
			-- Identity means the author never set one, not that they wanted the
			-- Handle's mesh origin in the palm — which for a pistol is mid-frame
			-- and leaves the gun hanging in front of the fist.
			if clone.Grip == CFrame.identity then
				clone.Grip = DEFAULT_ART_GRIP
			end
		end

		applyGrip(clone, art) -- the attribute still wins over both
		return clone
	end

	if not (art:IsA("Model") or art:IsA("BasePart")) then
		return nil
	end

	local tool = toolFromLooseArt(art)
	if not tool then
		return nil
	end
	stripScripts(tool)
	applyGrip(tool, art)
	return tool
end

-- The gun's own fire clip, if the art shipped one.
local function shotSoundOf(tool: Tool): Sound?
	local named: Sound? = nil
	local only: Sound? = nil
	local count = 0
	for _, d in tool:GetDescendants() do
		if not d:IsA("Sound") then
			continue
		end
		count += 1
		only = d
		local lower = string.lower(d.Name)
		for _, want in SHOT_SOUND_NAMES do
			if not named and string.find(lower, want, 1, true) then
				named = d
			end
		end
	end
	if named then
		return named
	end
	-- One sound is unambiguous. Several unnamed ones are a guess, and guessing
	-- wrong means a reload or magazine-drop clip on every trigger pull, which is
	-- worse than silence.
	return if count == 1 then only else nil
end

-- Fires the clip, quieter when the Silencer is rented. The art's own volume is
-- the baseline and is remembered on the instance, so repeated silenced shots
-- scale from it instead of compounding down to nothing.
local function playShot(sound: Sound, silenced: boolean)
	local base = sound:GetAttribute("BaseVolume")
	if typeof(base) ~= "number" then
		base = sound.Volume
		sound:SetAttribute("BaseVolume", base)
	end
	sound.Volume = (base :: number) * (if silenced then SILENCED_VOLUME else 1)
	sound:Play()
end

local function heldGun(player: Player): Tool?
	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	local tool = (character and character:FindFirstChild(GUN_TOOL_NAME))
		or (backpack and backpack:FindFirstChild(GUN_TOOL_NAME))
	return tool :: Tool?
end

local function removeGun(player: Player)
	local tool = heldGun(player)
	if tool then
		tool:Destroy()
	end
end

local function giveGun(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not character or not humanoid or not backpack then
		return
	end
	if heldGun(player) then
		return -- already carrying it; a re-grant must not stack a second one
	end

	local tool = userGun() or buildPlaceholderGun()

	-- Supplied-id seam, applied only when the art brought no clip of its own, so
	-- setting it can never fight with real gun art. Parented to the Handle so it
	-- plays from the gun's position rather than everywhere at once.
	local handle = tool:FindFirstChild("Handle") :: BasePart?
	if SHOT_SOUND_ID ~= "" and handle and not shotSoundOf(tool) then
		local sound = Instance.new("Sound")
		sound.Name = "Fire"
		sound.SoundId = SHOT_SOUND_ID
		sound.Parent = handle
	end

	tool.Parent = backpack
	humanoid:EquipTool(tool)

	-- The gun is a run attribute, not inventory: number keys and the backpack
	-- slot both unequip a Tool, and a player who did that would still register
	-- as armed while holding nothing. Put it straight back. Deferred so it
	-- doesn't re-enter the equip machinery from inside its own event.
	tool.Unequipped:Connect(function()
		task.defer(function()
			if tool.Parent and player:GetAttribute("HasGun") and humanoid.Health > 0 then
				humanoid:EquipTool(tool)
			end
		end)
	end)
end

local function syncGun(player: Player)
	if player:GetAttribute("HasGun") then
		giveGun(player)
		return
	end
	removeGun(player)
end

function GunService.Start()
	Players.PlayerRemoving:Connect(function(player)
		lastShot[player] = nil
	end)

	-- Keep the held gun in step with the attribute, both ways and across
	-- respawns: a fresh character starts empty-handed, and being caught clears
	-- HasGun (PickupsService), which has to take the visible gun with it.
	local function bindGun(player: Player)
		player:GetAttributeChangedSignal("HasGun"):Connect(function()
			syncGun(player)
		end)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid", 10)
			syncGun(player)
		end)
		syncGun(player)
	end

	Players.PlayerAdded:Connect(bindGun)
	for _, player in Players:GetPlayers() do
		bindGun(player)
	end

	-- Live grip tuning. `Tool.Grip` applies immediately to an equipped tool, so
	-- re-reading the art's attribute whenever it changes turns "how far down
	-- does this gun need to move?" into dragging a number in the Properties
	-- panel mid-playtest, instead of one full restart per guess. Costs nothing
	-- when nobody is tuning: the signal simply never fires.
	local art = ServerStorage:FindFirstChild(GUN_ART_NAME) or ServerStorage:FindFirstChild("Gun")
	if art then
		art:GetAttributeChangedSignal("Grip"):Connect(function()
			for _, player in Players:GetPlayers() do
				local tool = heldGun(player)
				if tool then
					applyGrip(tool, art)
				end
			end
		end)
	end

	Net.Shoot.listen(function(payload, player)
		if not player:GetAttribute("HasGun") then
			return
		end
		local ammo = player:GetAttribute("Ammo")
		if typeof(ammo) ~= "number" or ammo <= 0 then
			return
		end

		local now = os.clock()
		local last = lastShot[player]
		if last and now - last < FIRE_COOLDOWN then
			return
		end
		lastShot[player] = now

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not root then
			return
		end

		player:SetAttribute("Ammo", ammo - 1)

		local silenced = player:GetAttribute("HasSilencer") == true

		-- Before the raycast, and unconditionally: the bang belongs to pulling
		-- the trigger, not to connecting. Played server-side so every player
		-- hears it, which matters in a game where being heard is the cost of
		-- shooting. `Play` on an already-playing sound restarts it, which is the
		-- right behaviour at a 0.2s cooldown.
		local tool = heldGun(player)
		local sound = tool and shotSoundOf(tool)
		if sound then
			playShot(sound, silenced)
		end

		-- Summon on EVERY shot, not just a landed one. The shelf has always sold
		-- the Sidearm as "hunters hear every shot" and the code only alerted on a
		-- hit, which made missing free — so the honest read of the item was
		-- "spray at range, it costs nothing unless you connect". A gunshot is
		-- loud whether or not it finds anything; that noise is the price the
		-- whole weapon is balanced around, and the Silencer is the thing you buy
		-- to stop paying it.
		if not silenced then
			workspace:SetAttribute("HunterAlert", os.clock())
			workspace:SetAttribute("HunterAlertPos", root.Position)
		end

		local direction = payload.direction
		if direction.Magnitude < 0.001 then
			return
		end
		direction = direction.Unit

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }

		local origin = root.Position + HEAD_OFFSET
		local result = workspace:Raycast(origin, direction * GUN_RANGE, params)
		local hunterHum = result and hunterHumanoidFromHit(result.Instance)

		if not hunterHum then
			local swept = workspace:Spherecast(origin, ASSIST_RADIUS, direction * GUN_RANGE, params)
			hunterHum = swept and hunterHumanoidFromHit(swept.Instance)
		end

		if not hunterHum then
			return
		end

		hunterHum:TakeDamage(1)

		if SIREN_SOUND_ID ~= "" then
			local hunterModel = hunterHum.Parent
			local hunterRoot = hunterModel and (hunterModel :: Model).PrimaryPart
			if hunterRoot then
				local siren = Instance.new("Sound")
				siren.SoundId = SIREN_SOUND_ID
				siren.Parent = hunterRoot
				siren:Play()
				siren.Ended:Connect(function()
					siren:Destroy()
				end)
			end
		end
	end)
end

return GunService
