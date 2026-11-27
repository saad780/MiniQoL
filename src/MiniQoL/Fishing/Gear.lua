local _, ns = ...
local Guarded = ns.Guarded or function(fn) return fn end -- each error once, not every frame (Diagnostics.lua)
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
    local bonus = self.TooltipFishingBonus(tooltip)
    -- An item the client has not loaded yet has a placeholder for a tooltip;
    -- only what was read off the real one is remembered.
    if self.GetItemInfo(link) then bonusCache[link] = bonus end
    return bonus
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

---------------------------------------------------------------------------
-- Swapping
---------------------------------------------------------------------------
-- Bag positions are never remembered. Each piece is looked up again when it
-- is needed: the very same item by its GUID when one was recorded, else any
-- copy with the same item ID (the exact link first). So moving or sorting
-- your bags in between doesn't matter, and neither does levelling up (item
-- links carry your level, so an old link no longer matches the item).
local WEAPON_SLOTS = { [16] = true, [17] = true, [18] = true } -- the only ones combat allows
local MAX_TRIES, TIMEOUT, TICK = 3, 8, 0.1
local Container = C_Container
local PickupBagItem = (Container and Container.PickupContainerItem) or PickupContainerItem
local EquipCursor = EquipCursorItem or PickupInventoryItem

local function Describe(count)
    return count == 1 and "1 piece" or (count .. " pieces")
end

-- The realm without its spaces and hyphens, worked out from its own name as
-- alt gear does: the game's ready-made short form can stop answering, and the
-- full name in its place would be a different character's record.
local function CharacterKey()
    local realm = GetRealmName and GetRealmName()
    realm = type(realm) == "string" and realm:gsub("[%s%-]", "") or ""
    if realm == "" then realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or "" end
    return (UnitName("player") or "?") .. "-" .. realm
end

local function GUIDAt(location)
    if not (location and C_Item and C_Item.GetItemGUID and C_Item.DoesItemExist) then return nil end
    local ok, exists = pcall(C_Item.DoesItemExist, location)
    if not ok or not exists then return nil end
    local found, guid = pcall(C_Item.GetItemGUID, location)
    return found and guid or nil
end

local function WornGUID(slot)
    return ItemLocation and GUIDAt(ItemLocation:CreateFromEquipmentSlot(slot)) or nil
end

local function BagGUID(bag, index)
    return ItemLocation and GUIDAt(ItemLocation:CreateFromBagAndSlot(bag, index)) or nil
end

-- What a slot should hold: EMPTY, or { link, id, guid }. Older records and
-- the outfit itself store bare links.
local function Want(value)
    if value == EMPTY or type(value) == "table" then return value end
    if type(value) == "string" then return { link = value, id = ItemID(value) } end
end

local function Remember(slot)
    local link = GetInventoryItemLink("player", slot)
    if not link then return EMPTY end
    return { link = link, id = ItemID(link), guid = WornGUID(slot) }
end

local function Holds(slot, want)
    local link = GetInventoryItemLink("player", slot)
    if want == EMPTY then return link == nil end
    if not link or type(want) ~= "table" then return false end
    if want.guid then
        local guid = WornGUID(slot)
        if guid then return guid == want.guid end
    end
    return ItemID(link) == want.id
end

local function BagCount(bag)
    return Container and Container.GetContainerNumSlots and Container.GetContainerNumSlots(bag) or 0
end

-- Where a piece is in the bags right now, skipping bag slots this pass has
-- already used.
local function FindInBags(want, claimed)
    if not want.id then return nil end
    local sameLink, sameID
    for bag = BACKPACK_CONTAINER or 0, NUM_BAG_SLOTS or 4 do
        for index = 1, BagCount(bag) do
            local key = bag .. ":" .. index
            local link = not claimed[key] and Container.GetContainerItemLink(bag, index)
            if link and ItemID(link) == want.id then
                if want.guid and BagGUID(bag, index) == want.guid then return bag, index, key end
                if link == want.link and not sameLink then sameLink = { bag, index, key } end
                sameID = sameID or { bag, index, key }
            end
        end
    end
    local hit = sameLink or sameID
    if hit then return hit[1], hit[2], hit[3] end
end

-- The piece worn in another slot (a ring or one-hander on the other side),
-- unless that slot already holds what it should.
function Fishing:FindWornElsewhere(want, slot, targets)
    for _, other in ipairs(self.GEAR_SLOTS) do
        if other ~= slot and Holds(other, want) and not (targets[other] ~= nil and Holds(other, targets[other])) then
            return other
        end
    end
