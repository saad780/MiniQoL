-- Moving the waypoint arrow: a line down the middle of the screen while it is
-- dragged, a snap onto that line when close, and the place kept relative to
-- the middle so a centred arrow stays centred.
local root = ...
local function noop() end

---------------------------------------------------------------------------
-- A small world, enough for one waypoint
---------------------------------------------------------------------------
local MAPS = {
    [1429] = { name = "Elwynn Forest", mapType = 3, parent = 947, origin = 0, span = 1000 },
    [947] = { name = "Eastern Kingdoms", mapType = 2, parent = 0, origin = 0, span = 2000 },
}
Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5 } }
function CreateVector2D(x, y) return { x = x, y = y } end
C_Map = {
    GetMapInfo = function(mapID)
        local info = MAPS[mapID]
        return info and { mapID = mapID, name = info.name, mapType = info.mapType, parentMapID = info.parent } or nil
    end,
    GetBestMapForUnit = function() return 1429 end,
    GetMapPosFromWorldPos = function(_, position) return 1429, position end,
}
function UnitIsDeadOrGhost() return false end
function UnitIsGhost() return false end
C_Timer = { After = noop }

local ns = { db = { waypoints = {}, settings = { showArrow = true, arrowScale = 1.25 } } }
function ns:NewModule(name) self[name] = { name = name }; return self[name] end
function ns:GetCharacterKey() return "Tester-Realm" end
function ns:GetSetting(key) return self.db.settings[key] end
local handlers = {}
function ns:On(message, handler) handlers[message] = handler end
function ns:Fire(message, ...) if handlers[message] then handlers[message](...) end end
function ns:RegisterEvent() end
ns.Print = noop
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
function ns.WorldToMapRect(rect, wx, wy) return (wx - rect.origin) / rect.span, (wy - rect.origin) / rect.span end
function ns.GetPlayerWorld() return 1, 400, 600, 1429 end
function ns.Distance(x1, y1, x2, y2) return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) end

---------------------------------------------------------------------------
-- Frames with real scales and places
---------------------------------------------------------------------------
local methods = {}
local function NewFrame(kind, parent)
    local frame = { kind = kind, parent = parent, scripts = {}, points = {}, shown = true, scale = 1,
        strata = "MEDIUM", level = parent and parent.level + 1 or 1 }
    return setmetatable(frame, { __index = function(_, key)
        if methods[key] then return methods[key] end
        if type(key) == "string" and key:find("^%u") then return noop end
    end })
end
function methods:SetScript(name, fn) self.scripts[name] = fn end
function methods:GetScript(name) return self.scripts[name] end
function methods:SetShown(value)
    value = value and true or false
    if value == self.shown then return end
    self.shown = value
    local script = self.scripts[value and "OnShow" or "OnHide"]
    if script then script(self) end
