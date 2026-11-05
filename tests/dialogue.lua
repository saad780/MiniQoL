local root = ...
local function equal(actual, expected, label)
    assert(actual == expected, (label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local combat, focus, alt, ctrl, shift, gamepad = false, nil, false, false, false, false
local pending, objects = {}, {}
C_Timer = { After = function(_, callback) pending[#pending + 1] = callback end }
local function flush()
    local callbacks = pending; pending = {}
    for _, callback in ipairs(callbacks) do callback() end
end
local methods = {}
function methods:SetScript(key, callback) self.scripts[key] = callback end
function methods:GetScript(key) return self.scripts[key] end
function methods:HookScript(key, callback)
    self.hooks[key] = self.hooks[key] or {}
    table.insert(self.hooks[key], callback)
end
function methods:Fire(key, ...)
    if self.scripts[key] then self.scripts[key](self, ...) end
    for _, callback in ipairs(self.hooks[key] or {}) do callback(self, ...) end
end
function methods:SetShown(value)
    if self.shown == value then return end
    self.shown = value
    self:Fire(value and "OnShow" or "OnHide")
end
function methods:Show() self:SetShown(true) end
function methods:Hide() self:SetShown(false) end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:IsEnabled() return self.enabled end
function methods:IsObjectType(kind) return self.kind == kind end
function methods:SetParent(parent) self.parent = parent end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:GetEffectiveScale() return self.scale or (self.parent and self.parent:GetEffectiveScale()) or 1 end
function methods:GetEffectiveAlpha() return (self.alpha == nil and 1 or self.alpha) * (self.parent and self.parent:GetEffectiveAlpha() or 1) end
function methods:GetTop() return self.top end
function methods:GetBottom() return self.top and self.top - self.height end
function methods:GetLeft() return self.left end
function methods:GetRight() return self.left and self.left + self.width end
function methods:GetFrameLevel() return self.level or 5 end
function methods:SetFrameLevel(level) self.level = level end
function methods:SetFrameStrata(strata) self.strata = strata end
function methods:SetPoint(...) self.point = { ... } end
function methods:ClearAllPoints() self.point = nil end
function methods:EnableKeyboard(value) self.keyboard = value end
function methods:SetPropagateKeyboardInput(value) assert(not combat, "Keyboard propagation changed during combat"); self.propagate = value end
function methods:EnableMouse(value) self.mouse = value end
function methods:SetBackdrop(value) self.backdrop = value end
function methods:SetBackdropColor() end
function methods:SetBackdropBorderColor() end
function methods:SetTextColor() end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:SetText(text) self.textValue = text end
function methods:Click(mouse)
    self.clicks = self.clicks + 1
    self:Fire("OnClick", mouse)
end
local function frame(kind, name, parent)
    local object = setmetatable({ kind = kind, parent = parent, name = name, shown = true,
        enabled = true, width = 280, height = 18, top = 700, left = 30, scripts = {}, hooks = {}, events = {}, clicks = 0 }, { __index = methods })
    objects[#objects + 1] = object
    if name then _G[name] = object end
    return object
end
function CreateFrame(kind, name, parent) return frame(kind, name, parent) end
function methods:CreateFontString() return frame("FontString", nil, self) end
function InCombatLockdown() return combat end
function GetCurrentKeyBoardFocus() return focus end
function IsAltKeyDown() return alt end
function IsControlKeyDown() return ctrl end
function IsShiftKeyDown() return shift end
function UnitName() return "Testplayer" end
InputUtil = { IsGamepadUIEnabled = function() return gamepad end }
function SetOverrideBindingClick() error("Dialogue must not replace global bindings") end
function ClearOverrideBindings() error("Dialogue must not replace global bindings") end
C_AddOns = { GetAddOnMetadata = function() return "test" end }
SlashCmdList = {}
UIParent = frame("Frame", "UIParent")
UIParent.left, UIParent.top, UIParent.width, UIParent.height = 0, 1080, 1920, 1080
GossipFrame = frame("Frame", "GossipFrame", UIParent)
GossipFrame.left, GossipFrame.width, GossipFrame.top = 20, 338, 950
GossipFrame.GreetingPanel = frame("Frame", nil, GossipFrame)
local scroll = frame("Frame", nil, GossipFrame.GreetingPanel)
scroll.top, scroll.height = 800, 300
GossipFrame.GreetingPanel.ScrollBox = scroll
function scroll:GetFrames() return self.rows or {} end
QuestFrame = frame("Frame", "QuestFrame", UIParent)
QuestFrameGreetingPanel = frame("Frame", "QuestFrameGreetingPanel", QuestFrame)
QuestFrameRewardPanel = frame("Frame", "QuestFrameRewardPanel", QuestFrame)
QuestFrameDetailPanel = frame("Frame", "QuestFrameDetailPanel", QuestFrame)
QuestFrameProgressPanel = frame("Frame", "QuestFrameProgressPanel", QuestFrame)
QuestFrameAcceptButton = frame("Button", "QuestFrameAcceptButton", QuestFrameDetailPanel)
QuestFrameCompleteButton = frame("Button", "QuestFrameCompleteButton", QuestFrameProgressPanel)
QuestFrameCompleteQuestButton = frame("Button", "QuestFrameCompleteQuestButton", QuestFrameRewardPanel)
QuestGreetingScrollFrame = frame("Frame", "QuestGreetingScrollFrame", QuestFrameGreetingPanel)
QuestGreetingScrollFrame.top, QuestGreetingScrollFrame.height = 800, 300
QuestInfoFrame = { questLog = false, itemChoice = 0 }
QuestInfoRewardsFrame = frame("Frame", "QuestInfoRewardsFrame", QuestFrameRewardPanel)
local function showQuest(panel)
    GossipFrame:Hide(); QuestFrame:Show()
    for _, f in ipairs({QuestFrameGreetingPanel, QuestFrameRewardPanel, QuestFrameDetailPanel, QuestFrameProgressPanel}) do f:SetShown(f == panel) end
end
GossipFrame:Hide(); QuestFrame:Hide()
local ns = {}
assert(loadfile(root .. "/Core.lua"))("MiniQoL", ns)
ns:Initialize()
assert(loadfile(root .. "/Dialogue.lua"))("MiniQoL", ns)
local D = ns.Dialogue
D:Initialize(); flush()
equal(D.input:GetScript("OnKeyDown"), nil, "no handler outside NPC windows")
local function press(key) D:KeyDown(key); D:KeyUp(key); flush() end
local function row(parent, top, id)
    local button = frame("Button", nil, parent)
    button.top, button.id = top, id
    button.Icon = { texture = "third-party quest icon" }
    button.textValue = "|Tthird-party-icon:16|t Quest title"
    button:SetScript("OnClick", function(self) self.clickedID = self.id end)
    return button
end

-- Number the on-screen order, not opaque quest/option IDs or pool allocation order.
local a, b = row(scroll, 760, 9007), row(scroll, 720, 23)
local title = frame("Frame", nil, scroll)
local hidden, disabled, clipped = row(scroll, 730, 4), row(scroll, 710, 5), row(scroll, 810, 6)
hidden:Hide(); disabled.enabled = false
scroll.rows = { b, title, hidden, clipped, disabled, a }
local originalClick = a:GetScript("OnClick")
local thirdPartyClicks = 0
a:HookScript("OnClick", function() thirdPartyClicks = thirdPartyClicks + 1 end)
GossipFrame:Show(); flush()
equal(D.targets["1"], a, "first visible option")
equal(D.targets["2"], b)
equal(D.targets["3"], nil, "omit titles, clipped, disabled and hidden rows")
equal(a:GetScript("OnClick"), originalClick, "retain original click handler")
equal(a.Icon.texture, "third-party quest icon", "retain icon")
equal(a.textValue, "|Tthird-party-icon:16|t Quest title", "retain inline markers")
equal(D.badges["1"].point[4], GossipFrame.left + GossipFrame.width + 5, "hints use a separate outer rail")
press("1")
equal(a.clickedID, 9007, "native opaque ID used")
equal(thirdPartyClicks, 1, "native post-click hook retained")
press("NUMPAD2"); equal(b.clickedID, 23, "numpad alias")
equal(D.input.propagate, true, "key-up restores propagation")
D:KeyDown("W"); equal(D.input.propagate, true, "movement passes through")
ctrl = true; press("1"); ctrl = false
alt = true; press("1"); alt = false
shift = true; press("1"); shift = false
equal(a.clicks, 1, "modified keys are not captured")

-- Recycled rows are resolved again when the key is pressed.
a.top, b.top, b.id = 710, 760, 991
press("1"); equal(b.clickedID, 991, "recycled row uses its current ID and position")
D:KeyDown("1"); D:KeyDown("1")
equal(b.clicks, 3, "held key acts once")
D:KeyUp("1"); flush()

-- Chat/text inputs, confirmations, gamepad mode and combat retain their controls.
focus = {}; D:Refresh()
equal(D.input:GetScript("OnKeyDown"), nil, "typing removes keyboard handler")
equal(D.input.keyboard, false)
focus = nil; D.observer:GetScript("OnUpdate")(D.observer, 0.11)
equal(D.active, true, "resume after typing")
StaticPopup1 = frame("Frame", "StaticPopup1", UIParent)
D:Refresh(); equal(D.active, false, "confirmation blocks hotkeys")
StaticPopup1:Hide(); D:Refresh()
gamepad = true; D:Refresh(); equal(D.active, false, "defer to gamepad")
gamepad = false; D:Refresh()
SettingsPanel = frame("Frame", "SettingsPanel", UIParent)
D:Refresh(); equal(D.active, false, "settings panels take precedence")
SettingsPanel:Hide(); D:Refresh()
GossipFrame.alpha = 0; D:Refresh(); equal(D.active, false, "invisible native window does not capture keys")
GossipFrame.alpha = 1; D.observer:GetScript("OnUpdate")(D.observer, 0.11)
equal(D.active, true, "resume when native fade becomes visible")
combat = true; D.observer:GetScript("OnEvent")(D.observer, "PLAYER_REGEN_DISABLED")
equal(D.input:GetScript("OnKeyDown"), nil, "combat removes handler without propagation writes")
combat = false; D.observer:GetScript("OnEvent")(D.observer, "PLAYER_REGEN_ENABLED"); flush()
equal(D.active, true)

-- More than nine options: zero selects the tenth; the eleventh remains a mouse option.
scroll.rows = {}
for i = 1, 11 do scroll.rows[i] = row(scroll, 790 - i * 20, 1000 + i) end
D:Refresh(); press("0")
equal(scroll.rows[10].clickedID, 1010)
equal(D.targets["11"], nil)
GossipFrame.left = 1600; D:Refresh()
equal(D.badges["1"].point[4], 1579, "hint rail moves left at the screen edge")
GossipFrame.left = 20
ns.db.dialogue.hints = false; D:Refresh()
for _, badge in pairs(D.badges) do equal(badge:IsShown(), false, "hints can be hidden independently") end
press("1"); equal(scroll.rows[1].clicks, 1, "keys work without hints")
ns.db.dialogue.hints = true

-- QUEST_GREETING uses the active pool, which may enumerate out of order.
showQuest(QuestFrameGreetingPanel)
local greeting1, greeting2 = row(QuestFrameGreetingPanel, 760, 12), row(QuestFrameGreetingPanel, 720, 1)
local pool = { [greeting2] = true, [greeting1] = true }
QuestFrameGreetingPanel.titleButtonPool = { EnumerateActive = function() return pairs(pool) end }
D:Refresh(); equal(D.targets["1"], greeting1)
press("2"); equal(greeting2.clickedID, 1)

-- Rewards only select choices. Value labels and upgrade/coin markers are preserved.
showQuest(QuestFrameRewardPanel)
local reward1, reward2 = row(QuestInfoRewardsFrame, 730, 1), row(QuestInfoRewardsFrame, 730, 2)
reward1.left, reward2.left = 30, 190
reward1.type, reward2.type = "choice", "choice"
reward1.objectType, reward2.objectType = "item", "item"
reward1.AHledgerValue, reward1.GearwiseArrow = { text = "best value" }, { shown = true }
for _, button in ipairs({reward1, reward2}) do button:SetScript("OnClick", function(self) QuestInfoFrame.itemChoice = self.id end) end
local guaranteed = row(QuestInfoRewardsFrame, 760, 9); guaranteed.type = "reward"
QuestInfoRewardsFrame.RewardButtons = { guaranteed, reward2, reward1 }
local handins = 0
QuestFrameCompleteQuestButton:SetScript("OnClick", function() if QuestInfoFrame.itemChoice > 0 then handins = handins + 1 end end)
D:Refresh(); equal(D.targets["1"], reward1)
press("2"); equal(QuestInfoFrame.itemChoice, 2)
equal(handins, 0, "choosing an item does not turn in the quest")
equal(reward1.AHledgerValue.text, "best value"); equal(reward1.GearwiseArrow.shown, true)
equal(D.badges["1"].point[1], "BOTTOMRIGHT", "reward key avoids icon and above-item labels")
press("SPACE"); equal(handins, 1, "separate action completes selected reward")
QuestInfoFrame.questLog = true; D:Refresh(); equal(D.active, false, "quest log rewards are untouched")
QuestInfoFrame.questLog = false
D.observer:GetScript("OnUpdate")(D.observer, 0.11)
equal(D.active, true, "resume when NPC reward context returns")

-- Accept/progress actions use enabled native buttons. A held Space cannot chain actions.
showQuest(QuestFrameDetailPanel)
QuestFrameAcceptButton:SetScript("OnClick", function() showQuest(QuestFrameProgressPanel) end)
local progresses = 0
QuestFrameCompleteButton:SetScript("OnClick", function() progresses = progresses + 1 end)
D:Refresh(); D:KeyDown("SPACE"); flush(); D:KeyDown("SPACE")
equal(QuestFrameAcceptButton.clicks, 1); equal(progresses, 0, "no chained actions from held Space")
D:KeyUp("SPACE"); press("SPACE"); equal(progresses, 1)
QuestFrameCompleteButton.enabled = false; D:Refresh()
equal(D.primary, nil, "disabled progress action is not a target")
QuestFrameCompleteButton.enabled = true
ns.db.dialogue.advance = false; D:Refresh()
equal(D.primary, nil, "Space can be disabled independently")

-- Closing/disabling releases every keyboard script; repeated refreshes reuse hints.
GossipFrame:Show(); QuestFrame:Hide(); D:Refresh()
local objectCount = #objects
for i = 1, 20 do D:Refresh() end
equal(#objects, objectCount, "hint widgets are reused")
ns.db.dialogue.enabled = false; D:Refresh()
equal(D.input:GetScript("OnKeyDown"), nil)
ns:Initialize(); equal(ns.db.dialogue.enabled, false, "preserve user preference")
ns.db.dialogue.enabled = true; D:Refresh()
GossipFrame:Hide(); flush()
equal(D.input:GetScript("OnKeyDown"), nil, "close releases keys")
equal(D.observer:GetScript("OnUpdate"), nil, "no idle polling outside dialogue")
print("NPC dialogue choices, rewards, integration markers, typing, combat, confirmations and held-key guards passed")
