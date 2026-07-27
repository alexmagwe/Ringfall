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

local Net = require(ReplicatedStorage.Features.Gun.Net)

local GunService = {}
GunService.Priority = 12

local GUN_RANGE = 300
local FIRE_COOLDOWN = 0.2 -- seconds; server-enforced, ignores anything faster
local HEAD_OFFSET = Vector3.new(0, 2, 0) -- roughly eye height above the root
local SIREN_SOUND_ID = "" -- user supplies; siren plays on the hit hunter

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

function GunService.Start()
	Players.PlayerRemoving:Connect(function(player)
		lastShot[player] = nil
	end)

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
		if not result then
			return
		end

		local hunterHum = hunterHumanoidFromHit(result.Instance)
		if not hunterHum then
			return
		end

		hunterHum:TakeDamage(1)

		-- Summon: alert nearby hunters to the shooter's position. HunterService
		-- (Phase 2) consumes these two workspace attributes.
		workspace:SetAttribute("HunterAlert", os.clock())
		workspace:SetAttribute("HunterAlertPos", root.Position)

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
