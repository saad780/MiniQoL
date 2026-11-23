-- Private namespace and client data for Wayfinder's walking router.
local _, ns = ...
local Walking = { Nav = {}, PathData = {}, Maps = {}, Compat = {} }
ns.Walking = Walking

local zones = {}

function Walking.Maps.RegisterZoneLevels(records)
	zones = records
end

function Walking.Maps.EachZoneLevels()
	return pairs(zones)
end

function Walking.Maps.GetZoneLevels(mapID)
	local zone = zones[mapID]
	if zone then return zone[1], zone[2], zone[5] end
end

function Walking.RegisterEvent(event, handler)
	ns:RegisterEvent(event, handler)
end

Walking.Compat.GetPlayerWorldPosition = ns.GetPlayerWorld

function Walking.Compat.GetPlayerFaction()
	if ns.playerFaction == 1 then return "Alliance" end
	if ns.playerFaction == 2 then return "Horde" end
end

function Walking.Compat.GetPlayerLevel()
	local level = UnitLevel("player")
	if ns.Readable(level) and type(level) == "number" and level > 0 then return level end
end

function Walking.Compat.GetPlayerUnitPosition()
	if not UnitPosition then return end
	local ok, x, y, z, instance = pcall(UnitPosition, "player")
	if ok and ns.Readable(instance) and ns.Readable(z) and type(z) == "number" and z ~= 0 then
		return x, y, z, instance
	end
end

function Walking.Compat.IsOnTaxi()
	local taxi = UnitOnTaxi and UnitOnTaxi("player")
	return ns.Readable(taxi) and taxi == true
end

function Walking.Compat.IsIndoors()
	local indoors = IsIndoors and IsIndoors()
	if ns.Readable(indoors) then return indoors end
end
