local _, ns = ...
local E, T = ns.Explorer, ns.Theme
local QUERY_LIMIT = 40
local slots = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 13, 15, 16, 17, 18 }
local query, kind, gearSlot = "", "all", nil

local function Visible(page)
    return ns.panel and ns.panel:IsShown() and ns.db.page == page and ns.search:GetText() == ""
end

local function PlaceText(result)
    local map = E.MapName(result.mapID) or ""
    if not E.Located(result.mapID, result.x, result.y) then return map end
    return ("%s · %.1f, %.1f"):format(map, result.x * 100, result.y * 100)
end

local function SingleLine(parent, font, color, width, point, x, y)
    local text = T:Text(parent, "", font, width, color)
    text:SetPoint(point, x, y)
    text:SetWordWrap(false)
    return text
end

local function ResultRow(key, y, result)
    local row = ns:Row("explorer." .. key, 46)
    if not row.name then
        T:Chrome(row, T.BG_CARD, T.RULE)
        local icon = CreateFrame("Button", nil, row)
        row.item = icon
        icon:SetSize(28, 28)
        icon:SetPoint("LEFT", 9, 0)
        icon:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. row.result.itemID)
            GameTooltip:Show()
        end)
        icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
        icon:SetScript("OnClick", function()
            local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
            local _, link = getInfo(row.result.itemID)
            if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
        end)
        row.name = SingleLine(row, "GameFontHighlight", T.TEXT, 345, "TOPLEFT", 46, -7)
        row.detail = SingleLine(row, "GameFontDisableSmall", T.MUTED, 452, "BOTTOMLEFT", 46, 7)
        row.gain = SingleLine(row, "GameFontHighlightSmall", T.GOOD, 105, "TOPLEFT", 395, -8)
        row.gain:SetJustifyH("RIGHT")
        row.waypoint = T:Button(row, "Waypoint", 103, 24, function() E.Waypoint(row.result) end)
        row.waypoint:SetPoint("RIGHT", -8, 0)
    end
    row.result = result
    row:SetPoint("TOPLEFT", 0, -y)
    row.name:SetPoint("TOPLEFT", result.itemID and 46 or 10, -7)
    row.detail:SetPoint("BOTTOMLEFT", result.itemID and 46 or 10, 7)
    row.item:SetShown(result.itemID ~= nil)
    if result.itemID then
        local getIcon = C_Item and C_Item.GetItemIconByID or GetItemIcon
        row.item:SetNormalTexture(result.icon or (getIcon and getIcon(result.itemID)) or 134400)
    end
    local place = PlaceText(result)
    local detail = result.detail or ""
    if result.note then detail = result.note .. " · " .. detail end
    if result.effects then detail = "Review item effects · " .. detail
    elseif result.estimatedProc then detail = "Includes on-hit estimate · " .. detail
    elseif result.effectNotes then detail = "Set comparison · " .. detail end
    if result.slot then detail = Gearwise.slotNames[result.slot] .. " · " .. detail end
    if place ~= "" then detail = detail .. " · " .. place end
    row.name:SetText(result.name)
    row.detail:SetText(detail)
    row.gain:SetText(result.planOnly and "Set option" or result.breakEven and ("%.2f/min"):format(result.breakEven)
        or result.delta and (result.delta < 0.1 and "<0.1 score" or ("+%.1f score"):format(result.delta)) or "")
    row.waypoint:SetShown(E.Located(result.mapID, result.x, result.y) and true or false)
    -- Long creature and quest names still have access to the full location text.
    if not row.hasTip then
        T:Tip(row, function() return row.result.name end, function()
            local item, text = row.result, row.detail:GetText()
            if item.planOnly or item.breakEven then text = text .. ("\nCurrent estimate %+.1f score."):format(item.delta)
            elseif item.empty then text = text .. "\nFills an empty slot."
            elseif item.percent then text = text .. ("\n%.1f%% above the equipped slot score."):format(item.percent) end
            if item.effectNotes then text = text .. "\n" .. table.concat(item.effectNotes, "\n") end
            if item.effects then text = text .. "\nSome item effects or set bonuses are outside the score." end
            return text
        end)
        row.hasTip = true
    end
    return y + 50
end

local function ResetScroll()
    ns.scroll:SetVerticalScroll(0)
    ns:Refresh()
end

local searchGeneration = 0
local function UpdateQuery(text)
    query = text
    searchGeneration = searchGeneration + 1
    local generation = searchGeneration
    C_Timer.After(0.18, function()
        if generation == searchGeneration and Visible("worldsearch") then ResetScroll() end
    end)
end

