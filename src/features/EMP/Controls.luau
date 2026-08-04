--!strict
-- EMP's entry in the on-screen key legend. Picked up by the Controls feature's
-- auto-discovery; Controls never names EMP.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.EMP.Controls.

return function(Controls)
	Controls.registerControl({ key = "F", label = "EMP burst (when carrying one)", order = 27 })
end
