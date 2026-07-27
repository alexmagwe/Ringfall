--!strict
-- Player health: a per-run resource that only goes DOWN (hunter contact drains
-- it) and is topped up by MedKit pickups — no passive regeneration. This feature
-- owns just the `Health` / `MaxHealth` player attributes and refills them for a
-- fresh life. The actual draining lives in HunterService (it owns contact
-- detection); the MedKit heal lives in PickupsService; "death" at 0 HP is the
-- existing hunter catch → checkpoint sequence. Everyone talks through the
-- attributes, so this feature imports none of them.
--
-- Auto-loaded (name ends in `Service`).
-- .server.luau => splitter routes to ServerScriptService.Features.Health.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Features.Health.Constants)

local HealthService = {}
-- Before HunterService (15) so a spawning player already has Health set when a
-- hunter first reaches them.
HealthService.Priority = 8

local function fill(player: Player)
	player:SetAttribute("MaxHealth", Constants.MAX_HEALTH)
	player:SetAttribute("Health", Constants.MAX_HEALTH)
end

function HealthService.Start()
	local function bind(player: Player)
		fill(player)
		player.CharacterAdded:Connect(function()
			fill(player)
		end)
	end
	Players.PlayerAdded:Connect(bind)
	for _, player in Players:GetPlayers() do
		bind(player)
	end
end

return HealthService
