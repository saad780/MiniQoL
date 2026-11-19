-- The corpse waypoint: set when the spirit is released, never on death itself,
-- and completed by coming back to life however that happens, not by walking
-- up to the body.
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
local function Vector(x, y) return { GetXY = function() return x, y end } end

local playerMap, playerX, playerY = 1429, 400, 600 -- world yards
local function ZoneAt(wx)
    return wx < 1000 and 1429 or 1436
end
C_Map = {
    GetMapInfo = function(mapID)
        local info = MAPS[mapID]
        return info and { mapID = mapID, name = info.name, mapType = info.mapType, parentMapID = info.parent } or nil
    end,
    GetBestMapForUnit = function() return playerMap end,
    GetMapPosFromWorldPos = function(_, position) return ZoneAt(position.x), position end,
}

-- Where the body lies, and whether the game will say so yet.
local corpse, corpseKnown = nil, true
C_DeathInfo = { GetCorpseMapPosition = function(mapID)
    local info = MAPS[mapID]
    if not corpse or not corpseKnown or not info then return nil end
    local x, y = (corpse.x - info.origin) / info.span, (corpse.y - info.origin) / info.span
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return Vector(x, y)
end }

local state = "alive"
function UnitIsDeadOrGhost() return state ~= "alive" end
function UnitIsGhost() return state == "ghost" end

