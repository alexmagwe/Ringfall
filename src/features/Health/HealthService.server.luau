--!strict
-- Player health: a per-run resource that only goes DOWN (hunter contact drains
-- it) and is topped up by MedKit pickups or a stored medkit charge — no passive
-- regeneration. This feature owns the `Health` / `MaxHealth` / `MedCharges`
-- player attributes and refills the first two for a fresh life. The actual
-- draining lives in HunterService (it owns contact detection); the MedKit
-- *pickup* heal lives in PickupsService; charges are bought from the shelf
-- (see Store.luau) and spent through the UseMedkit packet below; "death" at 0 HP
-- is the existing hunter catch → checkpoint sequence. Everyone talks through the
-- attributes, so this feature imports none of them.
--
-- Auto-loaded (name ends in `Service`).
-- .server.luau => splitter routes to ServerScriptService.Features.Health.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Features.Health.Constants)
local Net = require(ReplicatedStorage.Features.Health.Net)

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

	-- Spend one stored charge. The client only asks; every condition is
	-- re-checked here, so a client that spams this gains nothing.
	Net.UseMedkit.listen(function(_payload, player: Player)
		local charges = player:GetAttribute("MedCharges")
		if typeof(charges) ~= "number" or charges <= 0 then
			return
		end
		local hp = player:GetAttribute("Health")
		local max = player:GetAttribute("MaxHealth")
		if typeof(hp) ~= "number" or typeof(max) ~= "number" then
			return
		end
		-- Refuse at full health rather than burning the charge for nothing.
		if hp >= max then
			return
		end

		player:SetAttribute("MedCharges", charges - 1)
		player:SetAttribute("Health", math.min(max, hp + Constants.MEDKIT_HEAL))
	end)
end

return HealthService
