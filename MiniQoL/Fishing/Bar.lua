local _, ns = ...
-- The small window that appears while you are holding a pole: lures, fishing
-- food, what your skill is made of, and what you have been pulling up.
local Fishing = ns.Fishing
local T = ns.Theme

local WIDTH, PAD = 232, 12
local ICON = 30
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local bar, lureButtons, foodButton

local function Secure(parent, name)
    -- BackdropTemplate as well as the secure one: Chrome below needs SetBackdrop.
    local button = CreateFrame("Button", name, parent, "SecureActionButtonTemplate, BackdropTemplate")
    button:SetSize(ICON, ICON)
    button:RegisterForClicks("AnyUp")
    T:Chrome(button, T.BG_CARD, { 0.27, 0.24, 0.17, 1 })
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.count = T:Text(button, "", "GameFontNormalSmall", ICON, T.TEXT)
    button.count:SetJustifyH("RIGHT")
    button.count:SetPoint("BOTTOMRIGHT", -2, 2)
    button:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(T.Color(T.BORDER_HI))
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.27, 0.24, 0.17, 1)
        GameTooltip:Hide()
    end)
    return button
end

function Fishing:CreateBar()
    bar = CreateFrame("Frame", "MiniQoLFishingBar", UIParent, "BackdropTemplate")
    self.bar = bar
    bar:Hide()
    bar:SetSize(WIDTH, 180)
    bar:SetFrameStrata("MEDIUM")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    T:Window(bar, 26)
    local saved = self.db.barPosition
    if type(saved) == "table" and #saved == 4 then
        bar:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
    else
        bar:SetPoint("CENTER", UIParent, "CENTER", 320, 0)
    end
    bar:SetScript("OnDragStart", bar.StartMoving)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        Fishing.db.barPosition = { point, relativePoint, x, y }
    end)

    bar.title = T:Text(bar, "Fishing", "GameFontNormalSmall", 120, T.GOLD)
    bar.title:SetPoint("TOPLEFT", PAD, -8)
    T:CloseButton(bar, function() Fishing:Set("bar", false) end):SetPoint("TOPRIGHT", -4, -4)

    bar.skill = T:Text(bar, "", "GameFontNormalLarge", WIDTH - PAD * 2, T.GOLD)
    bar.skill:SetPoint("TOPLEFT", PAD, -32)
    bar.breakdown = T:Text(bar, "", "GameFontDisableSmall", WIDTH - PAD * 2, T.MUTED)
    bar.breakdown:SetPoint("TOPLEFT", PAD, -52)
    bar.timers = T:Text(bar, "", "GameFontHighlightSmall", WIDTH - PAD * 2, T.INFO)
    bar.timers:SetPoint("TOPLEFT", PAD, -68)

    bar.lureLabel = T:Text(bar, "LURES", "GameFontDisableSmall", WIDTH - PAD * 2, T.GOLD_SOFT)
    bar.lureLabel:SetPoint("TOPLEFT", PAD, -88)
    lureButtons = {}
    foodButton = Secure(bar, "MiniQoLFishingFoodButton")
    foodButton:SetAttribute("type", "item")

    bar.rule = T:Rule(bar)
    bar.rule:SetWidth(WIDTH - PAD * 2)
    bar.session = T:Text(bar, "", "GameFontHighlightSmall", WIDTH - PAD * 2, T.TEXT)
    bar.recent = T:Text(bar, "", "GameFontDisableSmall", WIDTH - PAD * 2, T.MUTED)
    return bar
end

local function LureButton(index)
    local button = lureButtons[index]
    if not button then
        button = Secure(bar, "MiniQoLFishingLure" .. index)
        button:SetAttribute("type", "macro")
        button:SetScript("PostClick", function(self)
            if self.itemID then Fishing:WatchLure(self.itemID) end
        end)
        lureButtons[index] = button
    end
    return button
end

