--!strict
--services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
--packages
local Maid = require(script.Parent.Maid)
--modules
--types
-- type CustomScriptSignal<any...> = () -> {
-- 	Connect: () -> {
-- 		Disconnect: () -> (),
-- 	},
-- }

export type Area = {
	Active: boolean,
	CFrame: CFrame,
	Size: Vector3,
	Shape: Enum.PartType,
}

export type CustomScriptSignal<T...> = {
	Connect: () -> { Disconnect: () -> () },
}
export type Zone = {
	__index: Zone,

	new: () -> Zone, -- -> (zone, id)
	get: (id: string) -> Zone,

	_maid: Maid.Maid,

	_partsInArea: {
		[Area]: {
			[BasePart]: boolean,
			getBasePart: (BasePart) -> boolean,
			setBasePart: (BasePart, boolean?) -> (),
			proxy: {},
		},
	},
	_trackedParts: { [number]: BasePart },
	_areas: { Area },

	_enterListeners: { (Area, BasePart) -> () },
	_leftListeners: { (Area, BasePart) -> () },

	Id: string,

	_update: (Zone) -> (),
	_handlePartsInAreaDataOnListened: (Zone, area: Area, basePart: BasePart, isEntered: boolean?) -> (),

	OnPartEntered: (Zone, onEvent: (Area, BasePart) -> ()) -> CustomScriptSignal<(Area, BasePart) -> ()>,
	OnPartLeft: (Zone, (area: Area, part: BasePart) -> ()) -> CustomScriptSignal<(Area, BasePart) -> ()>,

	AddArea: (Zone, cf: CFrame, size: Vector3, shape: Enum.PartType, active: boolean) -> Area,
	RemoveArea: (Zone, area: Area) -> (),

	SetAreaActive: (Zone, area: Area, bool: boolean) -> (),

	AddTrackedParts: (Zone, part: BasePart) -> (),
	RemoveTrackedParts: (Zone, part: BasePart) -> (),

	GetPartsInsideArea: (Zone, Area) -> { BasePart },

	Destroy: (Zone) -> (),
}
--constants
--remotes
--variables
local zones = {}
--references
--local functions
local function deepClear(tbl: { [any]: any })
	setmetatable(tbl, nil)
	for k, v in pairs(tbl) do
		if type(v) ~= "table" then
			tbl[k] = nil
		else
			deepClear(v)
		end
	end
end

local function createArea(cf: CFrame, size: Vector3, shape: Enum.PartType, active: boolean): Area
	return {
		CFrame = cf,
		Size = size,
		Shape = shape,
		Active = active,
	}
end

local function createScriptSignal<T...>(fn: () -> () -> ()): CustomScriptSignal<T...>
	return {
		Connect = function()
			local disconnect = fn()

			return {
				Disconnect = disconnect,
			}
		end,
	}
end

--class
local zone: Zone = {} :: any
zone.__index = zone

function posIsInArea(area: Area, pos: Vector3)
	local relativePos = area.CFrame:PointToObjectSpace(pos)
	local defaultResult = math.abs(relativePos.X) < area.Size.X * 0.5
		and math.abs(relativePos.Y) < area.Size.Y * 0.5
		and math.abs(relativePos.Z) < area.Size.Z * 0.5

	local radius = if area.Shape == Enum.PartType.Ball then pos.Y * 0.5 else nil
	local circlePartTypeResult = if radius
		then (relativePos.X < radius and relativePos.Y < radius and relativePos.Z < radius)
		else false

	return if area.Shape == Enum.PartType.Ball then circlePartTypeResult else defaultResult
end

function zone.new()
	local self: Zone = setmetatable({}, zone) :: any

	local maid = Maid.new()

	local function initZone()
		maid:GiveTask(RunService.Heartbeat:Connect(function()
			self:_update()
		end))
	end

	self._maid = Maid.new()
	self._areas = {}
	self._trackedParts = {}
	self._partsInArea = {}

	self._enterListeners = {}
	self._leftListeners = {}

	local id = HttpService:GenerateGUID(false)
	self.Id = id

	zones[id] = zone

	initZone()

	return self, id
end

function zone.get(id: string)
	for _, zone in pairs(zones) do
		if zone.Id == id then
			return zone
		end
	end

	error("[Zone module error]: invalid zone id")
end

function zone:_update()
	for _, part in pairs(self._trackedParts) do
		for _, area in pairs(self._areas) do
			local partsInAreaData = self._partsInArea[area]
			if posIsInArea(area, part.Position) then
				partsInAreaData.setBasePart(part, true)
				-- partsInAreaData[part] = true
			else
				partsInAreaData.setBasePart(part, nil)
				-- partsInAreaData[part] = nil
			end
		end
	end
end

function zone:_handlePartsInAreaDataOnListened(area: Area, basePart: BasePart, isEntered: boolean?)
	local partsInAreaData = self._partsInArea[area]

	if isEntered then
		partsInAreaData[basePart] = isEntered

		local enterAreaListeners = self._enterListeners
		if enterAreaListeners and area.Active then
			for _, listener in pairs(enterAreaListeners) do
				listener(area, basePart)
			end
		end
	else
		partsInAreaData[basePart] = nil

		local leftAreaListeners = self._leftListeners
		if leftAreaListeners and area.Active then
			for _, listener in pairs(leftAreaListeners) do
				listener(area, basePart)
			end
		end
	end
