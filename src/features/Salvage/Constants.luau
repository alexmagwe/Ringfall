--!strict
-- Plain .luau => ReplicatedStorage.Features.Salvage.Constants (shared realms).
return {
	FOLDER = "Salvage",
	DROPS_FOLDER = "Drops",
	FLOAT_Y = 3,
	-- Keyed by MazeNav district (3 = outer .. 1 = inner). Deeper = fewer, richer.
	PER_DISTRICT = {
		[3] = { count = 10, value = 10, color = Color3.fromRGB(150, 160, 170) },
		[2] = { count = 8, value = 30, color = Color3.fromRGB(120, 190, 220) },
		[1] = { count = 6, value = 75, color = Color3.fromRGB(200, 150, 255) },
	},
	-- A theoretically perfect sweep of every piece is 100+240+450 = 790, but that
	-- means visiting all 24 cells across all three districts, and the round ends
	-- the moment anyone extracts the vault — so nobody gets to finish one. The
	-- vault is a single touch worth 500, which beats any realistic sweep while
	-- staying under the impossible maximum: committing to it is tempting, not
	-- automatic. Re-check this against PER_DISTRICT if you retune either.
	VAULT_VALUE = 500,
	ALARM_REFRESH = 1.0,
}
