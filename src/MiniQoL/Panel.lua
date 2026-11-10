local _, ns = ...
local T = ns.Theme

local WIDTH, HEIGHT, HEADER, SIDEBAR, FOOTER = 880, 520, 54, 190, 46
local CONTENT_W, COL_W, COL_GAP, ROW_H = 620, 307, 6, 30
local CARD_H, TILE_H = 54, 52
local LABEL_W, LABEL_W_SOURCE = 260, 196
local LABEL_X, CONTROL_INSET = 25, 18
local SELECT_W, ACTION_W = 110, 100

---------------------------------------------------------------------------
-- Module switches
---------------------------------------------------------------------------
function ns:SetModuleEnabled(name, enabled)
    if InCombatLockdown() then self:Print("Change modules after combat."); return end
    local runtime = MiniQoLRuntime
    if not runtime then return end
    local visited = {}
    local function change(id, value)
        if visited[id] then return end
        visited[id] = true
        if value then
            for _, dependency in ipairs(runtime.modules[id].dependencies) do
                if runtime.modules[dependency] then change(dependency, true) end
            end
            runtime.api.EnableAddOn(id)
        else
            for other, module in pairs(runtime.modules) do
                for _, dependency in ipairs(module.dependencies) do
                    if dependency == id then change(other, false); break end
                end
            end
            runtime.api.DisableAddOn(id)
        end
    end
    change(name, enabled)
    self:Refresh()
end

-- Three states worth distinguishing: running now, switched on but waiting for a
-- reload, and switched off. Everything in the panel reads them from here.
local function ModuleState(addon)
    if addon.loaded then
        return addon.enabled and "Active" or "Off after reload",
            addon.enabled and T.GOOD or T.BAD
    end
    return addon.enabled and "Reload to activate" or "Off",
        addon.enabled and T.GOLD_SOFT or T.FAINT
end