function E:OpenSearch(text)
    query, kind = text, "all"
    ns:ShowPage("worldsearch")
    ns.rows["explorer.search"].edit:SetFocus()
end

function E:RenderSearch(y)
    local row = ns:Row("explorer.search", 68)
    row:SetPoint("TOPLEFT", 0, -y)
    if not row.edit then
        local field = CreateFrame("Frame", nil, row, "BackdropTemplate")
        T:Chrome(field, { 0.028, 0.026, 0.022, 0.9 }, T.BORDER)
        field:SetPoint("TOPLEFT", 0, 0)
        field:SetPoint("TOPRIGHT", 0, 0)
        field:SetHeight(29)
        local edit = CreateFrame("EditBox", nil, field)
        row.edit = edit
        edit:SetAllPoints()
        edit:SetFontObject("ChatFontNormal")
        edit:SetTextInsets(10, 30, 0, 0)
        edit:SetTextColor(T.Color(T.TEXT))
        edit:SetAutoFocus(false)
        edit:SetMaxLetters(80)
        local hint = T:Text(edit, "Search the world by name, role, zone or ID…", "GameFontDisableSmall", 440, T.MUTED)
        hint:SetPoint("LEFT", 10, 0)
        local clear = T:CloseButton(field, function() UpdateQuery(""); edit:SetText(""); edit:SetFocus() end)
        clear:SetSize(18, 18)
        clear:SetPoint("RIGHT", -7, 0)
        clear:SetFrameLevel(edit:GetFrameLevel() + 2)
        edit:SetScript("OnTextChanged", function(self, typed)
            local text = self:GetText()
            hint:SetShown(text == "")
            clear:SetShown(text ~= "")
            if typed then UpdateQuery(text) end
        end)
        edit:SetScript("OnEditFocusGained", function() field:SetBackdropBorderColor(T.Color(T.BORDER_HI)) end)
        edit:SetScript("OnEditFocusLost", function() field:SetBackdropBorderColor(T.Color(T.BORDER)) end)
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        edit:SetScript("OnEnterPressed", function(self) self:ClearFocus(); ResetScroll() end)
        row.filters = {}
        for i, filter in ipairs(self.searchKinds) do
            local button = T:Button(row, filter[2], 83, 22, function() kind = filter[1]; ResetScroll() end)
            button:SetPoint("TOPLEFT", (i - 1) * 89, -36)
            row.filters[i] = button
        end
        hint:SetShown(query == "")
        clear:SetShown(query ~= "")
    end
    if row.edit:GetText() ~= query then row.edit:SetText(query) end
    for i, filter in ipairs(self.searchKinds) do row.filters[i]:SetPrimary(filter[1] == kind) end
    y = y + 68
    if not (self.loaders.npcs or self.npcs) then
        y = ns:Note("finder.data", "World search data is missing from this Mini QoL build.", y)
    end
    if #query:match("^%s*(.-)%s*$") < 2 then
        return ns:Note("finder.status", "Type at least two characters to search.", y)
    end
    local results, total = self:Search(query, kind, QUERY_LIMIT)
    if total == 0 then return ns:Note("finder.status", "No matches. Try another name or category.", y) end
    local status = total > QUERY_LIMIT and ("Showing %d of %d matches. Narrow the search to see more."):format(QUERY_LIMIT, total)
        or ("%d match%s"):format(total, total == 1 and "" or "es")
    y = ns:Note("finder.status", status, y)
    for i, result in ipairs(results) do y = ResultRow("search." .. i, y, result) end
    return y
end

local refreshTimer
local function RefreshGearSoon()
    if refreshTimer then return end
    refreshTimer = C_Timer.NewTimer(0.45, function()
        refreshTimer = nil
        E:CancelUpgrades()
        if Visible("nearby") then ns:Refresh() end
    end)
end

local function ScanFinished(scan)
    if scan and not scan.running then
        scan.time = GetTime()
    end
    if Visible("nearby") then ns:Refresh() end
end

local function NearbyVisible() return Visible("nearby") end

local events = CreateFrame("Frame")
for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
    "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED", "CHARACTER_POINTS_CHANGED",
    "SKILL_LINES_CHANGED", "SPELLS_CHANGED", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_REGEN_ENABLED",
    "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED",
    "PLAYERBANKBAGSLOTS_CHANGED", "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, id, success)
    if event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
        if success then E:UpgradeItemArrived(id) end
        local effects = Gearwise and Gearwise.Effects
        if success and effects and effects.waitingForStorage[id] then
            effects.waitingForStorage[id] = nil
            if NearbyVisible() then RefreshGearSoon() else E:CancelUpgrades() end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if NearbyVisible() then ns:Refresh() end
    elseif Visible("nearby") then
        RefreshGearSoon()
    else
        E:CancelUpgrades()
    end
