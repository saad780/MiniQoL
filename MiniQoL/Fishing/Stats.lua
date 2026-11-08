local _, ns = ...
-- Turns the catch record into the numbers the panel shows.
local Fishing = ns.Fishing

local function Rank(entries, total)
    table.sort(entries, function(a, b)
        if a.count == b.count then return (a.name or "") < (b.name or "") end
        return a.count > b.count
    end)
    for _, entry in ipairs(entries) do
        entry.percent = total > 0 and entry.count / total * 100 or 0
    end
    return entries
end

-- This session: the total the shares are of, the entries, and the fish caught.
-- With misses included they appear as one { missed = true } entry.
function Fishing:SessionSummary(includeMissed)
    local caught, byItem, entries = 0, {}, {}
    for _, catch in ipairs(self.db.catches) do
        local entry = byItem[catch.itemID]
        if not entry then
            entry = { itemID = catch.itemID, link = catch.link, icon = catch.icon,
                name = self.LinkName(catch.link), count = 0 }
            byItem[catch.itemID] = entry
            entries[#entries + 1] = entry
        end
        entry.count = entry.count + (catch.quantity or 1)
        caught = caught + (catch.quantity or 1)
    end
    local total = caught
    if includeMissed then
        local missed = 0
        for _, cast in ipairs(self.db.casts) do
            if not cast.caught then missed = missed + 1 end
        end
        if missed > 0 then
            entries[#entries + 1] = { missed = true, name = "Nothing", count = missed }
            total = total + missed
        end
    end
    return total, Rank(entries, total), caught
end

local function FromItems(items)
    local total, entries = 0, {}
    for itemID, item in pairs(items) do
        entries[#entries + 1] = { itemID = itemID, link = item.link, icon = item.icon,
            name = Fishing.LinkName(item.link), count = item.count, lastSeen = item.lastSeen }
        total = total + item.count
    end
    return total, Rank(entries, total)
end

function Fishing:AllTimeSummary()
    return FromItems(self.db.items)
end

function Fishing:LureSummary()
    return FromItems(self.db.lureUsed)
end

function Fishing:AreaSummary(zone, subzone)
    return FromItems((self.db.areaItems[zone] or {})[subzone] or {})
end

-- Zones, most fish first, each with its areas.
function Fishing:ZoneSummary()
    local total, entries = 0, {}
    for name, zone in pairs(self.db.zones) do
        local areas = {}
        for subzone, count in pairs(zone.subzones) do
            areas[#areas + 1] = { name = subzone, count = count }
        end
        entries[#entries + 1] = { name = name, zone = name, count = zone.count, areas = Rank(areas, zone.count) }
        total = total + zone.count
    end
    return total, Rank(entries, total)
end

-- Casts caught, casts that gave nothing, and the average wait for a catch.
function Fishing:CastSummary()
    local caught, missed = self.db.caughtCasts, self.db.missedCasts
    local average = caught > 0 and self.db.catchSeconds / caught or nil
    local attempts = caught + missed
    return caught, missed, average, attempts > 0 and caught / attempts * 100 or 0
end

function Fishing:SessionLength()
    local start = self.db.sessionStart
    return start and (time() - start) or 0
end

function Fishing:SessionRate()
    local seconds = self:SessionLength()
    if seconds < 60 then return nil end
    local _, _, caught = self:SessionSummary(false)
    return caught / (seconds / 3600)
end

-- Casts per hour of the day, 1 to 24, and the busiest count for scaling.
function Fishing:HourSummary()
    local hours, peak = {}, 0
    for hour = 1, 24 do
        local count = self.db.hours[hour] or 0
        hours[hour] = count
        if count > peak then peak = count end
    end
    return hours, peak
end

function Fishing:TotalCaught()
    local total = select(1, self:AllTimeSummary())
    return total
end

function Fishing:FavouriteZone()
    local _, zones = self:ZoneSummary()
    return zones[1]
end
