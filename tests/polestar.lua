-- Polestar's guide on Wayfinder's arrow: one waypoint that follows the guide's
-- goal through Polestar's follower API, never cleared on arrival, dismissed in
-- Polestar when the player removes it, and dropped quietly when Polestar hands
-- the guiding elsewhere or the goal can't be placed.
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
C_Map = {
    GetMapInfo = function(mapID)
        local info = MAPS[mapID]
        return info and { mapID = mapID, name = info.name, mapType = info.mapType, parentMapID = info.parent } or nil
    end,
    GetBestMapForUnit = function() return playerMap end,
    GetMapPosFromWorldPos = function(_, position) return position.x < 1000 and 1429 or 1436, position end,
}

local corpse
C_DeathInfo = { GetCorpseMapPosition = function(mapID)
    local info = MAPS[mapID]
    if not corpse or not info then return nil end
    local x, y = (corpse.x - info.origin) / info.span, (corpse.y - info.origin) / info.span
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return Vector(x, y)
end }
local state = "alive"
function UnitIsDeadOrGhost() return state ~= "alive" end
function UnitIsGhost() return state == "ghost" end

local ns = { db = { waypoints = {}, settings = { showArrow = true, clearOnArrival = true, corpseWaypoint = true,
    followPolestar = false } } }
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

