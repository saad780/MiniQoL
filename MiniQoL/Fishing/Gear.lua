local _, ns = ...
-- The fishing outfit: swap into it with one click, swap back to exactly what
-- you were wearing with the same click. The set can be snapshotted from what
-- you have on, edited slot by slot, or snapshotted and then tweaked.
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
        ns:Print("No fishing outfit saved yet. Open Mini QoL, go to Fishing, and save what you are wearing.")
        return false
    end
    -- Remember exactly what is on now, including the slots that are bare, so
    -- swapping back restores the outfit rather than approximating it.
    local previous, changed = {}, 0
    for _, slot in ipairs(self.GEAR_SLOTS) do
        local wanted = self.db.gear.set[slot]
        if wanted ~= nil then
            local current = self:EquippedLink(slot)
            previous[slot] = current or EMPTY
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
    local changed = 0
    for slot, link in pairs(previous) do
        local current = self:EquippedLink(slot)
        if link == EMPTY then
            if current then changed = changed + (Unequip(slot) and 1 or 0) end
        elseif current ~= link then
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
