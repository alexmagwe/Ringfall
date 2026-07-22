--!strict
-- LookBack's entry in the on-screen key legend.
--
-- Plain .luau => splitter routes to ReplicatedStorage.Features.LookBack.Controls.

return function(Controls)
	Controls.registerControl({ key = "Q", label = "Look behind (hold)", order = 40 })
end
