-- The group leader's waypoint goes to the group: members take it on their
-- arrow and follow it as it moves, it goes when the leader has none, a boss fight holds the
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
local surnames = {} -- name -> surname, as Forever gives it
function UnitName(unit) local name = NameOf(unit); return name, name and surnames[name] end
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
local function split(text)
    local fields = {}
    for field in (text .. "\t"):gmatch("([^\t]*)\t") do fields[#fields + 1] = field end
    return fields
end

---------------------------------------------------------------------------
-- 0. Who sent a message, on Forever and elsewhere
---------------------------------------------------------------------------
local IsSender = Group.IsSender
assert(IsSender("Mira-Realm", "party1"), "Name-Realm against a bare name on your own realm")
surnames.Mira = "Cake"
assert(IsSender("Mira-Cake", "party1"), "Forever: the dash before the surname")
assert(IsSender("Mira Cake", "party1"), "Forever: the space before the surname")
assert(IsSender("Mira-6922", "party1"), "Forever: a server number after the dash")
assert(not IsSender("Mira-Pie", "party1"), "a different surname is someone else")
assert(not IsSender("Tobb-Cake", "party1"), "a different first name is someone else")
party[2], surnames.Mira = "Mira Cake", nil -- UnitName with the surname inside the name
assert(IsSender("Mira-Cake", "party1"), "the surname inside UnitName's first value")
party[2] = "Mira"

---------------------------------------------------------------------------
-- 1. The leader sets a waypoint: it goes out once the burst settles
---------------------------------------------------------------------------
setWaypoint({ c = 0, x = 1234.567, y = -890.12, m = 1429, n = "Goldshire\tInn" })
setWaypoint(current)
equal(#sent, 0, "nothing until the change settles")
step()
equal(#sent, 1, "one message for the burst")
equal(sent[1].channel, "PARTY", "on the party channel")
local fields = split(sent[1].text)
equal(fields[1], "W", "a waypoint")
assert(fields[3]:match("^%d+%.1$"), "named for this session and change: " .. fields[3])
local firstID = fields[3]
equal(fields[5], "1234.6", "world yards to a tenth")
equal(fields[8], "Goldshire Inn", "the label without tabs")
equal(fields[9], "1", "asking who got it")
setWaypoint(current); step()
equal(#sent, 1, "the same waypoint isn't sent again")
local leaderWaypoint = current

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
equal(sent[2].text, "A\t2\t" .. firstID .. "\tgot", "that she got it")

ns.db.settings.followGroupWaypoint = false
local miraCurrent, miraSources = current, sources
current, sources = nil, {}
deliver(1, "Leader-Realm", "Tobb")
equal(sources.group, nil, "Tobb, following off, doesn't take it")
equal(sent[3].text, "A\t2\t" .. firstID .. "\toff", "and says so")
ns.db.settings.followGroupWaypoint = true

-- Someone who isn't the leader can't set waypoints on others.
current, sources = miraCurrent, miraSources
deliver(1, "Tobb-Realm", "Mira")
equal(#sent, 3, "a member's message is ignored, unanswered")

---------------------------------------------------------------------------
-- 3. The leader hears who got it, even when someone joins meanwhile
---------------------------------------------------------------------------
local miraState = { current = current, sources = sources }
current, sources = leaderWaypoint, {}
event("CHAT_MSG_ADDON", "MiniQoLWay", "R\t2", "PARTY", "Tobb-Realm") -- someone reloads
local again = split(sent[#sent].text)
equal(again[3], firstID, "the same waypoint goes out again under the same id")
equal(again[9], "0", "asking nothing back")
local resend = #sent
deliver(2, "Mira-Realm", "Leader")
deliver(3, "Tobb-Realm", "Leader")
settle()
local report = printed[#printed]
assert(report and report:find("got it: Mira", 1, true) and report:find("following turned off: Tobb", 1, true), tostring(report))

-- That resend changes nothing for a member who already has it...
current, sources = miraState.current, miraState.sources
local elsewhere = { c = 0, x = 1, y = 1, n = "Mira's own" }
current = elsewhere
deliver(resend, "Leader-Realm", "Mira")
equal(current, elsewhere, "Mira's arrow stays on her own waypoint")
-- ...nor for one who removed it.
local removed = sources.group
sources.group = nil
ns:Fire("WAYPOINT_REMOVED", removed)
deliver(resend, "Leader-Realm", "Mira")
equal(sources.group, nil, "a removed waypoint doesn't come back")

---------------------------------------------------------------------------
-- 4. The leader's arrow moves on: so does everyone's; none left: theirs goes
---------------------------------------------------------------------------
current, sources = leaderWaypoint, {}
setWaypoint({ c = 0, x = 2000, y = 2000, m = 1429, n = "The mill" }); settle()
local moved = split(sent[#sent].text)
assert(moved[1] == "W" and moved[3]:match("%.2$") and moved[8] == "The mill", "the next waypoint, a new id")
local movedAt = #sent
current, sources = elsewhere, {}
deliver(movedAt, "Leader-Realm", "Mira")
assert(sources.group and sources.group.n == "The mill", "Mira takes the new one, though she removed the last")
local miraHas = { current = current, sources = sources }
current, sources = nil, {}
setWaypoint(nil); settle()
assert(sent[#sent].text:match("^C\t2\t%d+%.3$"), "a clear goes out: " .. sent[#sent].text)
local clear = #sent
current, sources = miraHas.current, miraHas.sources
deliver(clear, "Leader-Realm", "Mira")
equal(sources.group, nil, "Mira's copy goes")

-- The arrow on the leader's corpse is nobody else's business.
current, sources = nil, {}
local before = #sent
setWaypoint({ source = "corpse", c = 0, x = 1, y = 1, n = "Your corpse" }); settle()
equal(#sent, before, "no corpse waypoint is shared")

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

-- Sharing switched off: the members' waypoint goes.
ns.db.settings.shareGroupWaypoint = false
ns:Fire("SETTING_CHANGED", "shareGroupWaypoint")
assert(sent[#sent].text:match("^C\t"), "switching sharing off clears theirs")
ns.db.settings.shareGroupWaypoint = true

---------------------------------------------------------------------------
-- 6. A member who joins asks once; the lead changing hands or leaving the
-- group lets it go
---------------------------------------------------------------------------
me, leaderName = "Mira", "Leader"
count = #sent
event("GROUP_ROSTER_UPDATE")
equal(sent[count + 1] and sent[count + 1].text, "R\t2", "a new member asks for the waypoint")
event("GROUP_ROSTER_UPDATE")
equal(#sent, count + 1, "once")
event("CHAT_MSG_ADDON", "MiniQoLWay", "W\t2\tabc.9\t0\t5\t5\t1429\tCamp\t0", "PARTY", "Leader-Realm")
assert(sources.group and sources.group.n == "Camp", "Mira has the leader's waypoint")
leaderName = "Tobb"
event("PARTY_LEADER_CHANGED")
equal(sources.group, nil, "a new leader: the old leader's waypoint goes")
equal(sent[#sent].text, "R\t2", "and the new leader is asked")
sources.group = { source = "group" }
inGroup = false
event("GROUP_ROSTER_UPDATE")
equal(sources.group, nil, "leaving the group lets the shared waypoint go")

print("Group waypoints: Forever names, shared by the leader after a burst, taken by members, resent to joiners without disturbing others, followed as it moves, cleared, corpse kept back, held through a boss fight, withdrawn when sharing stops or the lead changes, who got it reported passed")
