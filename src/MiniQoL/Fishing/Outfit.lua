local _, ns = ...
-- The outfit editor: every slot the swap can touch, laid out like the
-- character sheet. Click a slot to pick from what fits it, drop an item from
-- the bags onto the window, or right-click a slot to leave it alone.
local Fishing = ns.Fishing
local T = ns.Theme

local EMPTY = "empty"
local PAD, GAP, ROW_GAP = 16, 8, 6
local TILE_W, TILE_H, ICON = 216, 40, 32
local WIDTH, HEADER, FOOTER = PAD * 2 + TILE_W * 3 + GAP * 2, 52, 46
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local IDLE_BORDER = { 0.22, 0.20, 0.15, 1 }
local HINT = "Click a slot to choose an item, or drop one from your bags. Right-click a slot to leave it alone."

-- Held items along the top, then worn gear in three columns that read like
-- the character sheet: upper body, arms and legs, jewellery.
local SECTIONS = {
    { label = "In hand", columns = { { 16 }, { 17 }, { 18 } } },
    { label = "Worn", columns = { { 1, 2, 3, 15, 5 }, { 9, 10, 6, 7, 8 }, { 11, 12, 13, 14 } } },
}

-- The game's own empty-slot artwork, so a bare slot looks like the one on the
-- character sheet.
local SLOT_ART = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs",
    [8] = "Feet", [9] = "Wrists", [10] = "Hands", [11] = "Finger", [12] = "Finger",
    [13] = "Trinket", [14] = "Trinket", [15] = "Chest", [16] = "MainHand",
    [17] = "SecondaryHand", [18] = "Ranged",
}

local window, tiles

local function Hex(color)
    return ("|cff%02x%02x%02x"):format(color[1] * 255, color[2] * 255, color[3] * 255)
end

local function Icon(texture, size)
    return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(texture or QUESTION, size, size)
end

local function Hyperlink(link)
    return link:match("|H(item:[^|]+)|h") or link
end

local function QualityColor(quality, link)
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color and color.r then return { color.r, color.g, color.b, 1 } end
    return T:QualityColor(link)
end

local function Line(text, color)
    local r, g, b = T.Color(color)
    GameTooltip:AddLine(text, r, g, b, true)
end

