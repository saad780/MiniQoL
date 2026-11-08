-- One visual language for every Mini QoL window: warm near-black panels, a thin
-- brass border, gold for anything the player can act on. Widgets built here are
-- plain frames and textures, so they skin identically wherever they are used.
local _, ns = ...
local T = {}
ns.Theme = T

T.GOLD       = { 0.93, 0.78, 0.43 }
T.GOLD_SOFT  = { 0.74, 0.62, 0.35 }
T.TEXT       = { 0.87, 0.85, 0.81 }
T.MUTED      = { 0.58, 0.56, 0.52 }
T.FAINT      = { 0.38, 0.37, 0.34 }
T.GOOD       = { 0.36, 0.87, 0.52 }
T.BAD        = { 1.00, 0.47, 0.47 }
T.INFO       = { 0.55, 0.77, 0.91 }

T.BG         = { 0.052, 0.047, 0.040, 0.97 }
T.BG_HEADER  = { 0.094, 0.084, 0.066, 1 }
T.BG_CARD    = { 0.098, 0.090, 0.074, 0.85 }
T.BG_HOVER   = { 0.70, 0.56, 0.26, 0.10 }
T.BG_ACTIVE  = { 0.70, 0.55, 0.23, 0.19 }
T.BORDER     = { 0.42, 0.35, 0.21, 1 }
T.BORDER_HI  = { 0.86, 0.67, 0.33, 1 }
T.RULE       = { 0.70, 0.58, 0.30, 0.20 }

T.SOLID = "Interface\\Buttons\\WHITE8X8"
local SOLID = T.SOLID
local HAIRLINE = { bgFile = SOLID, edgeFile = SOLID, tile = false, edgeSize = 1 }

function T.Color(c, alpha)
    return c[1], c[2], c[3], alpha or c[4] or 1
end
local Color = T.Color

-- Frames are created with BackdropTemplate by the caller; this only paints them.
function T:Chrome(frame, bg, border)
    frame:SetBackdrop(HAIRLINE)
    frame:SetBackdropColor(Color(bg or self.BG))
    frame:SetBackdropBorderColor(Color(border or self.BORDER))
    return frame
end

-- A window: hairline brass frame, a raised header strip and a soft outer shadow
-- so it reads as a separate surface over the game world.
function T:Window(frame, headerHeight)
    self:Chrome(frame)
    local shadow = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    shadow:SetPoint("TOPLEFT", -5, 5)
    shadow:SetPoint("BOTTOMRIGHT", 5, -5)
    shadow:SetColorTexture(0, 0, 0, 0.42)
    if headerHeight and headerHeight > 0 then
        local header = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        header:SetPoint("TOPLEFT", 1, -1)
        header:SetPoint("TOPRIGHT", -1, -1)
        header:SetHeight(headerHeight)
        header:SetColorTexture(Color(self.BG_HEADER))
        frame.headerStrip = header
        local rule = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
        rule:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
        rule:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
        rule:SetHeight(1)
        rule:SetColorTexture(Color(self.RULE))
        -- A thin gold seam along the very top edge, the way the game's own
        -- parchment headers catch the light.
        local seam = frame:CreateTexture(nil, "BORDER")
        seam:SetPoint("TOPLEFT", 1, -1)
        seam:SetPoint("TOPRIGHT", -1, -1)
        seam:SetHeight(1)
        seam:SetColorTexture(self.GOLD[1], self.GOLD[2], self.GOLD[3], 0.30)
    end
    return frame
end

function T:Text(parent, value, font, width, color)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    if width then label:SetWidth(width) end
    label:SetText(value or "")
    if color then label:SetTextColor(Color(color)) end
    return label
end

function T:Rule(parent, alpha)
    local line = parent:CreateTexture(nil, "BACKGROUND")
    line:SetColorTexture(self.RULE[1], self.RULE[2], self.RULE[3], alpha or self.RULE[4])
    line:SetHeight(1)
    return line
end

