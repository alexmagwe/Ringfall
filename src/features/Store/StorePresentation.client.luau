--!strict
-- Screen presentation for the Store: registers the shelf window as a root, so
-- it mounts with the client tree and shows itself when StoreController opens.
-- Discovered + required by init.client.luau before the root mounts;
-- registration is the only side effect.
--
-- A root rather than a UIShell screen because the shelf isn't reached through
-- HUD navigation — you walk up to a terminal in the staging room.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local UIRegistry = require(ReplicatedStorage.Shared.Boil).UIRegistry
local Constants = require(ReplicatedStorage.Features.Store.Constants)

-- Client-realm sibling (StarterPlayerScripts.Features.Store.StoreView).
local StoreView = require(script.Parent.StoreView)

if Constants.Presentations.screen then
	UIRegistry.registerRoot("Store", React.createElement(StoreView))
end

return {}
