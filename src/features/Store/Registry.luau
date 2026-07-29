--!strict
-- Shared store catalogue. Holds the item definitions other features have
-- declared, plus a Changed signal the UI listens to so late registrations show
-- up without a remount. Mirrors Settings/Registry.luau.
--
-- Each realm has its own copy (Lua state is per-realm). Register from SHARED
-- code — a sibling `Store.luau` picked up by the Store feature's auto-discovery
-- — so both realms see the same catalogue. The server validates purchases
-- against this registry, so a server-only or client-only registration would let
-- the two sides drift and break validation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Packages.Signal)

export type Item = {
	id: string,
	label: string,
	-- One short line under the label in the shelf window.
	description: string?,

	-- Paid ONCE, permanent, stored in the profile's Unlocked map. 0 means the
	-- item is on the shelf from day one and only ever costs rent.
	unlockCost: number,
	-- Paid EVERY round you take the item in. The effect is a per-run attribute,
	-- so it dies with you exactly like your haul does.
	rentCost: number,

	-- Sort order in the shelf (low -> high). Ties break by label.
	order: number?,
	-- Can it be rented more than once in the same round? Ammo stacks; a gun
	-- does not. Defaults to false.
	repeatable: boolean?,

	-- SERVER ONLY. Applies the per-run effect (sets the feature's attributes).
	-- Registered from shared code so both realms see the same catalogue, but
	-- only StoreService ever calls it — the client never applies anything.
	apply: (player: Player) -> (),
	-- SERVER ONLY. Strips the per-run effect. Called when the player is caught
	-- (everything carried is lost) and again at round end. Must be idempotent.
	clear: (player: Player) -> (),
}

local Registry = {}

-- Fires whenever an item is registered. The shelf UI subscribes and re-reads
-- list() so a feature added later still appears.
Registry.Changed = Signal.new()

local items: { [string]: Item } = {}

-- Once the shared auto-discovery pass finishes, the registry is sealed. Any
-- later register call is realm-specific (server- or client-only code reaching
-- in after load) — exactly the thing that would let the two realms' catalogues
-- diverge and break server-side purchase validation. Hard error at the call
-- site beats silent drift.
local sealed = false

function Registry.seal()
	sealed = true
end

function Registry.registerItem(def: Item)
	if sealed then
		error(
			`[Store] item "{def.id}" registered after the registry was sealed. `
				.. `Register only from shared code (a sibling Store.luau picked up by `
				.. `auto-discovery), never from server- or client-only code — otherwise `
				.. `the two realms' catalogues diverge.`,
			2
		)
	end
	if items[def.id] ~= nil then
		warn(`[Store] item "{def.id}" already registered; overwriting`)
	end
	items[def.id] = def
	Registry.Changed:Fire()
end

function Registry.getItem(id: string): Item?
	return items[id]
end

-- The catalogue as a list, sorted by order then label.
function Registry.list(): { Item }
	local result: { Item } = {}
	for _, def in items do
		table.insert(result, def)
	end
	table.sort(result, function(a, b)
		local ao = a.order or math.huge
		local bo = b.order or math.huge
		if ao ~= bo then
			return ao < bo
		end
		return a.label < b.label
	end)
	return result
end

return Registry
