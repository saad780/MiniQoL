-- Mini QoL packaging adapter; upstream source and credits follow.
MiniQoLRuntime:Execute("Gearwise", function(...)
-- Equal-value look offers. When a looted item scores the same as what you are
-- wearing, the stats cannot decide it for you, so the choice is yours: a small
-- badge waits at the edge of the screen, and hovering it shows your character
-- wearing each version side by side. Accept or decline, and a declined item
-- never asks again.
local _, ns = ...
local Sidegrades = { offers = {}, shown = {}, waiting = {}, badges = {} }
ns.Sidegrades = Sidegrades

local BADGE, BADGE_GAP = 34, 5
local PANEL_W, PANEL_H, PAD = 292, 308, 15
local MODEL_W, MODEL_H, MODEL_GAP = 122, 162, 18
local READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local DECLINE = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local MAX_OFFERS = 6
-- The model loads your character in the background and dresses it in what you
-- wear once it arrives, which undoes a try-on made before then. The preview
-- puts the item on again at these points after each load, and keeps at it a
-- little longer while the item's look is still loading.
local TRY_AGAIN, GIVE_UP = { 0.05, 0.15, 0.35, 0.7, 1.2, 2 }, 5
-- Without a hand named, trying on a one-hander twice fills both hands.
local HAND = { [16] = "MAINHANDSLOT", [17] = "SECONDARYHANDSLOT" }
-- Neck, rings and trinkets: nothing to see on the character.
local UNSEEN = { [2] = true, [11] = true, [12] = true, [13] = true, [14] = true }
local REASON = Enum and Enum.ItemTryOnReason or {}
local WRONG_RACE, NOT_WEARABLE = REASON.WrongRace or 1, REASON.NotEquippable or 2
local LOADING = REASON.DataPending or 3

local function Theme() return MiniQoL.Theme end

local function ItemID(link)
	return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

---------------------------------------------------------------------------
-- Declined items
---------------------------------------------------------------------------
function Sidegrades:Declined(id)
	local list = ns.db and ns.db.styleRejected
	return type(list) == "table" and list[id] == true
end

function Sidegrades:Decline(id)
	if not id then return end
	ns.db.styleRejected = ns.db.styleRejected or {}
	ns.db.styleRejected[id] = true
end

function Sidegrades:ClearDeclined()
	local count = 0
	for _ in pairs(ns.db.styleRejected or {}) do count = count + 1 end
	ns.db.styleRejected = {}
	return count
end

---------------------------------------------------------------------------
-- Character preview
---------------------------------------------------------------------------
-- Both models turn together, so the two looks are always compared from the
-- same angle.
function Sidegrades:SetFacing(facing)
	self.facing = facing
	for _, model in ipairs(self.models or {}) do
		if model.SetFacing then pcall(model.SetFacing, model, facing) end
	end
end

-- A line over the model, for when it cannot show the difference.
function Sidegrades:Note(model, text)
	if not model.note then return end
	model.note.text:SetText(text or "")
	model.note:SetShown(text ~= nil)
end

-- Your character as you are now, plus, for the preview, the looted item in the
-- slot it would go to.
function Sidegrades:Dress(model, link, slot)
	if not model.SetUnit then return end
	model.tryOn, model.hand = link, HAND[slot]
	model.refused, model.loading = false, false
	self:Note(model, nil)
	pcall(model.SetUnit, model, "player")
	-- Takes off what the last offer tried on, when the model was already loaded.
	if model.Dress then pcall(model.Dress, model) end
	self:TryOn(model)
	self:Settle(model)
	if model.SetFacing then pcall(model.SetFacing, model, self.facing or 0.4) end
end

function Sidegrades:TryOn(model)
	if not model.tryOn then return end
	if not model.TryOn then model.refused = true; return end
	local ok, reason = pcall(model.TryOn, model, model.tryOn, model.hand)
	if not ok and model.hand then ok, reason = pcall(model.TryOn, model, model.tryOn) end
	-- Before the character arrives the answer can be a refusal; only the last
	-- one counts.
	model.refused = not ok or reason == WRONG_RACE or reason == NOT_WEARABLE
	model.loading = ok and reason == LOADING
	if not model.refused and not model.loading then self:Note(model, nil) end
end

-- Starts the try-on schedule over, after a dressing or a load.
function Sidegrades:Settle(model)
	model.since, model.step = 0, 1
	model.due = model.tryOn and TRY_AGAIN[1] or nil
end

function Sidegrades:Retry(model, elapsed)
	model.since = model.since + elapsed
	if model.since < model.due then return end
	self:TryOn(model)
	model.step = model.step + 1
	model.due = TRY_AGAIN[model.step]
	if not model.due and model.loading and model.since < GIVE_UP then model.due = model.since + 0.5 end
	if model.due then return end
	if model.refused then
		self:Note(model, "Can't be shown on your character.")
	elseif model.loading then
		self:Note(model, "Still loading. Hover again in a moment.")
	end
end

function Sidegrades:CreateModel(parent, x)
	local T = Theme()
	local created, model = pcall(CreateFrame, "DressUpModel", nil, parent)
	if not created or not model then return nil end
	model:SetSize(MODEL_W, MODEL_H)
	model:SetPoint("TOPLEFT", x, -(28 + 10))
	if model.SetPortraitZoom then pcall(model.SetPortraitZoom, model, 0) end
	if model.SetPosition then pcall(model.SetPosition, model, 0, 0, -0.1) end
	model:EnableMouse(true)
	model:EnableMouseWheel(false)

	local border = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	border:SetPoint("TOPLEFT", model, -1, 1)
	border:SetPoint("BOTTOMRIGHT", model, 1, -1)
	border:SetFrameLevel(math.max(0, model:GetFrameLevel() - 1))
	T:Chrome(border, { 0.03, 0.028, 0.024, 0.9 }, { 0.27, 0.24, 0.17, 1 })

	model:SetScript("OnMouseDown", function(self)
		self.dragX = GetCursorPosition()
		Sidegrades.turning = true
	end)
	model:SetScript("OnMouseUp", function(self)
		self.dragX = nil
		Sidegrades.turning = false
	end)
	model:SetScript("OnUpdate", function(self, elapsed)
		if self.due then Sidegrades:Retry(self, elapsed or 0) end
		if not self.dragX then return end
		local x = GetCursorPosition()
		if x == self.dragX then return end
		Sidegrades:SetFacing((Sidegrades.facing or 0.4) + (x - self.dragX) * 0.012)
		self.dragX = x
	end)
	-- SetUnit loads asynchronously; re-apply the preview once the model arrives.
	model:SetScript("OnModelLoaded", function(self)
		Sidegrades:TryOn(self)
		Sidegrades:Settle(self)
		if self.SetFacing then pcall(self.SetFacing, self, Sidegrades.facing or 0.4) end
	end)

	-- Its own frame, so the line sits above the character rather than behind it.
	model.note = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	model.note:SetPoint("BOTTOMLEFT", model, 6, 6)
	model.note:SetPoint("BOTTOMRIGHT", model, -6, 6)
	model.note:SetHeight(40)
	model.note:SetFrameLevel(model:GetFrameLevel() + 2)
	T:Chrome(model.note, { 0.05, 0.045, 0.038, 0.92 }, T.BORDER)
	model.note.text = T:Text(model.note, "", "GameFontDisableSmall", MODEL_W - 24, T.MUTED)
	model.note.text:SetJustifyH("CENTER")
	model.note.text:SetJustifyV("MIDDLE")
	model.note.text:SetPoint("CENTER", 0, 0)
	model.note:Hide()
	return model
end

---------------------------------------------------------------------------
-- The hover panel
---------------------------------------------------------------------------
function Sidegrades:CreatePanel()
	local T = Theme()
	local panel = CreateFrame("Frame", "GearwiseStylePanel", UIParent, "BackdropTemplate")
	self.panel = panel
	panel:Hide()
	panel:SetSize(PANEL_W, PANEL_H)
	panel:SetFrameStrata("DIALOG")
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	T:Window(panel, 28)

	panel.title = T:Text(panel, "Same value, different look", "GameFontNormalSmall", 178, T.GOLD)
	panel.title:SetWordWrap(false)
	panel.title:SetPoint("TOPLEFT", PAD, -9)
	panel.hint = T:Text(panel, "drag to turn", "GameFontDisableSmall", 76, T.FAINT)
	panel.hint:SetJustifyH("RIGHT")
	panel.hint:SetWordWrap(false)
	panel.hint:SetPoint("TOPRIGHT", -PAD, -10)

	self.models = {}
	local left = self:CreateModel(panel, PAD)
	local right = self:CreateModel(panel, PAD + MODEL_W + MODEL_GAP)
	if left then self.models[#self.models + 1] = left end
	if right then self.models[#self.models + 1] = right end
	panel.currentModel, panel.previewModel = left, right
	if not left or not right then
		-- No character preview on this client: say so rather than show a hole.
		panel.fallback = T:Text(panel, "Character preview is unavailable on this client.",
			"GameFontDisableSmall", PANEL_W - 30, T.MUTED)
		panel.fallback:SetPoint("TOPLEFT", PAD, -46)
	end

	local function Column(x, caption)
		local column = {}
		column.caption = T:Text(panel, caption, "GameFontDisableSmall", MODEL_W, T.GOLD_SOFT)
		column.caption:SetJustifyH("CENTER")
		column.caption:SetPoint("TOPLEFT", x, -(38 + MODEL_H + 6))
		column.name = T:Text(panel, "", "GameFontHighlightSmall", MODEL_W)
		column.name:SetJustifyH("CENTER")
		column.name:SetWordWrap(false)
		column.name:SetPoint("TOPLEFT", x, -(38 + MODEL_H + 20))
		-- Only the caption strip carries the tooltip; the model itself belongs
		-- to click-and-drag turning.
		column.hit = CreateFrame("Button", nil, panel)
		column.hit:SetPoint("TOPLEFT", x, -(38 + MODEL_H + 4))
		column.hit:SetSize(MODEL_W, 30)
		column.hit:SetScript("OnEnter", function(button)
			if not button.link then return end
			GameTooltip:SetOwner(button, "ANCHOR_LEFT")
			GameTooltip:SetHyperlink(button.link)
			GameTooltip:Show()
		end)
		column.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return column
	end
	panel.current = Column(PAD, "EQUIPPED")
	panel.preview = Column(PAD + MODEL_W + MODEL_GAP, "IF YOU SWAP")

	panel.rule = T:Rule(panel)
	panel.rule:SetWidth(PANEL_W - PAD * 2)
	panel.rule:SetPoint("TOPLEFT", PAD, -(38 + MODEL_H + 42))
	panel.footnote = T:Text(panel, "", "GameFontDisableSmall", PANEL_W - PAD * 2, T.MUTED)
	panel.footnote:SetWordWrap(false)
	panel.footnote:SetPoint("TOPLEFT", PAD, -(38 + MODEL_H + 50))

	local function Action(texture, label, x, onClick)
		local button = T:Button(panel, label, 128, 26, onClick)
		button:SetPoint("TOPLEFT", x, -(38 + MODEL_H + 72))
		button.icon = button:CreateTexture(nil, "OVERLAY")
		button.icon:SetSize(15, 15)
		button.icon:SetPoint("LEFT", 9, 0)
		button.icon:SetTexture(texture)
		button:SetLabelAnchor("LEFT", button.icon, "RIGHT", 7, 0)
		return button
	end
	panel.accept = Action(READY, "Wear the new one", PAD, function() Sidegrades:Accept(self.active) end)
	panel.accept:SetPrimary(true)
	T:Tip(panel.accept, "Wear the new one", "Equips the looted item. Your current one goes to your bags.")
	panel.decline = Action(DECLINE, "Keep mine", PAD + 128 + 6, function() Sidegrades:Reject(self.active) end)
	T:Tip(panel.decline, "Keep mine", "Dismisses this offer, and never asks about this item again. Use /gw styles reset to start over.")

	-- Stay open while the pointer is anywhere over the badge or the panel, so
	-- there is time to reach the buttons and turn the models.
	panel:SetScript("OnUpdate", function(self, elapsed)
		if Sidegrades.turning or self:IsMouseOver()
			or (Sidegrades.hovered and Sidegrades.hovered:IsMouseOver()) then
			self.away = 0
			return
		end
		self.away = (self.away or 0) + elapsed
		if self.away > 0.35 then Sidegrades:HidePanel() end
	end)
	return panel
end

function Sidegrades:HidePanel()
	if not self.panel then return end
	self.panel:Hide()
	self.active, self.hovered = nil, nil
	GameTooltip:Hide()
end

function Sidegrades:ShowPanel(offer, badge)
	if InCombatLockdown() then return end
	local T = Theme()
	local panel = self.panel or self:CreatePanel()
	-- Back on the same badge: leave the models as they are, turned or not.
	if panel:IsShown() and self.active == offer then
		self.hovered, panel.away = badge, 0
		return
	end
	self.active, self.hovered, self.turning = offer, badge, false
	self.facing = 0.4

	local oldLink = offer.result.oldLinks[1]
	local oldItem = oldLink and ns.Items:Get(oldLink)
	local newItem = ns.Items:Get(offer.link)
	panel.current.hit.link = oldLink
	panel.preview.hit.link = offer.link
	panel.current.name:SetText(oldLink and (oldItem and oldItem.name or "Equipped item") or "Nothing equipped")
	panel.current.name:SetTextColor(T.Color(oldLink and T:QualityColor(oldLink) or T.MUTED))
	panel.preview.name:SetText(newItem and newItem.name or "New item")
	panel.preview.name:SetTextColor(T.Color(T:QualityColor(offer.link)))

	local slot = offer.result.slot
	local slotName = ns.slotNames and ns.slotNames[slot] or "Equipment"
	panel.footnote:SetText(slotName .. "  \194\183  identical score for " .. (ns.profile and ns.profile.label or "your build"))

	panel:ClearAllPoints()
	local centre = badge:GetCenter()
	local middle = (UIParent:GetWidth() or 1024) / 2
	if centre and centre > middle then
		panel:SetPoint("TOPRIGHT", badge, "TOPLEFT", -8, 8)
	else
		panel:SetPoint("TOPLEFT", badge, "TOPRIGHT", 8, 8)
	end
	panel.away = 0
	panel:Show()
	-- Dressed only once shown: a model reloads the character when it appears,
	-- which would undo anything tried on while it was hidden.
	if panel.currentModel then self:Dress(panel.currentModel, nil) end
	local preview = panel.previewModel
	if preview then
		self:Dress(preview, not UNSEEN[slot] and offer.link or nil, slot)
		if UNSEEN[slot] then self:Note(preview, "This doesn't show on your character.") end
	end
end

---------------------------------------------------------------------------
-- Badges
---------------------------------------------------------------------------
function Sidegrades:Anchor()
	if self.anchor then return self.anchor end
	local anchor = CreateFrame("Frame", "GearwiseStyleAnchor", UIParent)
	self.anchor = anchor
	anchor:SetSize(BADGE, BADGE)
	anchor:SetMovable(true)
	anchor:SetClampedToScreen(true)
	local saved = ns.db.stylePosition
	if type(saved) == "table" and #saved == 4 then
		anchor:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
	else
		anchor:SetPoint("RIGHT", UIParent, "RIGHT", -26, 60)
	end
	return anchor
end

function Sidegrades:Badge(index)
	local badge = self.badges[index]
	if badge then return badge end
	local T = Theme()
	badge = CreateFrame("Button", nil, self:Anchor(), "BackdropTemplate")
	self.badges[index] = badge
	badge:SetSize(BADGE, BADGE)
	T:Chrome(badge, { 0.05, 0.045, 0.038, 0.95 }, T.GOLD_SOFT)
	badge:RegisterForDrag("LeftButton")
	badge.icon = badge:CreateTexture(nil, "ARTWORK")
	badge.icon:SetPoint("TOPLEFT", 3, -3)
	badge.icon:SetPoint("BOTTOMRIGHT", -3, 3)
	badge.icon:SetTexCoord(0.09, 0.91, 0.09, 0.91)
	-- A small "=" corner chip: this item is worth the same, nothing more.
	badge.chip = CreateFrame("Frame", nil, badge, "BackdropTemplate")
	badge.chip:SetSize(13, 11)
	badge.chip:SetPoint("BOTTOMRIGHT", 1, -1)
	badge.chip:SetFrameLevel(badge:GetFrameLevel() + 2)
	T:Chrome(badge.chip, { 0.05, 0.045, 0.038, 1 }, T.GOLD_SOFT)
	badge.chip.glyph = T:Text(badge.chip, "=", "GameFontNormalSmall", 13, T.GOLD)
	badge.chip.glyph:SetJustifyH("CENTER")
	badge.chip.glyph:SetPoint("CENTER", 0, 0)
	badge:SetScript("OnEnter", function(button)
		button:SetBackdropBorderColor(T.Color(T.BORDER_HI))
		if button.offer then Sidegrades:ShowPanel(button.offer, button) end
	end)
	badge:SetScript("OnLeave", function(button)
		button:SetBackdropBorderColor(T.Color(T.GOLD_SOFT))
	end)
	badge:SetScript("OnDragStart", function() Sidegrades:HidePanel(); Sidegrades.anchor:StartMoving() end)
	badge:SetScript("OnDragStop", function()
		Sidegrades.anchor:StopMovingOrSizing()
		local point, _, relativePoint, x, y = Sidegrades.anchor:GetPoint()
		ns.db.stylePosition = { point, relativePoint, x, y }
	end)
	return badge
end

function Sidegrades:Layout()
	for index = 1, #self.offers do self:Badge(index) end
	for index, badge in ipairs(self.badges) do
		local offer = self.offers[index]
		badge.offer = offer
		if offer then
			local item = ns.Items:Get(offer.link)
			badge.icon:SetTexture(item and item.icon or QUESTION)
			badge:ClearAllPoints()
			badge:SetPoint("TOP", self:Anchor(), "TOP", 0, -(index - 1) * (BADGE + BADGE_GAP))
			badge:Show()
		else
			badge:Hide()
		end
	end
	if self.anchor then
		self.anchor:SetHeight(math.max(BADGE, #self.offers * (BADGE + BADGE_GAP) - BADGE_GAP))
	end
	if self.active and not self.shown[self.active.key] then self:HidePanel() end
end

function Sidegrades:Clear()
	wipe(self.offers)
	wipe(self.shown)
	wipe(self.waiting)
	self:HidePanel()
	for _, badge in ipairs(self.badges) do badge.offer = nil; badge:Hide() end
end

function Sidegrades:Remove(offer)
	for index, entry in ipairs(self.offers) do
		if entry.key == offer.key then table.remove(self.offers, index); break end
	end
	self.shown[offer.key] = nil
	if self.active and self.active.key == offer.key then self:HidePanel() end
	self:Layout()
end

---------------------------------------------------------------------------
-- Deciding what to offer
---------------------------------------------------------------------------
-- An offer is worth making only when the score is a tie, the item is genuinely
-- a different one, and it has not been declined before.
function Sidegrades:Qualifies(result, link)
	if not result or result.status ~= "equal" then return false end
	local id = ItemID(link)
	if not id or not result.slot then return false end
	if self:Declined(id) then return false end
	for _, oldLink in ipairs(result.oldLinks or {}) do
		if ItemID(oldLink) == id then return false end
	end
	return true, id
end

function Sidegrades:Consider(bags, acquired)
	if not ns.db or not ns.db.styles then
		if #self.offers > 0 then self:Clear() end
		return
	end
	-- Drop offers whose item left the bags, or that a gear change resolved.
	for index = #self.offers, 1, -1 do
		local offer = self.offers[index]
		local location = bags[offer.key]
		local result = location and ns.Compare:Get(location.link)
		if not location or not self:Qualifies(result, location.link) then
			self.shown[offer.key] = nil
			table.remove(self.offers, index)
		else
			offer.result, offer.link = result, location.link
		end
	end

	local pending = self.waiting
	self.waiting = {}
	for _, candidate in ipairs(acquired) do pending[#pending + 1] = candidate end
	for _, candidate in ipairs(pending) do
		local location = bags[candidate.key]
		if location and not self.shown[candidate.key] and #self.offers < MAX_OFFERS then
			local result = ns.Compare:Get(location.link)
			if result.status == "pending" then
				self.waiting[#self.waiting + 1] = candidate
			else
				local ok, id = self:Qualifies(result, location.link)
				if ok then
					self.shown[candidate.key] = true
					self.offers[#self.offers + 1] =
						{ key = candidate.key, link = location.link, id = id, result = result }
				end
			end
		end
	end
	if #self.waiting > 0 then ns.Upgrades:Schedule(0.5) end
	self:Layout()
end

---------------------------------------------------------------------------
-- Answers
---------------------------------------------------------------------------
function Sidegrades:Accept(offer)
	if not offer then return end
	local location = ns.Upgrades.bags and ns.Upgrades.bags[offer.key]
	if not location then self:Remove(offer); return end
	local result = ns.Compare:Get(location.link)
	if result.status ~= "equal" and result.status ~= "upgrade" then self:Remove(offer); return end
	if not ns.Upgrades:EquipLocation(location, result.slot) then return end
	self:Remove(offer)
	ns.Upgrades:Schedule(0.5)
end

function Sidegrades:Reject(offer)
	if not offer then return end
	self:Decline(offer.id)
	self:Remove(offer)
end

---------------------------------------------------------------------------
-- Review and setup
---------------------------------------------------------------------------
-- /gw styles: re-offer every equal-value bag item that has not been declined.
-- Deliberately separate from the upgrade review, which reports its own counts.
function Sidegrades:Review()
	if not ns.db.styles then
		ns.Print("Enable look offers with /gw styles on.")
		return
	end
	ns:Invalidate(true)
	wipe(self.offers)
	wipe(self.shown)
	wipe(self.waiting)
	local counts, bags = ns.Upgrades:Snapshot()
	if not counts then
		ns.Print("Waiting for inventory item data...")
		ns.Upgrades:Schedule(0.5)
		return
	end
	local everything = {}
	for _, candidate in pairs(bags) do everything[#everything + 1] = candidate end
	ns.Upgrades.counts, ns.Upgrades.bags = counts, bags
	self:Consider(bags, everything)
	local count, waiting = #self.offers, #self.waiting
	local message = count > 0
		and ("%d equal-value item%s waiting at the edge of the screen."):format(count, count == 1 and "" or "s")
		or "No equal-value items in your bags to choose between."
	if waiting > 0 then message = message .. (" %d comparison%s still loading."):format(waiting, waiting == 1 and " is" or "s are") end
	ns.Print(message)
end

function Sidegrades:Init()
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then
			self:HidePanel()
			if self.anchor then self.anchor:Hide() end
		elseif self.anchor then
			self.anchor:Show()
		end
	end)
end

end)
