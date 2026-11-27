-- World map pins: the map sets each pin's click passthrough when it hands the
-- pin out, and that call is blocked in combat, so opening the map mid-fight
-- must not make it.
local root = ...
local function noop() end

function CreateFromMixins(...)
    local result = {}
    for i = 1, select("#", ...) do
        for key, value in pairs(select(i, ...)) do result[key] = value end
    end
    return result
end
MapCanvasDataProviderMixin = {}
-- As Blizzard_MapCanvas has it: clear, then set the buttons that pass through.
MapCanvasPinMixin = {}
function MapCanvasPinMixin:ShouldMouseButtonBePassthrough(button) return button == "RightButton" end
function MapCanvasPinMixin:CheckMouseButtonPassthrough(...)
    self:SetPassThroughButtons()
    local buttons = {}
    for i = 1, select("#", ...) do
        local button = select(i, ...)
        if self:ShouldMouseButtonBePassthrough(button) then buttons[#buttons + 1] = button end
    end
    self:SetPassThroughButtons(unpack(buttons))
end

function InCombatLockdown() return COMBAT == true end
local active = {}
WorldMapFrame = { AddDataProvider = noop }
function WorldMapFrame:EnumeratePinsByTemplate(template)
    assert(template == "WayfinderMapPinTemplate")
    local index = 0
    return function() index = index + 1; return active[index] end
end
EventUtil = { ContinueOnAddOnLoaded = function(_, fn) fn() end }

local events = {}
local ns = {}
function ns:NewModule(name) self[name] = {}; return self[name] end
function ns:On() end
function ns:RegisterEvent(event, fn) events[event] = fn end
MiniQoLRuntime = { Execute = function(_, _, fn) return fn("Wayfinder", ns) end }
assert(loadfile(root .. "/Modules/Wayfinder/MapPins.lua"))("Wayfinder", ns)
ns.MapPins:OnLogin()

-- A pin the way the map pools them: the protected call fails in combat.
local function Pin()
    local pin = setmetatable({ calls = 0 }, { __index = WayfinderMapPinMixin })
    function pin:SetPassThroughButtons(...)
        assert(not COMBAT, "ADDON_ACTION_BLOCKED: SetPassThroughButtons in combat")
        self.calls, self.buttons = self.calls + 1, { ... }
    end
    active[#active + 1] = pin
    return pin
end

-- Opening the map mid-fight hands out a fresh pin.
COMBAT = true
local first = Pin()
first:CheckMouseButtonPassthrough("RightButton")
assert(first.calls == 0, "nothing protected is called in combat")

-- Once the fight ends it gets its passthrough.
COMBAT = false
events.PLAYER_REGEN_ENABLED()
assert(first.buttons and first.buttons[1] == "RightButton" and #first.buttons == 1, "right clicks pass through after combat")
local calls = first.calls

-- Reused from the pool, in or out of combat, it is left as it is.
first:CheckMouseButtonPassthrough("RightButton")
COMBAT = true
first:CheckMouseButtonPassthrough("RightButton")
COMBAT = false
assert(first.calls == calls, "a pin that already passes right clicks is not set again")

-- Out of combat a new pin is set straight away.
local second = Pin()
second:CheckMouseButtonPassthrough("RightButton")
assert(second.buttons and second.buttons[1] == "RightButton", "a pin made out of combat is set at once")
events.PLAYER_REGEN_ENABLED()
assert(second.calls == 2 and first.calls == calls, "leaving combat does not touch pins that are already set")

-- Tooltips say how far an icon is and which way: world x counts north, y west.
function ns.GetPlayerWorld() return 1, 1000, 1000 end
local function way(x, y, cont) return ns.DistanceAndDirection(cont or 1, x, y) end
assert(way(1240, 1000) == "240 yd north", way(1240, 1000))
assert(way(1000, 760) == "240 yd east", way(1000, 760))
assert(way(1100, 900) == "141 yd northeast", way(1100, 900))
assert(way(900, 1100) == "141 yd southwest", way(900, 1100))
assert(way(1000, 1300) == "300 yd west", way(1000, 1300))
assert(way(700, 1000) == "300 yd south", way(700, 1000))
assert(way(1001, 1002) == "Here", "standing on it")
assert(way(1000, 13000) == "12.0k yd west", way(1000, 13000))
assert(way(1240, 1000, 0) == nil, "nothing for another continent")

---------------------------------------------------------------------------
-- The zone map (Shift+M): Wayfinder's icons, waypoints and the game's quest
-- objectives through a provider of its own, at frame levels that map has
---------------------------------------------------------------------------
local settings = { zoneMap = true, zoneMapQuests = true, iconScale = 1 }
function ns.Readable(value) return value ~= nil end
function ns:GetSetting(key) return settings[key] end
ns.db = { settings = settings }
Enum = { UIMapType = { Continent = 2, Zone = 3 } }
function CreateVector2D(x, y) return { x = x, y = y } end
C_Map = {
    GetMapInfo = function(mapID) if mapID == 1429 then return { mapType = 3, parentMapID = 13 } end end,
    GetMapPosFromWorldPos = function() return 1429 end,
}
local RECT = { cont = 0, top = 5000, left = 5000, width = 1000, height = 1000 }
function ns.GetMapRect(mapID) if mapID == 1429 then return RECT end end
function ns.WorldToMapRect(rect, wx, wy) return (rect.left - wy) / rect.width, (rect.top - wx) / rect.height end
local inn = { c = 0, x = 4600, y = 4700, n = "Innkeeper Farley", cats = { inn = true } }
ns.Categories = { GetVisibleCategory = function(_, rec) return rec == inn and "inn" or nil end }
ns.Database = { Query = function(_, cont, _, _, _, _, add) if cont == 0 then add(inn) end end }
ns.Seeds = { Query = noop }
ns.MinimapTurnIns = { QueryServices = noop }
ns.ServiceLocations = { Select = function(_, entries) return entries end }
local waypoint = { waypoint = true, c = 0, x = 4500, y = 4500, n = "Goldshire" }
ns.Navigation = { GetWaypoints = function() return { waypoint } end }
C_QuestLog = {
    GetQuestsOnMap = function(mapID)
        if mapID ~= 1429 then return {} end
        return { { questID = 7, x = 0.25, y = 0.75 }, { questID = 8, x = 0.5, y = 0.5 } }
    end,
    IsComplete = function(questID) return questID == 8 end,
    GetTitleForQuestID = function(questID) return ({ [7] = "Kobold Camp Cleanup", [8] = "Report to Goldshire" })[questID] end,
}
C_Timer = { After = function(_, fn) fn() end }

local acquired, providers = {}, {}
local zoneMap = { shown = true }
function zoneMap:AddDataProvider(provider) providers[#providers + 1] = provider end
function zoneMap:GetMapID() return 1429 end
function zoneMap:IsShown() return self.shown end
function zoneMap:RemoveAllPinsByTemplate() acquired = {} end
function zoneMap:AcquirePin(template, rec, catID, x, y)
    acquired[#acquired + 1] = { template = template, rec = rec, cat = catID, x = x, y = y }
end
zoneMap.ScrollContainer = { GetWidth = function() return 300 end, GetHeight = function() return 200 end,
    GetViewRect = function() return { left = 0, right = 1, top = 0, bottom = 1 } end }
BattlefieldMapFrame = zoneMap
ns.MapPins:AddToZoneMap()
ns.MapPins:AddToZoneMap()
assert(#providers == 1, "one provider on the zone map, however often it's asked")
local zoneProvider = providers[1]
function zoneProvider:GetMap() return zoneMap end
zoneProvider:RefreshAllData()
local byKind = {}
for _, pin in ipairs(acquired) do
    assert(pin.template == "WayfinderMapPinTemplate", "Wayfinder's own pins")
    byKind[pin.cat] = byKind[pin.cat] or {}
    table.insert(byKind[pin.cat], pin)
end
assert(byKind.inn and byKind.inn[1].rec == inn and math.abs(byKind.inn[1].x - 0.3) < 1e-9
    and math.abs(byKind.inn[1].y - 0.4) < 1e-9, "the innkeeper where it stands")
assert(byKind.waypoint and byKind.waypoint[1].rec == waypoint, "the waypoint")
assert(byKind.questObjective and #byKind.questObjective == 1, "one quest objective: the finished quest's turn-in is Wayfinder's own icon")
local objective = byKind.questObjective[1]
assert(objective.rec.questID == 7 and objective.rec.n == "Kobold Camp Cleanup", "named for its quest")
assert(objective.x == 0.25 and objective.y == 0.75, "where the game marks it")
assert(math.abs(objective.rec.x - 4250) < 1e-9 and math.abs(objective.rec.y - 4750) < 1e-9, "and where that is in the world")
settings.zoneMapQuests = false
zoneProvider:RefreshAllData()
for _, pin in ipairs(acquired) do assert(pin.cat ~= "questObjective", "quest objectives have their own switch") end
settings.zoneMap = false
zoneProvider:RefreshAllData()
assert(#acquired == 0, "the zone map setting off: nothing")
settings.zoneMap, settings.zoneMapQuests = true, true

-- A frame level the zone map doesn't have would put a pin under the explored-area art.
local levels = { definitions = { PIN_FRAME_LEVEL_AREA_POI = {}, PIN_FRAME_LEVEL_CORPSE = {}, PIN_FRAME_LEVEL_ENCOUNTER = {} } }
function zoneMap:GetPinFrameLevelsManager() return levels end
ns.OpenMapCompat = { RaisePin = noop }
ns.Categories.ApplyIcon = noop
local function TestPin(rec, catID)
    local pin = setmetatable({ Icon = { SetAtlas = noop, SetTexture = noop, SetAlpha = noop },
        Highlight = { SetAtlas = noop, SetTexture = noop } }, { __index = WayfinderMapPinMixin })
    function pin:GetMap() return zoneMap end
    function pin:UseFrameLevelType(kind) self.level = kind end
    pin.SetSize, pin.SetPosition = noop, noop
    pin:OnAcquired(rec, catID, 0.5, 0.5)
    return pin
end
C_Texture = { GetAtlasInfo = function() return nil end }
assert(TestPin(waypoint, "waypoint").level == "PIN_FRAME_LEVEL_CORPSE", "the waypoint on the zone map's top level")
assert(TestPin(objective.rec, "questObjective").level == "PIN_FRAME_LEVEL_ENCOUNTER", "quest objectives just under it")
assert(TestPin(inn, "inn").level == "PIN_FRAME_LEVEL_AREA_POI", "icons with the map's points of interest")
levels.definitions.PIN_FRAME_LEVEL_WAYPOINT_LOCATION = {}
assert(TestPin(waypoint, "waypoint").level == "PIN_FRAME_LEVEL_WAYPOINT_LOCATION", "the world map's own level where the map has it")
print("World map pins: no protected calls in combat, the zone map provider, passthrough caught up afterwards, tooltip distance and direction passed")
