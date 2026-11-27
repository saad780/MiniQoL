-- Diagnostics: an error in code that runs every frame is reported once and
-- then counted, and /mqol blocked lists every action the game blocked.
local root = ...
local frame
function CreateFrame()
    frame = { events = {} }
    function frame:RegisterEvent(name) self.events[name] = true end
    function frame:SetScript(name, fn) self[name] = fn end
    return frame
end
local reported = {}
function geterrorhandler() return function(message) reported[#reported + 1] = message end end
local now, combat = 100, false
function GetTime() return now end
function InCombatLockdown() return combat end
local said = {}
function print(...) said[#said + 1] = table.concat({ ... }, " ") end

local ns = {}
function ns:Print(message) said[#said + 1] = message end
assert(loadfile(root .. "/Diagnostics.lua"))("MiniQoL", ns)
local D = ns.Diagnostics

local function equal(actual, expected, label)
    assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

-- 1. A broken per-frame handler: one report, then counting.
local calls = 0
local handler = ns.Guarded(function(_, elapsed)
    calls = calls + 1
    if elapsed > 1 then error("Arrow.lua:12: attempt to index a nil value") end
end, "Wayfinder arrow")
for _ = 1, 60 do handler(nil, 2) end
equal(calls, 60, "the handler keeps running")
equal(#reported, 1, "sixty failures, one report")
assert(reported[1]:find("Wayfinder arrow", 1, true) and reported[1]:find("Arrow.lua:12", 1, true),
    "the report names the handler and the place: " .. reported[1])
handler(nil, 0)
equal(#reported, 1, "a good frame reports nothing")
local other = ns.Guarded(function() error("Trails.lua:5: bad argument") end, "ant trails")
other(); other()
equal(#reported, 2, "a different error is reported in its own right")
equal(ns.Guarded(nil), nil, "nothing to guard is left alone")

-- 2. Blocked actions, by any addon.
frame.OnEvent(frame, "ADDON_ACTION_BLOCKED", "MiniQoL", "Button:SetPassThroughButtons()")
now, combat = 160, true
frame.OnEvent(frame, "ADDON_ACTION_BLOCKED", "MiniQoL", "Button:SetPassThroughButtons()")
frame.OnEvent(frame, "ADDON_ACTION_FORBIDDEN", "SomeAddon", "CastSpellByName()")
assert(frame.events.ADDON_ACTION_BLOCKED and frame.events.ADDON_ACTION_FORBIDDEN, "listens for both")
local list = D.BlockedList()
equal(#list, 2, "one line per addon and action")
equal(list[1].count, 2, "counted")
equal(list[1].combat, true, "and noted as happening in combat")
equal(list[2].kind, "forbidden", "forbidden kept apart from blocked")

said = {}
now = 220
D.Print()
local text = table.concat(said, "\n")
assert(text:find("MiniQoL  Button:SetPassThroughButtons()  2 times, last 1 min ago, in combat", 1, true), text)
assert(text:find("SomeAddon  CastSpellByName()  forbidden once", 1, true), text)
assert(text:find("Arrow.lua:12: attempt to index a nil value  (60 times)", 1, true), text)

print = nil
_G.print = function() end
io.write("Diagnostics: per-frame errors reported once then counted, blocked actions listed passed\n")
