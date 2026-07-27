--!strict
-- Controls — the registry behind the on-screen key legend. Features declare
-- their own keys here instead of Controls hardcoding a list of things it
-- shouldn't know about.
--
-- A feature registers by dropping a sibling `Controls.luau` returning
-- `function(Controls) ... end`, picked up by the auto-discovery loop below.
-- See docs/game/Controls.md.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Controls.

export type Control = {
	-- Chip text, e.g. "SHIFT" or "W A S D". Kept short; the legend is narrow.
	key: string,
	-- What the key does, e.g. "Look behind (hold)".
	label: string,
	-- Sort order in the legend (low → high). Ties break by label.
	order: number?,
}

local Controls = {}

local registered: { Control } = {}

-- Discovery is the only sanctioned registration window: the legend is built
-- once when the HUD mounts, so anything registered later would silently never
-- appear. Seal turns that into a loud error at the call site instead.
local sealed = false

local function assertUnsealed(key: string)
	if not sealed then
		return
	end
	error(
		`[Controls] control "{key}" registered after the registry was sealed. `
			.. `Register from a sibling Controls.luau picked up by auto-discovery, `
			.. `not from controller/service code that runs after load.`,
		2
	)
end

function Controls.registerControl(def: Control)
	assertUnsealed(def.key)
	table.insert(registered, def)
end

function Controls.seal()
	sealed = true
end

-- The legend contents, sorted by order then label.
function Controls.list(): { Control }
	local result = table.clone(registered)
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

------------------------------------------------------------------------------
-- Auto-discovery
------------------------------------------------------------------------------
-- Walk the Features tree and require any sibling feature's `Controls.luau`.
-- That module returns `function(Controls) ... end` and uses registerControl to
-- declare its keys. A feature's Controls.luau never requires Features.Controls
-- itself, which is what keeps this free of circular requires.
do
	local Features = script.Parent
	for _, featureModule in Features:GetChildren() do
		if featureModule == script then
			continue
		end
		local mod = featureModule:FindFirstChild("Controls")
		if mod == nil or not mod:IsA("ModuleScript") then
			continue
		end

		local ok, result = pcall(require, mod)
		if not ok then
			warn(`[Controls] failed to require {mod:GetFullName()}: {result}`)
			continue
		end
		if typeof(result) ~= "function" then
			warn(`[Controls] {mod:GetFullName()} must return function(Controls); got {typeof(result)}`)
			continue
		end

		local okCall, err = pcall(result, Controls)
		if not okCall then
			warn(`[Controls] registration error in {mod:GetFullName()}: {err}`)
		end
	end

	Controls.seal()
end

return Controls
