local _, ns = ...
local Upgrades = { queue = {}, queued = {} }
ns.Upgrades = Upgrades

local function ItemKey(link)
	return ns.Text(link) and (link:match("item:[^|]+") or link)
end

local function Container(method, legacy, ...)
	local getter = C_Container and C_Container[method] or _G[legacy]
	if getter then return getter(...) end
end

function Upgrades:Snapshot()
	local counts, bags = {}, {}
	local function Count(link, amount, bag, slot)
		local key = ItemKey(link)
		if not key then return end
		counts[key] = (counts[key] or 0) + (amount or 1)
		if bag ~= nil and not bags[key] then bags[key] = { key = key, link = link, bag = bag, slot = slot } end
	end
	for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
		local slots = Container("GetContainerNumSlots", "GetContainerNumSlots", bag) or 0
		for slot = 1, slots do
			local link = Container("GetContainerItemLink", "GetContainerItemLink", bag, slot)
			local id = Container("GetContainerItemID", "GetContainerItemID", bag, slot)
			if id and not link then return nil end -- Do not turn a cache miss into a new acquisition.
			local info = Container("GetContainerItemInfo", "GetContainerItemInfo", bag, slot)
			local amount = type(info) == "table" and info.stackCount or nil
			Count(link, amount, bag, slot)
		end
	end
	-- Count equipped items too, so equipping or sorting does not create a new loot popup.
	for slot = 1, 19 do
		local link = GetInventoryItemLink("player", slot)
		if not link and GetInventoryItemID and GetInventoryItemID("player", slot) then return nil end
		Count(link)
	end
	return counts, bags
end

