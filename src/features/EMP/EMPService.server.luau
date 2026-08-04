--!strict
-- The EMP: a shelf-bought burst that switches hunters off instead of killing
-- them.
--
-- It exists because the Sidearm answers the wrong question. A gun handles "this
-- one is in my way" — one hunter, permanently, at the price of every hunter in
-- earshot hearing the shot. It has no answer at all for "three of these have me
-- in a dead end", because sixteen hits on a Warden is not a plan. The EMP is
-- that answer, and it deliberately kills nothing: what you buy is a window to
-- leave through, not a cleared route.
--
-- SERVER-AUTHORITATIVE. The client sends a direction and nothing else; the
-- origin, the range, the charge count and the cooldown are all decided here. A
-- client that could assert a burst could disable a district for free.
--
-- Auto-loaded (name ends in `Service`).
-- .server.luau => splitter routes to ServerScriptService.Features.EMP.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- The Hunter feature owns "hunters can be switched off"; this file owns the
-- reason. Neither names the other's content — same seam as `HunterAlert`.
local Stun = require(ReplicatedStorage.Features.Hunter.Stun)
local Constants = require(ReplicatedStorage.Features.EMP.Constants)
local Net = require(ReplicatedStorage.Features.EMP.Net)

local EMPService = {}
EMPService.Priority = 14

-- Where the burst goes off: along the player's aim, stopping at the first thing
-- it hits, capped at RANGE. Aiming at your own feet is a legal and deliberate
-- move — it is the panic button.
local function burstPoint(character: Model, root: BasePart, direction: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local origin = root.Position + Vector3.new(0, 2, 0)
	local hit = workspace:Raycast(origin, direction * Constants.RANGE, params)
	return if hit then hit.Position else origin + direction * Constants.RANGE
end

-- An expanding ring at the burst point. Purely so the area the pulse covered is
-- something the player SAW, rather than something they infer from which hunters
-- happened to stop.
local function showBurst(position: Vector3)
	local ring = Instance.new("Part")
	ring.Name = "EmpBurst"
	ring.Shape = Enum.PartType.Ball
	ring.Size = Vector3.new(3, 3, 3)
	ring.Color = Constants.COLOR
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.35
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.CFrame = CFrame.new(position)
	ring.Parent = workspace

	local light = Instance.new("PointLight")
	light.Color = Constants.COLOR
	light.Brightness = 6
	light.Range = Constants.RADIUS
	light.Parent = ring

	local d = Constants.RADIUS * 2
	TweenService
		:Create(ring, TweenInfo.new(Constants.RING_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(d, d, d),
			Transparency = 1,
		})
		:Play()
	TweenService:Create(light, TweenInfo.new(Constants.RING_SECONDS), { Brightness = 0 }):Play()
	Debris:AddItem(ring, Constants.RING_SECONDS + 0.2)

	if Constants.FIRE_SOUND_ID == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = Constants.FIRE_SOUND_ID
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = Constants.FIRE_SOUND_RANGE
	sound.Parent = ring
	sound:Play()
end

-- One-shot report, same "value|nonce" shape as PickupToast: the nonce is what
-- lets two identical results in a row both register. Firing into an empty
-- corridor has to say so, or a wasted charge is indistinguishable from a bug.
local resultNonce = 0
local function report(player: Player, message: string)
	resultNonce += 1
	player:SetAttribute("EmpResult", `{message}|{resultNonce}`)
end

function EMPService.Start()
	local lastFire: { [Player]: number } = {}

	Net.Fire.listen(function(payload: { direction: Vector3 }, player: Player)
		local charges = player:GetAttribute(Constants.CHARGES_ATTRIBUTE)
		if typeof(charges) ~= "number" or charges < 1 then
			return
		end
		if player:GetAttribute("Caught") == true or player:GetAttribute("Escaped") == true then
			return
		end

		local last = lastFire[player]
		if last and os.clock() - last < Constants.COOLDOWN then
			return
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not root then
			return
		end

		-- The client's vector is the ONLY thing taken from it, and it is
		-- sanitised: a zero or non-finite direction would send the raycast
		-- nowhere useful, and a non-unit one would scale the range.
		local direction = payload.direction
		if direction.Magnitude < 0.001 or direction.Magnitude ~= direction.Magnitude then
			return
		end

		lastFire[player] = os.clock()
		player:SetAttribute(Constants.CHARGES_ATTRIBUTE, charges - 1)

		local point = burstPoint(character, root, direction.Unit)
		showBurst(point)

		-- The one line this whole feature exists to call.
		local hit = Stun.pulse(point, Constants.RADIUS, Constants.SECONDS)
		report(player, if hit > 0 then `{hit} DISABLED` else "NOTHING IN RANGE")
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastFire[player] = nil
	end)
end

return EMPService
