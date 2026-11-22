local _, ns = ...
local addon = ns.AltMail
local owner = CreateFrame("Frame")
local backpackFrames = {}
local externalBadges = setmetatable({}, { __mode = "k" })
local activeBackpack
local bagnonFrames
local updateQueued = false
local mailIcon = "ui-hud-minimap-mail-icon"

local launcher = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
launcher:SetSize(32, 22)
launcher:SetClampedToScreen(true)
launcher.tooltipHeader = "Alt Mail"
launcher.Icon = launcher:CreateTexture(nil, "ARTWORK")
launcher.Icon:SetAtlas(mailIcon)
launcher.Icon:SetSize(19, 15)
launcher.Icon:SetPoint("CENTER")
launcher:SetScript("OnClick", addon.TogglePanel)
launcher:SetScript("OnEnter", function(button)
  GameTooltip:SetOwner(button, "ANCHOR_LEFT")
  GameTooltip:SetText(button.tooltipHeader)
  GameTooltip:Show()
end)
launcher:SetScript("OnLeave", function()
  GameTooltip:Hide()
end)
launcher:Hide()

BINDING_NAME_BAGANATORALTMAIL_MARK1 = "Mark for Mail Group 1"
BINDING_NAME_BAGANATORALTMAIL_MARK2 = "Mark for Mail Group 2"
local suggested = { "CTRL-SHIFT-1", "CTRL-SHIFT-2" }

local function Action(slot)
  return "BAGANATORALTMAIL_MARK" .. slot
end

local function SuggestedKey(slot)
  local key = suggested[slot]
  local action = GetBindingAction(key, true)
  if not action or action == "" or action == Action(slot) then
    return key
  end
end

function addon.GetMarkShortcut(slot)
  local key = GetBindingKey(Action(slot)) or SuggestedKey(slot)
  if key then
    return GetBindingText(key, "KEY_")
  end
end

local function RefreshBindings()
  if InCombatLockdown() then
    return
  end
  ClearOverrideBindings(owner)
  if launcher:IsVisible() then
    for slot = 1, #suggested do
      local key = not GetBindingKey(Action(slot)) and SuggestedKey(slot)
      if key then
        SetOverrideBinding(owner, false, key, Action(slot))
      end
    end
  end
  addon.RefreshMailControls()
end

-- Every frame in the game passes through here, and a frame can carry a GetName
-- of its own in place of the game's: the damage meter's rows answer with their
-- name label. Ask the game's, and trust only a string.
local function IsBaganatorBackpack(frame)
  local methods = (getmetatable(frame) or {}).__index
  local getName = type(methods) == "table" and methods.GetName or frame.GetName
  local name = getName and getName(frame)
  return type(name) == "string" and name:match("^Baganator_%a*BackpackViewFrame") ~= nil
end

local function PositionBaganator(frame)
  local manager = frame.ButtonsManager
  local buttons = manager and manager.active and manager.active.topRight
  local sort = manager and manager.cache and manager.cache.sort
  local anchor = buttons and buttons[#buttons] or frame.CloseButton
  if buttons and sort then
    for index, button in ipairs(buttons) do
      if button == sort then
        anchor = sort
        local neighbor = buttons[index + 1]
        if neighbor then
          local point, relativeTo, relativePoint, x, y = neighbor:GetPoint(1)
          -- Keep the native button chain and reserve space between these two buttons.
          if point == "RIGHT" and relativeTo == sort and relativePoint == "LEFT" and x == 0 then
            neighbor:SetPoint(point, relativeTo, relativePoint, -launcher:GetWidth(), y)
          end
        end
        break
      end
    end
  end

  launcher:ClearAllPoints()
  if anchor and anchor:IsShown() then
    launcher:SetPoint("RIGHT", anchor, "LEFT", 0, 0)
    launcher:SetFrameLevel(anchor:GetFrameLevel())
  else
    launcher:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
  end
end

local function Position(frame, provider)
  if provider == "baganator" then
    PositionBaganator(frame)
    return
  end
  launcher:SetFrameLevel(frame:GetFrameLevel() + 5)
  launcher:ClearAllPoints()
  if provider == "stock" and frame.CloseButton and frame.CloseButton:IsShown() then
    launcher:SetPoint("RIGHT", frame.CloseButton, "LEFT", -2, 0)
  else
    launcher:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -3, 2)
  end
end

local function IsOuterBaganatorBackpack(frame)
  if not IsBaganatorBackpack(frame) then
    return false
  end
  local parent = frame:GetParent()
  while parent and not parent:IsForbidden() do
    if IsBaganatorBackpack(parent) then
      return false
    end
    parent = parent:GetParent()
  end
  return true
end

