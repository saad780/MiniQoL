local _, ns = ...
-- Alt gear: what each character wears is written down whenever it changes, so
-- any other character on the account can look at it on the character sheet.
-- An Alts button there picks a character; their gear then covers your own
-- slots, with the usual item tooltips, until you pick yourself again or close
-- the sheet. Gear lives in MiniQoL's shared character records.
local AltGear = {}
ns.AltGear = AltGear
local T = ns.Theme

local SAVE_DELAY = 0.5             -- a swap moves several items; write once it settles
local RETRY_DELAY, RETRIES = 2, 5  -- for items the game is still describing
local GAP = 4
local BUTTON_W, BUTTON_H = 56, 20
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local CLASS_ICONS = "Interface\\TargetingFrame\\UI-Classes-Circles"
local WELL = { 0.03, 0.028, 0.024, 0.92 }
local IDLE_BORDER = { 0.22, 0.20, 0.15, 1 }
local CARD_BG = { 0.052, 0.047, 0.040, 0.95 }

-- Every slot on the sheet: its button (named "Character" .. button), the
-- inventory slot, what to call it and the game's empty-slot artwork. A slot
-- this client's sheet does not have is left out.
local SLOTS = {
    { button = "HeadSlot", id = 1, name = "Head", art = "Head" },
    { button = "NeckSlot", id = 2, name = "Neck", art = "Neck" },
    { button = "ShoulderSlot", id = 3, name = "Shoulder", art = "Shoulder" },
    { button = "BackSlot", id = 15, name = "Back", art = "Chest" },
    { button = "ChestSlot", id = 5, name = "Chest", art = "Chest" },
    { button = "ShirtSlot", id = 4, name = "Shirt", art = "Shirt" },
    { button = "TabardSlot", id = 19, name = "Tabard", art = "Tabard" },
    { button = "WristSlot", id = 9, name = "Wrist", art = "Wrists" },
    { button = "HandsSlot", id = 10, name = "Hands", art = "Hands" },
    { button = "WaistSlot", id = 6, name = "Waist", art = "Waist" },
    { button = "LegsSlot", id = 7, name = "Legs", art = "Legs" },
    { button = "FeetSlot", id = 8, name = "Feet", art = "Feet" },
    { button = "Finger0Slot", id = 11, name = "Ring", art = "Finger" },
    { button = "Finger1Slot", id = 12, name = "Ring", art = "Finger" },
    { button = "Trinket0Slot", id = 13, name = "Trinket", art = "Trinket" },
    { button = "Trinket1Slot", id = 14, name = "Trinket", art = "Trinket" },
    { button = "MainHandSlot", id = 16, name = "Main hand", art = "MainHand" },
    { button = "SecondaryHandSlot", id = 17, name = "Off hand", art = "SecondaryHand" },
    { button = "RangedSlot", id = 18, name = "Ranged", art = "Ranged" },
}
AltGear.SLOTS = SLOTS
-- Left out of the item level, as on the game's own sheet.
local COSMETIC = { [4] = true, [19] = true }
local MAIN_HAND, OFF_HAND = 16, 17

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetDetailedItemLevelInfo = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo

local viewing           -- the key of the character on show, or nil for yourself
local sheetButton, overlay
local saveToken = 0

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local Characters = ns.Characters
local HomeRealm, CharacterKey = Characters.Realm, Characters.PlayerKey
AltGear.CharacterKey = CharacterKey

local function HasGear(record)
    return type(record.items) == "table" and next(record.items) ~= nil
end

local function Hex(color)
    return ("|cff%02x%02x%02x"):format(color[1] * 255, color[2] * 255, color[3] * 255)
end

