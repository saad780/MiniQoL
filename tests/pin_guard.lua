-- The game's world map pins and the call it blocks in combat. With the map in an
-- addon's name (the continuous map puts zones up itself), every pin handed out
-- during a fight raised "tried to call the protected function
-- 'Button:SetPassThroughButtons()'". Guarded pins skip the call in a fight and
-- make it afterwards; protected pins and pins with a check of their own are
-- left exactly as they are.
local root = ...

local combat = false
function InCombatLockdown() return combat end
function securecallfunction(fn, ...) return fn(...) end
function hooksecurefunc(owner, name, hook)
    local original = owner[name]
    owner[name] = function(...)
        local a, b = original(...)
        hook(...)
        return a, b
    end
end

---------------------------------------------------------------------------
-- The map's pins and pools, as far as handing a pin out goes
---------------------------------------------------------------------------
local blocked = 0 -- protected calls made during a fight: each one an error in the game
MapCanvasPinMixin = {}
function MapCanvasPinMixin:CheckMouseButtonPassthrough(...)
    assert(self.owningMap, "a pin asks its map which buttons to let through")
    self:SetPassThroughButtons(...)
end
local function NewPin(protected)
    local pin = { protected = protected, calls = 0 }
    for key, value in pairs(MapCanvasPinMixin) do pin[key] = value end
    function pin:SetPassThroughButtons(...)
        if combat then blocked = blocked + 1; return end
        self.calls, self.set = self.calls + 1, table.concat({ ... }, ",")
    end
    function pin:IsProtected() return self.protected == true end
    function pin:IsForbidden() return false end
    return pin
end

local Pool = {}
function Pool:Acquire()
    local pin = table.remove(self.inactive)
    local new = pin == nil
    if new then pin = self.create() end
    self.active[pin] = true
    return pin, new
end
function Pool:Release(pin)
    self.active[pin] = nil
    table.insert(self.inactive, pin)
end
function Pool:EnumerateActive() return pairs(self.active) end
function Pool:EnumerateInactive() return ipairs(self.inactive) end

local TEMPLATES = {
    Quest = function() return NewPin() end,
    Flight = function() return NewPin() end,
    Group = function() return NewPin(true) end, -- party members: a protected frame
    Addon = function()                          -- another addon's pin, with a check of its own
        local pin = NewPin()
        pin.CheckMouseButtonPassthrough = function(self) self.own = (self.own or 0) + 1 end
        return pin
    end,
}
WorldMapFrame = { pinPools = {} }
function WorldMapFrame:AcquirePin(template)
    if not self.pinPools[template] then
        self.pinPools[template] = setmetatable({ active = {}, inactive = {}, create = TEMPLATES[template] },
            { __index = Pool })
    end
    local pin, new = self.pinPools[template]:Acquire()
    pin.pinTemplate, pin.owningMap = template, self
    pin:CheckMouseButtonPassthrough("LeftButton", "RightButton")
    return pin, new
end
function WorldMapFrame:RemovePin(pin)
    self.pinPools[pin.pinTemplate]:Release(pin)
    pin.owningMap = nil
end

local ns, events = {}, {}
function ns:NewModule(name) self[name] = { name = name }; return self[name] end
function ns:RegisterEvent(event, fn) events[event] = events[event] or {}; table.insert(events[event], fn) end
local function fight(on)
    combat = on
    for _, fn in ipairs(events[on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED"] or {}) do fn() end
end
MiniQoLRuntime = { Execute = function(_, _, fn) return fn("Wayfinder", ns) end }
assert(loadfile(root .. "/Modules/Wayfinder/PinGuard.lua"))("Wayfinder", ns)
local Guard = ns.PinGuard
Guard:OnLogin()

local function equal(actual, expected, label)
    assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local BUTTONS = "LeftButton,RightButton"

---------------------------------------------------------------------------
-- 1. Unguarded: the error as it was reported
---------------------------------------------------------------------------
local first = WorldMapFrame:AcquirePin("Quest")
equal(first.set, BUTTONS, "out of combat a pin is told its buttons")
WorldMapFrame:RemovePin(first)
fight(true)
WorldMapFrame:RemovePin(WorldMapFrame:AcquirePin("Quest"))
equal(blocked, 1, "in a fight the same pin makes the protected call")
fight(false)
blocked = 0
equal(rawget(WorldMapFrame.pinPools.Quest, "Acquire"), nil, "nothing is guarded until Wayfinder drives the map")

---------------------------------------------------------------------------
-- 2. Guarded: skipped in a fight, made when it ends
---------------------------------------------------------------------------
assert(Guard:Arm(), "armed once Wayfinder puts maps up itself")
assert(Guard:Arm() and Guard:IsArmed(), "and only once")
local reused = WorldMapFrame:AcquirePin("Quest")
equal(reused, first, "the pool hands the same pin back")
equal(reused.calls, 2, "out of combat it is told its buttons as before")

fight(true)
WorldMapFrame:RemovePin(reused)
local a = WorldMapFrame:AcquirePin("Quest") -- one from the pool
local b = WorldMapFrame:AcquirePin("Quest") -- one made during the fight
local c = WorldMapFrame:AcquirePin("Quest") -- another, gone again before the fight ends
equal(a, first, "a pin from the pool")
equal(blocked, 0, "no protected call in a fight, for pins old or new")
equal(b.set, nil, "the new pin waits")
WorldMapFrame:RemovePin(c)
fight(false)
equal(b.set, BUTTONS, "and is told its buttons when the fight ends")
equal(a.calls, 3, "so is the reused one")
equal(c.set, nil, "one back in its pool is not asked without a map")
equal(WorldMapFrame:AcquirePin("Quest"), c, "handed out again")
equal(c.set, BUTTONS, "it catches up then")
equal(blocked, 0, "still nothing blocked")

---------------------------------------------------------------------------
-- 3. Left exactly as they are
---------------------------------------------------------------------------
local member = WorldMapFrame:AcquirePin("Group")
equal(rawget(WorldMapFrame.pinPools.Group, "Acquire"), nil, "a pool of protected pins is not touched")
equal(member.CheckMouseButtonPassthrough, MapCanvasPinMixin.CheckMouseButtonPassthrough, "nor are its pins")
local theirs = WorldMapFrame:AcquirePin("Addon")
equal(theirs.own, 1, "a pin with a check of its own keeps it")
fight(true)
WorldMapFrame:RemovePin(theirs)
equal(WorldMapFrame:AcquirePin("Addon").own, 2, "in a fight as well")
fight(false)

---------------------------------------------------------------------------
-- 4. A kind of pin first made during a fight
---------------------------------------------------------------------------
fight(true)
blocked = 0
WorldMapFrame:AcquirePin("Flight")
equal(blocked, 1, "its very first pin can't be guarded in time")
WorldMapFrame:AcquirePin("Flight")
equal(blocked, 1, "every one after it is")
fight(false)

print("Pin guard: the game's map pins skip the protected call in a fight and make it after; protected pins and others' checks untouched")
