local root = ...
local ns = {}
MiniQoLRuntime = { Execute = function(_, _, fn) return fn("Wayfinder", ns) end }
assert(loadfile(root .. "/Modules/Wayfinder/QuestRoute.lua"))("Wayfinder", ns)
local plan = ns.RoutePlanner.Plan
local start = { x = 0, y = 0 }
local function point(x, y, penalty)
    return { x = x, y = y or 0, penalty = penalty }
end
local function task(key, id, kind, coords, optional, after)
    return { key = key, label = key, questID = id, quest = "Quest " .. id,
        kind = kind, candidates = coords, optional = optional, after = after }
end
local function keys(result)
    local order = {}
    for _, stop in ipairs(result.stops) do order[#order + 1] = stop.task.key end
    return table.concat(order, " ")
end

-- Choose camps for the whole open route. The first point of 1 is marginally
-- closer to the player yet costs more once the walk to its hand-in is counted.
local camps = { point(0,4), point(5,0), point(6,0,50) }
local active = { task("work",1,"objective",camps), task("hand-in",1,"turnin",{point(15)}) }
local result = plan(active, start)
assert(keys(result) == "work hand-in")
assert(result.stops[1].point == camps[2] and result.cost == 15)
local walked = plan(active, start, {distance=function(a,b)
    if a == start and b == camps[2] then return 100 end
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
end})
assert(walked.stops[1].point == camps[1], "learned terrain costs enter the fixed-order DP")

local other = task("other",2,"objective",{point(0.1)})
active[#active + 1] = other
result = plan(active, start, { forced="hand-in" })
assert(keys(result) == "work hand-in other", "pinning respects dependencies and holds unrelated stops back")
result = plan(active, start, { skips={work=true}, forced="hand-in" })
assert(keys(result) == "other" and #result.why == 2)
assert(#plan(active, start).stops == 3, "skipping must not mutate the input")
local broken = {
    task("a",3,"objective",{point(1)},false,{"b"}), task("b",3,"objective",{point(2)},false,{"a"}),
    task("empty",4,"objective",{}),task("missing",5,"turnin",{point(3)},false,{"outside"}),other,
}
result = plan(broken, start)
assert(keys(result) == "other" and #result.why == 4, "cycles, absent camps and missing prerequisites are explained")

local choices = {
    task("active",10,"objective",{point(100)}),
    task("near",11,"pickup",{point(20)},true), task("eggs",11,"objective",{point(35)},true),
    task("deliver",11,"turnin",{point(38)},true),
    task("remote",12,"pickup",{point(1500)},true),
    task("more",13,"pickup",{point(100,40)},true),
}
result = plan(choices,start,{slots=1,worth=400})
assert(keys(result) == "near eggs deliver active" and #result.why == 2)
assert(keys(plan(choices,start,{slots=0,worth=1000})) == "active")
result = plan(choices,start,{slots=3,worth=400})
assert(#result.stops == 5 and #result.why == 1 and result.why[1]:find("remote"))
local old = {}
for _, stop in ipairs(result.stops) do old[#old+1] = stop.task.key end
local quick = plan(choices,start,{slots=3,worth=400,previous=old,progressOnly=true,previousWhy=result.why})
assert(keys(quick) == keys(result) and quick.why == result.why)
local similar = {task("a",31,"pickup",{point(20)},true),task("b",32,"pickup",{point(21)},true)}
assert(keys(plan(similar,start,{slots=1,previous={"b"}})) == "b",
    "a one-yard change leaves last frame's pickup in the last free log slot")
-- Two cheap neighbors far from everything else cannot hide the cost of the
-- journey by each claiming the other as the reason to visit.
result = plan({task("a",20,"pickup",{point(10000)},true),task("b",21,"pickup",{point(10001)},true)},start,
    {slots=2,worth=300})
assert(#result.stops == 0 and #result.why == 2)
local hysteresis = {task("a",20,"objective",{point(100)}), task("b",21,"objective",{point(103)})}
assert(keys(plan(hysteresis,start,{previous={"b","a"}})) == "b a", "small savings keep the existing order")
hysteresis[1].candidates[1].x = 20
assert(keys(plan(hysteresis,start,{previous={"b","a"}})) == "a b", "clear savings replace the existing order")

local large, tickCount, first = {}, 0
for i = 1, 36 do
    local id = math.ceil(i / 3)
    local kind = i % 3 == 0 and "turnin" or "objective"
    large[i] = task(tostring(i), id, kind, {point((i*7919)%1703,(i*4937)%1289),point((i*1097)%1703,(i*3319)%1289,7)})
end
result = plan(large, start, {tick=function() tickCount = tickCount + 1 end,
    publish=function(p) if not first then first=p end end})
assert(first and #first.stops == #large and result.cost < first.cost * 0.98 and tickCount > 10)
assert(#result.stops == #large, "a busy quest log keeps every active stop")
local done = {}
for _, stop in ipairs(result.stops) do
    local t = stop.task
    if t.kind == "turnin" then assert(done[t.questID] == 2) else done[t.questID] = (done[t.questID] or 0) + 1 end
end
local reversed = {}
for i = #large,1,-1 do reversed[#reversed+1] = large[i] end
assert(keys(plan(reversed,start)) == keys(result), "input iteration order never changes the seeded refinement")
-- Empty log, many available quests and few free slots. Repeated planning
-- must keep a whole legal chain for each admitted pickup and a stable order.
local offers = {}
for q = 1, 48 do
    for i, kind in ipairs({"pickup","objective","turnin"}) do
        local x = q * 11 + i * 2
        offers[#offers+1] = task(q .. "-" .. i, q, kind, {point(x, q%3), point(x+2,q%3+1)}, true)
    end
end
local crowded = plan(offers,start,{slots=4,worth=300})
local order, picked, counts = {}, {}, {}
assert(#crowded.stops==12 and #crowded.why==44)
for i,stop in ipairs(crowded.stops) do
    local t=stop.task
    order[i]=t.key
    counts[t.questID]=(counts[t.questID] or 0)+1
    if t.kind=="pickup" then picked[t.questID]=true else assert(picked[t.questID]) end
    if t.kind=="turnin" then assert(counts[t.questID]==3) end
end
assert(keys(plan(offers,start,{slots=4,worth=300,previous=order})) == keys(crowded))
print("Quest route planner: open camp DP, precedence, pinning, skips, detours, capacity, stable order and legal refinement passed")
