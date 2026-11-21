local addonName, ns = ...
local addon = ns.AltMail
local mailboxOpen = false
local visit = 0
local active
local maxAttachments = ATTACHMENTS_MAX_SEND or 12

local function Finish(message)
  active = nil
  if message then
    addon.Print(message)
  end
  if addon.RefreshMailControls then
    addon.RefreshMailControls()
  end
end

function addon.IsMailboxOpen()
  return mailboxOpen and MailFrame and MailFrame:IsShown()
end

function addon.IsSending()
  return active ~= nil
end

local function HasComposeChanges()
  local subject = SendMailSubjectEditBox:GetText()
  return SendMailFrame.sendMode == "reply"
    or SendMailNameEditBox:GetText() ~= ""
    or (subject ~= "" and subject ~= SendMailFrame.previousItem)
    or SendMailBodyEditBox:GetText() ~= ""
    or MoneyInputFrame_GetCopper(SendMailMoney) > 0
    or (GetSendMailMoney() or 0) > 0
    or (GetSendMailCOD() or 0) > 0
end

local function CanUseComposer()
  return addon.IsMailboxOpen() and not InCombatLockdown() and not GetCursorInfo()
end

local function HasAttachments()
  for slot = 1, maxAttachments do
    if HasSendMailItem(slot) then
      return true
    end
  end
  return false
end

local function GetCurrentAssignmentLookup(run, job)
  local profile, name = addon.GetProfile()
  if job.category.slot or name == run.profileName then
    for _, category in ipairs(addon.GetMailCategories(profile)) do
      if category.id == job.category.id and (category.slot or category.name == job.category.name)
        and addon.Trim(category.search) == "" then
        local route = addon.GetRoute(name, category)
        if route and route.recipient == job.recipient and (run.manual or route.automatic) then
          return addon.GetAssignmentLookup(profile)
        end
      end
    end
  end
end

local function IsSameBagItem(item)
  local info = addon.GetMailableItem(item.bag, item.slot)
  if not info or info.itemID ~= item.id or info.hyperlink ~= item.link or info.stackCount ~= item.count then
    return false
  end
  return not item.guid or addon.GetStackGUID(item.bag, item.slot) == item.guid
end

local function Attach(item, slot)
  C_Container.PickupContainerItem(item.bag, item.slot)
  local kind, id = GetCursorInfo()
  if kind == "item" and id == item.id then
    ClickSendMailItemButton(slot)
  end
  if GetCursorInfo() then
    ClearCursor()
    return false
  end
  return kind == "item" and id == item.id
end

local function SendBatch(run, job, packed)
  if active ~= run then
    return
  end
  local assignmentFor = GetCurrentAssignmentLookup(run, job)
  if not assignmentFor or not CanUseComposer() or not SendMailFrame:IsShown() or HasComposeChanges()
    or (SendMailFrameLockSendMail and SendMailFrameLockSendMail:IsShown()) then
    Finish("Mail paused. Check the Send Mail tab before trying again.")
    return
  end

  for slot = 1, maxAttachments do
    local item = packed[slot]
    local _, id, _, count = GetSendMailItem(slot)
    if (item and (id ~= item.id or count ~= item.count or assignmentFor(id, item.guid) ~= job.category.id))
      or (not item and HasSendMailItem(slot)) then
      Finish("Attachments changed. Check the Send Mail tab before trying again.")
      return
    end
  end
  if GetSendMailPrice() > GetMoney() then
    Finish("You need more coin for postage. The attachments are in the Send Mail tab.")
    return
  end

  local pending = { recipient = job.recipient, items = packed, groupSlot = job.category.slot }
  run.pending = pending
  local ok = pcall(SendMail, job.recipient, "Mini QoL Alt Mail", "")
  if active ~= run or run.pending ~= pending then
    return
  end
  if not ok then
    Finish("Mail to " .. job.recipient .. " could not be sent. Check the Send Mail tab.")
    return
  end
  C_Timer.After(10, function()
    if active == run and run.pending == pending then
      Finish("WoW did not confirm delivery to " .. job.recipient .. ". Check before resending.")
    end
  end)
end

local function NextBatch(run)
  if active ~= run then
    return
  end
  if not CanUseComposer() or HasComposeChanges() or HasAttachments() then
    Finish("Mail paused because the mailbox or draft is in use.")
    return
  end

  local packed = {}
  local job = run.plan[run.index]
  while job and #packed == 0 do
    local assignmentFor = GetCurrentAssignmentLookup(run, job)
    if not assignmentFor then
      Finish("A category or recipient changed. Reopen the mailbox to try again.")
      return
    end
    while job.next <= #job.items and #packed < maxAttachments do
      local item = job.items[job.next]
      job.next = job.next + 1
      if assignmentFor(item.id, item.guid) == job.category.id and IsSameBagItem(item) then
        if not SendMailFrame:IsShown() then
          MailFrameTab_OnClick(nil, 2)
        end
        local ok, attached = pcall(Attach, item, #packed + 1)
        if GetCursorInfo() then
          ClearCursor()
        end
        if active ~= run then
          return
        end
        if not ok or not attached then
          Finish("An item could not be attached. Check the Send Mail tab.")
          return
        end
        packed[#packed + 1] = item
      end
    end
    if #packed == 0 then
      run.index = run.index + 1
      job = run.plan[run.index]
    end
  end

  if not job then
    Finish()
    return
  end
  C_Timer.After(0.35, function()
    SendBatch(run, job, packed)
  end)
end

function addon.StartMail(categoryID)
  if active or not addon.IsMailboxOpen() then
    return
  end
  local profile, name = addon.GetProfile()
  local plan = addon.GetMailPlan(profile, name, categoryID)
  local hasItems = false
  for _, job in ipairs(plan) do
    if #job.items > 0 then
      hasItems = true
      break
    end
  end
  if not hasItems then
    if categoryID then
      addon.Print("No eligible items in this mail group.")
    end
    return
  end

  active = { plan = plan, profileName = name, index = 1, manual = categoryID ~= nil }
  addon.RefreshMailControls()
  NextBatch(active)
end

local events = CreateFrame("Frame")
events:RegisterEvent("MAIL_SHOW")
events:RegisterEvent("MAIL_CLOSED")
events:RegisterEvent("MAIL_SEND_SUCCESS")
events:RegisterEvent("MAIL_FAILED")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:SetScript("OnEvent", function(_, event, source)
  if event == "MAIL_SHOW" then
    mailboxOpen = true
    visit = visit + 1
    local thisVisit = visit
    addon.RefreshMailControls()
    if not IsShiftKeyDown() then
      C_Timer.After(0.65, function()
        if visit == thisVisit and not IsShiftKeyDown() then
          addon.StartMail()
        end
      end)
    end
  elseif event == "MAIL_CLOSED" then
    mailboxOpen = false
    visit = visit + 1
    Finish()
  elseif event == "MAIL_SEND_SUCCESS" and active and active.pending then
    local run = active
    local pending = run.pending
    run.pending = nil
    addon.ClearSentMarks(pending.items, pending.groupSlot)
    addon.Print(("Sent %d stack(s) to %s."):format(#pending.items, pending.recipient))
    C_Timer.After(0.65, function()
      NextBatch(run)
    end)
  elseif event == "MAIL_FAILED" and active and active.pending and source == nil then
    Finish("WoW rejected mail to " .. active.pending.recipient .. ". Check the Send Mail tab.")
  elseif (event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN") and active and source == addonName then
    Finish("WoW blocked automatic sending. Check the Send Mail tab.")
  end
end)