---------------------------------------------------------------------------
-- The one-line summary on the settings page
---------------------------------------------------------------------------
function Fishing:OutfitSummary()
    local pieces, bare = self:GearSummary()
    if #pieces == 0 and bare == 0 then
        return "No outfit yet. Choose your pole and any fishing gear."
    end
    local icons, parts, missing = {}, {}, 0
    for index, link in ipairs(pieces) do
        if index <= 8 then
            local _, _, _, _, icon = self.GetItemInfoInstant(link)
            icons[#icons + 1] = Icon(icon, 18)
        end
        if not self:IsCarried(link) then missing = missing + 1 end
    end
    if #pieces > 0 then parts[#parts + 1] = #pieces == 1 and "1 piece" or (#pieces .. " pieces") end
    if bare > 0 then parts[#parts + 1] = bare == 1 and "1 slot taken off" or (bare .. " slots taken off") end
    local text = table.concat(icons, " ") .. (#icons > 0 and "   " or "") .. table.concat(parts, ", ")
    if missing > 0 then text = text .. "   " .. Hex(T.BAD) .. missing .. " not in your bags|r"
    elseif self:WearingGear() then text = text .. "   " .. Hex(T.GOOD) .. "Wearing it now|r" end
    return text
end

---------------------------------------------------------------------------
-- Feedback inside the window, where the eye already is
---------------------------------------------------------------------------
local noticeToken = 0

local function Notice(text, color)
    if not window then return end
    noticeToken = noticeToken + 1
    local token = noticeToken
    window.hint:SetText(text)
    window.hint:SetTextColor(T.Color(color or T.GOLD))
    C_Timer.After(5, function()
        if token ~= noticeToken then return end
        window.hint:SetText(HINT)
        window.hint:SetTextColor(T.Color(T.MUTED))
    end)
end

---------------------------------------------------------------------------
-- Choosing what goes in a slot
---------------------------------------------------------------------------
-- An item held on the cursor lands in its own slot wherever it is dropped, so
-- boots dropped on the hat still become the boots.
function Fishing:DropOnOutfit(slot)
    if not GetCursorInfo then return false end
    local kind, itemID, link = GetCursorInfo()
    if kind ~= "item" then return false end
    link = link or select(2, self.GetItemInfo(itemID))
    local target = link and self:SlotForItem(link, slot)
    if not target then
        Notice((self.LinkName(link) or "That item") .. " is not something you can wear.", T.BAD)
        return false
    end
    ClearCursor()
    self:SetGearSlot(target, link)
    return true
end

local function MenuText(item)
    local text = Icon(item.icon, 16) .. " " .. Hex(QualityColor(item.quality, item.link)) .. item.name .. "|r"
    if item.bonus > 0 then text = text .. "  " .. Hex(T.GOOD) .. "+" .. item.bonus .. " fishing|r" end
    if not item.carried then text = text .. "  " .. Hex(T.BAD) .. "not in bags|r"
    elseif item.worn then text = text .. "  " .. Hex(T.MUTED) .. "worn now|r" end
    return text
end

function Fishing:OpenSlotPicker(tile)
    local slot = tile.slot
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        -- No menu system: take what is worn there, as the old rows did.
        self:GearSlotFromWorn(slot)
        return
    end
    local candidates = self:SlotCandidates(slot)
    MenuUtil.CreateContextMenu(tile, function(_, root)
        root:CreateTitle(self.SLOT_NAMES[slot])
        if #candidates == 0 then
            local none = root:CreateButton(Hex(T.FAINT) .. "Nothing you carry fits here|r", function() end)
            if none.SetEnabled then none:SetEnabled(false) end
        end
        for _, item in ipairs(candidates) do
            local radio = root:CreateRadio(MenuText(item),
                function() return self.SameItem(self:GearSlotValue(slot), item.link) end,
                function() self:SetGearSlot(slot, item.link) end)
            if radio.SetTooltip then
                radio:SetTooltip(function(tooltip) pcall(tooltip.SetHyperlink, tooltip, Hyperlink(item.link)) end)
            end
        end
        root:CreateDivider()
        root:CreateRadio("Take it off while fishing",
            function() return self:GearSlotValue(slot) == EMPTY end,
            function() self:SetGearSlot(slot, EMPTY) end)
        root:CreateRadio("Leave it as it is",
            function() return self:GearSlotValue(slot) == nil end,
            function() self:ClearGearSlot(slot) end)
        if #candidates > 12 and root.SetScrollMode then root:SetScrollMode(320) end
    end)
end

---------------------------------------------------------------------------
-- Slot tiles
---------------------------------------------------------------------------
local function PaintTile(tile)
    local value = Fishing:GearSlotValue(tile.slot)
    tile.cross:Hide()
    tile.badge:SetText("")
    tile.icon:SetDesaturated(false)
    tile.icon:SetAlpha(1)
    if value and value ~= EMPTY then
        local item = Fishing:DescribeItem(value)
        local color = QualityColor(item.quality, value)
        tile.icon:SetTexture(item.icon or QUESTION)
        tile.item:SetText(item.name)
        tile.item:SetTextColor(T.Color(color))
        tile.well:SetBackdropBorderColor(color[1], color[2], color[3], 0.9)
        tile:SetBackdropColor(T.Color(T.BG_CARD))
        tile.border = T.BORDER
        if not Fishing:IsCarried(value) then
            tile.badge:SetText("not in bags")
            tile.badge:SetTextColor(T.Color(T.BAD))
        elseif item.bonus > 0 then
            tile.badge:SetText("+" .. item.bonus .. " fishing")
            tile.badge:SetTextColor(T.Color(T.GOOD))
        end
    else
        tile.icon:SetTexture("Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. (SLOT_ART[tile.slot] or "Chest"))
        tile.icon:SetDesaturated(true)
        tile.well:SetBackdropBorderColor(T.Color(IDLE_BORDER))
        if value == EMPTY then
            tile.icon:SetAlpha(0.45)
            tile.cross:Show()
            tile.item:SetText("Taken off")
            tile.item:SetTextColor(T.Color(T.TEXT))
            tile:SetBackdropColor(T.Color(T.BG_CARD))
            tile.border = T.BORDER
        else
            tile.icon:SetAlpha(0.3)
            tile.item:SetText("Not changed")
            tile.item:SetTextColor(T.Color(T.FAINT))
            tile:SetBackdropColor(0.07, 0.064, 0.054, 0.6)
            tile.border = IDLE_BORDER
        end
    end
    tile:SetBackdropBorderColor(T.Color(tile:IsMouseOver() and T.BORDER_HI or tile.border))
end

local function TileTooltip(tile)
    GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
    local value = Fishing:GearSlotValue(tile.slot)
    if value and value ~= EMPTY then
        GameTooltip:SetHyperlink(Hyperlink(value))
        if not Fishing:IsCarried(value) then Line("Not in your bags, so the swap will skip it.", T.BAD) end
    else
        GameTooltip:SetText(Fishing.SLOT_NAMES[tile.slot], T.Color(T.GOLD))
        Line(value == EMPTY and "Taken off while you fish, and put back afterwards."
            or "Not part of the outfit. Whatever you have on here stays on.", T.TEXT)
    end
    Line(" ", T.MUTED)
    Line("Click to choose  \194\183  Right-click to leave it alone", T.MUTED)
    GameTooltip:Show()
end

local function CreateTile(parent, slot)
    local tile = CreateFrame("Button", nil, parent, "BackdropTemplate")
    tile.slot = slot
    tile:SetSize(TILE_W, TILE_H)
    tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    T:Chrome(tile, T.BG_CARD, IDLE_BORDER)
    tile.hover = tile:CreateTexture(nil, "BACKGROUND", nil, 1)
    tile.hover:SetPoint("TOPLEFT", 1, -1)
    tile.hover:SetPoint("BOTTOMRIGHT", -1, 1)
    tile.hover:SetColorTexture(T.Color(T.BG_HOVER))
    tile.hover:Hide()

    tile.well = CreateFrame("Frame", nil, tile, "BackdropTemplate")
    tile.well:SetSize(ICON, ICON)
    tile.well:SetPoint("LEFT", 4, 0)
    T:Chrome(tile.well, { 0.03, 0.028, 0.024, 0.9 }, IDLE_BORDER)
    tile.icon = tile.well:CreateTexture(nil, "ARTWORK")
    tile.icon:SetPoint("TOPLEFT", 1, -1)
    tile.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    tile.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tile.cross = T:Text(tile.well, "\195\151", "GameFontNormalLarge", ICON, T.BAD)
    tile.cross:SetJustifyH("CENTER")
    tile.cross:SetPoint("CENTER", 0, 1)

    local textX = ICON + 12
    tile.slotName = T:Text(tile, Fishing.SLOT_NAMES[slot], "GameFontDisableSmall", 90, T.MUTED)
    tile.slotName:SetPoint("TOPLEFT", textX, -7)
    tile.badge = T:Text(tile, "", "GameFontDisableSmall", 90, T.GOOD)
    tile.badge:SetJustifyH("RIGHT")
    tile.badge:SetPoint("TOPRIGHT", -8, -7)
    tile.item = T:Text(tile, "", "GameFontHighlightSmall", TILE_W - textX - 8)
    tile.item:SetWordWrap(false)
    tile.item:SetPoint("TOPLEFT", textX, -21)

    tile:SetScript("OnEnter", function(self)
        self.hover:Show()
        self:SetBackdropBorderColor(T.Color(T.BORDER_HI))
        TileTooltip(self)
    end)
    tile:SetScript("OnLeave", function(self)
        self.hover:Hide()
        self:SetBackdropBorderColor(T.Color(self.border or IDLE_BORDER))
        GameTooltip:Hide()
    end)
    tile:SetScript("OnClick", function(self, button)
        if CursorHasItem and CursorHasItem() then Fishing:DropOnOutfit(self.slot); return end
        if button == "RightButton" then Fishing:ClearGearSlot(self.slot); return end
        Fishing:OpenSlotPicker(self)
    end)
    tile:SetScript("OnReceiveDrag", function(self) Fishing:DropOnOutfit(self.slot) end)
    return tile
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
-- Escape closes this window on its own rather than the whole panel. As with
-- the NPC shortcuts, the listener exists only while the window is open and
-- stays out of combat, where keyboard capture is restricted.
local function Listen(on)
    local keys = window.keys
    if on and not InCombatLockdown() then
        keys:SetPropagateKeyboardInput(true)
        keys:SetScript("OnKeyDown", function(self, key)
            if key ~= "ESCAPE" or InCombatLockdown() then return end
            -- An open slot menu gets the key first, so Escape closes the menu.
            local menus = Menu and Menu.GetManager and Menu.GetManager()
            if menus and menus.GetOpenMenu and menus:GetOpenMenu() then return end
            self:SetPropagateKeyboardInput(false)
            window:Hide()
        end)
        keys:EnableKeyboard(true)
    else
        keys:SetScript("OnKeyDown", nil)
        keys:EnableKeyboard(false)
    end
end

local function FindGear()
    local pole, pieces = Fishing:SuggestGear()
    local found = pieces == 1 and "1 piece that adds to fishing" or (pieces .. " pieces that add to fishing")
    if pole and pieces > 0 then Notice("Picked " .. pole.name .. " and " .. found .. ".")
    elseif pole then Notice("Picked " .. pole.name .. ". Nothing else you carry adds to fishing.")
    elseif pieces > 0 then Notice("Picked " .. found .. ", but you are not carrying a fishing pole.")
    else Notice("No fishing pole or fishing gear on you or in your bags.", T.BAD) end
end

-- Clearing throws away every choice, so it takes a second click.
local function ClearAll(button)
    if not button.armed then
        button.armed = true
        button:SetText("Really clear?")
        Notice("Click again to empty the whole outfit.", T.BAD)
        C_Timer.After(4, function()
            if button.armed then button.armed = nil; button:SetText("Clear") end
        end)
        return
    end
    button.armed = nil
    button:SetText("Clear")
    Fishing:ClearGear()
    Notice("Outfit cleared. Every slot is left as it is.")
end

local function CreateWindow()
    window = CreateFrame("Frame", "MiniQoLFishingOutfit", UIParent, "BackdropTemplate")
    window:Hide()
    window:SetFrameStrata("DIALOG")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    T:Window(window, HEADER)
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    -- Dropping anywhere on the window works, not only on a tile.
    window:SetScript("OnReceiveDrag", function() Fishing:DropOnOutfit() end)
    window:SetScript("OnMouseUp", function()
        if CursorHasItem and CursorHasItem() then Fishing:DropOnOutfit() end
    end)

    local title = T:Text(window, "Fishing outfit", "GameFontNormalLarge", nil, T.GOLD)
    title:SetPoint("TOPLEFT", PAD, -12)
    window.status = T:Text(window, "", "GameFontDisableSmall", WIDTH - 80, T.MUTED)
    window.status:SetPoint("TOPLEFT", PAD + 1, -33)
    T:CloseButton(window):SetPoint("TOPRIGHT", -7, -8)

    window.hint = T:Text(window, HINT, "GameFontHighlightSmall", WIDTH - PAD * 2, T.MUTED)
    window.hint:SetPoint("TOPLEFT", PAD, -(HEADER + 12))

    tiles = {}
    local y = HEADER + 36
    for _, section in ipairs(SECTIONS) do
        local label = T:Text(window, section.label:upper(), "GameFontDisableSmall", 200, T.GOLD_SOFT)
        label:SetPoint("TOPLEFT", PAD, -y)
        local rule = T:Rule(window)
        rule:SetPoint("TOPLEFT", PAD, -(y + 15))
        rule:SetPoint("TOPRIGHT", -PAD, -(y + 15))
        y = y + 22
        local rows = 0
        for column, slots in ipairs(section.columns) do
            for index, slot in ipairs(slots) do
                local tile = CreateTile(window, slot)
                tile:SetPoint("TOPLEFT", PAD + (column - 1) * (TILE_W + GAP), -(y + (index - 1) * (TILE_H + ROW_GAP)))
                tiles[slot] = tile
            end
            rows = math.max(rows, #slots)
        end
        y = y + rows * (TILE_H + ROW_GAP) + 10
    end
    window:SetSize(WIDTH, y + FOOTER)

    local footerRule = T:Rule(window)
    footerRule:SetPoint("BOTTOMLEFT", 1, FOOTER)
    footerRule:SetPoint("BOTTOMRIGHT", -1, FOOTER)

    window.find = T:Button(window, "Find fishing gear", 132, 24, FindGear)
    window.find:SetPoint("BOTTOMLEFT", PAD, 11)
    T:Tip(window.find, "Find fishing gear",
        "Picks your best fishing pole and every piece you carry that adds to fishing. Slots with nothing for fishing keep whatever you chose.")
    window.copy = T:Button(window, "Use what I'm wearing", 150, 24, function()
        Fishing:SnapshotGear()
        Notice("Every slot now matches what you have on.")
    end)
    window.copy:SetPoint("LEFT", window.find, "RIGHT", 6, 0)
    T:Tip(window.copy, "Use what I'm wearing",
        "Copies every slot from what you have on now; bare slots are taken off when fishing. Handy if you are already dressed for it. Later upgrades to your normal gear will be swapped out too, so Find fishing gear is usually the better start.")
    window.clear = T:Button(window, "Clear", 92, 24, ClearAll)
    window.clear:SetPoint("LEFT", window.copy, "RIGHT", 6, 0)
    T:Tip(window.clear, "Clear", "Empties the outfit, so every slot is left as it is.")

    window.swap = T:Button(window, "Put on outfit", 132, 24, function() Fishing:ToggleGear() end)
    window.swap:SetPoint("BOTTOMRIGHT", -PAD, 11)
    T:Tip(window.swap, "Swap", function()
        return Fishing:WearingGear() and "Puts back exactly what you had on before."
            or "Changes into the outfit. The same button, /mqol fish or the action bar button changes you back."
    end)

    window.keys = CreateFrame("Frame", nil, window)
    window:SetScript("OnShow", function() Listen(true); Fishing:RefreshOutfit() end)
    window:SetScript("OnHide", function()
        Listen(false)
        if window.clear.armed then window.clear.armed = nil; window.clear:SetText("Clear") end
    end)
    return window
end

function Fishing:RefreshOutfit()
    if not window or not window:IsShown() then return end
    for _, tile in pairs(tiles) do PaintTile(tile) end
    local pieces, bare = self:GearSummary()
    local wearing, any = self:WearingGear(), self:HasGearSet()
    local parts = {}
    if #pieces > 0 then parts[#parts + 1] = #pieces == 1 and "1 piece" or (#pieces .. " pieces") end
    if bare > 0 then parts[#parts + 1] = bare == 1 and "1 slot taken off" or (bare .. " slots taken off") end
    local status = any and table.concat(parts, "  \194\183  ") or "Nothing chosen yet"
    if wearing then status = status .. "  \194\183  " .. Hex(T.GOOD) .. "Wearing it now|r" end
    window.status:SetText(status)
    window.swap:SetText(wearing and "Change back" or "Put on outfit")
    window.swap:SetEnabled(wearing or any)
    window.clear:SetEnabled(any)
    -- Light up the next step: finding gear while there is none, then wearing it.
    window.find:SetPrimary(not any)
    window.swap:SetPrimary(any)
end

function Fishing:OpenOutfit()
    if not window then CreateWindow() end
    -- Opened from the panel, it closes with the panel.
    if ns.panel and not window.followsPanel then
        window.followsPanel = true
        ns.panel:HookScript("OnHide", function() window:Hide() end)
    end
    window:Show()
    window:Raise()
end

function Fishing:ToggleOutfit()
    if window and window:IsShown() then window:Hide() else self:OpenOutfit() end
end

function Fishing:SetupOutfit()
    self:On("GEAR_CHANGED", function()
        self:RefreshOutfit()
        ns:Refresh()
    end)
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    events:RegisterEvent("BAG_UPDATE_DELAYED")
    events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    events:SetScript("OnEvent", function() self:RefreshOutfit() end)
end
