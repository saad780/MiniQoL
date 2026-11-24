-- Reading an item: every comparison starts from the stats found here. The
-- tooltips are written the way the game writes them, with the item API silent
-- unless a case says otherwise, so each line has to be understood on its own.
local gearwise = ...

local function noop() end
function CreateFrame() return setmetatable({}, { __index = function() return noop end }) end
function GetTime() return 100 end

local WHITE, RED = { r = 1, g = 1, b = 1 }, { r = 1, g = 0.13, b = 0.13 }
local ITEMS = {}
local function Link(id) return "|cffffffff|Hitem:" .. id .. "::::|h[Item " .. id .. "]|h|r" end
local function ID(link) return tonumber(link:match("item:(%d+)")) end
C_Item = {
    GetItemInfo = function(link)
        local item = ITEMS[ID(link)]
        return item.name or "Item " .. ID(link), link, 2, 30, item.level or 0, "Type", "Kind", 1, item.loc, 1, 100,
            item.classID or 4, item.subclassID or 0, 0, 0, nil, item.setID
    end,
    GetItemStats = function(link) return ITEMS[ID(link)].api or {} end,
}
C_TooltipInfo = { GetHyperlink = function(link)
    local lines = { { leftText = "Item " .. ID(link), leftColor = WHITE } }
    for _, line in ipairs(ITEMS[ID(link)].lines) do
        if type(line) == "string" then line = { line } end
        lines[#lines + 1] = { leftText = line[1], leftColor = line.red and RED or WHITE,
            rightText = line[2], rightColor = line.rightRed and RED or WHITE }
    end
    return { lines = lines }
end }

local ns = {}
-- The packaged copy runs inside the bundle's module adapter.
MiniQoLRuntime = { Execute = function(_, name, chunk) return chunk(name, ns) end }
for _, file in ipairs({ "Core.lua", "EffectData.lua", "Effects.lua", "Items.lua", "Compare.lua" }) do
    assert(loadfile(gearwise .. "/" .. file))("Gearwise", ns)
end

local nextID = 0
-- Reads one tooltip and checks the stats named; `absent` lists stats that
-- must not have been found.
local function Read(label, definition, expected, absent)
    nextID = nextID + 1
    definition.loc = definition.loc or "INVTYPE_CHEST"
    ITEMS[nextID] = definition
    local item, status = ns.Items:Get(Link(nextID))
    assert(item, label .. ": not read (" .. tostring(status) .. " / " .. tostring(ns.Items.lastError) .. ")")
    for key, value in pairs(expected or {}) do
        local found = item.stats[key]
        assert(found and math.abs(found - value) < 0.001, ("%s: %s is %s, not %s"):format(label, key, tostring(found), value))
    end
    for _, key in ipairs(absent or {}) do
        assert(not item.stats[key], ("%s: %s should not be there (%s)"):format(label, key, tostring(item.stats[key])))
    end
    return item
end

-- 1. Plate for a warrior, the way the old tooltips put attack power.
Read("attack power", { lines = { "Chest", "577 Armor", "+12 Strength", "+10 Stamina",
    "Equip: +30 Attack Power.", "Equip: Improves your chance to get a critical strike by 1%." } },
    { armor = 577, str = 12, sta = 10, ap = 30, crit = 1 })
--    And the way the later ones do.
Read("attack power, later wording", { lines = { "Equip: Increases attack power by 28." } }, { ap = 28 })

-- 2. A druid's and a hunter's kind are their own stats, not general ones.
Read("feral attack power", { lines = { "Equip: +40 Attack Power in Cat, Bear, and Dire Bear forms only." } },
    { feralAP = 40 }, { "ap" })
Read("ranged attack power", { lines = { "Equip: +24 ranged Attack Power." } }, { rap = 24 }, { "ap" })