C_Timer = { After = function(_, fn) fn() end }
SOUNDKIT = { UI_MAP_WAYPOINT_REMOVE = "remove", UI_MAP_WAYPOINT_CLICK_TO_PLACE = "place", MAP_PING = "ping" }
local sounds = {}
function PlaySound(sound) sounds[#sounds + 1] = sound end

-- Frames remember the last arguments of every call, so the arrow's text can be read.
local function NewFrame()
    local frame = { scripts = {}, calls = {} }
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    function frame:CreateTexture() return NewFrame() end
    function frame:CreateFontString() return NewFrame() end
    function frame:SetTexture() return true end
    return setmetatable(frame, { __index = function(self, key)
        if type(key) ~= "string" or not key:find("^%u") then return nil end
        local method = function(this, ...) this.calls[key] = { ... } end
        rawset(self, key, method)
        return method
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

---------------------------------------------------------------------------
-- Polestar, as far as its follower API goes
---------------------------------------------------------------------------
local target         -- what Polestar's guide is going to, in API.Target's shape
local followers = {} -- owner -> { fn, opts }
local dismissed = 0
local polestarSettings = { ["nav.arrowToFollower"] = false }
local API = { version = 1, minor = 1 }
function API.Target() return target end
function API.Follow(owner, fn, opts) followers[owner] = { fn = fn, opts = opts }; return true end
function API.Unfollow(owner) local had = followers[owner] ~= nil; followers[owner] = nil; return had end
local function notify() for _, follower in pairs(followers) do follower.fn() end end
function API.Dismiss(owner)
    if not (followers[owner] and target) then return false end
    dismissed = dismissed + 1
    target = nil
    notify()
    return true
end
Polestar = { Nav = { API = API }, Get = function(path) return polestarSettings[path] end }
-- The guide moves on.
local function guide(goal)
    target = goal
    notify()
end

assert(loadfile(root .. "/Modules/Wayfinder/Navigation.lua"))("Wayfinder", ns)
assert(loadfile(root .. "/Modules/Wayfinder/Polestar.lua"))("Wayfinder", ns)
local Navigation, Follow = ns.Navigation, ns.PolestarFollow

local function equal(actual, expected, label)
    assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function near(actual, expected, label)
    assert(type(actual) == "number" and math.abs(actual - expected) < 1e-6, label .. ": " .. tostring(actual))
end
local function mark() return Navigation:GetSourceWaypoint("Polestar") end
local function arrow() return Navigation:GetWaypoint() end
local changes = 0
ns:On("WAYPOINT_CHANGED", function() changes = changes + 1 end)

---------------------------------------------------------------------------
-- 1. Off: nothing follows, and a waypoint left from a session that did goes
---------------------------------------------------------------------------
ns.db.waypoints["Tester-Realm"] = { list = {
    { c = 1, x = 100, y = 100, n = "The inn", m = 1429 },
    { c = 1, x = 900, y = 900, n = "Old goal", m = 1429, source = "Polestar", kept = true },
}, active = 2 }
Navigation:OnLogin()
Follow:OnLogin()
equal(followers.Wayfinder, nil, "off: Polestar isn't followed")
equal(mark(), nil, "and the old goal is gone")
local inn = arrow()
equal(inn.n, "The inn", "the player's own waypoint stays, with the arrow")
assert(Follow:Status():find("^Off"), "the page says it is off")
target = { map = 1429, x = 0.5, y = 0.5, title = "Accept Hogger", kind = "accept", quest = 176 }
notify()
equal(mark(), nil, "and Polestar's goal isn't shown")

---------------------------------------------------------------------------
-- 2. On: Polestar's goal is a waypoint, and the arrow points at it
---------------------------------------------------------------------------
printed, sounds = {}, {}
setting("followPolestar", true)
local follower = followers.Wayfinder
assert(follower, "turned on: Wayfinder follows Polestar")
equal(follower.opts.shows, true, "as an addon that shows the target")
assert(not follower.opts.pin, "not one that sets the game's own pin")
local goal = mark()
assert(goal, "Polestar's goal is a waypoint at once")
near(goal.x, 500, "where the goal is")
near(goal.y, 500, "on both axes")
equal(goal.n, "Accept Hogger", "named as Polestar names it")
equal(goal.m, 1429, "in its zone")
equal(arrow(), goal, "and the arrow points there")
equal(#sounds, 0, "with no click: the guide moved, not the player")
assert(printed[1] and printed[1]:find("Let a following addon show the way", 1, true),
    "and says how to hide Polestar's own arrow: " .. tostring(printed[1]))
assert(Follow:Status():find("still shows"), "the page says so too")
polestarSettings["nav.arrowToFollower"] = true
assert(Follow:Status():find("steps aside"), "until Polestar's arrow steps aside")

-- Told again of the same goal (Polestar planning the route again): no churn.
local before = changes
notify()
notify()
equal(mark(), goal, "the same waypoint")
equal(changes, before, "and nothing redrawn")

---------------------------------------------------------------------------
-- 3. The next travel stop takes priority over the final quest.
---------------------------------------------------------------------------
guide({ map = 1436, x = 0.5, y = 0.5, title = "Kill Defias", kind = "kill",
    next = { map = 1429, x = 0.8, y = 0.2, kind = "walk", title = "Walk to the flight master" } })
local leg = mark()
near(leg.x, 800, "the walking leg leads to the flight master first")
equal(Navigation.arrow.bearingFrame, 112, "faces the flight master before the quest in Westfall")
equal(leg.n, "Walk to the flight master", "named for the leg")
equal(leg.goal, "Kill Defias", "with the goal it is on the way to")
equal(arrow(), leg, "a new goal takes the arrow")
local count = 0
for _, rec in ipairs(Navigation:GetWaypoints()) do
    if rec.source == "Polestar" then count = count + 1 end
end
equal(count, 1, "one waypoint for Polestar, not a trail of old goals")
equal(#Navigation:GetWaypoints(), 2, "beside the inn")

-- Under the arrow: the whole name, wrapped rather than cut off, and the goal.
local label, under = Navigation.arrow.label, Navigation.arrow.goal
equal(label.calls.SetWordWrap[1], true, "the name wraps onto more lines")
assert(label.calls.SetWidth[1] > 110, "wider than the arrow")
equal(label.calls.SetText[1], "Walk to the flight master", "names the travel step")
equal(under.calls.SetText[1], "On the way to Kill Defias", "keeps the quest below the stop")
equal(under.calls.SetWordWrap[1], true, "which wraps too")

-- The final objective can move independently of the route leg.
target.x, target.y = 0.9, 0.1
notify()
Navigation:UpdateArrow()
equal(mark(), leg, "the walking leg stays put")
equal(Navigation.arrow.bearingFrame, 112, "moving the final goal cannot divert the arrow from the flight master")

-- The player puts the arrow on the inn; the route moves on to the flight.
Navigation:SetActiveWaypoint(inn)
equal(label.calls.SetText[1], "The inn", "the inn's name")
equal(under.calls.SetText[1], "", "with no goal line")
guide({ map = 1436, x = 0.5, y = 0.5, title = "Kill Defias", kind = "kill",
    next = { map = 1436, x = 0.2, y = 0.3, kind = "fly", title = "Fly to Sentinel Hill" } })
local flight = mark()
near(flight.x, 1200, "the waypoint moves to the next leg's end")
equal(flight.m, 1436, "in the zone it now lies in")
assert(flight ~= leg, "as a new record, so nothing remembered about the old spot carries over")
equal(arrow(), inn, "the same goal leaves the arrow where the player put it")

-- The last leg: the goal itself.
guide({ map = 1436, x = 0.5, y = 0.5, title = "Kill Defias", kind = "kill" })
near(mark().x, 1500, "at the goal")
equal(mark().n, "Kill Defias", "named for it")
equal(mark().goal, nil, "with no 'on the way' line")
equal(arrow(), inn, "still where the player put it")

---------------------------------------------------------------------------
-- 4. Arriving doesn't clear it: Polestar says when the goal is done
---------------------------------------------------------------------------
guide({ map = 1429, x = 0.4, y = 0.6, title = "Turn in Hogger", kind = "turnin", quest = 176 })
equal(arrow(), mark(), "a new goal takes the arrow back from the inn")
playerX, playerY = 401, 601
Navigation:UpdateArrow()
assert(mark(), "standing on it leaves it, though arrived waypoints are cleared")
Navigation:SetActiveWaypoint(inn)
playerX, playerY = 100, 100
Navigation:UpdateArrow()
equal(#Navigation:GetWaypoints(), 1, "an ordinary waypoint is still cleared on arrival")
playerX, playerY = 400, 600

---------------------------------------------------------------------------
-- 5. Removed by the player: the goal goes in Polestar too, until it moves on
---------------------------------------------------------------------------
sounds = {}
Navigation:SetActiveWaypoint(mark())
Navigation:ClearWaypoint() -- a middle-click on the arrow
equal(dismissed, 1, "Polestar lets the goal go")
equal(mark(), nil, "and nothing puts it back")
equal(sounds[1], "remove", "with the usual sound")
guide({ map = 1429, x = 0.3, y = 0.3, title = "Accept Report to Goldshire", kind = "accept", quest = 54 })
assert(mark(), "the guide moving on brings it back")
equal(arrow(), mark(), "with the arrow")
Navigation:ClearAllWaypoints()
equal(dismissed, 2, "clearing every waypoint lets the goal go as well")

---------------------------------------------------------------------------
-- 6. Taken away quietly, with nothing let go in Polestar
---------------------------------------------------------------------------
local camp = Navigation:AddWaypoint(1, 600, 600, "Camp", 1429, { focus = false })
guide({ map = 1429, x = 0.3, y = 0.3, title = "Accept Report to Goldshire", kind = "accept", quest = 54 })
assert(mark(), "followed again")
sounds = {}
guide({ map = 1429, x = 0.3, y = 0.3, title = "Accept Report to Goldshire", kind = "accept", quest = 54,
    handedOff = true })
equal(mark(), nil, "Shortest Path Forever guiding: no second arrow here")
equal(dismissed, 2, "and the goal isn't let go")
equal(#sounds, 0, "silently")
guide({ map = 1429, x = 0.3, y = 0.3, title = "Accept Report to Goldshire", kind = "accept", quest = 54 })
assert(mark(), "back when Polestar guides again")
guide({ map = 9999, x = 0.5, y = 0.5, title = "Kill Van Cleef", kind = "kill" })
equal(mark(), nil, "a goal no map of Wayfinder's can place shows nothing")
equal(dismissed, 2, "and isn't let go either")
guide(nil)
equal(mark(), nil, "nor does no goal at all")
equal(arrow(), camp, "the arrow goes to what's left")

---------------------------------------------------------------------------
-- 7. Dead: Wayfinder's own corpse waypoint shows the way back
---------------------------------------------------------------------------
guide({ map = 1429, x = 0.7, y = 0.7, title = "Collect Gold Dust", kind = "collect" })
local dust = mark()
corpse, state, playerX, playerY = { x = 300, y = 400 }, "ghost", 100, 100
event("PLAYER_ALIVE")
local body = Navigation:GetCorpseWaypoint()
assert(body, "releasing marks the body")
guide({ map = 1429, x = 0.3, y = 0.4, title = "Your corpse", kind = "manual" }) -- Polestar's death helper
equal(mark(), dust, "the guide's waypoint waits where it was")
equal(arrow(), body, "and the arrow stays on the body")
state = "alive"
event("PLAYER_UNGHOST")
guide({ map = 1429, x = 0.7, y = 0.7, title = "Collect Gold Dust", kind = "collect" })
equal(Navigation:GetCorpseWaypoint(), nil, "alive again: the body's waypoint is done")
equal(arrow(), dust, "and the arrow is back on the guide")
-- Without Wayfinder's corpse waypoint, Polestar's way back is followed.
setting("corpseWaypoint", false)
state = "ghost"
event("PLAYER_ALIVE")
guide({ map = 1429, x = 0.3, y = 0.4, title = "Your corpse", kind = "manual" })
equal(mark().n, "Your corpse", "Polestar's way back to the body")
state = "alive"
event("PLAYER_UNGHOST")
setting("corpseWaypoint", true)

---------------------------------------------------------------------------
-- 8. Off again, and Polestar missing or speaking another version
---------------------------------------------------------------------------
sounds = {}
setting("followPolestar", false)
equal(followers.Wayfinder, nil, "turned off: no longer following")
equal(mark(), nil, "its waypoint goes")
equal(dismissed, 2, "without letting the goal go in Polestar")
equal(#sounds, 0, "silently")

API.version = 2
assert(not Follow:Available(), "a later API version is left alone")
setting("followPolestar", true)
equal(followers.Wayfinder, nil, "and isn't followed")
API.version = 1
setting("followPolestar", false)
Polestar = nil
assert(not Follow:Available(), "without Polestar there is nothing to follow")
setting("followPolestar", true)
equal(mark(), nil, "and nothing to show")
equal(Follow:Status(), "Polestar isn't loaded.", "the page says why")

print = realPrint
print("Polestar: follows the guide's goal and the route's legs, kept on arrival, let go when removed, quiet when handed off, the body first when dead")
