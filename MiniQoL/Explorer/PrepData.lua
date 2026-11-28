local _, ns = ...
local E = ns.Explorer
local Prep = {}
E.Prep = Prep

function Prep.Provider()
    local modules = QuestieLoader and QuestieLoader._modules
    local db = modules and modules.QuestieDB
    if not (Questie and Questie.API and Questie.API.isReady and db and db.QuestPointers
        and db.QueryQuestSingle and db.QueryNPCSingle and db.QueryObjectSingle and db.QueryItemSingle
        and db.IsDoable and modules.ZoneDB and modules.QuestiePlayer) then return end
    return db, modules
end

-- Pick a representative spawn, preferring the destination when an NPC or item
-- can be found in several zones. Keep the giver/source name with its coordinates.
local function bestPlace(a, b)
    if a.here ~= b.here then return a.here and a or b end
    if (a.x ~= nil) ~= (b.x ~= nil) then return a.x and a or b end
    if a.area ~= b.area then return a.area < b.area and a or b end
    return (a.name or "") <= (b.name or "") and a or b
end

local function Prefer(a, b)
    if not a then return b end
    if not b then return a end
    local p = bestPlace(a, b)
    -- An item available from vendors worldwide isn't a reason to travel to
    -- every cloth quartermaster. Preserve alternatives as we combine sources.
    if p.here and not p.shared and (not a.here or not b.here or a.shared or b.shared) then
        return { area = p.area, mapID = p.mapID, here = true, shared = true, name = p.name, x = p.x, y = p.y }
    end
    return p
end

