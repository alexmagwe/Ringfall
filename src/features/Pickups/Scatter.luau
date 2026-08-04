--!strict
-- Registry for feature-owned things scattered in the maze.
--
-- `Constants.SPAWNS` holds the kinds Pickups genuinely owns — ammo, the stamina
-- upgrade, medkits. Anything a SEPARATE feature wants in the maze goes through
-- here instead, so adding one is zero edits to this folder: the feature drops a
-- sibling `Scatter.luau` returning `function(Scatter) … end`, exactly like
-- `Store.luau`, `Settings.luau`, `Controls.luau` and `RoundSummary.luau`.
--
-- Pickups owns the MECHANISM — where things land, the touch that consumes them,
-- the toast, the "you lose it when you're caught" rule. It owns none of the
-- CONTENT beyond its own three kinds. A registered spawn brings its own grant
-- (what the grab actually does) and its own `clearOnCatch` list, because Pickups
-- has no business knowing what a skateboard is.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Pickups.Scatter.

local Scatter = {}

export type Spawn = {
	-- Identifies the kind end to end: the pickup's `PickupKind` attribute, the
	-- toast signal, and the key this registry stores it under.
	kind: string,
	-- Child of ServerStorage.PickupModels to clone for the art. Missing => the
	-- neon-ball fallback, so a spawn works before any art exists.
	model: string?,
	count: number,
	color: Color3,
	-- Passed to `grant` and stashed on the pickup as `PickupAmount`.
	amount: number?,
	-- Placement constraints, all optional and all inclusive. See
	-- PickupsService.scatter — a constraint that leaves no candidate cells falls
	-- back to the unconstrained pool, so a spawn never fails to place.
	minBand: number?,
	maxBand: number?,
	minSpawnDist: number?,
	-- Toast text ("PICKED UP: …"). Defaults to `kind`.
	label: string?,
	-- Longest HORIZONTAL axis, in studs, to rescale the art to. nil leaves the
	-- model at whatever size it was authored — which is right for art made for
	-- this game and wrong for anything imported, where the scale is somebody
	-- else's export setting. A feature that also renders the same art somewhere
	-- else (the skateboard is drawn twice: lying in the maze and welded under a
	-- rider) sets this so the two cannot disagree about how big the thing is.
	scaleTo: number?,
	-- SERVER-SIDE, called on the grab. This is the whole point of the registry:
	-- the granting feature decides what its own pickup does.
	grant: (player: Player, amount: number?) -> (),
	-- Player attributes wiped when the holder is caught. Everything you carry
	-- dies with you (see PickupsService's clearCarriedKit) — a registered spawn
	-- has to name its own attributes because Pickups can't know them.
	clearOnCatch: { string }?,
}

local spawns: { [string]: Spawn } = {}

function Scatter.registerSpawn(def: Spawn)
	if spawns[def.kind] ~= nil then
		warn(`[Scatter] spawn "{def.kind}" already registered; overwriting`)
	end
	spawns[def.kind] = def
end

function Scatter.byKind(kind: string): Spawn?
	return spawns[kind]
end

-- Sorted by kind so cell-claiming order is stable across sessions — two spawns
-- with the same constraints must not swap places just because a hash iterated
-- differently.
function Scatter.list(): { Spawn }
	local result: { Spawn } = {}
	for _, def in spawns do
		table.insert(result, def)
	end
	table.sort(result, function(a, b)
		return a.kind < b.kind
	end)
	return result
end

------------------------------------------------------------------------------
-- Auto-discovery
------------------------------------------------------------------------------
-- Require every sibling feature's `Scatter.luau` and call it with this module.
-- Runs in BOTH realms: the client needs the registry too (for the toast label),
-- and a registration is just a table write, so it is harmless there. `grant`
-- only ever runs on the server, where PickupsService calls it.
do
	local features = script.Parent.Parent
	for _, feature in features:GetChildren() do
		local mod = feature:FindFirstChild("Scatter")
		-- Skip THIS module. Pickups is a sibling of every other feature, so the
		-- loop reaches its own folder and finds itself; requiring it from inside
		-- its own body is a cyclic require, which pcall would only turn into a
		-- warning on every boot.
		if mod == nil or mod == script or not mod:IsA("ModuleScript") then
			continue
		end

		local ok, result = pcall(require, mod)
		if not ok then
			warn(`[Scatter] failed to require {mod:GetFullName()}: {result}`)
			continue
		end
		if typeof(result) ~= "function" then
			warn(`[Scatter] {mod:GetFullName()} must return function(Scatter); got {typeof(result)}`)
			continue
		end

		local okCall, err = pcall(result, Scatter)
		if not okCall then
			warn(`[Scatter] registration error in {mod:GetFullName()}: {err}`)
		end
	end
end

return Scatter
