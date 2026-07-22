--!strict
-- Receives crouch state from clients and mirrors it to the `Crouched` player
-- attribute (the shared signal the Hunter reads). Resets on (re)spawn.
--
-- Auto-loaded (name ends in `Service`).
-- .server.luau => splitter routes to ServerScriptService.Features.Stealth.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StealthNet = require(ReplicatedStorage.Features.Stealth.StealthNet)

local StealthService = {}
StealthService.Priority = 12

function StealthService.Start()
	StealthNet.Crouch.listen(function(crouched: boolean, player: Player)
		player:SetAttribute("Crouched", crouched == true)
	end)

	local function reset(player: Player)
		player:SetAttribute("Crouched", false)
	end
	local function bind(player: Player)
		reset(player)
		player.CharacterAdded:Connect(function()
			reset(player)
		end)
	end
	Players.PlayerAdded:Connect(bind)
	for _, player in Players:GetPlayers() do
		bind(player)
	end
end

return StealthService
