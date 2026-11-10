local _, ns = ...
-- The fishing outfit: swap into it with one click, swap back to exactly what
-- you were wearing with the same click. The set can be filled from the fishing
-- gear you carry, snapshotted from what you have on, or picked slot by slot.
local Fishing = ns.Fishing

Fishing.SLOT_NAMES = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest",
    [6] = "Waist", [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands",
    [11] = "Ring 1", [12] = "Ring 2", [13] = "Trinket 1", [14] = "Trinket 2",
    [15] = "Back", [16] = "Main hand", [17] = "Off hand", [18] = "Ranged", [19] = "Tabard",
}

-- Slots worth offering: a fishing outfit is a pole, a hat, boots and the like.
Fishing.GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

local EMPTY = "empty" -- the set deliberately leaves this slot bare
local MAIN_HAND, OFF_HAND = 16, 17

-- Where each kind of item can go. Rings, trinkets and one-handed weapons fit
-- either of a pair.
local SLOTS_FOR = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
    INVTYPE_TABARD = { 19 },
}

local function ItemID(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

local function EquipLoc(link)
    local _, _, _, equipLoc = Fishing.GetItemInfoInstant(link)
    return equipLoc
end

local function EquipByLink(link, slot)
    local equip = (C_Item and C_Item.EquipItemByName) or EquipItemByName
    if not equip then return false end
    return pcall(equip, link, slot)
end

local function Unequip(slot)
    if not PickupInventoryItem then return false end
    local ok = pcall(PickupInventoryItem, slot)
    if not ok then return false end
    if CursorHasItem and CursorHasItem() then
        if PutItemInBackpack then pcall(PutItemInBackpack) end
        if CursorHasItem() and ClearCursor then ClearCursor() end
    end
    return true
end

function Fishing:EquippedLink(slot)
    return GetInventoryItemLink("player", slot)
end

---------------------------------------------------------------------------
-- What could go where
---------------------------------------------------------------------------
function Fishing.SameItem(a, b)
    return a == b or (ItemID(a) ~= nil and ItemID(a) == ItemID(b))
end

function Fishing:ItemFitsSlot(link, slot)
    local itemID, _, _, equipLoc = self.GetItemInfoInstant(link or "")
    if not itemID then return false end
    if slot == MAIN_HAND and self:IsPoleItem(itemID) then return true end
    if slot == OFF_HAND and equipLoc == "INVTYPE_WEAPON" and CanDualWield and not CanDualWield() then
        return false
    end
    for _, fits in ipairs(SLOTS_FOR[equipLoc] or {}) do
        if fits == slot then return true end
    end
    return false
end

-- "+5" from "Equip: Increased Fishing +5". Read from the item's tooltip, so
-- enchants and any client's wording are covered; remembered per link once the
-- client has the item.
local bonusCache = {}

function Fishing:ItemFishingBonus(link)
    if type(link) ~= "string" then return 0 end
    if bonusCache[link] then return bonusCache[link] end
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return 0 end
    local ok, tooltip = pcall(C_TooltipInfo.GetHyperlink, link:match("|H(item:[^|]+)|h") or link)
    if not ok or not tooltip or not tooltip.lines then return 0 end
    bonusCache[link] = self.TooltipFishingBonus(tooltip)
    return bonusCache[link]
end

local function BagLinks()
    local links, container = {}, C_Container
    if not (container and container.GetContainerNumSlots) then return links end
    for bag = BACKPACK_CONTAINER or 0, NUM_BAG_SLOTS or 4 do
        for index = 1, container.GetContainerNumSlots(bag) or 0 do
            local link = container.GetContainerItemLink(bag, index)
            if link then links[#links + 1] = link end
        end
    end
    return links
end

-- Worn or in the bags: an outfit piece that is neither cannot be swapped in.
function Fishing:IsCarried(link)
    local id = ItemID(link)
    if not id then return false end
    for _, slot in ipairs(self.GEAR_SLOTS) do
        if ItemID(self:EquippedLink(slot)) == id then return true end
    end
    return (self.GetItemCount(id) or 0) > 0
end

function Fishing:DescribeItem(link)
    local itemID, _, _, _, icon = self.GetItemInfoInstant(link)
    local name, _, quality, level = self.GetItemInfo(link)
    return { link = link, itemID = itemID, icon = icon, name = name or self.LinkName(link) or "Item",
        quality = quality, level = level or 0, bonus = self:ItemFishingBonus(link),
        pole = self:IsPoleItem(itemID) }
end

local function Better(a, b)
    if a.pole ~= b.pole then return a.pole end
    if a.bonus ~= b.bonus then return a.bonus > b.bonus end
    if (a.quality or 0) ~= (b.quality or 0) then return (a.quality or 0) > (b.quality or 0) end
    if a.level ~= b.level then return a.level > b.level end
    return a.name < b.name
end

-- Everything that could fill a slot: what is worn there, whatever in the bags
-- fits, and the piece the outfit already names even if it is not on you. Best
-- for fishing first.
function Fishing:SlotCandidates(slot)
    local list, seen = {}, {}
    local function add(link, worn)
        local key = ItemID(link) or link
        if seen[key] then
            seen[key].worn = seen[key].worn or worn
            return
        end
        local item = self:DescribeItem(link)
        item.worn, item.carried = worn, true
        seen[key] = item
        list[#list + 1] = item
    end
    local worn = self:EquippedLink(slot)
    if worn then add(worn, true) end
    for _, link in ipairs(BagLinks()) do
        if self:ItemFitsSlot(link, slot) then add(link, false) end
    end
    local saved = self:GearSlotValue(slot)
    if saved and saved ~= EMPTY and not seen[ItemID(saved) or saved] then
        add(saved, false)
        list[#list].carried = self:IsCarried(saved)
    end
    table.sort(list, Better)
    return list
end

-- The slot an item would land in: the one asked for if it fits, else the first
-- it fits, preferring a free one of a pair (the second ring, say).
function Fishing:SlotForItem(link, preferred)
    if preferred and self:ItemFitsSlot(link, preferred) then return preferred end
    local first
    for _, slot in ipairs(self.GEAR_SLOTS) do
        if self:ItemFitsSlot(link, slot) then
            first = first or slot
            local value = self:GearSlotValue(slot)
            if value == nil or value == EMPTY then return slot end
        end
    end
    return first
end

---------------------------------------------------------------------------
-- Defining the set
---------------------------------------------------------------------------
-- Snapshot: everything worn right now becomes the fishing outfit. Slots you
-- have nothing in are recorded as deliberately empty, so swapping in really
-- reproduces this outfit rather than leaving yesterday's gloves on.
function Fishing:SnapshotGear()
    local set = {}
    for _, slot in ipairs(self.GEAR_SLOTS) do
        local link = self:EquippedLink(slot)
        set[slot] = link or EMPTY
    end
    self.db.gear.set = set
    self:Fire("GEAR_CHANGED")
    return set
end

-- Manual: set one slot from what is worn there, or clear it. A cleared slot is
-- left alone by the swap; an "empty" slot is actively emptied.
function Fishing:SetGearSlot(slot, value)
    self.db.gear.set[slot] = value
    self:Fire("GEAR_CHANGED")
end

function Fishing:GearSlotFromWorn(slot)
    self:SetGearSlot(slot, self:EquippedLink(slot) or EMPTY)
end

function Fishing:ClearGearSlot(slot)
    self:SetGearSlot(slot, nil)
end

function Fishing:ClearGear()
    self.db.gear.set = {}
    self:Fire("GEAR_CHANGED")
end

function Fishing:GearSlotValue(slot)
    return self.db.gear.set[slot]
end

function Fishing:GearSlotIsEmpty(slot)
    return self.db.gear.set[slot] == EMPTY
end

function Fishing:HasGearSet()
    return next(self.db.gear.set) ~= nil
end

function Fishing:GearCount()
    local count = 0
    for _, value in pairs(self.db.gear.set) do
        if value ~= EMPTY then count = count + 1 end
    end
    return count
end

-- The pieces the outfit names, in slot order, and how many slots it empties.
function Fishing:GearSummary()
    local pieces, bare = {}, 0
    for _, slot in ipairs(self.GEAR_SLOTS) do
        local value = self.db.gear.set[slot]
        if value == EMPTY then bare = bare + 1
        elseif value then pieces[#pieces + 1] = value end
    end
    return pieces, bare
end

-- Fills the outfit from what you carry: the best pole, and every piece that
-- adds to fishing. Slots with nothing for fishing keep whatever was chosen.
function Fishing:SuggestGear()
    local pole, pieces, used = nil, 0, {}
    for _, slot in ipairs(self.GEAR_SLOTS) do
        for _, item in ipairs(self:SlotCandidates(slot)) do
            local useful = item.bonus > 0 or (slot == MAIN_HAND and item.pole)
            if useful and item.carried and not used[item.itemID] then
                used[item.itemID] = true
                self.db.gear.set[slot] = item.link
                if slot == MAIN_HAND and item.pole then pole = item else pieces = pieces + 1 end
                break
            end
        end
    end
    self:Fire("GEAR_CHANGED")
    return pole, pieces
end

function Fishing:WearingGear()
    return self.db.gear.active == true
end

---------------------------------------------------------------------------
-- Swapping
---------------------------------------------------------------------------
local function Describe(count)
    return count == 1 and "1 piece" or (count .. " pieces")
end

function Fishing:SwapToGear()
    if InCombatLockdown() then ns:Print("Fishing gear can wait until after combat."); return false end
    if not self:HasGearSet() then
        ns:Print("No fishing outfit yet. Type /mqol fish gear to choose one.")
        return false
    end
    local set = self.db.gear.set
    -- A two-handed pole pushes the off hand into the bags, so remember that
    -- too, or swapping back would leave the shield there.
    local guardOffHand = set[OFF_HAND] == nil and set[MAIN_HAND] ~= nil and set[MAIN_HAND] ~= EMPTY
        and EquipLoc(set[MAIN_HAND]) == "INVTYPE_2HWEAPON"
    -- Remember exactly what is on now, before anything moves and including
    -- the slots that are bare, so swapping back restores the outfit rather
    -- than approximating it.
    local previous, changed = {}, 0
    for _, slot in ipairs(self.GEAR_SLOTS) do
        if set[slot] ~= nil or (slot == OFF_HAND and guardOffHand) then
            previous[slot] = self:EquippedLink(slot) or EMPTY
        end
    end
    for _, slot in ipairs(self.GEAR_SLOTS) do
        local wanted = set[slot]
        if wanted ~= nil then
            local current = self:EquippedLink(slot)
            if wanted == EMPTY then
                if current then changed = changed + (Unequip(slot) and 1 or 0) end
            elseif current ~= wanted then
                if EquipByLink(wanted, slot) then changed = changed + 1 end
            end
        end
    end
    self.db.gear.saved = previous
    self.db.gear.active = true
    if self:Get("announceGear") then
        ns:Print(("Fishing outfit on (%s changed). Use it again to go back."):format(Describe(changed)))
    end
    self:Fire("GEAR_CHANGED")
    return true
end

function Fishing:SwapBack()
    if InCombatLockdown() then ns:Print("Your gear can wait until after combat."); return false end
    local previous = self.db.gear.saved
    if type(previous) ~= "table" or next(previous) == nil then
        self.db.gear.active = false
        ns:Print("Nothing to go back to; the outfit you had on was not recorded.")
        self:Fire("GEAR_CHANGED")
        return false
    end
    -- Slot order, so the main hand is back before the off hand goes on.
    local changed = 0
    for _, slot in ipairs(self.GEAR_SLOTS) do
        local link = previous[slot]
        local current = self:EquippedLink(slot)
        if link == EMPTY then
            if current then changed = changed + (Unequip(slot) and 1 or 0) end
        elseif link and current ~= link then
            if EquipByLink(link, slot) then changed = changed + 1 end
        end
    end
    self.db.gear.saved = nil
    self.db.gear.active = false
    if self:Get("announceGear") then
        ns:Print(("Back in your own gear (%s changed)."):format(Describe(changed)))
    end
    self:Fire("GEAR_CHANGED")
    return true
end

-- One action for a key, a macro or a button: out of your gear and into the
-- fishing outfit, then back again.
function Fishing:ToggleGear()
    if self:WearingGear() then return self:SwapBack() end
    return self:SwapToGear()
end

---------------------------------------------------------------------------
-- Putting it on an action bar
---------------------------------------------------------------------------
-- An addon cannot make a real ability, but a macro behaves like one on a bar.
-- This makes sure the macro exists and then puts it on the cursor, so it can
-- be dropped straight onto a bar.
Fishing.MACRO_NAME = "MiniQoL Fish"
local MACRO_ICON = "INV_Fishingpole_02"
local MACRO_BODY = "/mqol fish"

function Fishing:GearMacroIndex()
    if not GetMacroIndexByName then return nil end
    local index = GetMacroIndexByName(self.MACRO_NAME)
    return index ~= 0 and index or nil
end

function Fishing:EnsureGearMacro()
    if InCombatLockdown() then ns:Print("Macros cannot be made during combat."); return nil end
    local index = self:GearMacroIndex()
    if index then
        -- Keep the body current without disturbing an icon the player chose.
        if EditMacro then pcall(EditMacro, index, self.MACRO_NAME, nil, MACRO_BODY) end
        return index
    end
    if not CreateMacro then return nil end
    local ok, created = pcall(CreateMacro, self.MACRO_NAME, MACRO_ICON, MACRO_BODY)
    if not ok or not created then
        ns:Print("No free macro slot. Free one in the macro window, or use /mqol fish directly.")
        return nil
    end
    return created
end

function Fishing:PickupGearMacro()
    local index = self:EnsureGearMacro()
    if not index then return false end
    if not PickupMacro then return false end
    pcall(PickupMacro, index)
    ns:Print("Fishing swap is on your cursor -- drop it on an action bar.")
    return true
end

function Fishing:SetupGear()
    -- Leaving the outfit on across a logout is fine, but the gear you had on
    -- is only meaningful while the game remembers those items.
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function()
        if self.pendingSwap then
            local action = self.pendingSwap
            self.pendingSwap = nil
            if action == "toggle" then self:ToggleGear() end
        end
    end)
end
