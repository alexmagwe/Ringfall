--!strict
-- Health's entry in the on-screen key legend. Picked up by the Controls
-- feature's auto-discovery; Controls never names Health.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Health.Controls.

return function(Controls)
	Controls.registerControl({ key = "H", label = "Use medkit (when carrying one)", order = 30 })
end
