local _, ns = ...
local E = ns.Explorer
local sourceOrder = { vendor = 1, quest = 2, drop = 3, rare = 4, chest = 5, dungeon = 6 }

local npcPack, questRecords
local function QuestRecord(id)
    local pack = E:Data("npcs")
    if not pack then return end
    if pack ~= npcPack then
        npcPack, questRecords = pack, {}
        for _, npcs in pairs(pack.maps) do
            for _, npc in ipairs(npcs) do
                if npc[8] then
                    for _, quest in ipairs(npc[8]) do questRecords[quest[1]] = quest end
                end
            end
        end
    end
    return questRecords[id]
end

local function QuestFlag(fn, id)
    if not fn or not id then return end
    local ok, value = pcall(fn, id)
    if ok and (not Gearwise.Readable or Gearwise.Readable(value)) and type(value) == "boolean" then return value end
end

local originalRaces = { Alliance = { 1, 3, 4, 7 }, Horde = { 2, 5, 6, 8 } }
local function HasBit(mask, id)
    return math.floor(mask / 2 ^ (id - 1)) % 2 == 1
end

local function Allows(mask, id, faction)
    if not mask or mask == 0 then return true end
    if not id or id < 1 then return nil end
    if HasBit(mask, id) then return true end
    -- Older faction-wide masks also cover Forever races added later.
    local races = originalRaces[faction]
    if not races then return false end
    for _, race in ipairs(races) do if not HasBit(mask, race) then return false end end
    return true
end

local function QuestNote(source, player, completed)
    if source[1] ~= "quest" then return true end
    local id, level = source[8], player.level
    local log = C_QuestLog or {}
    if QuestFlag(log.IsOnQuest, id) then return true end
    local done = id and completed(id)
    if done and not QuestFlag(log.IsRepeatableQuest, id) then return false end
    local quest = id and QuestRecord(id)
    local classOK = quest and Allows(quest[6], player.classID)
    local raceOK = quest and Allows(quest[9], player.raceID, player.faction)
    if classOK == false or raceOK == false or (quest and not E.OwnFaction(quest[5], player.faction)) then return false end
    local required = source[9] or (quest and quest[3]) or 1
    if required > level + 3 then return false end
    if required > level then return true, "Quest requires level " .. required end
    local any = source[10] or (quest and quest[7]) or {}
    local unlocked, uncertain = #any == 0, false
    for _, prerequisite in ipairs(any) do
        local flag = completed(prerequisite)
        if flag then unlocked = true; break end
        if flag == nil then uncertain = true end
    end
    if not unlocked and not uncertain then return true, "Earlier quest required" end
    uncertain = not unlocked
    for _, prerequisite in ipairs(source[11] or (quest and quest[8]) or {}) do
        local flag = completed(math.abs(prerequisite))
        if flag == false then return true, "Earlier quest required" end
        if flag == nil then uncertain = true end
    end
    if uncertain or done == nil or classOK == nil or raceOK == nil then return true, "Check quest eligibility" end
    local questLevel = source[6] or (quest and quest[4]) or 0
    if questLevel > level + 4 then return true, "Level " .. questLevel .. " quest" end
    return true
end

local function RegionalCandidate(item, level)
    local required, itemLevel = item[2] or 0, item[3] or 0
    if required <= 1 and itemLevel == 0 then
        for _, source in ipairs(item[4]) do
            local questLevel = source[1] == "quest" and source[6]
            if questLevel and questLevel >= level - 6 and questLevel <= level + 4 then return true end
        end
    end
    if required <= 1 then return itemLevel >= level - 6 and itemLevel <= level + 10 end
    return required >= level - 6 and required <= level
end

