local _, ns = ...
local Finder = ns.TargetFinder
local PAGE = 7
local function Tip(button)
	local hit = Finder.best
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip:SetText(hit and hit.name or "Target Finder")
	if hit then
		local action = hit.kind == "mob" and "Mark with a skull" or "Place a waypoint"
		if hit.approximate then action = "Mark your position near this object" end
		local range = hit.distance and (" (%d yd)"):format(math.sqrt(hit.distance) + 0.5) or ""
		GameTooltip:AddLine(action .. range, 0.4, 1, 0.5)
	else
		GameTooltip:AddLine("Searching for your watched mobs and objects.", 0.8, 0.8, 0.8)
	end
	GameTooltip:AddLine("Right-click to edit. Shift-drag to move.", 0.85, 0.8, 0.65)
	GameTooltip:Show()
end

function Finder:Paint()
	local hit, b = self.best, self.button
	if not b then return end
	b.icon:SetDesaturated(not hit)
	b.icon:SetAlpha(hit and 1 or 0.45)
	b:SetBackdropBorderColor(hit and 0.35 or 0.4, hit and 1 or 0.35, hit and 0.48 or 0.22)
	b.glow:SetShown(hit ~= nil)
	if GameTooltip:IsOwned(b) then Tip(b)
	elseif self.markButton and GameTooltip:IsOwned(self.markButton) then Tip(self.markButton) end
	if self.window and self.window:IsShown() then
		self.status:SetText(hit and ("Nearby: " .. hit.name) or (b:IsShown() and "Searching nearby…" or ""))
	end
	self:PaintNames()
end

-- A personal mark for fights and groups where the raid icon can't be set.
-- The texture belongs to our frame; the nameplate remains owned by the game.
function Finder:MarkNameplate(hit)
	local plate = self.Read(C_NamePlate and C_NamePlate.GetNamePlateForUnit, hit.unit)
	if not plate or (plate.IsForbidden and plate:IsForbidden()) then return false end
	local unit = self.PlateToken(plate)
	if not unit or self.Read(UnitGUID, unit) ~= hit.guid then return false end
	local skull = self.localSkull
	if not skull then
		skull = CreateFrame("Frame", nil, UIParent)
		skull:SetFrameStrata("HIGH")
		skull:SetSize(20, 20)
		skull:EnableMouse(false)
		local icon = skull:CreateTexture(nil, "OVERLAY")
		icon:SetAllPoints()
		icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
		self.localSkull = skull
	end
	skull:ClearAllPoints()
	skull:SetPoint("BOTTOM", plate, "TOP", 0, 2)
	skull:Show()
	self.markedUnit, self.markedGUID, self.markedPlate, self.markedKey = unit, hit.guid, plate, hit.key
	return true
end

-- Separate frames let searches start, stop and move during lockdown. The
-- secure click surface copies the HUD's position without protecting its frame.
function Finder:SyncMarkButton()
	if InCombatLockdown() then return end
	local b, mark = self.button, self.markButton
	if not mark then
		mark = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
		self.markButton = mark
		mark:Hide()
		mark:SetSize(32, 32)
		mark:SetFrameStrata("MEDIUM")
		mark:SetFrameLevel(b:GetFrameLevel() + 1)
		mark:SetAttribute("useOnKeyDown", false)
		mark:SetAttribute("type1", "macro")
		mark:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		mark:SetScript("PreClick", function(button, mouse)
			if mouse ~= "LeftButton" then return end
			if InCombatLockdown() then self:Mark(); return end
			button:SetAttribute("macrotext1", nil)
			self:Mark(button)
		end)
		mark:SetScript("PostClick", function(button, mouse)
			if mouse == "RightButton" then self:Open()
			elseif not InCombatLockdown() then button:SetAttribute("macrotext1", nil) end
		end)
		mark:SetScript("OnEnter", Tip)
		mark:SetScript("OnLeave", function() GameTooltip:Hide() end)
		mark:RegisterForDrag("LeftButton")
		mark:SetScript("OnDragStart", b:GetScript("OnDragStart"))
		mark:SetScript("OnDragStop", b:GetScript("OnDragStop"))
	end
	mark:ClearAllPoints()
	mark:SetPoint(b:GetPoint(1))
	self:AnchorNames()
	local visibility = b:IsShown() and "[combat] hide; show" or "hide"
	if self.markVisibility ~= visibility then
		RegisterStateDriver(mark, "visibility", visibility)
		self.markVisibility = visibility
	end
end

function Finder:BuildButton()
	local t = MiniQoL.Theme
	local b = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
	self.button = b
	b:SetSize(32, 32)
	b:SetFrameStrata("MEDIUM")
	b:SetClampedToScreen(true)
	b:SetMovable(true)
	if self.db.x and self.db.y then b:SetPoint("CENTER", UIParent, "BOTTOMLEFT", self.db.x, self.db.y)
	else b:SetPoint("TOPRIGHT", Minimap or UIParent, "BOTTOMRIGHT", -6, -12) end
	t:Chrome(b)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 3, -3)
	b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
	b.icon:SetTexture("Interface\\Icons\\Ability_Hunter_SniperShot")
	b.icon:SetTexCoord(0.08,0.92,0.08,0.92)
	b.glow = b:CreateTexture(nil, "OVERLAY")
	b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	b.glow:SetBlendMode("ADD")
	b.glow:SetVertexColor(0.35, 1, 0.5)
	b.glow:SetSize(51, 51)
	b.glow:SetPoint("CENTER")
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", function(_, button)
		if button == "RightButton" then self:Open() else self:Mark() end
	end)
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnDragStart", function() if IsShiftKeyDown() then b:StartMoving() end end)
	b:SetScript("OnDragStop", function()
		b:StopMovingOrSizing()
		self.db.x, self.db.y = b:GetCenter()
		self:SyncMarkButton()
	end)
	b:SetScript("OnEnter", Tip)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	local elapsed = 0
	b:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed >= 0.3 then elapsed = 0; self:Scan() end
	end)
