local _, ns = ...
local Guarded = ns.Guarded or function(fn) return fn end -- each error once, not every frame (Diagnostics.lua)
-- The small window that appears while you are holding a pole: lures, fishing
-- food, what your skill is made of, the last thing you landed and everything
-- the session has given so far.
local Fishing = ns.Fishing
local T = ns.Theme

local WIDTH, PAD = 232, 12
local ICON = 30
local ROW, ROW_ICON, ROW_NUMBER = 16, 14, 40
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local bar, lureButtons, foodButton

-- The colour written into an item's link, in either of the game's two forms.
local function QualityColor(link)
    local quality = link and tonumber(link:match("|cnIQ(%d+):"))
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color and color.r then return { color.r, color.g, color.b, 1 } end
    return T:QualityColor(link)
end

-- One line of the catch list: an icon, a name that is cut short rather than
-- wrapped, and a number at the right edge.
local function CatchRow()
    local row = {}
    row.icon = bar:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_ICON, ROW_ICON)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.name = T:Text(bar, "", "GameFontHighlightSmall", WIDTH - PAD * 2 - ROW_ICON - 4 - ROW_NUMBER, T.TEXT)
    row.name:SetWordWrap(false)
    row.number = T:Text(bar, "", "GameFontHighlightSmall", ROW_NUMBER, T.TEXT)
    row.number:SetJustifyH("RIGHT")
    return row
end

-- Without an icon the name still starts where the others do.
local function ShowRow(row, y, icon, name, color, number)
    row.icon:ClearAllPoints()
    row.icon:SetPoint("TOPLEFT", PAD, -y)
    row.icon:SetTexture(icon)
    row.icon:SetShown(icon ~= nil)
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", PAD + ROW_ICON + 4, -(y + 2))
    row.name:SetText(name)
    row.name:SetTextColor(T.Color(color))
    row.name:Show()
    row.number:ClearAllPoints()
    row.number:SetPoint("TOPRIGHT", -PAD, -(y + 2))
    row.number:SetText(number)
    row.number:Show()
end

local function HideRow(row)
    row.icon:Hide()
    row.name:Hide()
    row.number:Hide()
end

local function CatchIcon(catch)
    return catch.icon or Fishing.GetItemIcon(catch.itemID) or QUESTION
end

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
    bar.empty = T:Text(bar, "Nothing yet this session.", "GameFontDisableSmall", WIDTH - PAD * 2, T.MUTED)
    bar.lastLabel = T:Text(bar, "LAST CATCH", "GameFontDisableSmall", 110, T.GOLD_SOFT)
    bar.lastAgo = T:Text(bar, "", "GameFontDisableSmall", 90, T.MUTED)
    bar.lastAgo:SetJustifyH("RIGHT")
    bar.last = CatchRow()
    bar.tallyLabel = T:Text(bar, "CAUGHT THIS SESSION", "GameFontDisableSmall", WIDTH - PAD * 2, T.GOLD_SOFT)
    bar.rows = {}
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
    -- combat the row is simply left as it was -- and so is everything that
    -- depends on it. Counting it afresh found no buttons during a fight: the
    -- label said there were no lures and the session lines moved up over them.
    local x, shown = 0, bar.lureCount or 0
    if not combat then
        shown = 0
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
        bar.lureCount = shown
        local food = self:BestFood()
        bar.hasFood = food ~= nil
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
    local hasButtons = shown > 0 or bar.hasFood == true
    local y = hasButtons and (104 + ICON + 10) or 112
    bar.rule:ClearAllPoints()
    bar.rule:SetPoint("TOPLEFT", PAD, -y)
    y = y + 8

    local _, kinds, caught = self:SessionSummary(false)
    local landed, empty = self:SessionCasts()
    local rate = self:SessionRate()
    local session = { ("%d caught"):format(caught) }
    if self:Get("statsIncludeMissed") and empty > 0 then
        session[#session + 1] = ("%d empty"):format(empty)
        -- The share of casts, not of fish: one cast can land a stack, and
        -- counting each fish made three from one cast look like three hits.
        session[#session + 1] = ("%.0f%% hit"):format(landed / (landed + empty) * 100)
    end
    if rate then session[#session + 1] = ("%.0f/hr"):format(rate) end
    if self:SessionLength() > 0 then session[#session + 1] = self.Duration(self:SessionLength()) end
    bar.session:ClearAllPoints()
    bar.session:SetPoint("TOPLEFT", PAD, -y)
    bar.session:SetText(table.concat(session, "  \194\183  "))
    -- Empty casts can push the line onto a second row.
    y = y + math.max(12, bar.session:GetStringHeight()) + 4

    -- The last thing landed, then the session's whole catch, most caught
    -- first. Empty casts are on the line above and nowhere below it.
    local last = self:LastCatch()
    bar.empty:SetShown(not last)
    bar.lastLabel:SetShown(last ~= nil)
    bar.lastAgo:SetShown(last ~= nil)
    bar.tallyLabel:SetShown(last ~= nil)
    local used = 0
    if last then
        y = y + 2
        bar.lastLabel:ClearAllPoints()
        bar.lastLabel:SetPoint("TOPLEFT", PAD, -y)
        bar.lastAgo:ClearAllPoints()
        bar.lastAgo:SetPoint("TOPRIGHT", -PAD, -y)
        bar.lastAgo:SetText(self.Since(last.time))
        y = y + 14
        local quantity = last.quantity or 1
        ShowRow(bar.last, y, CatchIcon(last), self.LinkName(last.link) or "?", QualityColor(last.link),
            quantity > 1 and ("x" .. quantity) or "")
        y = y + ROW + 6

        bar.tallyLabel:ClearAllPoints()
        bar.tallyLabel:SetPoint("TOPLEFT", PAD, -y)
        y = y + 14
        -- A long session lands more kinds than the window has room for: the
        -- rarest share the last row.
        local limit = self.SESSION_ROWS
        local listed = #kinds > limit and limit - 1 or #kinds
        for index = 1, listed do
            local kind = kinds[index]
            bar.rows[index] = bar.rows[index] or CatchRow()
            ShowRow(bar.rows[index], y, CatchIcon(kind), kind.name or "?", QualityColor(kind.link), kind.count)
            y = y + ROW
        end
        used = listed
        if #kinds > listed then
            local others = 0
            for index = listed + 1, #kinds do others = others + kinds[index].count end
            used = listed + 1
            bar.rows[used] = bar.rows[used] or CatchRow()
            ShowRow(bar.rows[used], y, nil, ("%d others"):format(#kinds - listed), T.MUTED, others)
            y = y + ROW
        end
    else
        HideRow(bar.last)
        bar.empty:ClearAllPoints()
        bar.empty:SetPoint("TOPLEFT", PAD, -y)
        y = y + 14
    end
    for index = used + 1, #bar.rows do HideRow(bar.rows[index]) end

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
    ticker:SetScript("OnUpdate", Guarded(function(_, delta)
        elapsed = elapsed + delta
        if elapsed < 1 then return end
        elapsed = 0
        if bar:IsShown() then self:RefreshBar() end
    end, "Fishing bar"))
    for _, event in ipairs({ "CATCHES_CHANGED", "GEAR_CHANGED", "CASTING_CHANGED" }) do
        self:On(event, function() self:UpdateBar() end)
    end
    self:On("SETTING_CHANGED", function(key)
        if key == "bar" then
            if not self:Get("bar") then self.barForced = nil end
            self:UpdateBar()
        elseif key == "statsIncludeMissed" then
            self:RefreshBar()
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