function T:Tip(frame, title, body, anchor)
    frame:HookScript("OnEnter", function(self)
        local text = type(title) == "function" and title(self) or title
        if not text then return end
        GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
        GameTooltip:SetText(text, Color(T.GOLD))
        local detail = type(body) == "function" and body(self) or body
        if detail and detail ~= "" then GameTooltip:AddLine(detail, 0.82, 0.80, 0.76, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return frame
end

-- Flat brass button. Disabled, hover and pressed states are all colour, so it
-- stays legible at any UI scale and never fights the stone artwork around it.
function T:Button(parent, label, width, height, onClick)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 92, height or 22)
    self:Chrome(button, self.BG_CARD, self.BORDER)
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.label:SetPoint("CENTER", 0, 0)
    button.label:SetText(label or "")
    button.label:SetTextColor(Color(self.GOLD))
    button.labelPoint = { "CENTER", nil, "CENTER", 0, 0 }

    function button:Paint()
        if not self:IsEnabled() then
            self:SetBackdropColor(0.07, 0.065, 0.055, 0.55)
            self:SetBackdropBorderColor(0.26, 0.23, 0.17, 1)
            self.label:SetTextColor(Color(T.FAINT))
        elseif self.primary then
            local hot = self:IsMouseOver()
            self:SetBackdropColor(0.30, 0.23, 0.09, hot and 1 or 0.92)
            self:SetBackdropBorderColor(Color(hot and T.BORDER_HI or T.GOLD_SOFT))
            self.label:SetTextColor(Color(T.GOLD))
        elseif self:IsMouseOver() then
            self:SetBackdropColor(0.17, 0.15, 0.11, 0.95)
            self:SetBackdropBorderColor(Color(T.BORDER_HI))
            self.label:SetTextColor(Color(T.GOLD))
        else
            self:SetBackdropColor(Color(T.BG_CARD))
            self:SetBackdropBorderColor(Color(T.BORDER))
            self.label:SetTextColor(Color(T.GOLD_SOFT))
        end
    end
    function button:SetText(value) self.label:SetText(value) end
    function button:GetText() return self.label:GetText() end
    function button:SetPrimary(value) self.primary = value and true or false; self:Paint() end

    button:SetScript("OnEnter", function(self) self:Paint() end)
    button:SetScript("OnLeave", function(self) self:Paint() end)
    button:SetScript("OnShow", function(self) self:Paint() end)
    -- Re-anchoring, so clear the previous point rather than stacking anchors.
    local function nudge(self, offset)
        local p = self.labelPoint
        self.label:ClearAllPoints()
        self.label:SetPoint(p[1], p[2] or self, p[3], p[4], p[5] + offset)
    end
    -- Lets a caller put an icon in front of the text without losing the
    -- one-pixel press nudge.
    function button:SetLabelAnchor(point, relativeTo, relativePoint, x, y)
        self.labelPoint = { point, relativeTo, relativePoint, x or 0, y or 0 }
        nudge(self, 0)
    end
    button:SetScript("OnMouseDown", function(self) if self:IsEnabled() then nudge(self, -1) end end)
    button:SetScript("OnMouseUp", function(self) nudge(self, 0) end)
    button:SetScript("OnDisable", function(self) self:Paint() end)
    button:SetScript("OnEnable", function(self) self:Paint() end)
    if onClick then button:SetScript("OnClick", onClick) end
    button:Paint()
    return button
end

-- Square tick box drawn from colour alone, to match the buttons.
function T:Check(parent, onClick)
    local check = CreateFrame("Button", nil, parent, "BackdropTemplate")
    check:SetSize(16, 16)
    self:Chrome(check, { 0.03, 0.028, 0.024, 0.9 }, self.BORDER)
    check.mark = check:CreateTexture(nil, "OVERLAY")
    check.mark:SetPoint("TOPLEFT", 3, -3)
    check.mark:SetPoint("BOTTOMRIGHT", -3, 3)
    check.mark:SetColorTexture(Color(self.GOLD))
    check.mark:Hide()

    function check:Paint()
        local on = self.checked and true or false
        self.mark:SetShown(on)
        if not self:IsEnabled() then
            self:SetBackdropBorderColor(0.26, 0.23, 0.17, 1)
            self.mark:SetColorTexture(Color(T.FAINT))
        elseif self:IsMouseOver() then
            self:SetBackdropBorderColor(Color(T.BORDER_HI))
            self.mark:SetColorTexture(Color(T.GOLD))
        else
            self:SetBackdropBorderColor(Color(on and T.GOLD_SOFT or T.BORDER))
            self.mark:SetColorTexture(Color(T.GOLD))
        end
    end
    function check:SetChecked(value) self.checked = value and true or false; self:Paint() end
    function check:GetChecked() return self.checked and true or false end

    check:SetScript("OnEnter", function(self) self:Paint() end)
    check:SetScript("OnLeave", function(self) self:Paint() end)
    check:SetScript("OnDisable", function(self) self:Paint() end)
    check:SetScript("OnEnable", function(self) self:Paint() end)
    if onClick then
        check:SetScript("OnClick", function(self)
            self:SetChecked(not self.checked)
            onClick(self)
        end)
    end
    check:Paint()
    return check
end

-- A small chevron drawn from two lines, so a button reads as "opens a list"
-- without depending on any artwork file.
function T:Caret(button, inset)
    local lines = {}
    for index, points in ipairs({ { -4, 2, 0, -2 }, { 0, -2, 4, 2 } }) do
        local line = button:CreateLine(nil, "OVERLAY")
        line:SetThickness(1.4)
        line:SetColorTexture(Color(self.GOLD_SOFT))
        line:SetStartPoint("RIGHT", button, -(inset or 8) + points[1], points[2])
        line:SetEndPoint("RIGHT", button, -(inset or 8) + points[3], points[4])
        lines[index] = line
    end
    button.caret = lines
    return lines
end

-- Horizontal slider: a hairline track with a brass thumb. Programmatic changes
-- never reach the callback, so repainting the panel cannot write settings back.
function T:Slider(parent, width, onChange)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, 16)
    local track = CreateFrame("Frame", nil, holder, "BackdropTemplate")
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    track:SetHeight(4)
    self:Chrome(track, { 0.025, 0.023, 0.020, 0.95 }, self.BORDER)

    local slider = CreateFrame("Slider", nil, holder)
    slider:SetAllPoints()
    slider:SetOrientation("HORIZONTAL")
    slider:SetObeyStepOnDrag(true)
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(Color(self.GOLD))
    thumb:SetSize(7, 15)
    slider:SetThumbTexture(thumb)
    holder.slider, holder.thumb, holder.track = slider, thumb, track

    function holder:Configure(minValue, maxValue, step)
        slider:SetMinMaxValues(minValue, maxValue)
        slider:SetValueStep(step)
    end
    function holder:Apply(value)
        self.applying = true
        slider:SetValue(value)
        self.applying = false
    end
    function holder:SetEnabled(enabled)
        slider:EnableMouse(enabled and true or false)
        thumb:SetColorTexture(Color(enabled and T.GOLD or T.FAINT))
    end
    slider:SetScript("OnValueChanged", function(_, value)
        if holder.applying or not onChange then return end
        onChange(value)
    end)
    slider:SetScript("OnEnter", function() thumb:SetColorTexture(Color(T.GOLD)); track:SetBackdropBorderColor(Color(T.BORDER_HI)) end)
    slider:SetScript("OnLeave", function() track:SetBackdropBorderColor(Color(T.BORDER)) end)
    return holder
