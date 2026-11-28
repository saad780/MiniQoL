local package = ...
local ns = { playerFaction = 2, playerClass = "WARRIOR", db = {}, Background = {} }
local cfg = { travelHearth = true, travelFlights = true, travelTransports = true }
local events, job, searches, steps = {}, nil, 0, 0
local now, stone, bind, duration, flying, dead = 100, 0, "Brill", 0, false, false
function ns:GetSetting(key) return cfg[key] end
function ns:GetCharacterKey() return "tester" end
function ns:NewModule(name) self[name] = {}; return self[name] end
function ns:On(event, fn) events[event] = fn end
function ns:Fire(event, ...) if events[event] then events[event](...) end end
function ns:RegisterEvent(event, fn) events[event] = fn end
function GetTaxiMapID() return 1 end
local function openTaxiMap(nodes)
	C_TaxiMap = { GetAllTaxiNodes = function() return nodes end }
	events.TAXIMAP_OPENED()
end
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
local _, boardZeppelin, _, waitingAtTower = route(uc, tower)
assert(boardZeppelin == "Take the zeppelin to Undercity" and waitingAtTower, "show the boarding action at the tower")
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

-- Thunder Bluff flight master to a quest outside Camp Taurajo. The flight
-- is known and short, but a ready hearth lands closer and gets there sooner.
local bluff = spot(1, -1197.2, 29.7, 1456)
local taurajo = spot(1, -2376.4, -1995.9, 1413)
local quest = spot(1, -2500, -2195, 1413)
openTaxiMap({ { nodeID=22, state=0 }, { nodeID=77, state=1 } })
bind, stone, duration = "Camp Taurajo", 1, 0
local hearthToCamp = "Use Hearthstone to Camp Taurajo"
local flyToCamp = "Fly to Camp Taurajo, The Barrens"
local waypoint = quest
ns.Navigation = { GetWaypoint = function() return waypoint end }
local _, campAction = route(quest, bluff)
assert(campAction == hearthToCamp, "ready Taurajo hearth: " .. tostring(campAction))
assert(not T:GetRecommendedFlight(), "the taxi map must agree with the hearth recommendation")

duration, now = 3600, now + 4
local _, boardFlight, _, waitingAtMaster = route(quest, bluff)
assert(boardFlight == flyToCamp and waitingAtMaster, "show the flight action at the master while the hearth cools")
local boardAt, flyTo = T:GetRecommendedFlight()
assert(boardAt.taxi == 22 and flyTo.taxi == 77, "highlight Camp Taurajo at the Thunder Bluff master")
waypoint = nil
assert(not T:GetRecommendedFlight(), "clearing the waypoint invalidates the taxi recommendation immediately")
waypoint = quest
duration, now = 0, now + 4
assert(select(2, route(quest, bluff)) == hearthToCamp, "reconsider a ready hearth before takeoff")

bind, now = "Thunder Bluff", now + 4
assert(select(2, route(quest, bluff)) == flyToCamp, "a ready bind back in Thunder Bluff loses to the flight")
bind = "Camp Taurajo"
setting("travelHearth", false)
assert(select(2, route(quest, bluff)) == flyToCamp)
flying = true
setting("travelHearth", true)
assert(select(2, aim(quest, bluff)) == "In flight", "do not suggest casting a hearthstone in flight")
flying = false
assert(select(2, route(quest, bluff)) == hearthToCamp)
duration = 3600
local onward, afterHearth = route(quest, taurajo)
assert(not onward and not afterHearth, "walk from the inn to the original quest pin")
stone, duration = 0, 0

-- Only confirmed destinations are usable. A new departure can be
-- learned in person. Opening the taxi map only records current/reachable.
setting("travelTransports", false)
local cross = spot(1, -437.1, -2596, 1413)
local orgMaster = spot(1, 1676, -4314, 1454)
assert(not route(orgMaster, cross))
openTaxiMap({ { nodeID=23, state=1 }, { nodeID=999, state=2 } })
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
openTaxiMap({ { nodeID=25, state=0 } })
assert(select(2, route(orgMaster, crossNode)):find("^Fly to"))
flying = true
local _, inFlight, _, riding = aim(orgMaster, crossNode)
assert(inFlight:find("^Flying to") and riding, "keep the ride instruction until landing")
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
-- Take a different portal while waiting to sail. The old boat instruction
-- must disappear on the first usable position, even within its boarding grace period.
local sw = spot(0, -8900, 600, 1453)
local auberdine = spot(1, 6544.8, 930.2, 1439)
local harbor = spot(0, -8651, 1332.3, 1453)
local destination = spot(1, 6200, 100, 1439)
assert(select(2, route(destination, harbor)):find("Take the boat"))
local before = searches
aim(destination, sw) -- move inside the same map without a loading screen
drain()
local backToDock, staleBoard = aim(destination, sw)
assert(searches == before + 1 and backToDock and not staleBoard, "replan immediately after a same-map relocation")
assert(select(2, route(destination, harbor)):find("Take the boat"))
T:Aim(destination, nil)
local onFoot, staleRide = route(destination, spot(1, 6180, 350, 1439))
assert(not onFoot and not staleRide, "unexpected landing resumes the trip from the actual position")

