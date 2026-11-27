local _, ns = ...
local Prep = ns.Explorer.Prep

-- Build a forecast in private tables. Only actual character state can remove a
-- quest from the next plan. Picking up and handing in are separate route stops.
function Prep.Route(records, character, origin, tick)
    local states, needed, route, waiting, optional = {}, {}, {}, {}, {}
    local function state(id)
        if not states[id] then
            local active = character.active(id)
            states[id] = { accepted = active, active = active, done = not active and character.done(id) }
        end
        return states[id]
    end
    local function used(id)
        return id and id > 0 and (state(id).done or state(id).active)
    end
    local function excluded(q)
        if used(q.breadcrumb) or used(q.nextQuest) then return true end
        if q.maxLevel > 0 and q.maxLevel < character.level then return true end
        for _, id in ipairs(q.exclusive) do if used(id) then return true end end
    end
    local function add(id)
        local q, s = records[id], state(id)
        if not q or s.done or needed[id] or (not s.active and excluded(q)) then return end
        needed[id] = true
        s.requires = {}
        if not s.active then
            local function requireQuest(dep, accept, optionalIntro)
                s.requires[#s.requires + 1] = { id = dep, accept = accept, optionalIntro = optionalIntro }
                add(dep)
            end
            local anyMet = false
            local choice, best
            for _, dep in ipairs(q.any) do
                if state(dep).done then anyMet = true; break end
                local alt = records[dep]
                if alt and not excluded(alt) then
                    local score = state(dep).active and 0 or character.doable(dep) and alt.level <= character.level and 1
                        or alt.relevant and 2 or 3
                    if not best or score < best or (score == best and dep < choice) then choice, best = dep, score end
                end
            end
            if #q.any > 0 then
                if not anyMet then requireQuest(choice or q.any[1]) end
            else
                for _, dep in ipairs(q.all) do
                    if not (state(math.abs(dep)).done or character.groupMet(dep)) then requireQuest(math.abs(dep)) end
                end
            end
            if q.parent and q.parent > 0 and not state(q.parent).active then
                if state(q.parent).done then s.block = "Parent quest already ended"
                else requireQuest(q.parent, true) end
            end
            if q.enabler and q.enabler > 0 and not used(q.enabler) then requireQuest(q.enabler, true) end
            -- A breadcrumb is optional, but accepting its destination first
            -- can make it disappear. Route feasible introductions first.
            for _, dep in ipairs(q.breadcrumbs) do
                local intro = records[dep]
                if intro and not state(dep).done and not excluded(intro) and intro.level <= character.level
                    and (state(dep).active or character.doable(dep)) and intro.finish and (state(dep).active or intro.start) then
                    requireQuest(dep, false, true)
                end
            end
            if q.level > character.level then s.block = "Requires level " .. q.level end
            if #s.requires == 0 and not character.doable(id) then
                s.block = s.block or "Questie reports other requirements"
            end
        end
        s.remaining = {}
        -- Replanning while questing must not turn a newly earned remote
        -- hand-in into a reason to leave before finishing other local work.
        if s.active and origin and origin.here then
            s.visitedZone = q.start and q.start.here
            for _, obj in ipairs(q.work) do
                if obj.place and obj.place.here then s.visitedZone = true; break end
            end
        end
        if not (s.active and character.ready(id)) then
            for i, obj in ipairs(q.work) do
                if not (s.active and character.finishedObjective and character.finishedObjective(id, obj)) then
                    s.remaining[i] = true
                end
            end
        end
    end
    for id, q in pairs(records) do
        if q.relevant or (q.possible and state(id).active) then add(id) end
    end
    for id in pairs(needed) do
        local parent = records[id].parent
        if parent and needed[parent] then
            local s = states[parent]
            s.holdFor = s.holdFor or {}
            s.holdFor[#s.holdFor + 1] = id
        end
    end

    local skipUnavailableIntros = false
    local function dependencyMissing(s)
        for _, req in ipairs(s.requires) do
            local pre = state(req.id)
            if not pre.done and not (req.accept and pre.accepted)
                and not (req.optionalIntro and skipUnavailableIntros and not pre.active) then return req end
        end
    end
    local prep, last, onExcursion = true, origin, false
    -- Once inside, exhaust reachable local stops before taking another trip.
    -- At the same hub, accept other work before moving to an objective.
    local function distance(p)
        if not (last and p.mapID and last.mapID == p.mapID) then return 3 end
        if not (last.x and p.x) then return 2 end
        return (last.x - p.x)^2 + (last.y - p.y)^2
    end
    while true do
        local best, bestTier, bestDistance
        local function offer(q, kind, index, p, label)
            if not p or (prep and (p.here or states[q.id].visitedZone)) then return end
            local tier = (prep or p.here) and 1 or 2
            if onExcursion and not p.here and (p.area == last.area or p.mapID and p.mapID == last.mapID) then
                tier = 0
            end
            local d = distance(p)
            if not best or tier < bestTier or (tier == bestTier and
                (d < bestDistance or (d == bestDistance and
                (kind < best.kind or (kind == best.kind and
                (q.id < best.id or (q.id == best.id and index < best.index))))))) then
                best = { id = q.id, quest = q.name, kind = kind, index = index, place = p, label = label }
                bestTier, bestDistance = tier, d
            end
        end
        for id in pairs(needed) do
            local s, q = states[id], records[id]
            if not s.done and not s.block then
                if not s.accepted then
                    if not dependencyMissing(s) then offer(q, 1, 0, q.start, "Pick up") end
                elseif next(s.remaining) then
                    for i in pairs(s.remaining) do
                        offer(q, 2, i, q.work[i].place, q.work[i].name)
                    end
                else
                    -- Keep the parent active while a child still needs its pickup.
                    local pendingChild = false
                    if s.holdFor then
                        for _, child in ipairs(s.holdFor) do
                            if not states[child].accepted and not states[child].block then pendingChild = true end
                        end
                    end
                    if not pendingChild then offer(q, 3, 0, q.finish, "Turn in") end
                end
            end
        end
        if best then
            local s = states[best.id]
            best.phase = prep and "Before traveling" or best.place.here and "In the zone" or "Outside the zone"
            if best.kind == 1 then
                s.accepted = true
                if #s.requires > 0 then
                    local names = {}
                    for _, req in ipairs(s.requires) do
                        if state(req.id).done or not req.optionalIntro then
                            names[#names + 1] = (req.accept and "accepting " or "turning in ") .. character.title(req.id)
                        end
                    end
                    if #names > 0 then best.after = "After " .. table.concat(names, " and ") end
                end
                for _, dep in ipairs(records[best.id].exclusive) do
                    if needed[dep] and not states[dep].accepted then states[dep].block = "Alternative to " .. best.quest end
                end
            elseif best.kind == 2 then s.remaining[best.index] = nil
            else s.done = true end
            route[#route + 1] = best
            last = best.place
            onExcursion = not prep and not last.here
        elseif prep then
            prep = false
        elseif not skipUnavailableIntros then
            skipUnavailableIntros = true
        else
            break
        end
        tick()
    end
    for id in pairs(needed) do
        local s, q = states[id], records[id]
        if not s.done then
            local req = dependencyMissing(s)
            local reason = s.block
            if not reason and req then
                reason = (req.accept and "Requires accepting " or "Requires turning in ") .. character.title(req.id)
            end
            if not reason then
                if not s.accepted then reason = "Pickup location unknown"
                elseif next(s.remaining) then
                    reason = "Locate " .. q.work[next(s.remaining)].name
                elseif q.finish then reason = "Waiting on a child quest"
                else reason = "Turn-in location unknown" end
            end
            waiting[#waiting + 1] = { id = id, quest = q.name, label = reason, place = not s.accepted and q.start or nil }
        end
    end
    table.sort(waiting, function(a, b) return a.quest < b.quest or a.quest == b.quest and a.id < b.id end)
    for id, q in pairs(records) do
        if q.possible and not needed[id] and not state(id).done and not excluded(q) then
            optional[#optional + 1] = { id = id, quest = q.name, place = q.possible, label = "Also possible here" }
        end
    end
    table.sort(optional, function(a, b) return a.quest < b.quest or a.quest == b.quest and a.id < b.id end)
    return route, waiting, optional
end
