-- What Gearwise does with the game's events, driven through the real Core,
-- Profiles, Items, Compare and Upgrades with item data read off tooltips.
--   Gear carried before it can be worn was looked at once, when it was looted,
--     and never again: the level arrived and nothing was offered.
--   With several upgrades waiting, the order was whatever the bags gave, and
--     the count on the prompt included every other thing just looted.
--   Every event wiped the caches and read the talents again on the spot, and
--     every item any other addon loaded counted as one.
local gearwise, shell = ...

local function noop() end

-- Anything not spelled out is a no-op, so the prompt builds as it would.
local methods = {}
local frame = {}
frame.__index = function(_, key)
    if methods[key] then return methods[key] end
    if type(key) == "string" and key:match("^%u") then return noop end
end
local LAST
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
    LAST = f
    return f
end
UIParent = CreateFrame("Frame")
GameTooltip = { SetOwner = noop, SetHyperlink = noop, Show = noop, Hide = noop }
function InCombatLockdown() return false end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function GetTime() return 100 end

local TIMERS = {}
C_Timer = { After = function(_, fn) TIMERS[#TIMERS + 1] = fn end }
-- Runs what is due, and what that schedules, for a few rounds.
local function Run(rounds)
    for _ = 1, rounds do
        if #TIMERS == 0 then return true end
        local due = TIMERS
        TIMERS = {}
        for _, fn in ipairs(due) do fn() end
    end
    return #TIMERS == 0
end
local function Settle() assert(Run(20), "timers never settled") end

---------------------------------------------------------------------------
-- The character
---------------------------------------------------------------------------
-- LEVEL is what UnitLevel answers and PAINTED what tooltips are coloured for.
-- Both lag behind the level-up event, as they do in the game.
local LEVEL, PAINTED, CAN_DUAL_WIELD = 16, 16, false
local TRAINED = { Dagger = true, Sword = true, Leather = true, Cloth = true }
function UnitClass() return "Rogue", "ROGUE" end
function UnitLevel() return LEVEL end
function CanDualWield() return CAN_DUAL_WIELD end

local WEAPON, ARMOR = 2, 4
local ITEMS = {
    [100] = { name = "Worn Jerkin", loc = "INVTYPE_CHEST", slot = "Chest", kind = "Leather", classID = ARMOR, subclassID = 2,
        lines = { "+1 Agility" } },
    [101] = { name = "Scout's Tunic", loc = "INVTYPE_CHEST", slot = "Chest", kind = "Leather", classID = ARMOR, subclassID = 2,
        level = 17, lines = { "+4 Agility" } },
    [110] = { name = "Dull Dagger", loc = "INVTYPE_WEAPON", slot = "One-Hand", kind = "Dagger", classID = WEAPON, subclassID = 15,
        level = 10, dps = 8 },
    [111] = { name = "Fine Rapier", loc = "INVTYPE_WEAPON", slot = "One-Hand", kind = "Sword", classID = WEAPON, subclassID = 7,
        level = 18, dps = 14 },
    [112] = { name = "Parrying Dagger", loc = "INVTYPE_WEAPONOFFHAND", slot = "Off Hand", kind = "Dagger", classID = WEAPON,
        subclassID = 15, dps = 9 },
    [113] = { name = "Short Bow", loc = "INVTYPE_RANGED", slot = "Ranged", kind = "Bow", classID = WEAPON, subclassID = 2,
        dps = 6 },
    [120] = { name = "Sturdy Bracers", loc = "INVTYPE_WRIST", slot = "Wrist", kind = "Leather", classID = ARMOR, subclassID = 2,
        lines = { "+2 Agility" } },
    [130] = { name = "Rough Leggings", loc = "INVTYPE_LEGS", slot = "Legs", kind = "Leather", classID = ARMOR, subclassID = 2,
        lines = { "+2 Agility" } },
    [131] = { name = "Fine Leggings", loc = "INVTYPE_LEGS", slot = "Legs", kind = "Leather", classID = ARMOR, subclassID = 2,
        lines = { "+6 Agility" } },
    [140] = { name = "Ruby Ring", loc = "INVTYPE_FINGER", slot = "Finger", classID = ARMOR, subclassID = 0,
        lines = { "+1 Stamina" } },
    [150] = { name = "Champion's Helm", loc = "INVTYPE_HEAD", slot = "Head", kind = "Leather", classID = ARMOR, subclassID = 2,
        lines = { "+10 Agility" } },
    [160] = { name = "Windcaller Cloak", loc = "INVTYPE_CLOAK", slot = "Back", kind = "Cloth", classID = ARMOR, subclassID = 1,
        lines = { "+3 Agility" }, loaded = false },
    [900] = { name = "Linen Bandage", loc = "", classID = 0, subclassID = 0 },
}
local function Link(id) return "|cffffffff|Hitem:" .. id .. "::::|h[" .. ITEMS[id].name .. "]|h|r" end
local function ID(link) return link and tonumber(link:match("item:(%d+)")) end

local WHITE, RED = { r = 1, g = 1, b = 1 }, { r = 1, g = 0.13, b = 0.13 }
local REQUESTS = 0
C_Item = {
    GetItemInfo = function(link)
        local id = ID(link)
        local item = ITEMS[id]
        if not item or item.loaded == false then return nil end
        return item.name, link, 1, 20, item.level or 0, "Type", item.kind, 1, item.loc, 1, 100,
            item.classID, item.subclassID, 0, 0, nil
    end,
    GetItemStats = function() return {} end,
    RequestLoadItemDataByID = function() REQUESTS = REQUESTS + 1 end,
}
-- The tooltip the game would draw, requirement colours included.
C_TooltipInfo = { GetHyperlink = function(link)
    local item = ITEMS[ID(link)]
    local lines = { { leftText = item.name, leftColor = WHITE } }
    if item.slot then
        lines[#lines + 1] = { leftText = item.slot, leftColor = WHITE, rightText = item.kind,
            rightColor = (item.kind and not TRAINED[item.kind]) and RED or WHITE }
    end
    if item.dps then
        lines[#lines + 1] = { leftText = ("%d - %d Damage"):format(item.dps * 2 - 4, item.dps * 2 + 4), leftColor = WHITE,
            rightText = "Speed 2.00", rightColor = WHITE }
        lines[#lines + 1] = { leftText = ("(%.1f damage per second)"):format(item.dps), leftColor = WHITE }
    end
    for _, text in ipairs(item.lines or {}) do lines[#lines + 1] = { leftText = text, leftColor = WHITE } end
    if item.level then
        lines[#lines + 1] = { leftText = "Requires Level " .. item.level,
            leftColor = PAINTED < item.level and RED or WHITE }
    end
    return { lines = lines }
end }

-- What is worn, one bag, and the cursor between them.
EQUIPPED = { [5] = Link(100), [16] = Link(110) }
BAG = { Link(111), Link(900), Link(120) }
local BAG_SIZE = 16
local cursor
local function FreeBagSlot()
    for slot = 1, BAG_SIZE do if not BAG[slot] then return slot end end
end
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

---------------------------------------------------------------------------
-- The addon
---------------------------------------------------------------------------
local shellNs = {}
assert(loadfile(shell .. "/Theme.lua"))("MiniQoL", shellNs)
MiniQoL = shellNs

local ns = {}
-- The packaged copy runs inside the bundle's module adapter.
MiniQoLRuntime = { Execute = function(_, name, chunk) return chunk(name, ns) end }
assert(loadfile(gearwise .. "/Core.lua"))("Gearwise", ns)
local core = LAST -- the frame Core listens on
for _, file in ipairs({ "Profiles.lua", "Items.lua", "Compare.lua", "Upgrades.lua" }) do
    assert(loadfile(gearwise .. "/" .. file))("Gearwise", ns)
end
ns.Display = { Init = noop, Schedule = noop, InstallHooks = noop, Changes = function() return {} end }
ns.Sidegrades = { Init = noop, Consider = noop }
ns.Options = { Init = noop, Refresh = noop }
local U = ns.Upgrades

local function Fire(event, ...) core.handlers.OnEvent(core, event, ...) end
local function Loot(id)
    BAG[FreeBagSlot()] = Link(id)
    Fire("BAG_UPDATE_DELAYED")
end
local function Prompt()
    if U.frame and U.frame:IsShown() and U.current then return ID(U.current.link), U.result end
end
local function Offered(id, label)
    local shown = Prompt()
    assert(shown == id, label .. ": " .. tostring(shown and ITEMS[shown].name))
end
-- Equipping from the prompt, and the events the game answers with.
local function Equip()
    U:Equip()
    Fire("PLAYER_EQUIPMENT_CHANGED", 1)
    Fire("BAG_UPDATE_DELAYED")
    Settle()
end

Fire("ADDON_LOADED", "Gearwise")
Fire("PLAYER_LOGIN")
Settle()
assert(not Prompt(), "nothing you already carry prompts at login")

---------------------------------------------------------------------------
-- Gear that becomes wearable
---------------------------------------------------------------------------
-- 1. Looted a level early: nothing to offer yet.
Loot(101)
Settle()
assert(not Prompt(), "a tunic for level 17 is not offered at 16")

-- 2. The level arrives. The game still answers 16 and still paints the
--    requirement red at this moment; the event is what says 17.
Fire("PLAYER_LEVEL_UP", 17)
Settle()
assert(ns.profile.level == 17, "the build is at the level the event announced: " .. ns.profile.level)
Offered(101, "the tunic is offered the moment it can be worn")
assert(U.frame.new.detail.text == "In your bags, and you can wear it now", "and the prompt says why now")
LEVEL, PAINTED = 17, 17
Equip()
assert(EQUIPPED[5] == Link(101), "it goes on from the prompt")
assert(not Prompt(), "the rapier for level 18 still waits, and the bracers you carried all along are not news")

-- 3. The sword carried since before login gets its turn at 18.
Fire("PLAYER_LEVEL_UP", 18)
Settle()
Offered(111, "the rapier is offered at 18")
LEVEL, PAINTED = 18, 18
Equip()
assert(EQUIPPED[16] == Link(111), "into the main hand")
assert(not Prompt(), "and the dagger it replaced is not offered back")

-- 4. An off-hand weapon before dual wield, then the skill.
Loot(112)
Settle()
assert(not Prompt(), "an off-hand dagger is no use without dual wield")
CAN_DUAL_WIELD = true
Fire("SPELLS_CHANGED")
Settle()
Offered(112, "learning dual wield offers it")
Equip()
assert(EQUIPPED[17] == Link(112), "for the off hand")

-- 5. A bow before bows are trained.
Loot(113)
Settle()
assert(not Prompt(), "an untrained weapon is not offered")
TRAINED.Bow = true
Fire("SKILL_LINES_CHANGED")
Settle()
Offered(113, "training the skill offers it")
U:Dismiss()
assert(not Prompt(), "and keeping what you have closes it")

---------------------------------------------------------------------------
-- Which upgrade comes first
---------------------------------------------------------------------------
-- 6. Two pairs of leggings, a ring and a bandage in one loot window. The
--    better leggings lead, and the count is a count of upgrades.
BAG[FreeBagSlot()] = Link(130)
BAG[FreeBagSlot()] = Link(131)
BAG[FreeBagSlot()] = Link(140)
BAG[FreeBagSlot()] = Link(900)
BAG[FreeBagSlot()] = Link(900)
Fire("BAG_UPDATE_DELAYED")
Settle()
Offered(131, "the biggest gain is offered first")
assert(U.frame.subtitle.text == "Upgrade 1 of 3", "three upgrades wait, not five things: " .. U.frame.subtitle.text)
Equip()
Offered(140, "then the ring: the lesser leggings are no longer an upgrade")
assert(U.frame.subtitle.text == "Upgrade found in your bags", "and nothing else waits: " .. U.frame.subtitle.text)

-- 7. A prompt you are reading is not swapped for a bigger one under you.
Loot(150)
Settle()
Offered(140, "the ring stays on screen")
assert(U.frame.subtitle.text == "Upgrade 1 of 2", "with the helm counted behind it")
U:Dismiss()
Offered(150, "and the helm follows")
U:Dismiss()

---------------------------------------------------------------------------
-- Bursts of events
---------------------------------------------------------------------------
local detections = 0
local Detect = ns.Profiles.Detect
ns.Profiles.Detect = function(...)
    detections = detections + 1
    return Detect(...)
end

-- 8. One swap is several events. They are answered once, a frame later.
for _ = 1, 3 do Fire("PLAYER_EQUIPMENT_CHANGED", 1) end
for _ = 1, 3 do Fire("BAG_UPDATE_DELAYED") end
Fire("SPELLS_CHANGED")
assert(detections == 0, "nothing is redone inside the events themselves")
Settle()
assert(detections == 1, "and once for the whole burst: " .. detections)

-- 9. Other addons loading item data fire one event per item. None of it is
--    Gearwise's to answer.
local revision = ns.revision
for id = 1, 500 do
    Fire("GET_ITEM_INFO_RECEIVED", 700000 + id, true)
    Fire("ITEM_DATA_LOAD_RESULT", 700000 + id, true)
end
Settle()
assert(ns.revision == revision and detections == 1, "a thousand foreign item loads change nothing")

-- 10. An item Gearwise is itself waiting on is another matter.
Loot(160)
assert(not Run(4), "its comparison keeps retrying while the data is missing")
assert(not Prompt(), "and nothing is offered meanwhile")
assert(REQUESTS == 1, "the data is asked for once, not on every retry: " .. REQUESTS)
revision = ns.revision
ITEMS[160].loaded = nil
Fire("GET_ITEM_INFO_RECEIVED", 160, true)
Settle()
assert(ns.revision > revision, "its arrival is answered")
Offered(160, "and the cloak is offered once it can be read")

print("Gear events: carried gear is offered when it can be worn, the biggest gain first, bursts answered once")
