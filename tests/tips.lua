-- Tips: one per login, each once per account, skipped while it doesn't apply,
-- and none when switched off.
local root = ...
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function settle() local due = timers; timers = {}; for _, fn in ipairs(due) do fn() end end
local loaded = { Questie = false }
C_AddOns = { IsAddOnLoaded = function(name) return loaded[name] == true end }
local said = {}
local ns = { db = { dialogue = { enabled = true } } }
function ns:Print(message) said[#said + 1] = message end
assert(loadfile(root .. "/Tips.lua"))("MiniQoL", ns)
local Tips = ns.Tips

local function equal(actual, expected, label)
    assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

Wayfinder = nil
Tips.OnLogin()
settle()
equal(#said, 1, "one tip at login")
assert(said[1]:find("/mqol", 1, true), "the first is about the panel: " .. said[1])
Tips.OnLogin(); settle()
equal(#said, 2, "the next login, the next tip")
assert(not said[2]:find("Middle-click", 1, true), "Wayfinder's tips wait while it isn't there: " .. said[2])

local settings = { questMiddleClick = true, showArrow = true, detailEnabled = true, antTrails = true }
Wayfinder = { db = {}, GetSetting = function(_, key) return settings[key] end }
Tips.OnLogin(); settle()
assert(said[3]:find("Middle-click", 1, true) and said[3]:find("world map", 1, true), "then the waypoint tip: " .. said[3])
local seen = {}
for _, text in ipairs(said) do seen[text] = true end

ns.db.tips = false
Tips.OnLogin(); settle()
equal(#said, 3, "switched off: none")
ns.db.tips = nil

for _ = 1, #Tips.LIST do Tips.OnLogin(); settle() end
local count = #said
Tips.OnLogin(); settle()
equal(#said, count, "all shown: they stop")
for i = 1, #said do for j = i + 1, #said do assert(said[i] ~= said[j], "no tip twice") end end
loaded.Questie = true
Tips.OnLogin(); settle()
equal(#said, count + 1, "a tip that didn't apply before comes once it does")
Tips.ShowNext()
equal(#said, count + 2, "/mqol tip starts over once all are seen")

io.write("Tips: one per login, once each, skipped until they apply, off switch, /mqol tip passed\n")
