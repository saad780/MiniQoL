local shell = ...
local function noop() end
local frames, timers, events, mouse

function CreateFrame(_, _, parent)
    local frame = { parent = parent, visible = true, hooks = {} }
    frames[#frames + 1] = frame
    function frame:GetParent() return self.parent end
    function frame:SetParent(value) self.parent = value end
    function frame:IsVisible() return self.visible and (not self.parent or self.parent:IsVisible()) end
    function frame:IsShown() return self.visible end
    function frame:SetShown(value) self.visible = value end
    function frame:Show() self:SetShown(true) end
    function frame:Hide() self:SetShown(false) end
    function frame:GetWidth() return 300 end
    function frame:GetHeight() return 200 end
    function frame:GetFrameLevel() return 1 end
    function frame:SetText(value) self.text = value end
    function frame:RegisterEvent(event) events[event] = self end
    function frame:SetScript(name, fn) self.hooks[name] = fn end
    frame.HookScript = frame.SetScript
    frame.CreateTexture = function() return CreateFrame("Texture", nil, frame) end
    frame.CreateFontString = frame.CreateTexture
    frame.IsForbidden, frame.GetName = noop, noop
    frame.SetSize, frame.SetClampedToScreen, frame.SetAtlas = noop, noop, noop
    frame.SetPoint, frame.ClearAllPoints, frame.SetFrameLevel = noop, noop, noop
    frame.SetFont, frame.SetTextColor = noop, noop
    return frame
end

function hooksecurefunc(target, method, callback)
    local original = target[method]
    target[method] = function(...) original(...); callback(...) end
end

C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
function GetMouseFoci() return mouse end
function GetBindingAction() return "" end
GetBindingKey, SetOverrideBinding, ClearOverrideBindings = noop, noop, noop
InCombatLockdown, GetCurrentKeyBoardFocus, GetCursorInfo = noop, noop, noop
function UnitName() return "Main" end
function GetNormalizedRealmName() return "Realm" end
function strtrim(text) return text:match("^%s*(.-)%s*$") end
strlower = string.lower
Enum = { BagIndex = { ReagentBag = 5 }, ItemClass = { Questitem = 12 } }

local function Fire(event)
    events[event].hooks.OnEvent(events[event], event)
end

local function Flush()
    while #timers > 0 do table.remove(timers, 1)() end
end

local function Load(provider)
    Baganator, Bagnon, ContainerFrameCombinedBags = nil, nil, nil
    ContainerFrameUtil_EnumerateContainerFrames = nil
    BaganatorAltMailGroups, BaganatorAltMailRoutes = nil, nil
    frames, timers, events, mouse = {}, {}, {}, {}
    UIParent = CreateFrame("Frame")
    local inventory = CreateFrame("Frame", nil, UIParent)
    inventory.GetBagID = function() return 0 end
    local first = CreateFrame("Button", nil, inventory)
    local second = CreateFrame("Button", nil, inventory)
    first.GetID = function() return 1 end
    second.GetID = function() return 2 end
    if provider == "stock" then
        first.GetBagID, second.GetBagID = inventory.GetBagID, inventory.GetBagID
        inventory.EnumerateValidItems = function() return ipairs({ first, second }) end
        ContainerFrameUtil_EnumerateContainerFrames = function() return ipairs({ inventory }) end
    else
        first.GetBag, second.GetBag = inventory.GetBagID, inventory.GetBagID
        function inventory:IsCached() return self.cached end
        inventory.Layout = noop
        inventory.ItemGroup = { buttons = { first, second } }
        Bagnon = { Frames = { Get = function(_, id)
            assert(id == "inventory")
            return inventory
        end } }
    end

    local items = {
        { itemID = 100, hyperlink = "item:100", stackCount = 20, isBound = false, guid = "Item-first" },
        { itemID = 100, hyperlink = "item:100", stackCount = 20, isBound = false, guid = "Item-second" },
    }
    C_Container = {
        GetContainerItemInfo = function(_, slot) return items[slot] end,
        GetContainerItemID = function(_, slot) return items[slot] and items[slot].itemID end,
        GetContainerItemQuestInfo = noop,
    }
    C_Item = {
        GetItemInfoInstant = function() return nil, nil, nil, nil, nil, 7 end,
        GetItemGUID = function(location) return items[location.slot].guid end,
    }
    ItemLocation = { CreateEmpty = function()
        return { SetBagAndSlot = function(self, _, slot) self.slot = slot end }
    end }

    local ns = { Print = noop }
    assert(loadfile(shell .. "/AltMail/Categories.lua"))("MiniQoL", ns)
    local addon = ns.AltMail
    addon.TogglePanel, addon.RefreshMailControls, addon.RefreshMarks = noop, noop, noop
    addon.IsSending = noop
    addon.SaveRoute(nil, addon.GetGroup(1), "Other", true)
    assert(loadfile(shell .. "/AltMail/Backpack.lua"))("MiniQoL", ns)
    Fire("PLAYER_LOGIN")
    Flush()

    local launcher
    for _, frame in ipairs(frames) do
        if frame.tooltipHeader == "Alt Mail" then launcher = frame end
    end
    assert(launcher and launcher:GetParent() == inventory and launcher:IsVisible())
    mouse = { first }
    addon.MarkHovered(1)
    Flush()
    assert(addon.GetMark("Item-first").slot == 1 and not addon.GetMark("Item-second"))

    local function CheckBadge(button, shown)
        for _, frame in ipairs(frames) do
            if frame.itemButton == button then return assert(frame:IsShown() == shown) end
        end
        assert(not shown)
    end
    CheckBadge(first, true)
    CheckBadge(second, false)
    items[1], items[2] = items[2], items[1]
    Fire("BAG_UPDATE_DELAYED")
    Flush()
    CheckBadge(first, false)
    CheckBadge(second, true)

    if provider == "bagnon" then
        inventory.cached = true
        inventory:Layout()
        Flush()
        CheckBadge(second, false)
        mouse = { second }
        addon.MarkHovered(1)
        assert(addon.GetMark("Item-first"), "a cached character changed a live bag mark")
    end
end

Load("stock")
Load("bagnon")
print("Alt Mail: stock and Bagnon work with Baganator absent, with a single stack badge and cached bags excluded")

local playerName, realm
function GetRealmName() return realm end
local function SetupRecovery(profiles)
    local ns = { Print = noop, Mail = { PlayerName = function() return playerName end },
        altMailLegacyProfiles = profiles }
    assert(loadfile(shell .. "/AltMail/Categories.lua"))("MiniQoL", ns)
    ns.AltMail.RefreshItemBadges = noop
    return ns.AltMail
end

local reads = 0
local numericProfile = { name = "First-Last", read = function()
    reads = reads + 1
    return {
        settings = {
            [1] = { name = "Cloth", recipient = "Other Alt", automatic = true },
            [2] = { name = "Mail Group 2", recipient = "Bank Alt" },
        },
        stackMarks = { ["Item-legacy"] = { slot = 1, itemID = 100 } },
    }, { DEFAULT = { ["2"] = { name = "Legacy", recipient = "Other Alt" } } }
end }
local profiles = { numericProfile }
BaganatorAltMailGroups, BaganatorAltMailRoutes = nil, nil
local addon = SetupRecovery(profiles)
addon.RestoreLegacySettings() -- Identity is unavailable while the addon loads.
assert(reads == 0)
playerName, realm = "First Other", ""
addon.RestoreLegacySettings()
assert(reads == 0)
playerName = "First Last"
addon.RestoreLegacySettings()
assert(reads == 1 and addon.GetGroup(1).name == "Cloth" and addon.GetGroup(1).label == "Cloth")
assert(addon.GetGroup(2).name == "Bank Alt" and addon.GetGroup(2).label == "", "legacy placeholders follow the recipient")
assert(addon.GetRoute(nil, addon.GetGroup(1)).automatic)
assert(addon.GetMark("Item-legacy").slot == 1)
assert(addon.GetRoute("DEFAULT", { id = "2", name = "Legacy" }).recipient == "Other Alt")

-- A later UI session reads the persisted MiniQoL groups and never reapplies a
-- retired snapshot over a recipient or mark the player deliberately cleared.
addon.SaveRoute(nil, addon.GetGroup(1), nil, false)
assert(addon.GetGroup(1).name == "Cloth", "unlinking preserves a custom label")
addon.ClearMark("Item-legacy")
addon = SetupRecovery(profiles)
addon.RestoreLegacySettings()
assert(reads == 1 and not addon.GetRoute(nil, addon.GetGroup(1)) and not addon.GetMark("Item-legacy"))

BaganatorAltMailGroups, BaganatorAltMailRoutes = nil, nil
addon = SetupRecovery(profiles)
addon.SaveRoute(nil, addon.GetGroup(1), "New Alt", false)
addon.RestoreLegacySettings()
assert(reads == 2 and addon.GetRoute(nil, addon.GetGroup(1)).recipient == "New Alt")

BaganatorAltMailGroups, BaganatorAltMailRoutes = nil, nil
addon = SetupRecovery({ numericProfile, numericProfile })
addon.RestoreLegacySettings()
assert(reads == 2 and not addon.GetRoute(nil, addon.GetGroup(1)))
print("Alt Mail recovery: full names and numeric realm folders, existing settings preserved, recovery runs once")
