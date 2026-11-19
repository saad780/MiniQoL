-- "Track my location": the map button moves the map to the player and keeps
-- it on them as they move, until the player takes the map themselves.
local root = ...
local function noop() end

---------------------------------------------------------------------------
-- The client: a world map with two zones and a continent
---------------------------------------------------------------------------
local ELWYNN, WESTFALL, CONTINENT, STORMWIND = 1429, 1436, 947, 84
local playerMap, playerX, playerY = ELWYNN, 0.40, 0.60
C_Map = {
    GetBestMapForUnit = function() return playerMap end,
    GetPlayerMapPosition = function(mapID)
        if mapID ~= playerMap then return nil end
        return { GetXY = function() return playerX, playerY end }
    end,
}
local combat = false
function InCombatLockdown() return combat end
local now = 0
function GetTime() return now end

local function NewFrame()
    local frame = { scripts = {}, hooks = {} }
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    function frame:GetScript(name) return self.scripts[name] end
    function frame:HookScript(name, fn) self.hooks[name] = fn end
    function frame:CreateTexture() return NewFrame() end
    function frame:SetShown(shown) self.shown = shown == true end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:SetDesaturated(value) self.desaturated = value end
    function frame:SetVertexColor(r, g, b) self.colour = { r, g, b } end
    return setmetatable(frame, { __index = function(self, key)
        if type(key) ~= "string" or not key:find("^%u") then return nil end
        rawset(self, key, noop)
        return noop
    end })
end
function CreateFrame() return NewFrame() end

local pans, mapChanges = {}, 0
local hooks = {}
function hooksecurefunc(owner, name, fn)
    hooks[owner] = hooks[owner] or {}
    hooks[owner][name] = fn
end
local canvas = NewFrame()
canvas.mouseButtonInfo = { LeftButton = { down = false }, RightButton = { down = false } }
function canvas:CalculateScrollExtentsAtScale() return 0.1, 0.9, 0.1, 0.9 end
function canvas:GetCanvasScale() return 2 end
WorldMapFrame = NewFrame()
WorldMapFrame.ScrollContainer = canvas
WorldMapFrame.mapID, WorldMapFrame.zoomedIn = CONTINENT, true
function WorldMapFrame:IsShown() return true end
function WorldMapFrame:GetMapID() return self.mapID end
function WorldMapFrame:SetMapID(mapID)
    self.mapID = mapID
    mapChanges = mapChanges + 1
    if hooks[self] and hooks[self].OnMapChanged then hooks[self].OnMapChanged(self) end
