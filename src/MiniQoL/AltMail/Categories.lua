local _, ns = ...
local addon = {}
ns.AltMail = addon
local stackLocation = ItemLocation:CreateEmpty()

function addon.Print(message)
  ns:Print("Alt Mail " .. message)
end

function addon.Trim(text)
  return strtrim(text or "")
end

function addon.GetProfile()
  local name = BAGANATOR_CURRENT_PROFILE or "DEFAULT"
  local profiles = BAGANATOR_CONFIG and BAGANATOR_CONFIG.Profiles
  local profile = profiles and profiles[name]
  if profile and type(profile.custom_categories) == "table"
    and type(profile.category_display_order) == "table"
    and type(profile.category_modifications) == "table" then
    return profile, name
  end
end

function addon.GetCategories(profile)
  local categories = {}
  if profile then
    for _, id in ipairs(profile.category_display_order) do
      local category = profile.custom_categories[id]
      if category and type(category.name) == "string" then
        categories[#categories + 1] = { id = id, name = category.name, search = category.search }
      end
    end
  end
  return categories
end

local function Groups()
  BaganatorAltMailGroups = type(BaganatorAltMailGroups) == "table" and BaganatorAltMailGroups or {}
  local groups = BaganatorAltMailGroups
  groups.settings = groups.settings or {}
  groups.stackMarks = groups.stackMarks or {}
  groups.excludedTypes = groups.excludedTypes or {}
  if groups.marks then
    local hadMarks = false
    for itemID, mark in pairs(groups.marks) do
      groups.excludedTypes[itemID] = true
      hadMarks = hadMarks or mark ~= false
    end
    groups.marks = nil
    if hadMarks then
      addon.Print("Old item-type marks were cleared. Mark the individual stacks you want to mail.")
    end
  end
  return groups
end

local function ProfileKey(name)
  if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) then return "" end
  return strlower((name:gsub("[%s%-]", "")))
end

function addon.RestoreLegacySettings()
  local profiles = ns.altMailLegacyProfiles
  if not profiles or (type(BaganatorAltMailGroups) == "table" and BaganatorAltMailGroups.legacyImported) then return end
  local player = ProfileKey(ns.Mail.PlayerName())
  if player == "" then return end
  local realm = ProfileKey(GetRealmName())
  local match
  for _, profile in ipairs(profiles) do
    if ProfileKey(profile.name) == player and (not profile.realm or realm == "" or ProfileKey(profile.realm) == realm) then
      if match then return end -- An ambiguous snapshot cannot safely choose a recipient.
      match = profile
    end
  end
  if not match then return end

  local saved = Groups()
  local groups, routes = match.read()
  if type(groups) == "table" and not next(saved.settings) and not next(saved.stackMarks) and not next(saved.excludedTypes) then
    BaganatorAltMailGroups = groups
  end
  if type(routes) == "table" and (not BaganatorAltMailRoutes or not next(BaganatorAltMailRoutes)) then
    BaganatorAltMailRoutes = routes
  end
  Groups().legacyImported = true
end

function addon.GetGroup(slot)
  local settings = Groups().settings[slot] or {}
  local defaultName = "Mail Group " .. slot
  local label = settings.label
  -- Older versions saved the numbered placeholder even when no name was entered.
  if label == nil and settings.name ~= defaultName then label = settings.name end
  label = addon.Trim(label)
  return {
    id = "altmail:" .. slot,
    slot = slot,
    label = label,
    name = label ~= "" and label or settings.recipient or defaultName,
  }
end

