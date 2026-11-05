-- Lightweight keyboard access to Blizzard's NPC windows. Native buttons keep
-- their text, artwork, tooltips and OnClick handlers (including addon hooks).
local _, ns = ...
local D = { targets = {}, badges = {}, held = {}, hooked = {}, elapsed = 0 }
ns.Dialogue = D

local function readable(value)
    return not (issecretvalue and issecretvalue(value)) and not (canaccessvalue and not canaccessvalue(value))
end

local function visible(frame)
    return frame and frame.IsVisible and frame:IsVisible()
end

local function clickable(button)
    if not visible(button) or not button.Click or (button.IsEnabled and not button:IsEnabled()) then return false end
    if button.GetEffectiveAlpha then
        local alpha = button:GetEffectiveAlpha()
        if not readable(alpha) or type(alpha) ~= "number" or alpha <= 0 then return false end
    end
    return true
end

local function geometry(frame, method)
    if not frame or not frame[method] then return nil end
    local value = frame[method](frame)
    if not readable(value) or type(value) ~= "number" then return nil end
    return value * (frame.GetEffectiveScale and frame:GetEffectiveScale() or 1)
end

local function within(button, viewport)
    if not visible(button) then return false end
    if not viewport then return true end
    local top, bottom = geometry(button, "GetTop"), geometry(button, "GetBottom")
    local limitTop, limitBottom = geometry(viewport, "GetTop"), geometry(viewport, "GetBottom")
    return not (top and bottom and limitTop and limitBottom)
        or (top <= limitTop + 1 and bottom >= limitBottom - 1)
end

function D:Settings()
    return ns.db and ns.db.dialogue
end

function D:Blocked(root)
    if InCombatLockdown and InCombatLockdown() then return true end
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focus then return true end
    for _, panel in ipairs({ ns.panel or false, GameMenuFrame or false, SettingsPanel or false,
        InterfaceOptionsFrame or false, ColorPickerFrame or false, WorldMapFrame or false }) do
        if panel and visible(panel) then return true end
    end
    if root and root.GetEffectiveAlpha then
        local alpha = root:GetEffectiveAlpha()
        if not readable(alpha) or type(alpha) ~= "number" or alpha <= 0 then return true end
    end
    if InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() then return true end
    for index = 1, STATICPOPUP_NUMDIALOGS or 4 do
        if visible(_G["StaticPopup" .. index]) then return true end
    end
    return false
end

function D:Context()
    if visible(GossipFrame) then
        local panel = GossipFrame.GreetingPanel
        return "gossip", GossipFrame, panel and panel.ScrollBox or GossipFrame.ScrollBox
    end
    if not visible(QuestFrame) then return end
    if visible(QuestFrameRewardPanel) then
        return "rewards", QuestFrame
    elseif visible(QuestFrameGreetingPanel) then
        return "greeting", QuestFrame, QuestGreetingScrollFrame
    elseif visible(QuestFrameDetailPanel) then
        return "detail", QuestFrame
    elseif visible(QuestFrameProgressPanel) then
        return "progress", QuestFrame
    end
end

function D:Collect(kind, viewport)
    local rows, seen = {}, {}
    local function add(button)
        if not button or seen[button] or not clickable(button) or not within(button, viewport) then return end
        if button.IsObjectType and not button:IsObjectType("Button") then return end
        seen[button] = true
        rows[#rows + 1] = { button = button, order = #rows + 1,
            top = geometry(button, "GetTop"), left = geometry(button, "GetLeft") }
    end
    if kind == "gossip" then
        if viewport and viewport.GetFrames then
            for _, button in ipairs(viewport:GetFrames() or {}) do add(button) end
        else
            for index = 1, 32 do add(_G["GossipTitleButton" .. index]) end
        end
    elseif kind == "greeting" then
        local pool = QuestFrameGreetingPanel and QuestFrameGreetingPanel.titleButtonPool
        if pool and pool.EnumerateActive then
            for button in pool:EnumerateActive() do add(button) end
        else
            for index = 1, 32 do add(_G["QuestTitleButton" .. index]) end
        end
    elseif kind == "rewards" then
        for _, button in ipairs(QuestInfoRewardsFrame and QuestInfoRewardsFrame.RewardButtons or {}) do
            if button.type == "choice" and (not button.objectType or button.objectType == "item") then add(button) end
        end
    end
    table.sort(rows, function(a, b)
        if a.top and b.top and math.abs(a.top - b.top) > 3 then return a.top > b.top end
        if a.left and b.left and math.abs(a.left - b.left) > 3 then return a.left < b.left end
        return a.order < b.order
    end)
    return rows
end

function D:Primary(kind)
    if kind == "detail" then return QuestFrameAcceptButton end
    if kind == "progress" then return QuestFrameCompleteButton end
    if kind == "rewards" then return QuestFrameCompleteQuestButton end
end

function D:HideHints()
    for _, badge in pairs(self.badges) do badge:Hide() end
end

