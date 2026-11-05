local _, ns = ...
local Display = { buttons = setmetatable({}, { __mode = "k" }), arrows = setmetatable({}, { __mode = "k" }),
	shades = setmetatable({}, { __mode = "k" }), coins = setmetatable({}, { __mode = "k" }),
	layers = setmetatable({}, { __mode = "k" }), hooks = {} }
ns.Display = Display
local MEDIA = "Interface\\AddOns\\Gearwise\\Media\\"
local labels = { str = "Strength", agi = "Agility", sta = "Stamina", int = "Intellect", spi = "Spirit",
	ap = "Attack power", rap = "Ranged AP", feralAP = "Feral AP", sp = "Spell power", heal = "Healing",
	armor = "Armor", bonusArmor = "Bonus armor", health = "Health", mana = "Mana", mp5 = "Mana / 5 sec",
	hp5 = "Health / 5 sec", dps = "Weapon DPS", crit = "Crit", hit = "Hit", dodge = "Dodge", parry = "Parry",
	block = "Block", defense = "Defense", blockValue = "Block value", critRating = "Crit rating",
	hitRating = "Hit rating", hasteRating = "Haste rating", expertiseRating = "Expertise", dodgeRating = "Dodge rating",
	parryRating = "Parry rating", blockRating = "Block rating", fire = "Fire damage", frost = "Frost damage",
	shadow = "Shadow damage", nature = "Nature damage", arcane = "Arcane damage", holy = "Holy damage",
	holyResist = "Holy resistance", fireResist = "Fire resistance", natureResist = "Nature resistance",
	frostResist = "Frost resistance", shadowResist = "Shadow resistance", arcaneResist = "Arcane resistance" }
local percentStats = { crit = true, hit = true, dodge = true, parry = true, block = true }

