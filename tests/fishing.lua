-- The fishing engine: the outfit swap has to put back exactly what was on,
-- including the slots that were bare, and the catch record has to tell a
-- recast apart from a cast that caught nothing.
local root = ...

local function noop() end

-- Enough of a frame for the engine; the windows are not built here.
local scripts = {}
local frame = {}
frame.__index = frame
function frame:SetScript(key, fn) self.handlers[key] = fn end
function frame:GetScript(key) return self.handlers[key] end
function frame:HookScript(key, fn) self.handlers[key] = fn end
function frame:RegisterEvent(event) self.events[event] = true end
function frame:RegisterUnitEvent(event) self.events[event] = true end
function frame:UnregisterEvent(event) self.events[event] = nil end
function frame:Fire(event, ...) if self.handlers.OnEvent then self.handlers.OnEvent(self, event, ...) end end
for _, name in ipairs({ "SetSize", "SetPoint", "ClearAllPoints", "SetAttribute",
    "RegisterForClicks", "SetFrameStrata", "SetClampedToScreen", "SetMovable", "EnableMouse",
    "RegisterForDrag", "SetWidth", "StartMoving", "StopMovingOrSizing", "SetFrameLevel",
    "SetHeight", "SetAllPoints", "SetTexture", "SetTexCoord", "SetJustifyH", "SetJustifyV",
    "SetTextColor", "SetWordWrap", "SetColorTexture", "SetDesaturated",
    "SetTexelSnappingBias", "SetSnapToPixelGrid", "SetThickness", "SetStartPoint", "SetEndPoint",
    "SetMaxLetters", "SetAutoFocus", "SetTextInsets", "SetFontObject",
    "SetAlpha", "SetVertexColor", "SetToplevel", "Raise", "EnableKeyboard", "SetPropagateKeyboardInput" }) do
    frame[name] = noop
end
function frame:SetText(value) self.text = value end
function frame:GetText() return self.text end
function frame:SetEnabled(value) self.enabled = value and true or false end
function frame:IsEnabled() return self.enabled ~= false end
function frame:IsMouseOver() return false end
-- Showing and hiding run the frame's own scripts, as in game.
function frame:SetShown(value)
    value = value and true or false
    if value == (self.shown == true) then return end
    self.shown = value
    local script = self.handlers[value and "OnShow" or "OnHide"]
    if script then script(self) end
end
function frame:Show() self:SetShown(true) end
function frame:Hide() self:SetShown(false) end
-- Only frames built with BackdropTemplate have the backdrop methods. Faking
-- them on everything hides a missing template until the game reports it.
local function RequiresBackdrop(self, method)
    assert(self.template and self.template:find("BackdropTemplate"),
        (self.name or "a frame") .. " needs BackdropTemplate to call " .. method
            .. " (template: " .. tostring(self.template) .. ")")
