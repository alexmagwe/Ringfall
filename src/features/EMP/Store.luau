--!strict
-- The EMP's entry on the staging-room shelf. Picked up by the Store feature's
-- auto-discovery; Store never names EMP.
--
-- WHAT IT IS FOR, and why it is not just a better gun. The Sidearm answers "this
-- one is in my way" — one hunter, permanently, at the price of every hunter in
-- earshot hearing it. The EMP answers "all of these are on me at once", which
-- the gun cannot: sixteen shots to drop a Warden is not a plan when three of
-- them have you in a dead end. It buys a WINDOW and kills nothing.
--
-- Priced between the Sidearm (60) and the Silencer (90) to rent, and unlocked at
-- 350 — under the Silencer's 400, because the Silencer permanently removes a
-- cost from every shot you take for the whole round, and this is two moments.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.EMP.Store.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Features.EMP.Constants)

local CHARGES = 2

return function(Store)
	Store.registerItem({
		id = "emp.pulse",
		label = "EMP charge",
		description = `{CHARGES} bursts. Disables every hunter near where it lands for {Constants.SECONDS}s — it kills nothing.`,
		unlockCost = 350,
		rentCost = 75,
		order = 30, -- after the gun family (10/20/25), before the medkit
		-- Repeatable, like the ammo box: charges are the one thing worth buying
		-- twice, and unlike the stamina cell there is no runaway — more bursts
		-- is more windows, not a longer one.
		repeatable = true,
		apply = function(player: Player)
			player:SetAttribute(
				Constants.CHARGES_ATTRIBUTE,
				(player:GetAttribute(Constants.CHARGES_ATTRIBUTE) or 0) + CHARGES
			)
		end,
		clear = function(player: Player)
			player:SetAttribute(Constants.CHARGES_ATTRIBUTE, nil)
		end,
	})
end