function Fishing:RefreshBar()
    if not bar or not bar:IsShown() then return end
    local combat = InCombatLockdown()

    local skill = self:Skill()
    if skill then
        bar.skill:SetText(("Fishing %d"):format(skill.total))
        local parts = { ("%d trained"):format(skill.rank) }
        if skill.lure > 0 then parts[#parts + 1] = ("+%d lure"):format(skill.lure) end
        if skill.gear > 0 then parts[#parts + 1] = ("+%d gear"):format(skill.gear) end
        if skill.buffs > 0 then parts[#parts + 1] = ("+%d buffs"):format(skill.buffs) end
        bar.breakdown:SetText(table.concat(parts, "  "))
    else
        bar.skill:SetText("Fishing")
        bar.breakdown:SetText("Not trained yet.")
    end

    local timers = {}
    local lureLeft = self:LureTimeLeft()
    timers[#timers + 1] = lureLeft and ("Lure " .. self.Short(lureLeft)) or "No lure on the pole"
    local foodLeft = self:FoodTimeLeft()
    if foodLeft then timers[#timers + 1] = "Food " .. self.Short(foodLeft) end
    local other = self:OtherBuff()
    if other then timers[#timers + 1] = other.name end
    bar.timers:SetText(table.concat(timers, "   \194\183   "))

    -- Lure and food buttons. Attributes can only be set out of combat, so in
    -- combat the row is simply left as it was.
    local x, shown = 0, 0
    if not combat then
        for index, lure in ipairs(self:CarriedLures()) do
            local button = LureButton(index)
            button.itemID = lure.itemID
            button:SetAttribute("macrotext", self:LureMacro(lure.itemID))
            button.icon:SetTexture(self.GetItemIcon(lure.itemID) or QUESTION)
            button.icon:SetDesaturated(not lure.usable)
            button.count:SetText(lure.count > 1 and lure.count or "")
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", PAD + x, -104)
            button:Show()
            x, shown = x + ICON + 4, index
        end
        for index = shown + 1, #lureButtons do lureButtons[index]:Hide() end
        local food = self:BestFood()
        if food then
            foodButton.itemID = food
            foodButton:SetAttribute("item", "item:" .. food)
            foodButton.icon:SetTexture(self.GetItemIcon(food) or QUESTION)
            foodButton.count:SetText(self.GetItemCount(food))
            foodButton:ClearAllPoints()
            foodButton:SetPoint("TOPRIGHT", -PAD, -104)
            foodButton:Show()
        else
            foodButton:Hide()
        end
    end
    bar.lureLabel:SetText(shown > 0 and "LURES" or "NO LURES IN YOUR BAGS")

    -- The button row only takes space when there is something in it.
    local hasButtons = shown > 0 or (not combat and self:BestFood() ~= nil)
    local y = hasButtons and (104 + ICON + 10) or 112
    bar.rule:ClearAllPoints()
    bar.rule:SetPoint("TOPLEFT", PAD, -y)
    y = y + 8

    local total, _, caught = self:SessionSummary(false)
    local _, missed = self:CastSummary()
    local rate = self:SessionRate()
    local session = { ("%d caught"):format(caught) }
    if rate then session[#session + 1] = ("%.0f/hr"):format(rate) end
    if self:SessionLength() > 0 then session[#session + 1] = self.Duration(self:SessionLength()) end
    bar.session:ClearAllPoints()
    bar.session:SetPoint("TOPLEFT", PAD, -y)
    bar.session:SetText(table.concat(session, "   \194\183   "))
    y = y + 16

    local lines = {}
    for _, entry in ipairs(self:RecentCatches(4)) do
        if entry.missed then
            lines[#lines + 1] = "|cff9d9d9dnothing|r  " .. self.Since(entry.time)
        else
            lines[#lines + 1] = (self.LinkName(entry.link) or "?")
                .. ((entry.quantity or 1) > 1 and (" x" .. entry.quantity) or "")
                .. "  " .. self.Since(entry.time)
        end
    end
    bar.recent:ClearAllPoints()
    bar.recent:SetPoint("TOPLEFT", PAD, -y)
    bar.recent:SetText(#lines > 0 and table.concat(lines, "\n") or "Nothing yet this session.")
    y = y + math.max(14, bar.recent:GetStringHeight())

    bar:SetHeight(y + PAD)
end

function Fishing:UpdateBar()
    if not bar then return end
    local wanted = self:Get("bar") and self:HasPole()
    if self.barForced then wanted = true end
    if wanted ~= bar:IsShown() then bar:SetShown(wanted) end
    self:RefreshBar()
end

-- Opens the window even without a pole, so the record can be read anywhere.
function Fishing:ToggleBar()
    if not bar then return end
    self.barForced = not bar:IsShown()
    if self.barForced then self:Set("bar", true) end
    self:UpdateBar()
end

function Fishing:SetupBar()
    self:CreateBar()
    local ticker = CreateFrame("Frame")
    local elapsed = 0
    ticker:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < 1 then return end
        elapsed = 0
        if bar:IsShown() then self:RefreshBar() end
    end)
    for _, event in ipairs({ "CATCHES_CHANGED", "GEAR_CHANGED", "CASTING_CHANGED" }) do
        self:On(event, function() self:UpdateBar() end)
    end
    self:On("SETTING_CHANGED", function(key)
        if key == "bar" then
            if not self:Get("bar") then self.barForced = nil end
            self:UpdateBar()
        end
    end)
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
    events:RegisterEvent("BAG_UPDATE_DELAYED")
    events:SetScript("OnEvent", function() self:UpdateBar() end)
    self:UpdateBar()
end
