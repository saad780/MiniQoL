-- Capitals on the seamless map: close in on one and its city map is shown with
-- the terrain left out, and the layer button swaps the two. Undercity's other
-- layer is the overworld, which is a different map underneath.
local root = ...
local function noop() end

-- Frames: anything not spelled out is a no-op.
local methods = {}
local frame = {}
frame.__index = function(_, key)
    if methods[key] then return methods[key] end
    if type(key) == "string" and key:match("^%u") then return noop end
end
function methods:SetSize(w, h) self.w, self.h = w, h end
function methods:GetWidth() return self.w or 800 end
function methods:GetHeight() return self.h or 600 end
function methods:SetShown(value) self.shown = value and true or false end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end
function methods:SetAlpha(value) self.alpha = value end
function methods:CreateTexture() return setmetatable({}, frame) end
function methods:CreateMaskTexture() return setmetatable({}, frame) end
function CreateFrame() return setmetatable({ shown = true }, frame) end

-- A small world: one continent, two zones, two capitals (left, right, top, bottom).
local WORLD_RECTS = {
    [1415] = { 0.5, 0.9, 0.1, 0.9 },
    [1429] = { 0.6, 0.7, 0.6, 0.7 }, [1453] = { 0.62, 0.64, 0.62, 0.64 }, -- Elwynn, Stormwind
    [1420] = { 0.6, 0.7, 0.2, 0.3 }, [1458] = { 0.64, 0.66, 0.24, 0.26 }, -- Tirisfal, Undercity
}
local TYPES = { [947] = 1, [1415] = 2 }
local function WorldRect(id)
    if id == 947 then return 0, 1, 0, 1 end
    local r = WORLD_RECTS[id]
    if r then return r[1], r[2], r[3], r[4] end
end
Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3 } }
C_Map = {
    GetMapRectOnMap = function(id, parent)
        local l, r, t, b = WorldRect(id)
        local pl, pr, pt, pb = WorldRect(parent)
        if not l or not pl then return end
        return (l - pl) / (pr - pl), (r - pl) / (pr - pl), (t - pt) / (pb - pt), (b - pt) / (pb - pt)
    end,
    GetMapArtLayers = function(id)
        if WorldRect(id) then return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } } end
    end,
    GetMapArtLayerTextures = function() local files = {}; for i = 1, 12 do files[i] = i end; return files end,
    GetMapInfo = function(id) if WorldRect(id) then return { mapID = id, mapType = TYPES[id] or 3 } end end,
    GetMapChildrenInfo = function() return { { mapID = 1415 } } end,
    -- The deepest zone at a point; capitals are added by the art module itself.
    GetMapInfoAtPosition = function(id, x, y)
        local pl, pr, pt, pb = WorldRect(id)
        local u, v = pl + x * (pr - pl), pt + y * (pb - pt)
        local children = id == 947 and { 1415 } or id == 1415 and { 1429, 1420 } or {}
        for _, child in ipairs(children) do
            local l, r, t, b = WorldRect(child)
            if u >= l and u <= r and v >= t and v <= b then return { mapID = child, mapType = TYPES[child] or 3 } end
        end
    end,
}

local button, follows, followed, fired = {}, {}, {}, {}
local ns = { name = "MiniQoL" }
ns.ContinuousEngine = {
    MapCityZones = { [1453] = 1429, [1454] = 1411, [1455] = 1426, [1456] = 1412, [1457] = 1438, [1458] = 1420 },
    GetModule = function() return { FollowLayerMap = function(id) followed[#followed + 1] = id end } end,
}
ns.ContinuousMap = { UpdateLayerButton = function(_, city, terrain) button.city, button.terrain = city, terrain end }
ns.DetailView = {
    FollowMap = function(_, ...) follows[#follows + 1] = { pinsOnly = select(9, ...) }; ns.following = true end,
    IsFollowingMap = function() return ns.following end,
    Exit = function() ns.following = false end,
}
ns.WorldFog = { Follow = noop }
function ns.IsCityMap(id) return id == 1453 or id == 1458 end
function ns.GetExplorationOverlays() return {} end
function ns.GetMapRect(id) if id == 1415 then return { cont = 0, top = 0, left = 0, width = 40000, height = 40000 } end end
ns.TileData = { [0] = {} }
function ns:GetSetting(key) return key == "detailEnabled" end
function ns:Fire(event) fired[#fired + 1] = event end
WorldMapFrame = { ScrollContainer = setmetatable({ w = 800, h = 600 }, frame) }
function WorldMapFrame:GetPinFrameLevelsManager() return { maxLevel = 3000 } end
MiniQoLRuntime = { Execute = function(_, _, fn) return fn("Wayfinder", ns) end }
assert(loadfile(root .. "/Modules/Wayfinder/ContinuousArt.lua"))("Wayfinder", ns)
local S = ns.ContinuousEngine.MapStitch

S.Build(CreateFrame(), 100, 70)
S.SetShown(true)
local function Shows(id)
    for _, visible in ipairs(S.VisibleMaps()) do if visible == id then return true end end
    return false
end
local function Last() return follows[#follows] end

-- Close in on Stormwind: its map, no terrain, and the button offers terrain.
S.SetView(0.63, 0.63, 0.001, 0.001, nil, 60)
assert(button.city == 1453 and button.terrain == false, "the button appears in Stormwind on its city map")
assert(Shows(1453), "Stormwind's map is drawn")
assert(Last() and Last().pinsOnly == true, "the terrain is left out, the markers kept")

-- Swap to terrain: the city map steps aside; the map underneath stays the city's.
S.ToggleCityView()
assert(button.city == 1453 and button.terrain == true, "the button now offers the city map back")
assert(not Shows(1453), "Stormwind's map is hidden")
assert(Last().pinsOnly == false, "the terrain is drawn")
assert(#followed == 0, "Stormwind keeps its own map underneath")
assert(fired[#fired] == "MAP_LAYER_CHANGED", "pins are told the layer changed")

-- Out of the city the button goes, and the swap does nothing there.
S.SetView(0.75, 0.5, 0.2, 0.2, nil, 2)
assert(button.city == nil, "no button outside a capital")
local before = #fired
S.ToggleCityView()
assert(#fired == before, "nothing to swap outside a capital")

-- The choice carries to the next city: Undercity opens on its overworld.
S.SetView(0.65, 0.25, 0.001, 0.001, nil, 60)
assert(button.city == 1458 and button.terrain == true, "Undercity remembers terrain was chosen")
assert(not Shows(1458) and Last().pinsOnly == false, "the overworld's terrain, not the city")
local chain = S.ChainAt(0.65, 0.25)
assert(chain[#chain] == 1420, "with Tirisfal's map underneath")

-- Back to the city map: Undercity's own map goes underneath again.
S.ToggleCityView()
assert(followed[#followed] == 1458, "Undercity's map is put back underneath")
assert(Shows(1458) and Last().pinsOnly == true, "its city map, without terrain")
chain = S.ChainAt(0.65, 0.25)
assert(chain[#chain] == 1458, "and it is the map the view is on")

-- Closing the map hides the button; the choice is kept for the session.
S.SetShown(false)
assert(button.city == nil, "no button with the map closed")
S.SetCityView(true)
local _, terrain = S.GetCityView()
assert(terrain == true, "a saved choice comes back")
print("City maps: shown close in, swapped with terrain, Undercity's overworld and the session choice passed")
