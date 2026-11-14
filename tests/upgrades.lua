-- The upgrade prompt after a swap: equipping an upgrade pushes the old piece
-- into the bags, and that piece can still beat what another slot holds -- the
-- old main hand over the off hand. Nothing else a swap moves should prompt.
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
function methods:HookScript(key, fn)
    local before = self.handlers[key]
    self.handlers[key] = function(...) if before then before(...) end; fn(...) end
end
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

-- Items: one-handed swords and a dagger a warrior can wield, rings, and a
-- fishing pole that no weapon skill covers.
local ITEMS = {
    [300] = { name = "Old Blade", loc = "INVTYPE_WEAPON", classID = 2, subclassID = 7, stats = { dps = 20 } },
    [301] = { name = "Worn Dagger", loc = "INVTYPE_WEAPON", classID = 2, subclassID = 15, stats = { dps = 18 } },
    [302] = { name = "New Blade", loc = "INVTYPE_WEAPON", classID = 2, subclassID = 7, stats = { dps = 40 } },
    [400] = { name = "Gold Band", loc = "INVTYPE_FINGER", classID = 4, subclassID = 0, stats = { str = 5 } },
    [401] = { name = "Copper Band", loc = "INVTYPE_FINGER", classID = 4, subclassID = 0, stats = { str = 2 } },
    [402] = { name = "Silver Band", loc = "INVTYPE_FINGER", classID = 4, subclassID = 0, stats = { str = 4 } },
    [500] = { name = "Fishing Pole", loc = "INVTYPE_2HWEAPON", classID = 2, subclassID = 20, stats = {} },
}
local function Link(id) return "|cff1eff00|Hitem:" .. id .. "::::|h[" .. ITEMS[id].name .. "]|h|r" end
local function ID(link) return link and tonumber(link:match("item:(%d+)")) end

-- The character: what is worn, one bag, and the cursor between them.
EQUIPPED = { [11] = Link(400), [12] = Link(401), [16] = Link(300), [17] = Link(301) }
BAG = { Link(402), Link(500) }
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
-- The game's swap: the worn piece takes the bag slot the new one left, and a
-- two-hander sends the off hand to the first free slot.
function EquipCursorItem(slot)
    local old = EQUIPPED[slot]
    EQUIPPED[slot] = cursor.link
    BAG[cursor.slot] = old
    if ITEMS[ID(cursor.link)].loc == "INVTYPE_2HWEAPON" and EQUIPPED[17] then
        BAG[FreeBagSlot()] = EQUIPPED[17]
        EQUIPPED[17] = nil
    end
    cursor = nil
end

local shellNs = {}
assert(loadfile(shell .. "/Theme.lua"))("MiniQoL", shellNs)
MiniQoL = shellNs

local ns = {}
-- The packaged copy runs inside the bundle's module adapter.
MiniQoLRuntime = { Execute = function(_, name, chunk) return chunk(name, ns) end }
for _, file in ipairs({ "Core.lua", "Compare.lua", "Upgrades.lua" }) do
    assert(loadfile(gearwise .. "/" .. file))("Gearwise", ns)
end
local items = {}
ns.Items = { Get = function(_, link)
    local id = ID(link)
    if not items[link] and ITEMS[id] then
        local item = ITEMS[id]
        items[link] = { id = id, link = link, name = item.name, icon = 1, level = 1, loc = item.loc,
            classID = item.classID, subclassID = item.subclassID, stats = item.stats }
    end
    return items[link]
end }
ns.Display = { Changes = function() return {} end, Schedule = noop }
ns.db = { popups = true, spaceToEquip = false }
ns.profile = { class = "WARRIOR", className = "Warrior", label = "Fury", level = 60,
    weights = { str = 2 }, meleeDPS = 3 }
ns.loggedIn = true
local U = ns.Upgrades

-- What the game's equipment and bag events do: fresh comparisons, then a scan.
local function Changed()
    ns.Compare:Clear()
    U:Schedule()
    Settle()
end
local function Prompt()
    if U.frame and U.frame:IsShown() and U.current then return U.current, U.result end
end
local function Hand(bagSlot, slot) -- a right-click or a drag, not the prompt
    C_Container.PickupContainerItem(0, bagSlot)
    EquipCursorItem(slot)
    Changed()
end
local function TakeOff(slot)
    BAG[FreeBagSlot()] = EQUIPPED[slot]
    EQUIPPED[slot] = nil
    Changed()
end
local function BagSlotOf(id)
    for slot = 1, BAG_SIZE do if ID(BAG[slot]) == id then return slot end end
end

U:Init()
assert(not Prompt(), "gear you already carry does not prompt at login")

-- Loot a better sword: it is offered for the main hand.
BAG[3] = Link(302)
Changed()
local current, result = Prompt()
assert(current and ID(current.link) == 302 and result.slot == 16, "the new sword is offered for the main hand")
assert(U.frame.new.detail.text == "In your bags", "loot reads as loot")

-- Equip it from the prompt: the old main hand now beats the off hand.
U:Equip()
Changed()
current, result = Prompt()
assert(EQUIPPED[16] == Link(302), "the new sword is in the main hand")
assert(current and ID(current.link) == 300, "the old main hand is offered again")
assert(result.slot == 17 and result.oldLinks[1] == Link(301), "for the off hand, over the dagger")
assert(U.frame.new.detail.text == "Just swapped out of your main hand", "and the prompt says where it came from")

-- Equip that too: the dagger it pushes out beats nothing, so the prompt closes.
U:Equip()
Changed()
assert(EQUIPPED[17] == Link(300) and ID(BAG[3]) == 301, "the old sword went to the off hand")
assert(not Prompt(), "a swapped-out piece that is worse everywhere does not prompt")

-- Taking a piece off by hand is a choice, not an upgrade to undo.
TakeOff(17)
assert(not Prompt(), "an emptied slot does not offer its own piece back")
Hand(BagSlotOf(300), 17)
assert(not Prompt(), "putting it back on prompts nothing")

-- A ring the game swaps out by hand can still beat the other ring.
Hand(BagSlotOf(402), 11)
current, result = Prompt()
assert(current and ID(current.link) == 400 and result.slot == 12, "the swapped-out ring is offered over the weaker one")
U:Equip()
Changed()
assert(EQUIPPED[12] == Link(400) and not Prompt(), "and the ring it replaces is not")

-- Putting a piece back where it was is the player's call too.
Hand(BagSlotOf(401), 12)
assert(not Prompt(), "a piece that beats its old slot's new item is not offered straight back")
Hand(BagSlotOf(400), 12)
U:Dismiss()

-- The fishing outfit: a two-handed pole sends both hands to the bags, and
-- nothing about that is an upgrade to undo.
local pole = BagSlotOf(500)
Hand(pole, 16)
assert(EQUIPPED[16] == Link(500) and not EQUIPPED[17], "the pole is on, both hands in the bags")
assert(not Prompt(), "putting the pole on prompts nothing")
C_Container.PickupContainerItem(0, BagSlotOf(302)); EquipCursorItem(16)
C_Container.PickupContainerItem(0, BagSlotOf(300)); EquipCursorItem(17)
Changed()
assert(EQUIPPED[16] == Link(302) and EQUIPPED[17] == Link(300), "back in your own weapons")
assert(not Prompt(), "the pole that comes off is not offered")

print("Upgrade prompt: a swapped-out weapon is offered for the other hand, and only that passed")