function Upgrades:Enqueue(candidate)
	if self.queued[candidate.key] then return end
	self.queued[candidate.key] = true
	self.queue[#self.queue + 1] = candidate
end

function Upgrades:Scan(review)
	if review then self.reviewRequested = true end
	review = self.reviewRequested
	local counts, bags = self:Snapshot()
	if not counts then
		if review and not self.reviewWaiting then
			self.reviewWaiting = true
			ns.Print("Waiting for inventory item data...")
		end
		self:Schedule(0.5)
		return
	end
	local found, loading, similar, worse, unusable = 0, 0, 0, 0, 0
	if ns.db.popups then
		for key, candidate in pairs(bags) do
			if review then
				local status = ns.Compare:Get(candidate.link).status
				if status == "upgrade" then found = found + 1
				elseif status == "pending" then loading = loading + 1
				elseif status == "equal" then similar = similar + 1
				elseif status == "downgrade" then worse = worse + 1
				elseif status == "unusable" or status == "unsupported" then unusable = unusable + 1 end
			end
			if review or (self.counts and counts[key] > (self.counts[key] or 0)) then self:Enqueue(candidate) end
		end
	else
		wipe(self.queue); wipe(self.queued)
		self.current = nil
		if self.frame then self.frame:Hide() end
	end
	self.counts, self.bags = counts, bags
	self:Advance()
	if review then
		self.reviewRequested, self.reviewWaiting = nil, nil
		local message
		if found > 0 then
			message = ("Found %d bag upgrade%s for %s."):format(found, found == 1 and "" or "s", ns.profile and ns.profile.label or "your build")
			if InCombatLockdown() then message = message .. " The prompt will open after combat." end
		elseif loading == 0 then
			message = ("No bag upgrades for %s (%d similar, %d downgrades, %d unusable)."):format(
				ns.profile and ns.profile.label or "your build", similar, worse, unusable)
		else message = "Checking bag items." end
		if loading > 0 then message = message .. (" %d comparison%s still loading."):format(loading, loading == 1 and " is" or "s are") end
		ns.Print(message)
		if loading > 0 then
			if ns.Items.lastError then ns.Print("Item data: " .. ns.Items.lastError) end
			if ns.Compare.lastError then ns.Print("Comparison: " .. ns.Compare.lastError) end
		end
	end
end

function Upgrades:Review()
	-- An explicit review starts with fresh item and equipment comparisons.
	ns:Invalidate(true)
	self:Scan(true)
end

function Upgrades:Schedule(delay)
	if self.pending or not ns.loggedIn then return end
	self.pending = true
	C_Timer.After(delay or 0.2, function()
		self.pending = false
		self:Scan()
	end)
end

function Upgrades:Dismiss()
	if self.current then self.queued[self.current.key] = nil end
	self.current = nil
	if self.frame then self.frame:Hide() end
	self:Advance()
end

function Upgrades:Advance()
	if not ns.profile or not ns.db.popups then return end
	if InCombatLockdown() then
		if self.frame then self.frame:Hide() end
		return
	end
	local pending = {}
	if self.current then table.insert(self.queue, 1, self.current); self.current = nil end
	while #self.queue > 0 do
		local candidate = table.remove(self.queue, 1)
		local location = self.bags and self.bags[candidate.key]
		local result = location and ns.Compare:Get(location.link)
		if result and result.status == "pending" then
			pending[#pending + 1] = candidate
		elseif result and result.status == "upgrade" then
			self.current = location
			self:Show(result)
			break
		else self.queued[candidate.key] = nil end
	end
	for _, candidate in ipairs(pending) do self.queue[#self.queue + 1] = candidate end
	if #pending > 0 then self:Schedule(0.5) end
	if not self.current and self.frame then self.frame:Hide() end
end

local function SameReplacement(a, b)
	return a and b and a.slot == b.slot and table.concat(a.oldLinks or {}, "|") == table.concat(b.oldLinks or {}, "|")
end

function Upgrades:Equip()
	if not self.current then return end
	if InCombatLockdown() then ns.Print("You can equip the upgrade after combat."); return end
	if CursorHasItem and CursorHasItem() then ns.Print("Put down the item on your cursor first."); return end
	local counts, bags = self:Snapshot()
	local location = bags and bags[self.current.key]
	if not location then self:Scan(); return end
	ns.Compare:Clear()
	local result = ns.Compare:Get(location.link)
	if result.status == "pending" then self:Schedule(); return end
	if result.status ~= "upgrade" then self:Dismiss(); return end
	if not SameReplacement(self.result, result) then
		self:Show(result)
		ns.Print("Your equipment changed. Review the updated comparison, then click Equip.")
		return
	end
	local info = Container("GetContainerItemInfo", "GetContainerItemInfo", location.bag, location.slot)
	if type(info) == "table" and info.isLocked then ns.Print("That item is busy. Try again in a moment."); return end
	local pickup = C_Container and C_Container.PickupContainerItem or PickupContainerItem
	if not pickup or not EquipCursorItem then ns.Print("Equipping is unavailable on this client."); return end
	-- This runs only from the player's click, with the exact reviewed slot.
	pickup(location.bag, location.slot)
	if CursorHasItem and not CursorHasItem() then return end
	EquipCursorItem(result.slot)
	local binding = StaticPopup_Visible and (StaticPopup_Visible("EQUIP_BIND")
		or StaticPopup_Visible("EQUIP_BIND_TRADEABLE") or StaticPopup_Visible("EQUIP_BIND_REFUNDABLE"))
	if ClearCursor and not binding then ClearCursor() end
	self.counts, self.bags = counts, bags
	-- Keep the prompt until equipment events confirm success (including bind confirmation).
	self:Schedule(0.5)
end

function Upgrades:CreateFrame()
	local frame = CreateFrame("Frame", "GearwiseUpgradePopup", UIParent, "BackdropTemplate")
	self.frame = frame
	frame:Hide()
	frame:SetSize(350, 171)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 } })
	frame:SetBackdropColor(0.04, 0.06, 0.09, 0.98)
	frame:SetBackdropBorderColor(0.4, 0.65, 0.8)
	local function Text(text, x, y, font, width)
		local label = frame:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
		label:SetPoint("TOPLEFT", x, y)
		label:SetWidth(width or 326)
		label:SetJustifyH("LEFT")
		label:SetText(text)
		return label
	end
	Text("Gearwise", 12, -12, "GameFontNormalLarge", 94)
	frame.summary = Text("", 112, -15, "GameFontHighlightSmall", 188)
	Text("Equipped", 12, -36, "GameFontNormal", 157)
	Text("Upgrade", 181, -36, "GameFontNormal", 157)
	local function Card(x, y)
		local card = CreateFrame("Button", nil, frame)
		card:SetPoint("TOPLEFT", x, y)
		card:SetSize(157, 48)
		card.icon = card:CreateTexture(nil, "ARTWORK")
		card.icon:SetSize(48, 48)
		card.icon:SetPoint("TOPLEFT", 0, 0)
		card.label = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		card.label:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 6, 0)
		card.label:SetWidth(103)
		card.label:SetJustifyH("LEFT")
		card:SetScript("OnEnter", function(button)
			if button.link then
				GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
				GameTooltip:SetHyperlink(button.link)
				GameTooltip:Show()
			end
		end)
		card:SetScript("OnLeave", function() GameTooltip:Hide() end)
		card:SetScript("OnClick", function(button)
			if button.link and HandleModifiedItemClick then HandleModifiedItemClick(button.link) end
		end)
		return card
	end
	frame.old = { Card(12, -53), Card(12, -107) }
	frame.new = Card(181, -53)
	frame.changes = Text("", 12, -107, "GameFontHighlightSmall")
	frame.note = Text("", 12, -125, "GameFontHighlightSmall")
	frame.note:SetTextColor(0.68, 0.72, 0.78)
	local equip = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	equip:SetSize(184, 34)
	equip:SetPoint("BOTTOMRIGHT", -12, 10)
	equip:SetText("Equip upgrade")
	equip:SetScript("OnClick", function() self:Equip() end)
	frame.equip = equip
	local later = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	later:SetSize(104, 22)
	later:SetPoint("RIGHT", equip, "LEFT", -8, 0)
	later:SetText("Keep current")
	later:SetScript("OnClick", function() self:Dismiss() end)
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -3, -3)
	close:SetScript("OnClick", function() self:Dismiss() end)
	frame:SetScript("OnHide", function()
		if GameTooltip.GetOwner then
			local owner = GameTooltip:GetOwner()
			if owner == frame.new or owner == frame.old[1] or owner == frame.old[2] then GameTooltip:Hide() end
		end
	end)
	return frame
