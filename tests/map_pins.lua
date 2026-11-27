-- World map pins: the map sets each pin's click passthrough when it hands the
-- pin out, and that call is blocked in combat, so opening the map mid-fight
-- must not make it.
local root = ...
local function noop() end

function CreateFromMixins(...)
    local result = {}
    for i = 1, select("#", ...) do
        for key, value in pairs(select(i, ...)) do result[key] = value end
    end
    return result
end
MapCanvasDataProviderMixin = {}
-- As Blizzard_MapCanvas has it: clear, then set the buttons that pass through.
MapCanvasPinMixin = {}
function MapCanvasPinMixin:ShouldMouseButtonBePassthrough(button) return button == "RightButton" end
function MapCanvasPinMixin:CheckMouseButtonPassthrough(...)
    self:SetPassThroughButtons()
    local buttons = {}
    for i = 1, select("#", ...) do
        local button = select(i, ...)
        if self:ShouldMouseButtonBePassthrough(button) then buttons[#buttons + 1] = button end
    end
    self:SetPassThroughButtons(unpack(buttons))
end

function InCombatLockdown() return COMBAT == true end
local active = {}
WorldMapFrame = { AddDataProvider = noop }
function WorldMapFrame:EnumeratePinsByTemplate(template)
    assert(template == "WayfinderMapPinTemplate")
    local index = 0
    return function() index = index + 1; return active[index] end
end
EventUtil = { ContinueOnAddOnLoaded = function(_, fn) fn() end }

local events = {}
local ns = {}
function ns:NewModule(name) self[name] = {}; return self[name] end
function ns:On() end
function ns:RegisterEvent(event, fn) events[event] = fn end
MiniQoLRuntime = { Execute = function(_, _, fn) return fn("Wayfinder", ns) end }
assert(loadfile(root .. "/Modules/Wayfinder/MapPins.lua"))("Wayfinder", ns)
ns.MapPins:OnLogin()

-- A pin the way the map pools them: the protected call fails in combat.
local function Pin()
    local pin = setmetatable({ calls = 0 }, { __index = WayfinderMapPinMixin })
    function pin:SetPassThroughButtons(...)
        assert(not COMBAT, "ADDON_ACTION_BLOCKED: SetPassThroughButtons in combat")
        self.calls, self.buttons = self.calls + 1, { ... }
    end
    active[#active + 1] = pin
    return pin
end

-- Opening the map mid-fight hands out a fresh pin.
COMBAT = true
local first = Pin()
first:CheckMouseButtonPassthrough("RightButton")
assert(first.calls == 0, "nothing protected is called in combat")

-- Once the fight ends it gets its passthrough.
COMBAT = false
events.PLAYER_REGEN_ENABLED()
assert(first.buttons and first.buttons[1] == "RightButton" and #first.buttons == 1, "right clicks pass through after combat")
local calls = first.calls

-- Reused from the pool, in or out of combat, it is left as it is.
first:CheckMouseButtonPassthrough("RightButton")
COMBAT = true
first:CheckMouseButtonPassthrough("RightButton")
COMBAT = false
assert(first.calls == calls, "a pin that already passes right clicks is not set again")

-- Out of combat a new pin is set straight away.
local second = Pin()
second:CheckMouseButtonPassthrough("RightButton")
assert(second.buttons and second.buttons[1] == "RightButton", "a pin made out of combat is set at once")
events.PLAYER_REGEN_ENABLED()
assert(second.calls == 2 and first.calls == calls, "leaving combat does not touch pins that are already set")

-- Tooltips say how far an icon is and which way: world x counts north, y west.
function ns.GetPlayerWorld() return 1, 1000, 1000 end
local function way(x, y, cont) return ns.DistanceAndDirection(cont or 1, x, y) end
assert(way(1240, 1000) == "240 yd north", way(1240, 1000))
assert(way(1000, 760) == "240 yd east", way(1000, 760))
assert(way(1100, 900) == "141 yd northeast", way(1100, 900))
assert(way(900, 1100) == "141 yd southwest", way(900, 1100))
assert(way(1000, 1300) == "300 yd west", way(1000, 1300))
assert(way(700, 1000) == "300 yd south", way(700, 1000))
assert(way(1001, 1002) == "Here", "standing on it")
assert(way(1000, 13000) == "12.0k yd west", way(1000, 13000))
assert(way(1240, 1000, 0) == nil, "nothing for another continent")
print("World map pins: no protected calls in combat, passthrough caught up afterwards, tooltip distance and direction passed")
