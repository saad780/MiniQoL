local _, ns = ...
local addon = ns.AltMail
local groupPanelHeight, categoryPanelHeight = 433, 351

local panel = CreateFrame("Frame", "MiniQoLAltMailPanel", UIParent, "BasicFrameTemplateWithInset")
panel:SetSize(425, groupPanelHeight)
panel:SetPoint("CENTER")
panel:SetFrameStrata("DIALOG")
panel:SetClampedToScreen(true)
panel:EnableMouse(true)
panel:SetMovable(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
panel.TitleText:SetText("Mini QoL Alt Mail")
panel:Hide()
tinsert(UISpecialFrames, panel:GetName())

local function Label(text, x, y, template)
  local label = panel:CreateFontString(nil, "ARTWORK", template or "GameFontNormal")
  label:SetPoint("TOPLEFT", x, y)
  label:SetJustifyH("LEFT")
  label:SetText(text)
  return label
end

local function Button(text, x, y, width)
  local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  button:SetSize(width, 24)
  button:SetPoint("TOPLEFT", x, y)
  button:SetText(text)
  return button
end

Label("Mail group", 17, -39)
local dropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
dropdown:SetSize(229, 24)
dropdown:SetPoint("TOPLEFT", 174, -34)
dropdown:SetDefaultText("Choose a mail group")

local function EditBox(y, maxBytes)
  local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
  box:SetSize(217, 23)
  box:SetPoint("TOPLEFT", 179, y)
  box:SetAutoFocus(false)
  box:SetMaxBytes(maxBytes)
  box:SetScript("OnEscapePressed", box.ClearFocus)
  return box
end

local nameLabel = Label("Group name", 17, -75)
local groupName = EditBox(-69, 48)
Label("Recipient", 17, -110)
local recipient = EditBox(-104, 96)

local automatic = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
automatic:SetPoint("TOPLEFT", 12, -138)
automatic.Text:SetText("Send automatically when I open a mailbox")

local save = Button("Save", 17, -180, 80)
local unlink = Button("Unlink", 103, -180, 80)
local send = Button("Send Now", 294, -180, 109)

local marks = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
marks:SetSize(268, 24)
marks:SetPoint("TOPLEFT", 17, -224)
local clearMark = Button("Remove Mark", 294, -224, 109)

local status = Label("", 17, -269, "GameFontHighlightSmall")
status:SetWidth(386)
status:SetJustifyV("TOP")
status:SetMaxLines(4)

local helpHeading = Label("How marking works", 17, -310, "GameFontNormalSmall")
local help = Label("", 17, -328, "GameFontHighlightSmall")
help:SetWidth(386)
help:SetJustifyV("TOP")
help:SetSpacing(3)

local selectedID = "altmail:1"
local selectedProfile
local selectedGUID

local function CurrentCategory()
  local profile, name = addon.GetProfile()
  for _, category in ipairs(addon.GetMailCategories(profile)) do
    if category.id == selectedID and (category.slot or name == selectedProfile) then
      return category, name
    end
  end
end

local function UpdateMarkButton(category)
  local mark = selectedGUID and addon.GetMark(selectedGUID)
  clearMark:SetEnabled(not addon.IsSending() and mark and mark.slot == category.slot or false)
end

marks:SetupMenu(function(_, root)
  local category = CurrentCategory()
  if not category or not category.slot then
    return
  end
  for _, item in ipairs(addon.GetMarkedItems(category.slot)) do
    root:CreateRadio(("%s ×%d"):format(item.link, item.count), function(guid)
      return guid == selectedGUID
    end, function(guid)
      selectedGUID = guid
      UpdateMarkButton(category)
    end, item.guid)
  end
end)

function addon.RefreshMarks()
  if not panel:IsShown() then
    return
  end
  local category = CurrentCategory()
  local visible = category ~= nil and category.slot ~= nil
  marks:SetShown(visible)
  clearMark:SetShown(visible)
  if visible then
    local mark = selectedGUID and addon.GetMark(selectedGUID)
    if not mark or mark.slot ~= category.slot then
      selectedGUID = nil
    end
    local total = #addon.GetMarkedItems(category.slot)
    marks:SetDefaultText(total == 0 and "No marked stacks" or ("%d marked stacks"):format(total))
    marks:SetEnabled(total > 0)
    marks:GenerateMenu()
    UpdateMarkButton(category)
  end
end

function addon.RefreshMailControls()
  if not panel:IsShown() then
    return
  end
  local category, name = CurrentCategory()
  local route = category and addon.GetRoute(name, category)
  local usable = category ~= nil and addon.Trim(category.search) == ""
  local isGroup = category ~= nil and category.slot ~= nil
  local label = addon.Trim(groupName:GetText())
  local saved = route ~= nil and addon.Trim(recipient:GetText()) == route.recipient
    and (automatic:GetChecked() == true) == route.automatic
    and (not isGroup or label == category.name)
  local busy = addon.IsSending()
  save:SetEnabled(not busy and usable and addon.Trim(recipient:GetText()) ~= "" and not saved
    and (not isGroup or label ~= ""))
  unlink:SetEnabled(not busy and route ~= nil)
  send:SetEnabled(not busy and usable and saved and addon.IsMailboxOpen() == true)
  local shortcut
  if isGroup then
    local shortcuts = { addon.GetMarkShortcut(1), addon.GetMarkShortcut(2) }
    shortcut = shortcuts[category.slot]
    help:SetText(("Group 1  %s    Group 2  %s\n"):format(shortcuts[1] or "Unbound", shortcuts[2] or "Unbound")
      .. "Hover a stack and press its group shortcut. The numbered envelope marks just that stack. "
      .. "Press the same shortcut again to clear it, or the other to move it.\n"
      .. "Click Send Now at a mailbox, or enable auto-send before opening one. Hold Shift when opening to skip auto-send.")
    UpdateMarkButton(category)
  end
  if busy then
    status:SetText("Sending items...")
  elseif not category then
    status:SetText("Choose a mail group.")
  elseif not usable then
    status:SetText("Clear this category's search rule to link it. Drag items into the category to choose what gets mailed.")
  elseif route and not saved then
    status:SetText("Save your changes before sending.")
  elseif isGroup and route then
    if not shortcut then
      status:SetText(("Choose a shortcut in Options > Keybindings > Mini QoL Alt Mail > Mark for Mail Group %d."):format(category.slot))
    else
      status:SetText("")
    end
  elseif isGroup then
    status:SetText("Enter your alt's name and save to start marking items.")
  elseif route and route.automatic then
    status:SetText("Linked. Drag items into the category to include them. Hold Shift when opening a mailbox to skip automatic sending.")
  elseif route then
    status:SetText("Linked. Drag items into the category, then click Send Now at a mailbox.")
  else
    status:SetText("Enter your alt's character name and save. Only items you drag into the category are eligible.")
  end
end

local function LoadCategory()
  local category, name = CurrentCategory()
  local route = category and addon.GetRoute(name, category)
  local isGroup = category ~= nil and category.slot ~= nil
  panel:SetHeight(isGroup and groupPanelHeight or categoryPanelHeight)
  nameLabel:SetShown(isGroup)
  groupName:SetShown(isGroup)
  helpHeading:SetShown(isGroup)
  help:SetShown(isGroup)
  groupName:SetText(isGroup and category.name or "")
  recipient:SetText(route and route.recipient or "")
  automatic:SetChecked(route and route.automatic or false)
  addon.RefreshMarks()
  addon.RefreshMailControls()
end

dropdown:SetupMenu(function(_, root)
  local profile, name = addon.GetProfile()
  local shownNativeTitle = false
  for _, category in ipairs(addon.GetMailCategories(profile)) do
    if not category.slot and not shownNativeTitle then
      root:CreateTitle("Baganator categories")
      shownNativeTitle = true
    end
    local label = category.slot and ("%d. %s"):format(category.slot, category.name) or category.name
    root:CreateRadio(label, function(entry)
      return selectedID == entry.id and (entry.slot ~= nil or selectedProfile == name)
    end, function(entry)
      selectedProfile = name
      selectedID = entry.id
      selectedGUID = nil
      LoadCategory()
    end, category)
  end
end)

panel:SetScript("OnShow", function()
  if not CurrentCategory() then
    selectedID = addon.GetGroup(1).id
    selectedGUID = nil
  end
  LoadCategory()
  dropdown:GenerateMenu()
end)

recipient:SetScript("OnTextChanged", addon.RefreshMailControls)
groupName:SetScript("OnTextChanged", addon.RefreshMailControls)
recipient:SetScript("OnEnterPressed", function()
  if save:IsEnabled() then
    save:Click()
  end
end)
automatic:HookScript("OnClick", addon.RefreshMailControls)

save:SetScript("OnClick", function()
  local category, name = CurrentCategory()
  if not category or addon.Trim(category.search) ~= "" or addon.IsSending() then
    return
  end
  local target, errorMessage = addon.ValidateRecipient(recipient:GetText())
  if not target then
    status:SetText(errorMessage)
    return
  end
  addon.SaveRoute(name, category, target, automatic:GetChecked() == true, addon.Trim(groupName:GetText()))
  recipient:ClearFocus()
  groupName:ClearFocus()
  LoadCategory()
  dropdown:GenerateMenu()
end)

unlink:SetScript("OnClick", function()
  local category, name = CurrentCategory()
  if category and not addon.IsSending() then
    addon.SaveRoute(name, category)
    LoadCategory()
  end
end)

send:SetScript("OnClick", function()
  if selectedID and CurrentCategory() then
    addon.StartMail(selectedID)
  end
end)

clearMark:SetScript("OnClick", function()
  local category = CurrentCategory()
  local mark = selectedGUID and addon.GetMark(selectedGUID)
  if category and mark and mark.slot == category.slot and not addon.IsSending() then
    addon.ClearMark(selectedGUID)
    selectedGUID = nil
    addon.RefreshMarks()
  end
end)

function addon.TogglePanel()
  panel:SetShown(not panel:IsShown())
end

SLASH_MINIQOLALTMAIL1 = "/altmail"
SlashCmdList.MINIQOLALTMAIL = addon.TogglePanel

ns:RegisterFeature({
  id = "mail.altMail", page = "mail", group = "Sending mail", label = "Alt Mail",
  kind = "action", button = "Open", run = addon.TogglePanel,
  tooltip = "Set recipients and review the individual bag stacks marked for each alt.",
})
