--!strict
-- Gun input + HUD: cursor reticle and ammo counter, only shown while the local
-- player has HasGun. Fires a Shoot request on click — the server is the sole
-- authority on ammo, range, cooldown and whether a hunter was actually hit.
-- Local cooldown here is feel only.
--
-- Auto-loaded: name ends in `Controller`.
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Gun.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Features.Gun.Net)

local LOCAL_FIRE_COOLDOWN = 0.2 -- feel only; server enforces the real cooldown
local AIM_RANGE = 300 -- keep in step with GunService.GUN_RANGE
-- Must match GunService.HEAD_OFFSET: the direction we send is measured from the
-- point the SERVER fires from, not from the camera.
local HEAD_OFFSET = Vector3.new(0, 2, 0)

local RETICLE_IDLE = Color3.fromRGB(255, 255, 255)
local RETICLE_TARGET = Color3.fromRGB(255, 70, 60)
local RETICLE_IDLE_SIZE = 26
local RETICLE_TARGET_SIZE = 18 -- tightens on a target: the shot is committed

local GunController = {}

function GunController.Start()
	local player = Players.LocalPlayer
	local camera = Workspace.CurrentCamera

	-- The gun is the only Tool in the game and it isn't inventory: the server
	-- equips it off `HasGun` and puts it straight back if anything unequips it,
	-- and it can't be dropped or swapped. The Roblox hotbar it makes appear is
	-- therefore a slot you cannot act on, sitting under the ammo readout that
	-- actually carries the information. Hidden here rather than in a shared UI
	-- file — no other feature spawns a Tool, so no other feature owns this.
	-- pcall: SetCoreGuiEnabled throws if the CoreGui isn't up yet, and losing
	-- the whole controller (crosshair, aiming, input) over a cosmetic call
	-- would be a bad trade.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	local gui = Instance.new("ScreenGui")
	gui.Name = "GunHud"
	gui.ResetOnSpawn = false
	-- Deliberately NOT IgnoreGuiInset (the other HUDs are). The reticle has to
	-- land on the exact pixel the aim ray is cast through, and both
	-- `GetMouseLocation` and `ViewportPointToRay` work in a space that excludes
	-- the topbar inset — ignoring it would draw the reticle half an inset above
	-- where the gun actually aims.
	gui.IgnoreGuiInset = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- The reticle follows the MOUSE, not the centre of the screen.
	--
	-- Roblox's default third-person camera leaves the cursor free: moving the
	-- mouse moves a pointer, it doesn't turn the camera. A crosshair pinned to
	-- screen centre therefore points wherever the camera happens to face and
	-- nothing the player does with the mouse moves it — there was no way to
	-- pick a target at all. Drawing on the cursor makes the pointer the aiming
	-- device, which is what the player is already trying to use it as.
	--
	-- A ring rather than a dot, and the system cursor stays visible underneath:
	-- the staging-room shelf is used while armed, and hiding the pointer to
	-- draw our own would break clicking on the shop.
	local reticle = Instance.new("Frame")
	reticle.Size = UDim2.fromOffset(26, 26)
	reticle.AnchorPoint = Vector2.new(0.5, 0.5)
	reticle.BackgroundTransparency = 1
	reticle.BorderSizePixel = 0
	reticle.Visible = false
	reticle.Parent = gui
	local reticleCorner = Instance.new("UICorner")
	reticleCorner.CornerRadius = UDim.new(1, 0)
	reticleCorner.Parent = reticle
	local reticleStroke = Instance.new("UIStroke")
	reticleStroke.Thickness = 2
	reticleStroke.Color = RETICLE_IDLE
	reticleStroke.Transparency = 0.15
	reticleStroke.Parent = reticle

	local ammoLabel = Instance.new("TextLabel")
	ammoLabel.Size = UDim2.fromOffset(160, 36)
	ammoLabel.Position = UDim2.new(1, -20, 1, -20)
	ammoLabel.AnchorPoint = Vector2.new(1, 1)
	ammoLabel.BackgroundTransparency = 1
	ammoLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	ammoLabel.TextSize = 26
	ammoLabel.Font = Enum.Font.GothamBold
	ammoLabel.TextXAlignment = Enum.TextXAlignment.Right
	ammoLabel.Text = "AMMO 0"
	ammoLabel.Visible = false
	ammoLabel.Parent = gui
	local ammoStroke = Instance.new("UIStroke")
	ammoStroke.Thickness = 2
	ammoStroke.Color = Color3.fromRGB(0, 0, 0)
	ammoStroke.Parent = ammoLabel

	local function updateAmmoLabel()
		local ammo = player:GetAttribute("Ammo")
		ammoLabel.Text = `AMMO {if typeof(ammo) == "number" then ammo else 0}`
	end

	player:GetAttributeChangedSignal("Ammo"):Connect(updateAmmoLabel)
	updateAmmoLabel()

	-- Named-model check, matching how GunService judges a hit: the Gun feature
	-- never requires HunterService, it only knows a Model called "Hunter". This
	-- is the cosmetic half of that same contract — the server still decides
	-- whether a shot connects.
	local function isHunter(instance: Instance?): boolean
		if not instance then
			return false
		end
		local model = instance:FindFirstAncestorWhichIsA("Model")
		return model ~= nil and model.Name == "Hunter"
	end

	-- Resolves the cursor into the direction the shot has to travel, plus what it
	-- is currently over (so the reticle can report it). One ray, shared by the
	-- per-frame reticle update and the fire request — they must agree, or the
	-- reticle would promise a hit the shot doesn't take.
	--
	-- The direction is measured from the point the SERVER fires from — the
	-- character's head — to the point under the cursor, NOT along the camera's
	-- look vector. In third person the camera sits several studs behind and above
	-- the character, so a ray cast from the head along the camera's direction is
	-- offset by that whole displacement: near-parallel lines that only converge
	-- at infinity, missing by most of the camera offset at exactly the ranges a
	-- fight happens at. Aiming at a POINT converges both rays at every distance.
	local function resolveAim(): (Vector3?, Instance?)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not root then
			return nil, nil
		end

		local cursor = UserInputService:GetMouseLocation()
		local cursorRay = camera:ViewportPointToRay(cursor.X, cursor.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character } -- includes the held gun

		local hit = workspace:Raycast(cursorRay.Origin, cursorRay.Direction * AIM_RANGE, params)
		-- Nothing under the cursor (open sky / past range): aim at the far end of
		-- the same ray, so the shot still goes where you're pointing.
		local aimPoint = if hit then hit.Position else cursorRay.Origin + cursorRay.Direction * AIM_RANGE

		local delta = aimPoint - (root.Position + HEAD_OFFSET)
		if delta.Magnitude < 0.001 then
			return nil, nil
		end
		return delta.Unit, if hit then hit.Instance else nil
	end

	-- Reticle: rides the cursor, and turns red and tightens over a hunter. That
	-- feedback is the targeting, really — the maze is dark and a hunter at range
	-- is a silhouette, so "am I actually pointed at it?" is a question the player
	-- cannot answer from the render alone.
	RunService.RenderStepped:Connect(function()
		local hasGun = player:GetAttribute("HasGun") == true
		reticle.Visible = hasGun
		ammoLabel.Visible = hasGun
		if not hasGun then
			return
		end

		local cursor = UserInputService:GetMouseLocation()
		reticle.Position = UDim2.fromOffset(cursor.X, cursor.Y)

		local _, hitInstance = resolveAim()
		local onTarget = isHunter(hitInstance)
		reticleStroke.Color = if onTarget then RETICLE_TARGET else RETICLE_IDLE
		local size = if onTarget then RETICLE_TARGET_SIZE else RETICLE_IDLE_SIZE
		reticle.Size = UDim2.fromOffset(size, size)
	end)

	local lastLocalShot = 0
	UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
		if gameProcessedEvent then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if not player:GetAttribute("HasGun") then
			return
		end
		local ammo = player:GetAttribute("Ammo")
		if typeof(ammo) ~= "number" or ammo <= 0 then
			return
		end
		local now = os.clock()
		if now - lastLocalShot < LOCAL_FIRE_COOLDOWN then
			return
		end

		local direction = resolveAim()
		if not direction then
			return -- no character yet; don't burn the cooldown on a shot that can't fire
		end
		lastLocalShot = now

		Net.Shoot.send({
			origin = camera.CFrame.Position,
			direction = direction,
		})
	end)
end

return GunController
