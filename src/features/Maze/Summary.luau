--!strict
-- Registry for the round-summary board's feature-owned sections.
--
-- The board reports the end of a run, and what a run is worth is not only the
-- Maze feature's business: the haul and the clock are, but "what the shelf will
-- now sell you" belongs to Store, "medkits spent" would belong to Health, and
-- so on. Rather than teach WinScreen about every one of them, each feature
-- declares its own section from a sibling `RoundSummary.luau` — the same
-- convention `Store.luau`, `Settings.luau`, `PlayerData.luau` and
-- `Controls.luau` already use, and for the same reason: adding a section is
-- zero edits to this folder.
--
-- Maze owns the MECHANISM (the board, the layout, when it shows). It owns none
-- of the CONTENT beyond its own run numbers.
--
-- Sections render CLIENT-SIDE from the player's own profile slice, so a section
-- costs no packet and no server work. `lines` is handed the `Ringfall` table
-- (Cash, BestHaul, Unlocked …) and returns the strings to print; returning an
-- empty table hides the section, which is how a feature stays quiet on a round
-- it has nothing to say about.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Maze.Summary.

local Summary = {}

export type Section = {
	id: string,
	title: string,
	-- Low to high. Ties break by id, so the order is stable across sessions.
	order: number?,
	lines: (profile: { [string]: any }) -> { string },
}

local sections: { [string]: Section } = {}

function Summary.registerSection(def: Section)
	if sections[def.id] ~= nil then
		warn(`[Summary] section "{def.id}" already registered; overwriting`)
	end
	sections[def.id] = def
end

function Summary.list(): { Section }
	local result: { Section } = {}
	for _, def in sections do
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
-- Require every sibling feature's `RoundSummary.luau`, which returns
-- `function(Summary) … end` and registers its sections when called. Runs in
-- both realms, exactly like the Store loop it mirrors — harmless on the server,
-- since sections are only ever rendered on the client.
do
	local features = script.Parent.Parent
	for _, feature in features:GetChildren() do
		local mod = feature:FindFirstChild("RoundSummary")
		if mod == nil or not mod:IsA("ModuleScript") then
			continue
		end

		local ok, result = pcall(require, mod)
		if not ok then
			warn(`[Summary] failed to require {mod:GetFullName()}: {result}`)
			continue
		end
		if typeof(result) ~= "function" then
			warn(`[Summary] {mod:GetFullName()} must return function(Summary); got {typeof(result)}`)
			continue
		end

		local okCall, err = pcall(result, Summary)
		if not okCall then
			warn(`[Summary] registration error in {mod:GetFullName()}: {err}`)
		end
	end
end

return Summary
