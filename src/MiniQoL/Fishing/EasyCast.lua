local _, ns = ...
-- Casting without hunting for the button: double right-click the world, or a
-- hotkey, while a pole is in hand. Reeling in is bound to the game's interact
-- key while the line is out.
local Fishing = ns.Fishing

local castButton, hotkey, interact
local lastClick, hotkeyBound, reelInBound, savedInteract = 0, nil, nil, nil
local lureToApply

-- Only a click on a secure button may cast, so the second click of the
-- double-click, and the hotkey, are bound to this one.
local function CreateCastButton()
    local button = CreateFrame("Button", "MiniQoLFishingCastButton", UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("type", "spell")
    button:SetAttribute("spell", Fishing:SpellName())
    -- With auto lure on and nothing on the pole, this click puts a lure on
    -- instead and the next one casts. Attributes only change out of combat,
    -- which is also the only time anything is bound to this button.
    button:SetScript("PreClick", function(self)
        if InCombatLockdown() then return end
        lureToApply = Fishing:Get("autoLure") and not Fishing:LureTimeLeft() and Fishing:BestLure() or nil
        if lureToApply then
            self:SetAttribute("type", "macro")
            self:SetAttribute("macrotext", Fishing:LureMacro(lureToApply))
        else
            self:SetAttribute("type", "spell")
        end
    end)
    button:SetScript("PostClick", function(self)
        if lureToApply then Fishing:WatchLure(lureToApply) end
        if not InCombatLockdown() then ClearOverrideBindings(self) end
    end)
    return button
end

-- The mouse is over the bobber when the game is showing its tooltip. Only the
-- English name is known, so elsewhere casting is simply always allowed.
local BOBBER = "fishing bobber"

local function OverBobber()
    local line = GameTooltip:IsShown() and GameTooltipTextLeft1:GetText()
    return line and line:lower() == BOBBER
end

local function ClearCastBinding()
    if not InCombatLockdown() then ClearOverrideBindings(castButton) end
end

-- SoftTargetInteract: 0 off, 1 gamepad, 2 keyboard and mouse, 3 both.
local INTERACT_ON = "3"

local function BindInteract()
    if not Fishing:Get("reelIn") or InCombatLockdown() then return end
    local current = GetCVar("SoftTargetInteract")
    if (tonumber(current) or 0) < 2 then
        savedInteract = current
        SetCVar("SoftTargetInteract", INTERACT_ON)
    end
    reelInBound = Fishing:Get("reelInKey")
    if reelInBound then SetOverrideBinding(interact, true, reelInBound, "INTERACTTARGET") end
end

local function ClearInteract()
    if InCombatLockdown() then return end
    ClearOverrideBindings(interact)
    reelInBound = nil
    if savedInteract then
        SetCVar("SoftTargetInteract", savedInteract)
        savedInteract = nil
    end
end

function Fishing:UpdateHotkey()
    if InCombatLockdown() or not hotkey then return end
    local key = self:Get("castMode") == "hotkey" and self:HasPole() and self:Get("castKey") or nil
    -- While the line is out that key reels in, so one key can do both.
    if key == reelInBound then key = nil end
    if key == hotkeyBound then return end
    ClearOverrideBindings(hotkey)
    if key then SetOverrideBindingClick(hotkey, true, key, "MiniQoLFishingCastButton") end
    hotkeyBound = key
end

local function ClearHotkey()
    if InCombatLockdown() or not hotkey then return end
    ClearOverrideBindings(hotkey)
    hotkeyBound = nil
end

function Fishing:SetupEasyCast()
    castButton = CreateCastButton()
    hotkey, interact = CreateFrame("Frame"), CreateFrame("Frame")

    WorldFrame:HookScript("OnMouseDown", function(_, mouseButton)
        if mouseButton ~= "RightButton" then return end
        -- Bindings cannot change in combat, and right-clicking a creature
        -- should still target or loot it.
        if self:Get("castMode") ~= "doubleClick" or InCombatLockdown()
            or UnitExists("mouseover") or not self:HasPole() then
            return
        end
        -- While the line is out, right-clicks on the bobber are for looting.
        if UnitChannelInfo("player") == self:SpellName() and OverBobber() then
            lastClick = 0
            return
        end
        local now = GetTime()
        if now - lastClick < self.DOUBLE_CLICK_TIME then
            lastClick = 0
            SetOverrideBindingClick(castButton, true, "BUTTON2", "MiniQoLFishingCastButton")
            -- Used up by this click; never leave it bound for a later one.
            C_Timer.After(self.DOUBLE_CLICK_TIME, ClearCastBinding)
        else
            lastClick = now
        end
    end)

    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
        "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LOGOUT" }) do
        events:RegisterEvent(event)
    end
    events:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
    events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    events:SetScript("OnEvent", function(_, event, _, _, spellID)
        if event == "UNIT_SPELLCAST_CHANNEL_START" then
            if self:IsFishingSpell(spellID) then BindInteract() end
            self:UpdateHotkey()
        elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            ClearInteract()
            self:UpdateHotkey()
        elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "UNIT_INVENTORY_CHANGED"
            or event == "PLAYER_REGEN_ENABLED" then
            self:UpdateHotkey()
            self:Fire("GEAR_CHANGED")
        else
            -- Never leave a binding behind when combat or a loading screen
            -- arrives first; it is bound again afterwards.
            ClearCastBinding()
            ClearInteract()
            ClearHotkey()
            lastClick = 0
            if event == "PLAYER_ENTERING_WORLD" then self:UpdateHotkey() end
        end
    end)

    self:On("SETTING_CHANGED", function(key)
        if key == "castMode" or key == "castKey" then self:UpdateHotkey() end
    end)
    self:UpdateHotkey()
end
