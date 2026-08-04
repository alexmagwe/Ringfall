--!strict
-- Skateboard's entry in the on-screen key legend. Picked up by the Controls
-- feature's auto-discovery; Controls never names Skateboard.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Skateboard.Controls.

return function(Controls)
	Controls.registerControl({ key = "R", label = "Ride skateboard (not on grass)", order = 35 })
end
