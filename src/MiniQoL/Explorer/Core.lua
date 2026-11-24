local _, ns = ...
local Explorer = { loaders = {} }
ns.Explorer = Explorer

function Explorer:Data(key)
    local load = self.loaders[key]
    if load then
        local data = load()
        self.loaders[key] = nil
        self[key] = data
    end
    return self[key]
end

local maps = {}
local function MapInfo(mapID)
    if not mapID or mapID == 0 then return end
    if maps[mapID] == nil then maps[mapID] = C_Map.GetMapInfo(mapID) or false end
    return maps[mapID] or nil
end

function Explorer.MapName(mapID)
    local info = MapInfo(mapID)
    return info and info.name
end

local zones = {}
function Explorer.Zone(mapID)
    if not mapID then return end
    if zones[mapID] then return zones[mapID] end
    local original = mapID
    local zone = mapID
    for _ = 1, 8 do
        local info = MapInfo(mapID)
        if not info or not info.mapType or info.mapType < 3 then break end
        zone = mapID
        mapID = info.parentMapID
    end
    zones[original] = zone
    return zone
end

function Explorer.Located(mapID, x, y)
    return mapID and mapID > 0 and x and y and (x ~= 0 or y ~= 0)
        and x >= 0 and x <= 1 and y >= 0 and y <= 1
end

local function ToWorld(mapID, x, y)
    if Wayfinder and Wayfinder.MapToWorld then return Wayfinder.MapToWorld(mapID, x, y) end
    local continent, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    if pos then return continent, pos:GetXY() end
end

function Explorer.PlayerPosition()
    local mapID = C_Map.GetBestMapForUnit("player")
    local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    local player = { mapID = mapID, zone = Explorer.Zone(mapID) }
    if position then
        local x, y = position:GetXY()
        if Explorer.Located(mapID, x, y) then
            player.continent, player.x, player.y = ToWorld(mapID, x, y)
        end
    end
    return player
end

-- Map position is the primary tiebreaker when the client has no world
-- coordinates for a floor or when a result is on another continent.
function Explorer.Distance(player, mapID, x, y)
    if not Explorer.Located(mapID, x, y) then return 3, math.huge end
    local tier = mapID == player.mapID and 0 or (Explorer.Zone(mapID) == player.zone and 0 or 2)
    if player.continent then
        local continent, wx, wy = ToWorld(mapID, x, y)
        if continent == player.continent then
            local dx, dy = wx - player.x, wy - player.y
            return math.min(tier, 1), (dx * dx + dy * dy) ^ 0.5
        end
    end
    return tier, math.huge
end

function Explorer.OwnFaction(faction, mine)
    return not faction or faction == "Neutral" or faction == mine
end

function Explorer.SourceLabel(source)
    local labels = Explorer.sourceLabels
    local verb = labels[source[1]] or source[1]
    return source[5] and (verb .. " " .. source[5]) or verb
end

Explorer.sourceLabels = {
    vendor = "Sold by", quest = "Quest reward from", drop = "Dropped by", rare = "Dropped by",
    dungeon = "Dungeon drop from", chest = "Found in", container = "Found in", world = "World drop from",
    crafted = "Made with",
}

function Explorer.Waypoint(result)
    if InCombatLockdown() then ns:Print("Set this waypoint after combat."); return end
    local navigation = Wayfinder and Wayfinder.db and Wayfinder.Navigation
    if not navigation then ns:Print("Enable Wayfinder to set a waypoint."); return end
    navigation:SetWaypointOnMap(result.mapID, result.x, result.y, result.name)
end