-- 3. A tank's shield: its own block, the block it adds, and defense.
Read("shield", { loc = "INVTYPE_SHIELD", subclassID = 6, lines = { { "Off Hand", "Shield" }, "2121 Armor", "39 Block",
    "+10 Stamina", "Equip: Increased Defense +7.", "Equip: Increases the block value of your shield by 23.",
    "Equip: Increases your chance to block attacks with a shield by 2%." } },
    { armor = 2121, blockValue = 62, sta = 10, defense = 7, block = 2 })

-- 4. A caster's robe.
Read("caster", { lines = { "+15 Intellect",
    "Equip: Increases damage and healing done by magical spells and effects by up to 12.",
    "Equip: Increases damage done by Shadow spells and effects by up to 14.",
    "Equip: Restores 4 mana per 5 sec.", "Equip: Improves your chance to hit with spells by 1%." } },
    { int = 15, sp = 12, shadow = 14, mp5 = 4, hit = 1 }, { "heal" })

-- 5. A healer's, in both wordings.
Read("healing", { lines = { "Equip: Increases healing done by spells and effects by up to 44." } }, { heal = 44 }, { "sp" })
Read("healing with some damage", { lines = {
    "Equip: Increases healing done by up to 44 and damage done by up to 15 for all magical spells and effects." } },
    { heal = 44, sp = 15 })

-- 6. A line that names spells is not thereby healing. Spell haste used to be
--    scored as that much healing, and so did spell penetration.
Read("spell haste", { lines = { "Equip: Improves spell haste rating by 20." } }, { hasteRating = 20 }, { "heal", "sp" })
local penetration = Read("spell penetration", { lines = { "Equip: Increases your spell penetration by 10." } }, nil,
    { "heal", "sp" })
assert(penetration.effects, "spell penetration is noted as something the score leaves out")
Read("ratings", { lines = { "Equip: Improves critical strike rating by 14.", "Equip: Increases your hit rating by 10.",
    "Equip: Increases your expertise rating by 12.", "Equip: Improves haste rating by 9." } },
    { critRating = 14, hitRating = 10, expertiseRating = 12, hasteRating = 9 })

-- 7. What the item API reports and what the tooltip says are one statement,
--    counted once; an enchant on top of it is counted too.
Read("the API and the tooltip agree", { api = { ITEM_MOD_ATTACK_POWER_SHORT = 30, ITEM_MOD_STAMINA_SHORT = 5 },
    lines = { "+5 Stamina", "Equip: +30 Attack Power." } }, { ap = 30, sta = 5 })
Read("an enchant", { api = { ITEM_MOD_STAMINA_SHORT = 5 }, lines = { "+5 Stamina", "+7 Stamina" } }, { sta = 12 })

-- 8. A weapon's damage, exact from its range and speed when the API is silent.
local sword = Read("weapon", { loc = "INVTYPE_WEAPON", classID = 2, subclassID = 7, lines = { { "One-Hand", "Sword" },
    { "43 - 81 Damage", "Speed 2.60" }, "(23.8 damage per second)", "+7 Agility", "Chance on hit: Wounds the target." } },
    { dps = (43 + 81) / (2 * 2.6), agi = 7 })
assert(sword.effects, "a proc is noted as unscored")
local buff = Read("temporary equip buffs", { lines = {
    "Equip: Your critical strikes have a chance to increase attack power by 100 for 10 sec.",
    "Equip: 2% chance on spellcast to increase your spell damage by 35." } }, nil, { "crit", "ap", "sp" })
assert(buff.effects, "trigger chances and temporary bonuses are flagged for manual comparison")

-- 9. Requirements. A level is compared as a number elsewhere; red text that
--    names a class or an untrained kind of armor is a restriction.
local early = Read("a level not yet reached", { level = 40, lines = { "+9 Strength",
    { "Requires Level 40", red = true } } }, { str = 9 })
assert(early.level == 40 and not early.restriction, "the level is kept as a number, not as red text")
local classed = Read("another class", { lines = { { "Classes: Mage", red = true } } })
assert(classed.restriction == "Classes: Mage", "a class line is a restriction")
local mail = Read("untrained armor", { lines = { { "Chest", "Mail", rightRed = true }, "210 Armor" } }, { armor = 210 })
assert(mail.restriction == "Mail", "so is an armor type in red")
local skilled = Read("a profession", { lines = { { "Requires Engineering (150)", red = true } } })
assert(skilled.restriction, "and a skill you lack")