end
function frame:SetBackdrop() RequiresBackdrop(self, "SetBackdrop") end
function frame:SetBackdropColor() RequiresBackdrop(self, "SetBackdropColor") end
function frame:SetBackdropBorderColor() RequiresBackdrop(self, "SetBackdropBorderColor") end
function frame:IsShown() return self.shown == true end
function frame:GetFrameLevel() return 1 end
function frame:GetStringHeight() return 12 end
function frame:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function frame:CreateTexture() return setmetatable({ handlers = {}, events = {} }, frame) end
function frame:CreateFontString() return setmetatable({ handlers = {}, events = {} }, frame) end
function CreateFrame(kind, name, parent, template)
    local f = setmetatable({ handlers = {}, events = {}, name = name, template = template }, frame)
    scripts[#scripts + 1] = f
    if name then _G[name] = f end
    return f
end

NOW, CLOCK = 1000, 1700000000
function GetTime() return NOW end
function time() return CLOCK end
function date(_, stamp) return { hour = 12 } end
-- A ticker keeps its function so a test can turn it by hand.
C_Timer = { After = function(_, fn) end, NewTimer = function() return { Cancel = noop } end,
    NewTicker = function(_, fn) return { fn = fn, Cancel = noop } end }
function UnitName() return PLAYER_NAME or "Tester" end
function GetNormalizedRealmName() return "Realm" end
function IsInventoryItemLocked() return false end
function InCombatLockdown() return COMBAT == true end
function GetCVar(key) return CVARS[key] end
function SetCVar(key, value) CVARS[key] = tostring(value) end
CVARS = { Sound_MasterVolume = "0.3", Sound_SFXVolume = "0.4", Sound_EnableSFX = "1",
    Sound_MusicVolume = "0.5", Sound_AmbienceVolume = "0.6", Sound_EnableSoundWhenGameIsInBG = "0",
    SoftTargetInteract = "0" }
function GetWeaponEnchantInfo() return false end
function GetProfessions() return nil end
function GetNumSkillLines() return 0 end
function UnitChannelInfo() return nil end
function UnitExists() return false end
GameTooltip = { IsShown = function() return false end, SetOwner = noop, Show = noop, Hide = noop,
    SetItemByID = noop, SetHyperlink = noop, SetText = noop, AddLine = noop }
WorldFrame = CreateFrame()
UIParent = CreateFrame()
StaticPopupDialogs, SlashCmdList = {}, {}
function StaticPopup_Show() end
YES, NO = "Yes", "No"
function SetOverrideBinding() end
function SetOverrideBindingClick() end
function ClearOverrideBindings() end
C_Spell = { GetSpellName = function(id) return id == 7620 and "Fishing" or ("Spell" .. tostring(id)) end }
-- Items are looked up by ID or by link, as the game allows.
local function id(item) return tonumber(tostring(item):match("item:(%d+)")) or tonumber(item) end
C_Item = {
    GetItemInfo = function(item)
        local itemID = id(item)
        return "Item" .. itemID, "|cffffffff|Hitem:" .. itemID .. "|h[Item" .. itemID .. "]|h|r", QUALITY[itemID] or 1, 10
    end,
    GetItemCount = function(item) return BAGS[id(item)] or 0 end,
    GetItemIconByID = function() return 1 end,
    GetItemInfoInstant = function(item)
        local itemID = id(item)
        if not itemID then return nil end
        return itemID, nil, nil, EQUIP_LOC[itemID], 1, (POLES[itemID] and 2 or 4), (POLES[itemID] and 20 or 1)
    end,
}
BAGS, POLES, EQUIP_LOC, QUALITY, FISHING_BONUS = {}, {}, {}, {}, {}
EQUIPPED = {}
function GetInventoryItemLink(_, slot) return EQUIPPED[slot] end
function GetInventoryItemID(_, slot)
    local link = EQUIPPED[slot]
    return link and tonumber(link:match("item:(%d+)")) or nil
end
function CanDualWield() return false end
-- Bags 0-4: BAG_ITEMS[bag][index] = link. BAG_SIZE gives a bag empty slots;
-- without it a bag is exactly its list.
BAG_ITEMS, BAG_SIZE = {}, {}
local function bagSize(bag) return BAG_SIZE[bag] or (BAG_ITEMS[bag] and #BAG_ITEMS[bag]) or 0 end
local function bagItem(bag, index) return BAG_ITEMS[bag] and BAG_ITEMS[bag][index] end
local function setBagItem(bag, index, item)
    BAG_ITEMS[bag] = BAG_ITEMS[bag] or {}
    BAG_ITEMS[bag][index] = item
end
-- The cursor holds an item and where it came from: { link, slot } or
-- { link, bag, index }. A test may also set it to a bare link. As in game,
-- dropping it on an occupied place sends what was there to where it came from.
CURSOR = nil
local function cursorLink() return type(CURSOR) == "table" and CURSOR.link or CURSOR end
local function sendHome(item)
    if type(CURSOR) ~= "table" then return end
    if CURSOR.slot then EQUIPPED[CURSOR.slot] = item else setBagItem(CURSOR.bag, CURSOR.index, item) end
end
local function wear(slot)
    local item = cursorLink()
    sendHome(EQUIPPED[slot])
    EQUIPPED[slot], CURSOR = item, nil
    -- A two-handed weapon pushes the off hand into the bags.
    if slot == 16 and EQUIP_LOC[id(item)] == "INVTYPE_2HWEAPON" and EQUIPPED[17] then
        for bag = 0, 4 do
            for index = 1, bagSize(bag) do
                if EQUIPPED[17] and not bagItem(bag, index) then setBagItem(bag, index, EQUIPPED[17]); EQUIPPED[17] = nil end
            end
        end
    end
end
function PickupInventoryItem(slot)
    if CURSOR then wear(slot)
    elseif EQUIPPED[slot] then CURSOR = { link = EQUIPPED[slot], slot = slot }; EQUIPPED[slot] = nil end
end
function EquipCursorItem(slot) if CURSOR then wear(slot) end end
function CursorHasItem() return CURSOR ~= nil end
function ClearCursor() sendHome(cursorLink()); CURSOR = nil end
function GetCursorInfo() local item = cursorLink(); if item then return "item", id(item), item end end
C_Container = {
    GetContainerNumSlots = bagSize,
    GetContainerItemLink = bagItem,
    GetContainerItemInfo = function(bag, index)
        return bagItem(bag, index) and { hyperlink = bagItem(bag, index), isLocked = false } or nil
    end,
    GetContainerNumFreeSlots = function(bag)
        local free = 0
        for index = 1, bagSize(bag) do if not bagItem(bag, index) then free = free + 1 end end
        return free, 0
    end,
    PickupContainerItem = function(bag, index)
        if CURSOR then
            local here = bagItem(bag, index)
            setBagItem(bag, index, cursorLink())
            sendHome(here)
            CURSOR = nil
        elseif bagItem(bag, index) then
            CURSOR = { link = bagItem(bag, index), bag = bag, index = index }
            setBagItem(bag, index, nil)
        end
    end,
}
C_TooltipInfo = {
    GetItemByID = function() return nil end,
    GetInventoryItem = function() return nil end,
    GetHyperlink = function(link)
        local itemID = id(link)
        local lines = { { leftText = "Item" .. itemID } }
        if FISHING_BONUS[itemID] then
            lines[#lines + 1] = { leftText = "Equip: Increased Fishing +" .. FISHING_BONUS[itemID] .. "." }
        end
        return { lines = lines }
    end,
}
-- The game's context menu: records what was offered so a test can pick it.
MenuUtil = { CreateContextMenu = function(owner, generator)
    local root = { entries = {} }
    function root:CreateTitle(text) self.title = text end
    function root:CreateDivider() end
    function root:CreateButton(text)
        local entry = { text = text, SetEnabled = noop }
        self.entries[#self.entries + 1] = entry
        return entry
    end
    function root:CreateRadio(text, selected, pick)
        local entry = { text = text, selected = selected, pick = pick }
        self.entries[#self.entries + 1] = entry
        return entry
    end
    generator(owner, root)
    MENU = root
end }
function IsFishingLoot() return FISHING_LOOT == true end
function GetNumLootItems() return #LOOT end
function GetLootSlotLink(slot) return LOOT[slot] and LOOT[slot].link end
function GetLootSlotInfo(slot) return 1, nil, LOOT[slot] and LOOT[slot].quantity or 1 end
LOOT, FISHING_LOOT = {}, false
function GetRealZoneText() return ZONE or "Elwynn Forest" end
function GetSubZoneText() return SUBZONE or "Crystal Lake" end
function GetMacroIndexByName() return 0 end
function CreateMacro() return 1 end
function PickupMacro() PICKED_UP = true end

local ns = { db = {} }
function ns.ContextMenu(owner, generator) return MenuUtil.CreateContextMenu(owner, generator) end
function ns:Print(message) PRINTED = message end
function ns:RegisterFeature(spec) FEATURES[#FEATURES + 1] = spec end
function ns:ShowPage() end
function ns:Refresh() REFRESHED = (REFRESHED or 0) + 1 end
FEATURES = {}
-- The real theme, so a frame that cannot take a backdrop is caught here
-- rather than on the first login after a change.
assert(loadfile(root .. "/Theme.lua"))("MiniQoL", ns)

local base = root .. "/Fishing/"
for _, file in ipairs({ "Core", "Catches", "Sound", "Character", "Lures", "Stats", "Gear", "Outfit", "Page", "Bar" }) do
    assert(loadfile(base .. file .. ".lua"))("MiniQoL", ns)
end
local F = ns.Fishing
F:Initialize()
F:SetupOutfit()
F:SetupGear()
local gearEvents = scripts[#scripts]

local function link(id) return "|cffffffff|Hitem:" .. id .. "|h[Item" .. id .. "]|h|r" end
-- The same item after a level-up: links carry the player's level.
local function relink(id) return "|cffffffff|Hitem:" .. id .. "::::::::14|h[Item" .. id .. "]|h|r" end
-- In game a swap runs a pass at a time on a ticker; here it is turned by hand.
local function settle()
    for _ = 1, 50 do
        if not F.swapTicker then return end
        F.swapTicker.fn()
    end
    error("the swap never finished")
end
local function equal(actual, expected, label)
    assert(actual == expected, (label or "value") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

---------------------------------------------------------------------------
print("-- the fishing outfit --")
-- Wearing: a hat, a chest, a sword. Nothing on the back.
EQUIPPED[1], EQUIPPED[5], EQUIPPED[16] = link(101), link(105), link(116)
F:SnapshotGear()
equal(F:GearSlotValue(1), link(101), "snapshot keeps the hat")
equal(F:GearSlotValue(15), "empty", "a bare slot is recorded as deliberately empty")
equal(F:GearCount(), 3, "three real pieces")

-- Tweak after snapshotting: the pole goes in the main hand, the hat is left alone.
EQUIPPED[16] = link(777)
POLES[777] = true
F:GearSlotFromWorn(16)
equal(F:GearSlotValue(16), link(777), "main hand now holds the pole")
F:ClearGearSlot(1)
equal(F:GearSlotValue(1), nil, "a cleared slot is left alone by the swap")

-- Now dress in ordinary gear and swap. The outfit's pieces are in the bags,
-- with room for what comes off.
EQUIPPED = { [1] = link(201), [5] = link(205), [15] = link(215), [16] = link(216) }
BAG_SIZE, BAG_ITEMS = { [0] = 6 }, { [0] = { link(105), link(777) } }
F:SwapToGear()
settle()
equal(F:WearingGear(), true, "wearing the outfit")
equal(EQUIPPED[16], link(777), "pole equipped")
equal(EQUIPPED[5], link(105), "fishing chest equipped")
equal(EQUIPPED[15], nil, "a slot the outfit empties is taken off")
equal(EQUIPPED[1], link(201), "an ignored slot keeps what it had")
equal(CURSOR, nil, "nothing left on the cursor")

print("-- swapping back after the bags were sorted --")
-- The swapped-out pieces end up somewhere else entirely, and a level-up has
-- changed the sword's link. Neither may matter.
BAG_SIZE = { [0] = 6, [1] = 4 }
BAG_ITEMS = { [0] = { [2] = link(777), [4] = link(215), [6] = relink(216) }, [1] = { [3] = link(205), [4] = link(105) } }
F:SwapBack()
settle()
equal(F:WearingGear(), false, "back in your own gear")
equal(EQUIPPED[16], relink(216), "the old weapon is back")
equal(EQUIPPED[5], link(205), "the old chest is back")
equal(EQUIPPED[15], link(215), "the cloak that was taken off is back")
equal(EQUIPPED[1], link(201), "the ignored slot never moved")
equal(bagItem(0, 6), link(777), "the pole went where the sword was")

print("-- one action toggles --")
F:ToggleGear()
settle()
equal(F:WearingGear(), true, "toggle swaps in")
F:ToggleGear()
settle()
equal(F:WearingGear(), false, "toggle swaps back")
equal(EQUIPPED[15], link(215), "and restores again")

COMBAT = true
F:ToggleGear()
equal(F:WearingGear(), false, "combat refuses the swap")
assert(PRINTED:find("combat"), "and says why")
COMBAT = false

print("-- changing back during combat --")
F:ToggleGear()
settle()
COMBAT = true
F:ToggleGear()
settle()
equal(id(EQUIPPED[16]), 216, "the weapon comes back mid-fight")
equal(EQUIPPED[5], link(105), "armour has to wait for the fight to end")
equal(F:WearingGear(), true, "the outfit counts as on until it is all off")
assert(PRINTED:find("combat ends"), "and says the rest follows")
COMBAT = false
gearEvents:Fire("PLAYER_REGEN_ENABLED")
settle()
equal(EQUIPPED[5], link(205), "the chest goes back once combat ends")
equal(EQUIPPED[15], link(215), "and the cloak")
equal(F:WearingGear(), false, "back in your own gear")

print("-- a fight starting while the outfit goes on --")
F:ToggleGear()
COMBAT = true
settle()
assert(PRINTED:find("Combat started"), "dressing for fishing stops")
equal(F:WearingGear(), true, "and the button changes back from there")
F:ToggleGear()
settle()
COMBAT = false
gearEvents:Fire("PLAYER_REGEN_ENABLED")
settle()
equal(F:WearingGear(), false, "all the way back")
equal(id(EQUIPPED[16]), 216, "with the sword")

print("-- one record per character --")
F:ToggleGear()
settle()
PLAYER_NAME = "Alt"
equal(F:WearingGear(), false, "another character isn't wearing this one's outfit")
PLAYER_NAME = nil
equal(F:WearingGear(), true, "this one still is")
F:ToggleGear()
settle()
equal(F:WearingGear(), false, "and goes back")
-- A record from an older build, kept for every character as bare links.
F.db.gear.worn, F.db.gear.active, F.db.gear.saved = nil, true, { [15] = "empty" }
equal(F:WearingGear(), true, "an older record is picked up")
F:ToggleGear()
settle()
equal(EQUIPPED[15], nil, "and put back")
equal(F.db.gear.saved, nil, "then dropped")
EQUIPPED[15] = link(215)

print("-- a two-handed pole and the off hand --")
-- Only the pole is in the outfit, but equipping it pushes the shield into the
-- bags. Swapping back has to bring the shield back as well.
local outfitBefore = F.db.gear.set
F.db.gear.set = {}
EQUIP_LOC[777], EQUIP_LOC[216], EQUIP_LOC[217] = "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_SHIELD"
EQUIPPED = { [16] = link(216), [17] = link(217) }
BAG_SIZE, BAG_ITEMS = { [0] = 4 }, { [0] = { link(777) } }
F:SetGearSlot(16, link(777))
F:SwapToGear()
settle()
equal(EQUIPPED[16], link(777), "pole in hand")
equal(EQUIPPED[17], nil, "the shield went to the bags with it")
F:SwapBack()
settle()
equal(EQUIPPED[16], link(216), "the sword is back")
equal(EQUIPPED[17], link(217), "and so is the shield")
F.db.gear.set = outfitBefore
BAG_SIZE, BAG_ITEMS = {}, {}

---------------------------------------------------------------------------
print("-- the catch record --")
F:RecordCast({ time = CLOCK, ended = CLOCK, caught = true, seconds = 12 })
F:RecordCatch({ itemID = 6303, link = link(6303), quantity = 1, time = CLOCK,
    zone = "Elwynn Forest", subzone = "Crystal Lake" })
F:RecordCast({ time = CLOCK, ended = CLOCK, caught = false })
F:RecordCatch({ itemID = 6303, link = link(6303), quantity = 2, time = CLOCK,
    zone = "Elwynn Forest", subzone = "Crystal Lake" })
local caught, missed, average, percent = F:CastSummary()
equal(caught, 1, "one cast caught")
equal(missed, 1, "one cast empty")
equal(average, 12, "average wait")
equal(math.floor(percent + 0.5), 50, "half the casts caught")

local total, entries, fish = F:SessionSummary(false)
equal(fish, 3, "three fish")
equal(entries[1].count, 3, "stacked into one entry")
equal(math.floor(entries[1].percent + 0.5), 100, "all of the catch")

local withMisses = select(2, F:SessionSummary(true))
local missEntry
for _, entry in ipairs(withMisses) do if entry.missed then missEntry = entry end end
assert(missEntry and missEntry.count == 1, "misses appear when asked for")

local zoneTotal, zones = F:ZoneSummary()
equal(zoneTotal, 3, "zone totals match")
equal(zones[1].name, "Elwynn Forest", "favourite zone")
equal(zones[1].areas[1].name, "Crystal Lake", "and the spot in it")

print("-- resets --")
F:ResetSession()
equal(select(3, F:SessionSummary(false)), 0, "session cleared")
equal(F:TotalCaught(), 3, "all-time totals kept")
F:ResetAll()
equal(F:TotalCaught(), 0, "everything erased")
assert(F:HasGearSet(), "the outfit survives erasing the record")

---------------------------------------------------------------------------
print("-- the splash --")
F:Set("sound", true)
F:Set("volume", 0.9)
F:BoostSound()
equal(CVARS.Sound_MasterVolume, "0.9", "volume raised")
equal(CVARS.Sound_MusicVolume, "0", "music silenced")
equal(CVARS.Sound_EnableSoundWhenGameIsInBG, "1", "kept audible in the background")
assert(F:SoundBoosted(), "boost recorded, so a crash can be undone")
F:RestoreSound()
equal(CVARS.Sound_MasterVolume, "0.3", "volume put back")
equal(CVARS.Sound_MusicVolume, "0.5", "music put back")
equal(CVARS.Sound_EnableSoundWhenGameIsInBG, "0", "background put back")
assert(not F:SoundBoosted(), "nothing left to undo")

---------------------------------------------------------------------------
print("-- choosing gear without wearing it --")
F:ClearGear()
EQUIPPED = { [1] = link(201), [16] = link(216) }
EQUIP_LOC[301], EQUIP_LOC[308], EQUIP_LOC[311], EQUIP_LOC[312], EQUIP_LOC[778] =
    "INVTYPE_HEAD", "INVTYPE_FEET", "INVTYPE_FINGER", "INVTYPE_FINGER", "INVTYPE_2HWEAPON"
POLES[778] = true
FISHING_BONUS[301], FISHING_BONUS[778], FISHING_BONUS[311] = 5, 20, 2
BAG_ITEMS = { [0] = { link(301), link(308), link(777) }, [1] = { link(778), link(311), link(312) } }
for _, itemID in ipairs({ 301, 308, 777, 778, 311, 312 }) do BAGS[itemID] = 1 end

assert(F:ItemFitsSlot(link(308), 8), "boots fit the feet")
assert(not F:ItemFitsSlot(link(308), 1), "and not the head")
assert(F:ItemFitsSlot(link(777), 16), "a pole fits the main hand")
equal(F:ItemFishingBonus(link(301)), 5, "fishing bonus read from the tooltip")

local hands = F:SlotCandidates(16)
equal(hands[1].itemID, 778, "the better pole is offered first")
equal(hands[2].itemID, 777, "then the other pole")
equal(hands[#hands].itemID, 216, "the sword you have on is still offered")
assert(hands[#hands].worn, "and marked as worn")

local pole, pieces = F:SuggestGear()
equal(pole and pole.itemID, 778, "finding gear picks the best pole")
equal(pieces, 2, "plus the fishing hat and the fishing ring")
equal(F:GearSlotValue(16), link(778), "pole in the outfit")
equal(F:GearSlotValue(1), link(301), "hat in the outfit")
equal(F:GearSlotValue(11), link(311), "fishing ring in the first ring slot")
equal(F:GearSlotValue(12), nil, "a ring with no bonus is not added")
equal(F:GearSlotValue(8), nil, "boots with no bonus are left alone")

F:SetGearSlot(1, "empty")
F:SetGearSlot(8, "empty")
F:SuggestGear()
equal(F:GearSlotValue(1), link(301), "finding again puts the fishing hat back")
equal(F:GearSlotValue(8), "empty", "slots with nothing for fishing keep their choice")

print("-- the outfit window --")
F:OpenOutfit()
local window = _G.MiniQoLFishingOutfit
assert(window and window:IsShown(), "the window opens")
assert(window.status:GetText():find("3 pieces"), "header counts the pieces: " .. tostring(window.status:GetText()))
assert(window.status:GetText():find("1 slot taken off"), "and the bare slots")
equal(window.swap:GetText(), "Put on outfit", "swap button offers to put it on")

-- Dropping boots on the head slot puts them on the feet.
CURSOR = link(308)
local tiles = {}
for _, child in ipairs(scripts) do if child.slot then tiles[child.slot] = child end end
assert(tiles[1] and tiles[8] and tiles[16], "a tile for every slot")
tiles[1].handlers.OnReceiveDrag(tiles[1])
equal(F:GearSlotValue(8), link(308), "boots land in the feet slot")
equal(F:GearSlotValue(1), link(301), "the hat is untouched")
equal(CURSOR, nil, "the cursor is cleared")

-- Dropping a ring picks the free ring slot.
CURSOR = link(312)
window.handlers.OnReceiveDrag(window)
equal(F:GearSlotValue(12), link(312), "second ring fills the free slot")

-- Right-click leaves a slot alone.
tiles[12].handlers.OnClick(tiles[12], "RightButton")
equal(F:GearSlotValue(12), nil, "right-click clears the slot")

-- Click opens a menu of what fits.
tiles[16].handlers.OnClick(tiles[16], "LeftButton")
equal(MENU.title, "Main hand", "menu is titled with the slot")
local offered = {}
for _, entry in ipairs(MENU.entries) do offered[#offered + 1] = entry end
assert(offered[1].text:find("Item778"), "the best pole heads the list")
assert(offered[1].text:find("+20 fishing"), "with its bonus")
assert(offered[1].selected(), "and is shown as chosen")
offered[2].pick()
equal(F:GearSlotValue(16), link(777), "picking from the menu sets the slot")
offered[#offered - 1].pick()
equal(F:GearSlotValue(16), "empty", "the menu can take the slot off")
offered[#offered].pick()
equal(F:GearSlotValue(16), nil, "or leave it alone")

-- Clearing everything takes two clicks.
window.clear.handlers.OnClick(window.clear)
assert(F:HasGearSet(), "one click only asks")
window.clear.handlers.OnClick(window.clear)
assert(not F:HasGearSet(), "the second click clears")
equal(window.status:GetText(), "Nothing chosen yet", "header says so")
equal(window.swap:IsEnabled(), false, "nothing to swap into")

window.find.handlers.OnClick(window.find)
equal(F:GearSlotValue(16), link(778), "the find button fills the outfit")
window:Hide()

print("-- the settings page --")
F:RegisterPage()
local byID = {}
for _, spec in ipairs(FEATURES) do byID[spec.id] = spec end
assert(byID["fishing.outfit"], "an outfit row")
assert(byID["fishing.outfit"].wide, "spanning the page")
assert(byID["fishing.outfit"].text():find("pieces"), "summarising the outfit: " .. byID["fishing.outfit"].text())
assert(byID["fishing.gearMacro"], "an action bar button")
assert(not byID["fishing.slot.16"], "no dropdown per slot")
byID["fishing.outfit"].run()
assert(window:IsShown(), "the row opens the outfit window")
window:Hide()
BAGS[778] = nil
assert(byID["fishing.outfit"].text():find("1 not in your bags"), "a missing piece is called out")
BAGS[778] = 1
F:Set("sound", false)
assert(not byID["fishing.volume"].available(), "volume waits for the louder splash")
assert(byID["fishing.volume"].unavailable, "and says why")
F:Set("sound", true)
assert(byID["fishing.volume"].available(), "and follows it")

---------------------------------------------------------------------------
print("-- the fishing window --")
-- Building the window is what caught a secure button missing BackdropTemplate.
F:SetupBar()
assert(F.bar, "the window exists")
equal(F.bar:IsShown(), false, "hidden without a pole")

POLES[777] = true
EQUIPPED[16] = link(777)
BAGS[6530] = 12        -- Nightcrawlers
BAGS[4593] = 3         -- fishing food
F:Set("bar", true)
F:UpdateBar()
equal(F.bar:IsShown(), true, "shown once a pole is in hand")
-- Drawing it builds the secure lure and food buttons, which is the path that
-- failed in game.
F:RefreshBar()
assert(_G.MiniQoLFishingLure1, "a lure button was built")
assert(_G.MiniQoLFishingFoodButton, "a food button was built")
equal(_G.MiniQoLFishingLure1.template, "SecureActionButtonTemplate, BackdropTemplate",
    "secure buttons also need a backdrop template")

F:RecordCast({ time = CLOCK, ended = CLOCK, caught = false })
F:Set("statsIncludeMissed", false)
F:RefreshBar()
assert(not F.bar.session:GetText():find("empty"), "empty casts stay off the session line by default")
F:Set("statsIncludeMissed", true)
assert(F.bar.session:GetText():find("1 empty"), "and appear once asked for: " .. F.bar.session:GetText())

EQUIPPED[16] = nil
F:UpdateBar()
equal(F.bar:IsShown(), false, "hidden again when the pole is put away")

---------------------------------------------------------------------------
print("-- the fishing window in a fight --")
-- The lure and food buttons cannot be touched in combat, so the row is left
-- as it was. Counting it afresh found nothing: the label said there were no
-- lures and the lines below moved up over the buttons.
EQUIPPED[16] = link(777)
F:UpdateBar()
local ruleY
F.bar.rule.SetPoint = function(_, _, _, y) ruleY = y end
F:RefreshBar()
local calm = ruleY
equal(F.bar.lureLabel:GetText(), "LURES", "lures are listed")
COMBAT = true
F:RefreshBar()
equal(F.bar.lureLabel:GetText(), "LURES", "and still are in a fight")
equal(ruleY, calm, "with the lines below staying below the buttons")
COMBAT = false

print("-- the share of casts --")
-- One cast landed a stack of three; one came up empty. That is half the
-- casts, not three hits in four.
F:ResetSession()
F:RecordCast({ time = CLOCK, ended = CLOCK, caught = true, seconds = 10 })
F:RecordCatch({ itemID = 6303, link = link(6303), quantity = 3, time = CLOCK,
    zone = "Elwynn Forest", subzone = "Crystal Lake" })
F:RecordCast({ time = CLOCK, ended = CLOCK, caught = false })
F:Set("statsIncludeMissed", true)
F:RefreshBar()
assert(F.bar.session:GetText():find("3 caught", 1, true), "three fish: " .. F.bar.session:GetText())
assert(F.bar.session:GetText():find("50% hit", 1, true), "from half the casts: " .. F.bar.session:GetText())

print("-- what the session has landed --")
-- The window lists everything caught this session, most caught first, under
-- the one thing landed last. It used to show the last four casts and no more.
local function shown(row) return row ~= nil and row.name:IsShown() end
local function land(itemID, quantity, secondsAgo, itemLink, icon)
    F:RecordCast({ time = CLOCK, ended = CLOCK, caught = true, seconds = 10 })
    F:RecordCatch({ itemID = itemID, link = itemLink or link(itemID), icon = icon, quantity = quantity,
        time = CLOCK - (secondsAgo or 0), zone = "Elwynn Forest", subzone = "Crystal Lake" })
end
local height
F.bar.SetHeight = function(_, value) height = value end
F:ResetSession()
F:RefreshBar()
equal(F.bar.empty:IsShown(), true, "an empty session says so")
equal(F.bar.empty:GetText(), "Nothing yet this session.", "in so many words")
equal(F.bar.lastLabel:IsShown(), false, "with no last catch")
equal(F.bar.lastAgo:IsShown(), false, "nor how long ago")
equal(F.bar.tallyLabel:IsShown(), false, "and no list")
equal(shown(F.bar.last), false, "the last session's catch is put away")
assert(F.bar.rows[1] and not shown(F.bar.rows[1]), "and so is its list")
local bare = height

land(6303, 3, 90)
land(6289, 1, 60)
land(6303, 2, 40)
land(6291, 2, 12)
F:RefreshBar()
equal(F.bar.empty:IsShown(), false, "a catch takes the empty line away")
equal(F.bar.lastLabel:IsShown(), true, "for the last catch")
equal(F.bar.tallyLabel:IsShown(), true, "and the list")
equal(F.bar.last.name:GetText(), "Item6291", "the last thing landed")
equal(F.bar.last.number:GetText(), "x2", "with how many came up")
equal(F.bar.lastAgo:GetText(), "12s ago", "and how long ago")
equal(F.bar.rows[1].name:GetText(), "Item6303", "the most caught heads the list")
equal(F.bar.rows[1].number:GetText(), 5, "with every cast of it added up")
equal(F.bar.rows[2].name:GetText(), "Item6291", "then the next")
equal(F.bar.rows[2].number:GetText(), 2, "by its count")
equal(F.bar.rows[3].name:GetText(), "Item6289", "down to the single fish")
equal(F.bar.rows[3].number:GetText(), 1, "which is one")
equal(F.bar.rows[3].icon:IsShown(), true, "each beside its icon")
assert(not shown(F.bar.rows[4]), "and nothing after it")
assert(height > bare, "the window grows to hold the list")
local three = height

-- An empty cast is neither the last catch nor a row, whatever the session
-- line counts.
F:RecordCast({ time = CLOCK, ended = CLOCK, caught = false })
F:Set("statsIncludeMissed", true)
F:RefreshBar()
equal(F.bar.last.name:GetText(), "Item6291", "an empty cast is not the last catch")
assert(shown(F.bar.rows[3]) and not shown(F.bar.rows[4]), "nor a row in the list")
equal(height, three, "so the window stays as it was")

local lastIcon
F.bar.last.icon.SetTexture = function(_, value) lastIcon = value end
land(6289, 1, 5, nil, 133)
F:RefreshBar()
equal(F.bar.last.name:GetText(), "Item6289", "a newer catch takes its place")
equal(F.bar.last.number:GetText(), "", "with no count beside a single fish")
equal(F.bar.lastAgo:GetText(), "5s ago", "and its own time")
equal(lastIcon, 133, "under the icon it was looted with")
equal(F.bar.rows[2].name:GetText(), "Item6289", "and it moves up the list")
equal(F.bar.rows[2].number:GetText(), 2, "as its count does")

-- Names take the colour of the item, in whichever form the link carries it.
local painted
F.bar.last.name.SetTextColor = function(_, r, g, b) painted = { r, g, b } end
land(6400, 1, 0, "|cff1eff00|Hitem:6400|h[Item6400]|h|r")
F:RefreshBar()
equal(math.floor(painted[1] * 255 + 0.5), 30, "an uncommon catch is green: red")
equal(math.floor(painted[2] * 255 + 0.5), 255, "green")
equal(math.floor(painted[3] * 255 + 0.5), 0, "and blue")
ITEM_QUALITY_COLORS = { [3] = { r = 0, g = 0.44, b = 0.87 } }
land(6401, 1, 0, "|cnIQ3:|Hitem:6401|h[Item6401]|h|r")
F:RefreshBar()
equal(F.bar.last.name:GetText(), "Item6401", "the newer form of link is read")
equal(painted[3], 0.87, "and coloured by its quality")
ITEM_QUALITY_COLORS = nil

-- More kinds than the window lists: the rarest share the last row.
F:ResetSession()
for itemID = 7001, 7010 do land(itemID, itemID - 7000) end
F:RefreshBar()
equal(F.bar.rows[1].name:GetText(), "Item7010", "the most caught first")
equal(F.bar.rows[7].name:GetText(), "Item7004", "seven kinds are named")
equal(F.bar.rows[8].name:GetText(), "3 others", "and the rest share a row")
equal(F.bar.rows[8].number:GetText(), 6, "with their catch added up")
equal(F.bar.rows[8].icon:IsShown(), false, "under no icon")
assert(not F.bar.rows[9], "so the list stops at eight rows")
F:ResetSession()
for itemID = 7001, 7008 do land(itemID, itemID - 7000) end
F:RefreshBar()
equal(F.bar.rows[8].name:GetText(), "Item7001", "eight kinds fit as they are")
equal(F.bar.rows[8].number:GetText(), 1, "each with its own count")
equal(F.bar.rows[8].icon:IsShown(), true, "and icon")

F:ResetSession()
land(6303, 1)
F:RefreshBar()
assert(shown(F.bar.rows[1]) and not shown(F.bar.rows[2]), "a shorter list puts the spare rows away")
assert(not F.bar.rows[2].icon:IsShown() and not F.bar.rows[2].number:IsShown(), "icon and count with them")
assert(height < three, "and the window shrinks back")
F.bar.SetHeight = nil

print("-- loot that is not an item --")
-- A currency in the loot has a link and no item ID. It is not a catch to
-- file, and the cast that landed it still landed something.
F:SetupCatches()
local catchEvents = scripts[#scripts]
F:ResetSession()
catchEvents:Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "cast", 7620)
LOOT = { { link = "|cffffffff|Hcurrency:61|h[Sea Shell]|h|r", quantity = 1 }, { link = link(6303), quantity = 2 } }
FISHING_LOOT = true
catchEvents:Fire("LOOT_READY")
catchEvents:Fire("LOOT_OPENED")
catchEvents:Fire("LOOT_CLOSED")
FISHING_LOOT, LOOT = false, {}
equal(select(3, F:SessionSummary(false)), 2, "the fish beside it are counted once")
local landed, empty = F:SessionCasts()
equal(landed, 1, "and the cast landed")
equal(empty, 0, "rather than coming up empty")

print("-- leaving with the line out --")
-- The game writes its sound settings down as it closes, so they go back
-- before it does, not only at the next login.
F:SetupSound()
local soundEvents = scripts[#scripts]
F:BoostSound()
equal(CVARS.Sound_MusicVolume, "0", "music is off while the line is out")
soundEvents:Fire("PLAYER_LOGOUT")
equal(CVARS.Sound_MusicVolume, "0.5", "and back on the way out")
equal(CVARS.Sound_MasterVolume, "0.3", "with the volume")
assert(not F:SoundBoosted(), "leaving nothing for the next login to undo")

print("-- the skill breakdown --")
-- The window asks for the breakdown every second, for its timers. Worn gear
-- and buffs are read when they change, not on every asking.
local GEAR_READS, BUFF_READS, POLE_BONUS = 0, 0, 20
local AURAS = { { auraInstanceID = 1, name = "Well Fed", expirationTime = NOW + 600 } }
function GetProfessions() return nil, nil, nil, 9 end
function GetProfessionInfo() return "Fishing", 1, 120, 150, 0, 0, 356, 25 end
C_TooltipInfo.GetInventoryItem = function(_, slot)
    GEAR_READS = GEAR_READS + 1
    if slot == 16 then return { lines = { { leftText = "Equip: Increased Fishing +" .. POLE_BONUS .. "." } } } end
end
C_TooltipInfo.GetUnitBuffByAuraInstanceID = function()
    BUFF_READS = BUFF_READS + 1
    return { lines = { { leftText = "Fishing skill increased by 10." } } }
end
C_UnitAuras = { GetBuffDataByIndex = function(_, index) return AURAS[index] end }
F:SetupCharacter()
local auraEvents = scripts[#scripts]
F:Fire("GEAR_CHANGED")
auraEvents:Fire("UNIT_AURA", "player")
local skill = F:Skill()
equal(skill.total, 120 + 25 + 20 + 10, "trained, lure, gear and food add up")
local gearReads, buffReads = GEAR_READS, BUFF_READS
for _ = 1, 5 do F:Skill() end
equal(GEAR_READS, gearReads, "worn gear is not read again while it is the same gear")
equal(BUFF_READS, buffReads, "nor the buffs")
POLE_BONUS = 5
equal(F:Skill().gear, 20, "a change nobody announced is not seen")
F:Fire("GEAR_CHANGED")
equal(F:Skill().gear, 5, "what is worn changing is announced, and read")
POLE_BONUS = 7
NOW = NOW + 11
equal(F:Skill().gear, 7, "and it is looked at again every so often regardless")
AURAS = {}
auraEvents:Fire("UNIT_AURA", "player")
equal(F:Skill().buffs, 0, "and so is a buff ending")

print("Fishing outfit swap, outfit window, gear finder, catch record, stats, splash, settings page, window and skill breakdown passed")