end

function T:CloseButton(parent, onClick)
    local close = CreateFrame("Button", nil, parent)
    close:SetSize(22, 22)
    local glyph = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    glyph:SetPoint("CENTER", 0, 1)
    glyph:SetText("\195\151") -- multiplication sign: a cleaner cross than "x"
    glyph:SetTextColor(Color(self.MUTED))
    close:SetScript("OnEnter", function() glyph:SetTextColor(Color(T.GOLD)) end)
    close:SetScript("OnLeave", function() glyph:SetTextColor(Color(T.MUTED)) end)
    close:SetScript("OnClick", onClick or function() parent:Hide() end)
    return close
end

-- Strips the stone artwork off a Blizzard scroll frame's bar, leaving a thin
-- brass thumb that matches everything else in the window.
function T:SkinScrollBar(scroll, name)
    local bar = scroll.ScrollBar or (name and _G[name .. "ScrollBar"])
    if not bar then return end
    for _, key in ipairs({ "ScrollUpButton", "ScrollDownButton", "Back", "Forward" }) do
        local child = bar[key] or (name and _G[name .. "ScrollBar" .. key])
        if child and child.Hide then child:Hide(); child:SetAlpha(0) end
    end
    local thumb = bar.GetThumbTexture and bar:GetThumbTexture()
    if thumb then
        thumb:SetTexture(SOLID)
        thumb:SetVertexColor(self.GOLD_SOFT[1], self.GOLD_SOFT[2], self.GOLD_SOFT[3], 0.55)
        thumb:SetSize(4, 48)
    end
    for _, region in ipairs({ bar:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "Texture" and region ~= thumb then
            region:SetAlpha(0)
        end
    end
    bar:SetWidth(8)
    return bar
end

-- Item-quality colour for a link, falling back to plain text colour.
function T:QualityColor(link)
    if type(link) ~= "string" then return self.MUTED end
    local hex = link:match("|c(%x%x%x%x%x%x%x%x)")
    if not hex then return self.TEXT end
    local r = tonumber(hex:sub(3, 4), 16) or 200
    local g = tonumber(hex:sub(5, 6), 16) or 200
    local b = tonumber(hex:sub(7, 8), 16) or 200
    return { r / 255, g / 255, b / 255, 1 }
end

function T:StripColor(value)
    if type(value) ~= "string" then return "" end
    return (value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", ""))
end
