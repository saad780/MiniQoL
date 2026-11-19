-- What each build is advised, with the real builds and the real comparison.
-- Three kinds of advice were wrong for a whole class at a time:
--   a rogue's or a warrior's ranged weapon was never judged by its damage, so
--     a better throwing knife tied with the worse one and was never offered;
--   a hunter was offered a throwing weapon over a bow that hit less hard;
--   a tank was offered a second weapon in place of the shield.
local gearwise, shell = ...

local function noop() end

-- Anything not spelled out is a no-op, so the prompt builds as it would.
local methods = {}
local frame = {}
frame.__index = function(_, key)
    if methods[key] then return methods[key] end
    if type(key) == "string" and key:match("^%u") then return noop end
end
function methods:SetScript(key, fn) self.handlers[key] = fn end
function methods:GetScript(key) return self.handlers[key] end
function methods:SetShown(value)
    value = value and true or false
    if value == self.shown then return end
    self.shown = value
    local script = self.handlers[value and "OnShow" or "OnHide"]
    if script then script(self) end
end
function methods:Show() self:SetShown(true) end
function methods:Hide() self:SetShown(false) end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown end
function methods:SetText(value) self.text = value end
function methods:GetText() return self.text end
function methods:GetStringHeight() return 14 end
function methods:GetFrameLevel() return 1 end
function methods:CreateTexture() return setmetatable({ handlers = {}, shown = true, parent = self }, frame) end
function methods:CreateFontString() return setmetatable({ handlers = {}, shown = true, parent = self }, frame) end
function CreateFrame(kind, name, parent, template)
    local f = setmetatable({ kind = kind, handlers = {}, shown = true, parent = parent, template = template }, frame)
    if name then _G[name] = f end
    return f
end
UIParent = CreateFrame("Frame")
GameTooltip = { SetOwner = noop, SetHyperlink = noop, Show = noop, Hide = noop }
function InCombatLockdown() return false end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function CanDualWield() return true end