function D:Badge(id, button, root, kind, label)
    local badge = self.badges[id]
    if not badge then
        badge = CreateFrame("Frame", nil, root, "BackdropTemplate")
        badge:EnableMouse(false)
        badge:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        badge:SetBackdropColor(0.07, 0.065, 0.05, 0.92)
        badge:SetBackdropBorderColor(0.65, 0.51, 0.25, 0.7)
        badge.text = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        badge.text:SetPoint("CENTER", 0, 0)
        badge.text:SetTextColor(0.96, 0.83, 0.51)
        self.badges[id] = badge
    end
    badge:SetParent(root)
    badge:SetFrameLevel(root:GetFrameLevel() + 20)
    badge:SetSize(id == "primary" and 42 or 16, 16)
    badge:ClearAllPoints()
    if id == "primary" then
        badge:SetPoint("TOP", button, "BOTTOM", 0, -2)
    elseif kind == "rewards" then
        -- Leave the item icon, upgrade arrow and above-item value markers free.
        badge:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 2)
    else
        -- An outer rail avoids editing quest text or covering inline icons.
        -- Parent it to the window, not to the clipped/recycled ScrollBox row.
        local right, left = geometry(root, "GetRight"), geometry(root, "GetLeft")
        local screenRight = geometry(UIParent, "GetRight")
        local top, bottom = geometry(button, "GetTop"), geometry(button, "GetBottom")
        if not (right and left and top and bottom) then badge:Hide(); return end
        local scale = root:GetEffectiveScale()
        local railX = right + 5 * scale
        if screenRight and railX + 16 * scale > screenRight then railX = left - 21 * scale end
        badge:SetPoint("LEFT", UIParent, "BOTTOMLEFT", railX / scale, (top + bottom) / (2 * scale))
    end
    badge.text:SetText(label)
    badge:Show()
end

function D:Suspend()
    -- Forever can dispatch keys to any frame retaining an OnKeyDown script.
    -- Remove the scripts as well as disabling the keyboard outside NPC use.
    self.active = false
    self.input:SetScript("OnKeyDown", nil)
    self.input:SetScript("OnKeyUp", nil)
    self.input:EnableKeyboard(false)
    self.input:Hide()
    if not (InCombatLockdown and InCombatLockdown()) then self.input:SetPropagateKeyboardInput(true) end
    self.held = {}
    self:HideHints()
end

function D:Refresh()
    if not self.input then return end
    self:HookWindows()
    self:HideHints()
    self.targets, self.primary = {}, nil
    local settings = self:Settings()
    local kind, root, viewport = self:Context()
    if not settings or not settings.enabled or not root then
        self:Suspend()
        self.observer:SetScript("OnUpdate", nil)
        return
    end
    self.observer:SetScript("OnUpdate", self.poll)
    if self:Blocked(root) then self:Suspend(); return end
    if kind == "rewards" and QuestInfoFrame and QuestInfoFrame.questLog then self:Suspend(); return end
    self.root, self.kind = root, kind
    for index, row in ipairs(self:Collect(kind, viewport)) do
        if index > 10 then break end
        local key = tostring(index % 10)
        self.targets[key] = row.button
        if settings.hints then self:Badge(key, row.button, root, kind, key) end
    end
    local primary = settings.advance and self:Primary(kind)
    if clickable(primary) then
        self.primary = primary
        if settings.hints then self:Badge("primary", primary, root, kind, "Space") end
    end
    if not next(self.targets) and not self.primary then self:Suspend(); return end
    if not self.active then
        self.input:SetPropagateKeyboardInput(true)
        self.input:SetScript("OnKeyDown", function(_, key) self:KeyDown(key) end)
        self.input:SetScript("OnKeyUp", function(_, key) self:KeyUp(key) end)
        self.input:EnableKeyboard(true)
        self.input:Show()
        self.active = true
    end
end

function D:KeyDown(key)
    if InCombatLockdown and InCombatLockdown() then self:Suspend(); return end
    self.input:SetPropagateKeyboardInput(true)
    if not self.active or self:Blocked(self.root) then self:Refresh(); return end
    if (IsAltKeyDown and IsAltKeyDown()) or (IsControlKeyDown and IsControlKeyDown()) or (IsShiftKeyDown and IsShiftKeyDown()) then return end
    local normalized = key:match("^NUMPAD(%d)$") or key
    if normalized ~= "SPACE" and not normalized:match("^%d$") then return end
    self:Refresh() -- Resolve pooled/recycled buttons at the instant of the key press.
    if not self.active then return end
    local target = normalized == "SPACE" and self.primary or self.targets[normalized]
    if not target and not self.held[key] then return end
    self.input:SetPropagateKeyboardInput(false)
    if self.held[key] then return end
    if not clickable(target) then return end
    self.held[key] = true
    -- This selects the existing reward button; completing the quest requires
    -- a separate action. Native confirmations and other addons' hooks still run.
    target:Click("LeftButton")
    self:RequestRefresh()
end

function D:KeyUp(key)
    self.held[key] = nil
    if not (InCombatLockdown and InCombatLockdown()) then self.input:SetPropagateKeyboardInput(true) end
end

function D:RequestRefresh()
    if self.queued then return end
    self.queued = true
    C_Timer.After(0, function() self.queued = false; self:Refresh() end)
end

function D:HookWindows()
    for _, frame in ipairs({ GossipFrame or false, QuestFrame or false }) do
        if frame and not self.hooked[frame] then
            self.hooked[frame] = true
            frame:HookScript("OnShow", function() self:RequestRefresh() end)
            frame:HookScript("OnHide", function() self:RequestRefresh() end)
        end
    end
end

function D:Initialize()
    if self.observer then return end
    self.input = CreateFrame("Frame", "MiniQoLDialogueKeys", UIParent)
    self.input:SetFrameStrata("DIALOG")
    self.input:SetSize(1, 1)
    self.input:SetPoint("CENTER")
    self.observer = CreateFrame("Frame")
    self.poll = function(_, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed >= 0.1 then self.elapsed = 0; self:Refresh() end
    end
    for _, event in ipairs({ "GOSSIP_SHOW", "GOSSIP_CLOSED", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS",
        "QUEST_COMPLETE", "QUEST_FINISHED", "QUEST_ITEM_UPDATE", "ADDON_LOADED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
        self.observer:RegisterEvent(event)
    end
    self.observer:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then self:Suspend() else self:RequestRefresh() end
    end)
    self:Suspend()
    self:HookWindows()
    self:RequestRefresh()
end