-- A flight taken on a walking route can cross multiple zones. Search once
-- after landing. A loading screen or zoning in flight must not start a search.
before = searches
flying = true
aim(destination, auberdine)
events.ZONE_CHANGED_NEW_AREA()
now = now + 1
aim(destination, rut)
T:Aim(destination, nil)
assert(searches == before)
flying = false
route(destination, rut)
assert(searches == before + 1, "replan after an unplanned flight")

-- An unplanned same-zone ship can move continuously without a loading
-- screen. With zero personal speed it is the deck carrying the player.
local speed = 0
function GetUnitSpeed() return speed, 7 end
T:Reset()
route(destination, auberdine)
before = searches
for i=1,6 do
	now = now + 1
	local _, instruction = aim(destination, spot(1, auberdine.x - 8*i, auberdine.y, 1439))
	if i >= 3 then assert(instruction == "Riding transport", "wait for the actual dock") end
end
assert(searches == before, "a moving ship should not launch walking searches")
now = now + 1
route(destination, spot(1, auberdine.x - 48, auberdine.y, 1439))
assert(searches == before + 1, "the ship stopped in the same zone")

-- Coalesce a burst of zone events. Ordinary steps and camera updates reuse
-- the route until a meaningful position change.
speed = 7
before = searches
events.ZONE_CHANGED()
events.ZONE_CHANGED_INDOORS()
events.ZONE_CHANGED_NEW_AREA()
now = now + 1
route(destination, spot(1, auberdine.x - 49, auberdine.y, 1439))
assert(searches == before + 1, "one search for the zone transition")
for i=1,20 do
	now = now + 0.5
	aim(destination, spot(1, auberdine.x - 49 - i*3, auberdine.y, 1439))
end
assert(searches == before + 1, "ordinary movement should reuse the plan")

-- The player can also move on deck. Reaching a different dock in the same
-- zone refreshes even when the ship wasn't a leg and no zone event fired.
setting("travelTransports", false)
local mainland = spot(1, -4346.9, 2430.2, 1444)
local island = spot(1, -4209.4, 3290.6, 1444)
local islandQuest = spot(1, -4400, 3550, 1444)
route(islandQuest, mainland)
before = searches
for i=1,24 do
	now = now + 0.5
	local here = spot(1, mainland.x + (island.x-mainland.x)*i/24,
		mainland.y + (island.y-mainland.y)*i/24, 1444)
	route(islandQuest, here)
end
assert(searches == before + 1, "one search on arrival at an unplanned dock")
for i=1,8 do now = now + 0.5; route(islandQuest, island) end
assert(searches == before + 1, "staying at the dock reuses the route")

-- A location change can interrupt a search between frame slices. Its
-- old departure must never be published after arriving in another zone.
setting("travelTransports", true)
local goal = spot(0, -9000, 700, 1453)
aim(goal, darn)
assert(job and coroutine.resume(job))
aim(goal, sw)
drain()
local stopAfterJump, instructionAfterJump = route(goal, sw)
assert(not stopAfterJump and not instructionAfterJump, "walk from the new position after cancelling the old search")

-- The walking search refuses starts it cannot verify (rough ground, no player
-- height), so a failure says nothing about the destination. On the road below
-- Sun Rock Retreat (Stonetalon 52.6, 55.8), 375 yards from a Gaea Seed, a failed
-- search once sent the arrow 2,388 yards to Thunder Bluff to fly back to Sun Rock.
ns.playerFaction = 2
assert(loadfile(base .. "Travel.lua"))()
T = ns.Travel
T:OnLogin()
openTaxiMap({ { nodeID=29, state=0 }, { nodeID=22, state=1 }, { nodeID=25, state=1 } })
setting("travelFlights", true)
local sunRockRoad = spot(1, 1099.7, 677.2, 1442)
local gaeaSeed = spot(1, 1447.8, 816.9, 1442)
local standing = sunRockRoad
ns.GetPlayerWorld = function() return standing.c, standing.x, standing.y, standing.m end
assert(not route(gaeaSeed, sunRockRoad), "walk to a nearby quest")
T:WalkFailed(gaeaSeed)
local seedStop, seedAction, seedCaption = route(gaeaSeed, sunRockRoad)
assert(not seedStop and not seedAction, "a failed search keeps the short walk: " .. tostring(seedCaption))
before = searches
T:WalkFailed(gaeaSeed)
assert(not route(gaeaSeed, sunRockRoad) and searches == before, "the same failure again is already priced in")

