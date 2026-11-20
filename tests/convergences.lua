-- Elemental Convergences: put on the map only by something that says where one
-- is. The game's own marker on the minimap (exact, nothing done), the mouse
-- held over that marker (the spot under the cursor), the Interact Key's pick
-- (beside it), or Skysight leaving the player Charged (within 25 yards of the
-- cast). Merely seeing one places nothing: it is drawn from far away. One
-- record per convergence however many signs, each placing it better; shown to
-- Skyborne only; marked by hand with /wf convergence.
local root = ...
local realPrint = print

local SKYSIGHT, CHARGED = 1259686, 1270893
local STARTING = "GameObject-0-4170-2521-17-460001-00005A"   -- the starting zone's
local WORLD = "GameObject-0-4170-1-17-616992-00005C"         -- the wider world's
local CHEST = "GameObject-0-4170-2521-17-181665-00005B"
local clock = 1000
function GetTime() return clock end
function time() return 1700000000 + clock end
function wipe(t) for key in pairs(t) do t[key] = nil end return t end

local timers = {}
C_Timer = { After = function(delay, fn) timers[#timers + 1] = { at = clock + delay, fn = fn } end }
local function advance(seconds)
    local target = clock + seconds
    while true do
        local nextIndex
        for index, timer in ipairs(timers) do
            if timer.at <= target and (not nextIndex or timer.at < timers[nextIndex].at) then nextIndex = index end
        end
        if not nextIndex then break end
        local timer = table.remove(timers, nextIndex)
        clock = math.max(clock, timer.at)
        timer.fn()
    end
    clock = target
end

-- The player's buffs, as the game lists them.
local buffs = {}
C_UnitAuras = { GetBuffDataByIndex = function(unit, index) return unit == "player" and buffs[index] or nil end }
local function buff(seconds, fields)
    local aura = { name = "Charged", spellId = CHARGED, sourceUnit = "player", duration = seconds,
        expirationTime = clock + seconds }
    for key, value in pairs(fields or {}) do aura[key] = value end
    return aura
end

-- One zone, 10000 yards across, inside a continent map that shows it at half size.
local ZONE, CONTINENT = 2521, 2500
local playerX, playerY = 4000, 2000
C_Map = {
    GetBestMapForUnit = function() return ZONE end,
    GetMapInfo = function(mapID) return mapID == ZONE and { parentMapID = CONTINENT } or { parentMapID = 0 } end,
}
-- Minimap markers: [guid] = { info = { ... }, at = { [mapID] = { x, y } } }
local markers, looks = {}, 0
C_VignetteInfo = {
    GetVignettes = function()
        looks = looks + 1
        local list = {}
        for guid in pairs(markers) do list[#list + 1] = guid end
        table.sort(list)
        return list
    end,
    GetVignetteInfo = function(guid) return markers[guid] and markers[guid].info end,
    GetVignettePosition = function(guid, mapID)
        local at = markers[guid] and markers[guid].at[mapID]
        return at and { GetXY = function() return at[1], at[2] end } or nil
    end,
}
-- The minimap: 200 across at half scale, showing 250 yards each way, its
-- middle at (1000, 600) of its own units. The cursor is given in screen pixels.
local viewRadius, rotating, facing = 250, false, 0
local cursorX, cursorY = 0, 0
Minimap = {
    GetCenter = function() return 1000, 600 end,
    GetWidth = function() return 200 end,
    GetHeight = function() return 200 end,
    GetEffectiveScale = function() return 0.5 end,
}
C_Minimap = { GetViewRadius = function() return viewRadius end }
function GetCursorPosition() return cursorX, cursorY end
function GetCVarBool(name) return name == "rotateMinimap" and rotating end
function GetPlayerFacing() return facing end
-- What the game draws on the minimap, listed for addons or not: { name, x, y }
-- in the world. A point of the minimap answers for any within 9 units of it.
local blips, asks, softCursor, askProblem = {}, 0, false, nil
local askedX, askedY
local inCombat, mouseOnMinimap, minimapShown = false, false, true
function InCombatLockdown() return inCombat end
Minimap.IsVisible = function() return minimapShown end
Minimap.IsMouseOver = function() return mouseOnMinimap end
Minimap.SetUsingSoftCursor = function(_, on) softCursor = on end
Minimap.UpdateMouseoverAtPoint = function(_, x, y)
    asks = asks + 1
    if askProblem then error(askProblem) end
    assert(softCursor, "the minimap is asked only once told the asking stands in for the mouse")
    askedX, askedY = x / 0.5 - 1000, y / 0.5 - 600
end
-- Points the mouse `right` and `up` minimap units from the minimap's middle.
local function pointAt(right, up) cursorX, cursorY = (1000 + right) * 0.5, (600 + up) * 0.5 end
C_TooltipInfo = { GetMinimapMouseover = function()
    local names = {}
    local turn = rotating and facing or 0
    local cosine, sine = math.cos(turn), math.sin(turn)
    for _, blip in ipairs(blips) do
        local east, north = playerY - blip.y, blip.x - playerX
        local px = (east * cosine + north * sine) / viewRadius * 100
        local py = (north * cosine - east * sine) / viewRadius * 100
        if (px - askedX) ^ 2 + (py - askedY) ^ 2 <= 81 then names[#names + 1] = blip.name end
    end
    if #names == 0 then return nil end
    return { type = 19, lines = { { type = 0, leftText = table.concat(names, "\n") } } }
end }

local pickName, pickGUID
function UnitName(unit) return unit == "softinteract" and pickName or nil end
function UnitGUID(unit) return unit == "softinteract" and pickGUID or nil end

Enum = { TooltipDataType = { Object = 4, MinimapMouseover = 19 }, TooltipDataLineType = { UnitName = 2 } }
local tooltipHooks = {}
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) tooltipHooks[kind] = fn end }

-- What an earlier version left behind: one merely seen, one Skysight was cast
-- near, one marked by hand, and somewhere else altogether.
local function old(key, x, y, accuracy, cats)
    return { k = key, kind = "obj", cats = cats or { convergence = true }, c = 1, x = x, y = y, a = accuracy,
        w = 1 / (accuracy * accuracy), n = "Elemental Convergence" }
end
local ns = { db = { settings = { cats = {}, showApproximate = true },
        pois = { seen = old("seen", 300, 300, 40), cast = old("cast", 600, 600, 10), hand = old("hand", 900, 900, 6),
            mail = old("mail", 300, 320, 40, { mailbox = true }) },
        observations = {
            a = { cat = "convergence", method = "sight" }, b = { cat = "convergence", method = "skysight" },
            c = { cat = "inn", method = "sight" } } },
    defaults = { cats = {} }, playerFaction = 2, playerRace = "Skyborne" }
function ns:NewModule(name) self[name] = { name = name }; return self[name] end
local events = {}
function ns:RegisterEvent(event, fn) events[event] = events[event] or {}; table.insert(events[event], fn) end
function ns:Fire() end
local function fire(event, ...) for _, fn in ipairs(events[event] or {}) do fn(event, ...) end end
function ns.Readable(value) return value ~= nil and value ~= "SECRET" end
function ns.GetPlayerWorld() if playerX then return 1, playerX, playerY, ZONE end end
function ns.MapToWorld(mapID, x, y)
    if mapID == ZONE then return 1, x * 10000, y * 10000 end
    if mapID == CONTINENT then return 1, x * 20000, y * 20000 end
end
function ns.Distance(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end
local printed, observed = {}, {}
function ns.Print(message) printed[#printed + 1] = tostring(message) end
ns.Observations = { Capture = function(_, info, method) observed[#observed + 1] = method end }
ns.Seeds = { Covers = function() return false end }
ns.QuestAvailability = { HasAvailableQuest = function() return false end }
MiniQoLRuntime = { Execute = function(_, _, fn) return fn("Wayfinder", ns) end }

for _, file in ipairs({ "Categories.lua", "Database.lua", "Convergences.lua" }) do
    assert(loadfile(root .. "/Modules/Wayfinder/" .. file))("Wayfinder", ns)
end
ns.Database:OnInitialize()
local Convergences = ns.Convergences

local function equal(actual, expected, label)
    assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function near(actual, expected, tolerance, label)
    assert(type(actual) == "number" and math.abs(actual - expected) <= tolerance, label .. ": " .. tostring(actual))
end
local function cast(unit, spellID)
    fire("UNIT_SPELLCAST_SUCCEEDED", unit or "player", "cast-guid", spellID or SKYSIGHT)
end
local function hover(name, lineType)
    tooltipHooks[Enum.TooltipDataType.Object]({}, { type = 4, lines = { { type = lineType or 0, leftText = name } } })
end
local function hoverMinimap(...)
    local lines = {}
    for _, name in ipairs({ ... }) do lines[#lines + 1] = { type = 0, leftText = name } end
    tooltipHooks[Enum.TooltipDataType.MinimapMouseover]({}, { type = 19, lines = lines })
end
local function records()
    local list = {}
    for _, rec in pairs(ns.db.pois) do
        if rec.cats.convergence then list[#list + 1] = rec end
    end
    return list
end
local function nearest(x, y)
    local best, shortest
    for _, rec in ipairs(records()) do
        local distance = ns.Distance(rec.x, rec.y, x, y)
        if not shortest or distance < shortest then best, shortest = rec, distance end
    end
    return best, shortest
end
local function said(text)
    for _, line in ipairs(printed) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- 1. The category, and what an earlier version left on the map
---------------------------------------------------------------------------
local category = ns.CategoryByID.convergence
assert(category, "convergences are a category of their own")
equal(ns.defaults.cats.convergence, true, "shown unless turned off")
equal(category.spell, SKYSIGHT, "drawn with Skysight's icon")

equal(#records(), 3, "three convergences from before")
Convergences:OnLogin()
advance(2) -- the look at the minimap on arriving in the world
equal(ns.db.pois.seen, nil, "one put where the player stood on merely seeing it is taken off the map")
equal(ns.db.pois.cast.a, 25, "one Skysight was cast near is within the game's 25 yards, not ten")
equal(ns.db.pois.hand.a, 6, "one marked by hand is left as it was")
assert(ns.db.pois.mail, "and nothing that isn't a convergence is touched")
equal(ns.db.observations.a, nil, "the sighting behind it is forgotten")
assert(ns.db.observations.b and ns.db.observations.c, "other observations are kept")
ns.db.pois.again = old("again", 300, 300, 40)
ns.Database:Rebuild()
Convergences:CorrectOldMarks()
assert(ns.db.pois.again, "the correction is made once")
ns.Database:Remove(ns.db.pois.again)
ns.Database:Remove(ns.db.pois.cast)
ns.Database:Remove(ns.db.pois.hand)
equal(#records(), 0, "a clean map for what follows")

---------------------------------------------------------------------------
-- 2. The game's marker on the minimap: exactly there, with nothing done
---------------------------------------------------------------------------
playerX, playerY = 9000, 1000
markers["Vignette-1"] = { info = { objectGUID = WORLD, name = "SECRET" }, at = { [ZONE] = { 0.905, 0.102 } } }
markers["Vignette-2"] = { info = { objectGUID = CHEST, name = "Battered Chest", atlasName = "VignetteLoot" },
    at = { [ZONE] = { 0.9, 0.1 } } }
fire("VIGNETTE_MINIMAP_UPDATED", "Vignette-2", true)
equal(#records(), 0, "some other object's marker is nothing to record")
fire("VIGNETTE_MINIMAP_UPDATED", "Vignette-1", true)
local marked = records()
equal(#marked, 1, "a marker on the world's convergence object records it, with no spell cast")
near(marked[1].x, 9050, 0.01, "where the game puts the marker, not where the player stands")
near(marked[1].y, 1020, 0.01, "on both axes")
equal(marked[1].a, 3, "exactly")
equal(marked[1].n, "Elemental Convergence", "named")
equal(marked[1].kind, "obj", "as a place, not an NPC")
equal(observed[#observed], "vignette", "noted as seen on the minimap")
equal(ns.db.convergence.listed, true, "and the game is known to list their markers")
assert(printed[1] and printed[1]:find("Elemental Convergence found.", 1, true), "and said once: " .. tostring(printed[1]))
fire("VIGNETTE_MINIMAP_UPDATED", "Vignette-1", true)
equal(#printed, 1, "the same marker again is nothing new")

-- Markers that come in a burst: the starting zone's object, one told only by
-- its name, one placed only on the map above, one the game hasn't placed yet.
markers["Vignette-3"] = { info = { objectGUID = "SECRET", name = "Elemental convergence" },
    at = { [ZONE] = { 0.1, 0.9 } } }
markers["Vignette-4"] = { info = { objectGUID = STARTING, name = "SECRET" }, at = { [CONTINENT] = { 0.25, 0.25 } } }
markers["Vignette-5"] = { info = { objectGUID = WORLD, name = "Elemental Convergence" }, at = {} }
fire("VIGNETTES_UPDATED")
fire("VIGNETTES_UPDATED")
equal(#records(), 1, "a burst is looked at once it settles")
advance(2)
equal(#records(), 3, "then each new convergence is recorded")
near(nearest(1000, 9000).x, 1000, 0.01, "one known only by its name, however it is capitalised")
near(nearest(5000, 5000).x, 5000, 0.01, "the starting zone's, placed on the map above")
markers["Vignette-5"].at[ZONE] = { 0.3, 0.3 }
fire("VIGNETTE_MINIMAP_UPDATED", "Vignette-5", true)
equal(#records(), 4, "one the game had not placed yet is recorded when it is")
near(nearest(3000, 3000).x, 3000, 0.01, "where the game then puts it")

---------------------------------------------------------------------------
-- 3. Seeing one places nothing; it is a moment to look at the minimap
---------------------------------------------------------------------------
playerX, playerY = 2000, 6000
printed = {}
hover("Battered Chest")
hover("SECRET")
equal(#printed, 0, "another object's tooltip, or an unreadable one, is nothing")
equal(#ns.db.convergence.trace, 0, "and nothing is noted")
hover("Elemental Convergence")
equal(#records(), 4, "the mouse on a convergence in view records nothing: it may be far off")
equal(#printed, 1, "but says how one gets on the map")
assert(said("in sight") and said("minimap") and said("Skysight"), "by the minimap or by Skysight: " .. printed[1])
local seen = ns.db.convergence.trace[#ns.db.convergence.trace]
equal(seen.why, "sight", "what the game showed just then is noted")
equal(seen.x, 2000, "with where the player stood")
equal(#seen.markers, 5, "and every marker on the minimap")

-- A marker that came without an event is found by that look.
advance(20)
markers["Vignette-6"] = { info = { objectGUID = WORLD, name = "Elemental Convergence" },
    at = { [ZONE] = { 0.21, 0.61 } } }
hover("Convergence \195\169l\195\169mentaire", 2)
equal(#records(), 5, "the game's marker for it, already showing, records it")
near(nearest(2100, 6100).x, 2100, 0.01, "where the marker is, not where the player stands")
equal(#printed, 2, "said as found")
assert(said("Elemental Convergence found."), "in the usual words")
local noted = ns.db.convergence.trace[#ns.db.convergence.trace]
local takenCount = 0
for _, marker in ipairs(noted.markers) do
    if marker.taken then takenCount = takenCount + 1 end
    assert(marker.name ~= "SECRET", "nothing unreadable is saved")
end
equal(takenCount, 5, "the note says which markers were taken for a convergence's")

-- The tooltip is drawn over and over while the mouse rests there.
local traced, looked = #ns.db.convergence.trace, looks
hover("Elemental Convergence")
hover("Elemental Convergence")
equal(looks, looked, "the mouse resting on it is one look at the minimap, not many")
equal(#ns.db.convergence.trace, traced, "and one note")
-- And the explanation is given once, however many are seen.
advance(20)
playerX, playerY = 8000, 8000
hover("Elemental Convergence")
equal(#printed, 2, "how one gets on the map is said once a session")
equal(#records(), 5, "and again nothing is recorded from the sight of it")

---------------------------------------------------------------------------
-- 4. The mouse on its marker on the minimap: the spot under the cursor
---------------------------------------------------------------------------
-- A marker the game draws but tells addons nothing of: no marker is listed.
advance(20)
markers = {}
playerX, playerY = 6000, 7000
printed = {}
pointAt(40, 20) -- 40 units right of the middle, 20 up: 100 yards east, 50 north
hoverMinimap("Battered Chest")
equal(#records(), 5, "the mouse on some other marker records nothing")
hoverMinimap("Off-Duty Pack Kodo", "Elemental Convergence")
equal(#records(), 6, "on a convergence's marker, it is recorded")
local pointed = nearest(6050, 6900)
near(pointed.x, 6050, 0.01, "north of the player by what the cursor is above the middle")
near(pointed.y, 6900, 0.01, "east of the player by what it is right of the middle")
near(pointed.a, 15, 0.01, "to within the marker's own width at this zoom")
equal(observed[#observed], "minimap", "noted as pointed at on the minimap")
assert(said("Elemental Convergence found."), "and said as found")
equal(ns.db.convergence.trace[#ns.db.convergence.trace].why, "minimap", "and noted")

-- Held there, the tooltip redraws: nothing more until a moment has passed.
pointAt(44, 20)
hoverMinimap("Elemental Convergence")
near(pointed.y, 6900, 0.01, "the mouse resting there records nothing more")
advance(5)
hoverMinimap("Elemental Convergence")
equal(#records(), 6, "later, the same convergence")
assert(pointed.y < 6900 and pointed.y > 6890, "its place settling between the two: " .. pointed.y)

-- A minimap that turns with the player: the player faces west, so "up" is west.
advance(5)
rotating, facing = true, math.pi / 2
playerX, playerY = 1000, 4000
pointAt(0, 40)
hoverMinimap("Elemental Convergence")
equal(#records(), 7, "pointed at on a turning minimap")
near(nearest(1000, 4100).y, 4100, 0.01, "straight up the minimap is straight ahead: west")
near(nearest(1000, 4100).x, 1000, 0.01, "and no further north")
rotating, facing = false, 0

-- Zoomed in, the same marker covers less ground.
advance(5)
viewRadius = 100
playerX, playerY = 1000, 1500
pointAt(-50, -50)
hoverMinimap("Elemental Convergence")
equal(#records(), 8, "pointed at on a zoomed-in minimap")
near(nearest(950, 1550).x, 950, 0.01, "half the minimap down is half the view south")
near(nearest(950, 1550).y, 1550, 0.01, "and west")
near(nearest(950, 1550).a, 6, 0.01, "placed more closely")
viewRadius = 250

-- The mouse off the minimap, at its very edge, or nowhere Wayfinder can place: nothing.
advance(5)
playerX, playerY = 3000, 8000
pointAt(140, 0)
hoverMinimap("Elemental Convergence")
equal(#records(), 8, "a cursor outside the minimap places nothing")
pointAt(0, 95)
hoverMinimap("Elemental Convergence")
equal(#records(), 8, "nor one on a marker held at the minimap's edge: that says which way, not where")
pointAt(10, 10)
playerX = nil
hoverMinimap("Elemental Convergence")
equal(#records(), 8, "nor does one where the player's place is unknown")
playerX = 3000

---------------------------------------------------------------------------
-- 5. The Interact Key's pick: beside it
---------------------------------------------------------------------------
playerX, playerY = 2500, 2500
fire("PLAYER_SOFT_INTERACT_CHANGED", nil, CHEST)
equal(#records(), 8, "another object picked for interacting is nothing")
fire("PLAYER_SOFT_INTERACT_CHANGED", nil, WORLD)
equal(#records(), 9, "a convergence picked for interacting is recorded")
equal(nearest(2500, 2500).a, 8, "where the player stands, within reach of it")
equal(observed[#observed], "interact", "noted as picked")
-- An object not met before, which the game names as one.
playerX, playerY = 2500, 3500
pickName = "Elemental Convergence"
fire("PLAYER_SOFT_INTERACT_CHANGED", nil, "GameObject-0-4170-1-17-700001-00005D")
equal(#records(), 10, "a convergence of a kind not met before is known by its name")
pickName = "Mailbox"
playerX, playerY = 2500, 4500
fire("PLAYER_SOFT_INTERACT_CHANGED", nil, "GameObject-0-4170-1-17-700001-00005E")
equal(#records(), 11, "and that kind is known from then on")
fire("PLAYER_SOFT_INTERACT_CHANGED", nil, "GameObject-0-4170-1-17-700002-00005F")
fire("PLAYER_SOFT_INTERACT_CHANGED", nil, "Creature-0-4170-1-17-616992-000060")
fire("PLAYER_SOFT_INTERACT_CHANGED", nil, "SECRET")
equal(#records(), 11, "a mailbox, a creature or an unreadable pick is nothing")
pickName = "Convergence Elemental"
playerX, playerY = 2500, 5500
fire("PLAYER_SOFT_INTERACT_CHANGED", nil, "Creature-0-4170-1-17-700003-000061")
equal(#records(), 11, "nor is a creature, whatever it is called")
equal(ns.db.convergence.objects[700003], nil, "and it teaches nothing")
pickName = nil

---------------------------------------------------------------------------
-- 6. Skysight leaving the player Charged: within 25 yards of the cast
---------------------------------------------------------------------------
playerX, playerY = 4000, 2000
printed = {}
buffs = { buff(15, { name = "Elemental Blessing", spellId = 1259688 }) } -- the ordinary blessing
cast()
advance(3)
equal(#records(), 11, "the ordinary blessing is no convergence")
buffs = {}
cast()
advance(3)
equal(#records(), 11, "nor is no buff at all")
equal(#timers, 1, "and it stops looking: only the minimap's own timer is left")

cast()
advance(0.3) -- Charged arrives a moment after the cast
equal(#records(), 11, "not before the player is Charged")
buffs = { buff(3600, { expirationTime = clock - 0.3 + 3600 }) }
advance(3)
equal(#records(), 12, "Charged by the cast: a convergence is here")
local first = nearest(4000, 2000)
near(first.x, 4000, 0.01, "put where the cast was made")
equal(first.a, 25, "the convergence within the game's 25 yards of it")
equal(observed[#observed], "skysight", "noted as found by Skysight")
assert(said("within 25 yards"), "said as near here, not as here: " .. tostring(printed[1]))
equal(ns.db.convergence.trace[#ns.db.convergence.trace].why, "charged", "and noted")
equal(ns.Categories:GetVisibleCategory(first), "convergence", "shown, as approximate")
ns.db.settings.showApproximate = false
equal(ns.Categories:GetVisibleCategory(first), nil, "unless approximate places are turned off")
ns.db.settings.showApproximate = true

-- The same convergence again, from a few steps away: one record, between the casts.
playerX, playerY = 4020, 2010
buffs = { buff(3600) }
cast()
advance(3)
equal(#records(), 12, "a second cast there is the same convergence")
assert(first.x > 4000 and first.x < 4020, "its place closing in between the casts: " .. first.x)

-- Still Charged from there, casting somewhere else: the buff began long ago.
advance(600)
playerX, playerY = 4800, 2600
cast()
advance(3)
equal(#records(), 12, "an old charge marks nothing where Skysight is cast next")

-- What else doesn't count, and what does.
playerX, playerY = 6000, 3000
buffs = { buff(3600) }
cast("party1")
cast("player", 2983) -- some other spell
advance(3)
equal(#records(), 12, "someone else's Skysight, or another spell, marks nothing")
buffs = { buff(3600, { name = "Arcane Intellect", spellId = 10157, sourceUnit = "party1" }) }
cast()
advance(3)
equal(#records(), 12, "another player's hour-long buff is not the charge")
buffs = { buff(3600, { duration = "SECRET" }), buff(3600, { expirationTime = "SECRET" }) }
cast()
advance(3)
equal(#records(), 12, "unreadable buffs mark nothing")
buffs = { buff(3600, { name = "Gift of the Winds", spellId = 1259999 }) }
cast()
advance(3)
equal(#records(), 13, "the charge under another ID, the player's own, new and an hour long, does")
buffs = { buff(900, { sourceUnit = "SECRET" }) }
playerX, playerY = 6000, 4000
cast()
advance(3)
equal(#records(), 14, "and Charged by its own ID does whatever its length or source")

-- With the game's marker for it showing: exactly there, not where the cast was.
playerX, playerY = 7000, 1000
markers["Vignette-7"] = { info = { objectGUID = WORLD, name = "Elemental Convergence", vignetteID = 7001 },
    at = { [ZONE] = { 0.7012, 0.1009 } } }
markers["Vignette-8"] = { info = { objectGUID = "GameObject-0-4170-1-17-800003-000062", name = "Old Well",
    vignetteID = 7006, atlasName = "well" }, at = { [ZONE] = { 0.6995, 0.0995 } } }
buffs = { buff(3600) }
cast()
advance(3)
equal(#records(), 15, "a convergence with a marker")
local exact = nearest(7012, 1009)
near(exact.x, 7012, 0.01, "is put where the marker is")
equal(exact.a, 3, "exactly, the cast adding nothing")
equal(ns.db.convergence.markers[7001], nil, "a marker already known teaches nothing")
equal(ns.db.convergence.markers[7006], nil, "and some other marker beside it is not taken for one")
equal(ns.db.convergence.objects[800003], nil, "nor its object")
markers["Vignette-8"] = nil

-- A marker of a kind not known, but out of the cast's reach: not the convergence's.
playerX, playerY = 7000, 2500
markers["Vignette-9"] = { info = { objectGUID = "GameObject-0-4170-1-17-800004-000063", name = "Old Well",
    vignetteID = 7007, atlasName = "well" }, at = { [ZONE] = { 0.7030, 0.2520 } } }
buffs = { buff(3600) }
cast()
advance(3)
equal(#records(), 16, "a convergence with no marker within reach of the cast")
near(nearest(7000, 2500).x, 7000, 0.01, "is put where the cast was made")
equal(nearest(7000, 2500).a, 25, "as within 25 yards")
equal(ns.db.convergence.markers[7007], nil, "the marker out of reach teaches nothing")
markers["Vignette-9"] = nil

-- A marker of a kind not known: the one within reach of the cast is the
-- convergence's, and its kind is learned. A chest's, a rare's, or one too far
-- off is not.
playerX, playerY = 7000, 5000
markers = {
    ["Vignette-A"] = { info = { objectGUID = "GameObject-0-4170-1-17-800001-00006A", name = "Swirling Winds",
        vignetteID = 7002, atlasName = "skyborne-swirl" }, at = { [ZONE] = { 0.7015, 0.5010 } } },
    ["Vignette-B"] = { info = { objectGUID = CHEST, name = "Battered Chest", vignetteID = 7003,
        atlasName = "VignetteLoot" }, at = { [ZONE] = { 0.7001, 0.5001 } } },
    ["Vignette-C"] = { info = { objectGUID = "Creature-0-4170-1-17-5831-00006B", name = "Swiftmane",
        vignetteID = 7004, atlasName = "skull" }, at = { [ZONE] = { 0.7002, 0.5002 } } },
    ["Vignette-D"] = { info = { objectGUID = "GameObject-0-4170-1-17-800002-00006C", name = "Old Well",
        vignetteID = 7005, atlasName = "well" }, at = { [ZONE] = { 0.7040, 0.5040 } } },
}
buffs = { buff(3600) }
cast()
advance(3)
equal(#records(), 17, "a convergence under a marker of an unknown kind")
local learned = nearest(7015, 5010)
near(learned.x, 7015, 0.01, "is put where that marker is")
near(learned.y, 5010, 0.01, "not where the chest, the rare or the cast is")
equal(learned.a, 3, "exactly")
equal(ns.db.convergence.objects[800001], true, "its object is remembered")
equal(ns.db.convergence.markers[7002], true, "and its kind of marker")
equal(ns.db.convergence.objects[181665], nil, "a chest's is not")
equal(ns.db.convergence.markers[7003], nil, "nor a chest's marker")
equal(ns.db.convergence.markers[7004], nil, "nor a rare's")
equal(ns.db.convergence.markers[7005], nil, "nor one out of the cast's reach")

-- From then on that kind is known the moment the game shows it, with no cast:
-- by its object, or by its kind of marker alone.
playerX, playerY = 500, 8500
markers = {
    ["Vignette-E"] = { info = { objectGUID = "GameObject-0-4170-1-17-800001-00006D", name = "Swirling Winds" },
        at = { [ZONE] = { 0.05, 0.85 } } },
    ["Vignette-F"] = { info = { objectGUID = "SECRET", name = "Swirling Winds", vignetteID = 7002 },
        at = { [ZONE] = { 0.05, 0.95 } } },
    ["Vignette-G"] = { info = { objectGUID = "GameObject-0-4170-1-17-800002-00006E", name = "Old Well",
        vignetteID = 7005 }, at = { [ZONE] = { 0.15, 0.85 } } },
}
fire("VIGNETTES_UPDATED")
advance(2)
equal(#records(), 19, "two more of the learned kind are recorded with nothing cast")
near(nearest(500, 8500).a, 3, 0.01, "one by its object")
near(nearest(500, 9500).a, 3, 0.01, "one by its kind of marker")
markers = {}

-- Nowhere Wayfinder can place (inside a dungeon): nothing to record.
playerX = nil
buffs = { buff(3600) }
cast()
hover("Elemental Convergence")
fire("PLAYER_SOFT_INTERACT_CHANGED", nil, WORLD)
advance(20)
equal(#records(), 19, "no position, no record")
playerX, playerY = 7000, 3500

---------------------------------------------------------------------------
-- 7. Asking the minimap: a marker the game draws but lists for no addon
---------------------------------------------------------------------------
equal(ns.db.convergence.can.ask, true, "that this game can be asked is noted at login")
equal(ns.db.convergence.can.markers and ns.db.convergence.can.point, true, "with the other ways it has")
-- Nothing listed, nothing cast, the mouse nowhere near: the minimap is gone
-- over as the player moves, and the marker found on it.
advance(100) -- any earlier sign that one was near has had its time
ns.db.convergence.listed = nil
markers, printed = {}, {}
playerX, playerY = 1500, 7000
blips = { { name = "Off-Duty Pack Kodo", x = 1510, y = 7010 },
    { name = "|TArrow:0|t Elemental Convergence", x = 1580, y = 6940 } }
local asked = asks
advance(3)
equal(#records(), 20, "a convergence's marker on the minimap is found with nothing done")
local found = nearest(1580, 6940)
near(found.x, 1580, 6, "where the marker is, not where the player stands: north")
near(found.y, 6940, 6, "and east")
equal(found.a, 10, "to within the spacing of the asking at this zoom")
assert(said("Elemental Convergence found."), "said as found")
assert(asks > asked, "by asking the minimap")
equal(softCursor, false, "which is handed back to the mouse afterwards")
equal(ns.db.convergence.sweepFinds, 1, "one find")
equal(ns.db.convergence.trace[#ns.db.convergence.trace].why, "sweep", "noted")
equal(observed[#observed], "minimap", "as read off the minimap")
asked = asks
advance(10)
equal(asks, asked, "placed, it is not looked for again")

-- Somewhere with nothing but a marker held at the minimap's edge for one far
-- off: gone over on arriving, and again only once moved on.
blips = { { name = "Elemental Convergence", x = 9230, y = 9000 } }
playerX, playerY = 9000, 9000
advance(3)
assert(asks > asked, "somewhere new, the minimap is gone over")
equal(#records(), 20, "and a marker at its edge is not taken for where one is")
blips = {}
asked = asks
advance(10)
equal(asks, asked, "but not again while the player stands still")
playerX = 9020
advance(3)
equal(asks, asked, "nor for a few steps")
playerX = 9040
advance(3)
assert(asks > asked, "once the player has moved on, again")

-- Never in a fight, with the mouse on the minimap, or with the minimap hidden.
asked = asks
inCombat, playerX = true, 9100
advance(3)
equal(asks, asked, "not in a fight")
inCombat, mouseOnMinimap = false, true
advance(3)
equal(asks, asked, "not while the mouse itself is on the minimap")
mouseOnMinimap, minimapShown = false, false
advance(3)
equal(asks, asked, "not with the minimap hidden")
minimapShown = true
advance(3)
assert(asks > asked, "and then it is")

-- A cast says one is within 25 yards: its marker is looked for there and then,
-- though the player hasn't moved, and the cast's rough place gives way to it.
playerX, playerY = 9500, 5000
advance(3)
blips = { { name = "Elemental Convergence", x = 9515, y = 4990 } }
asked = asks
advance(6)
equal(asks, asked, "standing still, the minimap is not gone over")
buffs = { buff(3600) }
cast()
advance(3)
equal(#records(), 21, "Charged there: a convergence")
local swept = nearest(9515, 4990)
near(swept.x, 9515, 6, "put at its marker, looked for because the cast said one is near")
near(swept.y, 4990, 6, "on both axes")
equal(swept.a, 10, "not left at the cast's 25 yards")

-- For a while: then the minimap is left alone again.
asked = asks
advance(10)
equal(asks, asked, "placed, it is looked for no more")
-- Seeing one says one is near, too.
playerX, playerY = 8500, 2500
blips = {}
advance(30)
blips = { { name = "Elemental Convergence", x = 8600, y = 2450 } }
asked = asks
advance(20)
equal(asks, asked, "the minimap is not gone over while the player stands still")
equal(#records(), 21, "its marker has come onto the minimap while the player stood still")
hover("Elemental Convergence")
advance(1)
equal(#records(), 22, "the mouse on it in the world sets the minimap being gone over")
near(nearest(8600, 2450).x, 8600, 6, "and it is put at its marker")

-- A marker the game does list at that very spot, of a kind not known: it is
-- this one, so its own place is taken as exact and its kind is learned.
playerX, playerY = 8500, 500
markers = { ["Vignette-S"] = { info = { objectGUID = "GameObject-0-4170-1-17-800010-00007A", name = "Swirl",
    vignetteID = 7010, atlasName = "swirl" }, at = { [ZONE] = { 0.8560, 0.0540 } } } }
blips = { { name = "Elemental Convergence", x = 8562, y = 538 } }
advance(3)
equal(#records(), 23, "found on the minimap, with a listed marker at the same spot")
local both = nearest(8560, 540)
near(both.x, 8560, 0.01, "put exactly where the listed marker is")
equal(both.a, 3, "as exact")
equal(ns.db.convergence.markers[7010], true, "and that kind of marker is known from then on")
equal(ns.db.convergence.objects[800010], true, "with its object")
markers = {}

-- Where the game lists their markers itself, the minimap is not gone over on
-- the off chance, only when something says one is near.
advance(100)
ns.db.convergence.listed = true
playerX, playerY = 9000, 6000
blips = { { name = "Elemental Convergence", x = 9050, y = 6000 } }
asked = asks
advance(12)
equal(asks, asked, "nothing asked on the off chance")
hover("Elemental Convergence")
advance(1)
equal(#records(), 24, "but one seen is looked for and found")
ns.db.convergence.listed = nil

-- A game that can't be asked: nothing is tried.
local ask = Minimap.UpdateMouseoverAtPoint
Minimap.UpdateMouseoverAtPoint = nil
playerX, playerY = 500, 500
blips = { { name = "Elemental Convergence", x = 520, y = 520 } }
asked = asks
advance(6)
equal(#records(), 24, "nothing is found without the asking")
Minimap.UpdateMouseoverAtPoint = ask
-- And one that refuses: the minimap is handed back, and it isn't tried again.
askProblem = "the asking was blocked"
advance(3)
assert(asks > asked, "it is tried")
equal(softCursor, false, "the minimap is handed back to the mouse all the same")
assert(tostring(ns.db.convergence.sweepProblem):find("blocked", 1, true), "what went wrong is noted")
askProblem = nil
asked = asks
playerX = 600
advance(10)
equal(asks, asked, "and it is not tried again this session")
equal(#records(), 24, "nothing recorded from it")
blips = {}
playerX, playerY = 7000, 3500

---------------------------------------------------------------------------
-- 8. By hand: here, whatever was thought before
---------------------------------------------------------------------------
printed = {}
assert(Convergences:MarkHere(), "/wf convergence marks one where you stand")
equal(#records(), 25, "as a record of its own")
assert(printed[1]:find("marked where you stand", 1, true), "and says so")
equal(#printed, 1, "once")
equal(ns.db.convergence.trace[#ns.db.convergence.trace].why, "hand", "what the game showed there is noted")
playerX, playerY = 7005, 3505
assert(Convergences:MarkHere(), "again, a few steps on")
equal(#records(), 25, "the same one")
near(nearest(7005, 3505).x, 7005, 0.01, "moved to where you stand now")
-- Even one the game's own marker placed.
playerX, playerY = 7020, 1000
assert(Convergences:MarkHere(), "standing by one the marker placed")
equal(#records(), 25, "still one record there")
near(nearest(7020, 1000).x, 7020, 0.01, "put where you say it is")
equal(nearest(7020, 1000).a, 6, "as marked by hand")

-- The notes are kept short.
assert(#ns.db.convergence.trace <= 12, "only the last dozen signs are kept: " .. #ns.db.convergence.trace)
for round = 1, 20 do
    advance(120)
    Convergences:MarkHere()
end
equal(#ns.db.convergence.trace, 12, "however many there are")

---------------------------------------------------------------------------
-- 9. Shown to Skyborne only
---------------------------------------------------------------------------
local shown = nearest(7012, 5010)
equal(ns.Categories:GetVisibleCategory(shown), "convergence", "a Skyborne sees them")
ns.db.settings.cats.convergence = false
equal(ns.Categories:GetVisibleCategory(shown), nil, "unless the category is turned off")
ns.db.settings.cats.convergence = true
ns.playerRace = "Orc"
equal(ns.Categories:GetVisibleCategory(shown), nil, "another race is not shown them")
assert(not Convergences:MarkHere(), "and cannot mark one")
equal(#records(), 25, "nothing is added")

-- A character of another race does not watch for them at all.
events, tooltipHooks = {}, {}
Convergences:OnLogin()
equal(next(events), nil, "no events for a race without Skysight")
equal(next(tooltipHooks), nil, "and no tooltip watched")

print = realPrint
print("Convergences: placed by the game's minimap marker, listed or found by asking the minimap, the mouse on that marker, the interact pick or a Charged Skysight; never by sight alone; marker kinds learned; one record each; Skyborne only")
