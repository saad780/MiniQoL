local _, ns = ...

function ns:ConsolidateIcons()
    -- Compatibility no-op for older saved profiles. Other addons own their icons.
end

function ns:UpdateMinimapButton()
    local button = self.minimapButton
    if not button or not self.db then return end
    button:SetShown(not self.db.minimap.hide)
    local angle = math.rad(self.db.minimap.angle or 220)
    local radiusX, radiusY = Minimap:GetWidth() / 2 + 6, Minimap:GetHeight() / 2 + 6
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radiusX, math.sin(angle) * radiusY)
end

function ns:CreateMinimapButton()
    if self.minimapButton then return end
    local button = CreateFrame("Button", "MiniQoLMinimapButton", Minimap)
    self.minimapButton = button
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 10)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", 0, 0)
    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then ns:ShowPage("miniqol") else ns:Toggle() end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            local mx, my = Minimap:GetCenter()
            if mx and my then
                ns.db.minimap.angle = math.deg(math.atan2(y / scale - my, x / scale - mx))
                ns:UpdateMinimapButton()
            end
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Mini QoL", 0.91, 0.77, 0.42)
        GameTooltip:AddLine("Left-click: settings", 1, 1, 1)
        GameTooltip:AddLine("Right-click: Mini QoL options", 1, 1, 1)
        GameTooltip:AddLine("Drag: move around the minimap", 0.65, 0.65, 0.65)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self:UpdateMinimapButton()
end
