-- Wayfinder's character key on Forever, where realms have no name, and the
-- data the old key code filed under "unknown" going back to its character.
local package = ...
local ns = {}
local onEvent
function CreateFrame()
	return { RegisterEvent = function() end, SetScript = function(_, _, fn) onEvent = fn end }
end
function securecallfunction(fn, ...) return fn(...) end
C_AddOns = { GetAddOnMetadata = function() return "test" end }
SlashCmdList, StaticPopupDialogs, UNKNOWNOBJECT = {}, {}, "Unknown"
bit = nil -- the client has bit.bor; the fallback must agree with it

-- Forever today: no realm name and realm ID 0; UnitName's second return is the surname.
local realm, normalized, realmID = "", "", 0
local first, surname, guid = "Firouzi", "Asman", "Player-6922-02C4B2FB"
function GetRealmName() return realm end
function GetNormalizedRealmName() return normalized end
function GetRealmID() return realmID end
function UnitName() return first, surname end
function UnitGUID() return guid end
function UnitFactionGroup() return "Horde" end
function UnitClass() return "Rogue", "ROGUE" end
function UnitRace() return "Skyborne", "Skyborne" end
MiniQoLRuntime = { Execute = function(_, name, fn) fn(name, ns) end }

local function equal(actual, expected, message)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(message, tostring(expected), tostring(actual)), 2)
	end
end

local function rows(value)
	local r = {}
	for i = 1, 16 do r[i] = value end
	return r
end

local OLD, FIROUZI = "Firouzi-CAMWOWUS1Realm4PvP", "Firouzi Asman-6922"
local staleList = { { n = "Go across bridge" } }
local currentList = { { n = "Turn in Boulderslide Ravine" } }
local bound = { n = "Sun Rock Retreat" }
-- As in the saved variables: Firouzi's data from before the realms lost their
-- names, everything since under "unknown", and another character's own key.
WayfinderDB = {
	settings = {},
	explored = {
		[OLD] = { [1] = { [3030] = rows(0x00FF), [3031] = rows(1) } },
		unknown = { [1] = { [3030] = rows(0xFF00), [3729] = rows(2) }, [0] = { [10] = rows(4) } },
		["Azonei-CAMWOWUS1Realm4PvP"] = { [0] = { [11] = rows(8) } },
	},
	imported = { [OLD] = { [1411] = true }, unknown = { [1442] = true } },
	waypoints = {
		[OLD] = { list = staleList, active = 1 },
		unknown = { list = currentList, active = 1 },
		["Azonei-CAMWOWUS1Realm4PvP"] = { list = {}, active = nil },
	},
	questAvailability = {
		[OLD] = { npcA = { [1] = {} }, npcB = { [2] = { repeatable = true } } },
		unknown = { npcB = { [3] = {} }, npcC = { [4] = {} } },
	},
	knownFlights = { unknown = { [22] = true, [29] = true } },
	targetFinder = { unknown = { manual = { { kind = "any", name = "deepmoss" } }, quests = {} } },
	hearthBinds = { unknown = bound },
}

assert(loadfile(package .. "/Modules/Wayfinder/Core.lua"))()
onEvent(nil, "ADDON_LOADED", "Wayfinder")
onEvent(nil, "PLAYER_LOGIN")

local db = WayfinderDB
equal(ns:GetCharacterKey(), FIROUZI, "a Forever realm keys by full name and the GUID's server")
for field in pairs({ explored = 1, imported = 1, waypoints = 1, questAvailability = 1,
		knownFlights = 1, targetFinder = 1, hearthBinds = 1 }) do
	equal(db[field].unknown, nil, field .. ": nothing is left under unknown")
	equal(db[field][OLD], nil, field .. ": nor under the old realm key")