end

function Upgrades:Show(result)
	local frame = self.frame or self:CreateFrame()
	self.result = result
	local function Fill(card, link)
		card.link = link
		local item = link and ns.Items:Get(link)
		card.icon:SetTexture(item and item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		card.label:SetText(link or "Empty slot")
		local height = math.max(48, card.label:GetStringHeight())
		card:SetHeight(height)
		card:Show()
		return height
	end
	local oldHeight = Fill(frame.old[1], result.oldLinks[1])
	if result.oldLinks[2] then
		frame.old[2]:ClearAllPoints()
		frame.old[2]:SetPoint("TOPLEFT", 12, -53 - oldHeight - 6)
		oldHeight = oldHeight + 6 + Fill(frame.old[2], result.oldLinks[2])
	else frame.old[2]:Hide() end
	local newHeight = Fill(frame.new, self.current.link)
	local score = result.percent and ("  |cff55df82+%.1f%%|r"):format(result.percent) or "  Empty slot"
	frame.summary:SetText(ns.profile.label .. score)
	local statsTop = 53 + math.max(oldHeight, newHeight) + 6
	frame.changes:ClearAllPoints()
	frame.changes:SetPoint("TOPLEFT", 12, -statsTop)
	local changes = ns.Display:Changes(result, math.huge, 2)
	frame.changes:SetText(#changes > 0 and table.concat(changes, "\n") or "No base stat changes.")
	local contentBottom = statsTop + math.max(14, frame.changes:GetStringHeight())
	frame.note:ClearAllPoints()
	frame.note:SetPoint("TOPLEFT", 12, -contentBottom - 4)
	local notes = {}
	if #result.oldLinks > 1 then notes[#notes + 1] = "Replaces main hand and off hand." end
	if result.effects then notes[#notes + 1] = "Effects and set bonuses excluded." end
	frame.note:SetText(table.concat(notes, "\n"))
	if #notes > 0 then contentBottom = contentBottom + 4 + frame.note:GetStringHeight() end
	frame:SetHeight(contentBottom + 50)
	frame:Show()
end

function Upgrades:Init()
	self:CreateFrame()
	-- Establish the initial inventory without prompting for pre-existing gear.
	self:Scan()
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:SetScript("OnEvent", function() if self.frame then self.frame:Hide() end end)
end