function Prep.ScanZone(area, tick)
    local db, modules = Prep.Provider()
    local zones, player = modules.ZoneDB, modules.QuestiePlayer
    local query = db.QueryQuestSingle
    local char = Questie.db.char
    local hidden = modules.QuestieCorrections and modules.QuestieCorrections.hiddenQuests or {}
    local maps, entityCache = {}, { {}, {}, {} }
    local targetKinds = { "monster", "object", "item" }
    local zoneMap = zones:GetUiMapIdByAreaId(area)
    local function areaMap(id)
        if maps[id] == nil then maps[id] = zones:GetUiMapIdByAreaId(id) or false end
        return maps[id]
    end
    local function spawns(list, name)
        local result
        for id, points in pairs(list or {}) do
            local mapID = areaMap(id)
            local p = { area = id, mapID = mapID or nil, name = name,
                here = id == area or (mapID and mapID == zoneMap) or zones:GetParentZoneId(id) == area }
            for _, xy in ipairs(points) do
                if type(xy[1]) == "number" and type(xy[2]) == "number"
                    and E.Located(mapID, xy[1] / 100, xy[2] / 100) then
                    p.x, p.y = xy[1] / 100, xy[2] / 100
                    break
                end
            end
            result = Prefer(result, p)
        end
        return result
    end
    local getters = { db.QueryNPCSingle, db.QueryObjectSingle, db.QueryItemSingle }
    local entitiesRead = 0
    local function entity(kind, id, visiting)
        if not id then return end
        local cache = entityCache[kind]
        if cache[id] ~= nil then return cache[id] or nil end
        entitiesRead = entitiesRead + 1
        if entitiesRead % 16 == 0 then tick() end
        local get = getters[kind]
        local place
        if kind ~= 3 then
            place = spawns(get(id, "spawns"), get(id, "name"))
        else
            visiting = visiting or {}
            if visiting[id] then return end
            visiting[id] = true
            for i, key in ipairs({ "npcDrops", "objectDrops", "itemDrops", "vendors" }) do
                for _, source in ipairs(get(id, key) or {}) do
                    place = Prefer(place, entity(i == 4 and 1 or i, source, visiting))
                end
            end
            visiting[id] = nil
        end
        cache[id] = place or false
        return place
    end
    local function participants(groups)
        local result
        for kind = 1, 3 do
            for _, id in ipairs(groups and groups[kind] or {}) do
                local friendly = kind ~= 1 or not db.IsFriendlyToPlayer
                    or db.IsFriendlyToPlayer(db.QueryNPCSingle(id, "friendlyToFaction"))
                local p = friendly and entity(kind, id) or nil
                if kind == 3 and p then
                    p = { area = p.area, mapID = p.mapID, here = p.here, shared = p.shared, x = p.x, y = p.y,
                        name = (db.QueryItemSingle(id, "name") or "Quest item") .. " from " .. (p.name or "item source") }
                end
                result = Prefer(result, p)
            end
        end
        return result
    end
    local function requirements(id)
        return not hidden[id] and not (char.hidden and char.hidden[id])
            and player.HasRequiredRace(query(id, "requiredRaces"))
            and player.HasRequiredClass(query(id, "requiredClasses"))
    end
    local function read(id)
        if not db.QuestPointers[id] or not requirements(id) then return end
        local q = { id = id, work = {}, start = participants(query(id, "startedBy")),
            finish = participants(query(id, "finishedBy")) }
        local function associate(p)
            if p and p.here then
                q.possible = q.possible or p
                if not p.shared then q.localWork = true end
            end
        end
        local function objective(name, p, kind, target)
            q.work[#q.work + 1] = { name = name or (p and p.name) or "Quest objective", place = p,
                kind = kind, target = target }
            associate(p)
        end
        local raw = query(id, "objectives") or {}
        local requestedItems = {}
        for kind = 1, 3 do
            for _, obj in ipairs(raw[kind] or {}) do
                if kind == 3 then requestedItems[obj[1]] = true end
                objective(obj[2] or getters[kind](obj[1], "name"), entity(kind, obj[1]),
                    targetKinds[kind], obj[1])
            end
        end
        local sourceItems = query(id, "requiredSourceItems")
        if sourceItems then
            local provided = query(id, "sourceItemId")
            for _, item in ipairs(sourceItems) do
                if item ~= provided and not requestedItems[item] then
                    objective(db.QueryItemSingle(item, "name"), entity(3, item), "sourceItem", item)
                end
            end
        end
        if raw[4] and raw[4][1] then objective("Reputation requirement") end
        for _, obj in ipairs(raw[5] or {}) do
            local p
            for _, npc in ipairs(obj[1] or {}) do p = Prefer(p, entity(1, npc)) end
            objective(obj[3], p or entity(1, obj[2]), "killcredit", obj[2])
        end
        for _, obj in ipairs(raw[6] or {}) do objective(obj[2] or "Use quest spell", nil, "spell", obj[1]) end
        local trigger = query(id, "triggerEnd")
        if trigger then objective(trigger[1], spawns(trigger[2])) end
        if #q.work == 0 and math.floor((query(id, "specialFlags") or 0) / 2) % 2 == 1 then
            local instructions = query(id, "objectivesText")
            objective(instructions and instructions[1] or "Complete the quest event")
        end
        for _, extra in ipairs(query(id, "extraObjectives") or {}) do
            local p = spawns(extra[1])
            for _, ref in ipairs(extra[5] or {}) do
                local kind = ({monster = 1, object = 2, item = 3})[ref[1]]
                if kind then p = Prefer(p, entity(kind, ref[2])) end
            end
            -- Extra map hints can be optional. Use them for discovery without
            -- inserting another required stop in the itinerary.
            associate(p)
        end
        local sort = query(id, "zoneOrSort")
        associate(q.start)
        associate(q.finish)
        q.relevant = q.localWork
            or (sort and sort > 0 and (sort == area or areaMap(sort) == zoneMap and zoneMap ~= nil))
        return q
    end
    local records = {}
    for id in pairs(db.QuestPointers) do
        local q = read(id)
        if q and (q.relevant or q.possible) then records[id] = q end
        tick()
    end
    -- Keep outside prerequisites as well, including every possible alternative.
    -- Mark visited before descending so malformed chains cannot recurse forever.
    local visited = {}
    local function include(id)
        if visited[id] then return end
        visited[id] = true
        local q = records[id] or read(id)
        if not q then return end
        records[id] = q
        q.name = query(id, "name") or ("Quest " .. id)
        q.level = query(id, "requiredLevel") or 0
        q.maxLevel = query(id, "requiredMaxLevel") or 0
        q.any = query(id, "preQuestSingle") or {}
        q.all = query(id, "preQuestGroup") or {}
        q.exclusive = query(id, "exclusiveTo") or {}
        q.parent = query(id, "parentQuest")
        q.enabler = query(id, "availableStartingWith")
        q.breadcrumb = query(id, "breadcrumbForQuestId")
        q.breadcrumbs = query(id, "breadcrumbs") or {}
        q.nextQuest = query(id, "nextQuestInChain")
        for _, list in ipairs({ q.any, q.all, q.breadcrumbs }) do
            for _, dep in ipairs(list) do include(math.abs(dep)) end
        end
        if q.parent and q.parent > 0 then include(q.parent) end
        if q.enabler and q.enabler > 0 then include(q.enabler) end
        tick()
    end
    local roots = {}
    for id in pairs(records) do roots[#roots + 1] = id end
    for _, id in ipairs(roots) do include(id) end
    return records
end

local function flag(fn, id)
    if not fn then return end
    local ok, value = pcall(fn, id)
    if ok and not (issecretvalue and issecretvalue(value)) then return value end
end

function Prep.Character()
    local db, modules = Prep.Provider()
    local log = C_QuestLog or {}
    local complete = Questie.db.char.complete
    local progress = {}
    return {
        level = modules.QuestiePlayer.GetPlayerLevel(),
        done = function(id) return complete[id] or flag(log.IsQuestFlaggedCompleted, id) == true end,
        active = function(id) return flag(log.IsOnQuest, id) == true end,
        ready = function(id) return flag(log.IsComplete, id) == true end,
        finishedObjective = function(id, obj)
            if obj.kind == "sourceItem" then
                local count = flag(C_Item and C_Item.GetItemCount or GetItemCount, obj.target)
                return type(count) == "number" and count > 0
            end
            if not obj.target or not db.GetQuest then return false end
            if not progress[id] then
                local quest = db.GetQuest(id)
                local live = flag(log.GetQuestObjectives, id) or {}
                local byTarget = {}
                for i, data in ipairs(quest and quest.ObjectiveData or {}) do
                    local target = data.Id or data.RootId
                    if target and live[i] then
                        local key = data.Type .. target
                        -- Two goals with the same target must both be finished.
                        if byTarget[key] ~= false then
                            local done = live[i].finished
                            byTarget[key] = not (issecretvalue and issecretvalue(done)) and done == true
                        end
                    end
                end
                progress[id] = byTarget
            end
            return progress[id][obj.kind .. obj.target]
        end,
        doable = function(id) return flag(db.IsDoable, id) == true end,
        title = function(id) return db.QueryQuestSingle(id, "name") or ("Quest " .. id) end,
        groupMet = function(id) return db:IsPreQuestGroupFulfilled({id}) end,
    }
end
