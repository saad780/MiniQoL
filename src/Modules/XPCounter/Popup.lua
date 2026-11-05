local addonName, addon = ...

local db
local moving = false
local popupSerial = 0
local category

local popup = CreateFrame("Frame", "XPCounterPopup", UIParent)
popup:SetSize(400, 44)
popup:SetFrameStrata("HIGH")
popup:SetClampedToScreen(true)
popup:SetMovable(true)
popup:RegisterForDrag("LeftButton")
popup:EnableMouse(false)
popup:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
popup:Hide()

local body = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
body:SetAllPoints()
body:SetJustifyH("CENTER")
body:SetJustifyV("MIDDLE")
body:SetShadowColor(0, 0, 0, 0.9)
body:SetShadowOffset(1, -1)

local function savePosition()
    if not db then return end
    local x, y = popup:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if x and y and parentX and parentY then
        db.x = math.floor(x - parentX + 0.5)
        db.y = math.floor(y - parentY + 0.5)
    end
end

popup:SetScript("OnDragStart", function(self)
    if moving then self:StartMoving() end
end)
popup:SetScript("OnDragStop", function(self)
    if moving then
        self:StopMovingOrSizing()
        savePosition()
    end
end)

local function preview()
    if not db or not db.popupsEnabled then return end
    popupSerial = popupSerial + 1
    body:SetText(moving and "Drag text; right-click to finish" or "53 XP - 3 more (~2m)")
    popup:Show()
    if not moving then
        local thisPopup = popupSerial
        C_Timer.After(5, function()
            if not moving and thisPopup == popupSerial then popup:Hide() end
        end)
    end
end

local function setMoving(enabled)
    moving = enabled and db and db.popupsEnabled or false
    popup:EnableMouse(moving)
    if moving then
        preview()
    else
        popupSerial = popupSerial + 1
        popup:Hide()
    end
end

popup:SetScript("OnMouseUp", function(_, button)
    if moving and button == "RightButton" then setMoving(false) end
end)

function addon.ShowPopup(message)
    if not db or not db.popupsEnabled or moving then return end
    popupSerial = popupSerial + 1
    local thisPopup = popupSerial
    body:SetText(message)
    popup:Show()
    C_Timer.After(5, function()
        if not moving and thisPopup == popupSerial then popup:Hide() end
    end)
end

local function createSettings()
    if not Settings or not Settings.RegisterCanvasLayoutCategory then return end
    local panel = CreateFrame("Frame", nil, UIParent)
    panel.name = "XP Counter"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -20)
    title:SetText("XP Counter")

    local checkbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -18)
    checkbox:SetChecked(db.popupsEnabled)

    local checkboxText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    checkboxText:SetPoint("LEFT", checkbox, "RIGHT", 8, 0)
    checkboxText:SetText("Show on-screen text popups (off by default)")

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", checkbox, "BOTTOMLEFT", 0, -12)
    description:SetText("Chat messages stay on. Popups disappear after 5 seconds.")

    local moveButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    moveButton:SetSize(130, 25)
    moveButton:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -20)

    local testButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    testButton:SetSize(110, 25)
    testButton:SetPoint("LEFT", moveButton, "RIGHT", 10, 0)
    testButton:SetText("Test popup")

    local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetButton:SetSize(120, 25)
    resetButton:SetPoint("LEFT", testButton, "RIGHT", 10, 0)
    resetButton:SetText("Reset position")

    local help = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", moveButton, "BOTTOMLEFT", 0, -15)
    help:SetText("Click Move popup, drag with the left button, then right-click the popup to finish.")

    local function refresh()
        checkbox:SetChecked(db.popupsEnabled)
        moveButton:SetEnabled(db.popupsEnabled)
        testButton:SetEnabled(db.popupsEnabled)
        moveButton:SetText(moving and "Done moving" or "Move popup")
    end

    checkbox:SetScript("OnClick", function(self)
        db.popupsEnabled = not not self:GetChecked()
        if not db.popupsEnabled then setMoving(false) end
        refresh()
    end)
    moveButton:SetScript("OnClick", function()
        setMoving(not moving)
        refresh()
        if moving and SettingsPanel and HideUIPanel then HideUIPanel(SettingsPanel) end
    end)
    testButton:SetScript("OnClick", preview)
    resetButton:SetScript("OnClick", function()
        db.x, db.y = 0, 180
        popup:ClearAllPoints()
        popup:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
        if moving then preview() end
    end)
    panel:SetScript("OnShow", refresh)

    category = Settings.RegisterCanvasLayoutCategory(panel, "XP Counter")
    Settings.RegisterAddOnCategory(category)
    refresh()
end

function addon.OpenSettings()
    if category and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, loadedName)
    if event == "ADDON_LOADED" then
        if loadedName ~= addonName then return end
        XPCounterDB = type(XPCounterDB) == "table" and XPCounterDB or {}
        db = XPCounterDB
        -- Apply the new default once to existing installations, then keep the player's choice.
        if type(db.popupDefaultRevision) ~= "number" or db.popupDefaultRevision < 2 then
            db.popupsEnabled = false
            db.popupDefaultRevision = 2
        end
        if type(db.x) ~= "number" or type(db.y) ~= "number" then db.x, db.y = 0, 180 end
        popup:ClearAllPoints()
        popup:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
        createSettings()
        self:UnregisterEvent("ADDON_LOADED")
        if not category then self:RegisterEvent("PLAYER_LOGIN") end
    elseif event == "PLAYER_LOGIN" then
        createSettings()
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