-- One level's static item IDs, grouped by source zone. Quest availability,
-- faction, exact position and equipment are evaluated anew for each scan.
local levelIndex
local function IndexForLevel(items, level)
    if levelIndex and levelIndex.items == items and levelIndex.level == level then return levelIndex end
    local index = { items = items, level = level, all = {}, zones = {} }
    for id, item in pairs(items) do
        if (item[2] or 0) <= level then
            if RegionalCandidate(item, level) then index.all[#index.all + 1] = id end
            for _, source in ipairs(item[4]) do
                if sourceOrder[source[1]] and E.Located(source[2], source[3], source[4]) then
                    local zone = E.Zone(source[2])
                    local ids = index.zones[zone]
                    if not ids then ids = {}; index.zones[zone] = ids end
                    if ids[#ids] ~= id then ids[#ids + 1] = id end
                end
            end
        end
    end
    levelIndex = index
    return index
end

local function BetterSource(tier, note, order, distance, best)
    if not best then return true end
    if (note ~= nil) ~= (best.note ~= nil) then return note == nil end
    if tier ~= best.tier then return tier < best.tier end
    if order ~= best.order then return order < best.order end
    return distance < best.distance
end

local function BestSource(item, id, player, completed, localOnly)
    local best
    for _, source in ipairs(item[4]) do
        local mapID, x, y = source[2], source[3], source[4]
        local order = sourceOrder[source[1]]
        if order and E.OwnFaction(source[7], player.faction) and E.Located(mapID, x, y)
            and (E.Zone(mapID) == player.zone) == localOnly then
            local available, note = QuestNote(source, player, completed)
            if available then
                local tier, distance = E.Distance(player, mapID, x, y)
                if BetterSource(tier, note, order, distance, best) then
                    best = best or { itemID = id, name = item[1] }
                    best.tier, best.distance, best.note, best.order = tier, distance, note, order
                    best.mapID, best.x, best.y, best.source = mapID, x, y, source
                end
            end
        end
    end
    return best
end

local function BetterUpgrade(a, b)
    if (a.note ~= nil) ~= (b.note ~= nil) then return a.note == nil end
    if a.tier ~= b.tier then return a.tier < b.tier end
    if a.delta ~= b.delta then return a.delta > b.delta end
    if a.order ~= b.order then return a.order < b.order end
    if a.distance ~= b.distance then return a.distance < b.distance end
    return a.itemID < b.itemID
end

local sharedSlot = { [12] = 11, [14] = 13 }
local function Score(candidate, compare)
    local result = compare:Get("item:" .. candidate.itemID)
    local planOnly = result.status ~= "upgrade" and candidate.tier == 0 and result.setPlan
    local breakEven = result.status ~= "upgrade" and candidate.tier == 0 and result.breakEven
    if result.status ~= "upgrade" and not planOnly and not breakEven then return nil, result.status == "pending" end
    candidate.slot = sharedSlot[result.slot] or result.slot
    candidate.empty, candidate.percent, candidate.delta = result.empty, result.percent, result.delta
    candidate.effects = result.effects
    candidate.effectNotes, candidate.planOnly = result.effectNotes, planOnly
    candidate.breakEven = breakEven
    candidate.estimatedProc = result.estimatedProc
    candidate.icon = result.item.icon
    candidate.detail = E.SourceLabel(candidate.source)
    return candidate
end

function E:CancelUpgrades()
    self.scan = nil
end

-- Bound the work of a frame even when Gearwise needs several tooltip reads.
local function Batches(scan, list, visit, done, prioritize)
    local index = 1
    local function step()
        if E.scan ~= scan then return end
        if scan.visible and not scan.visible() then E:CancelUpgrades(); return end
        if InCombatLockdown() then E:CancelUpgrades(); scan.finished(); return end
        if prioritize and prioritize(step) then return end
        local start = debugprofilestop and debugprofilestop()
        local last, scored = math.min(index + 95, #list), 0
        while index <= last and scored < 18 do
            if visit(list[index]) ~= false then scored = scored + 1 end
            index = index + 1
            if start and debugprofilestop() - start >= 2 then break end
        end
        if index <= #list then C_Timer.After(0, step) else done() end
    end
    C_Timer.After(0, step)
end

function E:StartUpgrades(slot, finished, visible)
    local items = self:Data("gear").items
    local player = self.PlayerPosition()
    player.level, player.faction = UnitLevel("player"), UnitFactionGroup("player")
    player.classID = select(3, UnitClass("player"))
    player.raceID = UnitRace and select(3, UnitRace("player"))
    local index = IndexForLevel(items, player.level)
    local localResults, regionalBySlot, hasLocalSource, quests = {}, {}, {}, {}
    local readyLocal = 0
    local scan = { mapID = player.mapID, slot = slot, profile = Gearwise.profile, pending = {}, ready = {}, equipped = {},
        visible = visible, finished = finished, running = true, setOptions = {}, procOptions = {} }
    self.scan = scan
    if GetInventoryItemID then
        for inventorySlot = 1, 19 do
            local id = GetInventoryItemID("player", inventorySlot)
            if id then scan.equipped[id] = true end
        end
    end

    local function completed(id)
        if quests[id] == nil then quests[id] = QuestFlag(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, id) end
        return quests[id]
    end
    local function score(candidate)
        local upgrade, waiting = Score(candidate, Gearwise.Compare)
        scan.pending[candidate.itemID] = waiting and candidate or nil
        if not upgrade or (slot and upgrade.slot ~= slot) then return end
        if upgrade.planOnly then
            scan.setOptions[#scan.setOptions + 1] = upgrade
        elseif upgrade.breakEven then
            scan.procOptions[#scan.procOptions + 1] = upgrade
        elseif upgrade.tier == 0 then
            localResults[#localResults + 1] = upgrade
            if not upgrade.note then readyLocal = readyLocal + 1 end
        else
            local prior = regionalBySlot[upgrade.slot]
            if not prior or BetterUpgrade(upgrade, prior) then regionalBySlot[upgrade.slot] = upgrade end
        end
    end
    local function publish()
        table.sort(localResults, BetterUpgrade)
        table.sort(scan.setOptions, BetterUpgrade)
        table.sort(scan.procOptions, function(a, b)
            if a.breakEven ~= b.breakEven then return a.breakEven < b.breakEven end
            return BetterUpgrade(a, b)
        end)
        scan.nearby, scan.elsewhere = localResults, {}
        if readyLocal < 6 then
            for _, result in pairs(regionalBySlot) do scan.elsewhere[#scan.elsewhere + 1] = result end
            table.sort(scan.elsewhere, BetterUpgrade)
        else
            for id, candidate in pairs(scan.pending) do
                if candidate.tier ~= 0 then scan.pending[id], scan.ready[id] = nil, nil end
            end
        end
        scan.running, scan.checkingElsewhere = false, false
        finished(scan)
    end
    local function takeReady()
        local list = {}
        for id in pairs(scan.ready) do
            if scan.pending[id] then list[#list + 1] = scan.pending[id] end
        end
        scan.ready = {}
        return list
    end
    -- Item data can arrive while another batch is still being scored. Keep
    -- those arrivals and revisit only comparisons whose inputs just loaded.
    function scan:retry()
        if self.running or self.retryQueued or not next(self.ready) then return end
        self.retryQueued = true
        C_Timer.After(0.2, function()
            self.retryQueued = false
            if E.scan ~= self or (visible and not visible()) then return end
            local list = takeReady()
            if #list == 0 then return end
            self.running = true
            Batches(self, list, score, publish)
        end)
    end

    local function inspect(id, localOnly)
        if hasLocalSource[id] then return false end
        local compare = Gearwise.Compare
        if compare.MayFit and not compare:MayFit(id, slot) then return false end
        local candidate = BestSource(items[id], id, player, completed, localOnly)
        if candidate then
            if localOnly then hasLocalSource[id] = true end
            if localOnly and candidate.note then
                local other = BestSource(items[id], id, player, completed, false)
                if other and not other.note then candidate = other end
            end
            score(candidate)
        end
        return candidate ~= nil
    end
    -- A cold cache can make a well-stocked zone look empty. Revisit arrivals
    -- before spending another frame on distant sources.
    local function prioritizeArrivals(resume)
        if readyLocal >= 6 then publish(); return true end
        if not next(scan.ready) then return false end
        Batches(scan, takeReady(), score, function() C_Timer.After(0, resume) end)
        return true
    end
    Batches(scan, index.zones[player.zone] or {}, function(id) return inspect(id, true) end, function()
        if readyLocal >= 6 then publish(); return end
        table.sort(localResults, BetterUpgrade)
        scan.nearby, scan.elsewhere, scan.checkingElsewhere = localResults, {}, true
        finished(scan)
        Batches(scan, index.all, function(id) return inspect(id, false) end, publish, prioritizeArrivals)
    end)
end

function E:UpgradeItemArrived(id)
    local scan = self.scan
    if not scan or not next(scan.pending) then return end
    if scan.equipped[id] then
        for waiting in pairs(scan.pending) do scan.ready[waiting] = true end
    elseif scan.pending[id] then
        scan.ready[id] = true
    else
        return
    end
    scan:retry()
end
