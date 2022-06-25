
local Settings = {
	MaxRegionSize = Vector3.new(1024, 1024, 1024),
	MaxNodesPerSubRegion = 10,
	MaxTreeDepth = 6,
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

local function SnapToCell(number, increment)
	return math.floor(number / increment + 0.5)
end

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
function OctreeDataPoint.New( PositionVector, NodeData, ParentSubRegion )
	local self = setmetatable({
		Position = PositionVector,
		Data = NodeData,
		ParentSubRegion = false,
	}, OctreeDataPoint)
	self:_SetParentSubRegion( ParentSubRegion )
	return self
end

-- remove region node
function OctreeDataPoint:Remove()
	if rawget(self, 'ParentSubRegion') then
		self.ParentSubRegion:Remove(self)
		return true
	end
	return false
end

-- get region node data
function OctreeDataPoint:GetData()
	return self.Data
end

-- set parent subregion
function OctreeDataPoint:_SetParentSubRegion( subregionClass )
	self.ParentSubRegion = setmetatable({}, subregionClass) -- prevents cyclic table issue
end

-- get parent subregion
function OctreeDataPoint:GetParentSubRegion()
	return self.ParentSubRegion
end

-- // Octree Region Class // --
local OctreeSubRegion = { ClassName = 'OctreeSubRegion' }
OctreeSubRegion.__index = OctreeSubRegion

function OctreeSubRegion.New( PositionVector, SizeVector, ParentSubRegion )
	local self = {}
	self.Divided = false
	self.SubRegions = false
	self.Depth = ParentSubRegion and ParentSubRegion.Depth or 0
	self.Position = PositionVector
	self.SizeVector = SizeVector or Settings.MaxNodesPerSubRegion
	self.DataPoints = {}
	self.Parent = setmetatable({}, ParentSubRegion) -- prevents cyclic table issue
	return setmetatable(self, OctreeSubRegion)
end

-- does this octree subregion contain the point
function OctreeSubRegion:Contains( Position )
	local lowerBounds = self.Position - (self.Size / 2)
	local upperBounds = self.Position + (self.Size / 2)
	return (
		Position.X >= lowerBounds.X and Position.X <= upperBounds.X and
		Position.Y >= lowerBounds.Y and Position.Y <= upperBounds.Y and
		Position.Z >= lowerBounds.Z and Position.Z <= upperBounds.Z
	)
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
	-- remove from this subregion if found
	-- also removes unnecessary points from the points list
	local index = 1
	while index < #DataPointsList do
		local dataPoint = DataPointsList[index]
		local dataPointIndex = table.find(self.DataPoints, dataPoint)
		if dataPointIndex then
			-- found in this list, keep it for belows' :RemoveBatch on child subregions
			table.remove(self.DataPoints, dataPointIndex)
			index += 1
		else
			-- does not exist in this subregion (and child regions); remove from list
			table.remove(DataPointsList, dataPointIndex)
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
end

-- check if subregion can be recombined
function OctreeSubRegion:_UpdateDividedState()
	if self.Divided and #self.DataPoints < Settings.MaxNodesPerSubRegion then
		for _, subRegion in ipairs( self.SubRegions ) do
			subRegion:_UpdateDividedState() -- update the lower region before this one
			subRegion.Parent = nil
		end
		self.Divided = false
		self.SubRegions = false -- since the data is no longer cached, clears memory
	end
end

-- add the target data point to the subregion
function OctreeSubRegion:InsertDataPoint( DataPoint )
	-- if it contains this point, add it to this sub region
	if self:Contains( DataPoint.Position ) then
		table.insert(self.DataPoints, DataPoint)
		DataPoint:_SetParentSubRegion( self )
		-- split if limit is reached
		if #self.DataPoints == Settings.MaxNodesPerSubRegion and (self.Depth + 1) < Settings.MaxTreeDepth then
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
end

-- add a batch of data points to the subregion
function OctreeSubRegion:BatchInsertDataPoints( DataPointsList )
	-- only keep those in the list that are within this subregion
	local index = 1
	while index < #DataPointsList do
		local DataPoint = DataPointsList[index]
		if self:Contains( DataPoint.Position ) then
			table.insert(self.DataPoints, DataPoint)
			DataPoint:_SetParentSubRegion( self )
			index += 1
		else
			table.remove(DataPointsList, index)
		end
	end

	if #self.DataPoints == Settings.MaxNodesPerSubRegion and (self.Depth + 1) < Settings.MaxTreeDepth then
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
end

-- // Octree Class // --
local OctreeClass = { ClassName = 'Octree3DMap' }
OctreeClass.__index = OctreeClass

function OctreeClass.New(Position, Size)
	local self = {}
	-- self.Region3DMap = {}
	self.Position = Position
	self.Size = Size
	self.RootRegion = OctreeSubRegion.New(Position, Size, false)
	return setmetatable(self, OctreeClass)
end

-- get the furthest square bounds of the octree
-- BoundPosition : Vector3, BoundSize : Vector3
function OctreeClass:GetOctreeBounds()
	
end

-- get the nearest octree node near this position (include a max distance)
function OctreeClass:GetNearestDataPointAtPosition( Position, maxDistance )
	
end

-- returns an octree node
function OctreeClass:Insert( Position, Data )
	local baseDataPoint = OctreeDataPoint.New(Position, Data)
	self.RootRegion:Insert(baseDataPoint)
end

-- does it contain the octree node
function OctreeClass:Contains( octreeNode )
	
end

-- remove a region node from the octree
function OctreeClass:RemoveNode( regionNode )
	
end

-- clear the octree map
function OctreeClass:Clear()
	for _, dataPoint in ipairs( self.RootRegion.DataPoints ) do
		dataPoint:Remove() -- tell the datapoint to remove itself from the subregion its in
	end
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

return OctreeClass