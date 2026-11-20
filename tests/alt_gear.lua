-- Alt gear: every character's gear is written down as it changes, and any
-- other character can pick it from the character sheet and see it over their
-- own slots.
local root = ...
local function noop() end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local methods = {}
local function NewFrame(kind, parent, template)
    local frame = { kind = kind, parent = parent, template = template, scripts = {}, points = {},
        events = {}, shown = true, level = parent and parent.level + 1 or 1 }
    return setmetatable(frame, { __index = function(_, key)
        if methods[key] then return methods[key] end
        if type(key) == "string" and key:find("^%u") then return noop end
    end })
end
function methods:SetScript(name, fn) self.scripts[name] = fn end
function methods:GetScript(name) return self.scripts[name] end
function methods:HookScript(name, fn)
    local before = self.scripts[name]
    self.scripts[name] = function(...) if before then before(...) end; return fn(...) end
end
-- Showing and hiding run the frame's own scripts, as in game.
function methods:SetShown(value)
    value = value and true or false
    if value == self.shown then return end
    self.shown = value
    local script = self.scripts[value and "OnShow" or "OnHide"]
    if script then script(self) end
end
function methods:Show() self:SetShown(true) end
function methods:Hide() self:SetShown(false) end
function methods:IsShown() return self.shown end
function methods:SetPoint(...) self.points[#self.points + 1] = { ... } end
function methods:ClearAllPoints() self.points = {} end
function methods:SetAllPoints(target) self.allPoints = target or self.parent end
function methods:SetFrameLevel(level) self.level = level end
function methods:GetFrameLevel() return self.level end
function methods:SetWidth(width) self.width = width end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetText(text) self.text = text end
function methods:GetText() return self.text end
function methods:GetStringWidth() return #(self.text or "") * 6 end
function methods:SetTextColor(r, g, b) self.color = { r, g, b } end
function methods:SetTexture(texture) self.texture = texture end
function methods:SetTexCoord(...) self.coords = { ... } end
function methods:SetDesaturated(value) self.desaturated = value end
function methods:SetAlpha(value) self.alpha = value end
function methods:IsEnabled() return true end
function methods:IsMouseOver() return false end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:UnregisterEvent(event) self.events[event] = nil end
function methods:CreateTexture() return NewFrame("Texture", self) end
function methods:CreateFontString() return NewFrame("FontString", self) end
function methods:CreateLine() return NewFrame("Line", self) end
-- Only frames built with BackdropTemplate have the backdrop methods.
local function RequiresBackdrop(self, method)
    assert(self.template and self.template:find("BackdropTemplate"),
        "a " .. tostring(self.kind) .. " needs BackdropTemplate to call " .. method)
end
function methods:SetBackdrop() RequiresBackdrop(self, "SetBackdrop") end
function methods:SetBackdropColor() RequiresBackdrop(self, "SetBackdropColor") end
function methods:SetBackdropBorderColor(r, g, b)
    RequiresBackdrop(self, "SetBackdropBorderColor")
    self.border = { r, g, b }
end
function CreateFrame(kind, name, parent, template)
    local frame = NewFrame(kind, parent, template)
    if name then _G[name] = frame end
    return frame
end

-- The character sheet, which the game may load after Mini QoL.
local SHEET_SLOTS = { "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "ShirtSlot",
    "TabardSlot", "WristSlot", "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot",
    "Finger1Slot", "Trinket0Slot", "Trinket1Slot", "MainHandSlot", "SecondaryHandSlot", "RangedSlot" }
local function ClearSheet()
    CharacterFrame, PaperDollFrame = nil, nil
    for _, name in ipairs(SHEET_SLOTS) do _G["Character" .. name] = nil end
end
local function NewSheet(without)
    CharacterFrame = NewFrame("Frame")
    PaperDollFrame = NewFrame("Frame", CharacterFrame)
    local items = NewFrame("Frame", PaperDollFrame)
    for _, name in ipairs(SHEET_SLOTS) do
        _G["Character" .. name] = name ~= without and NewFrame("Button", items) or nil
    end
end

---------------------------------------------------------------------------
-- The game
---------------------------------------------------------------------------
CLOCK = 1700000000
function time() return CLOCK end
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function runTimers()
    local due = timers
    timers = {}
    for _, fn in ipairs(due) do fn() end
end

local function ItemID(link) return tonumber(tostring(link):match("item:(%d+)")) end
local function link(id, name, quality)
    return ("|cnIQ%d:|Hitem:%d::::::::60:::::|h[%s]|h|r"):format(quality or 3, id, name)
end

local player -- whoever is logged in
function UnitName() return player.name end
function GetRealmName() return player.realm end
function GetNormalizedRealmName() return (player.realm:gsub(" ", "")) end
function UnitClass() return player.className, player.class end
function UnitRace() return player.race, player.race end
function UnitLevel() return player.level end
function UnitFactionGroup() return player.faction, player.faction end
function GetInventoryItemLink(_, slot) return player.items[slot] end
-- The game knows what is in a slot before it can describe it.
function GetInventoryItemID(_, slot) return player.loading[slot] or ItemID(player.items[slot]) end

local LOCATIONS = { [60] = "INVTYPE_2HWEAPON" }
local LEVELS = { [50] = 50, [60] = 60 }
function GetItemInfoInstant(id) return id, "Armor", "Cloth", LOCATIONS[id] or "INVTYPE_HEAD", "icon" .. id end
function GetItemInfo() return nil end -- nothing cached: quality comes from the link
function GetDetailedItemLevelInfo(itemLink) return LEVELS[ItemID(itemLink)] end
ITEM_QUALITY_COLORS = { [2] = { r = 0.12, g = 1, b = 0 }, [3] = { r = 0, g = 0.44, b = 0.87 },
    [4] = { r = 0.64, g = 0.21, b = 0.93 } }
RAID_CLASS_COLORS = { SHAMAN = { r = 0, g = 0.44, b = 0.87 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 },
    PALADIN = { r = 0.96, g = 0.55, b = 0.73 } }
CLASS_ICON_TCOORDS = { SHAMAN = { 0.25, 0.49, 0.25, 0.5 }, MAGE = { 0.25, 0.49, 0, 0.25 },
    PALADIN = { 0, 0.25, 0.5, 0.75 } }

GameTooltip = { lines = {} }
function GameTooltip:SetOwner(owner) self.owner, self.lines, self.title, self.hyperlink = owner, {}, nil, nil end
function GameTooltip:SetHyperlink(value) self.hyperlink = value end
function GameTooltip:SetText(text) self.title = text end
function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
GameTooltip.Show, GameTooltip.Hide = noop, noop
local function TooltipSays(text)
    for _, line in ipairs(GameTooltip.lines) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

local modified
function HandleModifiedItemClick(value) modified = value; return true end
local popup
function StaticPopup_Show(name) popup = name end
StaticPopupDialogs, YES, NO = {}, "Yes", "No"

-- The game's menus, as a tree the test can read and click.
local function Strip(text) return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function Description(text, kind)
    local d = { text = text, kind = kind, children = {}, enabled = true }
    function d:Add(child) self.children[#self.children + 1] = child; return child end
    function d:CreateTitle(value) return self:Add(Description(value, "title")) end
    function d:CreateRadio(value, isSelected, select)
        local child = Description(value, "radio")
        child.isSelected, child.select = isSelected, select
        return self:Add(child)
    end
    function d:CreateButton(value, fn)
        local child = Description(value, "button")
        child.click = fn
        return self:Add(child)
    end
    function d:CreateDivider() return self:Add(Description(nil, "divider")) end
    function d:SetEnabled(value) self.enabled = value end
    return d
end
local menu
local Menus = { CreateContextMenu = function(owner, generator)
    menu = Description("root", "root")
    menu.owner = owner
    generator(owner, menu)
end }
MenuUtil = Menus
MenuResponse = { Close = "close", CloseAll = "closeAll" }
local function Find(parent, needle)
    for _, child in ipairs(parent.children) do
        if child.text and Strip(child.text):find(needle, 1, true) then return child end
    end
end
local function Radios()
    local list = {}
    for _, child in ipairs(menu.children) do
        if child.kind == "radio" then list[#list + 1] = child end
    end
    return list
end

---------------------------------------------------------------------------
-- Mini QoL, logged in as one character after another
---------------------------------------------------------------------------
MiniQoLDB = {}
local printed, features = {}, {}
local refreshes = 0 -- each save repaints the settings page
local function Session(character)
    player = character
    GetAverageItemLevel = character.itemLevel and function() return character.itemLevel, character.itemLevel end or nil
    local ns = { db = MiniQoLDB }
    function ns:Print(message) printed[#printed + 1] = message end
    function ns:RegisterFeature(spec) features[spec.id] = spec end
    function ns:Refresh() refreshes = refreshes + 1 end
    assert(loadfile(root .. "/Theme.lua"))("MiniQoL", ns)
    assert(loadfile(root .. "/AltGear.lua"))("MiniQoL", ns)
    ns.AltGear:Start()
    return ns.AltGear
end
local function fire(A, event, ...)
    assert(A.events.events[event], "listens for " .. event)
    A.events.scripts.OnEvent(A.events, event, ...)
end
local function Record(key) return MiniQoLDB.altGear.characters[key] end
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function near(actual, expected, label)
    assert(type(actual) == "number" and math.abs(actual - expected) < 0.01, label .. ": " .. tostring(actual))
end
local function click(button, which) button.scripts.OnClick(button, which or "LeftButton") end

---------------------------------------------------------------------------
-- 1. Thrall logs in before the character sheet has loaded
---------------------------------------------------------------------------
local thrall = { name = "Thrall", realm = "Realm", class = "SHAMAN", className = "Shaman", race = "Orc",
    level = 60, faction = "Horde", itemLevel = 58.4, loading = {}, items = {
        [1] = link(101, "Helm of Ten Storms", 4), [3] = link(103, "Epaulets of Ten Storms", 4),
        [5] = link(105, "Breastplate of Ten Storms", 4), [16] = link(116, "Doomhammer", 4),
        [17] = link(117, "Totemic Shield", 3), [18] = link(118, "Totem of Rage", 3) } }
ClearSheet()
local A = Session(thrall)
assert(not A.hooked, "no sheet to put a button on yet")
fire(A, "PLAYER_ENTERING_WORLD")
local record = Record("Thrall-Realm")
assert(record, "logging in writes the character down")
equal(record.items[1], thrall.items[1], "with what is on the head")
equal(record.items[18], thrall.items[18], "and in every other slot")
equal(record.items[4], nil, "a bare slot stays bare")
equal(record.name, "Thrall", "named")
equal(record.class, "SHAMAN", "with the class")
equal(record.className, "Shaman", "as the game words it")
equal(record.race, "Orc", "the race")
equal(record.level, 60, "the level")
equal(record.realm, "Realm", "the realm")
near(record.itemLevel, 58.4, "and the game's own item level")
equal(record.saved, CLOCK, "and when")

NewSheet()
fire(A, "ADDON_LOADED", "Blizzard_UIPanels_Game")
assert(A.hooked, "the sheet is found once it loads")
assert(not A.events.events.ADDON_LOADED, "and then it stops looking")
local button = A.button
assert(button and button.shown, "an Alts button on the sheet")
equal(button.points[1][2], CharacterTrinket1Slot, "beside the bottom of the right-hand column")
equal(button.label.text, "Alts", "saying what it is for")

-- Nobody else yet: the menu says how they are added.
click(button)
equal(menu.owner, button, "a click opens the menu")
assert(Radios()[1].isSelected(), "with you chosen")
equal(#Radios(), 1, "and nobody else")
local note = Find(menu, "No other characters")
assert(note and not note.enabled, "it says there is no one else yet")
assert(not Find(menu, "Forget"), "and has nothing to forget")

---------------------------------------------------------------------------
-- 2. Kept up to date
---------------------------------------------------------------------------
CLOCK = CLOCK + 600
local oldHelm = thrall.items[1]
thrall.items[1] = link(201, "Helm of the Fallen Champion", 4)
fire(A, "PLAYER_EQUIPMENT_CHANGED", 1, false)
fire(A, "PLAYER_EQUIPMENT_CHANGED", 1, true)
equal(Record("Thrall-Realm").items[1], oldHelm, "written once the swap settles")
local saves = refreshes
runTimers()
equal(refreshes - saves, 1, "one write for the whole swap")
equal(Record("Thrall-Realm").items[1], thrall.items[1], "then the new helm is down")
equal(Record("Thrall-Realm").saved, CLOCK, "as of now")

-- The game knows the item but has not described it yet.
local chest = thrall.items[5]
thrall.items[5], thrall.loading[5] = nil, 105
fire(A, "PLAYER_EQUIPMENT_CHANGED", 5, true)
runTimers()
equal(Record("Thrall-Realm").items[5], chest, "an item still loading keeps the link written before")
equal(#timers, 1, "and the save is tried again")
thrall.items[5], thrall.loading[5] = chest, nil
runTimers()
equal(#timers, 0, "until everything is described")

thrall.items[10] = "|cnIQ3:|Hitem:110::::::::60:::::|h[]|h|r"
fire(A, "PLAYER_EQUIPMENT_CHANGED", 10, false)
runTimers()
equal(Record("Thrall-Realm").items[10], thrall.items[10], "a new item is kept as the game gave it")
thrall.items[10] = link(110, "Gauntlets of Ten Storms", 4)
runTimers()
equal(Record("Thrall-Realm").items[10], thrall.items[10], "and named on the next try")

thrall.loading[8] = 108
fire(A, "PLAYER_EQUIPMENT_CHANGED", 8, false)
runTimers()
equal(Record("Thrall-Realm").items[8], "item:108", "with no link at all, the item is still known")
for _ = 1, 10 do runTimers() end
equal(#timers, 0, "and it gives up asking after a few tries")
thrall.loading[8] = nil

fire(A, "PLAYER_LEVEL_UP", 61)
equal(Record("Thrall-Realm").level, 61, "a level-up counts before the game reports it")
thrall.level = 61

thrall.items[15] = link(115, "Cloak of the Shrouded Mists", 3)
fire(A, "PLAYER_LOGOUT")
equal(Record("Thrall-Realm").items[15], thrall.items[15], "logging out writes the last change at once")

---------------------------------------------------------------------------
-- 3. Uther, on another realm, with the sheet loaded before Mini QoL starts
---------------------------------------------------------------------------
CLOCK = CLOCK + 3600
NewSheet()
local uther = { name = "Uther", realm = "Argent Dawn", class = "PALADIN", className = "Paladin",
    race = "Human", level = 70, faction = "Alliance", itemLevel = 70, loading = {},
    items = { [1] = link(401, "Judgement Crown", 4) } }
local B = Session(uther)
assert(B.hooked and not B.events.events.ADDON_LOADED, "a sheet that is already there is used at once")
fire(B, "PLAYER_ENTERING_WORLD")
assert(Record("Uther-ArgentDawn"), "each character has its own entry")
equal(Record("Uther-ArgentDawn").realm, "Argent Dawn", "under its realm")

-- Logging out. The game stops giving the realm's short name, and stops
-- answering about equipment: every slot reads bare. This was saved as a
-- second Uther, under "Argent Dawn", with nothing worn and item level 0.
local crown = uther.items[1]
local normalized = GetNormalizedRealmName
GetNormalizedRealmName = function() return nil end
uther.items, GetAverageItemLevel = {}, function() return 0, 0 end
CLOCK = CLOCK + 60
fire(B, "PLAYER_LOGOUT")
equal(MiniQoLDB.altGear.characters["Uther-Argent Dawn"], nil, "no second Uther under the realm's full name")
equal(Record("Uther-ArgentDawn").items[1], crown, "and the one Uther keeps his crown")
equal(Record("Uther-ArgentDawn").itemLevel, 70, "and his item level")
GetNormalizedRealmName = normalized
uther.items = { [1] = crown }

---------------------------------------------------------------------------
-- 4. Jaina looks at the others
---------------------------------------------------------------------------
CLOCK = CLOCK + 7200
NewSheet("RangedSlot") -- this sheet has no ranged slot
local jaina = { name = "Jaina", realm = "Realm", class = "MAGE", className = "Mage", race = "Human",
    level = 42, faction = "Alliance", loading = {},
    items = { [1] = link(50, "Hat", 2), [16] = link(60, "Staff", 3) } }
-- Entries a logout already filed under a realm's full name: an empty one
-- newer than Uther's own, and a Thrall with gear newer than his.
local characters = MiniQoLDB.altGear.characters
characters["Uther-Argent Dawn"] = { name = "Uther", realm = "Argent Dawn", class = "PALADIN", level = 70,
    itemLevel = 0, items = {}, saved = CLOCK }
local newerThrall = { name = "Thrall", realm = "Realm", class = "SHAMAN", level = 61, itemLevel = 59,
    items = { [1] = link(202, "Helm of the Newer Save", 4) }, saved = CLOCK }
characters["Thrall-Realm "] = newerThrall
local thrallBefore = characters["Thrall-Realm"]
local C = Session(jaina)
fire(C, "PLAYER_ENTERING_WORLD")
equal(characters["Uther-Argent Dawn"], nil, "the empty Uther is folded away")
equal(Record("Uther-ArgentDawn").items[1], crown, "keeping the one with his gear")
equal(characters["Thrall-Realm "], nil, "the second Thrall too")
equal(Record("Thrall-Realm"), newerThrall, "the newer of two with gear is kept")
characters["Thrall-Realm"] = thrallBefore
-- With no item level from the game, it is worked out the game's way: the
-- staff fills both hands, out of the sixteen slots this sheet counts.
near(Record("Jaina-Realm").itemLevel, (50 + 60 + 60) / 16, "an item level of her own")
button = C.button

click(button, "RightButton")
equal(menu.owner, button, "a right-click opens the menu too")
local radios = Radios()
equal(#radios, 3, "you and the two others")
assert(Strip(radios[1].text):find("Jaina", 1, true) and radios[1].isSelected(), "you first, chosen")
assert(Strip(radios[2].text):find("Thrall", 1, true), "then this realm")
assert(Strip(radios[3].text):find("Uther", 1, true), "then other realms, though higher level")
assert(Strip(radios[3].text):find("Argent Dawn", 1, true), "naming the other realm")
assert(not Strip(radios[2].text):find("Realm", 1, true), "but not your own")
assert(Strip(radios[2].text):find("level 61", 1, true), "with each one's level")
assert(Find(menu, "Forget a character"), "and a way to forget one")

equal(radios[2].select(), "close", "picking one closes the menu")
local overlay = C.overlay
assert(overlay and overlay.shown, "Thrall's gear goes on show")
equal(select(2, C:Viewing()), "Thrall-Realm", "Thrall is the one viewed")
equal(button.label.text, "Thrall", "the button names who is on show")
equal(#overlay.slots, 18, "one slot for each the sheet has")
local function SlotFor(id)
    for _, slot in ipairs(overlay.slots) do
        if slot.info.id == id then return slot end
    end
end
local head = SlotFor(1)
equal(head.allPoints, CharacterHeadSlot, "exactly over your own head slot")
equal(head.icon.texture, "icon201", "showing Thrall's helm")
near(head.border[1], 0.64, "edged in its quality colour")
local shirt = SlotFor(4)
equal(shirt.allPoints, CharacterShirtSlot, "the shirt over the shirt")
equal(shirt.icon.texture, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Shirt", "a bare slot shows the empty artwork")
assert(shirt.icon.desaturated, "greyed")
equal(SlotFor(18), nil, "nothing for a slot the sheet does not have")
assert(overlay.level > CharacterHeadSlot.level, "above your own slots")
assert(button.level > overlay.card.level, "the button stays above the card, so you can switch")

local card = overlay.card
equal(card.name.text, "Thrall", "the card names the character")
near(card.name.color[3], 0.87, "in the class colour")
equal(card.icon.coords[1], 0.25, "with the class icon")
local details = card.details.text
assert(details:find("Level 61 Orc Shaman", 1, true), details)
assert(details:find("Item level 58", 1, true), details)
assert(details:find("Saved 3 hours ago", 1, true), details)
assert(not details:find("Realm", 1, true), "your own realm goes without saying")

head.scripts.OnEnter(head)
equal(GameTooltip.hyperlink, "item:201::::::::60:::::", "hovering shows the item's own tooltip")
assert(TooltipSays("Thrall's gear, saved 3 hours ago."), "and whose it is")
click(head)
equal(modified, thrall.items[1], "a click goes to the game's link and try-on handling")
shirt.scripts.OnEnter(shirt)
equal(GameTooltip.title, "Shirt", "a bare slot names itself")
assert(TooltipSays("Nothing worn here."), "and says it is empty")
modified = nil
click(shirt)
equal(modified, nil, "and has nothing to link")
click(head, "RightButton")
equal(menu.owner, head, "right-clicking a slot opens the menu")
card.scripts.OnMouseUp(card, "RightButton")
equal(menu.owner, card, "as does right-clicking the card")

-- Tabs keep the choice; closing the sheet does not.
PaperDollFrame:Hide()
PaperDollFrame:Show()
assert(overlay.shown and button.label.text == "Thrall", "changing tabs keeps Thrall on show")
CharacterFrame:Hide()
assert(not overlay.shown, "closing the sheet puts your own gear back")
equal(button.label.text, "Alts", "and the button says so")
CharacterFrame:Show()

C:View("Uther-ArgentDawn")
assert(card.details.text:find("Argent Dawn", 1, true), "another realm is named on the card")
click(card.close)
assert(not overlay.shown, "the card's close button goes back to your own gear")

C:View("Thrall-Realm")
click(button)
Radios()[1].select()
assert(not overlay.shown, "choosing yourself does too")
equal(C:View("Jaina-Realm"), false, "you are never shown as an alt")
equal(C:View("Nobody-Realm"), false, "nor is someone never seen")

-- A client without the game's menus: each click moves to the next character.
MenuUtil = nil
click(button)
equal(select(2, C:Viewing()), "Thrall-Realm", "first one")
click(button)
equal(select(2, C:Viewing()), "Uther-ArgentDawn", "then the next")
click(button)
equal(select(2, C:Viewing()), nil, "then back to you")
MenuUtil = Menus

---------------------------------------------------------------------------
-- 5. The settings page
---------------------------------------------------------------------------
-- Where the button is, with the key that opens the sheet as it is bound.
local where = features["altGear.where"].get()
assert(where:find("character sheet", 1, true) and where:find("Alts", 1, true), "the page says where the button is: " .. where)
assert(where:find("bottom right", 1, true), "whereabouts on the sheet")
assert(not where:find("()", 1, true), "with no key it names none")
function GetBindingKey(action) return action == "TOGGLECHARACTER0" and "C" or nil end
function GetBindingText(key) return key end
assert(features["altGear.where"].get():find("character sheet (C)", 1, true), "and the key that opens it")
GetBindingKey, GetBindingText = nil, nil
local summary = features["altGear.known"].get()
assert(summary:find("^3 characters: Jaina %(you%)"), summary)
assert(Strip(summary):find("Thrall 61", 1, true), summary)
assert(features["altGear.forget"].available(), "others to forget")
features["altGear.forget"].run()
equal(popup, "MINIQOL_ALTGEAR_FORGET", "forgetting them all asks first")

-- Forget one from the menu.
C:View("Uther-ArgentDawn")
click(button)
local forget = Find(menu, "Forget a character")
equal(Find(forget, "Uther").click(), "closeAll", "forgetting closes the menu and its submenu")
equal(Record("Uther-ArgentDawn"), nil, "Uther is forgotten")
assert(not overlay.shown, "and no longer on show")
assert(printed[#printed]:find("Uther", 1, true), "and it says so")
click(button)
equal(#Radios(), 2, "the menu is down to you and Thrall")

-- Off: no button, nothing written.
C:View("Thrall-Realm")
features["altGear.enabled"].set(false)
equal(features["altGear.enabled"].get(), false, "turned off")
assert(features["altGear.where"].get():find("^Turn this on"), "the page says how to get the button back")
assert(not button.shown, "the button goes")
assert(not overlay.shown, "and your own gear is back")
local before = Record("Jaina-Realm").saved
CLOCK = CLOCK + 60
jaina.items[1] = link(301, "Better Hat", 2)
fire(C, "PLAYER_EQUIPMENT_CHANGED", 1, true)
runTimers()
equal(Record("Jaina-Realm").saved, before, "changes are not written down")
equal(C:View("Thrall-Realm"), false, "and no one can be shown")
features["altGear.enabled"].set(true)
assert(button.shown, "on again: the button is back")
equal(Record("Jaina-Realm").items[1], jaina.items[1], "and you are written down at once")

StaticPopupDialogs.MINIQOL_ALTGEAR_FORGET.OnAccept()
assert(Record("Jaina-Realm") and not Record("Thrall-Realm"), "forgetting the others keeps you")
equal(features["altGear.forget"].available(), false, "then there is no one left to forget")
assert(features["altGear.known"].get():find("^1 character: Jaina"), "and the page says so")

-- How long ago.
equal(C.Ago(CLOCK - 30), "just now", "seconds")
equal(C.Ago(CLOCK - 300), "5 minutes ago", "minutes")
equal(C.Ago(CLOCK - 3600), "1 hour ago", "one hour")
equal(C.Ago(CLOCK - 3 * 86400), "3 days ago", "days")

print("Alt gear: saved on login, gear changes, level-up and logout; a late sheet; menu, overlay, tooltips, tabs, forgetting and the setting passed")
