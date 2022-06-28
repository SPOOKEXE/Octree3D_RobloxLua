
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

local function GenerateRandomPoints( Position, HalfSize, ForceCount )
	local randomPointsTable = {}
	local rnd = Random.new()
	for _ = 1, (ForceCount or 2000) do
		local position = Position + Vector3.new( rnd:NextInteger(-HalfSize.X, HalfSize.X), rnd:NextInteger(-HalfSize.Y, HalfSize.Y), rnd:NextInteger(-HalfSize.Z, HalfSize.Z) )
		VisualizerModule:Attachment(position, 2)
		table.insert(randomPointsTable, position)
	end
	return randomPointsTable
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

	local randomPointsTable = GenerateRandomPoints( ActiveOctree.Position, ActiveOctree.Size / 2 )

	task.wait(4)

	local s = 0 -- initialize

	-- test 1 - single data inserts
	--[[
	s = os.clock()
	for _, position in ipairs( randomPointsTable ) do
		ActiveOctree:Insert( position, true )
	end
	print(os.clock() - s, #ActiveOctree.RootRegion.DataPoints)
	ActiveOctree:Visualize( Color3.fromRGB(31, 150, 230), InstanceCache )
	-- clear
	task.wait(3)
	ClearInstanceCache()
	ActiveOctree:Clear()]]

	-- print(string.rep('\n', 30))

	-- test 2 - batch data insert
	s = os.clock()
	ActiveOctree:BatchInsert(randomPointsTable, true)
	ActiveOctree:Visualize( Color3.fromRGB(126, 28, 218), InstanceCache )
	print(os.clock() - s, #ActiveOctree.RootRegion.DataPoints)
	--task.wait(2)
	--ClearInstanceCache()
	--ActiveOctree:Clear()

	-- reset 4 (double check reset)
	--[[
	ClearInstanceCache()
	ActiveOctree:Clear()
	print(#ActiveOctree.RootRegion.DataPoints)]]
end

function Module:RunIntersectionTest()

	local randomPointsTable = GenerateRandomPoints( ActiveOctree.Position, ActiveOctree.Size / 2 )
	ActiveOctree:BatchInsert(randomPointsTable, true)

	local regionSize = 10
	local randomPosition = Vector3.new(0, 100, 0) + Vector3.new(
		math.random(0, 100) - regionSize * 2,
		math.random(0, 100) - regionSize * 2,
		math.random(0, 100) - regionSize * 2
	) * 0.5

	local IntersectRegion = Octree3DClass.SubRegionClass.New(randomPosition, Vector3.new(regionSize, regionSize, regionSize), false)
	local DataPointList = {}
	ActiveOctree:Visualize( Color3.fromRGB(126, 28, 218), InstanceCache )

	-- test intersection
	ActiveOctree:GetSubRegionIntersectedDataPoints(IntersectRegion, DataPointList)
	IntersectRegion:Visualize( Color3.new(0, 1, 0),  InstanceCache)
	for _, dataPoint in ipairs(DataPointList) do
		local partInstance = VisualizerModule:BasePart(dataPoint.Position, false, {
			Color = Color3.fromRGB(255, 200, 10),
			Size = Vector3.new(0.5, 0.5, 0.5),
		})
		table.insert(InstanceCache, partInstance)
	end
	print('Intersected Points ; ', #DataPointList)
end

function Module:RunParticleSimulationTest()
	local Active = true
	local ActivateBind = Instance.new('BindableEvent')
	local DestroyBind = Instance.new('BindableEvent')

	local randomPointsTable = GenerateRandomPoints( ActiveOctree.Position, ActiveOctree.Size / 2, 500 )
	local activeDataPoints = ActiveOctree:BatchInsert( randomPointsTable, true )

	local function VisualizeSubRegionHits( RegionPosition, RegionSize )

		local subregionArea = Octree3DClass.SubRegionClass.New(RegionPosition, RegionSize, false)
		subregionArea:Visualize(Color3.new(1, 1, 0), InstanceCache)
		local hitDataPoints = {}
		ActiveOctree:GetSubRegionIntersectedDataPoints( subregionArea, hitDataPoints )
		for _, DataPoint in ipairs( hitDataPoints ) do
			local BasePartVisual = VisualizerModule:BasePart(DataPoint.Position, false, {
				Size = Vector3.new(1, 1, 1),
				Color = Color3.new(1, 0, 0),
				Transparency = 0.2,
			})
			table.insert(InstanceCache, BasePartVisual)
		end

	end

	ActivateBind.Event:Connect(function()
		task.spawn(function()
			while Active do
				local mapSize = 100
				local seed = math.random()
				for _, dataPoint in ipairs( activeDataPoints ) do
					local currentPos = dataPoint.Position
					dataPoint.Position += Vector3.new(
						math.noise( currentPos.X / mapSize, currentPos.X / mapSize, seed ) * 1,
						math.noise( currentPos.Y / mapSize, currentPos.Y / mapSize, seed ) * 1,
						math.noise( currentPos.Z / mapSize, currentPos.Z / mapSize, seed ) * 1
					)
				end
				ActiveOctree:UpdateOctreeDataPointRegions()
				ActiveOctree:Visualize( Color3.fromRGB(126, 28, 218), InstanceCache )
				VisualizeSubRegionHits( ActiveOctree.Position, ActiveOctree.Size / 4 )
				task.wait(0.2)
				ClearInstanceCache()
			end
		end)
	end)

	DestroyBind.Event:Connect(function()
		ActivateBind:Destroy()
		DestroyBind:Destroy()
		Active = false
	end)

	return ActivateBind, DestroyBind
end

function Module:Init()
	ActiveOctree = Octree3DClass.New(Vector3.new(0, 100, 0), Vector3.new(100, 100, 100), false)
	-- Module:RunVisualTests()

	-- Module:RunDataTest()

	-- Module:RunIntersectionTest()

	--[[
	local Activate, Destroy = Module:RunParticleSimulationTest()
	Activate:Fire()
	task.wait(30)
	Destroy:Fire()]]
end

return Module
