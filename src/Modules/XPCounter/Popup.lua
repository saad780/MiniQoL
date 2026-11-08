local addonName, addon = ...

local db
local moving = false
local popupSerial = 0

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
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