end
function WorldMapFrame:IsAtMinZoom() return not self.zoomedIn end
function WorldMapFrame:PanTo(x, y) pans[#pans + 1] = { x, y } end
function WorldMapFrame:GetCanvasContainer() return NewFrame() end

GameTooltip = { lines = {} }
function GameTooltip:SetOwner(owner) self.owner, self.lines = owner, {} end
function GameTooltip:SetText(text) self.title = text end
function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
function GameTooltip:Show() end
function GameTooltip:IsOwned(owner) return self.owner == owner end
GameTooltip_Hide = noop
StaticPopupDialogs = {}

---------------------------------------------------------------------------
-- Wayfinder around the navigation module
---------------------------------------------------------------------------
local ns = { db = { waypoints = {}, settings = {} } }
function ns:NewModule(name) self[name] = { name = name }; return self[name] end
function ns.Readable(value) return value ~= nil end
local detail = { active = false, dragging = false, centred = 0 }
ns.DetailView = {
    IsActive = function() return detail.active end,
    IsDragging = function() return detail.active and detail.dragging end,
    CenterOnPlayer = function() detail.centred = detail.centred + 1; return true end,
    Exit = function() detail.active = false end,
}
local switching = false
ns.ContinuousEngine = { MapStitch = { Switching = function() return switching end } }
ns.ContinuousMap = { IsActive = function() return false end }
-- The player as the continuous map's API sees them, in world units.
function ns.GetPlayerWorld() return 1, playerX * 100, playerY * 100, playerMap, playerX, playerY end
MiniQoLRuntime = { Execute = function(_, _, fn) return fn("Wayfinder", ns) end }
assert(loadfile(root .. "/Modules/Wayfinder/OpenMapCompat.lua"))("Wayfinder", ns)
assert(loadfile(root .. "/Modules/Wayfinder/Navigation.lua"))("Wayfinder", ns)
local Navigation = ns.Navigation
Navigation:HookWorldMap()
local button = Navigation.locateButton
assert(button, "the button is on the map")

local function equal(actual, expected, label)
    assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function tick(seconds)
    seconds = seconds or 0.05
    now = now + seconds
    button.scripts.OnUpdate(button, seconds)
end
local function click() button.scripts.OnClick(button, "LeftButton") end
local function lastPan() return pans[#pans] end
local function start()
    if not Navigation:IsTracking() then click() end
    assert(Navigation:IsTracking(), "tracking started")
end

---------------------------------------------------------------------------
-- 1. The button and what it says
---------------------------------------------------------------------------
button.scripts.OnEnter(button)
equal(GameTooltip.title, "Track my location", "the button is named for tracking")
assert(GameTooltip.lines[1]:find("follows you", 1, true), "and says it follows you")
assert(not button.lit.shown, "unlit while not tracking")

click()
equal(Navigation:IsTracking(), true, "a click starts tracking")
equal(WorldMapFrame.mapID, ELWYNN, "and moves the map to the player's zone")
assert(button.lit.shown and button.icon.desaturated, "the button lights up")
equal(GameTooltip.title, "Tracking my location", "the open tooltip follows")

---------------------------------------------------------------------------
-- 2. Following the player
---------------------------------------------------------------------------
tick()
equal(lastPan()[1], 0.40, "the map is slid to the player")
playerX, playerY = 0.45, 0.62
tick()
equal(lastPan()[1], 0.45, "and follows them as they move")
equal(lastPan()[2], 0.62, "on both axes")
local count = #pans
tick(0.01)
equal(#pans, count, "a few times a second, not every frame")
playerX = 0.95
tick()
equal(lastPan()[1], 0.9, "kept inside what the map can scroll to")
WorldMapFrame.zoomedIn = false
count = #pans
tick()
equal(#pans, count, "a map zoomed all the way out already shows them")
WorldMapFrame.zoomedIn = true

-- Over the border into the next zone.
playerMap, playerX = WESTFALL, 0.05
tick()
equal(WorldMapFrame.mapID, WESTFALL, "the map turns to the next zone")
equal(Navigation:IsTracking(), true, "and that is not taken as the player leaving")

-- Never mid-fight.
combat, playerMap = true, ELWYNN
tick()
equal(WorldMapFrame.mapID, WESTFALL, "in combat the map is left alone")
combat = false
tick()
equal(WorldMapFrame.mapID, ELWYNN, "and turns once the fight is over")

---------------------------------------------------------------------------
-- 3. Taking the map back
---------------------------------------------------------------------------
canvas.hooks.OnMouseDown(canvas, "MiddleButton")
equal(Navigation:IsTracking(), true, "a middle-click sets a waypoint and keeps tracking")
canvas.hooks.OnMouseDown(canvas, "LeftButton")
equal(Navigation:IsTracking(), false, "pressing on the map to drag it stops tracking")
assert(not button.lit.shown and not button.icon.desaturated, "and the button goes back to gold")
count = #pans
tick()
equal(#pans, count, "the map is left where the player puts it")

start()
canvas.hooks.OnMouseDown(canvas, "RightButton")
equal(Navigation:IsTracking(), false, "a right-click stops it too")

-- A press that reaches the map through one of its icons.
start()
canvas.mouseButtonInfo.LeftButton.down = true
tick()
equal(Navigation:IsTracking(), false, "a press carried by the map stops it")
canvas.mouseButtonInfo.LeftButton.down = false

-- Already held when tracking starts: only a new press counts.
canvas.mouseButtonInfo.LeftButton.down = true
start()
tick()
equal(Navigation:IsTracking(), true, "a button held from before is not a new press")
canvas.mouseButtonInfo.LeftButton.down = false
tick()
canvas.mouseButtonInfo.LeftButton.down = true
tick()
equal(Navigation:IsTracking(), false, "the next press is")
canvas.mouseButtonInfo.LeftButton.down = false

-- Picking another map.
start()
WorldMapFrame:SetMapID(STORMWIND)
equal(Navigation:IsTracking(), false, "choosing another map stops tracking")

-- The button again.
start()
click()
equal(Navigation:IsTracking(), false, "clicking the button again stops it")

---------------------------------------------------------------------------
-- 4. The detail view
---------------------------------------------------------------------------
start()
detail.active = true
count = #pans
local centred = detail.centred
tick()
equal(detail.centred, centred + 1, "the detail view is kept on the player")
equal(#pans, count, "without moving the map under it")
detail.dragging = true
tick()
equal(Navigation:IsTracking(), false, "dragging the detail view stops tracking")
detail.active, detail.dragging = false, false

---------------------------------------------------------------------------
-- 5. The continuous map
---------------------------------------------------------------------------
local follows, glides = {}, {}
local api = { major = 1, IsStitched = function() return true end,
    WorldFromMap = function(_, x, y) return x * 10, y * 10 end,
    ShowWorld = function(u, v) glides[#glides + 1] = { u, v } end,
    FollowWorld = function(u, v) follows[#follows + 1] = { u, v } end }
OpenMapAPI = api
start()
playerX, playerY = 0.5, 0.5
tick()
equal(#follows, 1, "the continuous map eases along with the player")
equal(follows[1][1], 5, "to where they are")
equal(#pans, count, "rather than through the plain map's panning")
switching = true
WorldMapFrame:SetMapID(CONTINENT)
equal(Navigation:IsTracking(), true, "the map underneath changing with the view keeps tracking")
switching = false

-- OpenMap's own API can only glide, so it is asked twice a second at most.
api.FollowWorld = nil
local before = #glides
for _ = 1, 10 do
    playerX = playerX + 0.01
    tick()
end
equal(#glides - before, 1, "half a second of walking is one glide")
OpenMapAPI = nil
click()

print("Map tracking: follows the player and over zone borders, stops when the map is taken, detail view, continuous map passed")
