--!strict
-- Gun's entries on the staging-room shelf. Picked up by the Store feature's
-- auto-discovery; Store never names Gun.
--
-- Both ship unlocked (unlockCost 0) — a newcomer's first round can still be
-- armed. What you pay every round is the rent, and you lose the gun when you
-- die, exactly like your haul.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Gun.Store.

-- Kept local rather than read from Pickups' GUN_START_AMMO: the shelf and the
-- scattered pickup are two different sources for the same attribute, and
-- neither feature should have to require the other to price its own item.
local SIDEARM_AMMO = 12
local AMMO_BOX_ROUNDS = 12

return function(Store)
	Store.registerItem({
		id = "gun.sidearm",
		label = "Sidearm",
		description = `A gun and {SIDEARM_AMMO} rounds. One damage a hit, and hunters hear every shot.`,
		unlockCost = 0,
		rentCost = 60,
		order = 10,
		apply = function(player: Player)
			player:SetAttribute("HasGun", true)
			player:SetAttribute("Ammo", (player:GetAttribute("Ammo") or 0) + SIDEARM_AMMO)
		end,
		clear = function(player: Player)
			player:SetAttribute("HasGun", nil)
			player:SetAttribute("Ammo", nil)
		end,
	})

	-- The most expensive thing on the shelf, because it removes the one cost
	-- that makes shooting a decision at all: every shot summons the hunters that
	-- hear it, so firing trades a hunter's health for your position. Silenced,
	-- that trade disappears — which is worth a lot and should never be cheap or
	-- available on the first round. Priced above the Medkit (300/80) on purpose.
	Store.registerItem({
		id = "gun.silencer",
		label = "Silencer",
		description = "Shots stop summoning hunters, and the report is muffled.",
		unlockCost = 400,
		rentCost = 90,
		order = 25, -- keeps the gun family contiguous: sidearm, ammo, silencer
		apply = function(player: Player)
			player:SetAttribute("HasSilencer", true)
		end,
		clear = function(player: Player)
			player:SetAttribute("HasSilencer", nil)
		end,
	})

	Store.registerItem({
		id = "gun.ammo",
		label = "Ammo box",
		description = `{AMMO_BOX_ROUNDS} more rounds. Stacks — buy as many as you can fund.`,
		unlockCost = 0,
		rentCost = 30,
		order = 20,
		-- Ammo is the one thing worth buying twice in a round.
		repeatable = true,
		apply = function(player: Player)
			player:SetAttribute("Ammo", (player:GetAttribute("Ammo") or 0) + AMMO_BOX_ROUNDS)
		end,
		clear = function(player: Player)
			player:SetAttribute("Ammo", nil)
		end,
	})
end
