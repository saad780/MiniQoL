local _, ns = ...
-- Every cast and everything the water gives back, kept for the session and
-- added to the all-time totals.
local Fishing = ns.Fishing

-- The cast in progress: { time, startedAt, stoppedAt }
local currentCast
local lootRecorded = false

local function Count(items, catch)
    local item = items[catch.itemID]
    if not item then
        item = { count = 0 }
        items[catch.itemID] = item
    end
    item.link = catch.link or item.link
    item.icon = catch.icon or item.icon
    item.count = item.count + (catch.quantity or 1)
    item.lastSeen = catch.time
    return item
end

function Fishing:RecordCatch(catch)
    local data = self.db
    table.insert(data.catches, catch)
    Count(data.items, catch)
    if catch.zone then
        local zone = data.zones[catch.zone]
        if not zone then
            zone = { count = 0, subzones = {} }
            data.zones[catch.zone] = zone
        end
        zone.count = zone.count + (catch.quantity or 1)
        -- Away from a named area the subzone is empty.
        if catch.subzone and catch.subzone ~= "" then
            zone.subzones[catch.subzone] = (zone.subzones[catch.subzone] or 0) + (catch.quantity or 1)
            local areas = data.areaItems[catch.zone] or {}
            data.areaItems[catch.zone] = areas
            areas[catch.subzone] = areas[catch.subzone] or {}
            Count(areas[catch.subzone], catch)
        end
    end
end

function Fishing:RecordCast(cast)
    local data = self.db
    table.insert(data.casts, cast)
    data.sessionStart = data.sessionStart or cast.time
    if cast.caught then
        data.caughtCasts = data.caughtCasts + 1
        data.catchSeconds = data.catchSeconds + (cast.seconds or 0)
    else
        data.missedCasts = data.missedCasts + 1
    end
    local hour = date("*t", cast.time).hour + 1
    data.hours[hour] = (data.hours[hour] or 0) + 1
end

function Fishing:RecordLureUsed(itemID, link, icon)
    Count(self.db.lureUsed, { itemID = itemID, link = link, icon = icon, quantity = 1, time = time() })
end

local function FinishCast(caught)
    if not currentCast then return end
    Fishing:RecordCast({
        time = currentCast.time,
        ended = time(),
        caught = caught,
        seconds = caught and (GetTime() - currentCast.startedAt) or nil,
    })
    currentCast = nil
end

local function StartCast()
    if currentCast then
        local stoppedAt = currentCast.stoppedAt
        if stoppedAt and GetTime() - stoppedAt < Fishing.RECAST_WINDOW then
            -- Recasting straight away is not a miss; forget the old cast.
            currentCast = nil
        else
            FinishCast(false)
            Fishing:Fire("CATCHES_CHANGED")
        end
    end
    currentCast = { time = time(), startedAt = GetTime() }
end

local function StopCast()
    local cast = currentCast
    if not cast then return end
    cast.stoppedAt = GetTime()
    -- Clicking the bobber ends the cast just before the loot opens.
    C_Timer.After(Fishing.LOOT_GRACE, function()
        if currentCast == cast then
            FinishCast(false)
            Fishing:Fire("CATCHES_CHANGED")
        end
    end)
end

local function RecordLoot()
    if lootRecorded or not IsFishingLoot or not IsFishingLoot() then return end
    lootRecorded = true
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot) -- money has no link
        if link then
            local icon, _, quantity = GetLootSlotInfo(slot)
            Fishing:RecordCatch({
                itemID = tonumber(link:match("item:(%d+)")),
                link = link,
                icon = icon,
                quantity = quantity or 1,
                time = time(),
                zone = GetRealZoneText(),
                subzone = GetSubZoneText(),
            })
        end
    end
    FinishCast(true)
    Fishing:Fire("CATCHES_CHANGED")
end

-- The newest catches and misses together, newest first.
function Fishing:RecentCatches(limit)
    local catches, casts = self.db.catches, self.db.casts
    local c, m, recent = #catches, #casts, {}
    while #recent < limit do
        while m > 0 and casts[m].caught do m = m - 1 end
        local catch, miss = catches[c], casts[m]
        if not catch and not miss then break end
        local missTime = miss and (miss.ended or miss.time)
        if miss and (not catch or missTime > catch.time) then
            table.insert(recent, { missed = true, time = missTime })
            m = m - 1
        else
            table.insert(recent, catch)
            c = c - 1
        end
    end
    return recent
end

-- Forget this session's casts and catches; the all-time totals stay.
function Fishing:ResetSession()
    self.db.catches, self.db.casts, self.db.sessionStart = {}, {}, nil
    self.db.sessions = self.db.sessions + 1
    self:Fire("CATCHES_CHANGED")
end

-- Forget everything caught, ever. Settings and the gear set are kept.
function Fishing:ResetAll()
    local data = self.db
    data.items, data.zones, data.areaItems, data.lureUsed, data.hours = {}, {}, {}, {}, {}
    data.caughtCasts, data.missedCasts, data.catchSeconds = 0, 0, 0
    data.sessions = 1
    data.catches, data.casts, data.sessionStart = {}, {}, nil
    self:Fire("CATCHES_CHANGED")
end

function Fishing:IsCasting()
    return currentCast ~= nil
end

function Fishing:SetupCatches()
    local events = CreateFrame("Frame")
    -- Fast-loot addons take everything on LOOT_READY, before LOOT_OPENED.
    events:RegisterEvent("LOOT_READY")
    events:RegisterEvent("LOOT_OPENED")
    events:RegisterEvent("LOOT_CLOSED")
    events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    events:SetScript("OnEvent", function(_, event, _, _, spellID)
        if event == "LOOT_READY" or event == "LOOT_OPENED" then
            RecordLoot()
        elseif event == "LOOT_CLOSED" then
            lootRecorded = false
        elseif self:IsFishingSpell(spellID) then
            if event == "UNIT_SPELLCAST_CHANNEL_START" then StartCast() else StopCast() end
            self:Fire("CASTING_CHANGED")
        end
    end)
end
