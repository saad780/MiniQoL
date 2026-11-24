local root = ...
local now, first, surname, realm, guid = 100, "Tess", "Vale", "Home", "Player-71-AA"
function time() return now end
function GetRealmName() return realm end
function RegionalUniqueNamesEnabled() return true end
function UnitName() return first, surname end
function UnitGUID() return guid end
function UnitClass() return "Mage", "MAGE" end
function UnitLevel() return 12 end
function issecretvalue(value) return value == "SECRET" end
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function drain()
    local iterations = 0
    while #timers > 0 do
        iterations = iterations + 1
        assert(iterations <= 8, "bounded retries")
        table.remove(timers, 1)()
    end
end
function CreateFrame()
    return { RegisterEvent = function() end, SetScript = function(self, _, fn) self.fire = fn end }
end
Enum = { BagIndex = { ReagentBag = 2, CharacterBankTab_1 = 6, CharacterBankTab_2 = 7,
    CharacterBankTab_9 = 14, AccountBankTab_1 = 15 }, BankType = { Character = 1, Account = 2 } }
local bags = { [0] = {}, {}, {}, [6] = {}, [7] = {}, [15] = {} }
local function item(id, count) return { itemID = id, stackCount = count, hyperlink = "item:" .. id } end
bags[0][1], bags[1][1], bags[2][2] = item(100, 3), item(100, 4), item(101, 2)
bags[6][1], bags[7][1], bags[15][1] = item(102, 5), item(102, 8), item(999, 9)
local reads, missing = {}, {}
C_Container = {
    GetContainerNumSlots = function(bag) return bags[bag] and 2 or 0 end,
    GetContainerItemInfo = function(bag, slot)
        reads[bag] = (reads[bag] or 0) + 1
        if not missing[bag] then return bags[bag][slot] end
    end,
    GetContainerNumFreeSlots = function(bag)
        local free = 2
        for _ in pairs(bags[bag]) do free = free - 1 end
        return free
    end,
}
C_Bank = { FetchPurchasedBankTabData = function(kind) assert(kind == 1); return { {}, {} } end }
local map, zone, x, y = 12, "River", 0.4, 0.7
function GetRealZoneText() return zone end
C_Map = { GetBestMapForUnit = function() return map end,
    GetPlayerMapPosition = function() return { GetXY = function() return x, y end } end }

local db = {
    mail = { characters = { old = { name = "Tess Vale", realm = realm, seen = 15 } }, sent = { Home = {} } },
    altGear = { enabled = false, characters = {
        old = { name = "Tess", realm = realm, saved = 25, items = { [1] = "item:44" } },
        full = { name = "Tess Vale", realm = realm, saved = 28, items = { [2] = "item:45" } },
    } },
}
local function login()
    local ns = { db = db }
    assert(loadfile(root .. "/Characters.lua"))("MiniQoL", ns)
    ns.Characters:Start()
    return ns.Characters, ns.Characters.events
end
QuestieConfig = { char = { ["Orla Moss"] = { guid = "Player-71-BB" }, ["Orla Snow"] = { guid = "Player-99-CC" } } }
local service, events = login()
local a = service:Current()
assert(not db.altGear.characters and not db.mail.characters and db.mail.sent.Home and db.altGear.enabled == false)
assert(db.characters["tess@Home"].items[1] and not db.characters["tess@Home"].address, "ambiguous old gear stays recoverable")
assert(a.items[2] == "item:45" and a.name == "Tess Vale" and a.class == "MAGE")
assert(db.characters["orla moss@Home"].address and not db.characters["orla snow@Home"])
events:fire("PLAYER_ENTERING_WORLD")
assert(a.location.x == x and a.bags[0][100] == 3 and a.bags[1][100] == 4 and a.bags[2][101] == 2)
reads = {}
bags[0][1], bags[1][1], missing[1] = item(100, 7), item(202, 1), true
for _, id in ipairs({ 0, 0, 1, 1 }) do events:fire("BAG_UPDATE", id) end
events:fire("BAG_UPDATE_DELAYED")
assert(a.bags[0][100] == 3 and a.bags[1][100] == 4, "a partial read cannot double-count a moved stack")
missing[1] = nil
drain()
assert(a.bags[0][100] == 7 and a.bags[1][202] == 1 and not a.bags[1][100] and not reads[2])
bags[2] = nil
events:fire("BAG_UPDATE", 2)
events:fire("BAG_UPDATE_DELAYED")
assert(not next(a.bags[2]), "an unequipped bag no longer owns items")
events:fire("BANKFRAME_OPENED")
drain()
assert(a.bank[102] == 13 and a.bankLinks[102] == "item:102" and not reads[15])
bags[6][1], missing[7] = nil, true
events:fire("PLAYERBANKSLOTS_CHANGED", 1)
drain()
assert(a.bank[102] == 13, "an unreadable purchased tab preserves the complete snapshot")
missing[7], bags[7][1] = nil, nil
events:fire("BAG_UPDATE", 7)
drain()
assert(a.bankSeen and not next(a.bank) and not next(a.bankLinks), "a verified empty bank clears old stock")
events:fire("BANKFRAME_CLOSED")
map, zone, x, y = 25, "Hill", 0, 0
events:fire("ZONE_CHANGED_NEW_AREA")
assert(a.location.mapID == 25 and not a.location.x, "zone changes discard coordinates from the previous zone")
x, y = 0.1, 0.6
events:fire("PLAYER_LOGOUT")
assert(a.location.x == x and a.location.y == y)

QuestieConfig = nil
surname, guid = "Marsh", "Player-71-DD"
service, events = login()
local b = service:Current()
assert(b ~= a and b.name == "Tess Marsh" and not b.bags and not b.bank and not b.items and not b.location)
assert(service.records["orla moss@Home"].address, "an imported name survives a fresh session without addons")
surname, realm, guid = "Vale", "Elsewhere", "Player-92-AC"
service = login()
assert(service:Current() ~= a and a.bags[0][100] == 7, "the same full name on another realm has separate snapshots")
-- On Forever two physical realms can share the same regional name pool.
Enum.GameRule = { PvPRuleset = 1, RPRuleset = 2, HardcoreRuleset = 3 }
local pvp = true
C_GameRules = { IsGameRuleActive = function(rule) return rule == 1 and pvp end }
function GetCurrentRegion() return 1 end
realm, guid = "Home", "Player-71-AA"
service = login()
local shared = service:Current()
assert(shared.bags[0][100] == 7 and not db.characters["tess vale@Home"])
realm = "Second shard"
service = login()
assert(service:Current() == shared and service.records["orla moss@region1/PvP"].address)
pvp, realm, guid = false, "Normal shard", "Player-92-CA"
service = login()
assert(service:Current() ~= shared and not service:Current().bags, "PvE and PvP stay separate")
print("Character database: legacy migration, offline roster, separate owners, atomic bags and bank, and zone transitions passed")