end

-- An empty slot in a plain bag (profession bags only take their own kind).
local function FreeBagSlot(claimed)
    if not Container then return nil end
    for bag = BACKPACK_CONTAINER or 0, NUM_BAG_SLOTS or 4 do
        local free, family = 1, 0
        if Container.GetContainerNumFreeSlots then free, family = Container.GetContainerNumFreeSlots(bag) end
        if (free or 0) > 0 and (family or 0) == 0 then
            for index = 1, BagCount(bag) do
                local key = bag .. ":" .. index
                if not claimed[key] and not Container.GetContainerItemLink(bag, index) then return bag, index, key end
            end
        end
    end
end

local function BagLocked(bag, index)
    local info = Container.GetContainerItemInfo and Container.GetContainerItemInfo(bag, index)
    return type(info) == "table" and info.isLocked or false
end

-- Each move puts one thing on the cursor and drops it where it goes. A drop
-- the game refuses goes back where it came from.
local function Move(pickUp, drop)
    ClearCursor()
    pickUp()
    if not CursorHasItem() then return false end
    drop()
    if CursorHasItem() then ClearCursor(); return false end
    return true
end

local function EquipFromBag(bag, index, slot)
    -- What was worn there drops into the bag slot the piece came from.
    return Move(function() pcall(PickupBagItem, bag, index) end, function() pcall(EquipCursor, slot) end)
end

local function MoveWorn(from, slot)
    return Move(function() pcall(PickupInventoryItem, from) end, function() pcall(PickupInventoryItem, slot) end)
end

local function TakeOff(slot, bag, index)
    return Move(function() pcall(PickupInventoryItem, slot) end, function() pcall(PickupBagItem, bag, index) end)
end

-- What each character had on before the outfit, kept per character because
-- the outfit itself is shared by all of them.
function Fishing:SwapRecord()
    local gear = self.db.gear
    if type(gear.worn) ~= "table" then gear.worn = {} end
    local key = CharacterKey()
    -- Older builds kept a single record for every character.
    if gear.active ~= nil or gear.saved ~= nil then
        if gear.active and type(gear.saved) == "table" and gear.worn[key] == nil then gear.worn[key] = gear.saved end
        gear.active, gear.saved = nil, nil
    end
    return gear.worn[key]
end

function Fishing:SetSwapRecord(record)
    self:SwapRecord()
    self.db.gear.worn[CharacterKey()] = record
end

function Fishing:WearingGear()
    return self:SwapRecord() ~= nil
end

