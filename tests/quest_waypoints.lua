-- Middle-click a quest to follow it: from the quest log, the objective tracker
-- and Questie's tracker; the nearest open objective, then the turn-in; moved on
-- as the quest moves on, gone when it is handed in; Questie's data first, the
-- game's markers without it.
local root = ...
local function noop() end
local realPrint = print

---------------------------------------------------------------------------
-- A small world: two zones side by side on one continent
---------------------------------------------------------------------------
local MAPS = {
    [1429] = { name = "Elwynn Forest", mapType = 3, parent = 947, origin = 0, span = 1000 },
    [1436] = { name = "Westfall", mapType = 3, parent = 947, origin = 1000, span = 1000 },
    [947] = { name = "Eastern Kingdoms", mapType = 2, parent = 0, origin = 0, span = 2000 },
}
Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5 } }
function CreateVector2D(x, y) return { x = x, y = y } end
local playerX, playerY = 400, 600
C_Map = {
    GetMapInfo = function(mapID)
        local info = MAPS[mapID]
        return info and { mapID = mapID, name = info.name, mapType = info.mapType, parentMapID = info.parent } or nil
    end,
    GetBestMapForUnit = function() return 1429 end,
    GetMapPosFromWorldPos = function(_, position) return position.x < 1000 and 1429 or 1436, position end,
    GetMapChildrenInfo = function(mapID)
        if mapID ~= 947 then return {} end
        return { { mapID = 1429 }, { mapID = 1436 } }
    end,
}
function UnitIsDeadOrGhost() return false end
function UnitIsGhost() return false end

---------------------------------------------------------------------------
-- The quest log, as the game reports it
---------------------------------------------------------------------------
local QUESTS = {
    [100] = { title = "Kobold Camp Cleanup", objectives = { { finished = false }, { finished = false } } },
    [200] = { title = "Wolves Across the Border", objectives = { { finished = false } } },
    [300] = { title = "Bounty on Murlocs", objectives = { { finished = false } } },
    [400] = { title = "The Westfall Stew", objectives = { { finished = false } } },
    [500] = { title = "A Lost Letter", objectives = { { finished = false } } },
}
local markers = {} -- the game's own quest markers: [mapID] = { { questID, x, y } }
C_QuestLog = {
    IsOnQuest = function(id) return QUESTS[id] ~= nil and not QUESTS[id].gone end,
    IsComplete = function(id) return QUESTS[id] ~= nil and QUESTS[id].complete == true end,
    GetTitleForQuestID = function(id) return QUESTS[id] and QUESTS[id].title end,
    GetQuestObjectives = function(id) return QUESTS[id] and QUESTS[id].objectives end,
    GetQuestsOnMap = function(mapID) return markers[mapID] or {} end,
}

---------------------------------------------------------------------------
-- Questie: its loader's modules, as far as finding a quest's spot goes
---------------------------------------------------------------------------
-- [questID] = { open = { zone, x, y, name } for each objective, finisher = { ... } }
local SPAWNS = {
    [100] = { open = { { 12, 50, 50, "Kobold Vermin" }, { 12, 80, 20, "Kobold Worker" } },
        finisher = { 12, 40, 61, "Marshal McBride" } },
    [200] = { open = { { 40, 30, 30, "Prowler" } }, finisher = { 12, 45, 45, "Guard Thomas" } },
    [300] = { open = { { 40, 60, 60, "Murloc Raider" } }, finisher = { 40, 50, 50, "Gryan Stoutmantle" } },
}
local refreshed = 0
Questie = { API = { isReady = true, RegisterOnReady = function(callback) callback() end } }
QuestieLoader = { _modules = {
    TrackerMapEligibility = { RefreshAndGetCapabilities = function(id)
        refreshed = refreshed + 1
        if not SPAWNS[id] then return { Id = id }, { canNavigateQuest = false } end
        return { Id = id }, { canNavigateQuest = true }
    end },
    DistanceUtils = { GetNearestSpawnForQuest = function(quest)
        local data, state = SPAWNS[quest.Id], QUESTS[quest.Id]
        if state.complete then
            local f = data.finisher
            return { f[2], f[3] }, f[1], f[4]
        end
        for index, objective in ipairs(state.objectives) do
            local spot = data.open[index]
            if not objective.finished and spot then return { spot[2], spot[3] }, spot[1], spot[4] end
        end
    end },
    ZoneDB = { GetUiMapIdByAreaId = function(_, zone) return ({ [12] = 1429, [40] = 1436 })[zone] end },
} }