end

function Finder:UpdateList()
	local w = self.window
	if not w or not w:IsShown() then return end
	local lines = {}
	for i, entry in ipairs(self.db.manual) do
		lines[#lines+1] = { label = entry.name, manual = i }
	end
	local ids = {}
	for id in pairs(self.db.quests) do ids[#ids+1] = id end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local group = self.db.quests[id]
		lines[#lines+1] = { label = group.title, quest = id }
		for _, entry in ipairs(group.targets) do
			lines[#lines+1] = { label = "    " .. entry.name, kind = entry.kind }
		end
		if #group.targets == 0 then lines[#lines+1] = { label = "    No named targets available yet." } end
	end
	local pages = math.max(1, math.ceil(#lines / PAGE))
	self.page = math.min(self.page or 1, pages)
	for i, row in ipairs(self.rows) do
		local line = lines[(self.page-1) * PAGE + i]
		row.line = line
		row:SetShown(line ~= nil)
		if line then
			row.label:SetText(line.label)
			row.label:SetTextColor(MiniQoL.Theme.Color(line.quest and MiniQoL.Theme.GOLD or MiniQoL.Theme.TEXT))
			row.kind:SetText(line.kind == "object" and "Object" or line.kind == "mob" and "Mob" or "")
			row.remove:SetShown(line.manual ~= nil or line.quest ~= nil)
		end
	end
	self.empty:SetShown(#lines == 0)
	self.prev:SetShown(self.page > 1)
	self.next:SetShown(self.page < pages)
	self.counter:SetText(pages > 1 and ("%d / %d"):format(self.page, pages) or "")
end

function Finder:Open(name)
	if not self.db then return end
	if name and name ~= "" then self:Add(name) end
	local t = MiniQoL.Theme
	if not self.window then
		local w = CreateFrame("Frame", "MiniQoLTargetFinderWindow", UIParent, "BackdropTemplate")
		self.window = w
		w:SetSize(365, 360)
		w:SetPoint("CENTER")
		w:SetFrameStrata("DIALOG")
		w:EnableMouse(true)
		w:SetClampedToScreen(true)
		w:SetMovable(true)
		w:RegisterForDrag("LeftButton")
		w:SetScript("OnDragStart", w.StartMoving)
		w:SetScript("OnDragStop", w.StopMovingOrSizing)
		t:Window(w, 33)
		t:Text(w, "Target Finder", "GameFontNormalLarge", nil, t.GOLD):SetPoint("TOPLEFT", 13, -9)
		t:CloseButton(w):SetPoint("TOPRIGHT", -6, -5)
		table.insert(UISpecialFrames, w:GetName())
		t:Text(w, "Mob or object name (partial names work)", nil, nil, t.TEXT):SetPoint("TOPLEFT", 15, -44)
		local box = CreateFrame("EditBox", nil, w, "InputBoxTemplate")
		self.input = box
		box:SetAutoFocus(false)
		box:SetMaxLetters(120)
		box:SetSize(253, 25)
		box:SetPoint("TOPLEFT", 19, -59)
		local function add()
			if self:Add(box:GetText()) then box:SetText(""); box:ClearFocus() end
		end
		box:SetScript("OnEnterPressed", add)
		box:SetScript("OnEscapePressed", function() w:Hide() end)
		t:Button(w, "Track", 68, 24, add):SetPoint("TOPRIGHT", -14, -59)
		t:Text(w, "Shift + middle-click a mob or a tracker quest to watch it.", "GameFontHighlightSmall", 336, t.MUTED):SetPoint("TOPLEFT", 15, -93)
		self.status = t:Text(w, "", "GameFontHighlightSmall", 332, t.GOOD)
		self.status:SetPoint("TOPLEFT", 15, -115)
		self.empty = t:Text(w, "Your watch list is empty.", nil, nil, t.MUTED)
		self.empty:SetPoint("TOPLEFT", 16, -145)
		self.rows = {}
		for i = 1, PAGE do
			local row = CreateFrame("Frame", nil, w)
			self.rows[i] = row
			row:SetSize(336, 23)
			row:SetPoint("TOPLEFT", 15, -138 - (i-1)*25)
			row.label = t:Text(row, "", nil, 252, t.TEXT)
			row.label:SetWordWrap(false)
			row.label:SetPoint("LEFT")
			row.kind = t:Text(row, "", "GameFontHighlightSmall", nil, t.MUTED)
			row.kind:SetPoint("RIGHT", -5, 0)
			row.remove = t:CloseButton(row, function()
				local line = row.line
				if line.manual then table.remove(self.db.manual, line.manual)
				elseif line.quest then self.db.quests[line.quest] = nil; self.signatures[line.quest] = nil end
				self:Reindex()
			end)
			row.remove:SetPoint("RIGHT")
			t:Tip(row.remove, "Stop tracking", function() return row.line and row.line.label end)
		end
		self.prev = t:Button(w, "Previous", 72, 22, function() self.page = self.page - 1; self:UpdateList() end)
		self.prev:SetPoint("BOTTOMLEFT", 14, 11)
		self.next = t:Button(w, "Next", 65, 22, function() self.page = self.page + 1; self:UpdateList() end)
		self.next:SetPoint("BOTTOMRIGHT", -14, 11)
		self.counter = t:Text(w, "", "GameFontHighlightSmall", nil, t.MUTED)
		self.counter:SetPoint("BOTTOM", 0, 16)
	end
	self.page = 1
	self.window:Show()
	self:UpdateList()
	self:Paint()
	self.input:SetFocus()
end