-- A swap runs in short passes until every slot is right. A slot waits while
-- its item is locked (the server hasn't confirmed the last move yet), and the
-- off hand waits for the main hand, so a two-handed pole is out of the way
-- first. In combat only weapons can change; the rest waits for combat to end.
function Fishing:StartSwap(job)
    job.failed, job.tries, job.deadline, job.waitingForCombat = {}, {}, GetTime() + TIMEOUT, nil
    job.before = job.before or {}
    for slot, want in pairs(job.targets) do
        if job.before[slot] == nil then job.before[slot] = Holds(slot, want) end
    end
    self.job = job
    if not self.swapTicker then
        self.swapTicker = C_Timer.NewTicker(TICK, Guarded(function() self:RunSwap() end, "Fishing outfit swap"))
    end
    self:RunSwap()
end

function Fishing:StopSwapTicker()
    if self.swapTicker then self.swapTicker:Cancel(); self.swapTicker = nil end
end

function Fishing:RunSwap()
    local job = self.job
    if not job then self:StopSwapTicker(); return end
    local combat = InCombatLockdown()
    if combat and job.kind == "outfit" then
        -- Never keep dressing for fishing once a fight starts.
        self.job = nil
        self:StopSwapTicker()
        ns:Print("Combat started, so the fishing outfit stopped going on. Use it again to change back.")
        self:Fire("GEAR_CHANGED")
        return
    end
    local targets, claimed, busy, deferred = job.targets, {}, false, false
    for _, slot in ipairs(self.GEAR_SLOTS) do
        local want = targets[slot]
        if want ~= nil and not job.failed[slot] and not Holds(slot, want) then
            local mainFirst = slot == OFF_HAND and targets[MAIN_HAND] ~= nil and not job.failed[MAIN_HAND]
                and not Holds(MAIN_HAND, targets[MAIN_HAND])
            if combat and not WEAPON_SLOTS[slot] then
                deferred = true
            elseif mainFirst or IsInventoryItemLocked(slot) then
                busy = true
            elseif (job.tries[slot] or 0) >= MAX_TRIES then
                job.failed[slot] = "the game would not put it on"
            elseif want == EMPTY then
                local bag, index, key = FreeBagSlot(claimed)
                if bag then
                    claimed[key], job.tries[slot], busy = true, (job.tries[slot] or 0) + 1, true
                    TakeOff(slot, bag, index)
                else
                    job.failed[slot] = "no room in your bags"
                end
            else
                local bag, index, key = FindInBags(want, claimed)
                local from = not bag and self:FindWornElsewhere(want, slot, targets)
                if bag then
                    claimed[key], busy = true, true
                    if not BagLocked(bag, index) then
                        job.tries[slot] = (job.tries[slot] or 0) + 1
                        EquipFromBag(bag, index, slot)
                    end
                elseif from then
                    busy = true
                    if not IsInventoryItemLocked(from) then
                        job.tries[slot] = (job.tries[slot] or 0) + 1
                        MoveWorn(from, slot)
                    end
                elseif ItemID(GetInventoryItemLink("player", slot)) ~= want.id then
                    -- (A copy of it already in the slot is good enough.)
                    job.failed[slot] = "not in your bags"
                end
            end
        end
    end
    if busy and GetTime() < job.deadline then return end
    self:StopSwapTicker()
    if deferred then
        -- Weapons are done; armour can't change until the fight is over.
        if not job.waitingForCombat then
            job.waitingForCombat = true
            ns:Print("Weapons are back. The rest goes back on when combat ends.")
        end
        self:Fire("GEAR_CHANGED")
        return
    end
    self.job = nil
    local changed, problems = 0, {}
    for _, slot in ipairs(self.GEAR_SLOTS) do
        local want = targets[slot]
        if want ~= nil then
            if Holds(slot, want) then
                if not job.before[slot] then changed = changed + 1 end
            elseif want ~= EMPTY and not (want.id and ItemID(GetInventoryItemLink("player", slot)) == want.id) then
                local name = self.LinkName(want.link) or self.SLOT_NAMES[slot]
                problems[#problems + 1] = ("%s (%s)"):format(name, job.failed[slot] or "timed out")
            elseif want == EMPTY then
                problems[#problems + 1] = ("%s (%s)"):format(self.SLOT_NAMES[slot], job.failed[slot] or "timed out")
            end
        end
    end
    job.finish(changed, problems)
    if #problems > 0 then
        ns:Print((job.kind == "outfit" and "Couldn't put on: " or "Couldn't put back: ") .. table.concat(problems, ", "))
    end
    self:Fire("GEAR_CHANGED")
end

function Fishing:SwapToGear()
    if InCombatLockdown() then ns:Print("The fishing outfit can't go on during combat."); return false end
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
    local previous, targets = {}, {}
    for _, slot in ipairs(self.GEAR_SLOTS) do
        if set[slot] ~= nil or (slot == OFF_HAND and guardOffHand) then previous[slot] = Remember(slot) end
        if set[slot] ~= nil then targets[slot] = Want(set[slot]) end
    end
    self:SetSwapRecord(previous)
    self:StartSwap({ kind = "outfit", targets = targets, finish = function(changed)
        if self:Get("announceGear") then
            ns:Print(("Fishing outfit on (%s changed). Use it again to go back."):format(Describe(changed)))
        end
    end })
    self:Fire("GEAR_CHANGED")
    return true
end

-- Allowed in combat: weapons go back straight away, armour once it ends.
function Fishing:SwapBack()
    local previous = self:SwapRecord()
    if type(previous) ~= "table" or next(previous) == nil then
        self:SetSwapRecord(nil)
        ns:Print("Nothing to go back to; the outfit you had on was not recorded.")
        self:Fire("GEAR_CHANGED")
        return false
    end
    local targets = {}
    for slot, value in pairs(previous) do
        slot = tonumber(slot)
        if slot then targets[slot] = Want(value) end
    end
    self:StartSwap({ kind = "back", targets = targets, finish = function(changed)
        self:SetSwapRecord(nil)
        if self:Get("announceGear") then
            ns:Print(("Back in your own gear (%s changed)."):format(Describe(changed)))
        end
    end })
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
    -- Armour that couldn't go back during a fight goes back once it ends.
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function()
        local job = self.job
        if job and job.waitingForCombat then self:StartSwap(job) end
    end)
end