local function ItemID(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- A link the game has finished describing carries the item's name.
local function Named(link)
    return type(link) == "string" and link:find("|h%[.+%]|h") ~= nil
end

local function Hyperlink(link)
    return link:match("|H(item:[^|]+)|h") or link
end

local function LinkName(link)
    return link:match("|h%[(.-)%]|h")
end

local function Icon(link)
    local id = ItemID(link)
    if not (id and GetItemInfoInstant) then return nil end
    local _, _, _, _, icon = GetItemInfoInstant(id)
    return icon
end

local function EquipLocation(link)
    local id = ItemID(link)
    if not (id and GetItemInfoInstant) then return nil end
    local _, _, _, location = GetItemInfoInstant(id)
    return location
end

-- The item's quality, from the game if it has the item to hand, otherwise
-- from the colour written into the link (both the old "|cffRRGGBB" and the
-- newer "|cnIQ4:" kinds).
local function QualityColor(link)
    local quality = GetItemInfo and select(3, GetItemInfo(link))
    quality = quality or tonumber(link:match("|cnIQ(%d+):"))
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color and color.r then return { color.r, color.g, color.b, 1 } end
    return T:QualityColor(link)
end

local function ClassColor(class)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color and color.r then return { color.r, color.g, color.b, 1 } end
    return T.TEXT
end

local function Ago(stamp)
    local seconds = math.max(0, time() - (stamp or 0))
    if seconds < 90 then return "just now" end
    local function count(amount, unit)
        amount = math.floor(amount)
        return amount .. " " .. unit .. (amount == 1 and "" or "s") .. " ago"
    end
    if seconds < 3600 then return count(seconds / 60, "minute") end
    if seconds < 172800 then return count(seconds / 3600, "hour") end
    return count(seconds / 86400, "day")
end
AltGear.Ago = Ago

-- "Level 60 Orc Shaman", from whatever was written down.
local function Describe(record)
    local parts = { "Level " .. (record.level or "?") }
    if record.race then parts[#parts + 1] = record.race end
    if record.className then parts[#parts + 1] = record.className end
    return table.concat(parts, " ")
end

local function Slot(name)
    return _G["Character" .. name]
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
function AltGear:Initialize()
    local db = ns.db
    if type(db.altGear) ~= "table" then db.altGear = {} end
    self.db = db.altGear
    if self.db.enabled == nil then self.db.enabled = true end
    self.retries = 0
    return self
end

function AltGear:Enabled()
    return self.db ~= nil and self.db.enabled ~= false
end

function AltGear:SetEnabled(value)
    if not self.db then return end
    self.db.enabled = value and true or false
    if self.db.enabled then self:Save() end
    self:Refresh()
end

function AltGear:Record(key)
    local record = Characters.records and Characters.records[key]
    return type(record) == "table" and record.items and record or nil
end

-- What is worn in every slot. An item the game is still describing comes back
-- without a link, or with a link that has no name yet: the one written last
-- time stands in when it is the same item, and the save is tried again.
function AltGear:ReadWorn(previous)
    local items, incomplete = {}, false
    for _, slot in ipairs(SLOTS) do
        local id = GetInventoryItemID("player", slot.id)
        local link = GetInventoryItemLink("player", slot.id)
        if id and not Named(link) then
            incomplete = true
            local before = previous and previous[slot.id]
            if ItemID(before) == id and Named(before) then link = before end
            link = link or ("item:" .. id)
        end
        items[slot.id] = link
    end
    return items, incomplete
end

-- The game's own average where it has one; otherwise worked out the same
-- way: every slot but the shirt and tabard, a two-hander filling both hands.
local function AverageItemLevel(items)
    if GetAverageItemLevel then
        local ok, _, equipped = pcall(GetAverageItemLevel)
        if ok and type(equipped) == "number" and equipped > 0 then return equipped end
    end
    if not GetDetailedItemLevelInfo then return nil end
    local total, slots = 0, 0
    for _, slot in ipairs(SLOTS) do
        if not COSMETIC[slot.id] and (slot.id ~= 18 or Slot(slot.button)) then
            slots = slots + 1
            local link = items[slot.id]
            if slot.id == OFF_HAND and not link and items[MAIN_HAND]
                and EquipLocation(items[MAIN_HAND]) == "INVTYPE_2HWEAPON" then
                link = items[MAIN_HAND]
            end
            if link then
                local level = GetDetailedItemLevelInfo(link)
                if not level then return nil end
                total = total + level
            end
        end
    end
    return slots > 0 and total / slots or nil
end

-- Writes down this character as it is now. The level can be passed in, as on
-- a level-up the game still reports the old one.
function AltGear:Save(level)
    if not self:Enabled() then return false end
    local record = Characters:Observe(level)
    if not record then return false end
    local items, incomplete = self:ReadWorn(record.items)
    -- As the game logs out it can stop answering about equipment, and every
    -- slot reads bare. That is not news about the character: gear written
    -- down is never replaced by a read that found nothing worn at all.
    if not next(items) and HasGear(record) then return false end
    record.items, record.itemLevel, record.saved = items, AverageItemLevel(items), time()
    if incomplete and self.retries < RETRIES then
        self.retries = self.retries + 1
        self:SaveSoon(RETRY_DELAY)
    elseif not incomplete then
        self.retries = 0
    end
    ns:Refresh()
    return true
end

function AltGear:SaveSoon(delay)
    saveToken = saveToken + 1
    local token = saveToken
    C_Timer.After(delay or SAVE_DELAY, function()
        if token == saveToken then self:Save() end
    end)
end

-- Everyone but you, this realm first, then highest level.
function AltGear:Others()
    local me, home, list = CharacterKey(), HomeRealm(), {}
    for key, record in pairs(Characters.records or {}) do
        if key ~= me and type(record) == "table" and record.items then list[#list + 1] = { key = key, record = record } end
    end
    table.sort(list, function(a, b)
        local aHome, bHome = a.record.realm == home, b.record.realm == home
        if aHome ~= bHome then return aHome end
        local aLevel, bLevel = a.record.level or 0, b.record.level or 0
        if aLevel ~= bLevel then return aLevel > bLevel end
        return a.key < b.key
    end)
    return list
end

function AltGear:Forget(key)
    local record = self:Record(key)
    if not record or key == CharacterKey() then return false end
    record.items, record.itemLevel, record.saved = nil, nil, nil
    if viewing == key then self:View(nil) end
    ns:Print(("Forgot %s's gear. It is written down again the next time that character logs in.")
        :format(record.name or key))
    ns:Refresh()
    return true
end

function AltGear:ForgetOthers()
    local count = 0
    for _, alt in ipairs(self:Others()) do
        alt.record.items, alt.record.itemLevel, alt.record.saved = nil, nil, nil
        count = count + 1
    end
    self:View(nil)
    ns:Refresh()
    return count
end

function AltGear:Summary()
    local mine, others = self:Record(CharacterKey()), self:Others()
    local total = #others + (mine and 1 or 0)
    if total == 0 then return "No characters remembered yet." end
    local names = {}
    if mine then names[1] = (mine.name or "?") .. " (you)" end
    for index, alt in ipairs(others) do
        if index > 10 then names[#names + 1] = ("and %d more"):format(#others - 10); break end
        names[#names + 1] = Hex(ClassColor(alt.record.class)) .. (alt.record.name or alt.key) .. "|r "
            .. (alt.record.level or "?")
    end
    return ("%d %s: %s"):format(total, total == 1 and "character" or "characters", table.concat(names, ", "))
end

---------------------------------------------------------------------------
-- The alt's gear over your own slots
---------------------------------------------------------------------------
local function Line(text, color)
    local r, g, b = T.Color(color)
    GameTooltip:AddLine(text, r, g, b, true)
end

local function SlotTooltip(slot)
    local record = AltGear:Viewing()
    if not record then return end
    GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
    if slot.link then
        if not pcall(GameTooltip.SetHyperlink, GameTooltip, Hyperlink(slot.link)) then
            GameTooltip:SetText(LinkName(slot.link) or slot.info.name, T.Color(T.GOLD))
        end
    else
        GameTooltip:SetText(slot.info.name, T.Color(T.GOLD))
        Line("Nothing worn here.", T.TEXT)
    end
    Line(" ", T.MUTED)
    Line(("%s's gear, saved %s."):format(record.name or "?", Ago(record.saved)), T.MUTED)
    if slot.link then Line("Shift-click to link it  \194\183  Ctrl-click to try it on", T.MUTED) end
    GameTooltip:Show()
end

local function CreateSlot(parent, real, info)
    local slot = CreateFrame("Button", nil, parent, "BackdropTemplate")
    slot.info = info
    slot:SetAllPoints(real)
    T:Chrome(slot, WELL, IDLE_BORDER)
    -- Takes the mouse, so nothing reaches your own slot underneath.
    slot:EnableMouse(true)
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", 2, -2)
    slot.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    slot:SetScript("OnEnter", SlotTooltip)
    slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    slot:SetScript("OnClick", function(self, button)
        if button == "RightButton" then AltGear:OpenMenu(self); return end
        if self.link and HandleModifiedItemClick then HandleModifiedItemClick(self.link) end
    end)
    return slot
end

local function PaintSlot(slot, record)
    local link = record.items and record.items[slot.info.id]
    slot.link = link
    if link then
        slot.icon:SetTexture(Icon(link) or QUESTION)
        slot.icon:SetDesaturated(false)
        slot.icon:SetAlpha(1)
        local color = QualityColor(link)
        slot:SetBackdropBorderColor(color[1], color[2], color[3], 1)
    else
        slot.icon:SetTexture("Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. slot.info.art)
        slot.icon:SetDesaturated(true)
        slot.icon:SetAlpha(0.35)
        slot:SetBackdropBorderColor(T.Color(IDLE_BORDER))
    end
end

-- Who it is, over the middle of the sheet where your character stands.
local function CreateCard(parent, head, corner)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetPoint("TOPLEFT", head, "TOPRIGHT", GAP, 0)
    card:SetPoint("BOTTOMRIGHT", corner, "BOTTOMLEFT", -GAP, 0)
    T:Chrome(card, CARD_BG, T.BORDER)
    card:EnableMouse(true)
    card:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then AltGear:OpenMenu(self) end
    end)
    card.close = T:CloseButton(card, function() AltGear:View(nil) end)
    card.close:SetPoint("TOPRIGHT", -2, -2)
    T:Tip(card.close, "Back to your own gear")
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(36, 36)
    card.icon:SetPoint("TOP", 0, -14)
    card.name = T:Text(card, "", "GameFontNormalLarge")
    card.name:SetJustifyH("CENTER")
    card.name:SetWordWrap(false)
    card.details = T:Text(card, "", "GameFontHighlightSmall", nil, T.TEXT)
    card.details:SetJustifyH("CENTER")
    card.details:SetSpacing(3)
    card.details:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -6)
    card.details:SetPoint("TOPRIGHT", card.name, "BOTTOMRIGHT", 0, -6)
    return card
end

local function PaintCard(card, record)
    local coords = record.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[record.class]
    card.name:ClearAllPoints()
    if coords then
        card.icon:SetTexture(CLASS_ICONS)
        card.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        card.icon:Show()
        card.name:SetPoint("TOPLEFT", 24, -56)
        card.name:SetPoint("TOPRIGHT", -24, -56)
    else
        card.icon:Hide()
        card.name:SetPoint("TOPLEFT", 24, -16)
        card.name:SetPoint("TOPRIGHT", -24, -16)
    end
    card.name:SetText(record.name or "?")
    card.name:SetTextColor(T.Color(ClassColor(record.class)))
    local lines = { Describe(record) }
    if record.realm and record.realm ~= HomeRealm() then lines[#lines + 1] = Hex(T.MUTED) .. record.realm .. "|r" end
    if record.itemLevel then
        lines[#lines + 1] = Hex(T.GOLD) .. "Item level " .. math.floor(record.itemLevel) .. "|r"
    end
    lines[#lines + 1] = Hex(T.FAINT) .. "Saved " .. Ago(record.saved) .. "|r"
    if record.location and record.location.zone then lines[#lines + 1] = "Last seen in " .. record.location.zone end
    if record.bagsSeen then
        local total = 0
        for _, bag in pairs(record.bags) do
            for _, count in pairs(bag) do total = total + count end
        end
        lines[#lines + 1] = ("Bags: %d items"):format(total)
    end
    card.details:SetText(table.concat(lines, "\n"))
end

function AltGear:CreateOverlay()
    local head, corner = Slot("HeadSlot"), Slot("Trinket1Slot")
    overlay = CreateFrame("Frame", nil, _G.PaperDollFrame)
    overlay:SetAllPoints(_G.PaperDollFrame)
    -- Above your own slots, and whatever other addons have put on them.
    overlay:SetFrameLevel(head:GetFrameLevel() + 10)
    overlay.slots = {}
    for _, info in ipairs(SLOTS) do
        local real = Slot(info.button)
        if real then overlay.slots[#overlay.slots + 1] = CreateSlot(overlay, real, info) end
    end
    overlay.card = CreateCard(overlay, head, corner)
    overlay:Hide()
    self.overlay = overlay
end

function AltGear:Viewing()
    return viewing and self:Record(viewing) or nil, viewing
end

-- Shows a character's gear on the sheet, or your own with nil.
function AltGear:View(key)
    if not (key and self.hooked and self:Enabled() and self:Record(key)) or key == CharacterKey() then key = nil end
    viewing = key
    if key and not overlay then self:CreateOverlay() end
    if overlay then overlay:SetShown(key ~= nil) end
    self:Paint()
    return key ~= nil
end

function AltGear:Paint()
    local record = self:Viewing()
    if sheetButton then
        sheetButton:SetText(record and record.name or "Alts")
        sheetButton:SetWidth(math.max(BUTTON_W, (sheetButton.label:GetStringWidth() or 0) + 34))
    end
    if not (overlay and record) then return end
    for _, slot in ipairs(overlay.slots) do PaintSlot(slot, record) end
    PaintCard(overlay.card, record)
end

---------------------------------------------------------------------------
-- Choosing a character
---------------------------------------------------------------------------
local function MenuText(record, home)
    local parts = { "level " .. (record.level or "?") }
    if record.itemLevel then parts[#parts + 1] = "item level " .. math.floor(record.itemLevel) end
    if record.realm and record.realm ~= home then parts[#parts + 1] = record.realm end
    return Hex(ClassColor(record.class)) .. (record.name or "?") .. "|r  "
        .. Hex(T.MUTED) .. table.concat(parts, " \194\183 ") .. "|r"
end

-- Without the game's menus, each click moves on to the next character and
-- back round to you.
function AltGear:Cycle(others)
    if #others == 0 then
        ns:Print("No other characters yet. Each one is added when it logs in with Mini QoL on.")
        return
    end
    local current = 0
    for index, alt in ipairs(others) do
        if alt.key == viewing then current = index end
    end
    local nextAlt = others[current + 1]
    self:View(nextAlt and nextAlt.key or nil)
end

-- A choice changes what is under the menu, so it closes rather than waits.
local function Close(response)
    return MenuResponse and MenuResponse[response or "Close"] or nil
end

function AltGear:OpenMenu(owner)
    local others, home = self:Others(), HomeRealm()
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        self:Cycle(others)
        return
    end
    GameTooltip:Hide()
    ns.ContextMenu(owner, function(_, root)
        root:CreateTitle("Show the gear of")
        root:CreateRadio(Hex(T.GOLD) .. (Characters.PlayerName() or "You") .. "|r  " .. Hex(T.MUTED) .. "you|r",
            function() return viewing == nil end,
            function() self:View(nil); return Close() end)
        if #others == 0 then
            for _, text in ipairs({ "No other characters yet.", "Each is added when it logs in with Mini QoL on." }) do
                local note = root:CreateButton(Hex(T.FAINT) .. text .. "|r", function() end)
                if note.SetEnabled then note:SetEnabled(false) end
            end
            return
        end
        for _, alt in ipairs(others) do
            root:CreateRadio(MenuText(alt.record, home),
                function() return viewing == alt.key end,
                function() self:View(alt.key); return Close() end)
        end
        root:CreateDivider()
        local forget = root:CreateButton("Forget a character")
        for _, alt in ipairs(others) do
            forget:CreateButton(MenuText(alt.record, home), function()
                self:Forget(alt.key)
                return Close("CloseAll")
            end)
        end
        if #others > 14 and root.SetScrollMode then root:SetScrollMode(360) end
    end)
end

---------------------------------------------------------------------------
-- The button on the sheet
---------------------------------------------------------------------------
function AltGear:CreateButton()
    local corner = Slot("Trinket1Slot")
    sheetButton = T:Button(_G.PaperDollFrame, "Alts", BUTTON_W, BUTTON_H, function(button) self:OpenMenu(button) end)
    sheetButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    sheetButton:SetPoint("BOTTOMRIGHT", corner, "BOTTOMLEFT", -GAP, 0)
    -- Above the alt's card too, so you can always switch.
    sheetButton:SetFrameLevel(Slot("HeadSlot"):GetFrameLevel() + 30)
    T:Caret(sheetButton, 9)
    sheetButton:SetLabelAnchor("CENTER", nil, "CENTER", -6, 0)
    T:Tip(sheetButton, "Alts' gear", function()
        local record = self:Viewing()
        if record then
            return ("Showing %s's gear, saved %s. Click to choose someone else, or yourself to go back.")
                :format(record.name or "?", Ago(record.saved))
        end
        return "See what your other characters are wearing. Each one is added when it logs in with Mini QoL on, and kept up to date as it changes gear.\n\nClick to choose a character."
    end)
    self.button = sheetButton
end

function AltGear:Refresh()
    if not self.hooked then return end
    local on = self:Enabled()
    if on and not sheetButton then self:CreateButton() end
    if sheetButton then sheetButton:SetShown(on) end
    if not on and viewing then self:View(nil); return end
    self:Paint()
end

-- The character sheet can load after Mini QoL, so this is tried again as
-- other parts of the interface load.
function AltGear:HookSheet()
    if self.hooked then return true end
    local sheet = _G.PaperDollFrame
    if not (sheet and sheet.HookScript and Slot("HeadSlot") and Slot("Trinket1Slot")) then return false end
    self.hooked = true
    sheet:HookScript("OnShow", function() self:Refresh() end)
    -- Closing the sheet puts your own gear back; changing tabs does not.
    local frame = _G.CharacterFrame or sheet
    frame:HookScript("OnHide", function() self:View(nil) end)
    if sheet:IsShown() then self:Refresh() end
    return true
end

---------------------------------------------------------------------------
-- Settings and start-up
---------------------------------------------------------------------------
-- Where the button is, for the settings page, with the key that opens the
-- character sheet as the player has it bound.
function AltGear:Where()
    if not self:Enabled() then return "Turn this on for an Alts button on your character sheet." end
    local key = GetBindingKey and GetBindingKey("TOGGLECHARACTER0")
    local text = key and GetBindingText and GetBindingText(key) or key
    return ("Open your character sheet%s and click Alts, at the bottom right of your character by the lower trinket.")
        :format(text and text ~= "" and (" (" .. text .. ")") or "")
end

function AltGear:RegisterPage()
    local function ready() return self.db ~= nil end
    ns:RegisterFeature({ id = "altGear.enabled", page = "alts", group = "Character sheet", kind = "check",
        label = "Remember every character's gear", available = ready,
        get = function() return self:Enabled() end,
        set = function(value) self:SetEnabled(value) end,
        tooltip = "Writes down what each character wears whenever it changes, and puts an Alts button on the character sheet for looking at the others: at the bottom right of your character, beside the lower trinket slot. Click it, with either button, and pick a character. Each one is added the first time it logs in with Mini QoL on." })
    ns:RegisterFeature({ id = "altGear.where", page = "alts", group = "Character sheet", kind = "info",
        label = "Open your character sheet and click Alts.", available = ready,
        get = function() return self:Where() end })
    ns:RegisterFeature({ id = "altGear.known", page = "alts", group = "Remembered characters", kind = "info",
        label = "No characters remembered yet.", available = ready,
        get = function() return self:Summary() end })
    ns:RegisterFeature({ id = "altGear.forget", page = "alts", group = "Remembered characters", kind = "action",
        label = "Other characters", button = "Forget...",
        available = function() return ready() and #self:Others() > 0 end,
        unavailable = "No other characters are remembered yet.",
        run = function() StaticPopup_Show("MINIQOL_ALTGEAR_FORGET") end,
        tooltip = "Forgets the gear of every character but this one. Each is written down again the next time it logs in. To forget just one, use Forget a character in the Alts menu on the character sheet." })
end

function AltGear:OnEvent(event, ...)
    if event == "ADDON_LOADED" then
        if self:HookSheet() then self.events:UnregisterEvent("ADDON_LOADED") end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        self.retries = 0
        self:SaveSoon()
    elseif event == "PLAYER_LEVEL_UP" then
        self:Save(tonumber((...)))
    else
        -- Entering the world, and logging out, which catches the last change.
        self:Save()
    end
end

-- Called once the saved variables and the panel exist.
function AltGear:Start()
    self:Initialize()
    self:RegisterPage()
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
        "PLAYER_LOGOUT", "ADDON_LOADED" }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event, ...) self:OnEvent(event, ...) end)
    self.events = events
    if self:HookSheet() then events:UnregisterEvent("ADDON_LOADED") end
end

StaticPopupDialogs.MINIQOL_ALTGEAR_FORGET = {
    text = "Mini QoL: forget the gear of every character but this one?",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        local count = ns.AltGear:ForgetOthers()
        ns:Print(("Forgot %d %s."):format(count, count == 1 and "character" or "characters"))
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
