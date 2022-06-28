
local VisualizerModule = require(script.Parent.Visualizers)

local Settings = {
	MaxRegionSize = Vector3.new(1024, 1024, 1024),
	MaxNodesPerSubRegion = 6,
	MaxTreeDepth = 7,
}

local DivisionVectorOffsetMatrix = {
	Vector3.new(0.25, 0.25, -0.25),
	Vector3.new(-0.25, 0.25, -0.25),
	Vector3.new(0.25, 0.25, 0.25),
	Vector3.new(-0.25, 0.25, 0.25),
	Vector3.new(0.25, -0.25, -0.25),
	Vector3.new(-0.25, -0.25, -0.25),
	Vector3.new(0.25, -0.25, 0.25),
	Vector3.new(-0.25, -0.25, 0.25),
}

local function ScaleVector3(vector1, vector2)
	return Vector3.new(
		vector1.x * vector2.x,
		vector1.y * vector2.y,
		vector1.z * vector2.z
	)
end

-- // Region Node // --
local OctreeDataPoint = { ClassName = 'OctreeDataPoint' }
OctreeDataPoint.__index = OctreeDataPoint

-- create a new position node that goes inside subregions
function OctreeDataPoint.New( PositionVector, NodeData, _ )
	local self = setmetatable({
		Position = PositionVector,
		Data = NodeData,
		--ParentSubRegion = false,
	}, OctreeDataPoint)
	-- self:_SetParentSubRegion( ParentSubRegion )
	return self
end

-- get region node data
function OctreeDataPoint:GetData()
	return self.Data
end

-- set parent subregion
--[[function OctreeDataPoint:_SetParentSubRegion( subregionClass )
	self.ParentSubRegion = setmetatable({}, subregionClass) -- prevents cyclic table issue
end]]

-- get parent subregion
function OctreeDataPoint:GetParentSubRegion()
	return self.ParentSubRegion
end

-- visualize
function OctreeDataPoint:Visualize( cacheTable )
	local attachmentInstance = VisualizerModule:Attachment(self.Position, false)
	if cacheTable then
		table.insert(cacheTable, attachmentInstance)
	end
end

-- // Octree Region Class // --
local OctreeSubRegion = { ClassName = 'OctreeSubRegion' }
OctreeSubRegion.__index = OctreeSubRegion

function OctreeSubRegion.New( PositionVector, SizeVector, ParentSubRegion )
	local self = {}
	self.Divided = false
	self.SubRegions = false
	self.Depth = ParentSubRegion and (ParentSubRegion.Depth + 1) or 1
	self.Position = PositionVector
	self.Size = SizeVector or Settings.MaxNodesPerSubRegion
	self.DataPoints = {}
	self.Parent = ParentSubRegion and setmetatable({}, ParentSubRegion) -- prevents cyclic table issue
	return setmetatable(self, OctreeSubRegion)
end

-- does this subregion contain the point
function OctreeSubRegion:Contains( Position )
	local lowerBounds = self.Position - (self.Size / 2)
	local upperBounds = self.Position + (self.Size / 2)
	return (
		Position.X >= lowerBounds.X and Position.X <= upperBounds.X and
		Position.Y >= lowerBounds.Y and Position.Y <= upperBounds.Y and
		Position.Z >= lowerBounds.Z and Position.Z <= upperBounds.Z
	)
end

-- does this subregion intersect another subregion
function OctreeSubRegion:Intersects( otherSubRegion, EPSILON )
	EPSILON = EPSILON or 0.1
	local pos1 = self.Position
	local pos2 = otherSubRegion.Position
	local totalSizeMag = ((self.Size / 2) + (otherSubRegion.Size / 2)).Magnitude
	return
		math.abs(pos1.x-pos2.x) - totalSizeMag <= EPSILON and
		math.abs(pos1.y-pos2.y) - totalSizeMag <= EPSILON and
		math.abs(pos1.z-pos2.z) - totalSizeMag <= EPSILON
end

