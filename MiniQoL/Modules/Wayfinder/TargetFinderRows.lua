-- Mini QoL packaging adapter; upstream source and credits follow.
MiniQoLRuntime:Execute("Wayfinder", function(...)
local _, ns = ...
local Finder = ns.TargetFinder
local Read = Finder.Read
local PAGE = 8
local WAYPOINT = "TargetFinder"
local lastPick = {}

local function WatchKey(entry)
	return entry.kind .. ":" .. (entry.id or entry.name:lower())
end

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
	local hit = self.hitsByGUID[owned.guid]
	local unit = hit and hit.unit or owned.unit
	if Read(UnitGUID, unit) == owned.guid then return unit end
	if Read(UnitGUID, "target") == owned.guid then return "target" end
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

local function Click(self, row, mouse)
	local locked = InCombatLockdown()
	if not locked then
		row:SetAttribute("macrotext1", nil)
		row:SetAttribute("macrotext2", nil)
	end
	self.markers = nil
	self:Scan(true)
	if mouse == "RightButton" then Unmark(self, row); return end
	if mouse ~= "LeftButton" then return end
	local _, groups = Groups(self)
	local group = groups[row.key]
	local hit = group and NextHit(group.hits, lastPick[row.key])
	if not hit then return end
	if hit.kind == "object" then
		PlacePin(self, hit)
		lastPick[row.key] = hit.guid
		return
	end
	if locked or Read(UnitGUID, hit.unit) ~= hit.guid then return end
	lastPick[row.key] = hit.guid
	local condition = "[nocombat,@" .. hit.unit .. ",exists,nodead]"
	local macro = "/target " .. condition .. " " .. hit.unit
	if self.markedGUID and self.markedGUID ~= hit.guid then self:ClearLocalMark() end
	local mark = Read(GetRaidTargetIndex, hit.unit)
	if not mark or mark == 0 then
		local personal = self:MarkNameplate(hit)
		-- A solo nameplate skull can be removed even mid-fight. Share the
		-- native marker with a party, or use it when there is no plate.
		if (not personal or Read(IsInGroup) or Read(IsInRaid)) and CanMark() then
			macro = macro .. "\n/tm " .. condition .. " ~8"
			self.rowSkull = { key = row.key, guid = hit.guid, unit = hit.unit, time = GetTime() }
		elseif not personal and not PlacePin(self, hit) then
			ns.Print("Targeted " .. hit.displayName .. ". The game did not provide a place for its marker.")
		end
	end
	row:SetAttribute("macrotext1", macro)
end

local function AfterClick(self, row, mouse)
	if not InCombatLockdown() then
		row:SetAttribute("macrotext1", row.combatMacro)
		row:SetAttribute("macrotext2", nil)
	elseif mouse == "LeftButton" and row.combatMacro then
		-- The client resolves the prebound exact name during lockdown. Only draw
		-- a personal skull if the resulting target is still a verified sighting.
		self:Scan(true)
		local hit = self.hitsByGUID[Read(UnitGUID, "target")]
		if hit and hit.key == row.key and hit.kind == "mob" then
			lastPick[row.key] = hit.guid
			if self.markedGUID ~= hit.guid then self:ClearLocalMark() end
			local mark = Read(GetRaidTargetIndex, "target")
			if (not mark or mark == 0) and not self:MarkNameplate(hit) then PlacePin(self, hit) end
		end
	end
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
	row:SetAttribute("useOnKeyDown", false)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("PreClick", function(b, mouse) Click(self, b, mouse) end)
	row:SetScript("PostClick", function(b, mouse) AfterClick(self, b, mouse) end)
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
	if g.kind == "mob" and #g.name <= 120 and not g.name:find("[%c|%[%];/]") then
		return "/targetexact [combat] " .. g.name .. "\n/cleartarget [combat,dead]"
	end
end

function Finder:PaintNames(pageChanged)
	if not self.markButton then return end
	if #self.watches == 0 then wipe(lastPick) end
	local list, groups = Groups(self)
	local rows = self.nameRows or {}
	self.nameRows = rows
	local locked = InCombatLockdown()
	self.namePages = math.max(1, math.ceil(#list / PAGE))
	self.namePage = math.min(self.namePage or 1, self.namePages)
	local hold = locked
	if #list > 0 and not pageChanged and not hold then
		for _, row in ipairs(rows) do
			if row:IsShown() and row:IsMouseOver() then hold = true; break end
		end
	end
	for i = 1, PAGE do
		local row = rows[i]
		local g = list[(self.namePage - 1) * PAGE + i]
		if not hold then
			if g and not row then row = NewRow(self, i); rows[i] = row end
			if row and row.key ~= (g and g.key) then
				row.key, row.displayName = g and g.key, g and g.name
				row.combatMacro = g and CombatMacro(g)
				row:SetAttribute("macrotext1", row.combatMacro)
				if g then row.label:SetText(g.name) end
				row:SetShown(g ~= nil)
			end
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