function addon.GetMailCategories(profile)
  local categories = { addon.GetGroup(1), addon.GetGroup(2) }
  for _, category in ipairs(addon.GetCategories(profile)) do
    categories[#categories + 1] = category
  end
  return categories
end

function addon.GetRoute(profileName, category)
  if category.slot then
    local route = Groups().settings[category.slot]
    return route and route.recipient and route or nil
  end
  local routes = BaganatorAltMailRoutes and BaganatorAltMailRoutes[profileName]
  local route = routes and routes[category.id]
  if route and route.name == category.name then
    return route
  end
end

function addon.ValidateRecipient(text)
  local recipient = addon.Trim(text):gsub(" +", " ")
  if recipient == "" or #recipient > 96 or recipient:find("[|%c]") then
    return nil, "Enter your alt's character name."
  end

  local ownName = UnitName("player")
  local name, realm = recipient:match("^([^%-]+)%-(.+)$")
  name = name or recipient
  if ownName and strlower(addon.Trim(name)) == strlower(ownName) then
    local ownRealm = GetNormalizedRealmName() or ""
    if not realm or strlower((realm:gsub("%s+", ""))) == strlower(ownRealm) then
      return nil, "Choose a different character as the recipient."
    end
  end
  return recipient
end

function addon.SaveRoute(profileName, category, recipient, automatic, label)
  if category.slot then
    label = addon.Trim(label or category.label)
    Groups().settings[category.slot] = {
      label = label ~= "" and label or nil, recipient = recipient, automatic = automatic == true,
    }
    return
  end
  BaganatorAltMailRoutes = BaganatorAltMailRoutes or {}
  local routes = BaganatorAltMailRoutes[profileName] or {}
  BaganatorAltMailRoutes[profileName] = routes
  routes[category.id] = recipient and {
    name = category.name,
    recipient = recipient,
    automatic = automatic,
  } or nil
end

local function GetCategoryAssignments(profile)
  -- Baganator stores manually assigned item types as "i:<itemID>".
  local assignments = {}
  local seen = {}
  for _, category in ipairs(addon.GetCategories(profile)) do
    local change = profile.category_modifications[category.id]
    local pins = change and change.addedItems
    if pins and not seen[category.id] then
      seen[category.id] = true
      for key, pinned in pairs(pins) do
        local id = type(key) == "string" and tonumber(key:match("^i:(%d+)$"))
        if id and pinned == true then
          if assignments[id] == nil then
            assignments[id] = category.id
          else
            assignments[id] = false
          end
        end
      end
    end
  end
  return assignments
end

function addon.GetAssignmentLookup(profile)
  local nativeAssignments = GetCategoryAssignments(profile)
  local groups = Groups()
  for itemID in pairs(groups.excludedTypes) do
    nativeAssignments[itemID] = nil
  end
  for _, mark in pairs(groups.stackMarks) do
    nativeAssignments[mark.itemID] = nil
  end
  return function(itemID, guid)
    local mark = groups.stackMarks[guid]
    if mark and mark.itemID == itemID then
      return "altmail:" .. mark.slot
    end
    return nativeAssignments[itemID]
  end
end

function addon.GetStackGUID(bag, slot)
  stackLocation:SetBagAndSlot(bag, slot)
  local guid = C_Item.GetItemGUID(stackLocation)
  if type(guid) == "string" and not (issecretvalue and issecretvalue(guid)) and guid ~= "" then
    return guid
  end
end

function addon.GetMark(guid)
  return Groups().stackMarks[guid]
end

function addon.HasStackMarks()
  return next(Groups().stackMarks) ~= nil
end

function addon.GetMarkedItems(slot)
  local items = {}
  for guid, mark in pairs(Groups().stackMarks) do
    if mark.slot == slot then
      items[#items + 1] = { guid = guid, link = mark.link, count = mark.count }
    end
  end
  table.sort(items, function(a, b) return a.guid < b.guid end)
  return items
end

local function ExcludeNativeRoute(groups, itemID)
  local profile = addon.GetProfile()
  if GetCategoryAssignments(profile)[itemID] then
    groups.excludedTypes[itemID] = true
  end
end

function addon.ClearMark(guid)
  local groups = Groups()
  local mark = groups.stackMarks[guid]
  if not mark then
    return
  end
  ExcludeNativeRoute(groups, mark.itemID)
  groups.stackMarks[guid] = nil
  addon.RefreshItemBadges()
end

function addon.ToggleMark(slot, guid, info)
  local groups = Groups()
  local mark = groups.stackMarks[guid]
  if mark and mark.slot == slot then
    addon.ClearMark(guid)
    return false
  end
  ExcludeNativeRoute(groups, info.itemID)
  groups.stackMarks[guid] = { slot = slot, itemID = info.itemID, link = info.hyperlink, count = info.stackCount }
  addon.RefreshItemBadges()
  return true
end

function addon.ClearSentMarks(items, groupSlot)
  if not groupSlot then
    return
  end
  local groups = Groups()
  for _, item in ipairs(items) do
    local mark = groups.stackMarks[item.guid]
    if mark and mark.slot == groupSlot then
      ExcludeNativeRoute(groups, mark.itemID)
      groups.stackMarks[item.guid] = nil
    end
  end
  addon.RefreshItemBadges()
  addon.RefreshMarks()
end

function addon.LastBag()
  return Enum.BagIndex.ReagentBag or NUM_BAG_SLOTS
end

function addon.GetMailableItem(bag, slot)
  local info = C_Container.GetContainerItemInfo(bag, slot)
  if not info or info.isLocked or info.isBound ~= false or not info.hyperlink then
    return
  end
  local _, _, _, _, _, class = C_Item.GetItemInfoInstant(info.itemID)
  local quest = C_Container.GetContainerItemQuestInfo(bag, slot)
  if not class or class == Enum.ItemClass.Questitem or (quest and (quest.isQuestItem or (quest.questID or 0) > 0)) then
    return
  end
  return info
end

function addon.GetMailPlan(profile, profileName, selectedID)
  local routesByID = {}
  local plan = {}
  for _, category in ipairs(addon.GetMailCategories(profile)) do
    local route = addon.GetRoute(profileName, category)
    if route and addon.Trim(category.search) == "" and addon.ValidateRecipient(route.recipient)
      and ((selectedID and selectedID == category.id) or (not selectedID and route.automatic)) then
      local job = { category = category, recipient = route.recipient, items = {}, next = 1 }
      routesByID[category.id] = job
      plan[#plan + 1] = job
    end
  end

  if #plan == 0 then
    return plan
  end
  local assignmentFor = addon.GetAssignmentLookup(profile)
  for bag = 0, addon.LastBag() do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local itemID = C_Container.GetContainerItemID(bag, slot)
      local guid = itemID and addon.GetStackGUID(bag, slot)
      local job = itemID and routesByID[assignmentFor(itemID, guid)]
      local info = job and addon.GetMailableItem(bag, slot)
      if info then
        job.items[#job.items + 1] = {
          bag = bag, slot = slot, guid = guid, id = info.itemID, count = info.stackCount,
          link = info.hyperlink,
        }
      end
    end
  end
  return plan
end
