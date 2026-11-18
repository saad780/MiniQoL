-- Built-in locations and the ones the player records, at Orgrimmar's bank and
-- auction house, with the real data and the real coordinates. One auctioneer
-- spoken to used to take the two beside him off the map, and three bankers
-- seen from one spot used to stand in for a row of three as a single pile.
local root = ...

local explored, questing = true, false
local ns = { db = { hidden = {}, settings = { cats = {}, showApproximate = true } }, settings = { useSeedData = true } }
ns.QuestAvailability = { HasAvailableQuest = function() return questing end }
ns.defaults = { cats = {} }
function ns:NewModule(name) self[name] = { name = name }; return self[name] end
function ns:GetSetting(key) return self.settings[key] end
local listeners = {}
function ns:On(message, fn)
    listeners[message] = listeners[message] or {}
    table.insert(listeners[message], fn)
end
function ns:Fire(message, ...)
    for _, fn in ipairs(listeners[message] or {}) do fn(...) end
end
function ns.Debug() end
function ns.Distance(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end
-- Orgrimmar as the client lays it out: north and west in yards.
local ORGRIMMAR = { top = 2273.33, left = -3680.0, width = 1403.33, height = 935.83 }
function ns.MapToWorld(mapID, x, y)
    if mapID ~= 1454 then return nil end
    return 1, ORGRIMMAR.top - y * ORGRIMMAR.height, ORGRIMMAR.left - x * ORGRIMMAR.width
end
ns.Exploration = { IsExplored = function() return explored end }

local records = {}
ns.Database = { Query = function(_, cont, minX, maxX, minY, maxY, fn)
    for _, rec in ipairs(records) do
        if rec.c == cont and rec.x >= minX and rec.x <= maxX and rec.y >= minY and rec.y <= maxY then fn(rec) end
    end
end }
function wipe(t) for key in pairs(t) do t[key] = nil end return t end
MiniQoLRuntime = { Execute = function(_, _, fn) return fn("Wayfinder", ns) end }
assert(loadfile(root .. "/Modules/Wayfinder/Categories.lua"))("Wayfinder", ns)
assert(loadfile(root .. "/Modules/Wayfinder/Data/Seed.lua"))("Wayfinder", ns)
assert(loadfile(root .. "/Modules/Wayfinder/Seeds.lua"))("Wayfinder", ns)
local Seeds, Categories = ns.Seeds, ns.Categories
Seeds:OnLogin()

local function equal(actual, expected, label)
    assert(actual == expected, (label or "value") .. ": " .. tostring(actual))
end
local function Showing(cat)
    local found = {}
    Seeds:Query(1, -1e6, 1e6, -1e6, 1e6, function(seed)
        if seed.cats[cat] then found[#found + 1] = seed end
    end)
    return found
end
local function Record(cat, x, y, accuracy, id, name, kind)
    local rec = { k = "n" .. id, kind = kind or "npc", id = id, n = name, c = 1, x = x, y = y,
        a = accuracy, cats = { [cat] = true } }
    records[#records + 1] = rec
    ns:Fire("POI_UPDATED", rec, true)
    return rec
end
local function Forget()
    records = {}
    ns:Fire("DATA_CHANGED")
end
local function Nearest(list, x, y)
    local best
    for _, seed in ipairs(list) do
        local distance = ns.Distance(seed.x, seed.y, x, y)
        if not best or distance < best then best = distance end
    end
    return best
end

-- Where the player actually stood, from the saved variables.
local GRIMFUL = { 1692.449609469302, -4452.61138251517 }
local BANK = { 1625.847367145791, -4375.896447328618 }

-- 1. Nothing recorded: every individual the data lists has an icon. The three
--    bankers stand eight yards apart, which used to be near enough to count
--    as one.
equal(#Showing("auction"), 3, "three auctioneers are listed")
equal(#Showing("bank"), 3, "and three bankers")

-- 2. Speak to one auctioneer. He replaces the built-in location he stands on,
--    a yard away, and only that one.
Record("auction", GRIMFUL[1], GRIMFUL[2], 4, 9856, "Auctioneer Grimful")
local auctioneers = Showing("auction")
equal(#auctioneers, 2, "the other two auctioneers are still on the map")
assert(Nearest(auctioneers, GRIMFUL[1], GRIMFUL[2]) > 5, "the one he replaced is the one he stands on")

-- 3. The bank as it was saved: one banker spoken to, and the two beside him
--    only seen while standing there, so all three share one position.
local karus = Record("bank", BANK[1], BANK[2], 4, 3309, "Karus")
local soran = Record("bank", BANK[1], BANK[2], 10, 3320, "Soran")
local koma = Record("bank", BANK[1], BANK[2], 10, 3318, "Koma")
equal(#Showing("bank"), 2, "the two not spoken to keep their built-in places")
assert(not Seeds:Covers(karus, "bank"), "the banker spoken to is drawn")
assert(Seeds:Covers(soran, "bank") and Seeds:Covers(koma, "bank"),
    "the two seen from his spot are not piled on top of him")
-- Which is what every map view asks before drawing anything.
equal(Categories:GetVisibleCategory(karus), "bank", "Karus has his icon")
equal(Categories:GetVisibleCategory(soran), nil, "Soran is left to the built-in one")
equal(Categories:GetVisibleCategory(koma), nil, "and so is Koma")

-- 4. Speak to the other two as well, each from in front of them: every
--    built-in banker is now replaced by the one recorded there.
Forget()
for index, seed in ipairs(Showing("bank")) do
    Record("bank", seed.x + 2, seed.y, 4, 3300 + index, "Banker " .. index)
end
equal(#Showing("bank"), 0, "three recorded bankers replace all three")
for _, rec in ipairs(records) do
    assert(not Seeds:Covers(rec, "bank"), "and each of them is drawn")
end

-- 5. Two bankers recorded from nearly the same step, both nearest the same
--    built-in one, still account for two of the three, not one.
Forget()
local first = Showing("bank")[1]
Record("bank", first.x + 1, first.y, 4, 3301, "One")
Record("bank", first.x - 1, first.y, 4, 3302, "Two")
equal(#Showing("bank"), 1, "two records replace two built-in bankers")

-- 6. A rough sighting does not replace anything, however near it is.
Forget()
local rough = Record("bank", BANK[1], BANK[2], 10, 3320, "Soran")
equal(#Showing("bank"), 3, "a banker only seen in passing replaces none")
assert(Seeds:Covers(rough, "bank"), "and gives way to the built-in ones")

-- 7. It is drawn again once nothing better marks the spot: the built-in
--    locations removed by the player, not yet explored, or switched off.
local innkeeper = Record("inn", 0, 0, 10, 6929, "Innkeeper Gryshka")
local inn = Showing("inn")[1]
innkeeper.x, innkeeper.y = inn.x + 6, inn.y
ns:Fire("POI_UPDATED", innkeeper, false)
assert(Seeds:Covers(innkeeper, "inn"), "an innkeeper seen from the door gives way too")
-- An innkeeper is a food vendor as well. Giving way is whole: the sighting is
-- not drawn as a second, food icon beside the inn's own.
innkeeper.cats.food = true
equal(Categories:GetVisibleCategory(innkeeper), nil, "no food icon beside the inn's")
-- With innkeepers switched off nothing stands for them, so the vendor shows.
ns.db.settings.cats.inn = false
equal(Categories:GetVisibleCategory(innkeeper), "food", "unless inns are not being drawn at all")
ns.db.settings.cats.inn = nil
-- A quest on offer is still worth its marker.
innkeeper.cats.quest, questing = true, true
equal(Categories:GetVisibleCategory(innkeeper), "quest", "a quest giver keeps the quest marker")
innkeeper.cats.quest, questing = nil, false
innkeeper.cats.food = nil
Seeds:Hide(inn)
assert(not Seeds:Covers(innkeeper, "inn"), "until the built-in one is removed")
ns.db.hidden[inn.k] = nil
ns:Fire("POI_REMOVED", inn)
assert(Seeds:Covers(innkeeper, "inn"), "and again when it is back")
explored = false
ns:Fire("EXPLORED")
assert(not Seeds:Covers(innkeeper, "inn"), "nothing unexplored stands in for a sighting")
equal(#Showing("bank"), 0, "nor shows at all")
explored = true
ns:Fire("EXPLORED")
ns.settings.useSeedData = false
ns:Fire("SETTING_CHANGED", "useSeedData", false)
assert(not Seeds:Covers(innkeeper, "inn"), "nor anything switched off")
ns.settings.useSeedData = true
ns:Fire("SETTING_CHANGED", "useSeedData", true)

-- 8. Flight masters keep their own rules, and things that are not NPCs are
--    never rough in the first place.
local flight = Showing("flight")[1]
local master = Record("flight", flight.x + 6, flight.y, 10, 3310, "Doras")
assert(not Seeds:Covers(master, "flight"), "a flight master seen in passing is still drawn")
local mailbox = Showing("mailbox")[1]
local box = Record("mailbox", mailbox.x + 6, mailbox.y, 10, 1, "Mailbox", "obj")
assert(not Seeds:Covers(box, "mailbox"), "a mailbox is not a sighting")

print("Built-in locations: one record replaces one, rough sightings give way, at Orgrimmar's bank and auction house")
