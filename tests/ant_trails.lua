-- Ant trails: dots marching from the player along the walking route, on
-- the continuous world map and on the minimap.
local root = ...
local function noop() end
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function near(actual, expected, label)
    assert(type(actual) == "number" and math.abs(actual - expected) < 1e-6,
        label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

---------------------------------------------------------------------------
-- Frames and textures that remember where they were put
---------------------------------------------------------------------------
local textures = 0
local methods = {}
local function New(parent)
    return setmetatable({ parent = parent, scripts = {}, shown = true, level = 1 }, { __index = methods })
end
function methods:SetScript(name, fn) self.scripts[name] = fn end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end
function methods:SetPoint(point, relativeTo, relativePoint, x, y)
    self.point = { point, relativeTo, relativePoint, x, y }
end
function methods:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
function methods:SetFrameLevel(level) self.level = level end
function methods:GetFrameLevel() return self.level end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:CreateTexture()
    textures = textures + 1
    return New(self)
end
for _, name in ipairs({ "SetAllPoints", "SetClipsChildren", "EnableMouse", "SetTexture", "SetSize",
    "SetSnapToPixelGrid", "SetTexelSnappingBias" }) do
    methods[name] = noop
end
function CreateFrame(_, _, parent) return New(parent) end

local now = 0
function GetTime() return now end
EventUtil = { ContinueOnAddOnLoaded = function(_, fn) fn() end }

-- The world map: a 500 by 500 view of a world where 1000 yards is a tenth.
local sc = New()
sc.width, sc.height, sc.level = 500, 500, 10
WorldMapFrame = New()
WorldMapFrame.ScrollContainer = sc
function WorldMapFrame:GetCanvasContainer() return self end
local stitched = true
local controller = {
    IsStitched = function() return stitched end,
    ViewNow = function() if stitched then return 0.5, 0.5, 10 end end,
    ViewHalfExtents = function() return 0.05, 0.05 end,
}
local S = { artTop = 300 }
function S.FromYards(cont, wx, wy)
    if cont == 1 then return wy / 10000, wx / 10000 end
end
-- (so a point's pixels on the map are 0.5 * yards - 2250 on each axis)

-- The minimap: 140 pixels across, 100 yards from the middle to the edge.
Minimap = New()
Minimap.width, Minimap.height, Minimap.level = 140, 140, 20
local viewRadius, rotate, facing, shape = 100, false, 0, "ROUND"
C_Minimap = { GetViewRadius = function() return viewRadius end }
function GetCVarBool(name) return name == "rotateMinimap" and rotate end
function GetPlayerFacing() return facing end
function GetMinimapShape() return shape end

local unitNorth, unitWest, unitInstance = 4600, 4600, 1
function UnitPosition() return unitNorth, unitWest, 0, unitInstance end

local settings = { antTrails = true, antTrailsWhere = "both", antTrailColor = "cyan" }
local listeners, events = {}, {}
local ns = { ContinuousEngine = { MapStitch = S } }
function ns.ContinuousEngine:GetModule(name) return name == "worldmap" and controller or nil end
function ns:NewModule(name) self[name] = {}; return self[name] end
function ns:GetSetting(key) return settings[key] end
function ns:On(message, fn) listeners[message] = fn end
function ns:RegisterEvent(event, fn) events[event] = fn end
function ns.Readable(value) return value ~= nil end
function ns.GetPlayerWorld() return unitInstance, unitNorth, unitWest end
local trail
ns.Navigation = { GetTrail = function() if trail then return unpack(trail, 1, 8) end end }
local function set(key, value)
    settings[key] = value
    listeners.SETTING_CHANGED(key)
end

MiniQoLRuntime = { Execute = function(_, _, fn) return fn("Wayfinder", ns) end }
assert(loadfile(root .. "/Modules/Wayfinder/AntTrails.lua"))("Wayfinder", ns)
local Ants = ns.AntTrails
Ants:OnLogin()
local map, mini = Ants.map, Ants.mini
assert(map.frame and mini.frame, "a layer on each surface")
local function drawMap() map.frame.scripts.OnUpdate(map.frame) end
local function drawMini() mini.frame.scripts.OnUpdate(mini.frame) end
-- The dots now on a surface, as { x, y } in its own offsets.
local function dots(surface)
    local list = {}
    for i = 1, surface.shown do
        local dot = surface.dots[i]
        assert(dot.shown and dot.shadow.shown, "dot " .. i .. " is shown with its edge")
        list[i] = { dot.point[4], dot.point[5] }
    end
    for i = surface.shown + 1, #surface.dots do
        assert(not surface.dots[i].shown and not surface.dots[i].shadow.shown, "dot " .. i .. " is hidden")
    end
    return list
end

---------------------------------------------------------------------------
-- 1. On the world map: from the player, every 18 pixels, marching onward
---------------------------------------------------------------------------
trail = { 1, 4600, 5000 } -- straight at a waypoint 400 yards west of the player
drawMap()
local list = dots(map)
equal(#list, 12, "a dot every 18 pixels along 200")
for i, dot in ipairs(list) do
    near(dot[1], 50 + (i - 1) * 18, "dot " .. i .. " across")
    near(dot[2], -50, "dot " .. i .. " down (the map's offsets grow upward)")
end
equal(map.dots[1].point[3], "TOPLEFT", "placed from the view's corner")
equal(map.frame.level, 302, "over the map's art and terrain, under its icons")
now = 0.2
drawMap()
list = dots(map)
near(list[1][1], 50 + 0.2 * 1.5 * 18, "a fifth of a second on, every dot has moved toward the waypoint")
near(list[2][1], 50 + 18 + 5.4, "together")
equal(#list, 11, "the last one has reached the end and gone")

---------------------------------------------------------------------------
-- 2. Along a route, round its corners, from its next point on
---------------------------------------------------------------------------
now = 0
-- Route points 1 and 2 are behind the player; 2 is the next. Then a turn south.
trail = { 1, 4800, 4900, { 4500, 4600, 4800 }, { 4500, 4800, 4800 }, 2 }
drawMap()
list = dots(map)
equal(#list, 14, "250 pixels of route: 100 across, 100 down, 50 across")
near(list[6][1], 140, "the sixth dot, 90 pixels along, is still on the first leg")
near(list[6][2], -50, "at the player's height")
near(list[7][1], 150, "the seventh, 108 along, has turned the corner")
near(list[7][2], -58, "8 pixels down the second leg")
near(list[13][1], 166, "the 13th, 216 along, is on the last leg")
near(list[13][2], -150, "at the bottom")

-- A route that stops short of the waypoint ends where it does.
trail = { 1, nil, nil, { 4600, 4600 }, { 4600, 4800 }, 2 }
drawMap()
equal(#dots(map), 6, "100 pixels and no further")

-- Cut diagonally onto a road at the follower's confirmed join, then head
-- north. The perpendicular approach behind the join is no longer drawn.
trail = { 1, 4800, 4650, {4600, 4600, 4800}, {4600, 4650, 4650}, 3, 4650, 4650 }
drawMap(); drawMini()
local onMap, onMini = dots(map), dots(mini)
near(onMap[2][1] - onMap[1][1], 18 / math.sqrt(2), "world map dots start toward the forward join")
near(onMini[1][1], -onMini[1][2], "minimap dots use the same diagonal")
assert(onMini[1][2] > 0 and onMini[1][1]^2 + onMini[1][2]^2 >= 16^2, "the join leaves room for the player icon")

---------------------------------------------------------------------------
-- 3. Only what is in view, and never more than 400 dots
---------------------------------------------------------------------------
trail = { 1, 4600, 6000 } -- 700 pixels, off the right edge at 500
drawMap()
list = dots(map)
equal(#list, 26, "dots up to the view's edge")
assert(list[#list][1] <= 504, "none past it")
unitWest = 3000 -- the player far off to the left, out of view
drawMap()
list = dots(map)
assert(list[1][1] >= -4, "the trail comes into view at the edge")
unitWest = 4600

local xs, ys = {}, {}
for i = 1, 100 do -- a route back and forth across the whole view, 100 times
    xs[i], ys[i] = 4500 + (i % 2) * 0.01, i % 2 == 0 and 4500 or 5500
end
trail = { 1, nil, nil, xs, ys, 1 }
drawMap()
equal(map.shown, 400, "capped at 400 dots")
equal(#map.dots, 400, "and no more made")
local made = textures

---------------------------------------------------------------------------
-- 4. Nothing to draw
---------------------------------------------------------------------------
trail = nil
drawMap()
equal(#dots(map), 0, "no way shown, no trail")
trail = { 1, 4600, 5000 }
stitched = false
drawMap()
equal(#dots(map), 0, "the plain world map has none")
stitched = true
unitInstance = 2
drawMap()
equal(#dots(map), 0, "nor when the player is on another continent")
unitInstance = 1
drawMap()
equal(#dots(map), 12, "back")
equal(textures, made, "dots are reused, not made again")

---------------------------------------------------------------------------
-- 5. On the minimap: beyond the player arrow, rotating with it, inside its face
---------------------------------------------------------------------------
trail = { 1, 4660, 4600 } -- 60 yards north: 42 pixels up
drawMini()
list = dots(mini)
equal(#list, 3, "three dots clear the player arrow on a 42-pixel leg")
for i, dot in ipairs(list) do
    near(dot[1], 0, "straight up the middle")
    near(dot[2], 16 + (i - 1) * 11, "dot " .. i .. " up")
end
equal(mini.dots[1].point[3], "CENTER", "placed from the minimap's middle")
equal(mini.frame.level, 25, "over the minimap, under Wayfinder's service icons")
now = 0.25
drawMini()
list = dots(mini)
near(list[1][2], 18.75, "the minimap advances 2.75 pixels in a quarter second")
near(list[2][2] - list[1][2], 11, "slowing the dots keeps their spacing")
now = 0.99
drawMini()
near(dots(mini)[1][2], 26.89, "the first dot stays within one spacing of the clearance at the end of its cycle")
now = 0

rotate, facing = true, math.pi / 2 -- facing west: north is to the right
events.CVAR_UPDATE("CVAR_UPDATE", "rotateMinimap")
drawMini()
list = dots(mini)
near(list[2][1], 27, "a rotating minimap turns the trail with it")
near(list[2][2], 0, "to the right")
rotate, facing = false, 0
events.CVAR_UPDATE("CVAR_UPDATE", "rotateMinimap")

trail = { 1, 5000, 4600 } -- 400 yards north, far past the edge
drawMini()
list = dots(mini)
equal(#list, 5, "round: dots clear the arrow and stay inside the rim")
shape = "SQUARE"
events.CVAR_UPDATE("CVAR_UPDATE", "rotateMinimap")
viewRadius = 100
drawMini()
equal(#dots(mini), 5, "square: the same straight up")
trail = { 1, 5000, 4200 } -- north-east, toward a square's corner
drawMini()
local square = #dots(mini)
shape = "ROUND"
events.CVAR_UPDATE("CVAR_UPDATE", "rotateMinimap")
drawMini()
assert(square > #dots(mini), "a square minimap shows more of a trail into its corner")

-- A switchback passing over the arrow must keep the same gap on its return.
trail = { 1, nil, nil, { 4650, 4550 }, { 4550, 4650 }, 1 }
for _, phase in ipairs({ 0, 0.25, 0.55, 0.99, 1 }) do
    now = phase
    drawMini()
    local outbound, beyond = false, false
    for _, dot in ipairs(dots(mini)) do
        assert(dot[1]^2 + dot[2]^2 >= 16^2, "the arrow stays clear throughout the animation")
        if dot[1] > 0 then outbound = true elseif dot[1] < 0 then beyond = true end
    end
    assert(outbound and beyond, "the route is visible on both sides of the arrow")
end

viewRadius = 200 -- zoomed out: the same yards, half the pixels
trail = { 1, 4640, 4600 } -- 14 pixels from the player
drawMini()
equal(#dots(mini), 0, "a destination inside the clearance leaves the arrow visible")
trail = { 1, 4660, 4600 } -- 21 pixels from the player
drawMini()
equal(#dots(mini), 1, "a short leg just beyond the arrow can show a dot")
trail = { 1, 4720, 4600 }
drawMini()
list = dots(mini)
equal(#list, 3, "42 pixels of trail at the new zoom")
near(list[1][2], 16, "clearance stays the same size at the new zoom")

---------------------------------------------------------------------------
-- 6. Settings
---------------------------------------------------------------------------
drawMap()
assert(map.shown > 0 and mini.shown > 0, "both surfaces by default")
set("antTrailColor", "gold")
local color = map.dots[1].color
assert(color[1] == 1 and color[2] == 0.82, "a new color reaches the dots already made")
color = mini.dots[1].color
assert(color[1] == 1 and color[2] == 0.82, "on both surfaces")
set("antTrailsWhere", "map")
drawMap(); drawMini()
assert(map.shown > 0 and mini.shown == 0, "the world map only")
set("antTrailsWhere", "minimap")
drawMap(); drawMini()
assert(map.shown == 0 and mini.shown > 0, "the minimap only")
set("antTrailsWhere", "both")
set("antTrails", false)
drawMap(); drawMini()
assert(map.shown == 0 and mini.shown == 0, "off: none anywhere")

---------------------------------------------------------------------------
-- 7. A quest area's outline: drawn while you're in it and no trail leads on
---------------------------------------------------------------------------
local area
ns.Navigation.GetArea = function() if area then return unpack(area, 1, 3) end end
trail = nil
area = { 1, { unitNorth - 40, unitNorth + 40, unitNorth + 40, unitNorth - 40 },
    { unitWest - 40, unitWest - 40, unitWest + 40, unitWest + 40 } }
drawMap(); drawMini()
assert(map.shown == 0 and mini.shown == 0, "without the quest area setting, nothing")
settings.questAreas = true
drawMap(); drawMini()
assert(map.shown > 0 and mini.shown > 0, "the outline on both surfaces, though the trails are off")
local around = 0
for _, dot in ipairs(dots(mini)) do around = math.max(around, math.abs(dot[1]), math.abs(dot[2])) end
assert(around > 10, "around the player, not on them")
set("antTrails", true)
set("antTrailsWhere", "minimap")
drawMap(); drawMini()
assert(map.shown == 0 and mini.shown > 0, "with the trails on, wherever they show")
trail = { 1, unitNorth + 300, unitWest }
area = nil
drawMini()
assert(mini.shown > 0, "and the trail again once you've left the area")
set("antTrailsWhere", "both")

print("Ant trails: spaced and marching from the player, round route corners, clipped to the view and capped, minimap rotation and shape, settings, quest area outlines passed")
