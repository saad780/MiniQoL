-- Mini QoL packaging adapter; upstream source and credits follow.
MiniQoLRuntime:Execute("Wayfinder", function(...)
-- Open route over quest stops. All positions and costs are in world yards.
-- The caller supplies the distance model and cooperative scheduler. Planning
-- never changes a quest, a map, a candidate or a previously published route.
local _, ns = ...
local Planner = {}
ns.RoutePlanner = Planner

local min, max, sqrt = math.min, math.max, math.sqrt
local huge = math.huge
local function noop() end
local function straight(a, b)
    return sqrt((a.x - b.x)^2 + (a.y - b.y)^2)
end

local function context(origin, opts)
    local distance, tick = opts.distance or straight, opts.tick or noop
    local cache, calls = {}, 0
    local function checkpoint()
        calls = calls + 1
        if calls % 32 == 0 then tick() end
    end
    local function leg(a, b)
        if not b or a == b then return 0 end -- open end
        checkpoint()
        local row = cache[a]
        if not row then row = {}; cache[a] = row end
        local d = row[b]
        if not d then
            d = distance(a, b)
            row[b] = d
        end
        return d
    end
    return { origin = origin, tick = tick, checkpoint = checkpoint, leg = leg, why = {} }
end

local function explain(ctx, node, reason)
    local t = node.task
    local name = t.quest or t.label or tostring(t.questID)
    if t.label and name ~= t.label then name = name .. " · " .. t.label end
    ctx.why[#ctx.why + 1] = name .. " — " .. reason
end

local function graph(ctx, tasks, skips)
    local all, byKey, quests = {}, {}, {}
    for _, t in ipairs(tasks) do
        local n = { task = t, key = t.key, points = t.candidates or {}, deps = {}, children = {}, stage = 1 }
        byKey[n.key], all[#all + 1] = n, n
        local q = quests[t.questID]
        if not q then q = { objectives = {} }; quests[t.questID] = q end
        if t.kind == "objective" then q.objectives[#q.objectives + 1] = n end
        if t.kind == "pickup" then q.pickup = n end
    end
    table.sort(all, function(a, b) return a.key < b.key end)
    for _, n in ipairs(all) do
        local seen = {}
        local function add(p)
            if not p then n.missing = true
            elseif not seen[p] then
                n.deps[#n.deps + 1] = p
                p.children[#p.children + 1] = n
                seen[p] = true
            end
        end
        local q = quests[n.task.questID]
        if q.pickup and n ~= q.pickup then add(q.pickup) end
        if n.task.kind == "turnin" then for _, obj in ipairs(q.objectives) do add(obj) end end
        for _, key in ipairs(n.task.after or {}) do add(byKey[key]) end
        if skips[n.key] then n.reason = "skipped"
        elseif #n.points == 0 then n.reason = "no candidate location in this zone"
        elseif n.missing then n.reason = "a prerequisite has no stop in this zone" end
        ctx.checkpoint()
    end

    -- Kahn's algorithm also removes descendants of skipped, missing and cyclic
    -- prerequisites. A skipped objective is still required for the turn-in.
    local ready = {}
    for _, n in ipairs(all) do
        n.pending = #n.deps
        if not n.reason and n.pending == 0 then ready[#ready + 1] = n end
    end
    local head = 1
    while head <= #ready do
        local n = ready[head]
        n.reachable = true
        for _, child in ipairs(n.children) do
            child.pending = child.pending - 1
            if child.pending == 0 and not child.reason then ready[#ready + 1] = child end
        end
        head = head + 1
        ctx.checkpoint()
    end
    local viable = {}
    for _, n in ipairs(all) do
        if n.reachable then viable[#viable + 1] = n
        else explain(ctx, n, n.reason or "an unfinished prerequisite is skipped, missing or cyclic") end
    end
    return viable, byKey
end

-- Stage restricts what may precede a pinned stop to its own prerequisite
-- closure. In particular a pinned turn-in can never outrun its objectives.
local function pinFirst(nodes, pinned)
    local included = {}
    for _, n in ipairs(nodes) do included[n] = true; n.stage = 1 end
    if not included[pinned] then return end
    for _, n in ipairs(nodes) do n.stage = 3 end
    local function mark(n)
        if n.stage ~= 3 then return end
        n.stage = 1
        for _, dep in ipairs(n.deps) do mark(dep) end
    end
    mark(pinned)
    pinned.stage = 2
end

local function greedy(ctx, nodes, ranks)
    local order, done = {}, {}
    local from = ctx.origin
    while #order < #nodes do
        local best, bestPoint, bestRank, bestCost
        for _, n in ipairs(nodes) do
            local ready = not done[n]
            for _, dep in ipairs(n.deps) do
                if not done[dep] then ready = false; break end
            end
            local rank = ranks and ranks[n.key] or huge
            if ready and (not best or n.stage < best.stage or (n.stage == best.stage and rank <= bestRank)) then
                for _, p in ipairs(n.points) do
                    local cost = ctx.leg(from, p) + (p.penalty or 0)
                    if not best or n.stage < best.stage or rank < bestRank or cost < bestCost then
                        best, bestPoint, bestRank, bestCost = n, p, rank, cost
                    end
                end
            end
            ctx.checkpoint()
        end
        if not best then break end
        order[#order + 1], done[best], from = best, true, bestPoint
    end
    return order
end

-- Dynamic programming: an entry records the least cost of ending this stop
-- at this candidate, and which candidate at the preceding stop got us here.
local function chooseCamps(ctx, order)
    local parents, costs, previous = {}, { 0 }, { ctx.origin }
    for i, n in ipairs(order) do
        local row, back = {}, {}
        for j, p in ipairs(n.points) do
            local best, index = huge, 1
            for k, other in ipairs(previous) do
                local d = costs[k] + ctx.leg(other, p)
                if d < best then best, index = d, k end
            end
            row[j], back[j] = best + (p.penalty or 0), index
        end
        parents[i], previous, costs = back, n.points, row
    end
    local index = 1
    for k = 2, #costs do if costs[k] < costs[index] then index = k end end
    local plan = { order = order, points = { [0] = ctx.origin }, cost = costs[index] }
    for i = #order, 1, -1 do
        plan.points[i] = order[i].points[index]
        index = parents[i][index]
    end
    return plan
end

local function project(order, keep)
    local result = {}
    for _, n in ipairs(order) do
        if keep(n) then result[#result + 1] = n end
    end
    return result
end

local function reportMissing(ctx, wanted, order)
    if #wanted == #order then return end
    local included = {}
    for _, n in ipairs(order) do included[n] = true end
    for _, n in ipairs(wanted) do
        if not included[n] then explain(ctx, n, "a required pickup was left off the route") end
    end
end

-- How much of this open walk disappears when each optional quest is omitted?
-- Adjacent stops of the same quest form one cut, so the walk that rejoins
-- the two retained neighbors is charged exactly once.
local function savings(ctx, plan, groups)
    local delta = {}
    local i = 1
    while i <= #plan.order do
        local n = plan.order[i]
        local id = n.task.questID
        if groups[id] and n.task.optional then
            local first, distance = i, 0
            repeat
                local point = plan.points[i]
                distance = distance + ctx.leg(plan.points[i - 1], point) + (point.penalty or 0)
                i = i + 1
                local nextNode = plan.order[i]
            until not nextNode or not nextNode.task.optional or nextNode.task.questID ~= id
            delta[id] = (delta[id] or 0) + distance + ctx.leg(plan.points[i - 1], plan.points[i])
                - ctx.leg(plan.points[first - 1], plan.points[i])
        else i = i + 1 end
    end
    return delta
end

local function admit(ctx, all, pinned, opts)
    local groups, count, allowance = {}, 0, 0
    local slots, worth = max(0, opts.slots or 0), opts.worth or 700
    local active = project(all, function(n) return not n.task.optional end)
    local previous = {}
    for _, key in ipairs(opts.previous or {}) do previous[key] = true end
    for _, n in ipairs(all) do
        if n.task.optional then
            local id = n.task.questID
            local group = groups[id] or { id = id, worth = min(125, worth), first = n }
            if not groups[id] then groups[id], count = group, count + 1 end
            if n.task.kind ~= "pickup" then group.worth = worth end
            if n.task.kind == "pickup" then group.first = n end
            if previous[n.key] then group.following = true end
        end
    end
    if slots == 0 then
        for _, n in ipairs(all) do
            local group = groups[n.task.questID]
            if group and group.first == n then explain(ctx, n, "quest log has no free slots") end
        end
        all, count = active, 0
    end
    pinFirst(all, pinned)
    local plan = chooseCamps(ctx, greedy(ctx, all))
    if count == 0 then
        reportMissing(ctx, all, plan.order)
        return plan
    end
    for _, group in pairs(groups) do allowance = allowance + group.worth end
    local base = chooseCamps(ctx, greedy(ctx, active))
    local pinnedID = pinned and pinned.reachable and pinned.task.optional and pinned.task.questID
    while count > 0 do
        local delta = savings(ctx, plan, groups)
        local worst, excess, worstPriority
        for id, group in pairs(groups) do
            local over = (delta[id] or 0) - group.worth
            -- When two pickups compete for the last slot, a tiny change in the
            -- player's position should not displace the one already displayed.
            local priority = over
            if count > slots and group.following then priority = priority - group.worth * 0.05 end
            if id ~= pinnedID and (not worst or priority > worstPriority or (priority == worstPriority and id > worst.id)) then
                worst, excess, worstPriority = group, over, priority
            end
        end
        if not worst then break end
        local full = count > slots
        if not full and excess <= 0 and plan.cost <= base.cost + allowance then break end
        explain(ctx, worst.first, full and "other pickups use the free quest slots" or "detour exceeds the pickup allowance")
        local removeID = worst.id
        groups[removeID], count, allowance = nil, count - 1, allowance - worst.worth
        local kept, points = {}, { [0] = ctx.origin }
        for i, n in ipairs(plan.order) do
            if not (n.task.optional and n.task.questID == removeID) then
                kept[#kept + 1] = n
                points[#kept] = plan.points[i]
            end
        end
        -- Reusing the retained camps makes a batch of capacity cuts cheap.
        -- The cut calculation is exact at those camps. Before a cost-based
        -- admission decision we always solve their candidate layers again.
        if count > slots and count % 8 ~= 0 then
            plan = {order=kept, points=points, cost=plan.cost - (delta[removeID] or 0)}
        else
            plan = chooseCamps(ctx, kept)
        end
    end
    -- The greedy order through a removed, distant pickup can make its old
    -- neighbors an unnecessarily long walk. Re-seed from the remaining stops.
    local reseeded = chooseCamps(ctx, greedy(ctx, plan.order))
    if #reseeded.order < #plan.order then
        reportMissing(ctx, plan.order, reseeded.order)
        return reseeded
    end
    return reseeded.cost < plan.cost and reseeded or plan
end

local function edited(order, first, last, after)
    local result = {}
    local function appendRun()
        for j = first, last do result[#result + 1] = order[j] end
    end
    if after == 0 then appendRun() end
    for i, n in ipairs(order) do
        if after == nil then
            result[i] = i >= first and i <= last and order[last + first - i] or n
        else
            if i < first or i > last then result[#result + 1] = n end
            if i == after then appendRun() end
        end
    end
    return result
end

local function positions(order)
    local pos = {}
    for i, n in ipairs(order) do pos[n] = i end
    return pos
end

local function legalMove(order, pos, first, last, after)
    if after >= first - 1 and after <= last then return false end
    local earlier = after < first
    local lo, hi
    if earlier then
        if order[last].stage > order[after + 1].stage then return false end
        lo, hi = after + 1, first - 1
    else
        if order[first].stage < order[after].stage then return false end
        lo, hi = last + 1, after
    end
    for j = first, last do
        for _, dep in ipairs(earlier and order[j].deps or order[j].children) do
            local p = pos[dep]
            if p and p >= lo and p <= hi then return false end
        end
    end
    return true
end

-- Price each neighboring order at its current camps using only the changed
-- edges. Solve the full candidate DP again for the winning move. Directed
-- walking distances may differ even on the same pair of cells.
local function improve(ctx, plan)
    local order, p, leg = plan.order, plan.points, ctx.leg
    local n, pos, back = #order, positions(order), { [1] = 0 }
    for i = 2, n do back[i] = back[i - 1] + leg(p[i], p[i - 1]) - leg(p[i - 1], p[i]) end
    local best, start, finish, insert = -0.001
    -- Quest logs with unusually many objectives keep their full itinerary.
    -- Restrict the local search neighborhood there to keep refinement bounded.
    local span = n <= 64 and n or 20
    for first = 1, n do
        for last = first, min(first + 2, n) do
            local cut = leg(p[first - 1], p[last + 1]) - leg(p[first - 1], p[first]) - leg(p[last], p[last + 1])
            for k = max(0, first - span), min(n, last + span) do
                if k < first - 1 or k > last then
                    local change = cut + leg(p[k], p[first]) + leg(p[last], p[k + 1]) - leg(p[k], p[k + 1])
                    if change < best and legalMove(order, pos, first, last, k) then
                        best, start, finish, insert = change, first, last, k
                    end
                end
            end
        end
        for last = first + 1, min(n, first + span) do
            if order[last].stage ~= order[first].stage then break end
            local legal = true
            for _, dep in ipairs(order[last].deps) do
                if pos[dep] and pos[dep] >= first then legal = false; break end
            end
            if not legal then break end
            local change = back[last] - back[first] + leg(p[first - 1], p[last]) - leg(p[first - 1], p[first])
                + leg(p[first], p[last + 1]) - leg(p[last], p[last + 1])
            if change < best then best, start, finish, insert = change, first, last, nil end
        end
        ctx.checkpoint()
    end
    if start then return chooseCamps(ctx, edited(order, start, finish, insert)) end
end

local function randomFor(order)
    local seed = 19
    for _, node in ipairs(order) do
        for i = 1, #node.key do seed = (seed * 33 + node.key:byte(i)) % 2147483647 end
    end
    return function(limit)
        seed = seed * 48271 % 2147483647
        return 1 + seed % limit
    end
end

local function shake(ctx, plan, random)
    local order, n = plan.order, #plan.order
    for _ = 1, 2 do
        local pos = positions(order)
        for _ = 1, 16 do
            local first = random(n)
            local last = min(n, first + random(3) - 1)
            local after = random(n + 1) - 1
            if legalMove(order, pos, first, last, after) then
                order = edited(order, first, last, after)
                break
            end
        end
    end
    return chooseCamps(ctx, order)
end

local function output(plan, why)
    local result = { stops = {}, cost = plan.cost, why = why }
    for i, n in ipairs(plan.order) do result.stops[i] = { task = n.task, point = plan.points[i] } end
    return result
end

function Planner.Plan(tasks, origin, opts)
    opts = opts or {}
    local ctx = context(origin, opts)
    local all, byKey = graph(ctx, tasks, opts.skips or {})
    local pinned = byKey[opts.forced]
    local ranks = {}
    for i, key in ipairs(opts.previous or {}) do ranks[key] = i end
    local quick = opts.progressOnly and next(ranks)
    if quick then
        local selected, ids, count = {}, {}, 0
        for _, n in ipairs(all) do
            if ranks[n.key] then
                selected[#selected + 1] = n
                if n.task.optional and not ids[n.task.questID] then ids[n.task.questID], count = true, count + 1 end
            elseif not n.task.optional then quick = false end
        end
        if quick and #selected == #opts.previous and count <= (opts.slots or 0) and (not pinned or ranks[pinned.key]) then
            pinFirst(selected, pinned)
            local order = greedy(ctx, selected, ranks)
            if #order == #selected then
                local result = output(chooseCamps(ctx, order), opts.previousWhy or ctx.why)
                if opts.publish then opts.publish(result) end
                return result
            end
        end
    end

    local best = admit(ctx, all, pinned, opts)
    pinFirst(best.order, pinned)
    local prior, otherSeed
    if next(ranks) then
        local overlap = false
        for _, n in ipairs(best.order) do if ranks[n.key] then overlap = true; break end end
        if overlap then prior = chooseCamps(ctx, greedy(ctx, best.order, ranks)) end
        if prior then
            local different = false
            for i, n in ipairs(best.order) do
                if prior.order[i] ~= n then different = true; break end
            end
            if different then
                if prior.cost < best.cost then best, otherSeed = prior, best
                else otherSeed = prior end
            end
        end
    end
    local function preferred()
        if prior and best.cost >= prior.cost * 0.95 then return prior end
        return best
    end
    local shown = preferred()
    if opts.publish then opts.publish(output(shown, ctx.why)) end
    local function consider(candidate)
        if candidate.cost >= best.cost then return end
        best = candidate
        local nextPlan = preferred()
        if opts.publish and nextPlan.cost < shown.cost * 0.99 then
            shown = nextPlan
            opts.publish(output(shown, ctx.why))
        end
    end
    local function descend(plan, limit)
        for _ = 1, limit do
            local nextPlan = improve(ctx, plan)
            if not nextPlan or nextPlan.cost >= plan.cost then break end
            plan = nextPlan
            consider(plan)
            ctx.tick()
        end
    end
    descend(best, 8)
    if otherSeed then descend(otherSeed, 4) end
    if #best.order >= 7 then
        local random = randomFor(best.order)
        for _ = 1, 3 do
            local alternate = shake(ctx, best, random)
            consider(alternate)
            descend(alternate, 4)
            ctx.tick()
        end
    end
    return output(preferred(), ctx.why)
end

end)
