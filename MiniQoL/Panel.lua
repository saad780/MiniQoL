local _, ns = ...
local GOLD = { 0.91, 0.77, 0.42 }
local descriptions = {
    home = "Your everyday controls, together.", maps = "Exploration, service icons, navigation and travel.",
    bags = "Gearwise item comparisons, upgrade arrows and gear advice.", quests = "XP Counter chat reports, reputation and floating text.",
    sound = "Lightweight hotkeys for native NPC dialogue windows.", selling = "Peddler item marking and vendor selling.",
    miniqol = "Panel preferences and source credits.",
}

local function text(parent, value, x, y, font, width)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    label:SetPoint("TOPLEFT", x, y)
    label:SetJustifyH("LEFT")
    if width then label:SetWidth(width); label:SetWordWrap(false) end
    label:SetText(value)
    return label
end

local function tip(frame, title, body)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, unpack(GOLD))
        if body then GameTooltip:AddLine(body, 0.85, 0.85, 0.85, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function action(parent, label, width, callback)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetText(label)
    button:SetScript("OnClick", callback)
    return button
end

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

function ns:CreatePanel()
    if self.panel then return end
    local panel = CreateFrame("Frame", "MiniQoLPanel", UIParent, "BackdropTemplate")
    self.panel = panel
    panel:SetSize(704, 430)
    panel:SetPoint("CENTER")
    panel:SetClampedToScreen(true)
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    panel:SetBackdropColor(0.065, 0.06, 0.05, 0.98)
    panel:SetBackdropBorderColor(0.45, 0.39, 0.27, 1)
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        ns.db.position = { point, relativePoint, x, y }
    end)
    local p = self.db.position
    if type(p) == "table" and #p == 4 then panel:ClearAllPoints(); panel:SetPoint(p[1], UIParent, p[2], p[3], p[4]) end
    UISpecialFrames[#UISpecialFrames + 1] = "MiniQoLPanel"
    text(panel, "Mini QoL", 18, -17, "GameFontNormalLarge")
    text(panel, "WoW Forever", 19, -39, "GameFontDisableSmall")
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -3, -3)
    local divider = panel:CreateTexture(nil, "BACKGROUND")
    divider:SetColorTexture(0.7, 0.58, 0.3, 0.22)
    divider:SetPoint("TOPLEFT", 151, -63)
    divider:SetPoint("BOTTOMLEFT", 151, 38)
    divider:SetWidth(1)
    self.tabs = {}
    for index, page in ipairs(self.pages) do
        local id, label = page[1], page[2]
        local tab = CreateFrame("Button", nil, panel)
        tab:SetSize(128, 27)
        tab:SetPoint("TOPLEFT", 15, -67 - (index - 1) * 29)
        tab.label = text(tab, label, 9, -7, "GameFontHighlight", 118)
        tab.selected = tab:CreateTexture(nil, "BACKGROUND")
        tab.selected:SetAllPoints()
        tab.selected:SetColorTexture(0.7, 0.55, 0.23, 0.18)
        tab:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        tab:SetScript("OnClick", function()
            ns.db.page = id
            ns.search:SetText("")
            ns:Render()
        end)
        self.tabs[id] = tab
    end
    self.title = text(panel, "Overview", 169, -19, "GameFontNormalLarge", 270)
    self.description = text(panel, "", 169, -43, "GameFontDisableSmall", 500)
    local search = CreateFrame("EditBox", "MiniQoLSearch", panel, "InputBoxTemplate")
    self.search = search
    search:SetSize(176, 21)
    search:SetPoint("TOPRIGHT", -40, -17)
    search:SetAutoFocus(false)
    search:SetMaxLetters(80)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnTextChanged", function() ns:Render() end)
    tip(search, "Search everything", "Find controls and modules across every category. Clear to return to the selected page.")
    self.searchHint = text(search, "Search settings...", 1, -5, "GameFontDisableSmall", 170)
    local scroll = CreateFrame("ScrollFrame", "MiniQoLScrollFrame", panel, "UIPanelScrollFrameTemplate")
    self.scroll = scroll
    scroll:SetPoint("TOPLEFT", 168, -69)
    scroll:SetPoint("BOTTOMRIGHT", -32, 45)
    local content = CreateFrame("Frame", nil, scroll)
    self.content = content
    content:SetSize(500, 300)
    scroll:SetScrollChild(content)
    self.rows = {}
    self.footer = text(panel, "", 170, -402, "GameFontDisableSmall", 355)
    self.reload = action(panel, "Reload UI", 91, function()
        if InCombatLockdown() then ns:Print("Reload after combat."); return end
        ReloadUI()
    end)
    self.reload:SetPoint("BOTTOMRIGHT", -16, 12)
    panel:SetScript("OnShow", function() ns:Render() end)
    panel:Hide()
