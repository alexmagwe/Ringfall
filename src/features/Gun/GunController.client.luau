--!strict
-- Gun input + HUD: crosshair and ammo counter, only shown while the local
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
	-- Deliberately NOT IgnoreGuiInset (the other HUDs are). The crosshair has to
	-- land on the exact pixel `ViewportPointToRay` reads from, and that ray's
	-- coordinate space excludes the topbar inset — ignoring the inset would put
	-- the dot half an inset above where the gun actually aims.
	gui.IgnoreGuiInset = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local crosshair = Instance.new("Frame")
	crosshair.Size = UDim2.fromOffset(6, 6)
	crosshair.Position = UDim2.fromScale(0.5, 0.5)
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	crosshair.BackgroundTransparency = 0.2
	crosshair.BorderSizePixel = 0
	crosshair.Visible = false
	crosshair.Parent = gui
	local crosshairCorner = Instance.new("UICorner")
	crosshairCorner.CornerRadius = UDim.new(1, 0)
	crosshairCorner.Parent = crosshair

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

	RunService.Heartbeat:Connect(function()
		local hasGun = player:GetAttribute("HasGun") == true
		crosshair.Visible = hasGun
		ammoLabel.Visible = hasGun
	end)

	-- The direction the shot actually has to travel: from the point the server
	-- fires from (the character's head) to whatever the crosshair is covering.
	--
	-- Sending `camera.CFrame.LookVector` instead — what this used to do — aims
	-- from the wrong place. In third person the camera sits several studs behind
	-- and above the character, so a ray cast from the head along the camera's
	-- direction is that whole offset off target: near-parallel lines that only
	-- converge at infinity. Anything close enough to matter was missed by roughly
	-- the camera offset, which is why shooting felt broken rather than merely
	-- hard. Aiming at the POINT the camera sees converges both rays on the same
	-- spot at every distance.
	local function aimDirection(): Vector3?
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not root then
			return nil
		end

		local viewport = camera.ViewportSize
		local centreRay = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character } -- includes the held gun

		local hit = workspace:Raycast(centreRay.Origin, centreRay.Direction * AIM_RANGE, params)
		-- Nothing under the crosshair (open sky / past range): aim at the far end
		-- of the same ray, so the shot still goes where you're looking.
		local aimPoint = if hit then hit.Position else centreRay.Origin + centreRay.Direction * AIM_RANGE

		local delta = aimPoint - (root.Position + HEAD_OFFSET)
		if delta.Magnitude < 0.001 then
			return nil
		end
		return delta.Unit
	end

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

		local direction = aimDirection()
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
