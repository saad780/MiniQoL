local _, ns = ...
local E = ns.Explorer
local sourceOrder = { vendor = 1, quest = 2, drop = 3, rare = 4, chest = 5, dungeon = 6 }

local function QuestNote(source, level, completed)
    if source[1] ~= "quest" then return true end
    local id, required = source[8], source[9] or 1
    if (id and completed(id)) or required > level + 3 or (source[6] or 0) > level + 4 then return false end
    if required > level then return true, "Quest requires level " .. required end
    local any = source[10] or {}
    local unlocked = #any == 0
    for _, prerequisite in ipairs(any) do
        if completed(prerequisite) then unlocked = true; break end
    end
    if not unlocked then return true, "Earlier quest required" end
    for _, prerequisite in ipairs(source[11] or {}) do
        if not completed(prerequisite) then return true, "Earlier quest required" end
    end
    return true
end

local function BetterSource(a, b)
    if a.tier ~= b.tier then return a.tier < b.tier end
    if (a.note ~= nil) ~= (b.note ~= nil) then return a.note == nil end
    if a.order ~= b.order then return a.order < b.order end
    return a.distance < b.distance
end

local function Fits(item, level)
    local required, itemLevel = item[2] or 0, item[3] or 0
    if required <= 1 then return itemLevel >= level - 6 and itemLevel <= level + 10 end
    return required >= level - 6 and required <= level
end

function E:UpgradeSources(items, player, level, faction)
    local nearby, elsewhere, quests = {}, {}, {}
    local function completed(id)
        if quests[id] == nil then quests[id] = not not C_QuestLog.IsQuestFlaggedCompleted(id) end
        return quests[id]
    end
    for id, item in pairs(items) do
        if Fits(item, level) then
            local best
            for _, source in ipairs(item[4]) do
                local kind, mapID, x, y = unpack(source, 1, 4)
                if sourceOrder[kind] and self.OwnFaction(source[7], faction) and self.Located(mapID, x, y) then
                    local available, note = QuestNote(source, level, completed)
                    if available then
                        local tier, distance = self.Distance(player, mapID, x, y)
                        local candidate = { itemID = id, name = item[1], mapID = mapID, x = x, y = y,
                            tier = tier, distance = distance, note = note, order = sourceOrder[kind], source = source }
                        if not best or BetterSource(candidate, best) then best = candidate end
                    end
                end
            end
            if best then
                local list = best.tier == 0 and nearby or elsewhere
                list[#list + 1] = best
            end
        end
    end
    return nearby, elsewhere
end

local function BetterUpgrade(a, b)
    if (a.note ~= nil) ~= (b.note ~= nil) then return a.note == nil end
    if a.tier ~= b.tier then return a.tier < b.tier end
    local gainA, gainB = a.percent or 0, b.percent or 0
    if gainA ~= gainB then return gainA > gainB end
    if a.delta ~= b.delta then return a.delta > b.delta end
    if a.order ~= b.order then return a.order < b.order end
    if a.distance ~= b.distance then return a.distance < b.distance end
    return a.itemID < b.itemID
end

local function BestPerSlot(results)
    local best, picked = {}, {}
    for _, result in ipairs(results) do
        if not picked[result.slot] then
            best[#best + 1] = result
            picked[result.slot] = true
        end
    end
    return best
end

local function Score(candidate, compare)
    local result = compare:Get("item:" .. candidate.itemID)
    if result.status ~= "upgrade" then return nil, result.status == "pending" end
    candidate.slot = ({ [12] = 11, [14] = 13 })[result.slot] or result.slot
    candidate.empty, candidate.percent, candidate.delta = result.empty, result.percent, result.delta
    candidate.icon = result.item.icon
    candidate.detail = E.SourceLabel(candidate.source)
    return candidate
end

function E:CancelUpgrades()
    self.scan = nil
end

function E:StartUpgrades(slot, finished)
    local pack = self:Data("gear")
    local player = self.PlayerPosition()
    local level = UnitLevel("player")
    local candidates, alternatives = self:UpgradeSources(pack.items, player, level, UnitFactionGroup("player"))
    local results, outside, pending = {}, {}, {}
    local scan = { mapID = player.mapID, slot = slot, pending = pending }
    self.scan = scan
    local index, list, output = 1, candidates, results
    local function nextBatch()
        if self.scan ~= scan then return end
        if InCombatLockdown() then self.scan = nil; finished(); return end
        local last = math.min(index + 17, #list)
        for i = index, last do
            local upgrade, waiting = Score(list[i], Gearwise.Compare)
            if upgrade then output[#output + 1] = upgrade end
            if waiting then pending[list[i].itemID] = true end
        end
        index = last + 1
        if index <= #list then C_Timer.After(0, nextBatch); return end
        table.sort(output, BetterUpgrade)
        local localCount = 0
        for _, result in ipairs(results) do
            if not slot or result.slot == slot then localCount = localCount + 1 end
        end
        if list == candidates and localCount < 6 then
            list, output, index = alternatives, outside, 1
            C_Timer.After(0, nextBatch)
            return
        end
        scan.nearby, scan.elsewhere = results, BestPerSlot(outside)
        finished(scan)
    end
    C_Timer.After(0, nextBatch)
end
