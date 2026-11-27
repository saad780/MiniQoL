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
-- Follow a route using the bundled follower and switch bearings in place.
---------------------------------------------------------------------------
local requests = {}
local covered = true
local indoors, clearGround, floorCount = true, false, 1
local floorReads, sightReads = 0, 0
ns.db.settings.followWalkingRoute = true
ns.Walking = { Nav = {}, Compat = { GetPlayerFaction = function() return "Alliance" end,
    IsOnTaxi = function() return false end, IsIndoors = function() return indoors end } }
assert(loadfile(root .. "/Modules/Wayfinder/Vendor/PolestarWalking/Follow.lua"))("Wayfinder", ns)
ns.Walking.Nav.Path = {
    SurfacesAt = function(_, _, _, out)
        floorReads = floorReads + 1
        out[1], out[2] = 10, 54
        return floorCount
    end,
    Sight = function(_, _, _, z, _, _, _, faction)
        sightReads = sightReads + 1
        return clearGround and z == 10 and faction == "Alliance"
    end,
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
local function advance(frames, elapsed)
    for _ = 1, frames do
        now = now + elapsed
        arrow.scripts.OnUpdate(arrow, elapsed)
    end
end

Navigation:AddWaypoint(1, 400, 650, "Across the river", 1429)
equal(#requests, 0, "defers the walking search in combat")
inCombat = false
Navigation:UpdateArrow()
equal(#requests, 1, "starts the walking search after combat")
local balanced = requests[1]
equal(balanced.options.style, "balanced", "older profiles default to Balanced")
equal(balanced.options.profile, "Alliance", "routes with the player's faction")
assert(arrow.head.shown and arrow.bearingFrame == 32, "the objective is due west while the trail is being found")
equal(Navigation:GetTrail(), nil, "wait for the route before drawing its trail")

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
assert(arrow.head.shown and arrow.bearingFrame == 32 and not Navigation:GetTrail(), "a stale result changes neither bearing nor trail")

SetStyle("roads")
local roads = requests[3]
assert(direct.cancelled, "Direct is retired on switching to Roads Always")
equal(roads.options.style, "roads", "Roads Always uses Polestar's Roads style")
roads.done({ roads.from, { x = 430, y = 600 }, roads.to })
Navigation:UpdateArrow()
assert(arrow.head.shown, "the completed route shows a bearing")
advance(3, 1/60)
assert(arrow.bearingFrame > 0 and arrow.bearingFrame < 32, "the first walking aim eases away from the pending direct bearing")
advance(80, 1/60)
equal(arrow.bearingFrame, 0, "points north toward the turn around the obstacle")
-- 30 yd north to the bend, then 58 yd on to the waypoint: the walk, not the
-- 50 yd straight line across the river.
equal(arrow.distance.text, "88 yd", "yardage is the walk left to the leg destination")
ns.db.settings.arrowTime = true
local unitSpeed = { 0, 7 }
function GetUnitSpeed() return unitSpeed[1], unitSpeed[2] end
Navigation:UpdateArrow()
equal(arrow.distance.text, "88 yd  |cffbfbfbf13 s|r", "standing still, the time is at running speed")
unitSpeed[1] = 14
Navigation:UpdateArrow()
equal(arrow.distance.text, "88 yd  |cffbfbfbf6 s|r", "moving, at the speed you go")
unitSpeed[1] = 0.1
Navigation:UpdateArrow()
equal(arrow.distance.text, "88 yd  |cffbfbfbf13 s|r", "a creep counts as standing still")
equal(Navigation.FormatDuration(185), "3:05", "minutes and seconds")
equal(Navigation.FormatDuration(3900), "1 h 05 m", "hours and minutes")
ns.db.settings.arrowTime = false
GetUnitSpeed = nil
local function SetRouteArrow(enabled)
    ns.db.settings.followWalkingRoute = enabled
    ns:Fire("SETTING_CHANGED", "followWalkingRoute")
end
SetRouteArrow(false)
equal(arrow.bearingFrame, 32, "switches back to the direct bearing to the waypoint")
SetRouteArrow(true)
equal(arrow.bearingFrame, 0, "switches back to the same walking turn immediately")
equal(#requests, 3, "switching the arrow never restarts the search")
-- The walking trail takes the detour around the river.
local cont, endX, endY, xs, ys, idx = Navigation:GetTrail()
equal(cont, 1, "the trail is on the player's continent")
equal(endX, 400, "it ends at the waypoint")
equal(endY, 650, "on both axes")
equal(xs[idx], 430, "from the route's next point")
equal(ys[idx], 600, "north of the player, on the route")
equal(#xs, 3, "along the whole route")
local originalPosition = ns.GetPlayerWorld
ns.GetPlayerWorld = function() return 1, 430, 600, 1429 end
Navigation:UpdateArrow()
advance(80, 1/60)
equal(arrow.bearingFrame, 43, "once at the river bend the arrow turns down the next stretch")
ns.GetPlayerWorld = originalPosition

local nextWaypoint = Navigation:AddWaypoint(1, 420, 650, "Another destination", 1429)
assert(Navigation:GetWaypoint() == nextWaypoint, "placing a new waypoint changes the route")
local nextJob = requests[4]
nextJob.done(nil, "unreachable")
Navigation:UpdateArrow()
assert(arrow.head.shown and arrow.bearingFrame == 24, "the objective still has a bearing when the trail is blocked")
equal(arrow.distance.text, "No walking route", "reports the blocked walk")
equal(Navigation:GetTrail(), nil, "and no trail is drawn through them")

covered = false
Navigation:AddWaypoint(1, 420, 650, "Outside walking coverage", 1429)
assert(arrow.head.shown, "straight bearings still work on unmapped ground")
equal(arrow.distance.text, "54 yd", "reports the distance to the original waypoint")
cont, endX, endY, xs = Navigation:GetTrail()
assert(cont == 1 and endX == 420 and endY == 650 and xs == nil, "the trail runs straight at it too")
print("Walking arrow and trail: route turns, live direct-bearing toggle, route styles, stale searches and fallback passed")

-- An intercontinental destination stays selected while its local stop drives
-- the walking path. Being at the dock must never clear the final pin.
local stage = { c=1, x=460, y=600, m=1429, z=54, n="Orgrimmar zeppelin tower" }
local boarded = false
ns.Travel = { Aim = function()
    if boarded then return nil, "Take the zeppelin to Undercity", nil, true end
    if stage then return stage, nil, stage.n end
end, Reset = noop }
covered = true
ns.db.settings.clearOnArrival = true
local trip = Navigation:AddWaypoint(0, 1570, 270, "Undercity", 1429)
equal(requests[#requests].to.x, stage.x, "walking search aims at the local boarding point")
equal(requests[#requests].to.z, 54, "the pathfinder receives the tower height")
assert(arrow.head.shown and arrow.bearingFrame == 0, "an overseas goal uses the direct bearing to the local tower")
equal(arrow.label.text, "Orgrimmar zeppelin tower", "names the boarding point")
equal(arrow.goal.text, "On the way to Undercity", "keeps the final destination visible")
boarded = true
Navigation:UpdateArrow()
equal(arrow.label.text, "Take the zeppelin to Undercity", "shows the boarding instruction")
equal(Navigation:GetWaypoint(), trip, "the destination survives boarding")
assert(requests[#requests].cancelled and not arrow.head.shown, "no walking route or bearing during the ride")
equal(Navigation:GetTrail(), nil, "nor an ant trail")

boarded = false
Navigation:UpdateArrow()
local oldApproach = requests[#requests]
ns:Fire("TRAVEL_ORIGIN_CHANGED")
assert(oldApproach.cancelled, "relocation cancels a walk calculated from the old position")
Navigation:UpdateArrow()
assert(requests[#requests] ~= oldApproach and Navigation:GetWaypoint() == trip,
    "calculate a new approach even when the next stop and final pin are identical")

-- A flight or boat on this continent still has two distinct destinations.
local localTrip = Navigation:AddWaypoint(1, 400, 800, "Quest across the bay", 1429)
Navigation:UpdateArrow()
local approach = requests[#requests]
approach.done({ approach.from, {x=400, y=570}, approach.to })
Navigation:UpdateArrow()
advance(80, 1/60)
assert(arrow.head.shown and arrow.bearingFrame == 96 and arrow.distance.text == "97 yd", "walks east around the obstacle on the approach to the tower (30 yd, then 67 yd)")
equal(arrow.label.text, stage.n, "names the transport stop")
equal(arrow.goal.text, "On the way to " .. localTrip.n, "keeps the quest in view")
cont, endX, endY, xs, ys, idx = Navigation:GetTrail()
assert(endX == stage.x and endY == stage.y and xs[idx] == 400 and ys[idx] == 570, "trail turns east on the way to the tower")
boarded = true
Navigation:UpdateArrow()
assert(not arrow.head.shown and not Navigation:GetTrail(), "keep the boarding action until departure")
equal(arrow.label.text, "Take the zeppelin to Undercity", "shows what to board")
boarded, covered = false, false
stage = { c=1, x=400, y=550, m=1429, n="Flight master" }
Navigation:UpdateArrow()
assert(arrow.head.shown and arrow.bearingFrame == 96 and arrow.distance.text == "50 yd", "leads east to the next connection")
stage = nil
Navigation:UpdateArrow()
assert(arrow.head.shown and arrow.bearingFrame == 32 and arrow.distance.text == "200 yd", "after the last transfer the objective is due west")
equal(arrow.label.text, localTrip.n, "restores the quest name")

-- In open ground the road runs north at y=600. Join diagonally from its
-- east side, skipping the perpendicular approach and the next short bend.
local px, py = 400, 560
ns.GetPlayerWorld = function() return 1, px, py, 1429 end
covered, indoors, clearGround = true, false, true
local function roadRoute(name)
    Navigation:AddWaypoint(1, 600, 600, name, 1429)
    local job = requests[#requests]
    job.done({ job.from, {x=400,y=600,z=10}, {x=420,y=600,z=10}, {x=600,y=600,z=10} })
    Navigation:UpdateArrow()
end
roadRoute("North road")
advance(80, 1/60)
local requestCount = #requests
local _, _, _, _, _, from, joinX, joinY = Navigation:GetTrail()
assert(joinX and joinX > 420 and joinY == 600 and from == 4, "the dots join at the reachable forward aim and continue past it")
assert(arrow.bearingFrame > 0 and arrow.bearingFrame < 16, "the arrow leads diagonally onto the road")
local firstBearing, firstReads, firstSurfaces = arrow.bearingFrame, sightReads, floorReads
for i = 1, 20 do now = now + .04; Navigation:UpdateArrow() end
assert(sightReads == firstReads and floorReads == firstSurfaces and arrow.bearingFrame == firstBearing, "stationary look-ahead reuses its terrain checks")
px, now = 445, 12
Navigation:UpdateArrow()
assert(#requests == requestCount and arrow.bearingFrame < 16, "running parallel 40 yards off the road keeps the forward aim")
-- Across an uncrossable barrier: retain the current leg's guidance while the
-- new search runs. A change of destination must drop that old aim immediately.
clearGround, px, py, now = false, 470, 485, 24
Navigation:UpdateArrow()
assert(#requests == requestCount + 1 and Navigation:GetTrail(), "a substantial deviation starts a replacement without dropping the trail")
local pending = requests[#requests]
floorCount, clearGround = 2, true
roadRoute("Other side of the ridge")
assert(pending.cancelled and not select(7, Navigation:GetTrail()), "overlapping floors cannot authorize an outdoor shortcut")
local newBearing = arrow.bearingFrame
pending.done({ pending.from, { x = 200, y = 100 }, pending.to })
Navigation:UpdateArrow()
equal(arrow.bearingFrame, newBearing, "a late route from a retired leg cannot take the arrow back")

-- Feed a measured heading into the real arrow frame independently of how the
-- walking grid chose it. The waypoint starts due north, as does the first aim.
local sampleAngle = 0
ns.Walking.Nav.follow.Step = function(_, _, _, _, _, state, x, y)
    state.idx, state.off = 2, 0
    return x + 40 * math.cos(math.rad(sampleAngle)), y + 40 * math.sin(math.rad(sampleAngle))
end
local steadyGoal = Navigation:AddWaypoint(1, px + 200, py, "Steady road", 1429)
local steadyJob = requests[#requests]
steadyJob.done({ steadyJob.from, steadyJob.to })
for _, degrees in ipairs({0.5, 1, 1.6, 2.2, 2.9, 1.4, -2.9}) do
    sampleAngle = degrees
    advance(24, 1/60)
    equal(arrow.bearingFrame, 0, "small sustained route changes leave the needle still")
end
sampleAngle = 8
advance(70, 1/60)
equal(arrow.bearingFrame, 3, "a gradual real change eventually moves the needle")

-- Looking just to either side of a sprite boundary should keep the needle
-- still, while a deliberate turn of the character reads on the next frame.
local facing = 0
function GetPlayerFacing() return facing end
for _, halfFrame in ipairs({0.48,0.52,0.49,0.51}) do
    facing = math.rad(8 - (2 + halfFrame) * 360/128)
    advance(1, 1/144)
    equal(arrow.bearingFrame, 3, "no flicker between neighbouring atlas frames")
end
facing = math.pi / 2
advance(1, 1/144)
equal(arrow.bearingFrame, 99, "turning the character responds before the next route sample")
facing = 0
sampleAngle = 175
advance(4, 1/60)
assert(arrow.bearingFrame > 3 and arrow.bearingFrame < 12, "a large route change starts smoothly")
advance(130, 1/60)
equal(arrow.bearingFrame, 62, "the needle catches the new turn")
sampleAngle = -175
for i = 1, 90 do
    advance(1, 1/60)
    assert(arrow.bearingFrame >= 62 and arrow.bearingFrame <= 66, "crosses south by the short arc")
end
equal(arrow.bearingFrame, 66, "arrives on the far side of the angle seam")
sampleAngle = 80
advance(3, 1/60)
SetRouteArrow(false)
equal(arrow.bearingFrame, 0, "direct mode cancels a turn in progress immediately")
assert(Navigation:GetWaypoint() == steadyGoal)

ns.GetPlayerWorld = function() end
Navigation:UpdateArrow()
assert(not arrow.head.shown and not Navigation:GetTrail(), "no bearing is available during a loading screen")
