
local Octree3DClass = require(script.Parent.Octree3D)

local ActiveOctree = false

-- // Module // --
local Module = {}

function Module:RunTests()
	print(ActiveOctree)
end

function Module:Init()
	ActiveOctree = Octree3DClass.New(Vector3.new(), false, false)
	Module:RunTests()
end

return Module
