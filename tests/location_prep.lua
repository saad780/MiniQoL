local package = ...
local ns = {}
for _, file in ipairs({ "Core", "PrepData", "PrepRoute" }) do
    assert(loadfile(package .. "/Explorer/" .. file .. ".lua"))("MiniQoL", ns)
end
local prep = ns.Explorer.Prep
assert(not prep.Provider(), "Questie optional for the rest of MiniQoL")
local function source(name, area, x)
    return { name = name, spawns = { [area] = { { x, 50 } } } }
end
local npcs = { [1] = source("Sputtervalve", 17, 63), [2] = source("Ziz Fizziks", 406, 59),
    [3] = source("Logger", 406, 60), [4] = source("Traveler", 17, 31) }
npcs[5] = { name = "Wandering mob", spawns = { [406] = {{10, 20}}, [17] = {{11, 21}} } }
local objects = { [20] = source("Egg sack", 406, 58) }
local items = { [30] = { name = "Egg", objectDrops = {20} }, [31] = { name = "Cloth", npcDrops = {5} } }
local function q(name, start, finish, work, extra)
    local row = extra or {}
    row.name, row.startedBy, row.finishedBy, row.objectives = name, {{start}}, {{finish}}, work
    return row
end
local quests = {
    [11] = q("Outside prerequisite", 4, 1),
    [12] = q("Outside pickup unlocked", 1, 2, { [3] = {{30}} }, {preQuestGroup = {11}}),
    [13] = q("Local follow-up", 2, 2, { {{3}} }, {preQuestSingle = {12}}),
    [14] = q("Unavoidable return", 2, 1, nil, {preQuestSingle = {13}}),
    [15] = q("Bring the news back", 1, 2, nil, {preQuestSingle = {14}}),
    [16] = q("Wrong faction", 2, 2, nil, {requiredRaces = 8}),
    [17] = q("Wrong class", 2, 2, nil, {requiredClasses = 8}),
    [18] = q("Future pickup", 1, 2, nil, {requiredLevel = 35}),
    [19] = q("Unknown pickup", nil, 2),
    [20] = q("Not offered", 1, 2),
    [21] = q("Remote only", 1, 4),
    [22] = q("Donation elsewhere", 1, 4, { [3] = {{31}} }),
    [23] = q("Flexible giver", 1, 2, nil),
    [24] = q("Introduction", 4, 2, nil, {breadcrumbForQuestId = 25}),
    [25] = q("Do after the introduction", 2, 2, nil, {breadcrumbs = {24}}),
    [26] = q("Event without coordinates", 2, 2, nil, {specialFlags = 2, objectivesText = {"Visit the cave"}}),
    [27] = q("Item starter", nil, 1),
    [28] = q("Do either first", 2, 2, nil, {preQuestSingle = {11, 21}}),
    [29] = q("Already turned in", 2, 2),
}
quests[23].startedBy = {{1,2}}
quests[27].startedBy = { [3] = {30} }
local function field(rows) return function(id, key) return rows[id] and rows[id][key] end end
local completed, active, ready = {[29]=true}, {}, {}
local db = { QuestPointers = quests, QueryQuestSingle = field(quests), QueryNPCSingle = field(npcs),
    QueryObjectSingle = field(objects), QueryItemSingle = field(items),
    IsDoable = function(id) return id ~= 20 and id ~= 12 and id ~= 13 and id ~= 14 and id ~= 15 end,
    IsPreQuestGroupFulfilled = function(_, group) return completed[group[1]] end }
local identity = function(_, id) return id end
QuestieLoader = { _modules = { QuestieDB = db, ZoneDB = { GetUiMapIdByAreaId = identity, GetParentZoneId = function() end },
    QuestiePlayer = { HasRequiredClass = function(mask) return mask ~= 8 end, HasRequiredRace = function(mask) return mask ~= 8 end,
        GetPlayerLevel = function() return 26 end } } }
Questie = { API = { isReady = true }, db = { char = { complete = completed } } }
C_QuestLog = { IsOnQuest = function(id) return active[id] == true end, IsComplete = function(id) return ready[id] == true end }
local ticks = 0
local function tick() ticks = ticks + 1 end
local records = prep.ScanZone(406, tick)
assert(not records[16] and not records[17] and ticks > 20)
local function plan(origin)
    local route, waiting, optional = prep.Route(records, prep.Character(), origin, tick)
    local steps, pending = {}, {}
    for i, step in ipairs(route) do
        local key = step.id .. "." .. step.kind
        assert(not steps[key], "duplicate step " .. key)
        steps[key] = {i=i, phase=step.phase, place=step.place, after=step.after}
    end
    for _, w in ipairs(waiting) do pending[w.id] = w.label end
    return steps, pending, optional
end
local steps, pending, optional = plan()
assert(steps["11.3"].i < steps["12.1"].i and steps["12.1"].phase == "Before traveling")
assert(steps["12.2"].place.name == "Egg sack" and steps["12.2"].phase == "In the zone")
assert(steps["12.3"].i < steps["13.1"].i and steps["13.1"].after:find("Outside pickup unlocked",1,true))
assert(steps["13.3"].i < steps["14.1"].i and steps["14.3"].phase == "Outside the zone")
assert(steps["14.3"].i < steps["15.1"].i and steps["15.1"].phase == "Outside the zone" and steps["15.3"].phase == "In the zone")
assert(steps["23.1"].phase == "In the zone" and steps["27.1"].place.name == "Egg from Egg sack")
assert(steps["24.3"].i < steps["25.1"].i and not steps["21.1"], "breadcrumb ordering and only one OR prerequisite")
assert(pending[18]:find("35") and pending[19]:find("unknown") and pending[20] and pending[26]:find("Visit the cave"))
assert(not steps["29.1"] and not steps["29.3"])
assert(not steps["22.1"] and #optional == 1 and optional[1].id == 22, "common cloth sources are optional")
active[12], ready[12], completed[11] = true, true, true
steps = plan()
assert(not steps["12.1"] and not steps["12.2"] and steps["12.3"] and not steps["11.1"])
ready[12] = nil
db.GetQuest = function() return { ObjectiveData = { {Type="item", Id=30} } } end
C_QuestLog.GetQuestObjectives = function() return { {finished=true} } end
steps = plan()
assert(not steps["12.2"] and steps["12.3"], "completed individual goal dropped on refresh")
active[14], ready[14] = true, true
steps = plan({here=true, mapID=406, x=0.5, y=0.5})
assert(steps["14.3"].phase == "Outside the zone" and steps["14.3"].i > steps["23.1"].i,
    "a newly completed quest keeps its remote hand-in for the outside trip")
active[14], ready[14] = nil, nil
active[12] = nil
steps = plan()
assert(steps["12.1"] == nil, "unavailable after abandonment when Questie still blocks it")
-- Gated data may contain cycles. They must remain visible without fabricating a pickup.
records[13].any, records[14].any = {14}, {13}
steps, pending = plan()
assert(not steps["13.1"] and pending[13] and pending[14])
print("Location Prep: incoming pickups, outside prerequisites, optional sources, breadcrumbs, local chains, return trips and character progress passed")