end

function ns:Row(key, height)
    local row = self.rows[key]
    if not row then
        row = CreateFrame("Frame", nil, self.content)
        row:EnableMouse(true)
        self.rows[key] = row
    end
    row:SetSize(500, height)
    row:ClearAllPoints()
    row:Show()
    return row
end

function ns:Section(key, label, y)
    local row = self:Row("section." .. key, 29)
    if not row.label then
        row.label = text(row, "", 0, -7, "GameFontNormal")
        row.line = row:CreateTexture(nil, "BACKGROUND")
        row.line:SetColorTexture(0.7, 0.58, 0.3, 0.16)
        row.line:SetPoint("BOTTOMLEFT", 0, 0)
        row.line:SetSize(494, 1)
    end
    row.label:SetText(label)
    row:SetPoint("TOPLEFT", 0, -y)
    return y + 33
end

function ns:FeatureRow(feature, x, y)
    local row = self:Row("feature." .. feature.id, 43)
    row:SetWidth(246)
    row:SetPoint("TOPLEFT", x, -y)
    if not row.label then
        row.label = text(row, "", 25, -3, "GameFontHighlight", feature.kind == "choice" and 112 or 195)
        row.source = text(row, "", 25, -21, "GameFontDisableSmall", 194)
        row.favorite = CreateFrame("Button", nil, row)
        row.favorite:SetSize(16, 18)
        row.favorite:SetPoint("TOPRIGHT", -2, 0)
        row.favorite.label = text(row.favorite, "*", 3, -1, "GameFontNormalLarge")
        row.favorite:SetScript("OnClick", function()
            ns.db.favorites[feature.id] = not ns.db.favorites[feature.id] or nil
            ns:Render()
        end)
        tip(row.favorite, "Favorite", "Pin this control to Overview.")
        if feature.kind == "choice" then
            row.choice = action(row, "", 83, function()
                local value = ns:Read(feature)
                for i, option in ipairs(feature.choices) do
                    if option[1] == value then ns:Write(feature, feature.choices[i % #feature.choices + 1][1]); return end
                end
                ns:Write(feature, feature.choices[1][1])
            end)
            row.choice:SetPoint("TOPRIGHT", -19, -1)
        else
            row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.check:SetSize(25, 25)
            row.check:SetPoint("TOPLEFT", -3, 2)
            row.check:SetScript("OnClick", function(self) ns:Write(feature, self:GetChecked() and true or false) end)
            tip(row.check, feature.label, feature.tooltip .. (feature.reload and "\n\nRequires a UI reload." or ""))
        end
    end
    local available = self:Available(feature)
    row.label:SetText(feature.label)
    row.source:SetText((feature.addon or "Mini QoL") .. (feature.reload and " |cffe9c46a(reload)|r" or ""))
    row.favorite.label:SetTextColor(unpack(self.db.favorites[feature.id] and GOLD or { 0.32, 0.32, 0.32 }))
    row:SetAlpha(available and 1 or 0.4)
    if row.check then row.check:SetEnabled(available); row.check:SetChecked(self:Read(feature) and true or false) end
    if row.choice then
        row.choice:SetEnabled(available)
        local value = self:Read(feature)
        for _, option in ipairs(feature.choices) do if option[1] == value then row.choice:SetText(option[2]); break end end
    end
    tip(row, feature.label, (feature.tooltip or feature.label) .. (available and "" or "\n\nEnable the source module and reload first."))
end

function ns:AddonRow(addon, y)
    local row = self:Row("addon." .. addon.name, 44)
    row:SetPoint("TOPLEFT", 0, -y)
    if not row.label then
        row.label = text(row, "", 25, -2, "GameFontHighlight", 350)
        row.detail = text(row, "", 25, -21, "GameFontDisableSmall", 350)
        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetSize(25, 25)
        row.check:SetPoint("TOPLEFT", -3, 3)
        row.check:SetScript("OnClick", function(self) ns:SetModuleEnabled(addon.name, self:GetChecked() and true or false) end)
        row.options = action(row, "Options", 82, function() ns:OpenProvider(addon.provider) end)
        row.options:SetPoint("TOPRIGHT", -7, -4)
    end
    row.label:SetText(addon.title)
    local status = addon.loaded and (addon.enabled and "Active" or "Off after reload") or (addon.enabled and "Reload to activate" or "Off")
    row.detail:SetText(status .. (addon.version ~= "" and "  |  " .. addon.version or ""))
    row.check:SetShown(MiniQoLRuntime ~= nil and MiniQoLRuntime.modules[addon.name] ~= nil)
    row.check:SetChecked(addon.enabled)
    row.options:SetShown(addon.provider ~= nil)
    row.options:SetEnabled(addon.provider and self:Loaded(addon.provider.addon) or false)
    local module = MiniQoLRuntime and MiniQoLRuntime.modules[addon.name]
    local author = module and module.metadata.Author or "See source credits"
    tip(row, addon.name, addon.notes .. "\n\nAuthor: " .. author .. "\n\nModule switches apply after a reload. Required dependencies are switched together.")
    tip(row.check, "Enable " .. addon.name, "Changes apply after a reload. Required dependencies are enabled together; dependent modules are disabled together.")
    return y + 46
end

function ns:Render()
    if not self.panel then return end
    local page, query = self.db.page or "home", self.search:GetText() or ""
    local validPage = false
    for _, item in ipairs(self.pages) do if item[1] == page then validPage = true; self.title:SetText(item[2]) end end
    if not validPage then page = "home"; self.db.page = page; self.title:SetText("Overview") end
    if query ~= "" then self.title:SetText("Search results") end
    self.searchHint:SetShown(query == "")
    self.description:SetText(query ~= "" and "Controls and modules from every category." or descriptions[page])
    for id, tab in pairs(self.tabs) do
        tab.selected:SetShown(id == page and query == "")
        tab.label:SetTextColor(unpack(id == page and GOLD or { 0.8, 0.8, 0.8 }))
    end
    for _, row in pairs(self.rows) do row:Hide() end
    local y, featureCount = 0, 0
    local features = {}
    for _, feature in ipairs(self.features) do
        local relevant = query ~= "" or feature.page == page or (page == "home" and self.db.favorites[feature.id])
        if relevant and self:Matches(query, feature.label, feature.addon or "Mini QoL", feature.page, feature.tooltip or "") then
            features[#features + 1] = feature
        end
    end
    if page == "home" and query == "" then
        local intro = self:Row("intro", 51)
        intro:SetPoint("TOPLEFT", 0, 0)
        if not intro.label then intro.label = text(intro, "", 0, -2, "GameFontHighlight", 495); intro.note = text(intro, "", 0, -24, "GameFontDisableSmall", 495) end
        intro.label:SetText("Peddler, Gearwise, Wayfinder and XP Counter.")
        intro.note:SetText("Choose a category, search, or star a setting to keep it here.")
        y = 54
        y = self:Section("favorites", #features > 0 and "Favorite settings" or "Everyday settings", y)
        if #features == 0 then
            local selected = { ["wayfinder.showMinimapServices"] = true, ["wayfinder.showOnWorldMap"] = true,
                ["wayfinder.fog"] = true, ["gearwise.bags"] = true, ["dialogue.enabled"] = true, ["miniqol.icon"] = true }
            for _, feature in ipairs(self.features) do if selected[feature.id] then features[#features + 1] = feature end end
        end
    elseif #features > 0 then y = self:Section("controls", "Quick controls", y) end
    for index, feature in ipairs(features) do
        local col, line = (index - 1) % 2, math.floor((index - 1) / 2)
        self:FeatureRow(feature, col * 251, y + line * 44)
    end
    featureCount = #features
    y = y + math.ceil(#features / 2) * 44
    local count, active = 0, 0
    local addons = self:Addons()
    for _, addon in ipairs(addons) do if addon.loaded then active = active + 1 end end
    if page ~= "miniqol" or query ~= "" then
        for _, addon in ipairs(addons) do
            if (query ~= "" or page == "addons" or page == "home" and addon.provider and addon.name == addon.provider.addon or addon.page == page)
                and self:Matches(query, addon.name, addon.title, addon.notes) then
                if count == 0 then y = self:Section("modules", page == "home" and "Module settings" or "Modules & advanced settings", y + 5) end
                y = self:AddonRow(addon, y)
                count = count + 1
            end
        end
    else
        y = self:Section("about", "Mini QoL  " .. self.version, y + 8)
        local about = self:Row("about", 78)
        about:SetPoint("TOPLEFT", 0, -y)
        if not about.label then
            about.label = text(about, "Panel and NPC shortcuts by saad780.\nPanel layout inspired by Leatrix Plus.\nNPC shortcuts inspired by Dialogue UI.\nBundled modules retain their original authors and licences.\nFull notices are included in CREDITS.md and each module folder.", 0, -3, "GameFontHighlightSmall")
            about.label:SetWidth(494); about.label:SetWordWrap(true)
        end
        y = y + 83
        y = self:Section("credits", "Module authors", y)
        local runtime = MiniQoLRuntime
        if runtime then
            for _, name in ipairs(runtime.order) do
                local row = self:Row("credit." .. name, 37)
                row:SetPoint("TOPLEFT", 0, -y)
                if not row.label then row.label = text(row, name, 0, -2, "GameFontNormalSmall", 490); row.author = text(row, runtime.modules[name].metadata.Author or "See retained source headers", 0, -18, "GameFontHighlightSmall", 490) end
                y = y + 39
            end
        end
    end
    if featureCount == 0 and count == 0 and (page ~= "miniqol" or query ~= "") then
        local empty = self:Row("empty", 40)
        empty:SetPoint("TOPLEFT", 0, -y)
        if not empty.label then empty.label = text(empty, "No matching settings or modules.", 0, -8, "GameFontDisable") end
        y = y + 45
    end
    self.content:SetHeight(math.max(y + 8, 300))
    local maxScroll = math.max(0, self.content:GetHeight() - self.scroll:GetHeight())
    self.scroll:SetVerticalScroll(math.min(self.scroll:GetVerticalScroll(), maxScroll))
    self.footer:SetText(self.reloadPending and "|cffe9c46aChanges pending. Reload to apply.|r" or (active .. " / " .. #addons .. " modules active   |   /mqol"))
end

function ns:ShowPage(page)
    self:CreatePanel()
    self.db.page = page
    self.search:SetText("")
    self.panel:Show()
    self:Render()
end

function ns:Toggle()
    self:CreatePanel()
    self.panel:SetShown(not self.panel:IsShown())
end

function ns:RegisterSettings()
    if not Settings or not Settings.RegisterCanvasLayoutCategory then return end
    local panel = CreateFrame("Frame")
    text(panel, "Mini QoL", 20, -20, "GameFontNormalLarge")
    text(panel, "Compact controls for your WoW Forever setup.", 20, -53)
    local button = action(panel, "Open Mini QoL", 155, function() ns:ShowPage("home") end)
    button:SetPoint("TOPLEFT", 20, -84)
    local category = Settings.RegisterCanvasLayoutCategory(panel, "Mini QoL")
    Settings.RegisterAddOnCategory(category)
end