local ns = { db = { waypoints = {}, settings = { showArrow = true, clearOnArrival = true, corpseWaypoint = true } } }
function ns:NewModule(name) self[name] = { name = name }; return self[name] end
function ns:GetCharacterKey() return "Tester-Realm" end
function ns:GetSetting(key) return self.db.settings[key] end
local listeners, events = {}, {}
function ns:On(message, fn) listeners[message] = listeners[message] or {}; table.insert(listeners[message], fn) end
function ns:Fire(message, ...) for _, fn in ipairs(listeners[message] or {}) do fn(...) end end
function ns:RegisterEvent(event, fn) events[event] = events[event] or {}; table.insert(events[event], fn) end
local function event(name) for _, fn in ipairs(events[name] or {}) do fn(name) end end
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
function ns.GetPlayerWorld() return 1, playerX, playerY, playerMap end
function ns.Distance(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

-- Timers wait until the test lets a second pass.
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function second()
    local due = timers
    timers = {}
    for _, fn in ipairs(due) do fn() end
end

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
function hooksecurefunc() end
function GetPlayerFacing() return 0 end
function print(...) printed[#printed + 1] = table.concat({ ... }, " ") end
MiniQoLRuntime = { Execute = function(_, _, fn) return fn("Wayfinder", ns) end }

assert(loadfile(root .. "/Modules/Wayfinder/Navigation.lua"))("Wayfinder", ns)
local Navigation = ns.Navigation

local function equal(actual, expected, label)
    assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function near(actual, expected, label)
    assert(type(actual) == "number" and math.abs(actual - expected) < 1e-6, label .. ": " .. tostring(actual))
end
local function corpseMark() return Navigation:GetCorpseWaypoint() end
local function count() return #Navigation:GetWaypoints() end

Navigation:OnLogin()
local inn = Navigation:AddWaypoint(1, 450, 650, "The inn", 1429)
event("PLAYER_ENTERING_WORLD")
equal(corpseMark(), nil, "alive at login: no corpse waypoint")

---------------------------------------------------------------------------
-- 1. Dying sets nothing; releasing the spirit does
---------------------------------------------------------------------------
corpse, state = { x = 300, y = 400 }, "dead"
event("PLAYER_DEAD")
second()
equal(corpseMark(), nil, "dying alone sets no waypoint")
event("PLAYER_ENTERING_WORLD") -- a reload while lying dead
second()
equal(corpseMark(), nil, "nor does a reload before releasing")
equal(Navigation:GetWaypoint(), inn, "and the arrow is still on the inn")

state, playerX, playerY = "ghost", 100, 100 -- released, at the graveyard
event("PLAYER_ALIVE")
local mark = corpseMark()
assert(mark, "releasing the spirit sets a waypoint on the corpse")
near(mark.x, 300, "where the body lies")
near(mark.y, 400, "on both axes")
equal(mark.n, "Your corpse", "named for what it is")
equal(Navigation:GetWaypoint(), mark, "the arrow points at it")
equal(count(), 2, "and the inn is still set")

---------------------------------------------------------------------------
-- 2. Reaching the body doesn't complete it; coming back to life does
---------------------------------------------------------------------------
playerX, playerY = 302, 401
Navigation:UpdateArrow()
equal(corpseMark(), mark, "standing on the body leaves the waypoint")
-- Another waypoint nearer the body than the inn, set without taking the arrow.
local camp = Navigation:AddWaypoint(1, 315, 415, "Camp", 1429, { focus = false })
equal(Navigation:GetWaypoint(), mark, "the arrow stays on the corpse")
state = "alive"
event("PLAYER_UNGHOST")
equal(corpseMark(), nil, "reviving completes it")
equal(Navigation:GetWaypoint(), inn, "and the arrow goes back to the inn, not the nearest")
equal(count(), 2, "nothing else was removed")
Navigation:RemoveWaypoint(camp)

-- A spirit healer brings you back far from the body: same thing.
state = "ghost"
event("PLAYER_ALIVE")
assert(corpseMark(), "a second death marks the body again")
playerX, playerY = 50, 50
state = "alive"
event("PLAYER_UNGHOST")
equal(corpseMark(), nil, "reviving away from the body still completes it")

---------------------------------------------------------------------------
-- 3. A graveyard in the next zone over
---------------------------------------------------------------------------
corpse, state, playerMap, playerX, playerY = { x = 900, y = 500 }, "ghost", 1436, 1200, 500
event("PLAYER_ALIVE")
mark = corpseMark()
assert(mark, "found through the continent's map")
near(mark.x, 900, "in the zone it lies in")
equal(mark.m, 1429, "described by that zone")
state, playerMap = "alive", 1429
event("PLAYER_UNGHOST")

---------------------------------------------------------------------------
-- 4. The game slow to place the body after the release
---------------------------------------------------------------------------
corpse, corpseKnown, state = { x = 300, y = 400 }, false, "ghost"
event("PLAYER_ALIVE")
equal(corpseMark(), nil, "nothing to point at yet")
second()
equal(corpseMark(), nil, "still nothing")
corpseKnown = true
second()
assert(corpseMark(), "set as soon as the game knows")
equal(#timers, 0, "and then it stops looking")

---------------------------------------------------------------------------
-- 5. A reload or loading screen as a ghost leaves things as they were
---------------------------------------------------------------------------
Navigation:SetActiveWaypoint(inn)
event("PLAYER_ENTERING_WORLD")
equal(count(), 2, "no second corpse waypoint")
equal(Navigation:GetWaypoint(), inn, "and the arrow stays where it was put")
state = "alive"
event("PLAYER_UNGHOST")
equal(corpseMark(), nil, "reviving still completes it")
equal(Navigation:GetWaypoint(), inn, "with the arrow left on the inn")

---------------------------------------------------------------------------
-- 6. Resurrected before releasing: there was never a corpse waypoint
---------------------------------------------------------------------------
state = "dead"
event("PLAYER_DEAD")
state = "alive"
event("PLAYER_ALIVE")
second()
equal(corpseMark(), nil, "a resurrection taken where you fell sets nothing")

---------------------------------------------------------------------------
-- 7. The setting
---------------------------------------------------------------------------
setting("corpseWaypoint", false)
state = "ghost"
event("PLAYER_ALIVE")
second()
equal(corpseMark(), nil, "off: releasing sets nothing")
setting("corpseWaypoint", true)
assert(corpseMark(), "turned on as a ghost: the body is marked")
setting("corpseWaypoint", false)
equal(corpseMark(), nil, "turned off: the waypoint goes")
setting("corpseWaypoint", true)
state = "alive"
event("PLAYER_UNGHOST")

---------------------------------------------------------------------------
-- 8. Leftovers and bodies no map can show
---------------------------------------------------------------------------
-- Logged out a ghost and came back to life elsewhere: cleared at login.
Navigation:AddWaypoint(1, 300, 400, "Your corpse", 1429, { source = "corpse" })
event("PLAYER_ENTERING_WORLD")
equal(corpseMark(), nil, "an old corpse waypoint goes once you are alive")

-- Inside an instance the body has no place on the outdoor maps.
corpse, state, printed = { x = 5000, y = 5000 }, "ghost", {}
event("PLAYER_ALIVE")
for _ = 1, 10 do second() end
equal(corpseMark(), nil, "nothing to point at")
equal(#timers, 0, "it gives up after a few seconds")
assert(printed[1] and printed[1]:find("corpse", 1, true), "and says why")

print = realPrint
print("Corpse waypoint: set on release not death, kept on arrival, completed on revive, next zone, slow placing, reload, setting passed")