-- Beside Sun Rock's master, a flight beats walking to the Crossroads. When the
-- search to the master fails, keep that flight rather than trying farther masters.
local byMaster = spot(1, 990, 1040, 1442)
local crossroadsQuest = spot(1, -480, -2600, 1413)
standing = byMaster
local master = route(crossroadsQuest, byMaster)
assert(master and master.taxi == 29, "fly from Sun Rock: " .. tostring(master and master.n))
T:WalkFailed(master)
local masterAgain = route(crossroadsQuest, byMaster)
assert(masterAgain and masterAgain.taxi == 29, "keep Sun Rock's flight: " .. tostring(masterAgain and masterAgain.n))

-- Freewind was in the old cache even though the character had only learned
-- nearby Camp Taurajo. Test the upgrade before the first flight map opens.
local freewind = spot(1, -5407.7, -2414.3, 1441)
waypoint = freewind
ns.db.knownFlights.tester = { [22]=true, [77]=true, [30]=true }
Polestar = { Nav = { GetKnownTaxiNodes = function() return { [30]=true } end } }
ForeverDungeonJournal_NS = { FoundFlightNames = function()
	return { ["thunder bluff, mulgore"]=true, ["camp taurajo, the barrens"]=true }
end }
assert(loadfile(base .. "Travel.lua"))()
T = ns.Travel
T:OnLogin()
T:ObserveTaxi(30, false) -- a visible zone-map pin on Forever
assert(not ns.db.knownFlights.tester[30], "a world-map pin and the legacy cache cannot unlock Freewind")
assert(select(2, route(freewind, bluff)) == flyToCamp, "use the confirmed Taurajo flight on the way to Freewind")
assert(select(2, T:GetRecommendedFlight()).taxi == 77)

local kind = "DISTANT"
NumTaxiNodes = function() return 2 end
TaxiNodeGetType = function(slot) return slot == 1 and "CURRENT" or kind end
local listed = { { nodeID=22, state=0, slotIndex=1 }, { nodeID=30, state=1, slotIndex=2 } }
openTaxiMap(listed)
assert(not ns.db.knownFlights.tester[30], "a DISTANT flight-master slot overrides a positive map row")
kind = "REACHABLE"
events.TAXI_NODE_STATUS_CHANGED()
assert(select(2, route(freewind, bluff)) == "Fly to Freewind Post, Thousand Needles")
kind = "DISTANT"
events.TAXI_NODE_STATUS_CHANGED()
assert(not T:GetRecommendedFlight(), "withdraw a stale flight even while standing at its master")
assert(select(2, route(freewind, bluff)) == flyToCamp)

-- Repeat during a suspended route search and then reload the character.
kind = "REACHABLE"
openTaxiMap(listed)
T:Reset()
aim(freewind, bluff)
assert(job and coroutine.resume(job))
kind = "DISTANT"
events.TAXI_NODE_STATUS_CHANGED()
drain()
assert(not T:GetRecommendedFlight() and select(2, route(freewind, bluff)) == flyToCamp)
events.TAXIMAP_CLOSED()
kind = "REACHABLE"
events.TAXI_NODE_STATUS_CHANGED()
assert(not ns.db.knownFlights.tester[30], "ignore status changes after the map closes")
ForeverDungeonJournal_NS = nil
assert(loadfile(base .. "Travel.lua"))()
T = ns.Travel
T:OnLogin()
assert(select(2, route(freewind, bluff)) == flyToCamp, "retain verified flights across reloads")
TaxiNodeName = function(slot) return slot == 1 and "Thunder Bluff, Mulgore" or "Freewind Post, Thousand Needles" end
C_TaxiMap = nil
events.TAXIMAP_OPENED()
assert(select(2, route(freewind, bluff)) == "Fly to Freewind Post, Thousand Needles", "learn from classic slots alone")

print("Waypoint travel: faction crossings, hearth, confirmed flights, loading screens, alternate landings and zone changes passed")