---------------------------------------------------------------------------
-- Panel chrome
---------------------------------------------------------------------------
function ns:CreatePanel()
    if self.panel then return end
    local panel = CreateFrame("Frame", "MiniQoLPanel", UIParent, "BackdropTemplate")
    self.panel = panel
    panel:SetSize(WIDTH, HEIGHT)
    panel:SetPoint("CENTER")
    panel:SetClampedToScreen(true)
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    T:Window(panel, HEADER)
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        ns.db.position = { point, relativePoint, x, y }
    end)
    local saved = self.db.position
    if type(saved) == "table" and #saved == 4 then
        panel:ClearAllPoints()
        panel:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
    end
    UISpecialFrames[#UISpecialFrames + 1] = "MiniQoLPanel"

    local title = T:Text(panel, "Mini QoL", "GameFontNormalLarge", nil, T.GOLD)
    title:SetPoint("TOPLEFT", 18, -12)
    local brand = T:Text(panel, "WoW Forever  \194\183  " .. self.version, "GameFontDisableSmall", 160, T.MUTED)
    brand:SetPoint("TOPLEFT", 19, -33)
    T:CloseButton(panel):SetPoint("TOPRIGHT", -7, -8)

    -- Search box: a plain edit box in themed chrome, so it matches the buttons
    -- instead of carrying Blizzard's stone artwork into the header.
    local searchFrame = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    searchFrame:SetSize(216, 22)
    searchFrame:SetPoint("TOPRIGHT", -40, -16)
    T:Chrome(searchFrame, { 0.028, 0.026, 0.022, 0.9 }, T.BORDER)
    local search = CreateFrame("EditBox", "MiniQoLSearch", searchFrame)
    self.search = search
    search:SetAllPoints()
    search:SetFontObject("ChatFontNormal")
    search:SetTextInsets(8, 22, 0, 0)
    search:SetTextColor(T.Color(T.TEXT))
    search:SetAutoFocus(false)
    search:SetMaxLetters(80)
    search:SetScript("OnEscapePressed", function(box) box:SetText(""); box:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
    search:SetScript("OnTextChanged", function() ns:Render() end)
    search:SetScript("OnEditFocusGained", function() searchFrame:SetBackdropBorderColor(T.Color(T.BORDER_HI)) end)
    search:SetScript("OnEditFocusLost", function() searchFrame:SetBackdropBorderColor(T.Color(T.BORDER)) end)
    self.searchHint = T:Text(search, "Search every setting...", "GameFontDisableSmall", 170, T.FAINT)
    self.searchHint:SetPoint("LEFT", 9, 0)
    local clear = T:CloseButton(searchFrame, function() search:SetText(""); search:ClearFocus() end)
    clear:SetSize(18, 18)
    clear:SetPoint("RIGHT", -3, 0)
    clear:SetFrameLevel(search:GetFrameLevel() + 2)
    self.searchClear = clear
    T:Tip(search, "Search everything", "Finds controls from every category at once. Clear the box to return to the selected page.")

    local divider = panel:CreateTexture(nil, "BACKGROUND", nil, 3)
    divider:SetColorTexture(T.Color(T.RULE))
    divider:SetPoint("TOPLEFT", SIDEBAR, -HEADER - 1)
    divider:SetPoint("BOTTOMLEFT", SIDEBAR, FOOTER)
    divider:SetWidth(1)

    local footerRule = T:Rule(panel)
    footerRule:SetPoint("BOTTOMLEFT", 1, FOOTER)
    footerRule:SetPoint("BOTTOMRIGHT", -1, FOOTER)

    self:CreateSidebar()

    self.description = T:Text(panel, "", "GameFontDisableSmall", CONTENT_W, T.MUTED)
    self.description:SetPoint("TOPLEFT", SIDEBAR + 18, -HEADER - 13)

    local scroll = CreateFrame("ScrollFrame", "MiniQoLScrollFrame", panel, "UIPanelScrollFrameTemplate")
    self.scroll = scroll
    scroll:SetPoint("TOPLEFT", SIDEBAR + 18, -HEADER - 34)
    scroll:SetPoint("BOTTOMRIGHT", -28, FOOTER + 10)
    T:SkinScrollBar(scroll, "MiniQoLScrollFrame")
    local content = CreateFrame("Frame", nil, scroll)
    self.content = content
    content:SetSize(CONTENT_W, 300)
    scroll:SetScrollChild(content)
    self.rows = {}

    self.footer = T:Text(panel, "", "GameFontDisableSmall", 380, T.MUTED)
    self.footer:SetPoint("BOTTOMLEFT", SIDEBAR + 18, 17)
    self.reload = T:Button(panel, "Reload UI", 100, 24, function()
        if InCombatLockdown() then ns:Print("Reload after combat."); return end
        ReloadUI()
    end)
    self.reload:SetPoint("BOTTOMRIGHT", -16, 11)
    T:Tip(self.reload, "Reload UI",
        function() return ns.reloadPending and "Applies the module and map changes waiting below."
            or "Restarts the interface. Nothing is lost." end)

    panel:SetScript("OnShow", function() ns:Render() end)
    panel:Hide()
end

function ns:CreateSidebar()
    local panel = self.panel
    self.tabs = {}
    local y, group = HEADER + 12, nil
    for _, page in ipairs(self.pages) do
        if page.group and page.group ~= group then
            group = page.group
            local header = T:Text(panel, page.group:upper(), "GameFontDisableSmall", 150, T.FAINT)
            header:SetPoint("TOPLEFT", 19, -(y + 8))
            y = y + 26
        end
        local tab = CreateFrame("Button", nil, panel)
        tab:SetSize(SIDEBAR - 16, 28)
        tab:SetPoint("TOPLEFT", 8, -y)
        tab.fill = tab:CreateTexture(nil, "BACKGROUND")
        tab.fill:SetAllPoints()
        tab.fill:SetColorTexture(T.Color(T.BG_ACTIVE))
        tab.marker = tab:CreateTexture(nil, "ARTWORK")
        tab.marker:SetPoint("TOPLEFT", 0, 0)
        tab.marker:SetPoint("BOTTOMLEFT", 0, 0)
        tab.marker:SetWidth(2)
        tab.marker:SetColorTexture(T.Color(T.GOLD))
        tab.hover = tab:CreateTexture(nil, "BACKGROUND", nil, 1)
        tab.hover:SetAllPoints()
        tab.hover:SetColorTexture(T.Color(T.BG_HOVER))
        tab.hover:Hide()
        tab.label = T:Text(tab, page.label, "GameFontHighlight", SIDEBAR - 50)
        tab.label:SetPoint("LEFT", 12, 0)
        tab.label:SetJustifyV("MIDDLE")
        tab.label:SetWordWrap(false)
        if page.module then
            tab.dot = tab:CreateTexture(nil, "OVERLAY")
            tab.dot:SetSize(6, 6)
            tab.dot:SetPoint("RIGHT", -13, 0)
        end
        tab:SetScript("OnEnter", function(self) self.hover:Show() end)
        tab:SetScript("OnLeave", function(self) self.hover:Hide() end)
        tab:SetScript("OnClick", function()
            ns.db.page = page.id
            ns.search:SetText("")
            ns.scroll:SetVerticalScroll(0)
            ns:Render()
        end)
        self.tabs[page.id] = tab
        y = y + 29
    end
end

---------------------------------------------------------------------------
-- Pooled content rows
---------------------------------------------------------------------------
function ns:Row(key, height, width)
    local row = self.rows[key]
    if not row then
        row = CreateFrame("Frame", nil, self.content, "BackdropTemplate")
        row:EnableMouse(true)
        self.rows[key] = row
    end
    row:SetSize(width or CONTENT_W, height)
    row:ClearAllPoints()
    row:Show()
    return row
end

function ns:Section(key, label, y)
    local row = self:Row("section." .. key, 26)
    if not row.label then
        row.label = T:Text(row, "", "GameFontDisableSmall", CONTENT_W, T.GOLD_SOFT)
        row.label:SetPoint("TOPLEFT", 0, -3)
        row.line = T:Rule(row)
        row.line:SetPoint("BOTTOMLEFT", 0, 1)
        row.line:SetWidth(CONTENT_W)
    end
    row.label:SetText(label:upper())
    row:SetPoint("TOPLEFT", 0, -y)
    return y + 30
end

function ns:Note(key, text, y)
    local row = self:Row("note." .. key, 1)
    if not row.label then
        row.label = T:Text(row, "", "GameFontHighlightSmall", CONTENT_W, T.MUTED)
        row.label:SetPoint("TOPLEFT", 0, -1)
    end
    row.label:SetText(text)
    local height = math.max(14, row.label:GetStringHeight()) + 8
    row:SetHeight(height)
    row:SetPoint("TOPLEFT", 0, -y)
    return y + height
end

---------------------------------------------------------------------------
-- One setting
---------------------------------------------------------------------------
-- Sliders and read-only lines need the full content width, as does anything
-- that asks for it; everything else pairs up in two columns.
local function IsWide(feature)
    return feature.wide or feature.kind == "slider" or feature.kind == "info"
end

-- A label may be worked out at repaint (a summary beside a button, say). The
-- static label still names the row for search and tooltips.
local function LabelText(feature)
    if feature.text then
        local ok, text = pcall(feature.text)
        if ok and text then return text end
    end
    return feature.label
end

local function Options(feature)
    if feature.options then
        local ok, list = pcall(feature.options)
        if ok and type(list) == "table" then return list end
        return {}
    end
    return feature.choices or {}
end

local function OptionLabel(feature, value)
    for _, option in ipairs(Options(feature)) do
        if option[1] == value then return option[2] end
    end
    return "—"
end

function ns:FeatureRow(feature, x, y, showSource)
    local wide = IsWide(feature)
    local row = self:Row("feature." .. feature.id, ROW_H, wide and CONTENT_W or COL_W)
    row:SetPoint("TOPLEFT", x, -y)
    if not row.built then
        row.built = true
        row.hover = row:CreateTexture(nil, "BACKGROUND")
        row.hover:SetPoint("TOPLEFT", -4, 0)
        row.hover:SetPoint("BOTTOMRIGHT", 0, 0)
        row.hover:SetColorTexture(T.Color(T.BG_HOVER))
        row.hover:Hide()
        row:SetScript("OnEnter", function(self) self.hover:Show() end)
        row:SetScript("OnLeave", function(self) self.hover:Hide() end)

        local kind = feature.kind
        local labelWidth = LABEL_W
        local controlWidth = feature.controlWidth or (kind == "select" and SELECT_W or ACTION_W)
        if kind == "select" or kind == "action" then
            -- Stop short of the button: a long label is cut off with an
            -- ellipsis (the tooltip has it in full) rather than running under it.
            labelWidth = (wide and CONTENT_W or COL_W) - LABEL_X - CONTROL_INSET - controlWidth - 6
        elseif kind == "slider" then labelWidth = 240
        elseif kind == "info" then labelWidth = CONTENT_W - 44 end
        row.label = T:Text(row, "", kind == "info" and "GameFontDisableSmall" or "GameFontHighlight", labelWidth)
        row.label:SetPoint("LEFT", LABEL_X, 0)
        row.label:SetJustifyV("MIDDLE")
        row.label:SetWordWrap(false)
        row.source = T:Text(row, "", "GameFontDisableSmall", 62, T.FAINT)
        row.source:SetPoint("RIGHT", -20, 0)
        row.source:SetJustifyH("RIGHT")
        row.source:SetJustifyV("MIDDLE")
        row.source:SetWordWrap(false)

        row.favorite = CreateFrame("Button", nil, row)
        row.favorite:SetSize(16, ROW_H)
        row.favorite:SetPoint("RIGHT", 0, 0)
        row.favorite.glyph = T:Text(row.favorite, "*", "GameFontNormalLarge", 16)
        row.favorite.glyph:SetJustifyH("CENTER")
        row.favorite.glyph:SetPoint("CENTER", 0, -2)
        row.favorite:SetScript("OnClick", function()
            ns.db.favorites[feature.id] = not ns.db.favorites[feature.id] or nil
            ns:Render()
        end)
        T:Tip(row.favorite, "Pin to Overview",
            function() return ns.db.favorites[feature.id]
                and "Pinned. Click to remove it from the Overview page."
                or "Keeps this control on the Overview page." end)

        if kind == "select" then
            row.control = T:Button(row, "", controlWidth, 20, function(button) ns:OpenSelect(feature, button) end)
            row.control:SetPoint("RIGHT", -CONTROL_INSET, 0)
            T:Caret(row.control, 9)
            row.control:SetLabelAnchor("LEFT", row.control, "LEFT", 8, 0)
            -- The chosen value stays inside the button, clear of the caret.
            row.control.label:SetWidth(controlWidth - 26)
            row.control.label:SetJustifyH("LEFT")
            row.control.label:SetWordWrap(false)
            T:Tip(row.control, feature.label, "Click to choose.")
        elseif kind == "action" then
            row.control = T:Button(row, feature.button or "Run", controlWidth, 20, function() ns:Run(feature) end)
            row.control:SetPoint("RIGHT", -CONTROL_INSET, 0)
            if feature.primary then row.control:SetPrimary(true) end
            T:Tip(row.control, feature.label, function() return feature.tooltip or feature.label end)
        elseif kind == "slider" then
            row.value = T:Text(row, "", "GameFontHighlightSmall", 56, T.GOLD)
            row.value:SetJustifyH("RIGHT")
            row.value:SetJustifyV("MIDDLE")
            row.value:SetPoint("RIGHT", -20, 0)
            row.control = T:Slider(row, 260, function(value)
                if ns:Write(feature, value) then row.value:SetText(ns:Format(feature, value)) end
            end)
            row.control:SetPoint("LEFT", 280, 0)
            row.control:Configure(feature.min, feature.max, feature.step)
        elseif kind ~= "info" then
            row.check = T:Check(row, function(button)
                -- A refused write (combat, module unloaded) must not leave the
                -- box showing a value the setting never took.
                if not ns:Write(feature, button:GetChecked()) then
                    button:SetChecked(ns:Read(feature) and true or false)
                end
            end)
            row.check:SetPoint("LEFT", 2, 0)
        end
        -- Moving onto a control inside the row fires the row's OnLeave, so the
        -- children keep the highlight alive themselves.
        for _, child in ipairs({ row.check, row.control, row.favorite }) do
            child:HookScript("OnEnter", function() row.hover:Show() end)
            child:HookScript("OnLeave", function() row.hover:Hide() end)
        end
        T:Tip(row, feature.label, function()
            local body = feature.tooltip or feature.label
            if feature.addon then body = body .. "\n\nFrom the " .. feature.addon .. " module." end
            if feature.reload then body = body .. "\n\nTakes effect after a UI reload." end
            if not ns:Available(feature) then
                -- Settings that depend on another one say which; module
                -- settings wait for their module.
                local why = feature.unavailable or (feature.addon and "Enable the source module and reload first.")
                if why then body = body .. "\n\n" .. why end
            end
            return body
        end)
    end

    local available = self:Available(feature)
    -- The source tag only earns its column in search results and on the
    -- Overview, where the rows no longer come from a single module.
    local plain = feature.kind == nil or feature.kind == "check"
    local source = showSource and plain and (feature.addon or "Mini QoL") or ""
    row.label:SetTextColor(T.Color(available and (feature.kind == "info" and T.MUTED or T.TEXT) or T.FAINT))
    if plain then row.label:SetWidth(source ~= "" and LABEL_W_SOURCE or LABEL_W) end
    row.source:SetText(source)
    row.favorite:SetShown(feature.kind ~= "info")
    row.favorite.glyph:SetTextColor(T.Color(self.db.favorites[feature.id] and T.GOLD or T.FAINT))

    if feature.kind == "info" then
        row.label:SetText(available and (self:Read(feature) or feature.label) or feature.label)
    else
        row.label:SetText(available and LabelText(feature) or feature.label)
    end
    if row.check then
        row.check:SetEnabled(available)
        row.check:SetChecked(self:Read(feature) and true or false)
    end
    if feature.kind == "select" then
        row.control:SetEnabled(available)
        row.control:SetText(available and OptionLabel(feature, self:Read(feature)) or "—")
    elseif feature.kind == "action" then
        row.control:SetEnabled(available)
    elseif feature.kind == "slider" then
        local value = available and self:Read(feature) or feature.min
        row.control:SetEnabled(available)
        row.control:Apply(value)
        row.value:SetText(available and self:Format(feature, value) or "—")
    end
end

function ns:Format(feature, value)
    if feature.format then
        local ok, text = pcall(feature.format, value)
        if ok and text then return text end
    end
    return tostring(value)
end

-- Selects open the game's own context menu: it handles placement, keyboard and
-- closing, and it is transient enough not to fight the panel's look.
function ns:OpenSelect(feature, button)
    local list = Options(feature)
    if #list == 0 then return end
    if not MenuUtil or not MenuUtil.CreateContextMenu then
        -- No menu system: step through the options instead of doing nothing.
        local current = self:Read(feature)
        for index, option in ipairs(list) do
            if option[1] == current then self:Write(feature, list[index % #list + 1][1]); return end
        end
        self:Write(feature, list[1][1])
        return
    end
    MenuUtil.CreateContextMenu(button, function(_, root)
        root:CreateTitle(feature.label)
        for _, option in ipairs(list) do
            root:CreateRadio(option[2],
                function() return ns:Read(feature) == option[1] end,
                function() ns:Write(feature, option[1]) end)
        end
    end)
end

-- Lays out one block of settings: narrow controls pair up, then anything that
-- needs the full width is stacked underneath.
function ns:FeatureBlock(list, y, showSource)
    local narrow, wide = {}, {}
    for _, feature in ipairs(list) do
        local bucket = IsWide(feature) and wide or narrow
        bucket[#bucket + 1] = feature
    end
    for index, feature in ipairs(narrow) do
        local column, line = (index - 1) % 2, math.floor((index - 1) / 2)
        self:FeatureRow(feature, column * (COL_W + COL_GAP), y + line * ROW_H, showSource)
    end
    y = y + math.ceil(#narrow / 2) * ROW_H
    for _, feature in ipairs(wide) do
        self:FeatureRow(feature, 0, y, showSource)
        y = y + ROW_H
    end
    return y
end

---------------------------------------------------------------------------
-- One module
---------------------------------------------------------------------------
function ns:AddonRow(addon, y, jump)
    local row = self:Row("addon." .. addon.name, CARD_H)
    row:SetPoint("TOPLEFT", 0, -y)
    if not row.built then
        row.built = true
        T:Chrome(row, T.BG_CARD, { 0.27, 0.24, 0.17, 1 })
        row.check = T:Check(row, function(button) ns:SetModuleEnabled(addon.name, button:GetChecked()) end)
        row.check:SetPoint("TOPLEFT", 14, -12)
        row.label = T:Text(row, "", "GameFontNormal", 300, T.GOLD)
        row.label:SetPoint("TOPLEFT", 40, -10)
        row.detail = T:Text(row, "", "GameFontDisableSmall", 380, T.MUTED)
        row.detail:SetPoint("TOPLEFT", 52, -29)
        row.detail:SetWordWrap(false)
        row.dot = row:CreateTexture(nil, "OVERLAY")
        row.dot:SetSize(6, 6)
        row.dot:SetPoint("TOPLEFT", 41, -33)
        row.options = T:Button(row, "Settings", 92, 22, function() ns:ShowPage(addon.page) end)
        row.options:SetPoint("RIGHT", -12, 0)
        T:Tip(row.options, "Settings",
            "Jumps to this module's page. Every one of its settings lives there.")
        T:Tip(row.check, "Enable " .. addon.name,
            "Switches the module on or off. Changes apply after a reload; modules that depend on each other are switched together.")
        T:Tip(row, addon.title, function()
            return addon.notes .. "\n\nAuthor: " .. addon.author
                .. (addon.version ~= "" and "\nVersion: " .. addon.version or "")
        end)
    end
    local status, color = ModuleState(addon)
    local detail = status
    if addon.version ~= "" then detail = detail .. "   \194\183   " .. addon.version end
    if addon.author ~= "" then detail = detail .. "   \194\183   " .. addon.author end
    row.label:SetText(addon.title)
    row.dot:SetColorTexture(T.Color(color))
    row.detail:SetText(detail)
    row.check:SetChecked(addon.enabled)
    row.options:SetShown(jump and addon.page ~= nil)
    row.options:SetEnabled(addon.loaded)
    return y + CARD_H + 8
end

-- Compact status tiles for the Overview page: four modules at a glance, each a
-- shortcut to its own page.
function ns:ModuleTiles(addons, y)
    local width = math.floor((CONTENT_W - COL_GAP * 3) / 4)
    for index, addon in ipairs(addons) do
        local tile = self:Row("tile." .. addon.name, TILE_H, width)
        tile:SetPoint("TOPLEFT", (index - 1) * (width + COL_GAP), -y)
        if not tile.built then
            tile.built = true
            T:Chrome(tile, T.BG_CARD, { 0.27, 0.24, 0.17, 1 })
            tile.dot = tile:CreateTexture(nil, "OVERLAY")
            tile.dot:SetSize(6, 6)
            tile.dot:SetPoint("TOPLEFT", 11, -13)
            tile.label = T:Text(tile, "", "GameFontHighlightSmall", width - 32, T.TEXT)
            tile.label:SetPoint("TOPLEFT", 23, -9)
            tile.label:SetWordWrap(false)
            tile.status = T:Text(tile, "", "GameFontDisableSmall", width - 22, T.MUTED)
            tile.status:SetPoint("TOPLEFT", 11, -28)
            tile.status:SetWordWrap(false)
            tile.button = CreateFrame("Button", nil, tile)
            tile.button:SetAllPoints()
            tile.button:SetScript("OnEnter", function() tile:SetBackdropBorderColor(T.Color(T.BORDER_HI)) end)
            tile.button:SetScript("OnLeave", function() tile:SetBackdropBorderColor(0.27, 0.24, 0.17, 1) end)
            tile.button:SetScript("OnClick", function() ns:ShowPage(addon.page) end)
            T:Tip(tile.button, addon.title, function()
                return addon.notes .. "\n\nClick to open this module's page."
            end)
        end
        local status, color = ModuleState(addon)
        tile.label:SetText(addon.name)
        tile.status:SetText(status)
        tile.dot:SetColorTexture(T.Color(color))
    end
    return y + TILE_H + 10
end

---------------------------------------------------------------------------
-- Repaint
---------------------------------------------------------------------------
local DEFAULT_PINS = {
    "wayfinder.showMinimapServices", "wayfinder.showOnWorldMap", "wayfinder.fog",
    "gearwise.bags", "gearwise.popups", "dialogue.enabled",
}

function ns:Render()
    if not self.panel then return end
    local query = self.search:GetText() or ""
    local searching = query ~= ""
    local page = self:Page(self.db.page) or self.pages[1]
    self.db.page = page.id

    self.searchHint:SetShown(not searching)
    self.searchClear:SetShown(searching)
    self.description:SetText(searching and "Matching controls and modules from every category." or page.description)

    local addons = self:Addons()
    local byName = {}
    for _, addon in ipairs(addons) do byName[addon.name] = addon end
    for _, item in ipairs(self.pages) do
        local tab = self.tabs[item.id]
        local selected = item.id == page.id and not searching
        tab.fill:SetShown(selected)
        tab.marker:SetShown(selected)
        tab.label:SetTextColor(T.Color(selected and T.GOLD or T.TEXT))
        if tab.dot then
            local addon = byName[item.module]
            local _, color = ModuleState(addon or { loaded = false, enabled = false })
            tab.dot:SetColorTexture(T.Color(color))
        end
    end

    for _, row in pairs(self.rows) do row:Hide() end

    local features = {}
    for _, feature in ipairs(self.features) do
        local relevant = searching or feature.page == page.id
        if relevant and self:Matches(query, feature.label, feature.addon or "Mini QoL", feature.page, feature.tooltip or "") then
            features[#features + 1] = feature
        end
    end

    local y = 0
    if page.id == "home" and not searching then
        y = self:Section("modules", "Modules", y)
        y = self:ModuleTiles(addons, y)
        local pinned = {}
        for _, feature in ipairs(self.features) do
            if self.db.favorites[feature.id] then pinned[#pinned + 1] = feature end
        end
        local usingDefaults = #pinned == 0
        if usingDefaults then
            for _, id in ipairs(DEFAULT_PINS) do
                for _, feature in ipairs(self.features) do
                    if feature.id == id then pinned[#pinned + 1] = feature; break end
                end
            end
        end
        y = self:Section("pinned", usingDefaults and "Everyday settings" or "Pinned settings", y + 4)
        if usingDefaults then
            y = self:Note("pinhint", "Click the * beside any setting to keep it here.", y)
        end
        features = pinned
        y = self:FeatureBlock(features, y, true)
    elseif searching then
        if #features > 0 then
            y = self:Section("controls", "Search results", y)
            y = self:FeatureBlock(features, y, true)
        end
    else
        -- Settings keep the grouping their module gave them, so a long page
        -- reads as a few short lists rather than one wall of checkboxes.
        local groups, order = {}, {}
        for _, feature in ipairs(features) do
            local name = feature.group or page.label
            if not groups[name] then groups[name] = {}; order[#order + 1] = name end
            local bucket = groups[name]
            bucket[#bucket + 1] = feature
        end
        for index, name in ipairs(order) do
            y = self:Section("g." .. page.id .. "." .. name, name, index == 1 and y or y + 6)
            y = self:FeatureBlock(groups[name], y, false)
        end
    end

    -- Modules appear on their own page, in search results, and all together on
    -- the Mini QoL page. The Overview uses the compact tiles above instead.
    local shown = 0
    for _, addon in ipairs(addons) do
        local relevant = searching or page.id == "miniqol" or page.module == addon.name
        if relevant and self:Matches(query, addon.name, addon.title, addon.notes) then
            if shown == 0 then y = self:Section("modulecards", page.id == "miniqol" and "Modules" or "Module", y + 6) end
            y = self:AddonRow(addon, y, page.module ~= addon.name)
            shown = shown + 1
        end
    end

    if page.id == "miniqol" and not searching then
        y = self:Section("about", "About", y + 4)
        y = self:Note("about", "Mini QoL, Gearwise, Wayfinder and XP Counter by saad780."
            .. "\nPeddler by Cartas; adaptations by saad780."
            .. "\nCarbonite data and OpenMap adaptations are included."
            .. "\nInspired by Leatrix Plus and Dialogue UI."
            .. "\nGPLv3 distribution; no warranty. Redistribution permitted."
            .. "\nSee LICENSE, CREDITS.md and module notices.", y)
    end

    if #features == 0 and shown == 0 and (searching or page.id ~= "home") then
        y = self:Note("empty", searching and ("Nothing matches \"" .. query .. "\".")
            or "Nothing to configure on this page yet.", y + 4)
    end

    self.content:SetHeight(math.max(y + 10, self.scroll:GetHeight()))
    local maxScroll = math.max(0, self.content:GetHeight() - self.scroll:GetHeight())
    self.scroll:SetVerticalScroll(math.min(self.scroll:GetVerticalScroll(), maxScroll))

    local active = 0
    for _, addon in ipairs(addons) do if addon.loaded then active = active + 1 end end
    if self.reloadPending then
        self.footer:SetText("|cffe9c46aChanges are waiting. Reload to apply them.|r")
    else
        self.footer:SetText(active .. " of " .. #addons .. " modules active   \194\183   /mqol")
    end
    self.reload:SetPrimary(self.reloadPending and true or false)
end

---------------------------------------------------------------------------
-- Entry points
---------------------------------------------------------------------------
function ns:ShowPage(page)
    self:CreatePanel()
    self.db.page = page
    self.search:SetText("")
    self.scroll:SetVerticalScroll(0)
    self.panel:Show()
    self:Render()
end

function ns:Toggle()
    self:CreatePanel()
    self.panel:SetShown(not self.panel:IsShown())
end

-- The only entry Mini QoL adds to the game's AddOns list. Every setting for
-- every bundled module lives in the panel, so this page exists purely to open
-- it rather than to be a second, competing settings screen.
function ns:RegisterSettings()
    if not Settings or not Settings.RegisterCanvasLayoutCategory then return end
    local panel = CreateFrame("Frame")
    local title = T:Text(panel, "Mini QoL", "GameFontNormalLarge", nil, T.GOLD)
    title:SetPoint("TOPLEFT", 20, -20)
    local blurb = T:Text(panel, "Peddler, Gearwise, Wayfinder and XP Counter, in one panel.",
        "GameFontHighlight", 520)
    blurb:SetPoint("TOPLEFT", 20, -48)

    local card = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    card:SetPoint("TOPLEFT", 20, -76)
    card:SetSize(430, 118)
    T:Chrome(card, T.BG_CARD, T.BORDER)
    local button = T:Button(card, "Open Mini QoL", 170, 26, function()
        if SettingsPanel and HideUIPanel then HideUIPanel(SettingsPanel) end
        ns:ShowPage("home")
    end)
    button:SetPrimary(true)
    button:SetPoint("TOPLEFT", 16, -16)
    local list = T:Text(card, "Maps and travel  \194\183  Gear advice  \194\183  Selling"
        .. "\nXP and reputation  \194\183  NPC dialogue hotkeys  \194\183  Module switches",
        "GameFontHighlightSmall", 398, T.MUTED)
    list:SetPoint("TOPLEFT", 16, -54)
    local hint = T:Text(card, "Also /mqol, or the gear button beside the minimap.",
        "GameFontDisableSmall", 398, T.FAINT)
    hint:SetPoint("TOPLEFT", 16, -92)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "Mini QoL")
    Settings.RegisterAddOnCategory(category)
end
