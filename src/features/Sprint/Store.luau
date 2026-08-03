--!strict
-- Sprint's entry on the staging-room shelf. Picked up by the Store feature's
-- auto-discovery; Store never names Sprint.
--
-- The same `StaminaBonus` attribute the scattered Stamina pickup grants, bought
-- up front instead of found. Both add to it, so a player who buys one and finds
-- one carries both — which is the point of leaving the pickup in the maze.
--
-- WHY IT IS THE DEAREST UNLOCK ON THE SHELF (500, above the Silencer's 400),
-- and what it actually buys — which is not the same everywhere.
--
-- Hunter speed scales with depth: 18.7 at the rim, 31.9 near the hub, against a
-- 17.6 walk and a 28.6 sprint. So in the outer district a sprint outruns them
-- outright and stamina is a real escape; near the hub they are FASTER than your
-- sprint, and stamina only buys distance and time to reach a corner or a gate.
--
-- It therefore does not help you win a fight, and deep in it does not reliably
-- win a flight either. What it buys is the outer two-thirds of a run made
-- recoverable, which matters most on the way out — carrying the vault, with
-- every hunter alerted, on the leg the run is worth the most.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Sprint.Store.

-- Matches the scattered pickup's grant (Pickups/Constants.SPAWNS), so the two
-- sources of the same attribute stay worth the same. Base stamina is 100, so
-- this is half again.
local STAMINA_BONUS = 50

return function(Store)
	Store.registerItem({
		id = "sprint.stamina",
		label = "Stamina cell",
		description = `Half again the sprint before you run dry (+{STAMINA_BONUS}).`,
		unlockCost = 500,
		rentCost = 70,
		order = 50,
		-- NOT repeatable, unlike the ammo box. Stacking these makes the sprint
		-- effectively continuous in the outer rings, and a player who can sprint
		-- forever out there is never caught — which removes the hunters from
		-- two-thirds of the maze rather than making them survivable.
		apply = function(player: Player)
			player:SetAttribute("StaminaBonus", (player:GetAttribute("StaminaBonus") or 0) + STAMINA_BONUS)
		end,
		clear = function(player: Player)
			player:SetAttribute("StaminaBonus", nil)
		end,
	})
end