-- get all data points that are within the subregion that was passed
function OctreeSubRegion:GetPointsInIntersectedRegion( intersectionSubRegion, arrayList )
	if self.Divided then
		for _, subRegion in ipairs( self.SubRegions ) do
			subRegion:GetPointsInIntersectedRegion( intersectionSubRegion, arrayList )
		end
	elseif self:Intersects( intersectionSubRegion, false ) then -- false = eplison value
		for _, dataPoint in ipairs( self.DataPoints ) do
			if intersectionSubRegion:Contains(dataPoint.Position) then
				table.insert(arrayList, dataPoint)
			end
		end
	end
end

-- remove the target data point from this subregion
function OctreeSubRegion:Remove( DataPoint )
	-- remove from this if found
	local index = table.find(self.DataPoints, DataPoint)
	if index then
		table.remove(self.DataPoints, index)
	end
	-- remove from child subregions if has divided
	if self.Divided then
		for _, subRegion in ipairs( self.SubRegions ) do
			subRegion:Remove( DataPoint )
		end
	end
	self:_UpdateDividedState()
end

-- remove a batch of data points from this subregion
function OctreeSubRegion:RemoveBatch( DataPointsList )
	-- remove data point
	for _, dataPoint in ipairs( DataPointsList ) do
		local dataPointIndex = table.find(self.DataPoints, dataPoint)
		-- print(dataPointIndex)
		if dataPointIndex then
			-- found in this list, remove
			table.remove(self.DataPoints, dataPointIndex)
		end
	end

	-- remove from child subregions if has divided
	if self.Divided then
		for _, subRegion in ipairs( self.SubRegions ) do
			subRegion:RemoveBatch( DataPointsList )
		end
	end
	self:_UpdateDividedState()
end

-- split subregion
function OctreeSubRegion:_DivideSubRegion()
	local newSize = self.Size / 2
	self.SubRegions = {}
	for _, offsetVector in ipairs(DivisionVectorOffsetMatrix) do
		table.insert(self.SubRegions, OctreeSubRegion.New(self.Position + ScaleVector3(self.Size, offsetVector), newSize, self))
	end
	for _, subRegion in ipairs( self.SubRegions ) do
		subRegion:BatchInsertDataPoints( self.DataPoints )
	end
	self.Divided = true
end

-- check if subregion can be recombined
function OctreeSubRegion:_UpdateDividedState()
	local hasReachedLimit = #self.DataPoints >= Settings.MaxNodesPerSubRegion
	if self.Divided then
		for _, subRegion in ipairs( self.SubRegions ) do
			if hasReachedLimit then
				-- print('update depth ; ', self.Depth)
				subRegion:_UpdateDividedState() -- update the lower region before this one
			else
				-- print('under limit, set subregion parent to nil')
				subRegion.Parent = nil
			end
		end
		if not hasReachedLimit then
			-- print('under limit, remove subregion and undivide')
			self.Divided = false
			self.SubRegions = false -- since the data is no longer cached, clears memory
		end
	end
end

-- add the target data point to the subregion
function OctreeSubRegion:InsertDataPoint( DataPoint )
	-- if it contains this point, add it to this sub region
	if self:Contains( DataPoint.Position ) then
		table.insert(self.DataPoints, DataPoint)
		--DataPoint:_SetParentSubRegion( self )
		-- split if limit is reached
		if #self.DataPoints >= Settings.MaxNodesPerSubRegion and (self.Depth + 1) < Settings.MaxTreeDepth then
			self:_DivideSubRegion()
			return -- no need to continue below, we just split them here and divided them
		end
	end
	-- if divided, add to child subregions
	if self.Divided then
		for _, subRegion in ipairs( self.SubRegions ) do
			subRegion:InsertDataPoint( DataPoint )
		end
		return
	end
	self:_UpdateDividedState()
end

-- add a batch of data points to the subregion
function OctreeSubRegion:BatchInsertDataPoints( DataPointsList )
	-- add data points
	for _, DataPoint in ipairs( DataPointsList ) do
		if self:Contains( DataPoint.Position ) and not table.find(self.DataPoints, DataPoint) then
			table.insert(self.DataPoints, DataPoint)
			-- DataPoint:_SetParentSubRegion( self )
		end
	end

	if #self.DataPoints >= Settings.MaxNodesPerSubRegion and (self.Depth + 1) < Settings.MaxTreeDepth then
		self:_DivideSubRegion()
		return -- no need to continue below, we just split them here and divided them
	end

	-- if divided, add to child subregions
	if self.Divided then
		for _, subRegion in ipairs( self.SubRegions ) do
			subRegion:BatchInsertDataPoints( DataPointsList )
		end
		return
	end

	self:_UpdateDividedState()
