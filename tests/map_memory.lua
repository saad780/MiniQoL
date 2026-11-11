local root = ...
local function near(actual, expected, label)
    assert(math.abs(actual - expected) < 0.000001, (label or "coordinate") .. ": " .. tostring(actual))
end
local function noop() end
local frames = {}
function CreateFrame()
    local f = { scripts = {}, hooks = {}, shown = false }
    function f:SetScript(event, fn) self.scripts[event] = fn end
    function f:HookScript(event, fn) self.hooks[event] = fn end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    frames[#frames + 1] = f
    return f
end
function hooksecurefunc(object, key, fn)
    local original = object[key]
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
GetTime = function() return 10 end
InCombatLockdown = function() return false end
geterrorhandler = function() return error end
C_Timer = { After = noop }
C_Map = {
    GetMapRectOnMap = noop, GetMapInfoAtPosition = noop,
    GetMapInfo = function(id) return { mapType = id == 999 and 4 or 3 } end,
}

local map, sc = CreateFrame(), CreateFrame()
WorldMapFrame, map.ScrollContainer = map, sc
map.providers, map.mapID = {}, 1001
sc.mapID, sc.width, sc.height = 1001, 800, 600
sc.currentScale, sc.currentScrollX, sc.currentScrollY = 1, 0.5, 0.5
sc.Child = { SetScale = noop }
sc.mouseButtonInfo = { LeftButton = { down = false } }
function sc:GetWidth() return self.width end
function sc:GetHeight() return self.height end
function sc:GetFrameLevel() return 100 end
function sc:GetCanvasScale() return self.currentScale end
function sc:GetCurrentScrollX() return self.currentScrollX end
function sc:GetCurrentScrollY() return self.currentScrollY end
sc.SetMouseWheelZoomMode, sc.SetScalingMode = noop, noop
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
function map:EnumeratePinsByTemplate() return function() end end
map.AddCanvasClickHandler = noop
function map:AddDataProvider(provider) self.providers[#self.providers + 1] = provider end
function map:OnCanvasScaleChanged()
    for _, provider in ipairs(self.providers) do provider:OnCanvasScaleChanged() end
end
function map:SetMapID(id)
    self.mapID, sc.mapID = id, id
    sc:OnCanvasSizeChanged()
    for _, provider in ipairs(self.providers) do provider:OnMapChanged() end
end
function map:Open(id)
    self.shown = true
    self:SetMapID(id)
    for _, provider in ipairs(self.providers) do provider:OnShow() end
end
function map:Close()
    self.shown = false
    for _, provider in ipairs(self.providers) do provider:OnHide() end
    if self.hooks.OnHide then self.hooks.OnHide(self) end
end

local events, character = {}, "First-Realm"
local ns = { db = {}, DetailView = { IsFollowingMap = function() return false end },
    OpenMapCompat = { Install = noop } }
function ns:NewModule(name) self[name] = {}; return self[name] end
function ns:RegisterEvent(event, fn) events[event] = fn end
function ns:GetCharacterKey() return character end
function ns:GetSetting(key) return key == "continuousMap" end
ns.Readable = function() return true end
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
S.ContinentAt, S.Recull, S.SetShown, S.SetZoom, S.SetView, S.SetPlayer, S.RaiseArrow = noop, noop, noop, noop, noop, noop, noop
function S.GetCityView() return 1458, surface end
function S.SetCityView(value) surface = value == true end
function S.ResetCityView() surface = false end
assert(loadfile(base .. "Vendor/OpenMap/WorldMap.lua"))("Wayfinder", ns)
local painter = frames[#frames]
local continuous, controller = ns.ContinuousMap, ns.ContinuousEngine:GetModule("worldmap")
continuous:Start()
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

print("Map reopen, pending repaint, layers, explicit navigation and session-only memory passed")
