-- Mini QoL packaging adapter; upstream source and credits follow.
MiniQoLRuntime:Execute("Wayfinder", function(...)
local _, ns = ...
local Finder = ns.TargetFinder
local Read = Finder.Read
local PAGE = 8
local WAYPOINT = "TargetFinder"
local lastPick = {}

local WatchKey = Finder.EntryKey

-- Scan already sorted individual sightings and merged tokens for the same GUID.
-- One typed fragment can have several distinct names, each with its own cycle.
local function Groups(self)
	local list, groups, matched = {}, {}, {}
	local function group(key, name, kind)
		if not groups[key] then
			local g = { key = key, name = name, kind = kind, hits = {} }
			groups[key], list[#list + 1] = g, g
		end
		return groups[key]
	end
	for _, hit in ipairs(self.hits) do
		local g = group(hit.key, hit.displayName, hit.kind)
		g.hits[#g.hits + 1] = hit
		matched[WatchKey(hit.entry)] = true
	end
	local nearby = #list
	for _, entry in ipairs(self.watches) do
		local lower = entry.name:lower()
		local found = matched[WatchKey(entry)] or groups[entry.kind .. ":" .. lower]
		if not found and entry.kind == "any" then
			for i = 1, nearby do
				if list[i].name:lower():find(lower, 1, true) then found = true; break end
			end
		end
		if not found then group(entry.kind .. ":" .. lower, entry.name, entry.kind) end
	end
	-- Keep the HUD in name order, so a passing mob cannot swap two click targets.
	table.sort(list, function(a, b)
		local liveA, liveB = #a.hits > 0, #b.hits > 0
		if liveA ~= liveB then return liveA end
		if a.name ~= b.name then return a.name < b.name end
		return a.key < b.key
	end)
	return list, groups
end

local function NextHit(hits, previous)
	for i, hit in ipairs(hits) do
		if hit.guid == previous then return hits[i % #hits + 1] end
	end
	return hits[1]
end

local function CanMark()
	return not Read(IsInRaid) or Read(UnitIsGroupLeader, "player") or Read(UnitIsGroupAssistant, "player")
end

local function PlacePin(self, hit)
	if not hit.x then return false end
	local label = hit.displayName .. (hit.approximate and " (nearby)" or "")
	ns.Navigation:PlaceSourceWaypoint(WAYPOINT, hit.c, hit.x, hit.y, label, hit.m, { focus = true })
	self.db.pinKey = hit.key
	return true
end

local function OwnsRow(row, key)
	if row.key == key then return true end
	-- Once the last live match leaves, a typed fragment returns to a dim row.
	local filter = row.key:match("^any:(.+)")
	local name = key and key:match("^[^:]+:(.+)")
	return filter and name and name:find(filter, 1, true)
end

local function SkullUnit(self, owned)
	if Read(UnitGUID, "target") == owned.guid then return "target" end
	local hit = self.hitsByGUID[owned.guid]
	local unit = hit and hit.unit or owned.unit
	if Read(UnitGUID, unit) == owned.guid then return unit end
end

function Finder:CheckRowSkull()
	local owned = self.rowSkull
	if not owned then return end
	local unit = SkullUnit(self, owned)
	if not unit then return end
	local icon = Read(GetRaidTargetIndex, unit)
	if icon == 8 then
		owned.confirmed = true
	elseif owned.confirmed or (icon and icon > 0) or GetTime() - owned.time > 2 then
		self.rowSkull = nil
	end
end

local function Unmark(self, row)
	local key = row.key
	if not key then return end
	if OwnsRow(row, self.db.pinKey) then
		local pin = ns.Navigation:GetSourceWaypoint(WAYPOINT)
		if pin then ns.Navigation:RemoveWaypoint(pin) end
		self.db.pinKey = nil
	end
	if OwnsRow(row, self.markedKey) then self:ClearLocalMark() end
	local owned = self.rowSkull
	if not owned or not OwnsRow(row, owned.key) then return end
	local unit = SkullUnit(self, owned)
	if not unit then return end
	if Read(GetRaidTargetIndex, unit) == 8 then
		if InCombatLockdown() then
			ns.Print("Right-click again after combat to clear the raid skull.")
			return
		end
		if not CanMark() then return end
		row:SetAttribute("macrotext2", "/tm [nocombat,@" .. unit .. ",exists] 0")
	end
end

local function ExactCommand(name, condition)
	if #name <= 120 and not name:find("[%c|;]") and not name:find("^%[") then
		return "/targetexact " .. (condition or "") .. name
	end
end

-- Nameplates identify sightings, but the client cannot acquire a target by
-- nameplate number. Use a targetable alias for a specific spawn when possible.
local aliases = { "target", "mouseover", "focus", "pettarget", "party1target", "party2target", "party3target", "party4target" }
local function TargetAlias(guid)
	for _, unit in ipairs(aliases) do
		if Read(UnitGUID, unit) == guid then return unit end
	end
end

-- Combat keeps the secure icon's last binding. Show and act on the same name.
function Finder:IconHit()
	if not InCombatLockdown() then return self.best end
	local key = self.markButton and self.markButton.combatKey
	if not key then return end
	for _, hit in ipairs(self.hits) do
		if hit.key == key then return hit end
	end
end

function Finder:PreparePick(button)
	local locked = InCombatLockdown()
	self.pendingPick = nil
	if not locked then button:SetAttribute("macrotext1", nil) end
	self.markers = nil
	self:Scan(true)
	local key = button.key
	if button == self.markButton then
		local nearest = self:IconHit()
		key = nearest and nearest.key
	end
	if not key then return end
	local hits = {}
	for _, hit in ipairs(self.hits) do
		if hit.key == key then hits[#hits + 1] = hit end
	end
	local hit = NextHit(hits, lastPick[key])
	if not hit then return end
	if hit.kind == "object" then
		PlacePin(self, hit)
		lastPick[key] = hit.guid
		return
	end
	if locked and not button.combatMacro then return end
	local before = Read(UnitGUID, "target")
	local pick = { key = key, button = button, before = before, wanted = hit.guid, candidates = {} }
	for _, candidate in ipairs(hits) do
		pick.candidates[candidate.guid] = Read(GetRaidTargetIndex, candidate.unit) or 0
	end
	self.pendingPick = pick
	if locked then return end
	local alias = TargetAlias(hit.guid)
	local command = alias and ("/target [@" .. alias .. ",exists,nodead] " .. alias) or ExactCommand(hit.displayName)
	if not command then self.pendingPick = nil; return end
	-- Clear an unrelated target before the exact-name search. A failed search
	-- cannot raid-mark the old target, and the final line restores it on a miss.
	local clear = before and alias ~= "target" and (alias or not pick.candidates[before])
	if clear then command = "/cleartarget\n" .. command end
	if not alias then command = command .. "\n/cleartarget [dead]" end
	-- A name-only lookup for an ID-specific quest can land on a different NPC
	-- with the same name. Mark that lookup personally after checking the GUID.
	local plate = Read(C_NamePlate and C_NamePlate.GetNamePlateForUnit, hit.unit)
	local safeToMark = not before or clear or before == hit.guid or (pick.candidates[before] or 0) > 0
	pick.share = safeToMark and (alias or not hit.entry.id) and CanMark()
		and (button == self.markButton or Read(IsInGroup) or Read(IsInRaid) or not plate)
	if pick.share then command = command .. "\n/tm [@target,exists,nodead] ~8" end
	if clear then command = command .. "\n/targetlasttarget [noexists]" end
	button:SetAttribute("macrotext1", command)
end

local function Confirm(self, pick)
	local guid = Read(UnitGUID, "target")
	if not guid or pick.candidates[guid] == nil or (guid == pick.before and guid ~= pick.wanted) then return end
	local hit = self.hitsByGUID[guid]
	if not hit or hit.key ~= pick.key or Read(UnitIsDeadOrGhost or UnitIsDead, "target") ~= false then return end
	self.pendingPick = nil
	lastPick[pick.key] = guid
	if self.markedGUID and self.markedGUID ~= guid then self:ClearLocalMark() end
	local icon = Read(GetRaidTargetIndex, "target")
	if pick.share and pick.candidates[guid] == 0 then
		self.rowSkull = { key = pick.key, guid = guid, unit = hit.unit, time = GetTime(), confirmed = icon == 8 }
	end
	if (not icon or icon == 0) and not self:MarkNameplate(hit) and not pick.share then PlacePin(self, hit) end
	return true
end

function Finder:FinishPick(button)
	if not InCombatLockdown() then button:SetAttribute("macrotext1", button.combatMacro) end
	local pick = self.pendingPick
	if not pick or pick.button ~= button or Confirm(self, pick) then return end
	-- Some clients publish the new hard target on the following frame. A later
	-- click or untrack invalidates this callback before it can paint anything.
	C_Timer.After(0.1, function()
		if self.pendingPick ~= pick then return end
		self:Scan(true)
		Confirm(self, pick)
		self.pendingPick = nil
	end)
end

local function Tooltip(row)
	local g = row.group
	GameTooltip:SetOwner(row, "ANCHOR_LEFT")
	GameTooltip:SetText(row.displayName)
	if g and #g.hits > 0 then
		local hit = NextHit(g.hits, lastPick[row.key])
		local distance = hit.distance and (" (%d yd)"):format(math.sqrt(hit.distance) + 0.5) or ""
		local action = g.kind == "object" and "Place a waypoint" or "Target and mark"
		GameTooltip:AddLine(action .. distance, 0.4, 1, 0.5)
		if #g.hits > 1 then GameTooltip:AddLine("Click again for the next match.", 0.85, 0.85, 0.85) end
	else
		GameTooltip:AddLine("Searching nearby.", 0.8, 0.8, 0.8)
	end
	GameTooltip:AddLine("Right-click to unmark.", 0.85, 0.8, 0.65)
	GameTooltip:AddLine("Middle-click to stop tracking this name.", 0.85, 0.8, 0.65)
	if Finder.namePages > 1 then
		GameTooltip:AddLine(("Scroll for more names (%d/%d)."):format(Finder.namePage, Finder.namePages), 0.85, 0.8, 0.65)
	end
	GameTooltip:Show()
end

local function Anchor(self, row, index)
	local side = self.nameSide
	local offset = 2 + (index - 1) * 21
	row:ClearAllPoints()
	if self.namesAbove then
		row:SetPoint("BOTTOM" .. side, self.markButton, "TOP" .. side, 0, offset)
	else
		row:SetPoint("TOP" .. side, self.markButton, "BOTTOM" .. side, 0, -offset)
	end
end

function Finder:AnchorNames()
	local bottom, right = self.button:GetBottom(), self.button:GetRight()
	self.namesAbove = bottom and bottom < PAGE * 21 + 2
	self.nameSide = right and right < 180 and "LEFT" or "RIGHT"
	for i, row in ipairs(self.nameRows or {}) do Anchor(self, row, i) end
end

local function NewRow(self, index)
	local theme = MiniQoL.Theme
	local row = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate,BackdropTemplate")
	row:SetSize(180, 20)
	Anchor(self, row, index)
	row:SetFrameStrata("MEDIUM")
	row:SetClampedToScreen(true)
	theme:Chrome(row)
	row.label = theme:Text(row, "", "GameFontHighlightSmall", 142, theme.TEXT)
	row.label:SetPoint("LEFT", 6, 0)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)
	row.count = theme:Text(row, "", "GameFontHighlightSmall", nil, theme.GOOD)
	row.count:SetPoint("RIGHT", -5, 0)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row:SetAttribute("type1", "macro")
	row:SetAttribute("type2", "macro")
	-- The physical middle click can hide its own secure row, even in combat.
	row:SetAttribute("type3", "untrack")
	SecureHandlerSetFrameRef(row, "icon", self.markButton)
	row:SetAttribute("_untrack", [[
		self:Hide()
		local icon = self:GetFrameRef("icon")
		if icon:GetAttribute("finderKey") == self:GetAttribute("finderKey") then
			icon:SetAttribute("macrotext1", nil)
		end
	]])
	row:SetAttribute("useOnKeyDown", false)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
	row:SetScript("PreClick", function(b, mouse)
		if mouse == "LeftButton" then self:PreparePick(b)
		elseif mouse == "RightButton" then
			self.pendingPick = nil
			if not InCombatLockdown() then b:SetAttribute("macrotext2", nil) end
			self:Scan(true)
			Unmark(self, b)
		end
	end)
	row:SetScript("PostClick", function(b, mouse)
		if mouse == "LeftButton" then self:FinishPick(b)
		elseif mouse == "MiddleButton" and b.key then
			self.pendingPick, lastPick[b.key] = nil, nil
			self:Untrack(b.key, b.displayName)
		elseif mouse == "RightButton" and not InCombatLockdown() then b:SetAttribute("macrotext2", nil) end
	end)
	row:SetScript("OnEnter", Tooltip)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:EnableMouseWheel(true)
	row:SetScript("OnMouseWheel", function(_, delta)
		if InCombatLockdown() then return end
		self.namePage = math.max(1, math.min(self.namePages, self.namePage - delta))
		self:PaintNames(true)
	end)
	return row
end

local function CombatMacro(g)
	-- Only bind a real creature name. Search fragments stay literal filters.
	local command = g.kind == "mob" and ExactCommand(g.name, "[combat] ")
	if command then return command .. "\n/cleartarget [combat,dead]" end
end

function Finder:PaintNames(pageChanged)
	if not self.markButton then return end
	if #self.watches == 0 then wipe(lastPick) end
	local list, groups = Groups(self)
	local rows = self.nameRows or {}
	self.nameRows = rows
	local locked = InCombatLockdown()
	if not locked then
		local best = self.best
		local key = best and best.key
		if self.markButton.combatKey ~= key then
			self.markButton.combatKey = key
			self.markButton:SetAttribute("finderKey", key)
			local g = groups[key]
			self.markButton.combatMacro = g and CombatMacro(g)
			self.markButton:SetAttribute("macrotext1", self.markButton.combatMacro)
		end
	end
	self.namePages = math.max(1, math.ceil(#list / PAGE))
	self.namePage = math.min(self.namePage or 1, self.namePages)
	local hold = locked
	if #list > 0 and not pageChanged and not hold then
		for _, row in ipairs(rows) do
			if row:IsShown() and row:IsMouseOver() and groups[row.key] then hold = true; break end
		end
	end
	for i = 1, PAGE do
		local row = rows[i]
		local g = list[(self.namePage - 1) * PAGE + i]
		if not hold then
			if g and not row then row = NewRow(self, i); rows[i] = row end
			if row and row.key ~= (g and g.key) then
				row.key, row.displayName = g and g.key, g and g.name
				row:SetAttribute("finderKey", row.key)
				row.combatMacro = g and CombatMacro(g)
				row:SetAttribute("macrotext1", row.combatMacro)
				if g then row.label:SetText(g.name) end
			end
			if row and row:IsShown() ~= (g ~= nil) then row:SetShown(g ~= nil) end
		end
		if row and row.key then
			row.group = groups[row.key]
			local n = row.group and #row.group.hits or 0
			if row.liveCount ~= n then
				row.liveCount = n
				row.label:SetTextColor(n > 0 and 0.45 or 0.65, n > 0 and 1 or 0.65, n > 0 and 0.55 or 0.65)
				row.count:SetText(n > 0 and tostring(n) or "")
			end
			if GameTooltip:IsOwned(row) then Tooltip(row) end
		end
	end
end

end)
