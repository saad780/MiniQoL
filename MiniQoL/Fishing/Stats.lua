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

-- This session's casts: how many landed something, and how many came up empty.
function Fishing:SessionCasts()
    local landed, empty = 0, 0
    for _, cast in ipairs(self.db.casts) do
        if cast.caught then landed = landed + 1 else empty = empty + 1 end
    end
    return landed, empty
end

local function FromItems(items, counts)
    local total, entries = 0, {}
    for itemID in pairs(counts or items) do
        local item = items[itemID] or {}
        local count = counts and counts[itemID] or item.count
        entries[#entries + 1] = { itemID = itemID, link = item.link, icon = item.icon,
            name = Fishing.LinkName(item.link), count = count, lastSeen = item.lastSeen }
        total = total + count
    end
    return total, Rank(entries, total)
end

function Fishing:AllTimeSummary()
    return FromItems(self.db.items)
end

-- Fishing loot uses ordinary item IDs. Some species have a different ID
-- for each trophy weight or bloated variant. IDs also work with a cold cache.
local fishSpecies = {
    ["Brilliant Smallfish"] = {6291, 6643},
    ["Longjaw Mud Snapper"] = {6289, 6292, 6294, 6295, 6645},
    ["Bristle Whisker Catfish"] = {6308, 6309, 6310, 6311, 6363, 6364, 6647},
    ["Slitherskin Mackerel"] = {6303, 6644},
    ["Rainbow Fin Albacore"] = {6361, 6646},
    ["Oily Blackmouth"] = {6358, 21162},
    ["Firefin Snapper"] = {6359, 21163},
    ["Rockscale Cod"] = {6362, 21164},
    ["Mithril Head Trout"] = {8365, 8366},
    ["Spotted Yellowtail"] = {4603, 13876, 13877, 13878, 13879, 13880},
    ["Redgill"] = {13758, 13881, 13882, 13883, 13884, 13885, 13886, 13887},
    ["Whitescale Salmon"] = {13889, 13891},
    ["Salmon (trophy)"] = {13901, 13902, 13903, 13904, 13905, 13906},
    ["Mightfish"] = {13754, 13893, 13914, 13915, 13916, 13917, 21243},
    ["Spotted Sunfish"] = {1467}, ["Sickly Looking Fish"] = {6299},
    ["Loch Frenzy"] = {6317}, ["Steelscale Crushfish"] = {6360},
    ["Oil Covered Fish"] = {6458}, ["Deviate Fish"] = {6522},
    ["Spinefin Halibut"] = {8959}, ["Darkshore Grouper"] = {12238},
    ["Stonescale Eel"] = {13422}, ["Summer Bass"] = {13756}, ["Lightning Eel"] = {13757},
    ["Nightfin Snapper"] = {13759}, ["Sunscale Salmon"] = {13760}, ["Plated Armorfish"] = {13890, 286152},
    ["Feralas Ahi"] = {16967}, ["Sar'theris Striker"] = {16968},
    ["Savage Coast Blue Sailfin"] = {16969}, ["Misty Reed Mahi Mahi"] = {16970},
    ["Brownell's Blue Striped Racer"] = {19803}, ["Pale Ghoulfish"] = {19804}, ["Keefer's Angelfish"] = {19805},
    ["Dezian Queenfish"] = {19806}, ["Speckled Tastyfish"] = {19807}, ["Rockhide Strongfish"] = {19808},
    ["Zulian Mudskunk"] = {19975}, ["Sagefish"] = {21071}, ["Greater Sagefish"] = {21153},
}

function Fishing:FishHistory(zoneName, allLoot)
    local zone = self.db.zones[zoneName]
    local counts = zoneName and (zone and zone.itemCounts or {})
    if allLoot then return FromItems(self.db.items, counts) end
    local entries, total = {}, 0
    for name, ids in pairs(fishSpecies) do
        local count = 0
        for _, id in ipairs(ids) do
            if counts then count = count + (counts[id] or 0)
            elseif self.db.items[id] then count = count + self.db.items[id].count end
        end
        if count > 0 then
            entries[#entries + 1] = { name = name, count = count }
            total = total + count
        end
    end
    return total, Rank(entries, total)
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
