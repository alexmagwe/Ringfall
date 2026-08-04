-- Admin config. Edit AllowedUserIds to grant someone Cmdr access.
--
-- USER IDS, NOT USERNAMES. `CmdrService` registers Cmdr's default commands, so
-- anyone on this list can teleport, kill and the rest in the LIVE game — which
-- makes the list a security surface, not a convenience. A username is the weak
-- form of that: names can be changed and released, so a name on this list can
-- end up belonging to someone else. A UserId is permanent and belongs to one
-- account forever.
--
-- This shipped as `AllowedUsernames = { "Encryptal" }`, the boilerplate author's
-- account, which would have granted admin in a published game to someone the
-- game's owner does not control.
--
-- To find an id: in Studio, `game:GetService("StudioService"):GetUserId()` is
-- the signed-in account; for anyone else, `Players:GetUserIdFromNameAsync(name)`.

return {
	-- Exact Roblox UserIds allowed to run any Cmdr command. An empty list locks
	-- the console for everyone, which is the safe default if you are unsure.
	AllowedUserIds = {
		11163685327, -- kepla176 (owner)
	},

	-- Keys that open the Cmdr console on the client.
	ActivationKeys = { Enum.KeyCode.F2 },
}