local function GetVisibleBackpack()
  local best, highest, largest = nil, 0, 0
  for frame, provider in pairs(backpackFrames) do
    local stockBag = provider == "stock" and frame:GetBagID()
    local combined = frame == ContainerFrameCombinedBags
    if frame:IsVisible() and (provider ~= "stock" or combined
      or (type(stockBag) == "number" and stockBag >= 0 and stockBag <= addon.LastBag())) then
      local priority = provider == "baganator" and 4 or provider == "bagnon" and 3 or 1
      if provider == "stock" and (combined or stockBag == 0) then
        priority = 2
      end
      local area = frame:GetWidth() * frame:GetHeight()
      if priority > highest or (priority == highest and (area > largest or (area == largest and frame == activeBackpack))) then
        best, highest, largest = frame, priority, area
      end
    end
  end
  return best
end

local QueueUpdate
local DrawExternalBadges

local function WatchBackpack(frame, provider)
  if backpackFrames[frame] then
    return
  end
  backpackFrames[frame] = provider
  frame:HookScript("OnShow", QueueUpdate)
  frame:HookScript("OnHide", QueueUpdate)
  if provider == "baganator" then
    local manager = frame.ButtonsManager
    if manager and type(manager.Arrange) == "function" then
      hooksecurefunc(manager, "Arrange", QueueUpdate)
    end
  elseif provider == "bagnon" and type(frame.Layout) == "function" then
    hooksecurefunc(frame, "Layout", QueueUpdate)
  elseif provider == "stock" and type(frame.UpdateItems) == "function" then
    hooksecurefunc(frame, "UpdateItems", QueueUpdate)
  end
end

local function FindStockBackpacks()
  if not ContainerFrameUtil_EnumerateContainerFrames then
    return
  end
  for _, frame in ContainerFrameUtil_EnumerateContainerFrames() do
    if not frame:IsForbidden() then
      WatchBackpack(frame, "stock")
    end
  end
end

local function FindBagnonBackpack()
  local frames = Bagnon and Bagnon.Frames
  if frames and frames ~= bagnonFrames and type(frames.Show) == "function" then
    bagnonFrames = frames
    hooksecurefunc(frames, "Show", QueueUpdate)
  end
  local frame = frames and frames.Get and frames:Get("inventory")
  if frame and type(frame.HookScript) == "function" and not frame:IsForbidden() then
    WatchBackpack(frame, "bagnon")
  end
end

local function FindBaganatorBackpacks()
  local frame = EnumerateFrames()
  while frame do
    if not backpackFrames[frame] and not frame:IsForbidden() and IsOuterBaganatorBackpack(frame) then
      WatchBackpack(frame, "baganator")
    end
    frame = EnumerateFrames(frame)
  end
end

local function UpdateLauncher()
  updateQueued = false
  if InCombatLockdown() then
    return
  end
  FindStockBackpacks()
  FindBagnonBackpack()
  local frame = GetVisibleBackpack()
  if Baganator and backpackFrames[frame] ~= "baganator" then
    FindBaganatorBackpacks()
    frame = GetVisibleBackpack()
  end
  local changed = frame ~= activeBackpack
  activeBackpack = frame
  if frame then
    if changed then
      launcher:SetParent(frame)
    end
    Position(frame, backpackFrames[frame])
  end
  if changed then
    launcher:SetShown(frame ~= nil)
    RefreshBindings()
  end
  DrawExternalBadges()
end

QueueUpdate = function()
  if not updateQueued then
    updateQueued = true
    C_Timer.After(0, UpdateLauncher)
  end
end

local function GetBackpackItemSlot(frame)
  local itemButton
  while frame and not frame:IsForbidden() do
    local provider = backpackFrames[frame] or (Baganator and IsOuterBaganatorBackpack(frame) and "baganator")
    if provider then
      if not itemButton or (provider == "bagnon" and frame:IsCached()) then
        return
      end
      local getBag = (provider == "bagnon" and itemButton.GetBag) or itemButton.GetBagID
      local bag, slot = getBag and getBag(itemButton), itemButton:GetID()
      if type(bag) == "number" and bag >= 0 and bag <= addon.LastBag()
        and type(slot) == "number" and slot > 0 then
        return bag, slot
      end
      return
    end
    if not itemButton and frame.GetID and (frame.GetBagID or frame.GetBag) then
      itemButton = frame
    end
    frame = frame:GetParent()
  end
end

local function CreateBadge(itemButton)
  local badge = CreateFrame("Frame", nil, itemButton)
  badge:SetSize(20, 17)
  badge.itemButton = itemButton

  local envelope = badge:CreateTexture(nil, "ARTWORK")
  envelope:SetSize(19, 15)
  envelope:SetPoint("TOPLEFT", 0, 0)
  envelope:SetAtlas(mailIcon)

  local number = badge:CreateFontString(nil, "OVERLAY")
  number:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
  number:SetTextColor(1, 1, 1)
  number:SetPoint("BOTTOMRIGHT", 0, 0)
  badge.number = number

  badge:Hide()
  return badge
end

local function UpdateBadge(badge, details)
  local itemID = details.itemID
  local bag, slot = GetBackpackItemSlot(badge.itemButton)
  if not itemID or not bag or C_Container.GetContainerItemID(bag, slot) ~= itemID then
    return false
  end
  local mark = addon.GetMark(addon.GetStackGUID(bag, slot))
  if not mark or mark.itemID ~= itemID then
    return false
  end
  badge.number:SetText(mark.slot)
  return true