end
function zone:AddArea(cf: CFrame, size: Vector3, shape: Enum.PartType, active: boolean)
	local area = createArea(cf, size, shape, active)
	table.insert(self._areas, area)

	local partsInAreaData = {}
	local proxy = setmetatable({}, {
		__index = function(tbl, k: BasePart)
			return partsInAreaData[k]
		end,
		__newindex = function(tbl, k: BasePart, v: boolean?)
			-- if v then
			-- 	partsInAreaData[k] = v

			-- 	local enterAreaListeners = self._enterListeners
			-- 	if enterAreaListeners and area.Active then
			-- 		for _, listener in pairs(enterAreaListeners) do
			-- 			listener(area, k)
			-- 		end
			-- 	end
			-- else
			-- 	partsInAreaData[k] = nil

			-- 	local leftAreaListeners = self._leftListeners
			-- 	if leftAreaListeners and area.Active then
			-- 		for _, listener in pairs(leftAreaListeners) do
			-- 			listener(area, k)
			-- 		end
			-- 	end
			-- end
			self:_handlePartsInAreaDataOnListened(area, k, v)
		end,
	}) :: any

	partsInAreaData.proxy = proxy

	partsInAreaData.getBasePart = function(basePart: BasePart): boolean
		return partsInAreaData.proxy[basePart] or false
	end

	partsInAreaData.setBasePart = function(basePart: BasePart, bool: boolean?)
		local bool0 = partsInAreaData.proxy[basePart]
		if bool0 ~= bool then
			partsInAreaData.proxy[basePart] = bool
		end
	end

	self._partsInArea[area] = partsInAreaData

	return area
end

function zone:RemoveArea(area: Area)
	local k = table.find(self._areas, area)
	assert(k, "[Zone module error]: invalid area argument")

	table.remove(self._areas, k)
	deepClear(self._partsInArea[area])
	self._partsInArea[area] = nil
end

function zone:SetAreaActive(area: Area, bool: boolean)
	local partsInAreaData = self._partsInArea[area]

	area.Active = bool

	if bool == false then
		for k, v in pairs(partsInAreaData) do
			self:_handlePartsInAreaDataOnListened(area, k, nil)
		end
	end
end

function zone:AddTrackedParts(part: BasePart)
	table.insert(self._trackedParts, part)
end

function zone:RemoveTrackedParts(part: BasePart)
	local k = assert(table.find(self._trackedParts, part), "[Zone module error]: invalid part")
	table.remove(self._trackedParts, k)
end

function zone:OnPartEntered(onEvent: (Area, BasePart) -> ())
	-- local scriptSignal = createScriptSignal(function(onEvent: (area: Area, part: BasePart) -> ())
	local scriptSignal = createScriptSignal(function()
		table.insert(self._enterListeners, onEvent)

		return function()
			-- local k = table.find(_listeners, onEvent)
			local k = table.find(self._enterListeners, onEvent)
			if k then
				table.remove(self._enterListeners, k)
			else
				warn("[Zone module warning]: listener is already removed!")
			end
			-- end
		end
	end)
	return scriptSignal
end

function zone:OnPartLeft(onEvent: (Area, BasePart) -> ())
	-- local scriptSignal = createScriptSignal(function(onEvent: (area: Area, part: BasePart) -> ())
	local scriptSignal = createScriptSignal(function()
		table.insert(self._leftListeners, onEvent)

		return function()
			-- local k = table.find(_listeners, onEvent)
			local k = table.find(self._leftListeners, onEvent)
			if k then
				table.remove(self._leftListeners, k)
			else
				warn("[Zone module warning]: listener is already removed!")
			end
			-- end
		end
	end)
	return scriptSignal
end
-- function zone:OnPartLeft(area: Area, onEvent: (area: Area, part: BasePart) -> ())
-- 	-- local _listeners = self._leftListeners[area] or {}
-- 	-- self._leftListeners[area] = _listeners

-- 	-- table.insert(_listeners, onEvent)

-- 	-- return {
-- 	-- 	Disconnect = function()
-- 	-- 		local k = table.find(_listeners, onEvent)
-- 	-- 		if k then
-- 	-- 			table.remove(_listeners, k)
-- 	-- 		else
-- 	-- 			warn("[Zone module warning]: listener is already removed!")
-- 	-- 		end
-- 	-- 	end,
-- 	-- }

-- 	local scriptSignal = createScriptSignal(function()
-- 		local _listeners = self._leftListeners[area] or {}
-- 		self._leftListeners[area] = _listeners
-- 		table.insert(_listeners, onEvent)

-- 		return function()
-- 			-- local k = table.find(_listeners, onEvent)
-- 			local k = table.find(_listeners, onEvent)
-- 			if k then
-- 				table.remove(_listeners, k)
-- 			else
-- 				warn("[Zone module warning]: listener is already removed!")
-- 			end
-- 			-- end
-- 		end
-- 	end)
-- 	return scriptSignal
-- end
function zone:GetPartsInsideArea(area: Area)
	local partsInArea = assert(self._partsInArea[area], "[Zone module error]: invalid area")

	local parts = {}
	for k, v in pairs(partsInArea) do
		if typeof(k) == "Instance" and k:IsA("BasePart") and v == true then
			table.insert(parts, k)
		end
	end
	return parts
end

function zone:Destroy()
	zones[zone.Id] = nil

	self._maid:Destroy()
	deepClear(self)

	setmetatable(self, nil)
end

return zone
