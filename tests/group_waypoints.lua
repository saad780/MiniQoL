-- The group leader's waypoint goes to the group: members take it on their
-- arrow, it goes when the leader removes theirs, a boss fight holds the
-- message back until messages are allowed, and the leader hears who got it.
local root = ...

---------------------------------------------------------------------------
-- A party of three on one client each: the test plays one at a time
---------------------------------------------------------------------------
local me = "Leader"
local party = { "Leader", "Mira", "Tobb" } -- party1, party2 are the others
local leaderName = "Leader"
local inGroup = true
local function Units()
    local others = {}
    for _, name in ipairs(party) do if name ~= me then others[#others + 1] = name end end
    return others
end
local function NameOf(unit)
    if unit == "player" then return me end
    local index = tonumber(unit:match("^party(%d)$"))
    return index and Units()[index]
end
function IsInGroup() return inGroup end
function IsInRaid() return false end
function UnitExists(unit) return NameOf(unit) ~= nil end
function UnitIsUnit(a, b) return NameOf(a) == NameOf(b) end
function UnitName(unit) return NameOf(unit), nil end
function UnitIsGroupLeader(unit) return NameOf(unit) == leaderName end

local sent, lockdown = {}, false
C_ChatInfo = {
    RegisterAddonMessagePrefix = function(prefix) C_ChatInfo.prefix = prefix end,
    SendAddonMessage = function(prefix, text, channel) sent[#sent + 1] = { prefix = prefix, text = text, channel = channel } end,
    InChatMessagingLockdown = function() return lockdown end,
}
-- Timers on a clock of the test's own.
local timers, clock = {}, 0
C_Timer = { After = function(delay, fn) timers[#timers + 1] = { at = clock + delay, fn = fn } end }
local function advance(seconds)
    clock = clock + seconds
    local ran = true
    while ran do
        ran = false
        for i, timer in ipairs(timers) do
            if timer.at <= clock then
                table.remove(timers, i)
                timer.fn()
                ran = true
                break
            end
        end
    end
end
local function step() advance(1) end      -- past the burst, short of the report
local function settle() advance(30) end   -- everything due

---------------------------------------------------------------------------
-- Wayfinder's namespace, with an arrow that keeps a list
---------------------------------------------------------------------------
local ns = { db = { settings = { shareGroupWaypoint = true, followGroupWaypoint = true, reportGroupWaypoint = true } } }
function ns:NewModule(name) self[name] = { name = name }; return self[name] end
function ns:GetSetting(key) return self.db.settings[key] end
function ns.Readable(value) return value ~= nil end
local listeners, events = {}, {}
function ns:On(message, fn) listeners[message] = listeners[message] or {}; table.insert(listeners[message], fn) end
function ns:Fire(message, ...) for _, fn in ipairs(listeners[message] or {}) do fn(...) end end
function ns:RegisterEvent(event, fn) events[event] = events[event] or {}; table.insert(events[event], fn) end
local function event(name, ...) for _, fn in ipairs(events[name] or {}) do fn(name, ...) end end
local printed = {}
function ns.Print(message) printed[#printed + 1] = message end

local current
local sources = {}
ns.Navigation = {
    GetWaypoint = function() return current end,
    GetSourceWaypoint = function(_, source) return sources[source] end,
    PlaceSourceWaypoint = function(_, source, c, x, y, label, mapID, options)
        local rec = { source = source, c = c, x = x, y = y, n = label, m = mapID, note = options.note }
        sources[source] = rec
        if options.focus then current = rec end
        return rec
    end,
    RemoveWaypoint = function(_, rec)
        if sources[rec.source] == rec then sources[rec.source] = nil end
        if current == rec then current = nil end
    end,
}
local function setWaypoint(rec)
    current = rec
    ns:Fire("WAYPOINT_CHANGED", rec)
end

MiniQoLRuntime = { Execute = function(_, _, fn) return fn("Wayfinder", ns) end }
assert(loadfile(root .. "/Modules/Wayfinder/GroupWaypoints.lua"))("Wayfinder", ns)
local Group = ns.GroupWaypoints
Group:OnLogin()

local function equal(actual, expected, label)
    assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
-- What a member's client hears when the last message went out.
local function deliver(index, from, as)
    local message = sent[index]
    local before = me
    me = as
    event("CHAT_MSG_ADDON", message.prefix, message.text, message.channel, from)
    me = before
end

equal(C_ChatInfo.prefix, "MiniQoLWay", "the prefix is registered")

---------------------------------------------------------------------------
-- 1. The leader sets a waypoint: it goes out once the burst settles
---------------------------------------------------------------------------
setWaypoint({ c = 0, x = 1234.567, y = -890.12, m = 1429, n = "Goldshire\tInn" })
setWaypoint(current)
equal(#sent, 0, "nothing until the change settles")
step()
equal(#sent, 1, "one message for the burst")
equal(sent[1].channel, "PARTY", "on the party channel")
local fields = {}
for field in (sent[1].text .. "\t"):gmatch("([^\t]*)\t") do fields[#fields + 1] = field end
equal(fields[1], "W", "a waypoint")
equal(fields[5], "1234.6", "world yards to a tenth")
equal(fields[8], "Goldshire Inn", "the label without tabs")
equal(fields[9], "1", "asking who got it")
setWaypoint(current); step()
equal(#sent, 1, "the same waypoint isn't sent again")

---------------------------------------------------------------------------
-- 2. A member takes it; a member with following off says so
---------------------------------------------------------------------------
current, sources = nil, {}
deliver(1, "Leader-Realm", "Mira")
local taken = sources.group
assert(taken and taken.c == 0 and math.abs(taken.x - 1234.6) < 1e-6 and taken.n == "Goldshire Inn", "Mira's arrow has it")
equal(current, taken, "and points at it")
assert(taken.note:find("Leader", 1, true), "naming who shared it")
equal(#sent, 2, "Mira answers")
assert(sent[2].text:match("^A\t1\t1\tgot$"), "that she got it: " .. sent[2].text)

ns.db.settings.followGroupWaypoint = false
current, sources = nil, {}
deliver(1, "Leader-Realm", "Tobb")
equal(sources.group, nil, "Tobb, following off, doesn't take it")
assert(sent[3].text:match("^A\t1\t1\toff$"), "and says so")
ns.db.settings.followGroupWaypoint = true

-- Someone who isn't the leader can't set waypoints on others.
deliver(1, "Tobb-Realm", "Mira")
equal(sources.group, nil, "a member's message is ignored")
equal(#sent, 3, "and unanswered")

---------------------------------------------------------------------------
-- 3. The leader hears who got it
---------------------------------------------------------------------------
current = { c = 0, x = 1234.567, y = -890.12, m = 1429, n = "Goldshire" }
deliver(2, "Mira-Realm", "Leader")
deliver(3, "Tobb-Realm", "Leader")
settle()
local report = printed[#printed]
assert(report and report:find("got it: Mira", 1, true) and report:find("following turned off: Tobb", 1, true), tostring(report))

---------------------------------------------------------------------------
-- 4. The leader removes it: so do the members
---------------------------------------------------------------------------
setWaypoint(nil); settle()
assert(sent[#sent].text:match("^C\t1\t2\t1$"), "a clear goes out: " .. sent[#sent].text)
local clear = #sent
current, sources = nil, {}
sources.group = { source = "group" }
deliver(clear, "Leader-Realm", "Mira")
equal(sources.group, nil, "Mira's copy goes")

-- The arrow on the leader's corpse is nobody else's business.
setWaypoint({ source = "corpse", c = 0, x = 1, y = 1, n = "Your corpse" }); settle()
equal(#sent, clear + 1, "only Mira's answer: no corpse waypoint is shared")

---------------------------------------------------------------------------
-- 5. A boss fight: held back, then sent
---------------------------------------------------------------------------
lockdown = true
setWaypoint({ c = 0, x = 50, y = 60, m = 1429, n = "Boss room" })
local count = #sent
settle() -- the retry finds messages still locked
equal(#sent, count, "nothing while messages are locked")
lockdown = false
event("ENCOUNTER_END")
equal(#sent, count + 1, "sent once the fight is over")
assert(sent[#sent].text:find("Boss room", 1, true), "the newest waypoint")

---------------------------------------------------------------------------
-- 6. A member who joins asks once; leaving the group lets it go
---------------------------------------------------------------------------
me, leaderName = "Mira", "Leader"
count = #sent
event("GROUP_ROSTER_UPDATE")
assert(sent[count + 1] and sent[count + 1].text == "R\t1", "a new member asks for the waypoint")
event("GROUP_ROSTER_UPDATE")
equal(#sent, count + 1, "once")
me = "Leader"
deliver(count + 1, "Mira-Realm", "Leader")
assert(sent[#sent].text:find("Boss room", 1, true) and sent[#sent].text:match("\t0$"), "the leader answers, asking nothing back")
me = "Mira"
sources.group = { source = "group" }
inGroup = false
event("GROUP_ROSTER_UPDATE")
equal(sources.group, nil, "leaving the group lets the shared waypoint go")

print("Group waypoints: shared by the leader after a burst, taken by members, cleared, corpse kept back, held through a boss fight, asked for on joining, who got it reported passed")
