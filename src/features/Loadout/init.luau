--!strict
-- Registry for the "what am I carrying" strip.
--
-- WHY THIS EXISTS. Every feature that had something to tell you drew its own
-- label and picked its own corner: medkit charges bottom-left, ammo and haul
-- bottom-right, EMP and skateboard bottom-centre. Eight bottom-anchored labels
-- chosen independently, and by the time the eighth arrived there were four
-- collisions — the worst of them silent, because the medkit line sat *inside*
-- the controls legend's panel and simply could not be read. A player carrying a
-- medkit had no way to know.
--
-- No offset is the right offset when every feature is guessing. The fix is the
-- same one Controls already uses for keys: features declare WHAT to say, one
-- owner decides WHERE, and a layout stacks them so two rows cannot occupy the
-- same pixels however many features are installed.
--
-- A feature drops a sibling `Loadout.luau` returning `function(Loadout) … end`,
-- exactly like `Store.luau`, `Settings.luau`, `Controls.luau`, `Scatter.luau`
-- and `RoundSummary.luau`.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Loadout.

local Loadout = {}

export type Slot = {
	id: string,
	-- Low to high, top of the strip down. Ties break by id so the order is
	-- stable across sessions rather than following hash iteration.
	order: number?,
	-- Player attributes whose change should re-read this slot. The strip
	-- subscribes to each one; a slot that watches nothing never updates.
	watch: { string },
	-- The line to draw, or NIL TO HIDE THE ROW ENTIRELY. Hiding is the common
	-- case — "AMMO 0" and "HAUL 0" are readouts of nothing, and a strip that
	-- shows every slot at all times is the clutter this replaces.
	text: (player: Player) -> string?,
	color: Color3?,
	-- Attribute whose numeric RISE should flash the row. This is behaviour the
	-- rows share (haul flashed on a pickup, and ammo wanted to), so it lives
	-- here rather than being re-tweened in each feature.
	flashOn: string?,
}

local slots: { [string]: Slot } = {}

function Loadout.registerSlot(def: Slot)
	if slots[def.id] ~= nil then
		warn(`[Loadout] slot "{def.id}" already registered; overwriting`)
	end
	slots[def.id] = def
end

function Loadout.list(): { Slot }
	local result: { Slot } = {}
	for _, def in slots do
		table.insert(result, def)
	end
	table.sort(result, function(a, b)
		local ao, bo = a.order or math.huge, b.order or math.huge
		if ao ~= bo then
			return ao < bo
		end
		return a.id < b.id
	end)
	return result
end

------------------------------------------------------------------------------
-- Auto-discovery
------------------------------------------------------------------------------
-- Require every sibling feature's `Loadout.luau` and call it with this table.
-- Runs in both realms; a registration is just a table write, and only
-- LoadoutController (client) ever reads the result.
do
	local features = script.Parent
	for _, feature in features:GetChildren() do
		if feature == script then
			continue
		end
		local mod = feature:FindFirstChild("Loadout")
		if mod == nil or not mod:IsA("ModuleScript") then
			continue
		end

		local ok, result = pcall(require, mod)
		if not ok then
			warn(`[Loadout] failed to require {mod:GetFullName()}: {result}`)
			continue
		end
		if typeof(result) ~= "function" then
			warn(`[Loadout] {mod:GetFullName()} must return function(Loadout); got {typeof(result)}`)
			continue
		end

		local okCall, err = pcall(result, Loadout)
		if not okCall then
			warn(`[Loadout] registration error in {mod:GetFullName()}: {err}`)
		end
	end
end

return Loadout