function Display:Changes(result, limit, perLine)
	limit, perLine = limit or 6, perLine or 3
	local rows = {}
	for key, value in pairs(result.changes or {}) do
		local duplicateHealing = key == "heal" and math.abs(value - (result.changes.sp or 0)) < 0.01
		if math.abs(value) >= 0.01 and labels[key] and not duplicateHealing then
			local weight = ns.profile.weights[key] or 0
			if key == "dps" then weight = ns.profile.meleeDPS or ns.profile.rangedDPS or (ns.profile.wand and 5) or 0 end
			if key == ns.profile.school then weight = ns.profile.weights.sp or 0 end
			rows[#rows + 1] = { key = key, value = value, importance = math.abs(value * weight) }
		end
	end
	table.sort(rows, function(a, b)
		if a.importance == b.importance then return a.key < b.key end
		return a.importance > b.importance
	end)
	local lines, parts = {}, {}
	for index = 1, math.min(#rows, limit) do
		local row = rows[index]
		local format = math.abs(row.value - math.floor(row.value + 0.5)) < 0.01 and "%+d" or "%+.1f"
		local text = format:format(row.value) .. (percentStats[row.key] and "%" or "") .. " " .. labels[row.key]
		parts[#parts + 1] = (row.value > 0 and "|cff55df82" or "|cffff7777") .. text .. "|r"
		if #parts == perLine or index == math.min(#rows, limit) then
			lines[#lines + 1] = table.concat(parts, "   ")
			parts = {}
		end
	end
	if #rows > limit then lines[#lines + 1] = ("+%d more stat changes"):format(#rows - limit) end
	return lines
end

local function TooltipLink(tooltip, data)
	if TooltipUtil and TooltipUtil.GetDisplayedItem then
		local _, link = TooltipUtil.GetDisplayedItem(tooltip)
		if ns.Text(link) then return link end
	end
	if data and ns.Text(data.hyperlink) then return data.hyperlink end
	if tooltip.GetItem then local _, link = tooltip:GetItem(); if ns.Text(link) then return link end end
end

function Display:Tooltip(tooltip, data)
	if not ns.db or not ns.db.tooltips or not ns.profile or self.inTooltip then return end
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
	local link = TooltipLink(tooltip, data)
	if not link or tooltip.gearwiseAdded then return end
	self.inTooltip = true
	local result = ns.Compare:Get(link)
	self.inTooltip = false
	if result.status == "irrelevant" then return end
	tooltip.gearwiseAdded = true
	tooltip.gearwiseLink = link
	tooltip.gearwiseRevision = ns.revision
	tooltip:AddLine(" ")
	local color, verdict = "|cffadb6c2", "Similar stats"
	local owner = tooltip.GetOwner and tooltip:GetOwner()
	local name = owner and owner.GetName and owner:GetName()
	if name and name:match("^Character.+Slot$") then
		verdict = "Equipped"
	elseif result.status == "upgrade" or result.status == "downgrade" then
		local up = result.status == "upgrade"
		color = up and "|cff55df82" or "|cffff7777"
		verdict = ("|T%s%s.tga:13:13|t %s"):format(MEDIA, up and "Upgrade" or "Downgrade", up and "Upgrade" or "Downgrade")
		if result.percent then verdict = verdict .. ("  %+.1f%% score"):format(result.percent)
		elseif result.empty then verdict = verdict .. "  Empty slot" end
	elseif result.status == "pending" then verdict = "Loading item data..."
	elseif result.status == "unusable" or result.status == "unsupported" then verdict = result.reason or "Cannot compare" end
	tooltip:AddDoubleLine("|cff8bc5e8Gearwise|r", color .. verdict .. "|r")
	tooltip:AddLine(ns.profile.label .. " " .. ns.profile.className .. (ns.profile.leveling and "  /  Leveling" or ""), 0.65, 0.69, 0.74)
	if verdict ~= "Equipped" then
		if result.oldLinks and #result.oldLinks > 0 then
			local slotLabel = result.slot == 17 and "Off hand" or (result.slot == 16 and "Main hand" or "Replaces")
			tooltip:AddLine(slotLabel .. ": " .. table.concat(result.oldLinks, " + "), 0.7, 0.73, 0.77, true)
		end
		for _, line in ipairs(self:Changes(result)) do tooltip:AddLine(line, 1, 1, 1, true) end
		if result.effects then tooltip:AddLine("Stat estimate; special effects and set bonuses need comparison.", 0.65, 0.69, 0.74, true) end
	end
end

local function BagLocation(button)
	if button.info and button.info.cached then return nil end
	local bag = button.GetBagID and button:GetBagID() or (button.GetBag and button:GetBag()) or button.bagID or button.bag
	if bag == nil and button.GetParent then
		local parent = button:GetParent()
		local name = parent and parent.GetName and parent:GetName()
		if name and name:match("^ContainerFrame%d+$") then bag = parent:GetID() end
	end
	if not ns.Number(bag) then return nil end
	if bag < 0 or bag > (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) then return nil end
	if button.IsCached then
		local ok, cached = pcall(button.IsCached, button)
		if not ok or cached then return nil end
	end
	local slot = button.GetSlotID and button:GetSlotID() or (button.GetID and button:GetID())
	if not ns.Number(slot) or slot < 1 then return nil end
	return bag, slot
end

function Display:Track(button, kind)
	if not button or not button.CreateTexture then return end
	local previous = self.buttons[button]
	if kind == "quest" or button.type == "choice" or button.type == "reward" then
		self.buttons[button] = "quest"
	else
		local ok, bag = pcall(BagLocation, button)
		if ok and bag ~= nil then self.buttons[button] = "bag" end
	end
	if not previous and self.buttons[button] then
		button:HookScript("OnShow", function() self:Schedule() end)
		button:HookScript("OnHide", function() self:Arrow(button); self:Shade(button); self:Coin(button) end)
		self:Schedule()
	end
end

function Display:QuestLog(button)
	local parent = button
	for depth = 1, 8 do
		if not parent then break end
		if parent == MapQuestInfoRewardsFrame then return true end
		if parent == QuestInfoRewardsFrame or parent == QuestFrameRewardPanel or parent == QuestFrameDetailPanel then return false end
		parent = parent.GetParent and parent:GetParent()
	end
	return QuestInfoFrame and QuestInfoFrame.questLog or false
end

function Display:QuestReward(button)
	if button.objectType and button.objectType ~= "item" then return nil end
	local kind, index = button.type, button:GetID()
	if kind ~= "choice" and kind ~= "reward" then return nil end
	if not ns.Number(index) or index <= 0 then return nil end
	local fromLog = self:QuestLog(button)
	local getLink, query
	if fromLog then
		getLink = GetQuestLogItemLink
		if kind == "choice" then query = GetQuestLogChoiceInfo else query = GetQuestLogRewardInfo end
	else getLink, query = GetQuestItemLink, GetQuestItemInfo end
	local link
	if getLink then
		local ok, value = pcall(getLink, kind, index)
		if ok then link = ns.Text(value) end
	end
	local info = query and (fromLog and { pcall(query, index) } or { pcall(query, kind, index) }) or {}
	local count = info[1] and ns.Number(info[4]) and info[4] > 0 and info[4] or 1
	local id = info[1] and info[7]
	-- Reward links can lag behind the icon/item ID while the quest window loads.
	if not link and ns.Number(id) and id > 0 then link = "item:" .. id end
	return link, count
end

function Display:Link(button, kind)
	if kind == "bag" then
		local bag, slot = BagLocation(button)
		if bag == nil then return nil end
		local getLink = C_Container and C_Container.GetContainerItemLink or GetContainerItemLink
		return getLink and getLink(bag, slot)
	end
	return self:QuestReward(button)
end

function Display:Icon(button)
	for _, key in ipairs({ "Icon", "icon", "IconTexture", "iconTexture" }) do
		local icon = button[key]
		if icon and (type(icon) == "table" or type(icon) == "userdata") and icon.GetObjectType then return icon end
	end
	local name = button.GetName and button:GetName()
	return (name and (_G[name .. "IconTexture"] or _G[name .. "Icon"])) or button
end

function Display:Shade(button, result)
	local shade = self.shades[button]
	if not ns.db.unusable or not result or result.status ~= "unusable" then
		if shade then shade:Hide() end
		return
	end
	if not shade then
		if InCombatLockdown() then return end
		shade = button:CreateTexture(nil, "OVERLAY", nil, 6)
		shade:SetColorTexture(0.9, 0.03, 0.03, 0.20)
		self.shades[button] = shade
	end
	shade:SetAllPoints(self:Icon(button))
	shade:Show()
end

function Display:Layer(button)
	if not self.layers[button] then
		local layer = CreateFrame("Frame", nil, button)
		layer:SetAllPoints(button)
		layer:EnableMouse(false)
		-- Reward buttons can have child art/glows above their own texture layers.
		layer:SetFrameLevel(button:GetFrameLevel() + 10)
		self.layers[button] = layer
	end
	return self.layers[button]
end

function Display:Coin(button, show)
	local coin = self.coins[button]
	if not show then if coin then coin:Hide() end; return end
	if not coin then
		if InCombatLockdown() then return end
		coin = self:Layer(button):CreateTexture(nil, "OVERLAY", nil, 7)
		coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
		coin:SetSize(15, 15)
		self.coins[button] = coin
	end
	coin:ClearAllPoints()
	coin:SetPoint("BOTTOMLEFT", self:Icon(button), "BOTTOMLEFT", -1, -1)
	coin:Show()
end

function Display:Arrow(button, result)
	local arrow = self.arrows[button]
	local direction = result and ((result.status == "upgrade" and "Upgrade") or (result.status == "downgrade" and "Downgrade"))
	if not direction then if arrow then arrow:Hide() end; return end
	if not arrow then
		if InCombatLockdown() then return end
		arrow = self:Layer(button):CreateTexture(nil, "OVERLAY", nil, 7)
		arrow:SetSize(18, 18)
		self.arrows[button] = arrow
	end
	arrow:ClearAllPoints()
	arrow:SetPoint("TOPRIGHT", self:Icon(button), "TOPRIGHT", 1, 1)
	arrow:SetTexture(MEDIA .. direction .. ".tga")
	arrow:Show()
end

function Display:Discover()
	local function Add(button) if button then self:Track(button, "quest") end end
	local function Root(root)
		if root and root:IsShown() and root.RewardButtons then
			for i = 1, #root.RewardButtons do Add(rawget(root.RewardButtons, i)) end
		end
	end
	Root(QuestInfoRewardsFrame)
	Root(MapQuestInfoRewardsFrame)
	if QuestInfoFrame then Root(QuestInfoFrame.rewardsFrame) end
	for i = 1, 20 do
		for _, prefix in ipairs({ "QuestInfoRewardsFrameQuestInfoItem", "MapQuestInfoRewardsFrameQuestInfoItem",
			"QuestInfoItem", "QuestRewardItem", "QuestChoiceItem", "QuestLogItem" }) do
			local button = _G[prefix .. i]
			if button and button:IsShown() then Add(button) end
		end
	end
	for index = 1, (NUM_CONTAINER_FRAMES or 13) do
		local frame = _G["ContainerFrame" .. index]
		if frame and frame:IsShown() then
			if frame.EnumerateValidItems then
				for _, button in frame:EnumerateValidItems() do self:Track(button) end
			else
				for _, button in pairs(frame.Items or {}) do self:Track(button) end
				for slot = 1, math.max(40, frame.size or 0) do self:Track(_G["ContainerFrame" .. index .. "Item" .. slot]) end
			end
		end
	end
	local combined = ContainerFrameCombinedBags
	if combined and combined:IsShown() then
		if combined.EnumerateValidItems then
			for _, button in combined:EnumerateValidItems() do self:Track(button) end
		else
			for _, button in pairs(combined.Items or {}) do self:Track(button) end
		end
	end
	-- Bagnon creates its own buttons, and existing buttons can predate our hooks.
	-- Walk only its visible inventory, not every UI frame in the game.
	local function Children(frame, depth)
		if not frame or not frame.GetChildren or depth > 7 or not frame:IsShown() then return end
		if frame.bag ~= nil or frame.GetBagID or frame.GetBag then self:Track(frame) end
		local function Visit(...)
			for index = 1, select("#", ...) do Children(select(index, ...), depth + 1) end
		end
		Visit(frame:GetChildren())
	end
	for _, name in ipairs({ "Bagnon", "BagBrother" }) do
		local addon = _G[name]
		if addon and addon.Frames and addon.Frames.Get then Children(addon.Frames:Get("inventory"), 0) end
	end
end

function Display:Update()
	if not ns.profile then return end
	self:Discover()
	local choices = {}
	for button, kind in pairs(self.buttons) do
		self:Coin(button)
		if not button:IsVisible() then
			self:Arrow(button)
			self:Shade(button)
		else
			local ok, link = pcall(self.Link, self, button, kind)
			local result = ok and link and ns.Compare:Get(link) or nil
			self:Arrow(button, ((kind == "bag" and ns.db.bags) or (kind == "quest" and ns.db.quests)) and result or nil)
			self:Shade(button, result)
			if kind == "quest" and ns.db.quests and button.type == "choice"
				and (not button.objectType or button.objectType == "item") then
				local parent = button:GetParent() or button
				local group = choices[parent]
				if not group then group = {}; choices[parent] = group end
				local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
				local info = ok and link and getInfo and { getInfo(link) } or {}
				local _, count = self:QuestReward(button)
				if not ns.Number(info[11]) then group.pending = true
				else
					local value = info[11] * count
					local index = button:GetID()
					if value > 0 and (not group.value or value > group.value or (value == group.value and index < group.index)) then
						group.best, group.value, group.index = button, value, index
					end
				end
			end
		end
	end
	for _, group in pairs(choices) do
		if not group.pending and group.best then self:Coin(group.best, true) end
	end
	for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
		if tooltip:IsShown() and tooltip.gearwiseLink and tooltip.gearwiseRevision ~= ns.revision
			and tooltip.RebuildFromTooltipInfo then
			pcall(tooltip.RebuildFromTooltipInfo, tooltip)
		end
	end
end

function Display:Schedule()
	if self.pending or not ns.loggedIn then return end
	self.pending = true
	C_Timer.After(0.1, function() self.pending = false; self:Update() end)
end

function Display:InstallHooks()
	local function Hook(target, method, callback)
		local key = tostring(target) .. ":" .. method
		if target and type(target[method]) == "function" and not self.hooks[key] then
			self.hooks[key] = true
			hooksecurefunc(target, method, callback)
		end
	end
	for _, method in ipairs({ "SetItemButtonQuality", "SetItemButtonTexture", "SetItemButtonTextureVertexColor" }) do
		Hook(_G, method, function(button) self:Track(button) end)
	end
	for _, method in ipairs({ "Update", "UpdateItemContextMatching", "OnShow", "UpdateItem" }) do
		Hook(ContainerFrameItemButtonMixin, method, function(button) self:Track(button) end)
	end
	for _, method in ipairs({ "QuestInfo_ShowRewards", "QuestInfo_Display", "QuestFrameItems_Update", "QuestLog_Update",
		"ContainerFrame_Update", "ContainerFrame_GenerateFrame", "ToggleAllBags", "OpenAllBags" }) do
		Hook(_G, method, function() self:Discover(); self:Schedule() end)
	end
	for _, name in ipairs({ "QuestInfoRewardsFrame", "MapQuestInfoRewardsFrame", "QuestFrameRewardPanel", "QuestFrameDetailPanel" }) do
		local root = _G[name]
		local key = tostring(root) .. ":GearwiseOnShow"
		if root and root.HookScript and not self.hooks[key] then
			self.hooks[key] = true
			root:HookScript("OnShow", function() self:Discover(); self:Schedule() end)
		end
	end
	-- Bagnon's classes can be installed after its shared BagBrother addon.
	Hook(_G, "QuestInfo_GetRewardButton", function(root, index)
		self:Track(root.RewardButtons and root.RewardButtons[index], "quest")
	end)
	for _, name in ipairs({ "Bagnon", "BagBrother" }) do
		local addon = _G[name]
		if addon then
			for _, class in ipairs({ "Item", "ItemSlot", "ContainerItem" }) do
				Hook(addon[class], "Update", function(button) self:Track(button) end)
			end
		end
	end
end

function Display:Init()
	for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
		tooltip:HookScript("OnTooltipCleared", function(tip)
			tip.gearwiseAdded, tip.gearwiseLink, tip.gearwiseRevision = nil, nil, nil
		end)
	end
	if TooltipDataProcessor and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data) self:Tooltip(tip, data) end)
	else
		for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
			tooltip:HookScript("OnTooltipSetItem", function(tip) self:Tooltip(tip) end)
		end
	end
	self:InstallHooks()
	self:Discover()
	C_Timer.NewTicker(0.5, function() self:Update() end)
end
