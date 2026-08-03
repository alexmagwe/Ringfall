--!strict
-- Sprint's entry on the staging-room shelf. Picked up by the Store feature's
-- auto-discovery; Store never names Sprint.
--
-- The same `StaminaBonus` attribute the scattered Stamina pickup grants, bought
-- up front instead of found. Both add to it, so a player who buys one and finds
-- one carries both — which is the point of leaving the pickup in the maze.
--
-- WHY IT IS THE DEAREST THING ON THE SHELF (500, above the Silencer's 400).
-- Every other item widens what you can do in a fight or in the dark. This one
-- widens the only thing that reliably gets you out of one: a hunter is faster
-- than your walk and slower than your sprint, so sprint duration IS your escape
-- budget. Raising it does not help you win a fight — it makes losing one
-- survivable, which is worth more in a game whose primary verb is hiding.
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
		-- NOT repeatable, unlike the ammo box. Stacking these turns the escape
		-- budget into an unlimited one, and a player who can sprint forever is
		-- never caught — which removes the hunters from the game rather than
		-- making them survivable.
		apply = function(player: Player)
			player:SetAttribute("StaminaBonus", (player:GetAttribute("StaminaBonus") or 0) + STAMINA_BONUS)
		end,
		clear = function(player: Player)
			player:SetAttribute("StaminaBonus", nil)
		end,
	})
end
