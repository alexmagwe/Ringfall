--!strict
-- Store's section on the round-summary board. Discovered by
-- src/features/Maze/Summary.luau at load; Maze never names Store.
--
-- Banking a haul is abstract — a number goes up. This turns it into the thing
-- the number is FOR: what the shelf will now sell you that it would not have
-- before, and how far off the next one is. That is the whole progression loop
-- stated in one panel at the moment it changes.
--
-- Nothing here unlocks anything. Unlocks are still bought by hand at the shelf;
-- this only reports affordability, so the board never claims a purchase the
-- player did not make.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Store.RoundSummary.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Features.Store.Constants)
local Registry = require(ReplicatedStorage.Features.Store.Registry)

local MAX_LISTED = 4 -- a board, not a catalogue; the shelf itself is the catalogue

return function(Summary)
	Summary.registerSection({
		id = "store.affordable",
		title = "THE SHELF",
		order = 20,
		lines = function(profile): { string }
			local cash = if typeof(profile.Cash) == "number" then profile.Cash else 0
			local unlocked = if typeof(profile.Unlocked) == "table" then profile.Unlocked else {}

			local affordable: { string } = {}
			local cheapestLocked: number? = nil
			local cheapestLabel: string? = nil

			for _, item in Registry.list() do
				-- Items that ship unlocked have nothing to report, and one you
				-- already own is not news.
				if item.unlockCost <= 0 or unlocked[item.id] then
					continue
				end
				if item.unlockCost <= cash then
					table.insert(affordable, `{item.label}  ·  unlock for {item.unlockCost}`)
				elseif cheapestLocked == nil or item.unlockCost < cheapestLocked then
					cheapestLocked = item.unlockCost
					cheapestLabel = item.label
				end
			end

			if #affordable == 0 then
				-- Still worth a line: a target reads as progress, where silence
				-- reads as nothing having happened.
				if cheapestLocked and cheapestLabel then
					return { `{cheapestLabel}  ·  {cheapestLocked - cash} more to unlock` }
				end
				return {}
			end

			-- No "You can now unlock:" intro line. The section heading already
			-- says THE SHELF, and a heading followed by a second heading was
			-- half of what made the board read as a paragraph. Each line states
			-- its own meaning instead.
			table.sort(affordable)
			local lines: { string } = {}
			for index, entry in affordable do
				if index > MAX_LISTED then
					table.insert(lines, `…and {#affordable - MAX_LISTED} more`)
					break
				end
				table.insert(lines, entry)
			end
			return lines
		end,
	})

	-- Referenced so the profile key this reads stays tied to Store's own
	-- constant rather than drifting into a second copy of the string.
	assert(Constants.PROFILE_KEY == "Ringfall", "[Store] RoundSummary reads the Ringfall profile slice")
end
