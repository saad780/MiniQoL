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
for _, name in ipairs({ "SetSize", "SetPoint", "ClearAllPoints", "Show", "Hide", "SetShown", "SetAttribute",
    "RegisterForClicks", "SetFrameStrata", "SetClampedToScreen", "SetMovable", "EnableMouse",
    "RegisterForDrag", "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetWidth",
    "SetHeight", "SetAllPoints", "SetTexture", "SetTexCoord", "SetJustifyH", "SetText", "SetTextColor",
    "SetWordWrap", "SetColorTexture", "SetDesaturated", "SetTexelSnappingBias", "SetSnapToPixelGrid" }) do
    frame[name] = noop
end
function frame:IsShown() return false end
function frame:CreateTexture() return setmetatable({ handlers = {}, events = {} }, frame) end
function frame:CreateFontString() return setmetatable({ handlers = {}, events = {} }, frame) end
function CreateFrame()
    local f = setmetatable({ handlers = {}, events = {} }, frame)
    scripts[#scripts + 1] = f
    return f
end

NOW, CLOCK = 1000, 1700000000
function GetTime() return NOW end
function time() return CLOCK end
function date(_, stamp) return { hour = 12 } end
C_Timer = { After = function(_, fn) end, NewTimer = function() return { Cancel = noop } end,
    NewTicker = function() return { Cancel = noop } end }
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
    SetItemByID = noop }
WorldFrame = CreateFrame()
UIParent = CreateFrame()
StaticPopupDialogs, SlashCmdList = {}, {}
function StaticPopup_Show() end
YES, NO = "Yes", "No"
function SetOverrideBinding() end
function SetOverrideBindingClick() end
function ClearOverrideBindings() end
C_Spell = { GetSpellName = function(id) return id == 7620 and "Fishing" or ("Spell" .. tostring(id)) end }
C_Item = {
    GetItemInfo = function(id) return "Item" .. id, "|cffffffff|Hitem:" .. id .. "|h[Item" .. id .. "]|h|r" end,
    GetItemCount = function(id) return BAGS[id] or 0 end,
    GetItemIconByID = function() return 1 end,
    GetItemInfoInstant = function(id) return id, nil, nil, nil, nil, (POLES[id] and 2 or 4), (POLES[id] and 20 or 1) end,
}
BAGS, POLES = {}, {}
EQUIPPED = {}
function GetInventoryItemLink(_, slot) return EQUIPPED[slot] end
function GetInventoryItemID(_, slot)
    local link = EQUIPPED[slot]
    return link and tonumber(link:match("item:(%d+)")) or nil
end
EQUIPS = {}
function EquipItemByName(link, slot) EQUIPS[#EQUIPS + 1] = { link = link, slot = slot } EQUIPPED[slot] = link end
CURSOR = nil
function PickupInventoryItem(slot) CURSOR = EQUIPPED[slot] EQUIPPED[slot] = nil end
function CursorHasItem() return CURSOR ~= nil end
function PutItemInBackpack() CURSOR = nil end
function ClearCursor() CURSOR = nil end
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
function ns:Print(message) PRINTED = message end
function ns:RegisterFeature(spec) FEATURES[#FEATURES + 1] = spec end
function ns:ShowPage() end
FEATURES = {}
ns.Theme = { Chrome = noop, Text = function() return setmetatable({ handlers = {}, events = {} }, frame) end,
    Window = noop, Rule = function() return setmetatable({ handlers = {}, events = {} }, frame) end,
    CloseButton = function() return setmetatable({ handlers = {}, events = {} }, frame) end,
    Color = function(c) return c[1], c[2], c[3], c[4] end,
    BG_CARD = { 0, 0, 0, 1 }, GOLD = { 1, 1, 1, 1 }, MUTED = { 1, 1, 1, 1 }, TEXT = { 1, 1, 1, 1 },
    INFO = { 1, 1, 1, 1 }, GOLD_SOFT = { 1, 1, 1, 1 }, BORDER_HI = { 1, 1, 1, 1 } }

local base = root .. "/Fishing/"
for _, file in ipairs({ "Core", "Catches", "Sound", "Character", "Lures", "Stats", "Gear", "Page" }) do
    assert(loadfile(base .. file .. ".lua"))("MiniQoL", ns)
end
local F = ns.Fishing
F:Initialize()

local function link(id) return "|cffffffff|Hitem:" .. id .. "|h[Item" .. id .. "]|h|r" end
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

-- Now dress in ordinary gear and swap.
EQUIPPED[1], EQUIPPED[5], EQUIPPED[15], EQUIPPED[16] = link(201), link(205), link(215), link(216)
EQUIPS = {}
F:SwapToGear()
equal(F:WearingGear(), true, "wearing the outfit")
equal(EQUIPPED[16], link(777), "pole equipped")
equal(EQUIPPED[5], link(105), "fishing chest equipped")
equal(EQUIPPED[15], nil, "a slot the outfit empties is taken off")
equal(EQUIPPED[1], link(201), "an ignored slot keeps what it had")

print("-- swapping back --")
F:SwapBack()
equal(F:WearingGear(), false, "back in your own gear")
equal(EQUIPPED[16], link(216), "the old weapon is back")
equal(EQUIPPED[5], link(205), "the old chest is back")
equal(EQUIPPED[15], link(215), "the cloak that was taken off is back")
equal(EQUIPPED[1], link(201), "the ignored slot never moved")

print("-- one action toggles --")
F:ToggleGear()
equal(F:WearingGear(), true, "toggle swaps in")
F:ToggleGear()
equal(F:WearingGear(), false, "toggle swaps back")
equal(EQUIPPED[15], link(215), "and restores again")

COMBAT = true
F:ToggleGear()
equal(F:WearingGear(), false, "combat refuses the swap")
assert(PRINTED:find("combat"), "and says why")
COMBAT = false

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
print("-- the settings page --")
F:RegisterPage()
local byID = {}
for _, spec in ipairs(FEATURES) do byID[spec.id] = spec end
assert(byID["fishing.gearSnapshot"], "a save button")
assert(byID["fishing.gearMacro"], "an action bar button")
assert(byID["fishing.slot.16"], "a row for the main hand")
local options = byID["fishing.slot.16"].options()
equal(options[#options][1], "ignore", "every slot can be left alone")
equal(options[#options - 1][1], "empty", "or deliberately emptied")
byID["fishing.slot.16"].set("empty")
equal(F:GearSlotValue(16), "empty", "set through the page")
byID["fishing.slot.16"].set("ignore")
equal(F:GearSlotValue(16), nil, "and cleared through the page")

print("Fishing outfit swap, catch record, stats, splash and settings rows passed")