---------------------------------------------------------------------------
-- Wayfinder's namespace and the arrow's stand-ins
---------------------------------------------------------------------------
local ns = { db = { waypoints = {}, settings = { showArrow = true, clearOnArrival = true, corpseWaypoint = true,
    questMiddleClick = true } } }
function ns:NewModule(name) self[name] = { name = name }; return self[name] end
function ns:GetCharacterKey() return "Tester-Realm" end
function ns:GetSetting(key) return self.db.settings[key] end
local listeners, events = {}, {}
function ns:On(message, fn) listeners[message] = listeners[message] or {}; table.insert(listeners[message], fn) end
function ns:Fire(message, ...) for _, fn in ipairs(listeners[message] or {}) do fn(...) end end
function ns:RegisterEvent(event, fn) events[event] = events[event] or {}; table.insert(events[event], fn) end
local function event(name, ...) for _, fn in ipairs(events[name] or {}) do fn(name, ...) end end
local function setting(key, value)
    ns.db.settings[key] = value
    ns:Fire("SETTING_CHANGED", key, value)
end
local printed = {}
function ns.Print(message) printed[#printed + 1] = tostring(message) end
function ns.Readable(value) return value ~= nil end
function ns.GetMapRect(mapID)
    local info = MAPS[mapID]
    return info and { cont = 1, origin = info.origin, span = info.span } or nil
end
function ns.MapToWorld(mapID, x, y)
    local info = MAPS[mapID]
    if not info then return nil end
    return 1, info.origin + x * info.span, info.origin + y * info.span
end
function ns.WorldToMapRect(rect, wx, wy)
    return (wx - rect.origin) / rect.span, (wy - rect.origin) / rect.span
end
function ns.GetPlayerWorld() return 1, playerX, playerY, 1429 end
function ns.Distance(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function settle()
    while #timers > 0 do
        local due = timers
        timers = {}
        for _, fn in ipairs(due) do fn() end
    end
end
SOUNDKIT = { UI_MAP_WAYPOINT_REMOVE = "remove", UI_MAP_WAYPOINT_CLICK_TO_PLACE = "place", MAP_PING = "ping" }
local sounds = {}
function PlaySound(sound) sounds[#sounds + 1] = sound end

local function NewFrame()
    local frame = { scripts = {} }
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    function frame:CreateTexture() return NewFrame() end
    function frame:CreateFontString() return NewFrame() end
    function frame:SetTexture() return true end
    return setmetatable(frame, { __index = function(self, key)
        if type(key) ~= "string" or not key:find("^%u") then return nil end
        rawset(self, key, noop)
        return noop
    end })
end
function CreateFrame() return NewFrame() end
UIParent = NewFrame()
StaticPopupDialogs = {}
LinkUtil = { RegisterLinkHandler = noop }
EventUtil = { ContinueOnAddOnLoaded = noop }
function GetPlayerFacing() return 0 end
function print(...) printed[#printed + 1] = table.concat({ ... }, " ") end
MiniQoLRuntime = { Execute = function(_, _, fn) return fn("Wayfinder", ns) end }

-- hooksecurefunc for globals and for methods on a table.
function hooksecurefunc(owner, name, hook)
    if type(owner) == "string" then owner, name, hook = _G, owner, name end
    local original = owner[name]
    owner[name] = function(...)
        local a, b, c = original(...)
        hook(...)
        return a, b, c
    end
end

---------------------------------------------------------------------------
-- Quest UI frames: what the game's and Questie's rows look like to a click
---------------------------------------------------------------------------
local function UIFrame(parent, fields)
    local frame = fields or {}
    frame.parent, frame.hooks, frame.children = parent, {}, {}
    if parent then table.insert(parent.children, frame) end
    function frame:GetParent() return self.parent end
    function frame:GetChildren() return unpack(self.children) end
    function frame:IsForbidden() return false end
    function frame:IsProtected() return self.protected == true end
    function frame:IsMouseClickEnabled() return self.mouse == true end
    function frame:HookScript(script, fn)
        local before = self.hooks[script]
        self.hooks[script] = before and function(...) before(...); fn(...) end or fn
    end
    return frame
end
local function click(frame, button)
    if frame.hooks.OnMouseUp then frame.hooks.OnMouseUp(frame, button or "MiddleButton") end
end

-- The quest log: a title row per quest.
local logRows = {
    UIFrame(nil, { mouse = true, questID = 100 }),
    UIFrame(nil, { mouse = true, questID = 400 }),
    UIFrame(nil, { mouse = true, questID = 500 }),
}
QuestScrollFrame = { titleFramePool = { EnumerateActive = function()
    local index = 0
    return function() index = index + 1; return logRows[index] end
end } }
function QuestLogQuests_Update() end

-- The objective tracker: a block per quest, its header and quest icon clickable,
-- its quest item a protected button.
local blocks = {}
QuestObjectiveTracker = {
    GetExistingBlock = function(_, id) return blocks[id] end,
    UpdateSingle = function() end,
}
local block = UIFrame(nil, { parentModule = QuestObjectiveTracker, id = 200 })
local header = UIFrame(block, { mouse = true })
local poi = UIFrame(block, { mouse = true })
local item = UIFrame(block, { mouse = true, protected = true })
block.poiButton, blocks[200] = poi, block

-- Questie's tracker: a fixed pool of lines, each with a quest and a few buttons.
local function questieQuest(id) return { Id = id, IsComplete = function() return 0 end } end
linePool1 = UIFrame(nil, { mouse = true, Quest = questieQuest(300) })
linePool1.questFocus = UIFrame(linePool1, { mouse = true })
linePool2 = UIFrame(nil, { mouse = true }) -- an unused line

assert(loadfile(root .. "/Modules/Wayfinder/Navigation.lua"))("Wayfinder", ns)
assert(loadfile(root .. "/Modules/Wayfinder/QuestWaypoints.lua"))("Wayfinder", ns)
local Navigation, Quests = ns.Navigation, ns.QuestWaypoints

local function equal(actual, expected, label)
    assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function near(actual, expected, label)
    assert(type(actual) == "number" and math.abs(actual - expected) < 1e-6, label .. ": " .. tostring(actual))
end
local function mark() return Navigation:GetSourceWaypoint("quest") end
local function arrow() return Navigation:GetWaypoint() end

Navigation:OnLogin()
Quests:OnLogin()
QuestLogQuests_Update()
QuestObjectiveTracker:UpdateSingle({ GetID = function() return 200 end })

---------------------------------------------------------------------------
-- 1. The quest log: the nearest open objective
---------------------------------------------------------------------------
local inn = Navigation:AddWaypoint(1, 100, 100, "The inn", 1429)
sounds = {}
click(logRows[1], "LeftButton")
click(logRows[1], "RightButton")
equal(mark(), nil, "left and right clicks are the game's own")
click(logRows[1])
local cleanup = mark()
assert(cleanup, "a middle-click on a quest in the log follows it")
near(cleanup.x, 500, "at its nearest objective")
near(cleanup.y, 500, "on both axes")
equal(cleanup.n, "Kobold Camp Cleanup: Kobold Vermin", "named for the quest and what is there")
equal(cleanup.questID, 100, "kept with the quest's ID, for the next session")
equal(arrow(), cleanup, "the arrow points there")
equal(Quests:GetFollowed(), 100, "the quest is followed")

---------------------------------------------------------------------------
-- 2. Following: moved on as the quest moves on, and gone when handed in
---------------------------------------------------------------------------
Navigation:SetActiveWaypoint(inn)
local before = refreshed
event("QUEST_LOG_UPDATE")
event("QUEST_LOG_UPDATE")
settle()
equal(mark(), cleanup, "progress inside an objective leaves it where it is")
equal(refreshed, before, "without asking Questie again")

QUESTS[100].objectives[1].finished = true
event("QUEST_LOG_UPDATE")
settle()
near(mark().x, 800, "a finished objective: on to the nearest one left")
equal(mark().n, "Kobold Camp Cleanup: Kobold Worker", "named for it")
equal(arrow(), inn, "leaving the arrow where the player put it")

QUESTS[100].complete = true
QUESTS[100].objectives[2].finished = true
event("QUEST_LOG_UPDATE")
settle()
near(mark().x, 400, "complete: to the turn-in")
near(mark().y, 610, "on both axes")
equal(mark().n, "Turn in Kobold Camp Cleanup: Marshal McBride", "named for handing it in")

Navigation:SetActiveWaypoint(mark())
playerX, playerY = 401, 609
Navigation:UpdateArrow()
assert(mark(), "arriving doesn't clear it")
playerX, playerY = 400, 600

sounds = {}
QUESTS[100].gone = true
event("QUEST_TURNED_IN", 100, 450, 0)
equal(mark(), nil, "handed in: the waypoint goes")
equal(Quests:GetFollowed(), nil, "and the quest is no longer followed")
equal(#sounds, 0, "quietly")
equal(arrow(), inn, "the arrow goes back to what is left")

---------------------------------------------------------------------------
-- 3. The objective tracker: the quest icon, the title, never a quest item
---------------------------------------------------------------------------
assert(poi.hooks.OnMouseUp and header.hooks.OnMouseUp, "the block's quest icon and title take the middle-click")
equal(item.hooks.OnMouseUp, nil, "its protected quest item button is left alone")
equal(block.hooks.OnMouseUp, nil, "and nothing that didn't take clicks already")
click(poi)
equal(Quests:GetFollowed(), 200, "the quest icon's quest, found through its block")
near(mark().x, 1300, "its nearest objective, in the next zone")

-- The same quest again: stop.
sounds = {}
click(header)
equal(mark(), nil, "a second middle-click stops following")
equal(Quests:GetFollowed(), nil, "for good")
equal(sounds[1], "remove", "with the usual sound")

---------------------------------------------------------------------------
-- 4. Questie's tracker, and one quest at a time
---------------------------------------------------------------------------
click(logRows[1]) -- quest 100 is gone from the log now
equal(mark(), nil, "a quest no longer in the log is ignored")
click(poi)
local wolves = mark()
click(linePool1.questFocus)
equal(Quests:GetFollowed(), 300, "a button on a Questie line follows the line's quest")
equal(mark().n, "Bounty on Murlocs: Murloc Raider", "at its spot")
local count = 0
for _, rec in ipairs(Navigation:GetWaypoints()) do
    if rec.source == "quest" then count = count + 1 end
end
equal(count, 1, "one quest followed at a time")
assert(mark() ~= wolves, "the new one in the old one's place")
click(linePool2)
equal(Quests:GetFollowed(), 300, "an empty Questie line does nothing")

-- The player removes it from the arrow: no longer followed.
Navigation:SetActiveWaypoint(mark())
Navigation:ClearWaypoint()
equal(Quests:GetFollowed(), nil, "removed by hand, the quest is let go")
QUESTS[300].objectives[1].finished = true
event("QUEST_LOG_UPDATE")
settle()
equal(mark(), nil, "and nothing puts it back")

---------------------------------------------------------------------------
-- 5. Without Questie: the game's own markers
---------------------------------------------------------------------------
Questie.API.isReady = false
markers[1436] = { { questID = 400, x = 0.3, y = 0.4 } }
click(logRows[2])
local stew = mark()
assert(stew, "the game's marker, found on another zone of the continent")
near(stew.x, 1300, "where the game puts it")
equal(stew.n, "The Westfall Stew", "named for the quest")
printed = {}
click(logRows[3])
equal(mark(), stew, "a quest with no known place leaves things as they were")
assert(printed[1] and printed[1]:find("A Lost Letter", 1, true), "and says so: " .. tostring(printed[1]))
Questie.API.isReady = true

---------------------------------------------------------------------------
-- 6. The setting
---------------------------------------------------------------------------
setting("questMiddleClick", false)
equal(mark(), nil, "turned off: the quest is no longer followed")
click(poi)
equal(mark(), nil, "and middle-clicks do nothing")
setting("questMiddleClick", true)
click(poi)
assert(mark(), "on again")

local imported
ns.TargetFinder = { ImportQuest = function(_, id) imported = id end }
function IsShiftKeyDown() return true end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end
click(poi)
equal(imported, 200, "shift-middle imports from Blizzard's tracker")
click(linePool1.questFocus)
equal(imported, 300, "shift-middle imports from Questie's tracker")
equal(Quests:GetFollowed(), 200, "importing targets preserves waypoint following")
function IsShiftKeyDown() return false end

-- A map click selects the actual pin, even when its canvas also receives the
-- release. A map pin can be a native quest POI, an HBD wrapper or an addon frame.
local function visible() return true end
local function opaque() return 1 end
local canvas = UIFrame(nil, { GetAlpha = opaque })
WorldMapFrame = UIFrame(nil, { IsShown = visible, GetMapID = function() return 1429 end,
    GetCanvasContainer = function() return canvas end, ScrollContainer = UIFrame(nil),
    AcquirePin = noop, RemoveAllPinsByTemplate = noop, OnMapChanged = noop })
ns.OpenMapCompat = { IsActive = function() return false end }
ns.DetailView = { IsActive = function() return false end, IsFollowingMap = function() return false end }
ns.QuestAvailability = { IsQuestAvailable = function() return false end }
ns.QuestTurnIns = { IsReady = function(_, id) return C_QuestLog.IsComplete(id) end }
local clock, foci = 0, {}
function GetTime() return clock end
function GetMouseFoci() return foci end
EventUtil.ContinueOnAddOnLoaded = function(_, callback) callback() end
C_Timer.NewTicker = noop
assert(loadfile(root .. "/Modules/Wayfinder/AddonPins.lua"))("Wayfinder", ns)
ns.AddonPins:OnLogin()

local function mapPin(x, y)
    return UIFrame(canvas, { GetMap = function() return WorldMapFrame end,
        GetPosition = function() return x, y end, GetAlpha = opaque, IsVisible = visible,
        GetSize = function() return 16, 16 end })
end
local function mapClick(focus, canvasFirst, expected, wx, wy)
    local count = #Navigation:GetWaypoints()
    clock = clock + 1
    foci = { canvas, focus }
    event("GLOBAL_MOUSE_DOWN", "MiddleButton")
    if canvasFirst then Navigation:PlaceMapClick(1429, .88, .91) end
    event("GLOBAL_MOUSE_UP", "MiddleButton")
    if not canvasFirst then Navigation:PlaceMapClick(1429, .88, .91) end
    equal(#Navigation:GetWaypoints(), count + 1, "one waypoint per map click")
    equal(arrow().n, expected, "the arrow names the selected pin")
    near(arrow().x, wx, "at the selected map position")
    near(arrow().y, wy, "on both axes")
end
local native = mapPin(.28, .36)
native.GetQuestID = function() return 400 end
native.icon = 12345
QUESTS[400].objectives[1].text = "Collect Goretusk Livers"
mapClick(UIFrame(native), true, "The Westfall Stew: Collect Goretusk Livers", 280, 360)
equal(Quests:GetFollowed(), 200, "choosing a map pin preserves the tracked quest")

local hbd = mapPin(.63, .74)
hbd.icon = UIFrame(hbd, { IsObjectType = visible, IsVisible = visible, GetAlpha = opaque,
    GetSize = native.GetSize, data = { Id = 400, QuestData = { Id = 400, name = "The Westfall Stew" },
        ObjectiveIndex = 1, ObjectiveData = { Description = "Goretusk Liver" }, Name = "Goretusk" } })
mapClick(hbd.icon, false, "The Westfall Stew: Goretusk Liver", 630, 740)
local offer = mapPin(.34, .52)
offer.questID = 500
mapClick(offer, false, "A Lost Letter", 340, 520)
hbd.icon.data = { Id = 300, Type = "complete", QuestData = { Id = 300, name = "Bounty on Murlocs" },
    Name = "Gryan Stoutmantle" }
mapClick(hbd.icon, true, "Turn in Bounty on Murlocs: Gryan Stoutmantle", 630, 740)

local polestar = mapPin(.1, .1)
polestar.GetPosition, polestar.GetMap = nil, nil
polestar.data = { x = 47, y = 33, pin = { kind = "objective", header = "Goretusk",
    refs = { { entry = { q = 400, title = "The Westfall Stew" }, name = "Goretusk Liver" } } } }
Polestar = { Pins = { WorldPinOf = function(frame) return frame == polestar and frame.data end } }
mapClick(polestar, false, "The Westfall Stew: Goretusk Liver", 470, 330)
polestar.data.pin.refs[2] = { entry = { q = 500, title = "A Lost Letter" } }
mapClick(polestar, true, "Goretusk", 470, 330)
local service = mapPin(.15, .26)
service.data = { Name = "Innkeeper Heather" }
mapClick(service, false, "Innkeeper Heather", 150, 260)
local relic = mapPin(.61, .82)
GameTooltip = { IsShown = visible, GetOwner = function() return relic end }
GameTooltipTextLeft1 = { GetText = function() return "Weathered Relic" end }
mapClick(relic, true, "Weathered Relic", 610, 820)
mapClick(nil, true, "Elwynn Forest 88.0, 91.0", 880, 910)

local prior, priorCount = arrow(), #Navigation:GetWaypoints()
clock, foci = clock + 1, { native }
event("GLOBAL_MOUSE_DOWN", "MiddleButton")
foci = { hbd.icon }
event("GLOBAL_MOUSE_UP", "MiddleButton")
Navigation:PlaceMapClick(1429, .2, .1)
equal(arrow(), prior, "releasing on a different pin cancels the click")
equal(#Navigation:GetWaypoints(), priorCount, "a cancelled pin click leaves the canvas alone")
local ownPin = UIFrame(canvas, { wayfinderDetailPin = true })
clock, foci = clock + 1, { ownPin }
event("GLOBAL_MOUSE_DOWN", "MiddleButton")
foci = { canvas } -- the pin's own handler can refresh the displayed pins on release
Navigation:PlaceMapClick(1429, .2, .1)
event("GLOBAL_MOUSE_UP", "MiddleButton")
equal(#Navigation:GetWaypoints(), priorCount, "the detail pin's handler owns the click")

QUESTS[400].objectives[2] = { finished = false, text = "Collect Okra" }
equal(Quests:MapPinLabel(400), "The Westfall Stew", "a map pin with ambiguous objectives uses the quest title")
equal(Quests:MapPinLabel(400, nil, nil, false, 2), "The Westfall Stew: Collect Okra", "explicit objective index")

print = realPrint
print("Quest map clicks: named Blizzard, Questie and Polestar pins, exact spawn, one waypoint per click")
print("Quest waypoints: log, tracker icon and Questie lines; nearest objective then turn-in; follows progress, gone when handed in; game markers without Questie")
