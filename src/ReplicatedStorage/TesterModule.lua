
local Octree3DClass = require(script.Parent.Octree3D)
local VisualizerModule = require(script.Parent.Visualizers)

local ActiveOctree = false

local InstanceCache = {}
local function ClearInstanceCache()
	for _, item in ipairs( InstanceCache ) do
		if typeof(item) == 'Instance' then
			item:Destroy()
		end
	end
	InstanceCache = {}
end

-- // Module // --
local Module = {}

function Module:RunVisualTests()
	-- depth 1
	print(ActiveOctree)
	ActiveOctree:Visualize( Color3.new(0.031372, 0.780392, 0.717647), InstanceCache )
	-- clear
	task.wait(3)
	ClearInstanceCache()

	-- depth 2
	ActiveOctree.RootRegion:_DivideSubRegion()
	print(ActiveOctree)
	ActiveOctree:Visualize( Color3.new(1, 1, 0), InstanceCache )
	-- clear
	task.wait(3)
	ClearInstanceCache()

	-- depth 3
	for _, regionClass in ipairs( ActiveOctree.RootRegion.SubRegions ) do
		regionClass:_DivideSubRegion()
	end
	print(ActiveOctree)
	ActiveOctree:Visualize( Color3.new(0.15, 0.6, 0.9), InstanceCache )
	-- clear
	task.wait(3)
	ClearInstanceCache()

	-- reset 4
	ActiveOctree.RootRegion:_UpdateDividedState()
	print(ActiveOctree)
end

function Module:RunDataTest()

	local randomPointsTable = {} do
		local halfSize = ActiveOctree.Size / 2
		local rnd = Random.new()
		for _ = 1, 1000 do
			local position =  ActiveOctree.Position + Vector3.new(
				rnd:NextInteger(-halfSize.X, halfSize.X),
				rnd:NextInteger(-halfSize.Y, halfSize.Y),
				rnd:NextInteger(-halfSize.Z, halfSize.Z)
			)
			VisualizerModule:Attachment(position, 5)
			table.insert(randomPointsTable, position)
		end
	end

	task.wait(5)

	local s = 0

	-- test 1 - single data inserts
	s = os.clock()
	for _, position in ipairs( randomPointsTable ) do
		ActiveOctree:Insert( position, true )
	end
	print(os.clock() - s, #ActiveOctree.RootRegion.DataPoints)
	ActiveOctree:Visualize( Color3.fromRGB(31, 150, 230), InstanceCache )
	-- clear
	task.wait(3)
	ActiveOctree:Clear()
	ClearInstanceCache()

	-- test 2 - batch data insert
	s = os.clock()
	ActiveOctree:BatchInsert(randomPointsTable, true)
	ActiveOctree:Visualize( Color3.fromRGB(126, 28, 218), InstanceCache )
	print(os.clock() - s, #ActiveOctree.RootRegion.DataPoints)
	task.wait(2)
	ClearInstanceCache()
	ActiveOctree:Clear()

	-- reset 4 (double check reset)
	ClearInstanceCache()
	ActiveOctree:Clear()
	print(#ActiveOctree.RootRegion.DataPoints)
end

function Module:Init()
	ActiveOctree = Octree3DClass.New(Vector3.new(0, 100, 0), Vector3.new(100, 100, 100), false)
	-- Module:RunVisualTests()
	Module:RunDataTest()
end

return Module
