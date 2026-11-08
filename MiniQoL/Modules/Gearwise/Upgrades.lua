-- Mini QoL packaging adapter; upstream source and credits follow.
MiniQoLRuntime:Execute("Gearwise", function(...)
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
	-- One pass over the bags serves both prompts: the upgrade queue and the
	-- equal-value look offers, which must see the same acquisitions.
	local acquired = {}
	for key, candidate in pairs(bags) do
		if review then
			local status = ns.Compare:Get(candidate.link).status
			if status == "upgrade" then found = found + 1
			elseif status == "pending" then loading = loading + 1
			elseif status == "equal" then similar = similar + 1
			elseif status == "downgrade" then worse = worse + 1
			elseif status == "unusable" or status == "unsupported" then unusable = unusable + 1 end
		end
		if review or (self.counts and counts[key] > (self.counts[key] or 0)) then
			acquired[#acquired + 1] = candidate
		end
	end
	if ns.db.popups then
		for _, candidate in ipairs(acquired) do self:Enqueue(candidate) end
	else
		wipe(self.queue); wipe(self.queued)
		self.current = nil
		if self.frame then self.frame:Hide() end
	end
	self.counts, self.bags = counts, bags
	self:Advance()
	if ns.Sidegrades then ns.Sidegrades:Consider(bags, acquired) end
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
	if self.current then self:UpdateQueueBadge() end
end

local function SameReplacement(a, b)
	return a and b and a.slot == b.slot and table.concat(a.oldLinks or {}, "|") == table.concat(b.oldLinks or {}, "|")
end

-- Shared by both prompts: move one reviewed bag slot into one equipment slot,
-- straight from the player's click. Returns false, with a reason printed, when
-- the client will not allow it right now.
function Upgrades:EquipLocation(location, slot)
	if InCombatLockdown() then ns.Print("You can equip the item after combat."); return false end
	if CursorHasItem and CursorHasItem() then ns.Print("Put down the item on your cursor first."); return false end
	local info = Container("GetContainerItemInfo", "GetContainerItemInfo", location.bag, location.slot)
	if type(info) == "table" and info.isLocked then ns.Print("That item is busy. Try again in a moment."); return false end
	local pickup = C_Container and C_Container.PickupContainerItem or PickupContainerItem
	if not pickup or not EquipCursorItem then ns.Print("Equipping is unavailable on this client."); return false end
	pickup(location.bag, location.slot)
	if CursorHasItem and not CursorHasItem() then return false end
	EquipCursorItem(slot)
	local binding = StaticPopup_Visible and (StaticPopup_Visible("EQUIP_BIND")
		or StaticPopup_Visible("EQUIP_BIND_TRADEABLE") or StaticPopup_Visible("EQUIP_BIND_REFUNDABLE"))
	if ClearCursor and not binding then ClearCursor() end
	return true
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
	-- This runs only from the player's click, with the exact reviewed slot.
	if not self:EquipLocation(location, result.slot) then return end
	self.counts, self.bags = counts, bags
	-- Keep the prompt until equipment events confirm success (including bind confirmation).
	self:Schedule(0.5)
end

local MEDIA = "Interface\\AddOns\\MiniQoL\\Modules\\Gearwise\\Media\\"
local SLOT_NAMES = ns.slotNames or {}
local WIDTH, PAD, HEADER = 400, 15, 34
local INNER = WIDTH - PAD * 2
-- The icon is the fastest way to recognise a piece of gear, so it gets the
-- room; the row grows with it to keep the same margins.
local ICON_SIZE = 36
local ROW_HEIGHT = 46

function Upgrades:CreateFrame()
	local T = MiniQoL.Theme
	local frame = CreateFrame("Frame", "GearwiseUpgradePopup", UIParent, "BackdropTemplate")
	self.frame = frame
	frame:Hide()
	frame:SetSize(WIDTH, 280)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	T:Window(frame, HEADER)

	local title = T:Text(frame, "Gearwise", "GameFontNormal", nil, T.GOLD)
	title:SetPoint("TOPLEFT", PAD, -11)
	frame.subtitle = T:Text(frame, "", "GameFontDisableSmall", 190, T.MUTED)
	frame.subtitle:SetJustifyH("RIGHT")
	frame.subtitle:SetPoint("TOPRIGHT", -34, -13)
	T:CloseButton(frame, function() self:Dismiss() end):SetPoint("TOPRIGHT", -5, -7)

	-- Score banner: the one number the prompt exists to deliver.
	local score = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	score:SetSize(INNER, 38)
	score:SetPoint("TOPLEFT", PAD, -(HEADER + 11))
	T:Chrome(score, { 0.105, 0.095, 0.072, 0.9 }, T.GOLD_SOFT)
	frame.score = score
	score.value = T:Text(score, "", "GameFontNormalLarge", nil, T.GOOD)
	score.value:SetJustifyV("MIDDLE")
	score.value:SetPoint("LEFT", 11, 0)
	score.caption = T:Text(score, "", "GameFontDisableSmall", 230, T.MUTED)
	score.caption:SetJustifyH("RIGHT")
	score.caption:SetJustifyV("MIDDLE")
	score.caption:SetPoint("RIGHT", -11, 0)

	local function Heading(text)
		local label = T:Text(frame, text, "GameFontDisableSmall", INNER, T.GOLD_SOFT)
		return label
	end
	frame.fromHeading = Heading("REPLACING")
	frame.toHeading = Heading("UPGRADE")

	local function Row()
		local row = CreateFrame("Button", nil, frame, "BackdropTemplate")
		row:SetSize(INNER, ROW_HEIGHT)
		T:Chrome(row, T.BG_CARD, { 0.27, 0.24, 0.17, 1 })
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(ICON_SIZE, ICON_SIZE)
		row.icon:SetPoint("LEFT", 6, 0)
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.iconEdge = CreateFrame("Frame", nil, row, "BackdropTemplate")
		row.iconEdge:SetPoint("TOPLEFT", row.icon, -1, 1)
		row.iconEdge:SetPoint("BOTTOMRIGHT", row.icon, 1, -1)
		row.iconEdge:SetBackdrop({ edgeFile = T.SOLID, edgeSize = 1 })
		row.iconEdge:SetBackdropBorderColor(0.3, 0.27, 0.2, 1)
		row.name = T:Text(row, "", "GameFontHighlightSmall", INNER - ICON_SIZE - 24)
		row.name:SetWordWrap(false)
		row.name:SetJustifyV("MIDDLE")
		row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 8)
		row.detail = T:Text(row, "", "GameFontDisableSmall", INNER - ICON_SIZE - 24, T.MUTED)
		row.detail:SetWordWrap(false)
		row.detail:SetPoint("LEFT", row.icon, "RIGHT", 10, -9)
		row:SetScript("OnEnter", function(button)
			button:SetBackdropBorderColor(T.Color(T.BORDER_HI))
			if button.link then
				GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
				GameTooltip:SetHyperlink(button.link)
				GameTooltip:Show()
			end
		end)
		row:SetScript("OnLeave", function(button)
			button:SetBackdropBorderColor(0.27, 0.24, 0.17, 1)
			GameTooltip:Hide()
		end)
		row:SetScript("OnClick", function(button)
			if button.link and HandleModifiedItemClick then HandleModifiedItemClick(button.link) end
		end)
		return row
	end
	frame.old = { Row(), Row() }
	frame.new = Row()

	frame.arrow = frame:CreateTexture(nil, "ARTWORK")
	frame.arrow:SetSize(16, 16)
	frame.arrow:SetTexture(MEDIA .. "Upgrade.tga")

	frame.rule = T:Rule(frame)
	frame.rule:SetWidth(INNER)
	frame.changes = T:Text(frame, "", "GameFontHighlightSmall", INNER)
	frame.note = T:Text(frame, "", "GameFontDisableSmall", INNER, T.MUTED)

	frame.equip = T:Button(frame, "Equip upgrade", 182, 26, function() self:Equip() end)
	frame.equip:SetPrimary(true)
	frame.equip:SetPoint("BOTTOMRIGHT", -PAD, PAD - 2)
	frame.equip:SetLabelAnchor("LEFT", frame.equip, "LEFT", 14, 0)
	-- The same chip the dialogue hotkeys use, so the key reads as a key.
	local hint = CreateFrame("Frame", nil, frame.equip, "BackdropTemplate")
	frame.spaceHint = hint
	hint:SetSize(44, 16)
	hint:SetPoint("RIGHT", -8, 0)
	hint:SetBackdrop({ bgFile = T.SOLID, edgeFile = T.SOLID, edgeSize = 1 })
	hint:SetBackdropColor(0.07, 0.065, 0.05, 0.92)
	hint:SetBackdropBorderColor(0.65, 0.51, 0.25, 0.7)
	hint.text = T:Text(hint, "Space", "GameFontNormalSmall", 44, T.GOLD)
	hint.text:SetJustifyH("CENTER")
	hint.text:SetPoint("CENTER", 0, 0)
	T:Tip(frame.equip, "Equip upgrade", function()
		local body = "Swaps the item in from your bags. Bind-on-equip items still ask for confirmation."
		if ns.db and ns.db.spaceToEquip then
			body = body .. "\n\nSpace does the same while this prompt is open, so it will not jump until you answer."
		end
		return body
	end)
	frame.later = T:Button(frame, "Keep current", 110, 26, function() self:Dismiss() end)
	frame.later:SetPoint("RIGHT", frame.equip, "LEFT", -8, 0)
	T:Tip(frame.later, "Keep current", "Dismisses this prompt. Use /gw upgrades to review bag upgrades again.")

	-- A one-pixel keyboard listener, armed only while the prompt is up. Every
	-- path that hides the prompt disarms it, because it hangs off OnHide.
	self.keys = CreateFrame("Frame", "GearwiseUpgradeKeys", UIParent)
	self.keys:SetFrameStrata("DIALOG")
	self.keys:SetSize(1, 1)
	self.keys:SetPoint("CENTER")
	self.keys:Hide()

	frame:SetScript("OnShow", function() self:ArmKeys(true) end)
	frame:SetScript("OnHide", function()
		self:ArmKeys(false)
		if GameTooltip.GetOwner then
			local owner = GameTooltip:GetOwner()
			if owner == frame.new or owner == frame.old[1] or owner == frame.old[2] then GameTooltip:Hide() end
		end
	end)
	return frame
end

---------------------------------------------------------------------------
-- Space to equip
---------------------------------------------------------------------------
-- The same rules the NPC dialogue hotkeys use: the key is only taken while the
-- prompt is actually on screen, and never while something else owns the
-- keyboard. Gossip and quest windows are listed too, so the dialogue hotkeys
-- keep Space to themselves whenever both could be open.
local function KeyBlocked()
	if InCombatLockdown() then return true end
	if GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() then return true end
	for _, panel in ipairs({ GameMenuFrame or false, SettingsPanel or false, InterfaceOptionsFrame or false,
		ColorPickerFrame or false, WorldMapFrame or false, GossipFrame or false, QuestFrame or false,
		MerchantFrame or false, TradeFrame or false, MiniQoL and MiniQoL.panel or false }) do
		if panel and panel.IsVisible and panel:IsVisible() then return true end
	end
	if InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() then return true end
	for index = 1, STATICPOPUP_NUMDIALOGS or 4 do
		local popup = _G["StaticPopup" .. index]
		if popup and popup:IsVisible() then return true end
	end
	return false
end

function Upgrades:KeyDown(key)
	self.keys:SetPropagateKeyboardInput(true)
	local normalized = key == "SPACE" and key or nil
	if not normalized then return end
	if (IsAltKeyDown and IsAltKeyDown()) or (IsControlKeyDown and IsControlKeyDown())
		or (IsShiftKeyDown and IsShiftKeyDown()) then return end
	if not self.frame or not self.frame:IsShown() or not self.current then return end
	if KeyBlocked() then return end
	-- Swallow the repeat as well as the press, so holding Space cannot equip
	-- twice or fall through to a jump.
	self.keys:SetPropagateKeyboardInput(false)
	if self.held then return end
	self.held = true
	self:Equip()
end

function Upgrades:ArmKeys(on)
	local input = self.keys
	if not input then return end
	self.held = nil
	if on and ns.db and ns.db.spaceToEquip and not InCombatLockdown() then
		input:SetPropagateKeyboardInput(true)
		input:SetScript("OnKeyDown", function(_, key) self:KeyDown(key) end)
		input:SetScript("OnKeyUp", function(_, key)
			if key == "SPACE" then self.held = nil end
			if not InCombatLockdown() then input:SetPropagateKeyboardInput(true) end
		end)
		input:EnableKeyboard(true)
		input:Show()
	else
		-- Forever can dispatch keys to any frame that still holds an OnKeyDown
		-- script, so clear them rather than only disabling the keyboard.
		input:SetScript("OnKeyDown", nil)
		input:SetScript("OnKeyUp", nil)
		input:EnableKeyboard(false)
		input:Hide()
		if not InCombatLockdown() then input:SetPropagateKeyboardInput(true) end
	end
	if self.frame and self.frame.spaceHint then
		self.frame.spaceHint:SetShown(ns.db and ns.db.spaceToEquip and true or false)
	end
end

-- Re-applies the hotkey setting to a prompt that is already on screen.
function Upgrades:RefreshKeys()
	self:ArmKeys(self.frame ~= nil and self.frame:IsShown())
end

-- "Upgrade 1 of 4" once more than one candidate is waiting, so dismissing the
-- prompt does not look like it threw the rest away.
function Upgrades:UpdateQueueBadge()
	local frame = self.frame
	if not frame or not frame.subtitle then return end
	local waiting = #self.queue
	frame.subtitle:SetText(waiting > 0 and ("Upgrade 1 of " .. (waiting + 1)) or "Upgrade found in your bags")
end

function Upgrades:Show(result)
	local frame = self.frame or self:CreateFrame()
	local T = MiniQoL.Theme
	self.result = result

	local function Fill(row, link, detail)
		row.link = link
		local item = link and ns.Items:Get(link)
		row.icon:SetTexture(item and item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		local color = link and T:QualityColor(link) or T.MUTED
		row.name:SetText(link and (item and item.name or T:StripColor(link)) or "Nothing equipped")
		row.name:SetTextColor(T.Color(color))
		row.iconEdge:SetBackdropBorderColor(T.Color(color, link and 0.8 or 0.4))
		row.detail:SetText(detail or "")
		row:Show()
	end

	-- Every row is re-anchored on each prompt, so clear the previous point first.
	local function Place(region, y, x, point, relativePoint)
		region:ClearAllPoints()
		region:SetPoint(point or "TOPLEFT", frame, relativePoint or "TOPLEFT", x or PAD, -y)
	end

	local twoHanded = #result.oldLinks > 1
	local slotLabel = SLOT_NAMES[result.slot] or "Equipment"
	local y = HEADER + 11 + 38 + 13

	frame.fromHeading:SetText(#result.oldLinks > 0 and "REPLACING" or "EMPTY SLOT")
	Place(frame.fromHeading, y)
	y = y + 15
	Place(frame.old[1], y)
	Fill(frame.old[1], result.oldLinks[1], twoHanded and "Main hand" or slotLabel)
	y = y + ROW_HEIGHT
	if twoHanded then
		y = y + 4
		Place(frame.old[2], y)
		Fill(frame.old[2], result.oldLinks[2], "Off hand")
		y = y + ROW_HEIGHT
	else
		frame.old[2]:Hide()
	end

	y = y + 6
	Place(frame.arrow, y, PAD + 6 + ICON_SIZE / 2, "TOP")
	y = y + 18

	Place(frame.toHeading, y)
	y = y + 15
	Place(frame.new, y)
	Fill(frame.new, self.current.link, "In your bags")
	y = y + ROW_HEIGHT + 12

	Place(frame.rule, y)
	y = y + 11

	local changes = ns.Display:Changes(result, math.huge, 2)
	Place(frame.changes, y)
	frame.changes:SetText(#changes > 0 and table.concat(changes, "\n") or "No base stat changes.")
	y = y + math.max(14, frame.changes:GetStringHeight())

	local notes = {}
	if twoHanded then notes[#notes + 1] = "Replaces both weapon slots." end
	if result.effects then notes[#notes + 1] = "Use effects and set bonuses are not scored." end
	frame.note:SetText(table.concat(notes, "\n"))
	Place(frame.note, y + 7)
	if #notes > 0 then y = y + 7 + frame.note:GetStringHeight() end

	if result.percent then
		frame.score.value:SetText(("+%.1f%%"):format(result.percent))
		frame.score.value:SetTextColor(T.Color(T.GOOD))
	else
		frame.score.value:SetText(result.empty and "New gear" or "Upgrade")
		frame.score.value:SetTextColor(T.Color(T.GOLD))
	end
	frame.score.caption:SetText(ns.profile.label .. " " .. ns.profile.className .. "  \194\183  " .. slotLabel)
	self:UpdateQueueBadge()

	frame:SetHeight(y + 14 + 26 + PAD)
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

end)