end)

local function SelectSlot(button)
    if not MenuUtil or not MenuUtil.CreateContextMenu then return end
    ns.ContextMenu(button, function(_, root)
        local function add(slot, label)
            root:CreateRadio(label, function() return gearSlot == slot end, function() gearSlot = slot; ResetScroll() end)
        end
        add(nil, "All slots")
        for _, slot in ipairs(slots) do add(slot, Gearwise.slotNames[slot]) end
    end)
end

-- Gearwise also rebuilds its profile when item data arrives. Only an actual
-- scoring change should invalidate comparisons already made in this scan.
local function SameBuild(scan, current)
    local old = scan.profile
    if old == current then return true end
    if old.key ~= current.key or old.class ~= current.class or old.level ~= current.level
        or old.leveling ~= current.leveling or old.meleeDPS ~= current.meleeDPS or old.rangedDPS ~= current.rangedDPS then
        return false
    end
    for key, value in pairs(old.weights) do if current.weights[key] ~= value then return false end end
    for key in pairs(current.weights) do if old.weights[key] == nil then return false end end
    scan.profile = current
    return true
end

local function RenderGearGroup(key, title, results, y)
    local shown = 0
    for _, result in ipairs(results) do
        if not gearSlot or gearSlot == result.slot then
            if shown == 0 then y = ns:Section("nearby." .. key, title, y) end
            shown = shown + 1
            y = ResultRow("gear." .. key .. "." .. shown, y, result)
            if shown == (gearSlot and 20 or 40) then break end
        end
    end
    return y, shown
end

function E:RenderNearby(y)
    if not (Gearwise and Gearwise.Compare and Gearwise.profile) then
        return ns:Note("nearby.status", "Enable Gearwise in Mini QoL to compare gear.", y)
    end
    if not (self.gear or self.loaders.gear) then
        return ns:Note("nearby.status", "Gear source data is missing from this Mini QoL build.", y)
    end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return ns:Note("nearby.status", "Your current zone is unavailable.", y) end
    local row = ns:Row("explorer.gear.controls", 33)
    row:SetPoint("TOPLEFT", 0, -y)
    if not row.slot then
        row.slot = T:Button(row, "All slots", 120, 24, function() SelectSlot(row.slot) end)
        row.slot:SetPoint("TOPLEFT", 0, 0)
        row.build = SingleLine(row, "GameFontDisableSmall", T.MUTED, 364, "TOPLEFT", 131, -6)
        T:Button(row, "Refresh", 90, 24, function() E:CancelUpgrades(); ResetScroll() end):SetPoint("TOPRIGHT", 0, 0)
    end
    row.slot:SetText(gearSlot and Gearwise.slotNames[gearSlot] or "All slots")
    local profile = Gearwise.profile
    row.build:SetText(profile.label and ("Score gain for " .. profile.label .. " " .. (profile.className or "")) or "Gearwise score gain")
    y = y + 33
    if InCombatLockdown() then return ns:Note("nearby.status", "Gear comparisons resume after combat.", y) end

    local scan = self.scan
    if not scan or scan.mapID ~= mapID or scan.slot ~= gearSlot or not SameBuild(scan, Gearwise.profile)
        or (scan.time and GetTime() - scan.time > 30) then
        self:StartUpgrades(gearSlot, ScanFinished, NearbyVisible)
        scan = self.scan
    end
    if not scan.nearby then return ns:Note("nearby.status", "Checking gear sources against your equipped items…", y) end
    scan:retry()
    local localCount, outsideCount
    y, localCount = RenderGearGroup("local", E.MapName(E.Zone(mapID)) or "Current zone", scan.nearby, y)
    y, outsideCount = RenderGearGroup("outside", "Other zones · selected upgrades", scan.elsewhere, y)
    y = RenderGearGroup("sets", "Local set options with pieces you own", scan.setOptions, y)
    y = RenderGearGroup("procs", "Local on-hit effects with an unknown rate", scan.procOptions, y)
    if scan.checkingElsewhere then
        y = ns:Note("nearby.status", "Checking other zones…", y)
    elseif localCount + outsideCount == 0 and not next(scan.pending) then
        y = ns:Note("nearby.empty", "No scored upgrades found among the known sources checked.", y)
    end
    if next(scan.pending) then y = ns:Note("nearby.pending", "Waiting for item data for some gear. Results update as it arrives.", y) end
    return y
end