end
local explored = db.explored[FIROUZI]
equal(explored[1][3030][5], 0xFFFF, "cells explored under either key are both kept")
equal(explored[1][3031][1], 1, "tiles only the old key had")
equal(explored[1][3729][1], 2, "tiles only unknown had")
equal(explored[0][10][1], 4, "another continent")
equal(db.explored["Azonei-CAMWOWUS1Realm4PvP"][0][11][1], 8, "other characters keep their data")
assert(db.imported[FIROUZI][1411] and db.imported[FIROUZI][1442], "imported maps from both")
equal(db.waypoints[FIROUZI].list, currentList, "the waypoints shown lately win over the stale list")
local quests = db.questAvailability[FIROUZI]
assert(quests.npcA[1] and quests.npcC[4], "NPCs from both copies")
assert(quests.npcB[3] and not quests.npcB[2], "the newer copy of one NPC's offers wins")
assert(db.knownFlights[FIROUZI][22] and db.knownFlights[FIROUZI][29], "known flights")
equal(db.targetFinder[FIROUZI].manual[1].name, "deepmoss", "Target Finder's list")
equal(db.hearthBinds[FIROUZI], bound, "hearth bind")

-- A /reload or the next login moves nothing again.
ns:MigrateCharacterData()
equal(db.waypoints[FIROUZI].list, currentList, "the second pass leaves the data alone")

-- Data written under "unknown" later is folded in as the newer copy.
db.knownFlights.unknown = { [25] = true }
ns:MigrateCharacterData()
assert(db.knownFlights[FIROUZI][25] and db.knownFlights[FIROUZI][22] and not db.knownFlights.unknown,
	"a later unknown copy joins the character's")

-- Two old keys with one first name: whose is whose is unknowable, so neither moves.
local function login(name, last, id)
	first, surname, guid = name, last, id
	ns.charKey = nil
	ns:MigrateCharacterData()
	return ns:GetCharacterKey()
end
db.waypoints["Deca-RealmOne"] = { list = { { n = "one" } } }
db.waypoints["Deca-RealmTwo"] = { list = { { n = "two" } } }
equal(login("Deca", "Dant", "Player-6922-00000001"), "Deca Dant-6922", "the full name, without a realm")
assert(db.waypoints["Deca-RealmOne"] and db.waypoints["Deca-RealmTwo"] and not db.waypoints["Deca Dant-6922"],
	"ambiguous old keys stay where they are")
-- Nor does a Forever key that merely shares the first name.
db.waypoints["Reco Other-7000"] = { list = { { n = "other" } } }
equal(login("Reco", "Veri", "Player-6922-00000002"), "Reco Veri-6922", "another Reco")
assert(db.waypoints["Reco Other-7000"] and not db.waypoints["Reco Veri-6922"], "another server's Reco keeps its own")

-- No GUID yet: no key, and nothing moves.
db.waypoints.unknown = { list = {} }
equal(login("Chaku", "Inya", nil), "unknown", "no key before the client has the GUID")
assert(db.waypoints.unknown, "and unknown stays put")

-- A realm with a name keeps the old "Name-NormalizedRealm" key. Early in loading
-- GetNormalizedRealmName can be empty while GetRealmName has the name.
realm, normalized, realmID = "CAMWOW US1 Realm-4 PvP", "", 91
db.waypoints["Azonei-OtherRealm"] = { list = { { n = "a namesake elsewhere" } } }
equal(login("Azonei", nil, "Player-6922-00000003"), "Azonei-CAMWOWUS1Realm4PvP", "GetRealmName, normalized")
assert(db.waypoints["Azonei-OtherRealm"], "a named realm never takes a namesake's key")
assert(not db.waypoints.unknown and db.waypoints["Azonei-CAMWOWUS1Realm4PvP"], "but does take unknown")
-- A realm with an ID but no name yet has no key: it is not a Forever realm.
realm, normalized, realmID = "", "", 91
equal(login("Alt", "Banki", "Player-6922-00000004"), "unknown", "a named realm not yet named")

print("Character key: Forever full name and server, old realm keys and unknown data moved once, ambiguity left alone passed")