end
function methods:Show() self:SetShown(true) end
function methods:Hide() self:SetShown(false) end
function methods:IsShown() return self.shown end
function methods:SetPoint(point, relativeTo, relativePoint, x, y)
    self.points[#self.points + 1] = { point, relativeTo, relativePoint, x or 0, y or 0 }
end
function methods:ClearAllPoints() self.points = {} end
function methods:SetScale(scale) self.scale = scale end
function methods:GetEffectiveScale() return (self.parent and self.parent:GetEffectiveScale() or 1) * self.scale end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetWidth(width) self.width = width end
function methods:SetFrameStrata(strata) self.strata = strata end
function methods:GetFrameStrata() return self.strata end
function methods:SetFrameLevel(level) self.level = level end
function methods:GetFrameLevel() return self.level end
function methods:CreateTexture() return NewFrame("Texture", self) end
function methods:CreateFontString() return NewFrame("FontString", self) end
function methods:SetTexture() return true end
function methods:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function methods:SetText(text) self.text = text end
-- Where a frame anchored to the screen sits, in its own units.
function methods:GetCenter()
    local point = self.points[1]
    if not point then return nil end
    local ratio = UIParent:GetEffectiveScale() / self:GetEffectiveScale()
    local width, height = UIParent.width * ratio, UIParent.height * ratio
    local x = width / 2 + point[4]
    local y = (point[3] == "TOP" and height or height / 2) + point[5]
    if point[1] == "TOP" then y = y - self.height / 2 end
    return x, y
end
local created = {}
function CreateFrame(kind, name, parent)
    local frame = NewFrame(kind, parent)
    if name then _G[name] = frame end
    created[#created + 1] = frame
    return frame
end
-- The guide line: the frame stretched from the top of the screen to the bottom.
local function Guide()
    for _, frame in ipairs(created) do
        local top, bottom = frame.points[1], frame.points[2]
        if top and bottom and top[1] == "TOP" and top[2] == UIParent and bottom[1] == "BOTTOM" then return frame end
    end
end

-- A 1920 by 1080 screen at a UI scale of 0.8.
UIParent = NewFrame("Frame")
UIParent.scale, UIParent.width, UIParent.height = 0.8, 1920, 1080
function UIParent:GetCenter() return 960, 540 end
local cursorX, cursorY = 0, 0 -- in pixels, as the game gives it
function GetCursorPosition() return cursorX, cursorY end

GameTooltip = { SetOwner = noop, SetText = noop, AddLine = noop, Show = noop, Hide = noop }
GameTooltip_Hide = noop
StaticPopupDialogs = {}
LinkUtil = { RegisterLinkHandler = noop }
EventUtil = { ContinueOnAddOnLoaded = noop }
function hooksecurefunc() end
function GetPlayerFacing() return 0 end
MiniQoLRuntime = { Execute = function(_, _, fn) return fn("Wayfinder", ns) end }

assert(loadfile(root .. "/Modules/Wayfinder/Navigation.lua"))("Wayfinder", ns)
local Navigation = ns.Navigation
Navigation:OnLogin()
Navigation:AddWaypoint(1, 450, 650, "The inn", 1429)
local arrow = WayfinderArrow
assert(arrow and arrow.shown, "the arrow is up")

local function equal(actual, expected, label)
    assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function near(actual, expected, label)
    assert(type(actual) == "number" and math.abs(actual - expected) < 1e-6, label .. ": " .. tostring(actual))
end
-- The arrow's place: its offset from the middle of the screen.
local function offset()
    local point = arrow.points[1]
    equal(point[1], "CENTER", "held by its centre")
    equal(point[2], UIParent, "to the screen")
    equal(point[3], "CENTER", "at its middle")
    return point[4], point[5]
end
-- The arrow's scale times the UI scale is 1, so its units are pixels here and
-- one screen unit is 0.8 of them.
local function cursorTo(x, y) cursorX, cursorY = x, y end
local MIDDLE_X, MIDDLE_Y = 768, 432

---------------------------------------------------------------------------
-- 1. Picking it up shows the line, and the arrow stays where it was grabbed
---------------------------------------------------------------------------
local startX, startY = arrow:GetCenter()
near(startX, MIDDLE_X, "the arrow starts in the middle")
assert(not (Guide() and Guide().shown), "no line until the arrow is picked up")
cursorTo(startX - 10, startY + 5) -- grabbed a little off centre
arrow.scripts.OnDragStart(arrow)
local x, y = offset()
near(x, 0, "it does not jump to the cursor")
near(y, startY - MIDDLE_Y, "on either axis")
local guide = Guide()
assert(guide and guide.shown, "a line runs down the middle of the screen")
equal(guide.points[1][3], "TOP", "from the top")
equal(guide.points[2][3], "BOTTOM", "to the bottom")
near(guide.points[1][4], 0, "through the middle")
equal(guide.width, 2, "thin")
assert(guide.level < arrow.level, "behind the arrow")
equal(guide.line.color[4], 0.9, "bright while the arrow sits on it")
equal(guide.line.color[1], 0.35, "in the arrow's cyan")

---------------------------------------------------------------------------
-- 2. Dragged away from the middle, then back near it
---------------------------------------------------------------------------
cursorTo(startX - 10 + 30, startY + 5)
arrow.scripts.OnUpdate(arrow, 0.001)
x = offset()
near(x, 30, "30 pixels out is 37.5 screen units, too far to snap")
equal(guide.line.color[4], 0.35, "the line dims while the arrow is off it")
equal(guide.line.color[1], 1, "and turns white")

cursorTo(startX - 10 + 12, startY + 5 - 100)
arrow.scripts.OnUpdate(arrow, 0.001)
x, y = offset()
near(x, 0, "12 pixels out is 15 screen units: it snaps to the middle")
near(y, startY - MIDDLE_Y - 100, "and still moves up and down freely")
equal(guide.line.color[4], 0.9, "lighting the line up")

cursorTo(startX - 10 - 12, startY + 5)
arrow.scripts.OnUpdate(arrow, 0.001)
near(offset(), 0, "from either side")

cursorTo(startX - 10 - 14, startY + 5)
arrow.scripts.OnUpdate(arrow, 0.001)
near(offset(), -14, "14 pixels out is 17.5 screen units: free again")

---------------------------------------------------------------------------
-- 3. Letting go near the middle keeps it in the middle
---------------------------------------------------------------------------
cursorTo(startX - 10 + 8, startY + 5 - 200)
arrow.scripts.OnDragStop(arrow)
local saved = ns.db.arrowPosition
equal(saved[1], "CENTER", "kept by its centre")
equal(saved[2], "CENTER", "against the middle of the screen")
near(saved[3], 0, "exactly in the middle")
near(saved[4], startY - MIDDLE_Y - 200, "at the height it was dropped")
assert(not guide.shown, "the line goes when the arrow is let go")
Navigation:PlaceArrow()
x, y = offset()
near(x, 0, "and put back there next time")
near(y, saved[4], "at the same height")

-- Let go away from the middle: kept where it was dropped.
local centreX, centreY = arrow:GetCenter()
cursorTo(centreX, centreY)
arrow.scripts.OnDragStart(arrow)
cursorTo(centreX - 200, centreY)
arrow.scripts.OnDragStop(arrow)
near(ns.db.arrowPosition[3], -200, "dropped to one side, it stays there")

---------------------------------------------------------------------------
-- 4. A bigger arrow: the snapping distance is in screen units, not the arrow's
---------------------------------------------------------------------------
ns.db.settings.arrowScale = 2
Navigation:PlaceArrow() -- 1.6 pixels to the arrow's unit; a screen unit is two of them
centreX, centreY = arrow:GetCenter()
cursorTo(centreX * 1.6, centreY * 1.6)
arrow.scripts.OnDragStart(arrow)
cursorTo((480 + 10) * 1.6, centreY * 1.6)
arrow.scripts.OnUpdate(arrow, 0.001)
near(offset(), 10, "10 of the bigger arrow's units is 20 screen units: no snap")
cursorTo((480 + 7) * 1.6, centreY * 1.6)
arrow.scripts.OnUpdate(arrow, 0.001)
near(offset(), 0, "7 is 14 screen units: snaps")
arrow.scripts.OnDragStop(arrow)
ns.db.settings.arrowScale = 1.25
Navigation:PlaceArrow()

---------------------------------------------------------------------------
-- 5. The arrow going away mid-drag ends the drag
---------------------------------------------------------------------------
centreX, centreY = arrow:GetCenter()
cursorTo(centreX, centreY)
arrow.scripts.OnDragStart(arrow)
cursorTo(centreX + 100, centreY)
Navigation:ClearWaypoint()
assert(not arrow.shown, "the last waypoint removed hides the arrow")
equal(arrow.grab, nil, "and ends the drag")
assert(not guide.shown, "taking the line with it")
near(ns.db.arrowPosition[3], 100, "where it had got to is kept")
cursorTo(0, 0)
arrow.scripts.OnUpdate(arrow, 0.001)
near(offset(), 100, "and the cursor no longer moves it")

print("Arrow placement: drag without a jump, snap to the middle from either side, saved centred, a bigger arrow, hidden mid-drag passed")

---------------------------------------------------------------------------
-- Walking routes drive the same arrow and replace in-flight jobs on changes.
---------------------------------------------------------------------------
local requests = {}
local covered = true
ns.Walking = { Nav = { follow = { Reset = noop, Mark = noop, Catch = noop,
    Step = function(xs, ys, _, _, _, state)
        state.idx = 2
        return xs[2], ys[2]
    end } }, Compat = { GetPlayerFaction = function() return "Alliance" end, IsOnTaxi = function() return false end } }
ns.Walking.Nav.Path = {
    Available = function(cont) return covered and cont == 1 end,
    Find = function(cont, from, to, done, options)
        local job = { cont = cont, from = from, to = to, done = done, options = options }
        requests[#requests + 1] = job
        return job
    end,
    Cancel = function(job) job.cancelled = true end,
}
C_AddOns = { LoadAddOn = function() error("walking should not load another addon") end }
local inCombat, now = true, 0
function InCombatLockdown() return inCombat end
function GetTime() return now end

Navigation:AddWaypoint(1, 400, 650, "Across the river", 1429)
equal(#requests, 0, "defers the walking search in combat")
inCombat = false
Navigation:UpdateArrow()
equal(#requests, 1, "starts the walking search after combat")
local balanced = requests[1]
equal(balanced.options.style, "balanced", "older profiles default to Balanced")
equal(balanced.options.profile, "Alliance", "routes with the player's faction")
assert(not arrow.head.shown, "no straight bearing while finding a route")

local function SetStyle(style)
    ns.db.settings.routeStyle = style
    ns:Fire("SETTING_CHANGED", "routeStyle")
end
SetStyle("fastest")
local direct = requests[2]
assert(balanced.cancelled, "changing styles cancels the previous search")
equal(direct.options.style, "fastest", "Direct uses Polestar's Fastest style")
balanced.done({ balanced.from, balanced.to })
Navigation:UpdateArrow()
assert(not arrow.head.shown, "a stale result cannot show a bearing")

SetStyle("roads")
local roads = requests[3]
assert(direct.cancelled, "Direct is retired on switching to Roads Always")
equal(roads.options.style, "roads", "Roads Always uses Polestar's Roads style")
roads.done({ roads.from, { x = 430, y = 600 }, roads.to })
Navigation:UpdateArrow()
assert(arrow.head.shown, "the completed route shows a bearing")
equal(arrow.bearingFrame, 0, "aims at the first turn, north")
equal(arrow.distance.text, "88 yd", "reports the distance along the walk")

local nextWaypoint = Navigation:AddWaypoint(1, 420, 650, "Another destination", 1429)
assert(Navigation:GetWaypoint() == nextWaypoint, "placing a new waypoint changes the route")
local nextJob = requests[4]
nextJob.done(nil, "unreachable")
Navigation:UpdateArrow()
equal(arrow.distance.text, "No walking route", "keeps the arrow from sending players through obstructions")

covered = false
Navigation:AddWaypoint(1, 420, 650, "Outside walking coverage", 1429)
assert(arrow.head.shown, "straight bearings still work on unmapped ground")
equal(arrow.distance.text, "54 yd", "reports the distance to the original waypoint")
print("Walking arrow: combat deferral, style changes, stale searches, route distance and fallback passed")

-- An intercontinental destination stays selected while its local stop drives
-- the walking path. Being at the dock must never clear the final pin.
local stage = { c=1, x=460, y=600, m=1429, z=54 }
local boarded = false
ns.Travel = { Aim = function()
    if boarded then return nil, "Take the zeppelin to Undercity" end
    return stage, nil, "Orgrimmar zeppelin tower"
end, Reset = noop }
covered = true
ns.db.settings.clearOnArrival = true
local trip = Navigation:AddWaypoint(0, 1570, 270, "Undercity", 1429)
equal(requests[#requests].to.x, stage.x, "walking search aims at the local boarding point")
equal(requests[#requests].to.z, 54, "the pathfinder receives the tower height")
equal(arrow.label.text, "Orgrimmar zeppelin tower", "names the boarding point")
equal(arrow.goal.text, "On the way to Undercity", "keeps the final destination visible")
boarded = true
Navigation:UpdateArrow()
equal(arrow.label.text, "Take the zeppelin to Undercity", "shows the boarding instruction")
equal(Navigation:GetWaypoint(), trip, "the destination survives boarding")
assert(requests[#requests].cancelled and not arrow.head.shown, "no walking route or bearing during the ride")