local TIMERS = {}
C_Timer = { After = function(_, fn) TIMERS[#TIMERS + 1] = fn end }
local function Settle()
    for _ = 1, 20 do
        if #TIMERS == 0 then return end
        local due = TIMERS
        TIMERS = {}
        for _, fn in ipairs(due) do fn() end
    end
    error("timers never settled")
end

-- One weak and one strong plain weapon of every kind the ranged slot takes,
-- then the pieces the cases below weigh against each other.
local AXE2H, BOW, GUN, SWORD, STAFF, THROWN, CROSSBOW, WAND = 1, 2, 3, 7, 10, 16, 18, 19
local WEAPON, ARMOR = 2, 4
local ITEMS = {
    [2947] = { name = "Small Throwing Knife", loc = "INVTYPE_THROWN", subclassID = THROWN, stats = { dps = 2.5 } },
    [3107] = { name = "Keen Throwing Knife", loc = "INVTYPE_THROWN", subclassID = THROWN, stats = { dps = 3.8 } },
    [2504] = { name = "Worn Shortbow", loc = "INVTYPE_RANGED", subclassID = BOW, stats = { dps = 2.2 } },
    [2506] = { name = "Hornwood Recurve Bow", loc = "INVTYPE_RANGED", subclassID = BOW, stats = { dps = 4.2 } },
    [2508] = { name = "Old Blunderbuss", loc = "INVTYPE_RANGEDRIGHT", subclassID = GUN, stats = { dps = 2.3 } },
    [2509] = { name = "Ornate Blunderbuss", loc = "INVTYPE_RANGEDRIGHT", subclassID = GUN, stats = { dps = 5.1 } },
    [15807] = { name = "Light Crossbow", loc = "INVTYPE_RANGEDRIGHT", subclassID = CROSSBOW, stats = { dps = 3.1 } },
    [15808] = { name = "Fine Light Crossbow", loc = "INVTYPE_RANGEDRIGHT", subclassID = CROSSBOW, stats = { dps = 6.0 } },
    [5069] = { name = "Fire Wand", loc = "INVTYPE_RANGEDRIGHT", subclassID = WAND, stats = { dps = 9.0 } },
    [5347] = { name = "Pestilent Wand", loc = "INVTYPE_RANGEDRIGHT", subclassID = WAND, stats = { dps = 14.0 } },
    -- A bow worth wearing for what is on it, and a gun that only hits harder.
    [9001] = { name = "Bow of the Monkey", loc = "INVTYPE_RANGED", subclassID = BOW, stats = { dps = 9.0, agi = 3 } },
    [9002] = { name = "Heavy Rifle", loc = "INVTYPE_RANGEDRIGHT", subclassID = GUN, stats = { dps = 21.0 } },
    [9003] = { name = "Balanced Throwing Axe", loc = "INVTYPE_THROWN", subclassID = THROWN, stats = { dps = 30.0 } },
    -- Plain two-handers, and one with something on it.
    [9101] = { name = "Worn Battleaxe", loc = "INVTYPE_2HWEAPON", subclassID = AXE2H, stats = { dps = 10.0 } },
    [9102] = { name = "Heavy Battleaxe", loc = "INVTYPE_2HWEAPON", subclassID = AXE2H, stats = { dps = 14.0 } },
    [9103] = { name = "Stalker's Axe", loc = "INVTYPE_2HWEAPON", subclassID = AXE2H, stats = { dps = 9.0, agi = 4 } },
    [9111] = { name = "Gnarled Staff", loc = "INVTYPE_2HWEAPON", subclassID = STAFF, stats = { dps = 10.0 } },
    [9112] = { name = "Ironwood Staff", loc = "INVTYPE_2HWEAPON", subclassID = STAFF, stats = { dps = 14.0 } },
    -- A tank's hands.
    [9201] = { name = "Guard's Sword", loc = "INVTYPE_WEAPON", subclassID = SWORD, stats = { dps = 30.0 } },
    [9202] = { name = "Captain's Sword", loc = "INVTYPE_WEAPON", subclassID = SWORD, stats = { dps = 40.0 } },
    [9203] = { name = "Parrying Blade", loc = "INVTYPE_WEAPONOFFHAND", subclassID = SWORD, stats = { dps = 45.0 } },
    [9207] = { name = "Recruit's Sword", loc = "INVTYPE_WEAPON", subclassID = SWORD, stats = { dps = 20.0 } },
    [9208] = { name = "Officer's Sword", loc = "INVTYPE_WEAPON", subclassID = SWORD, stats = { dps = 34.0 } },
    [9209] = { name = "Soldier's Sword", loc = "INVTYPE_WEAPON", subclassID = SWORD, stats = { dps = 25.0 } },
    [9210] = { name = "Duelist's Blade", loc = "INVTYPE_WEAPONMAINHAND", subclassID = SWORD, stats = { dps = 30.0 } },
    [9204] = { name = "Round Buckler", loc = "INVTYPE_SHIELD", classID = ARMOR, subclassID = 6,
        stats = { armor = 400, blockValue = 10 } },
    [9205] = { name = "Kite Shield", loc = "INVTYPE_SHIELD", classID = ARMOR, subclassID = 6,
        stats = { armor = 600, blockValue = 14 } },
    [9206] = { name = "Orb of Vigor", loc = "INVTYPE_HOLDABLE", classID = ARMOR, subclassID = 0, stats = { sta = 30 } },
    -- Two rings a player might weigh differently from the build.
    [9301] = { name = "Band of Might", loc = "INVTYPE_FINGER", classID = ARMOR, subclassID = 0, stats = { str = 5 } },
    [9302] = { name = "Band of Grace", loc = "INVTYPE_FINGER", classID = ARMOR, subclassID = 0, stats = { agi = 3 } },
}
local PAIRS = { { 2947, 3107 }, { 2504, 2506 }, { 2508, 2509 }, { 15807, 15808 }, { 5069, 5347 } }
local function Link(id) return "|cffffffff|Hitem:" .. id .. "::::|h[" .. ITEMS[id].name .. "]|h|r" end
local function ID(link) return link and tonumber(link:match("item:(%d+)")) end

-- The character: what is worn, one bag, and the cursor between them.
EQUIPPED, BAG = {}, {}
local BAG_SIZE = 16
local cursor
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and BAG_SIZE or 0 end,
    GetContainerItemLink = function(bag, slot) return bag == 0 and BAG[slot] or nil end,
    GetContainerItemID = function(bag, slot) return bag == 0 and ID(BAG[slot]) or nil end,
    GetContainerItemInfo = function(bag, slot) return bag == 0 and BAG[slot] and { stackCount = 1 } or nil end,
    PickupContainerItem = function(bag, slot) cursor = { link = BAG[slot], slot = slot } end,
}
function GetInventoryItemLink(_, slot) return EQUIPPED[slot] end
function GetInventoryItemID(_, slot) return ID(EQUIPPED[slot]) end
function CursorHasItem() return cursor ~= nil end
function ClearCursor() cursor = nil end
function EquipCursorItem(slot)
    EQUIPPED[slot], BAG[cursor.slot] = cursor.link, EQUIPPED[slot]
    cursor = nil
end

local CLASS, LEVEL = "ROGUE", 16
function UnitClass() return CLASS:sub(1, 1) .. CLASS:sub(2):lower(), CLASS end
function UnitLevel() return LEVEL end

local shellNs = {}
assert(loadfile(shell .. "/Theme.lua"))("MiniQoL", shellNs)
MiniQoL = shellNs

local ns = {}
-- The packaged copy runs inside the bundle's module adapter.
MiniQoLRuntime = { Execute = function(_, name, chunk) return chunk(name, ns) end }
for _, file in ipairs({ "Core.lua", "Profiles.lua", "Compare.lua", "Display.lua", "Upgrades.lua" }) do
    assert(loadfile(gearwise .. "/" .. file))("Gearwise", ns)
end
local items = {}
ns.Items = { Get = function(_, link)
    local id = ID(link)
    if not items[link] and ITEMS[id] then
        local item = ITEMS[id]
        items[link] = { id = id, link = link, name = item.name, icon = 1, level = 1, loc = item.loc,
            classID = item.classID or WEAPON, subclassID = item.subclassID, stats = item.stats }
    end
    return items[link]
end }
ns.Display.Schedule = noop
ns.db = { popups = true, spaceToEquip = false, spec = "auto", mode = "auto" }
ns.loggedIn = true
local U, Compare = ns.Upgrades, ns.Compare

-- The real builds, as the character sheet would pick them.
local function Become(class, level, spec)
    CLASS, LEVEL = class, level
    ns.db.spec = spec or "auto"
    ns.profile = ns.Profiles:Detect()
    Compare:Clear()
    return ns.profile
end
local function Wear(slot, id)
    EQUIPPED[slot] = id and Link(id) or nil
    Compare:Clear()
end
local function Wearing(id) Wear(18, id) end
local function Status(id) return Compare:Get(Link(id)).status end
local function Is(id, expected, label)
    local status = Status(id)
    assert(status == expected, label .. ": " .. status)
end

---------------------------------------------------------------------------
-- The ranged slot of a build that fights in melee
---------------------------------------------------------------------------
-- 1. The report: a level 16 rogue with a Small Throwing Knife picks up a
--    better one. Neither has a stat on it.
Become("ROGUE", 16)
Wearing(2947)
Is(3107, "upgrade", "a better throwing knife is an upgrade for a rogue")
Is(2947, "equal", "the same knife again is not")
Wearing(3107)
Is(2947, "downgrade", "and the worse one is a downgrade")

-- 2. What a melee build wears the slot for is still the stats. A rifle that
--    hits more than twice as hard does not replace three agility.
Wearing(9001)
Is(9002, "downgrade", "damage alone does not beat stats in a rogue's ranged slot")
Wearing(9002)
Is(9001, "upgrade", "and the bow with agility replaces the rifle")
Become("WARRIOR", 30)
Wearing(9001)
Is(9002, "downgrade", "nor in a warrior's")

-- 3. An empty slot takes anything that fits it.
Become("ROGUE", 16)
Wearing(nil)
local result = Compare:Get(Link(2947))
assert(result.status == "upgrade" and result.empty, "a first throwing knife fills an empty slot")

-- 4. No build that can use a ranged weapon lets a plainly better one tie,
--    whatever the class, the build or the level. A hunter's throwing weapon
--    is the one that is set aside instead (below).
local usable = {}
for class, builds in pairs(ns.Profiles.classes) do
    for _, build in ipairs(builds) do
        for _, level in ipairs({ 10, 30, 60 }) do
            local profile = Become(class, level, build.key)
            assert(profile.key == build.key, class .. " " .. build.key .. " was not selected")
            for _, pair in ipairs(PAIRS) do
                Wearing(pair[1])
                local status = Status(pair[2])
                local label = ("%s %s at %d, %s: %s"):format(class, build.key, level, ITEMS[pair[2]].name, status)
                local thrown = ITEMS[pair[2]].subclassID == THROWN
                if class == "HUNTER" and thrown then
                    assert(status == "unsupported", label)
                else
                    assert(status == "upgrade" or status == "unusable", label)
                end
                if status == "upgrade" then usable[class] = (usable[class] or 0) + 1 end
            end
        end
    end
end
for _, class in ipairs({ "WARRIOR", "ROGUE", "HUNTER", "PRIEST", "MAGE", "WARLOCK" }) do
    assert(usable[class], class .. " never got to compare a ranged weapon")
end
for _, class in ipairs({ "PALADIN", "SHAMAN", "DRUID" }) do
    assert(not usable[class], class .. " cannot use any of these")
end

---------------------------------------------------------------------------
-- Hunters
---------------------------------------------------------------------------
-- 5. A hunter fights with the ranged slot, and weighs it as the main weapon.
local spare = Become("ROGUE", 60).rangedDPS
assert(Become("HUNTER", 60).rangedDPS > spare * 20, "a hunter's ranged weapon is not a rogue's")
Wearing(9001)
Is(9002, "upgrade", "for a hunter the rifle that hits twice as hard wins")

-- 6. But shots need something that shoots. A throwing axe that hits three
--    times as hard as the bow is not a replacement for it.
Is(9003, "unsupported", "a hunter is not offered a throwing weapon over a bow")
assert(Compare:Get(Link(9003)).reason:find("bow", 1, true), "and the tooltip says why")
Wearing(nil)
Is(9003, "unsupported", "nor for an empty ranged slot")
Become("ROGUE", 60)
Wearing(2504)
Is(9003, "upgrade", "a rogue throws the same axe happily")

-- 7. The melee weapon is a hunter's spare, as the ranged one is a rogue's: a
--    plainly better one is an upgrade, and the stats on it decide the rest.
Become("HUNTER", 30)
Wear(16, 9101)
Is(9102, "upgrade", "a hunter's plainly better axe does not tie")
Is(9103, "upgrade", "four agility is worth more than one point of damage")
Wear(16, 9103)
Is(9102, "downgrade", "and five points of damage do not buy four agility back")
--    Below level 20 the early-level weight still applies, to every class it
--    applied to before.
assert(Become("HUNTER", 8).meleeDPS == 8 and Become("HUNTER", 12).meleeDPS == 2, "a young hunter swings the axe")
assert(Become("HUNTER", 30).meleeDPS < 1, "a grown one mostly does not")
assert(Become("MAGE", 8).meleeDPS == 8 and Become("MAGE", 12).meleeDPS == 2, "nor has a young mage changed")
assert(Become("WARRIOR", 12).meleeDPS == 14, "nor a warrior")
--    A caster past 20 never swings the staff at all: plain staves stay a tie,
--    which is what the look offers are for.
Become("MAGE", 30)
Wear(16, 9111)
Is(9112, "equal", "a mage's staff is not judged by its damage")
Wear(16, nil)

---------------------------------------------------------------------------
-- Shield builds
---------------------------------------------------------------------------
-- 8. A protection warrior with sword and shield. Weighed against the shield,
--    a second weapon wins on damage alone.
Become("WARRIOR", 30, "protection")
Wear(16, 9202)
Wear(17, 9204)
result = Compare:Get(Link(9201))
assert(result.slot == 16 and result.status == "downgrade",
    "the weaker sword is weighed against the main hand, not the shield: " .. result.status .. " for slot " .. tostring(result.slot))
Wear(16, 9201)
result = Compare:Get(Link(9202))
assert(result.slot == 16 and result.status == "upgrade", "the better sword is still offered for the main hand")
Is(9203, "unsupported", "an off-hand blade is not offered over a shield")
Is(9206, "unsupported", "nor something held in the off hand")
Is(9205, "upgrade", "a better shield is")
Is(9102, "unsupported", "and a two-hander was never offered to a shield build")
--    With no shield on yet the off hand is still kept for one.
Wear(17, nil)
Is(9203, "unsupported", "an empty off hand is not filled with a blade either")
Is(9204, "upgrade", "but with a shield")
--    A tank who already holds a second weapon chose to; compare as for anyone.
Wear(17, 9201)
Is(9203, "upgrade", "a better off-hand blade replaces an off-hand blade")
--    And only shield builds are held to this: a fury warrior carrying a
--    shield is offered the weapon.
Become("WARRIOR", 30, "fury")
Wear(16, 9202)
Wear(17, 9204)
result = Compare:Get(Link(9201))
assert(result.slot == 17 and result.status == "upgrade", "a fury warrior swaps the shield for a second sword")
Wear(16, nil)
Wear(17, nil)

---------------------------------------------------------------------------
-- Two weapons
---------------------------------------------------------------------------
-- 9. A rogue with a 30 in the main hand and a 20 in the off hand loots a 34.
--    It gains more over the 20, and used to be sent to the off hand, leaving
--    the lesser sword in front. The harder-hitting weapon goes in the main
--    hand; the 30 it pushes out is then offered for the off hand in turn.
Become("ROGUE", 30)
Wear(16, 9201)
Wear(17, 9207)
result = Compare:Get(Link(9208))
assert(result.status == "upgrade" and result.slot == 16, "the best weapon is offered for the main hand: slot " .. tostring(result.slot))
Wear(16, 9208)
result = Compare:Get(Link(9201))
assert(result.status == "upgrade" and result.slot == 17, "and the one it replaced for the off hand: slot " .. tostring(result.slot))
--    One that is better than the off hand only goes to the off hand.
Wear(16, 9201)
result = Compare:Get(Link(9209))
assert(result.status == "upgrade" and result.slot == 17, "a sword between the two goes in the off hand")
--    A main hand that cannot move to the off hand stays where it is.
Wear(16, 9210)
result = Compare:Get(Link(9208))
assert(result.status == "upgrade" and result.slot == 17, "a main-hand-only blade is not pushed out for less")
--    With the off hand empty the same holds: best in front, then the other.
Wear(16, 9201)
Wear(17, nil)
result = Compare:Get(Link(9208))
assert(result.status == "upgrade" and result.slot == 16, "and with an empty off hand the better sword still leads")
Wear(16, nil)

---------------------------------------------------------------------------
-- The list of changes
---------------------------------------------------------------------------
-- 10. Changes are listed by what they are worth to the build in that slot. A
--    rogue's bow leads with its agility; a hunter's with its damage.
local function First(class, level)
    Become(class, level)
    Wearing(9002)
    local lines = ns.Display:Changes(Compare:Get(Link(9001)), 6, 1)
    return lines[1]
end
assert(First("ROGUE", 30):find("Agility", 1, true), "a rogue reads the agility first: " .. First("ROGUE", 30))
assert(First("HUNTER", 30):find("Weapon DPS", 1, true), "a hunter reads the damage first: " .. First("HUNTER", 30))

---------------------------------------------------------------------------
-- Values set by hand
---------------------------------------------------------------------------
-- 11. A build's values are a judgement, and can be replaced: per character,
--     per build, and only for the stats that build weighs. The defaults are
--     never written over.
local P = ns.Profiles
local function Close(a, b) return math.abs(a - b) < 0.0001 end
Become("ROGUE", 60)
local key = ns.profile.key
assert(key == "combat", "a rogue with no talents yet is scored as combat")
assert(P:Default("ROGUE", key, "agi") == 2.3 and P:Default("ROGUE", key, "meleeDPS") == 15, "the build's own values")
assert(P:Default("ROGUE", key, "sp") == nil and P:Default("ROGUE", key, "defense") == nil,
    "what a rogue does not weigh is not his to set")
assert(not ns.profile.custom, "nothing is changed to begin with")
--     By the build's own values three agility beats five strength.
Wear(11, 9302)
Wear(12, 9302)
Is(9301, "downgrade", "the strength ring loses to agility by default")
--     A player who values strength more says so, and the advice follows.
assert(P:SetValue("ROGUE", key, "str", 3), "strength can be set")
Become("ROGUE", 60)
assert(ns.profile.weights.str == 3 and ns.profile.custom, "the build takes the value")
Is(9301, "upgrade", "and now the strength ring wins")
assert(ns.db.custom.combat.str == 3, "it is kept with the character, under the build")
assert(P:Changed("ROGUE", key) == 1, "and counted")
--     Another build is untouched.
assert(Become("ROGUE", 60, "subtlety").weights.str == 1 and not ns.profile.custom, "subtlety keeps its own strength")
--     Values land on the control's steps, stay inside its range, and a value
--     set back to the default is simply the default again.
P:SetValue("ROGUE", key, "agi", 1.2300001)
assert(Close(ns.db.custom.combat.agi, 1.25), "values snap to the step: " .. tostring(ns.db.custom.combat.agi))
P:SetValue("ROGUE", key, "agi", 99)
assert(ns.db.custom.combat.agi == 5, "and stop at the top of the range")
P:SetValue("ROGUE", key, "agi", 2.2999999)
assert(ns.db.custom.combat.agi == nil, "the default again is no change at all")
assert(not P:SetValue("ROGUE", key, "sp", 2) and ns.db.custom.combat.sp == nil, "spell power is refused for a rogue")
--     Weapon damage is set the same way.
P:SetValue("ROGUE", key, "rangedDPS", 5)
assert(Become("ROGUE", 60).rangedDPS == 5, "ranged weapon damage follows")
--     Leveling adds its bonus on top of whatever stamina is worth.
P:SetValue("ROGUE", key, "sta", 2)
assert(Close(Become("ROGUE", 60).weights.sta, 2), "stamina as set at 60")
assert(Close(Become("ROGUE", 30).weights.sta, 2 * 1.35), "and with the leveling bonus below it")
--     Reset brings every default back.
P:Reset(key)
Become("ROGUE", 60)
assert(ns.profile.weights.str == 1 and ns.profile.rangedDPS < 1 and not ns.profile.custom, "reset is the build's own again")
assert(P:Changed("ROGUE", key) == 0 and ns.db.custom.combat == nil, "with nothing left behind")
Is(9301, "downgrade", "and the advice is the default advice")
--     Every build offers something, and only stats it has a value for.
for class, builds in pairs(P.classes) do
    for _, build in ipairs(builds) do
        local offered = 0
        for _, stat in ipairs(P.STATS) do
            local default = P:Default(class, build.key, stat.key)
            if default ~= nil then
                offered = offered + 1
                assert(default >= 0 and default <= stat.max,
                    ("%s %s: %s's own value %s is outside its control"):format(class, build.key, stat.key, default))
                local steps = default / stat.step
                assert(Close(steps, math.floor(steps + 0.5)),
                    ("%s %s: %s's own value %s is not on a step"):format(class, build.key, stat.key, default))
            end
        end
        assert(offered >= 8, class .. " " .. build.key .. " offers too little to set: " .. offered)
        for stat in pairs(build.weights) do
            assert(P:Default(class, build.key, stat) ~= nil, class .. " " .. build.key .. " weighs " .. stat .. " but cannot set it")
        end
    end
end
Wear(11, nil)
Wear(12, nil)

---------------------------------------------------------------------------
-- And the prompt itself, from loot to the slot
---------------------------------------------------------------------------
Become("ROGUE", 16)
Wearing(2947)
local function Changed()
    Compare:Clear()
    U:Schedule()
    Settle()
end
local function Prompt()
    if U.frame and U.frame:IsShown() and U.current then return U.current, U.result end
end
U:Init()
assert(not Prompt(), "the knife already worn prompts nothing")
BAG[1] = Link(3107)
Changed()
local current, offered = Prompt()
assert(current and ID(current.link) == 3107, "the better knife is offered")
assert(offered.slot == 18 and offered.oldLinks[1] == Link(2947), "for the ranged slot, over the small one")
assert(U.frame.score.caption.text:find("Ranged", 1, true), "and the prompt names the slot")
U:Equip()
Changed()
assert(EQUIPPED[18] == Link(3107) and ID(BAG[1]) == 2947, "equipping it swaps the knives")
assert(not Prompt(), "and the old knife is not offered back")

print("Builds: ranged damage, hunters' bows, tanks' shields, the better weapon in front, values set by hand")
