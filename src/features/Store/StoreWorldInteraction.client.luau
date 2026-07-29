--!strict
-- World presentation for the Store (seam #4): the staging-room terminal.
-- Binds every part tagged `StoreTerminal` — triggering its ProximityPrompt
-- opens the shelf window, and walking away closes it again.
--
-- It calls the same core intent the window calls (StoreController.setOpen), so
-- the two presentations are peers; neither knows about the other. Binding by
-- CollectionService tag rather than by path means a terminal rebuilt with the
-- maze re-binds itself with no rebuild hook here.
--
-- No Studio assets needed: StoreService builds and tags the terminal.
--
-- .client.luau => splitter routes to StarterPlayerScripts.Features.Store.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Features.Store.Constants)

-- Client-realm sibling controller (StarterPlayerScripts.Features.Store.…).
local StoreController = require(script.Parent.StoreController)

if not Constants.Presentations.world then
	return {}
end

local activeTerminal: BasePart? = nil
local watchConnection: RBXScriptConnection? = nil

local function stopWatching()
	if watchConnection then
		watchConnection:Disconnect()
		watchConnection = nil
	end
end

-- While the window is open, close it as soon as the player leaves the terminal.
-- A centred window blocks the view, so leaving it pinned open while you sprint
-- into the maze is worse than making you re-trigger the prompt.
local function startWatching()
	stopWatching()
	watchConnection = RunService.Heartbeat:Connect(function()
		local terminal = activeTerminal
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if terminal == nil or terminal.Parent == nil or root == nil then
			StoreController.setOpen(false)
			return
		end
		if (root.Position - terminal.Position).Magnitude > Constants.CLOSE_RANGE then
			StoreController.setOpen(false)
		end
	end)
end

StoreController.OpenChanged:Connect(function(open: boolean)
	if open then
		startWatching()
		return
	end
	stopWatching()
end)

local function bind(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local prompt = instance:FindFirstChildWhichIsA("ProximityPrompt")
	if prompt == nil then
		warn(`[Store] {instance:GetFullName()} is tagged {Constants.WORLD_TAG} but has no ProximityPrompt`)
		return
	end
	prompt.Triggered:Connect(function(player)
		if player ~= Players.LocalPlayer then
			return
		end
		activeTerminal = instance
		StoreController.setOpen(true)
	end)
end

for _, instance in CollectionService:GetTagged(Constants.WORLD_TAG) do
	bind(instance)
end
CollectionService:GetInstanceAddedSignal(Constants.WORLD_TAG):Connect(bind)

return {}
