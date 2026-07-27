--!strict
-- Gun's entry in the on-screen key legend. Picked up by the Controls
-- feature's auto-discovery; Controls never names Gun.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Gun.Controls.

return function(Controls)
	Controls.registerControl({ key = "MOUSE 1", label = "Shoot (when armed)", order = 25 })
end