end

local function DrawExternalBadge(button, painted)
  if not button:IsVisible() then
    return
  end
  local bag, slot = GetBackpackItemSlot(button)
  local itemID = bag and C_Container.GetContainerItemID(bag, slot)
  local mark = itemID and addon.GetMark(addon.GetStackGUID(bag, slot))
  if not mark or mark.itemID ~= itemID then
    return
  end
  local badge = externalBadges[button]
  if not badge then
    badge = CreateBadge(button)
    badge:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    externalBadges[button] = badge
  end
  badge.number:SetText(mark.slot)
  badge:Show()
  painted[badge] = true
end

DrawExternalBadges = function()
  local painted = {}
  if addon.HasStackMarks() then
    for frame, provider in pairs(backpackFrames) do
      if frame:IsVisible() then
        if provider == "stock" and frame.EnumerateValidItems then
          local bag = frame:GetBagID()
          if frame == ContainerFrameCombinedBags or (bag and bag >= 0 and bag <= addon.LastBag()) then
            for _, button in frame:EnumerateValidItems() do
              DrawExternalBadge(button, painted)
            end
          end
        elseif provider == "bagnon" then
          local buttons = frame.ItemGroup and frame.ItemGroup.buttons
          for _, button in ipairs(buttons or {}) do
            DrawExternalBadge(button, painted)
          end
        end
      end
    end
  end
  for _, badge in pairs(externalBadges) do
    if not painted[badge] then
      badge:Hide()
    end
  end
end

local baganatorConnected = false
local function ConnectBaganator()
  if baganatorConnected or not Baganator then
    return
  end
  baganatorConnected = true
  if Baganator.Skins and Baganator.Skins.AddFrame then
    Baganator.Skins.AddFrame("IconButton", launcher, { "altMail" })
  end
  local api = Baganator.API
  if api and api.RegisterCornerWidget then
    api.RegisterCornerWidget("Alt Mail group", "baganator_alt_mail_group", UpdateBadge, CreateBadge, {
      corner = "top_left", priority = 1,
    }, true)
  end
  if Baganator.CallbackRegistry then
    Baganator.CallbackRegistry:RegisterCallback("ViewComplete", QueueUpdate, owner)
  end
end

function addon.RefreshItemBadges()
  local api = Baganator and Baganator.API
  if api and api.RequestItemButtonsRefresh then
    api.RequestItemButtonsRefresh()
  end
  QueueUpdate()
end

function addon.MarkHovered(slot)
  if InCombatLockdown() or addon.IsSending() or GetCurrentKeyBoardFocus() or GetCursorInfo() then
    return
  end
  local bag, bagSlot = GetBackpackItemSlot((GetMouseFoci() or {})[1])
  if not bag then
    return
  end
  local item = C_Container.GetContainerItemInfo(bag, bagSlot)
  if not item then
    return
  end
  local guid = addon.GetStackGUID(bag, bagSlot)
  if not guid then
    addon.Print("This stack can't be identified for mail.")
    return
  end
  local mark = addon.GetMark(guid)
  local group = addon.GetGroup(slot)
  local route = addon.GetRoute(nil, group)
  if not mark or mark.slot ~= slot then
    if not route then
      addon.Print("Set a recipient for " .. group.name .. " in Alt Mail first.")
      return
    end
    if not addon.GetMailableItem(bag, bagSlot) then
      addon.Print("This item can't be marked for mail.")
      return
    end
  end
  if addon.ToggleMark(slot, guid, item) then
    addon.Print(item.hyperlink .. " marked for " .. route.recipient .. ".")
  else
    addon.Print((item.hyperlink or mark.link) .. " mail mark removed.")
  end
  addon.RefreshMarks()
end

owner:RegisterEvent("PLAYER_LOGIN")
owner:RegisterEvent("PLAYER_ENTERING_WORLD")
owner:RegisterEvent("PLAYER_REGEN_ENABLED")
owner:RegisterEvent("UPDATE_BINDINGS")
owner:RegisterEvent("BAG_UPDATE_DELAYED")
owner:RegisterEvent("ADDON_LOADED")
owner:SetScript("OnEvent", function(_, event, name)
  if event == "UPDATE_BINDINGS" then
    RefreshBindings()
  elseif event == "BAG_UPDATE_DELAYED" then
    if launcher:IsVisible() and addon.HasStackMarks() then
      addon.RefreshItemBadges()
    end
  elseif event == "ADDON_LOADED" then
    if name == "Baganator" or name == "Bagnon" or name == "Blizzard_UIPanels_Game" then
      ConnectBaganator()
      QueueUpdate()
    end
  else
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
      addon.RestoreLegacySettings()
    end
    QueueUpdate()
    if event == "PLAYER_REGEN_ENABLED" then
      RefreshBindings()
    end
  end
end)

ConnectBaganator()

for _, name in ipairs({ "OpenBackpack", "ToggleBackpack", "OpenAllBags", "ToggleAllBags" }) do
  if type(_G[name]) == "function" then
    hooksecurefunc(name, QueueUpdate)
  end
end
