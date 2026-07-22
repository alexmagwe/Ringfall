--!strict
-- Sprint's entries in the on-screen key legend. Picked up by the Controls
-- feature's auto-discovery; Controls never names Sprint.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.Sprint.Controls.

return function(Controls)
	Controls.registerControl({ key = "W A S D", label = "Move", order = 10 })
	Controls.registerControl({ key = "SHIFT", label = "Sprint", order = 20 })
	Controls.registerControl({ key = "C", label = "Crouch (hide behind walls)", order = 30 })
end
