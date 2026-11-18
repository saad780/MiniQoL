-- Which service icons share a pin. A built-in location is one person at a
-- counter, so three auctioneers are three icons; they only share one where they
-- would land on top of each other, and a real duplicate is still one icon.
local root = ...

local ns = {}
function ns:NewModule(name) self[name] = { name = name }; return self[name] end
function ns.Distance(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end
ns.CategoryByID = {
    bank = { order = 1, label = "Bank" },
    auction = { order = 2, label = "Auction house" },
    flight = { order = 3, label = "Flight master" },
    vendor = { order = 4, label = "Vendor" },
}
MiniQoLRuntime = { Execute = function(_, _, fn) return fn("Wayfinder", ns) end }
assert(loadfile(root .. "/Modules/Wayfinder/ServiceLocations.lua"))("Wayfinder", ns)
local Locations = ns.ServiceLocations

-- As the map views collect them: where it is in yards, and where that lands
-- on screen at the zoom being drawn.
local pixelsPerYard = 2.5
local function Entry(cat, x, y, fields)
    local rec = { c = 1, x = x, y = y, cats = { [cat] = true } }
    for key, value in pairs(fields) do rec[key] = value end
    return { rec = rec, cat = cat, c = 1, id = rec.id, n = rec.n, kind = rec.kind, seed = rec.seed,
        cats = rec.cats, x = x, y = y, mx = 0, my = 0,
        screenX = x * pixelsPerYard, screenY = y * pixelsPerYard }
end
local function BuiltIn(cat, x, y, name) return Entry(cat, x, y, { kind = "seed", seed = true, n = name }) end
local function Recorded(cat, x, y, id, name) return Entry(cat, x, y, { kind = "npc", id = id, n = name }) end
local function AddonMarker(cat, x, y, id, name) return Entry(cat, x, y, { ephemeral = true, id = id, n = name }) end

local function kept(...) return #Locations:Select({ ... }) end
local function equal(actual, expected, label)
    assert(actual == expected, (label or "value") .. ": " .. tostring(actual))
end

-- 1. Orgrimmar's auction house as it stood: one auctioneer spoken to, the
--    other two known only as built-in locations 10 and 26 yards from him.
equal(kept(
    Recorded("auction", 1692.45, -4452.61, 9856, "Auctioneer Grimful"),
    BuiltIn("auction", 1685.63, -4460.25, "Auctioneer"),
    BuiltIn("auction", 1666.91, -4457.44, "Auctioneer")), 3, "three auctioneers, three icons")

-- 2. Built-in locations a few yards apart are different people.
equal(kept(
    BuiltIn("bank", 0, 0, "Banker"),
    BuiltIn("bank", 8, 0, "Banker"),
    BuiltIn("bank", 16, 0, "Banker")), 3, "three bankers in a row")
-- The same point listed twice is still one.
equal(kept(BuiltIn("bank", 0, 0, "Banker"), BuiltIn("bank", 1, 0, "Banker")), 1, "one point listed twice")

-- 3. A built-in location still showing beside a record is somebody else: the
--    pairing of the two was done before either reached here.
equal(kept(
    Recorded("bank", 0, 0, 3309, "Karus"),
    BuiltIn("bank", 10, 0, "Banker")), 2, "a record does not swallow its neighbour")
equal(kept(
    Recorded("bank", 0, 0, nil, nil),
    BuiltIn("bank", 10, 0, "Banker")), 2, "nor does a nameless one")

-- 4. A temporary marker from another addon has not been paired with anything,
--    so it is still matched to a built-in location by place.
equal(kept(
    AddonMarker("bank", 0, 0, 3309, "Karus"),
    BuiltIn("bank", 10, 0, "Banker")), 1, "an addon's marker replaces the built-in one it sits on")

-- 5. One NPC recorded twice is one icon.
equal(kept(
    Recorded("bank", 0, 0, 3309, "Karus"),
    Recorded("bank", 1, 0, 3309, "Karus")), 1, "one NPC, one icon")

-- 6. Zoomed out until they would be drawn on top of each other, the same
--    counter is one readable icon again rather than a clump: whether built-in,
--    recorded, or a mixture of the two.
pixelsPerYard = 0.5
equal(kept(
    BuiltIn("bank", 0, 0, "Banker"),
    BuiltIn("bank", 8, 0, "Banker"),
    BuiltIn("bank", 16, 0, "Banker")), 1, "one icon for the counter from far out")
equal(kept(
    Recorded("bank", 0, 0, 3309, "Karus"),
    BuiltIn("bank", 8, 0, "Banker"),
    BuiltIn("bank", 16, 0, "Banker")), 1, "a named banker among them makes no clump either")
equal(kept(
    Recorded("bank", 0, 0, 3309, "Karus"),
    Recorded("bank", 8, 0, 3320, "Soran"),
    Recorded("bank", 16, 0, 3318, "Koma")), 1, "nor do three named ones")

-- 7. Other services you recorded are never merged by how close they are
--    drawn, but two built-in ones of a kind are: they used to be merged
--    outright, and must not become a pile now that each is its own.
equal(kept(
    Recorded("vendor", 0, 0, 1, "Thrumn"),
    Recorded("vendor", 8, 0, 2, "Kuruk")), 2, "two vendors stay two")
equal(kept(
    BuiltIn("vendor", 0, 0, "Mailbox"),
    BuiltIn("vendor", 18, 0, "Mailbox")), 1, "two built-in ones share an icon from far out")
pixelsPerYard = 2.5
equal(kept(
    BuiltIn("vendor", 0, 0, "Mailbox"),
    BuiltIn("vendor", 18, 0, "Mailbox")), 2, "and are two again with room to draw them")
pixelsPerYard = 0.5

-- The minimap holds records rather than entries, and says what it is drawing.
local one = { c = 1, x = 0, y = 0, seed = true, cats = { bank = true } }
local two = { c = 1, x = 8, y = 0, cats = { bank = true } }
assert(Locations:Overlaps(one, two, 4, "bank"), "records overlap by the category given")
assert(not Locations:Overlaps(one, two, 20, "bank"), "and not with room between them")
assert(not Locations:Overlaps(one, two, 4, "vendor"), "nor as a kind that is never merged")

-- 8. And separate counters are separate however small they are drawn.
equal(kept(
    BuiltIn("bank", 0, 0, "Banker"),
    BuiltIn("bank", 400, 0, "Banker")), 2, "two banks are two icons")

print("Service icons: each built-in location is its own, merged only where they would overlap")