-- 10. Item data arriving: only what was asked for counts as an answer.
assert(not ns.Items:Arrived(424242), "an item nobody here asked about is someone else's")
ns.Items:Request(424242)
assert(ns.Items:Arrived(424242), "one that was asked for is")
assert(not ns.Items:Arrived(424242), "once")

print("Items: attack power, block, defense, ratings, healing and requirements read off the tooltip")

-- Exercise complete comparisons with the live tooltip wording, pinned rate
-- and set IDs. Only the supplied equipment and storage are simulated.
local worn, carried, banked = {}, {}, {}
function wipe(t) for k in pairs(t) do t[k] = nil end end
function GetInventoryItemLink(_, slot) return worn[slot] and Link(worn[slot]) end
function C_Item.GetItemCount(id, bank) return (carried[id] or 0) + (bank and banked[id] or 0) end
ns.profile = {class="HUNTER", level=60, shoots=true, rangedDPS=15, meleeDPS=1, weights={ap=1,rap=1,int=1,agi=1}}
local function check(id)
    ns.Compare:Clear()
    ns.Items:Clear()
    local r = ns.Compare:Get(Link(id))
    assert(r.delta, "no comparison for " .. id .. ": " .. tostring(ns.Compare.lastError or ns.Items.lastError))
    return r, table.concat(r.effectNotes or {}, "\n")
end
local function near(a,b) assert(math.abs(a-b) < 0.0001, tostring(a) .. " vs " .. tostring(b)) end
local function bow(dps, effect)
    return {loc="INVTYPE_RANGED", classID=2, subclassID=2, api={ITEM_MOD_DAMAGE_PER_SECOND_SHORT=dps},
        lines={{"Ranged","Speed 2.00"},effect}}
end
ITEMS[6469] = bow(12.1, "Chance on hit: Venom Shot the target for 23 to 33 Nature damage.")
ITEMS[900001] = bow(12.6)
worn[18] = 900001
local r, notes = check(6469)
near(r.delta, (12.1 + 28*1.85/60 - 12.6)*15)
assert(r.status=="upgrade" and notes:find("1.85 procs/min, observed", 1, true) and not r.effects)
worn[18] = 6469
r = check(900001)
assert(r.status=="downgrade", "deduct the replaced weapon's proc")
ITEMS[900002] = bow(12.1, "Chance on hit: Fires a bolt for 20 to 40 Fire damage.")
worn[18] = 900001
r, notes = check(900002)
near(r.breakEven,1)
assert(r.status=="downgrade" and notes:find("1.00 procs/min", 1, true))
ITEMS[900003] = bow(12.1, "Chance on hit: 10% chance to deal 20 to 40 Fire damage.")
r = check(900003)
near(r.delta, (12.1 + 30*0.1/2 - 12.6)*15)
ITEMS[900004] = bow(12.1, "Chance on hit: Deals 20 Fire damage every 2 sec for 10 sec.")
r = check(900004)
assert(r.effects and not r.breakEven and r.status=="downgrade")
ITEMS[900005] = bow(12.1, "Chance on hit: 10% chance to increase your agility by 30 for 10 sec.")
r, notes = check(900005)
near(r.delta, (12.1-12.6)*15 + 30*(1-math.exp(-0.5)))
assert(notes:find("uptime"))
ITEMS[900008] = {loc="INVTYPE_TRINKET", lines={"Equip: Your melee attacks have a 5% chance to deal 60 Fire damage."}}
function UnitAttackSpeed() return 2, 3 end
r, notes = check(900008)
near(r.delta, 60*0.05*(1/2+1/3))
assert(notes:find("per landed swing"), "explicit on-hit jewelry can use both weapon speeds")

