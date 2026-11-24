local package = ...
local ns = { playerFaction = 2, playerClass = "WARRIOR", db = {}, Background = {} }
local cfg = { travelHearth = true, travelFlights = true, travelTransports = true }
local events, job, searches, steps = {}, nil, 0, 0
local now, stone, bind, duration, flying, dead = 100, 0, "Brill", 0, false, false
function ns:GetSetting(key) return cfg[key] end
function ns:GetCharacterKey() return "tester" end
function ns:NewModule(name) self[name] = {}; return self[name] end
function ns:On(event, fn) events[event] = fn end
function ns:RegisterEvent(event, fn) events[event] = fn end
function ns.Readable(value) return value ~= nil end
function ns.Distance(x, y, a, b) return math.sqrt((x-a)^2 + (y-b)^2) end
function ns.Background:Has() return job ~= nil end
function ns.Background:Queue(_, fn)
	assert(not job)
	searches = searches + 1
	job = coroutine.create(fn)
end
local function drain()
	while job do
		local ok, err = coroutine.resume(job)
		assert(ok, err)
		steps = steps + 1
		if coroutine.status(job) == "dead" then job = nil end
	end
end
function GetTime() return now end
function GetBindLocation() return bind end
function GetItemCount(id) return id == 6948 and stone or 0 end
function GetItemCooldown() return duration > 0 and now or 0, duration, 1 end
function UnitIsDeadOrGhost() return dead end
function InCombatLockdown() return false end
C_Map = {}
ns.Walking = { Compat = { IsOnTaxi = function() return flying end, GetPlayerUnitPosition = function() end } }
MiniQoLRuntime = { Execute = function(_, name, fn) fn(name, ns) end }
local base = package .. "/Modules/Wayfinder/"
assert(loadfile(base .. "Data/TravelNetwork.lua"))()
assert(loadfile(base .. "Travel.lua"))()
local T = ns.Travel
T:OnLogin()
local function spot(c, x, y, m) return { c=c, x=x, y=y, m=m, n="Destination" } end
local function aim(goal, here) return T:Aim(goal, here.c, here.x, here.y, here.m) end
local function route(goal, here)
	aim(goal, here)
	drain()
	return aim(goal, here)
end
local function setting(key, value)
	cfg[key] = value
	events.SETTING_CHANGED(key)
end

local org = spot(1, 1550, -4420, 1454)
local uc = spot(0, 1570, 270, 1458)
local tower, _, caption = route(uc, org)
assert(tower and caption:find("zeppelin to Undercity"), tostring(caption))
local count = searches
for i=1,200 do aim(uc, org) end
assert(searches == count and steps > 10, "unchanged arrow updates should reuse the budgeted plan")
assert(select(2, aim(uc, tower)) == "Take the zeppelin to Undercity")
assert(select(2, T:Aim(uc, nil)) == "Take the zeppelin to Undercity", "retain the ride during a loading screen")
local dock = spot(0, 2064, 288.6, 1420)
assert(route(uc, dock) == nil, "walk to the final pin after the crossing")
setting("travelTransports", false)
assert(not route(uc, org), "no cross-continent walk or unrequested transport")
setting("travelTransports", true)

-- A neutral boat, with different boarding points in each direction.
local booty = spot(0, -14298.1, 539.4, 1434)
local ratchet = spot(1, -985.3, -3796.6, 1413)
assert(select(2, route(booty, ratchet)) == "Take the boat to Booty Bay")
assert(select(2, route(ratchet, booty)) == "Take the boat to Ratchet")

-- One ready hearth can replace a crossing. Re-evaluate when it cools
-- down, is taken out of the bags, or the character changes their bind.
stone = 1
local brill = spot(0, 2274, 240, 1420)
assert(select(2, route(brill, org)) == "Use Hearthstone to Gallows' End Tavern")
duration, now = 3600, now + 4
assert(route(brill, org) ~= nil)
duration, bind, now = 0, "Unmapped Inn", now + 4
assert(route(brill, org) ~= nil)
bind, now = "Brill", now + 4
assert(select(2, route(brill, org)):find("Hearthstone"))
setting("travelHearth", false)
assert(route(brill, org) ~= nil)
setting("travelHearth", true)
bind = "Newly opened inn"
ns.GetPlayerWorld = function() return 0, brill.x, brill.y, brill.m end
events.HEARTHSTONE_BOUND()
assert(select(2, route(brill, org)) == "Use Hearthstone to Newly opened inn")
stone, now = 0, now + 4

-- Only confirmed destinations are usable. A new departure can be
-- learned in person. Opening the taxi map only records current/reachable.
setting("travelTransports", false)
local cross = spot(1, -437.1, -2596, 1413)
local orgMaster = spot(1, 1676, -4314, 1454)
assert(not route(orgMaster, cross))
GetTaxiMapID = function() return 1 end
C_TaxiMap = { GetAllTaxiNodes = function() return { { nodeID=23, state=1 }, { nodeID=999, state=2 } } end }
events.TAXIMAP_OPENED()
assert(ns.db.knownFlights.tester[23] and not ns.db.knownFlights.tester[999])
local _, instruction, name = route(orgMaster, cross)
local crossNode
for _, row in ipairs(ns.TravelNetwork.taxi) do
	if row[1] == 25 then crossNode = spot(row[2], row[3], row[4], row[5]) end
end
-- A confirmed undiscovered master on an ordinary walk gets a hint without
-- changing the goal or adding a detour. Check a walk with no usable flights.
local localGoal = spot(1, crossNode.x + 175, crossNode.y, crossNode.m)
T:ObserveTaxi(25, true)
now = now + 2
local hintStop, hintAction, hint = route(localGoal, crossNode)
assert(not hintStop and not hintAction and hint and hint:find("Learn the flight point"))
local _, board = route(orgMaster, crossNode)
assert(board and board:find("Learn the flight point") and board:find("Orgrimmar"), tostring(name or instruction or board))
T:RememberTaxi(25)
assert(select(2, aim(orgMaster, crossNode)):find("^Fly to"))
flying = true
assert(select(2, aim(orgMaster, crossNode)):find("^Flying to"))
flying = false
assert(not route(orgMaster, orgMaster))
setting("travelFlights", false)
assert(not route(orgMaster, crossNode))
setting("travelTransports", true)

-- Replacing a goal mid-search cannot publish an obsolete boarding point.
T:Reset()
aim(uc, org)
aim(booty, org)
drain()
local stop = route(booty, org)
assert(stop and stop.n ~= "Undercity")
dead = true
assert(not aim(booty, org) and not job)
dead = false
booty.source = "Polestar"
assert(not aim(booty, org) and not job)

-- Alliance cannot take the Horde zeppelin. The Alliance airship and the
-- Darnassus portal work even with no discovered flights.
ns.playerFaction = 1
assert(loadfile(base .. "Travel.lua"))()
T = ns.Travel
T:OnLogin()
local zephras = spot(2991, 2000, 600, 2521)
local allianceDock = route(zephras, spot(0, 800, 400, 1416))
assert(allianceDock and allianceDock.n == "Dalaran")
local darn = spot(1, 9947.5, 2630, 1457)
local rut = spot(1, 8643.6, 841, 1438)
assert(select(2, route(rut, darn)) == "Take the portal to Rut'theran Village")
print("Waypoint travel: faction crossings, timed rides, hearth availability, flight knowledge, landing and cancellation passed")