end

-- update all data points
function OctreeSubRegion:UpdateDataPointRegions()
	local clonedPoints = {}
	for _, dataPoint in ipairs( self.DataPoints ) do
		table.insert(clonedPoints, dataPoint)
	end
	self:RemoveBatch( self.DataPoints )
	-- print(#self.DataPoints)
	self:BatchInsertDataPoints(clonedPoints)
	-- print(#self.DataPoints)
	self:_UpdateDividedState()
end

function OctreeSubRegion:Visualize( forceColor, cacheTable )
	if self.Divided then
		for _, subRegion in ipairs( self.SubRegions ) do
			subRegion:Visualize(forceColor, cacheTable)
		end
	else
		local basePart = VisualizerModule:BasePart(self.Position, false, {
			Name = self.Depth,
			Transparency = 0.95,
			Color = forceColor or Color3.new(1, 0, 0),
			Size = self.Size,
		})

		if cacheTable then
			table.insert(cacheTable, basePart)
		end

		for _, dataPoint in ipairs( self.DataPoints ) do
			dataPoint:Visualize(cacheTable)
		end
	end
end

-- // Octree Class // --
local OctreeClass = { ClassName = 'Octree3DMap', SubRegionClass = OctreeSubRegion }
OctreeClass.__index = OctreeClass

function OctreeClass.New(Position, Size)
	local self = {}
	-- self.Region3DMap = {}
	self.Position = Position or Vector3.new()
	self.Size = Size or Settings.MaxRegionSize
	self.RootRegion = OctreeSubRegion.New(self.Position, self.Size, false)
	return setmetatable(self, OctreeClass)
end

-- update all data points in octree
function OctreeClass:UpdateOctreeDataPointRegions()
	self.RootRegion:UpdateDataPointRegions()
end

-- get the furthest square bounds of the octree
-- BoundPosition : Vector3, BoundSize : Vector3
function OctreeClass:GetOctreeBounds()
	return self.Position, self.Size
end

-- get all datapoints within this octree that are in the region
function OctreeClass:GetSubRegionIntersectedDataPoints( subRegion, arrayList )
	self.RootRegion:GetPointsInIntersectedRegion( subRegion, arrayList )
end

-- returns an octree node
function OctreeClass:Insert( Position, Data )
	local baseDataPoint = OctreeDataPoint.New(Position, Data)
	self.RootRegion:InsertDataPoint(baseDataPoint)
	return baseDataPoint
end

-- batch insert
function OctreeClass:BatchInsert( PositionTable, Data )
	local batchTable = {}
	for _, position in ipairs( PositionTable ) do
		table.insert(batchTable, OctreeDataPoint.New(position, Data))
	end
	self.RootRegion:BatchInsertDataPoints(batchTable)
	return batchTable
end

-- does the octree contain the data point
function OctreeClass:ContainsDataPoint( dataPointNode )
	return table.find(self.RootRegion.DataPoints, dataPointNode) ~= nil
end

-- remove a data point from the octree
function OctreeClass:RemoveDataPoint( regionNode )
	self.RootRegion:Remove(regionNode)
end

-- batch remove data points from the octree
function OctreeClass:BatchRemoveDataPoints( dataPointsTable )
	self.RootRegion:RemoveBatch(dataPointsTable)
end

-- clear the octree map
function OctreeClass:Clear()
	-- set all parent subregions of data points to nil so it can be garbage collected
	self.RootRegion:RemoveBatch(self.RootRegion.DataPoints)
	-- release memory and let it garbage collect, make a new root subregion
	self.RootRegion = OctreeSubRegion.New(self.Position, self.Size, false)
end

-- destroy the octree
function OctreeClass:Destroy()
	self:Clear() -- clear the root subregion first
	self.Position = false
	self.Size = false
	setmetatable(self, nil)
end

-- visualize (debug)
function OctreeClass:Visualize( forceColor, cacheTable )
	self.RootRegion:Visualize( forceColor, cacheTable )
end

return OctreeClass