local function viper(slot, name, active)
    return {loc=slot, name=name, setID=162, lines={active and "Embrace of the Viper (2/5)" or "Embrace of the Viper (1/5)",
        active and "Set: +10 Intellect." or "(2) Set: +10 Intellect.", "(3) Set: +10 Attack Power.",
        "(4) Set: A chance to heal you.", "(5) Set: +10 Stamina."}}
end
ITEMS[6473] = viper("INVTYPE_CHEST","Armor of the Fang")
ITEMS[10410] = viper("INVTYPE_LEGS","Leggings of the Fang")
ITEMS[10411] = viper("INVTYPE_FEET","Footpads of the Fang")
ITEMS[900006] = {loc="INVTYPE_LEGS", lines={"+5 Agility"}}
worn[5], worn[7] = 6473, 900006
r, notes = check(10410)
near(r.delta,5)
assert(notes:find("Gain 2%-piece") and r.status=="upgrade")
worn[7] = 10410
ITEMS[10410] = viper("INVTYPE_LEGS","Leggings of the Fang",true)
r, notes = check(900006)
near(r.delta,-5)
assert(notes:find("Lose 2%-piece"), "resolve active lines which omit their threshold")
worn[7] = 900006
worn[5] = nil
banked[6473] = 2
r, notes = check(10410)
near(r.delta,-5)
assert(r.setPlan == 10 and notes:find("Armor of the Fang %(bank%)") and notes:find("0 in bags, 1 in bank"))
assert(notes:find("combined change %+5.0 score"), "include both replacements in the projected gain")

-- Older set estimates report only the bonus available from a stored piece.
local detailedSets = ns.Effects.Sets
ns.Effects.Sets = function(...)
    local lost, gained, review, plan = detailedSets(...)
    return lost, gained, review, plan and plan.value
end
r, notes = check(10410)
near(r.delta, -5)
assert(r.status == "downgrade" and r.setPlan == 10 and not notes:find("combined change", 1, true),
    "a bonus-only plan remains a preview without inventing a combined gear score")
ns.Effects.Sets = detailedSets
ITEMS[900007] = {loc="INVTYPE_CHEST", lines={"+15 Agility"}}
worn[5] = 900007
r, notes = check(10410)
assert(not r.setPlan and notes:find("combined change %-10.0 score"), "a banked piece can cost more than the bonus")
worn[5] = nil
carried[6473], banked[6473] = 1, nil
r, notes = check(10410)
assert(r.setPlan == 10 and notes:find("Armor of the Fang %(bags%)"))
carried[6473], carried[10410] = nil, 5
r = check(10410)
assert(not r.setPlan, "duplicates of the candidate cannot unlock another tier")
Syndicator = {API={GetCurrentCharacter=function() return "Test-Realm" end, GetCharacter=function(key)
    assert(key=="Test-Realm")
    return {bankTabs={{slots={{itemID=10411}}}}}
end}}
r, notes = check(10410)
assert(r.setPlan == 10 and notes:find("Footpads of the Fang %(bank, last seen%)"))
local snapshot = { bankSeen = 123, bankLinks = {} }
MiniQoL = { Characters = { Current = function() return snapshot end } }
r = check(10410)
assert(not r.setPlan, "a verified empty personal bank supersedes Syndicator")
Syndicator = nil
snapshot.bankLinks[10411] = true
r, notes = check(10410)
assert(r.setPlan == 10 and notes:find("Footpads of the Fang %(bank, last seen%)"), "native bank history without Syndicator")
MiniQoL = nil
banked[10411], banked[6473] = 1, 1
-- A three-piece as the first threshold needs two stored partners at once.
ITEMS[10410].lines = {"Embrace of the Viper (0/5)", "(3) Set: +10 Attack Power."}
r, notes = check(10410)
assert(r.setPlan == 10 and notes:find("Armor of the Fang %+ Footpads of the Fang") and notes:find("combined change %+5.0"))
ITEMS[10411].loc = "INVTYPE_CHEST"
r = check(10410)
assert(not r.setPlan, "two pieces competing for one armor slot cannot complete a three-piece")
print("Weapon proc estimates, break-even rates, set thresholds and personal bank planning passed")
