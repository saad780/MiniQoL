-- Standing in for TomTom: the /way formats guides hand out, the table other
-- addons call into, and the list of waypoints that now stands behind the arrow.
local root = ...
local function noop() end
local realPrint = print

---------------------------------------------------------------------------
-- A small world: three zones, each with its own band of world coordinates
---------------------------------------------------------------------------
local SPAN = 1000
local MAPS = {
    [1429] = { name = "Elwynn Forest", mapType = 3, origin = 0 },
    [84] = { name = "Stormwind City", mapType = 3, origin = 10000 },
    [1411] = { name = "Durotar", mapType = 3, origin = 20000 },
    [947] = { name = "Azeroth", mapType = 2, origin = 30000 },
}

Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5 } }
function CreateVector2D(x, y) return { x = x, y = y } end

local children = {}
for mapID, info in pairs(MAPS) do
    if mapID ~= 947 then
        children[#children + 1] = { mapID = mapID, name = info.name, mapType = info.mapType }
    end
end
-- Enough entries that the walk is trusted rather than falling back to scanning
-- every id. These name maps no waypoint can sit on, and must be passed over.
for index = 1, 60 do
    children[#children + 1] = { mapID = 50000 + index, name = "Scenario " .. index, mapType = 4 }
end

C_Map = {
    GetMapInfo = function(mapID)
        local info = MAPS[mapID]
        return info and { mapID = mapID, name = info.name, mapType = info.mapType } or nil
    end,
    GetMapChildrenInfo = function(mapID) return mapID == 947 and children or nil end,
    GetBestMapForUnit = function() return 1429 end,
    GetMapPosFromWorldPos = function(_, position)
        for mapID, info in pairs(MAPS) do
            if mapID ~= 947 and position.x >= info.origin and position.x < info.origin + SPAN then
                return mapID, position
            end
        end
        return 947, position
    end,
}

local playerX, playerY = 400, 600

local ns = { db = { waypoints = {}, settings = { showArrow = true, clearOnArrival = false } } }
function ns:NewModule(name) self[name] = { name = name }; return self[name] end
function ns:GetCharacterKey() return "Tester-Realm" end
function ns:GetSetting(key) return self.db.settings[key] end
function ns:On() end
function ns:RegisterEvent() end
function ns:Fire() end
local printed = {}
function ns.Print(message) printed[#printed + 1] = tostring(message) end
function ns.Readable() return true end
function ns.Debug() end
function print(...)
    local parts = {}
    for index = 1, select("#", ...) do parts[#parts + 1] = tostring(select(index, ...)) end
    printed[#printed + 1] = table.concat(parts, " ")
end

function ns.GetMapRect(mapID)
    local info = MAPS[mapID]
    return info and { cont = 1, origin = info.origin } or nil
end
function ns.MapToWorld(mapID, x, y)
    local info = MAPS[mapID]
    if not info then return nil end
    return 1, info.origin + x * SPAN, info.origin + y * SPAN
end
function ns.WorldToMapRect(rect, wx, wy)
    return (wx - rect.origin) / SPAN, (wy - rect.origin) / SPAN
end
function ns.GetPlayerWorld() return 1, playerX, playerY, 1429, playerX / SPAN, playerY / SPAN end
function ns.Distance(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

---------------------------------------------------------------------------
-- Enough of the client to build the arrow and open a menu
---------------------------------------------------------------------------
local NewFrame
NewFrame = function()
    local frame = { scripts = {} }
    function frame:SetScript(event, handler) self.scripts[event] = handler end
    function frame:HookScript(event, handler) self.scripts[event] = handler end
    function frame:GetScript(event) return self.scripts[event] end
    function frame:RegisterForClicks(...) self.clicks = { ... } end
    function frame:CreateTexture() return NewFrame() end
    function frame:CreateFontString() return NewFrame() end
    function frame:SetTexture() return true end
    function frame:SetText(value) self.text = value end
    function frame:IsShown() return self.shown == true end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    -- Anything else the client would answer is a no-op, but only the methods:
    -- fields the code caches on a frame have to read back as nothing at first.
    return setmetatable(frame, { __index = function(self, key)
        if type(key) ~= "string" or not key:find("^%u") then return nil end
        rawset(self, key, noop)
        return noop
    end })
end
function CreateFrame() return NewFrame() end
UIParent = NewFrame()
StaticPopupDialogs = {}
function StaticPopup_Show() end
SlashCmdList = {}
LinkUtil = { RegisterLinkHandler = noop }
EventUtil = { ContinueOnAddOnLoaded = noop }
C_Timer = { After = function(_, fn) fn() end }
function hooksecurefunc() end
function GetPlayerFacing() return 0 end
function GetTime() return 0 end
C_AddOns = { IsAddOnLoaded = function(name) return name == "PretendTomTom" end }

local menu
local function MenuRoot()
    local builder = {}
    function builder:CreateTitle(text) menu.title = text end
    function builder:CreateRadio(text, selected, click)
        local row = { text = text, selected = selected, click = click, initializers = {} }
        function row:AddInitializer(fn) self.initializers[#self.initializers + 1] = fn end
        menu.rows[#menu.rows + 1] = row
        return row
    end
    function builder:CreateButton(text, click)
        local button = { text = text, click = click }
        menu.buttons[#menu.buttons + 1] = button
        return button
    end
    function builder:CreateDivider() end
    return builder
end
MenuUtil = { CreateContextMenu = function(owner, build)
    menu = { owner = owner, rows = {}, buttons = {} }
    build(owner, MenuRoot())
end }
Menu = { GetManager = function()
    return { CloseMenus = function() menu = nil end }
end }

MiniQoLRuntime = { Execute = function(_, _, fn) return fn("Wayfinder", ns) end }

---------------------------------------------------------------------------
-- A waypoint left behind by the builds that kept only one
---------------------------------------------------------------------------
ns.db.waypoints["Tester-Realm"] = { waypoint = true, c = 1, x = 450, y = 650, m = 1429,
    n = "Old waypoint", where = "Elwynn Forest 45.0, 65.0", cats = {} }

assert(loadfile(root .. "/Modules/Wayfinder/Navigation.lua"))("Wayfinder", ns)
assert(loadfile(root .. "/Modules/Wayfinder/TomTom.lua"))("Wayfinder", ns)
local Navigation, Compat = ns.Navigation, ns.TomTomCompat

local function equal(actual, expected, label)
    assert(actual == expected, (label or "value") .. ": " .. tostring(actual))
end
local function near(actual, expected, label)
    assert(type(actual) == "number" and math.abs(actual - expected) < 1e-6,
        (label or "value") .. ": " .. tostring(actual))
end
local function named(index) return (Navigation:GetWaypoints()[index] or {}).n end
local function said(text)
    for _, line in ipairs(printed) do
        if line:find(text, 1, true) then return true end
    end
    return false
end
local function forget() printed = {} end

Navigation:OnLogin()
equal(#Navigation:GetWaypoints(), 1, "the old waypoint survived")
equal(Navigation:GetWaypoint().n, "Old waypoint", "and the arrow is still on it")
local saved = ns.db.waypoints["Tester-Realm"]
equal(type(saved.list), "table", "it is saved as a list now")
equal(saved.active, 1, "with the arrow's place recorded")
assert(Navigation:GetWaypoint().uid, "every waypoint gets a handle")
Navigation:ClearAllWaypoints()

---------------------------------------------------------------------------
-- 1. Taking over TomTom's commands and table
---------------------------------------------------------------------------
Compat:OnInitialize()
equal(TomTom, ns.TomTomShim, "the TomTom table is published")
equal(SLASH_WAYFINDERWAY1, "/way", "/way answers")
equal(SLASH_WAYFINDERWAY2, "/cway", "/cway answers")
equal(SLASH_WAYFINDERWAYBACK1, "/wayb", "/wayb answers")
assert(type(SlashCmdList.WAYFINDERWAY) == "function", "and the handler is wired")

local way = SlashCmdList.WAYFINDERWAY

---------------------------------------------------------------------------
-- 2. Every shape of /way a guide might hand you
---------------------------------------------------------------------------
way("42.1 65.3 Goldshire Inn")
equal(#Navigation:GetWaypoints(), 1, "coordinates in the zone you are in")
local first = Navigation:GetWaypoint()
equal(first.n, "Goldshire Inn", "the label is kept")
near(first.x, 421, "placed where the coordinates say")
near(first.y, 653, "on both axes")

way("[51.2, 30.4]")
equal(#Navigation:GetWaypoints(), 2, "bracketed, comma separated coordinates")
equal(Navigation:GetWaypoint().n, "Elwynn Forest 51.2, 30.4", "unnamed points describe themselves")

way("Stormwind City 42 65 The bank")
equal(#Navigation:GetWaypoints(), 3, "a zone by name")
equal(Navigation:GetWaypoint().m, 84, "resolved to that zone")
way("durotar 10 20")
equal(Navigation:GetWaypoint().m, 1411, "an unambiguous prefix is enough")
way("#1429 70 70 By map id")
equal(Navigation:GetWaypoint().m, 1429, "a map id works too")
equal(#Navigation:GetWaypoints(), 5, "five waypoints stand together")
equal(Navigation:GetWaypoint().n, "By map id", "the newest takes the arrow")
equal(named(1), "Goldshire Inn", "and the first is still on the map")

way("70 70 By map id")
equal(#Navigation:GetWaypoints(), 5, "the same place is not added twice")

forget()
way("nowhere at all")
assert(said("/wayb"), "unreadable input prints the usage")
forget()
way("Fakeland 10 20")
assert(said("No zone called 'Fakeland'"), "an unknown zone says so")

---------------------------------------------------------------------------
-- 3. Reset, by zone and altogether
---------------------------------------------------------------------------
forget()
way("reset stormwind city")
equal(#Navigation:GetWaypoints(), 4, "one zone's waypoints go")
assert(said("Stormwind City"), "and it says which zone")
forget()
way("list")
assert(said("4 waypoints"), "the list prints what is set")
assert(said("Durotar"), "naming where each one is")
way("reset all")
equal(#Navigation:GetWaypoints(), 0, "reset all empties it")
equal(Navigation:GetWaypoint(), nil, "and the arrow has nothing to follow")

---------------------------------------------------------------------------
-- 4. /wayb, right where you stand
---------------------------------------------------------------------------
SlashCmdList.WAYFINDERWAYBACK("Camp")
equal(#Navigation:GetWaypoints(), 1, "a waypoint where you stand")
equal(Navigation:GetWaypoint().x, playerX, "exactly where you stand")
equal(Navigation:GetWaypoint().n, "Camp", "named as asked")
Navigation:ClearAllWaypoints()

---------------------------------------------------------------------------
-- 5. The table Questie and the rest call into
---------------------------------------------------------------------------
local uid = TomTom:AddWaypoint(1429, 0.42, 0.65, { title = "Kill ten rats", crazy = true })
assert(type(uid) == "table", "AddWaypoint hands back a handle")
equal(uid[1], 1429, "shaped the way TomTom's is")
equal(uid.desc, "Kill ten rats", "carrying the description")
equal(#Navigation:GetWaypoints(), 1, "and a waypoint exists")
equal(Navigation:GetWaypoint().n, "Kill ten rats", "named by the caller")
assert(TomTom:IsValidWaypoint(uid), "the handle is live")
assert(TomTom:WaypointExists(1429, 0.42, 0.65, "Kill ten rats"), "and can be asked about")
assert(not TomTom:WaypointExists(1429, 0.9, 0.9, "Elsewhere"), "somewhere else has none")

-- Several objectives at once is the whole point of keeping a list.
local second = TomTom:AddWaypoint(1429, 0.80, 0.20, { title = "Objective two" })
local third = TomTom:AddWaypoint(1429, 81, 21, { title = "Objective three" })
equal(#Navigation:GetWaypoints(), 3, "every objective stands")
near(Navigation:GetWaypoints()[3].x, 810, "percentages are taken as well as fractions")

assert(TomTom:SetCrazyArrow(uid, 10, "Kill ten rats"), "the arrow can be aimed")
equal(Navigation:GetWaypoint().n, "Kill ten rats", "at the one that was asked for")
equal(#Navigation:GetWaypoints(), 3, "and nothing else moved")

playerX, playerY = 815, 215
equal(TomTom:GetClosestWaypoint(), third, "the closest is the one you are standing by")
near(TomTom:GetDistanceToWaypoint(third), math.sqrt(50), "distances come back in yards")
playerX, playerY = 400, 600

assert(TomTom:RemoveWaypoint(second), "a single waypoint can be taken back")
equal(#Navigation:GetWaypoints(), 2, "and only that one goes")
equal(TomTom:RemoveWaypoint(second), false, "removing it twice changes nothing")
TomTom:ClearAllWaypoints()
equal(#Navigation:GetWaypoints(), 0, "ClearAllWaypoints empties it")

---------------------------------------------------------------------------
-- 6. The arrow: middle-click removes one, right-click lists them all
---------------------------------------------------------------------------
way("10 10 First")
way("20 20 Second")
way("30 30 Third")
local arrow = Navigation.arrow
assert(arrow, "the arrow was built")
local clicks = {}
for _, button in ipairs(arrow.clicks) do clicks[button] = true end
assert(clicks.MiddleButtonUp and clicks.RightButtonUp, "the arrow takes both buttons")

equal(Navigation:GetWaypoint().n, "Third", "the arrow is on the newest")
arrow.scripts.OnClick(arrow, "MiddleButton")
equal(#Navigation:GetWaypoints(), 2, "middle-click removes the one it is on")
assert(Navigation:GetWaypoint().n ~= "Third", "and the arrow moves on")

arrow.scripts.OnClick(arrow, "RightButton")
assert(menu and #menu.rows == 2, "right-click lists what is left")
assert(menu.rows[1].text:find("First", 1, true) == 1, "each waypoint has a row")
assert(menu.rows[1].text:find("yd", 1, true), "with how far away it is")
equal(menu.title, "2 waypoints", "and a count at the top")
assert(menu.buttons[#menu.buttons].text:find("Clear all", 1, true), "clearing them all is offered")

menu.rows[1].click()
equal(Navigation:GetWaypoint().n, "First", "a row takes the arrow")
equal(#Navigation:GetWaypoints(), 2, "and removes nothing")
assert(menu.rows[1].selected(), "the row shows which one the arrow is on")

-- The x on a row removes exactly that waypoint.
arrow.scripts.OnClick(arrow, "RightButton")
local row = menu.rows[2]
equal(row.text:find("Second", 1, true), 1, "the second row is the second waypoint")
equal(#row.initializers, 1, "the row is given a remove button")
local rowFrame = NewFrame()
row.initializers[1](rowFrame)
local remove = rowFrame.wayfinderRemove
assert(remove and remove.shown, "the button is there and shown")
remove.scripts.OnClick()
equal(#Navigation:GetWaypoints(), 1, "it removed one waypoint")
assert(menu and #menu.rows == 1, "and the list comes back with what is left")
equal(named(1), "First", "and left the other alone")
equal(Navigation:GetWaypoint().n, "First", "the arrow kept its own")

-- Menu rows are pooled and lent on, so the button leaves with its row.
rowFrame.scripts.OnHide()
assert(not remove.shown, "the button hides with its row")

menu.buttons[#menu.buttons].click()
equal(#Navigation:GetWaypoints(), 0, "clear all empties the list")

---------------------------------------------------------------------------
-- 7. The real TomTom keeps its own
---------------------------------------------------------------------------
local shim = ns.TomTomShim
local genuine = { AddWaypoint = noop }
TomTom = genuine
local forwarded
SlashCmdList.TOMTOM_WAY = function(input) forwarded = input end
Compat:OnLogin()
SlashCmdList.WAYFINDERWAY("42 65 Theirs")
equal(forwarded, "42 65 Theirs", "/way is handed to the real TomTom")
equal(#Navigation:GetWaypoints(), 0, "and sets nothing of ours")

Compat.superseded = nil
Compat:OnInitialize()
equal(TomTom, genuine, "its table is never overwritten")
assert(Compat.superseded, "we stand aside instead")
TomTom = shim

print = realPrint
print("TomTom /way formats, the waypoint list, the shared table and the arrow menu passed")
