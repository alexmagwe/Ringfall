-- Store — the staging-room shelf. Two prices per item:
--
--   * Unlock — paid once, permanent, stored in the profile's Unlocked map.
--     Widens what the shelf offers you forever.
--   * Rent   — paid every round you take the item in. Applied as a per-run
--     attribute, and lost on death like everything else you carry.
--
-- Progression is your options widening, not your raw power climbing: a
-- fully-unlocked veteran still has to fund and risk their kit every round,
-- exactly like a newcomer, so the free-for-all gap stays bounded.
--
-- The Store owns the MECHANISM (prices, validation, the terminal, the shelf
-- UI). It owns no CONTENT: every item is declared by the feature whose effect
-- it applies, via a sibling `Store.luau` returning `function(Store) … end`
-- that the auto-discovery loop below picks up at load time. Adding an item is
-- therefore zero edits to this folder — same convention as Settings/PlayerData.
--
-- See docs/game/Store.md for the full integration guide.

local Store = {}

Store.Constants = require(script.Constants)
Store.Registry = require(script.Registry)
Store.UI = require(script.StoreUI)

Store.registerItem = Store.Registry.registerItem

------------------------------------------------------------------------------
-- Auto-discovery
------------------------------------------------------------------------------
-- Walk the Features tree and require any sibling feature's `Store.luau` module.
-- That module returns `function(Store) ... end` — when called it receives this
-- table and uses registerItem to declare what it sells.
--
-- The convention avoids a circular require (a feature's Store.luau never
-- requires Features.Store itself) and runs identically on client and server
-- (both realms load this module and run the loop independently), which is what
-- keeps the two catalogues in step for server-side validation.
do
	local Features = script.Parent
	for _, featureModule in Features:GetChildren() do
		if featureModule == script then
			continue
		end
		local mod = featureModule:FindFirstChild("Store")
		if mod == nil or not mod:IsA("ModuleScript") then
			continue
		end

		local ok, result = pcall(require, mod)
		if not ok then
			warn(`[Store] failed to require {mod:GetFullName()}: {result}`)
			continue
		end
		if typeof(result) ~= "function" then
			warn(`[Store] {mod:GetFullName()} must return function(Store); got {typeof(result)}`)
			continue
		end

		local okCall, err = pcall(result, Store)
		if not okCall then
			warn(`[Store] registration error in {mod:GetFullName()}: {err}`)
		end
	end

	-- Discovery is the only sanctioned registration window. Seal so any later
	-- registerItem call (from server- or client-only code) errors instead of
	-- silently drifting the two realms' catalogues apart.
	Store.Registry.seal()
end

return Store
