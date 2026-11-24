local root = ...
local function near(actual, expected, label)
    assert(math.abs(actual - expected) < 0.000001, (label or "coordinate") .. ": " .. tostring(actual))
end
local function noop() end
local frames = {}
function CreateFrame()
    local f = { scripts = {}, hooks = {}, shown = false }
    function f:SetScript(event, fn) self.scripts[event] = fn end
    function f:HookScript(event, fn)
        local before = self.hooks[event]
        self.hooks[event] = before and function(...) before(...); fn(...) end or fn
    end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    frames[#frames + 1] = f
    return f
end
-- (as the game's: after the original, and a global function by its name)
function hooksecurefunc(object, key, fn)
    if type(object) == "string" then object, key, fn = _G, object, key end
    local original = object[key]
    assert(type(original) == "function", "hooking a function that isn't there: " .. tostring(key))
    object[key] = function(...)
        original(...)
        fn(...)
    end
end
function CreateFromMixins() return {} end
MapCanvasDataProviderMixin = {}
Enum = { UIMapType = { World = 1, Continent = 2, Zone = 3 } }
MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_NONE = 0
MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_FULL = 1
local time = 10
GetTime = function() return time end
local fight = false
InCombatLockdown = function() return fight end
geterrorhandler = function() return error end
local timers = {}
C_Timer = { After = function(delay, callback)
    timers[#timers + 1] = { time = time + delay, callback = callback }
end }
local function advance(seconds)
    local finish = time + seconds
    while true do
        local nextTimer
        for i, timer in ipairs(timers) do
            if timer.time <= finish and (not nextTimer or timer.time < timers[nextTimer].time) then
                nextTimer = i
            end
        end
        if not nextTimer then break end
        local timer = table.remove(timers, nextTimer)
        time = timer.time
        timer.callback()
    end
    time = finish
end
C_Map = {
    GetMapRectOnMap = noop, GetMapInfoAtPosition = noop,
    GetMapInfo = function(id) return { mapType = id == 999 and 4 or 3 } end,
}

local map, sc = CreateFrame(), CreateFrame()
WorldMapFrame, map.ScrollContainer = map, sc
map.providers, map.mapID = {}, 1001
sc.mapID, sc.width, sc.height = 1001, 800, 600
sc.currentScale, sc.currentScrollX, sc.currentScrollY = 1, 0.5, 0.5
sc.Child = { SetScale = noop, GetRect = noop }
sc.mouseButtonInfo = { LeftButton = { down = false } }
function sc:GetWidth() return self.width end
function sc:GetHeight() return self.height end
function sc:GetFrameLevel() return 100 end
-- (as Blizzard's: a current value cleared by MarkCanvasDirty falls back to the target)
function sc:GetCanvasScale() return self.currentScale or self.targetScale end
function sc:GetCurrentScrollX() return self.currentScrollX or self.targetScrollX end
function sc:GetCurrentScrollY() return self.currentScrollY or self.targetScrollY end
local ctrlDown, shiftDown = false, false
function IsControlKeyDown() return ctrlDown end
function IsShiftKeyDown() return shiftDown end
local cursorX, cursorY = 400, 300 -- the view's middle
function GetCursorPosition() return cursorX, cursorY end
function sc:GetCursorPosition() return cursorX, cursorY end
function sc:GetEffectiveScale() return 1 end
function sc:GetLeft() return 0 end
function sc:GetTop() return 600 end
function sc:SetMouseWheelZoomMode(mode) self.wheelMode = mode end
sc.SetScalingMode = noop
-- (another addon moving Blizzard's view; debugstack says whose code called it)
function sc:InstantPanAndZoom(scale, x, y)
    self.currentScale, self.targetScale, self.currentScrollX, self.currentScrollY = scale, scale, x, y
end
local stackAddon = "Blizzard_MapCanvas"
function debugstack() return "Interface/AddOns/" .. stackAddon .. "/Code.lua:1: in function" end
sc.SetNormalizedHorizontalScroll, sc.SetNormalizedVerticalScroll = noop, noop
sc.MarkAreaTriggersDirty, sc.MarkViewRectDirty = noop, noop
function sc:NormalizeHorizontalSize(px) return px / 1000 end
function sc:NormalizeVerticalSize(px) return px / (self.mapID == 947 and 750 or 1000) end
function sc:CalculateScrollExtentsAtScale() return 0, 1, 0, 1 end
function sc:CalculateScrollExtents()
    self.scrollXExtentsMin, self.scrollXExtentsMax, self.scrollYExtentsMin, self.scrollYExtentsMax =
        self:CalculateScrollExtentsAtScale(self.currentScale)
end
sc.CreateZoomLevels = noop
function sc:ResetZoom() self.currentScale, self.currentScrollX, self.currentScrollY = 1, 0.5, 0.5 end
function sc:OnCanvasSizeChanged() self:CreateZoomLevels(); self:ResetZoom() end
local levels = { InsertFrameLevelAbove = function() return true end }
function map:GetPinFrameLevelsManager() return levels end
function map:GetMapID() return self.mapID end
function map:GetCanvas() return sc.Child end
local pinsByTemplate = {}
function map:EnumeratePinsByTemplate(template)
    local list, i = pinsByTemplate[template] or {}, 0
    return function() i = i + 1; return list[i] end
end
function map:AddCanvasClickHandler(fn) self.clickHandler = fn end
function map:AddDataProvider(provider) self.providers[#self.providers + 1] = provider end
function map:OnCanvasScaleChanged()
    for _, provider in ipairs(self.providers) do provider:OnCanvasScaleChanged() end
end
function map:SetMapID(id)
    -- (the game's canvas: putting up the map that is already up changes nothing)
    if self.mapID == id and self.drawn then return end
    self.mapID, sc.mapID, self.drawn = id, id, true
    sc:OnCanvasSizeChanged()
    for _, provider in ipairs(self.providers) do provider:OnMapChanged() end
end
-- WorldMapMixin:OnShow: the player's map, the data providers' OnShow, and only
-- then the zoom reset.
function map:Open(id)
    self.shown = true
    self:SetMapID(id)
    for _, provider in ipairs(self.providers) do provider:OnShow() end
    sc:ResetZoom()
end
function map:Close()
    self.shown = false
    for _, provider in ipairs(self.providers) do provider:OnHide() end
    if self.hooks.OnHide then self.hooks.OnHide(self) end
end

local events, character = {}, "First-Realm"
-- Starting the continuous map is Wayfinder putting maps up itself: the game's
-- pins are guarded from then on (PinGuard.lua, tests/pin_guard.lua).
local armed = 0
local ns = { db = {}, DetailView = { IsFollowingMap = function() return false end },
    OpenMapCompat = { Install = noop }, PinGuard = { Arm = function() armed = armed + 1 end },
    MapPins = { RefreshNow = noop } }
function ns:NewModule(name) self[name] = {}; return self[name] end
function ns:RegisterEvent(event, fn)
    events[event] = events[event] or {}
    table.insert(events[event], fn)
end
local function fire(event, ...) for _, fn in ipairs(events[event] or {}) do fn(event, ...) end end
local printed = {}
function ns.Print(message) printed[#printed + 1] = message end
function ns:GetCharacterKey() return character end
function ns:GetSetting(key) return key == "continuousMap" end
ns.Readable = function() return true end
local playerMap, playerX, playerY = 1001, 0.5, 0.5
local tracking
function ns.GetPlayerWorld() return 1, 0, 0, playerMap, playerX, playerY end
ns.Navigation = { IsTracking = function() return tracking end }
-- The game's quest log, its waypoint, the player and the Gamepad UI.
QuestMapFrame = { DetailsFrame = { questMapID = 0 } }
function QuestMapFrame_ShowQuestDetails() end
local userWaypoint, waypointsSet = nil, {}
UiMapPoint = { CreateFromCoordinates = function(mapID, x, y)
    return { uiMapID = mapID, position = { GetXY = function() return x, y end } }
end }
C_Map.GetUserWaypoint = function() return userWaypoint end
C_Map.SetUserWaypoint = function(point) userWaypoint = point; waypointsSet[#waypointsSet + 1] = point; fire("USER_WAYPOINT_UPDATED") end
C_Map.CanSetUserWaypointOnMap = function() return true end
C_SuperTrack = { SetSuperTrackedUserWaypoint = noop }
local facing = 0
function GetPlayerFacing() return facing end
C_Map.GetBestMapForUnit = function() return playerMap end
C_Map.GetPlayerMapPosition = function(mapID)
    if mapID == playerMap then return { GetXY = function() return playerX, playerY end } end
end
local gamepadUI = true
InputUtil = { IsGamepadUIEnabled = function() return gamepadUI end }
MiniQoLRuntime = { Execute = function(_, _, fn) return fn("Wayfinder", ns) end }
local base = root .. "/Modules/Wayfinder/"
assert(loadfile(base .. "ContinuousMap.lua"))("Wayfinder", ns)
local S, surface = { WORLD = 947 }, false
ns.ContinuousEngine.MapStitch = S
local rects = { [947] = { 0, 1, 0, 1 }, [1001] = { 0.1, 0.3, 0.2, 0.4 },
    [1002] = { 0.6, 0.8, 0.5, 0.7 } }
function S.Rect(id) if rects[id] then return unpack(rects[id]) end end
function S.ArtSize(id) if rects[id] then return 1000, id == 947 and 750 or 1000 end end
function S.Size() return 1000, 750 end
S.IsBuilt, S.Layout = function() return true end, function() return true end
S.ContinentAt, S.Recull, S.SetShown, S.SetZoom, S.SetView, S.RaiseArrow = noop, noop, noop, noop, noop, noop
local arrowAt -- where the map's player arrow was last put: { u, v, facing }
function S.SetPlayer(u, v, turned)
    if not u then arrowAt = nil return false end
    arrowAt = { u, v, turned }
    return true
end
function S.GetCityView() return 1458, surface end
function S.SetCityView(value) surface = value == true end
function S.ResetCityView() surface = false end
-- The maps under a world point, the world first.
function S.ChainAt(u, v)
    local chain = { 947 }
    for _, id in ipairs({ 1001, 1002 }) do
        local l, r, t, b = unpack(rects[id])
        if u >= l and u <= r and v >= t and v <= b then chain[#chain + 1] = id end
    end
    return chain
end
assert(loadfile(base .. "Vendor/OpenMap/WorldMap.lua"))("Wayfinder", ns)
local painter = frames[#frames]
-- (the controller makes its ticker, then a debug timer, then the view's painter)
local ticker = frames[#frames - 2]
assert(ticker.scripts.OnUpdate and ticker ~= painter, "the controller's ticker")
local continuous, controller = ns.ContinuousMap, ns.ContinuousEngine:GetModule("worldmap")
-- With the game's Gamepad UI on, the map is left to Blizzard: nothing of it is
-- touched, as the UI's controller buttons would carry the addon's taint (closing
-- the map with B was blocked, upstream's 95092ae). It's set up as soon as the UI
-- goes back to mouse and keyboard, out of combat.
continuous:Start()
assert(armed == 0 and not continuous.started, "the Gamepad UI on: the map stays Blizzard's")
assert(#printed == 1 and printed[1]:find("Gamepad UI"), "and chat says why, once")
continuous:Start()
assert(#printed == 1, "once")
gamepadUI = false
fight = true
fire("INPUT_DEVICE_INTERFACE_TRANSITION")
assert(armed == 0, "not set up in a fight")
fight = false
fire("PLAYER_REGEN_ENABLED")
assert(armed == 1, "the continuous map arms the pin guard when it starts")
assert(continuous.started and printed[2]:find("back"), "back as the UI goes to mouse and keyboard")
continuous:Start()
assert(armed == 1, "and only when it starts")
local function draw()
    if painter:IsShown() then painter.scripts.OnUpdate(painter) end
end
local function expect(u, v, zoom)
    local a, b, c = controller.ViewNow()
    near(a, u); near(b, v); near(c, zoom, "zoom")
end

-- A first opening has no remembered view and fits the requested map normally.
map:Open(1001); draw()
expect(0.2, 0.3, 3.75)
controller.ShowNow(0.68, 0.58, 16); draw()
surface = true
map:Close()
assert(ns.db.mapViews == nil, "the view must never reach saved variables")
map:Open(1001); draw() -- Blizzard opens the player's zone, not the last host.
expect(0.68, 0.58, 16)
assert(surface == true, "selected map layer was lost")

-- Resizing the open window preserves the world framing rather than refitting.
sc.width, sc.height = 1000, 700
sc:OnCanvasSizeChanged(); draw()
expect(0.68, 0.58, 16)
sc.width, sc.height = 800, 600
sc:OnCanvasSizeChanged(); draw()
expect(0.68, 0.58, 16)

-- Deliberate navigation while open must show the newly requested map.
map:SetMapID(1002); draw()
expect(0.7, 0.6, 3.75)
controller.ShowNow(0.66, 0.57, 24)
map:Close() -- close before the queued view update has painted
assert(not painter:IsShown(), "a hidden repaint could erase the remembered view")
map:Open(1001); draw()
expect(0.66, 0.57, 24)

-- The view is session state: remembered across a close, never written out, and
-- with no logout handler left to write it.
controller.ShowNow(0.64, 0.56, 32); draw()
assert(events.PLAYER_LOGOUT == nil, "the view must not be saved on logout any more")
map:Close()
surface = false
map:Open(1002); draw()
expect(0.64, 0.56, 32)
assert(surface == true)
assert(ns.db.mapViews == nil, "closing still must not persist the view")

-- The memory is no longer keyed by character, because it never outlives the
-- session. Native dungeon maps still cannot overwrite the continuous-map view.
map:Close()
map:Open(999); map:Close()
map:Open(1002); draw()
expect(0.64, 0.56, 32)

-- Wayfinder's markers and the player's arrow sit in the view rather than on
-- the canvas. A move of the canvas is passed on within the call that made it;
-- only the heavier work waits for the queued repaint a frame later.
local tracked
S.TrackView = function(u, v, hu, hv) tracked = { u, v, hu, hv } end
sc.currentScrollX = sc.currentScrollX + 0.01
for _, provider in ipairs(map.providers) do
    if provider.OnCanvasPanChanged then provider:OnCanvasPanChanged() end
end
assert(tracked, "a pan reaches the markers before the next frame")
local movedU, movedV = controller.ViewNow()
near(tracked[1], movedU, "where the canvas now is")
near(tracked[2], movedV)
assert(tracked[3] > 0 and tracked[4] > 0, "with how much of the world is in view")
assert(painter:IsShown(), "and the full update is still queued behind it")
draw()
map:Close()
tracked = nil
for _, provider in ipairs(map.providers) do
    if provider.OnCanvasPanChanged then provider:OnCanvasPanChanged() end
end
assert(tracked == nil, "a closed map places nothing")
map:Open(1002); draw()
S.TrackView = nil

-- The view moved to stays as long as the map is open: someone may be looking
-- something up. Closed, it is kept for 45 s, counted from each close.
controller.ShowNow(0.66, 0.58, 24); draw()
advance(120); draw()
expect(0.66, 0.58, 24)
map:Close(); advance(44); map:Open(1001); draw()
expect(0.66, 0.58, 24)
advance(60); draw()
expect(0.66, 0.58, 24)
map:Close(); advance(44); map:Open(1002); draw()
expect(0.66, 0.58, 24)

-- Closed for 45 s, the map opens as the game's does: the zone it opens on,
-- the player's, whole, rather than the player at the zoom left.
map:Close(); advance(45); map:Open(1001); draw()
expect(0.2, 0.3, 3.75)

-- A map opened and not moved keeps nothing: the next opening, however soon,
-- shows the zone the player is in by then.
map:Close()
playerMap = 1002
map:Open(1002); draw()
expect(0.7, 0.6, 3.75)

-- A zoom on the same centre is a move to keep too.
controller.ShowNow(0.7, 0.6, 12); draw()
map:Close(); advance(30); map:Open(1002); draw()
expect(0.7, 0.6, 12)

-- Kept no longer, the opening shows the zone though the canvas still holds the
-- old view when the map's OnShow runs (the game resets the zoom only after it).
-- That opening is where the map starts, not a move to keep: closed again at
-- once, the next opening shows the zone the player is in by then.
map:Close(); advance(45); map:Open(1002); draw()
expect(0.7, 0.6, 3.75)
map:Close()
playerMap = 1001
map:Open(1001); draw()
expect(0.2, 0.3, 3.75)

-- A tracking reopen uses the player's current position, at the zoom left.
controller.ShowNow(0.55, 0.5, 24); draw()
tracking = true
continuous:ClearPositionMemory()
map:Close()
playerMap, playerX, playerY = 1002, 0.25, 0.25
map:Open(1002); draw()
expect(0.65, 0.55, 24)

-- Tracking off, with the map not moved since, the next opening shows the zone.
tracking = false
map:Close(); map:Open(1002); draw()
expect(0.7, 0.6, 3.75)

---------------------------------------------------------------------------
-- Fixes taken from OpenMap's controller since 0.5.0-beta
---------------------------------------------------------------------------
-- Blizzard's MarkCanvasDirty, on every icon any addon adds or removes, clears
-- the current scale and scroll that equal their targets. That's no move: the
-- map underneath still follows a view kept still (upstream's 60c2b06).
map:Close(); map:Open(1001); draw()
controller.ShowNow(0.7, 0.6, 5); draw() -- over map 1002, close enough to be on it
assert(map:GetMapID() == 1001, "the map underneath waits for the view to rest")
for _ = 1, 8 do
    sc.currentScale, sc.currentScrollX, sc.currentScrollY = nil, nil, nil -- icons came and went
    ticker.scripts.OnUpdate(ticker, 0.1)
end
assert(map:GetMapID() == 1002, "busy icons don't hold the map underneath back")
draw()
expect(0.7, 0.6, 5)

-- A press that wandered off and came back near its start is a drag, not a
-- click into the zone under the cursor (upstream's 102d963).
controller.ShowNow(0.7, 0.6, 2); draw()
local function press(path)
    cursorX, cursorY = 400, 300
    sc.mouseButtonInfo.LeftButton.down = true
    sc.hooks.OnMouseDown(sc, "LeftButton")
    for _, x in ipairs(path) do
        cursorX = x
        sc.hooks.OnUpdate(sc, 0.016)
    end
    sc.mouseButtonInfo.LeftButton.down = false
    map.clickHandler(map, "LeftButton", cursorX, cursorY)
end
press({ 440, 401 })
assert(not controller.Animating(), "a drag back to 1 pixel from its start doesn't zoom in")
press({ 401 })
assert(controller.Animating(), "a press that stays put still zooms into the zone under it")
cursorX, cursorY = 400, 300

-- A window laid out 0 pixels across never leaves the view NaN, which every
-- later view was worked out from (upstream's e5aa708).
map:Close()
sc.width = 0
map:Open(1001); draw()
local u0, v0, z0 = controller.ViewNow()
assert(u0 == u0 and v0 == v0 and z0 == z0 and z0 >= 1, "the view stays a real one")
sc.width = 800
sc:OnCanvasSizeChanged(); draw()
local u1, v1, z1 = controller.ViewNow()
assert(u1 == u1 and v1 == v1 and z1 == z1 and z1 >= 1, "and the window coming back to size finds it")

-- Blizzard's map functions are hooked, never replaced: a replacement that the
-- game's own code calls taints what it does next (upstream's 25acdc6, #345).
assert(sc.ResetZoom ~= nil and sc.CalculateScrollExtentsAtScale(sc) == 0, "Blizzard's own extents stand")
controller.ShowNow(0.25, 0.32, 8); draw()
assert(sc.scrollXExtentsMax - sc.scrollXExtentsMin > 1, "ours put in after Blizzard's: panning past the map")

-- In a fight nothing of Blizzard's map is written: what's asked for waits, and is
-- put up as the fight ends.
fight = true
local before = { sc.currentScale, sc.currentScrollX, sc.currentScrollY }
controller.ShowNow(0.22, 0.31, 12)
sc.hooks.OnMouseWheel(sc, 1)
sc.hooks.OnUpdate(sc, 0.016)
assert(sc.currentScale == before[1] and sc.currentScrollX == before[2] and sc.currentScrollY == before[3],
    "the view isn't touched in a fight")
assert(not controller.Animating(), "nor zoomed by the wheel")
assert(map.clickHandler(map, "LeftButton") == false, "a click is Blizzard's in a fight")
fight = false
fire("PLAYER_REGEN_ENABLED"); draw()
expect(0.22, 0.31, 12)

-- The map opened in a fight shows as Blizzard shows it, and as the fight ends,
-- as any opening would: the view kept from the last.
map:Close()
fight = true
map:Open(1002); draw()
local fu, fv, fz = controller.ViewNow()
assert(math.abs(fu - 0.22) + math.abs(fv - 0.31) > 0.01, "in the fight, Blizzard's own view")
fight = false
fire("PLAYER_REGEN_ENABLED"); draw()
expect(0.22, 0.31, 12)

-- Another map put up in a fight keeps Blizzard's zoom levels and wheel then;
-- ours come back with the fight's end, and the view it left stays.
local ourLevels = sc.zoomLevels
fight = true
sc.wheelMode = nil
map:SetMapID(1001); draw()
assert(sc.zoomLevels == ourLevels and sc.wheelMode == nil, "nothing of Blizzard's written in the fight")
fight = false
fire("PLAYER_REGEN_ENABLED"); draw()
assert(sc.zoomLevels ~= ourLevels and sc.wheelMode == MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_NONE, "ours put in after it")

-- Another addon's view change is put back next frame; Blizzard's own stands.
controller.ShowNow(0.21, 0.29, 10); draw()
stackAddon = "SomeMapAddon"
sc:InstantPanAndZoom(1, 0.5, 0.5)
advance(0); draw()
expect(0.21, 0.29, 10)
stackAddon = "Blizzard_MapCanvas"

-- A quest's details, opened from the tracker: the map opens on the quest's map,
-- and a kept view that would take the map underneath off it shows that map
-- whole instead, so Blizzard doesn't close them (upstream's 266a098, #224).
controller.ShowNow(0.7, 0.6, 5); draw() -- looking at map 1002
map:Close()
map:Open(1001) -- the tracker opens the quest's map, 1001
QuestMapFrame.DetailsFrame.questMapID = 1001
QuestMapFrame_ShowQuestDetails()
draw()
expect(0.2, 0.3, 3.75)
for _ = 1, 10 do ticker.scripts.OnUpdate(ticker, 0.1) end
assert(map:GetMapID() == 1001, "the map underneath stays the quest's")
map:Close(); map:Open(1001); draw()
expect(0.2, 0.3, 3.75) -- (reopened soon after, it's on the quest's map still)
QuestMapFrame.DetailsFrame.questMapID = 0

-- Ctrl- and Shift-clicks are Blizzard's and other addons' (upstream's 134ec32).
-- Blizzard's waypoint from a Ctrl-click goes on the zone that was clicked, where
-- it was clicked: the game puts it on the map underneath, clamped to it.
controller.ShowNow(0.7, 0.6, 2); draw() -- the cursor over map 1002, the map underneath 1001
ctrlDown = true
assert(map.clickHandler(map, "LeftButton") == false and not controller.Animating(), "Ctrl-click left to Blizzard")
C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(1001, 1, 1)) -- Blizzard's, clamped
ctrlDown = false
local placed = waypointsSet[#waypointsSet]
assert(#waypointsSet == 2 and placed.uiMapID == 1002, "put on the zone clicked")
local px, py = placed.position:GetXY()
near(px, 0.5, "where it was clicked"); near(py, 0.5)
advance(1)
C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(1001, 0.4, 0.4)) -- a quest's, later
assert(#waypointsSet == 3, "another waypoint is left where it is")
shiftDown = true
assert(map.clickHandler(map, "LeftButton") == false and not controller.Animating(), "Shift-click left to others")
shiftDown = false

-- Your arrow turns and moves every frame, not on the tenth-second tick (upstream's 58e62ba).
playerMap, playerX, playerY = 1001, 0.5, 0.5
facing = 1
ticker.scripts.OnUpdate(ticker, 0.01)
assert(arrowAt and arrowAt[3] == 1, "turned within the frame")
playerX = 0.6
ticker.scripts.OnUpdate(ticker, 0.01)
near(arrowAt[1], 0.22, "and moved")
playerX = 0.5

-- A highlight pin made after setup is hooked too, after Blizzard's own Refresh.
local refreshed, hidden = 0, 0
local pin = { HighlightTexture = { Hide = function() hidden = hidden + 1 end } }
function pin:Refresh() refreshed = refreshed + 1 end
pinsByTemplate.MapHighlightPinTemplate = { pin }
map:SetMapID(1002)
pin:Refresh()
assert(refreshed == 1 and hidden == 1, "Blizzard's refresh ran, then ours hid its glow")
pinsByTemplate.MapHighlightPinTemplate = nil

-- A fresh load of the module -- what a reload or a relog gives you -- starts
-- with no remembered view at all.
map:Close()
local reloaded = { db = ns.db }
function reloaded:NewModule(name) self[name] = { name = name } return self[name] end
local previousExecute = MiniQoLRuntime.Execute
MiniQoLRuntime.Execute = function(_, _, fn) return fn("Wayfinder", reloaded) end
assert(loadfile(base .. "ContinuousMap.lua"))()
MiniQoLRuntime.Execute = previousExecute
assert(reloaded.ContinuousMap:SavedView() == nil, "a new session must not inherit the last one's view")
assert(ns.db.mapViews == nil, "nothing about the view belongs in saved variables")

print("Map memory: the view kept while open and for 45 s closed, then the player's whole zone, preserved layers, and tracking reopen passed")
