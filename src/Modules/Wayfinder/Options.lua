-- Settings panel (Esc > Options > AddOns > Wayfinder) and the world map's quick menu.
local _, ns = ...

local Options = ns:NewModule("Options")

ns.settingObjects = {} -- settings key (or "cats.<id>") -> Settings API object

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
-- Wayfinder registers no settings category of its own. Every setting below is
-- declared to Mini QoL and drawn on the panel's Maps & travel page, so the
-- game's AddOns list holds one Mini QoL entry and nothing lives in two places.
-- SetSetting still routes through settingObjects when something else populates
-- it, so the table stays.
function Options:Open()
	if MiniQoL and MiniQoL.ShowPage then MiniQoL:ShowPage("maps") end
end

---------------------------------------------------------------------------
-- World map button and menu
---------------------------------------------------------------------------
local function SetEverything(enabled)
	for _, cat in ipairs(ns.CategoryList) do
		ns:SetCategoryEnabled(cat.id, enabled)
	end
end

local function BuildMenu(_, root)
	root:CreateTitle("Wayfinder")
	for _, cat in ipairs(ns.CategoryList) do
		root:CreateCheckbox(cat.label, function()
			return ns:IsCategoryEnabled(cat.id)
		end, function()
			ns:SetCategoryEnabled(cat.id, not ns:IsCategoryEnabled(cat.id))
		end)
	end
	root:CreateButton("Show all", function()
		SetEverything(true)
	end)
	root:CreateButton("Hide all", function()
		SetEverything(false)
	end)
	root:CreateDivider()
	root:CreateCheckbox("Zoom into minimap detail", function()
		return ns:GetSetting("detailEnabled")
	end, function()
		ns:SetSetting("detailEnabled", not ns:GetSetting("detailEnabled"))
	end)
	root:CreateCheckbox("Icons on the world map", function()
		return ns:GetSetting("showOnWorldMap")
	end, function()
		ns:SetSetting("showOnWorldMap", not ns:GetSetting("showOnWorldMap"))
	end)
	root:CreateDivider()
	root:CreateTitle("Unexplored terrain")
	for mode, text in ipairs(ns.UNEXPLORED_NAMES) do
		root:CreateRadio(text, function()
			return ns:GetSetting("unexploredTerrain") == mode
		end, function()
			ns:SetSetting("unexploredTerrain", mode)
		end, mode)
	end
	root:CreateDivider()
	root:CreateButton("Open detail view", function()
		if ns.ContinuousMap:ZoomToDetail() then return end
		local opened, reason = ns.DetailView:EnterFromMap()
		if not opened then
			ns.Print(reason == "city" and "The detail view isn't available on city maps."
				or "No minimap terrain for this map.")
		end
	end)
	root:CreateButton("Settings...", function()
		Options:Open()
	end)
	root:CreateButton("Reset button position", function()
		Options:ResetMapButtonPosition()
	end)
end

local DEFAULT_BUTTON_X, DEFAULT_BUTTON_Y = -44, -6

function Options:PositionMapButton(x, y)
	local button = self.mapButton
	if not button then return end
	local canvas = WorldMapFrame:GetCanvasContainer()
	local saved = ns.db.settings.mapButtonPosition
	if type(saved) ~= "table" then saved = {} end
	x = x or tonumber(saved.x) or DEFAULT_BUTTON_X
	y = y or tonumber(saved.y) or DEFAULT_BUTTON_Y
	-- Keep the entire button inside the canvas, including on a smaller map.
	local scale = canvas:GetEffectiveScale() / button:GetEffectiveScale()
	local width, height = canvas:GetWidth() * scale, canvas:GetHeight() * scale
	if width > 0 and height > 0 then
		x = math.max(math.min(6 + button:GetWidth() - width, -6), math.min(-6, x))
		y = math.max(math.min(6 + button:GetHeight() - height, -6), math.min(-6, y))
	end
	button.offsetX, button.offsetY = x, y
	button:ClearAllPoints()
	button:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", x, y)
end

function Options:StopMapButtonDrag()
	local button = self.mapButton
	if not button or not button.dragging then return end
	button.dragging = nil
	button:SetScript("OnUpdate", nil)
	ns.db.settings.mapButtonPosition = { x = button.offsetX, y = button.offsetY }
end

function Options:ResetMapButtonPosition()
	self:StopMapButtonDrag()
	ns.db.settings.mapButtonPosition = nil
	self:PositionMapButton()
end

function Options:CreateMapButton()
	local button = CreateFrame("Button", "WayfinderMapButton", WorldMapFrame)
	self.mapButton = button
	button:SetSize(32, 32)
	button:SetFrameStrata("HIGH")
	self:PositionMapButton()
	button:RegisterForDrag("LeftButton")
	button:SetScript("OnDragStart", function(self)
		if not IsShiftKeyDown() then return end
		GameTooltip_Hide()
		local cursorX, cursorY = GetCursorPosition()
		local scale = self:GetEffectiveScale()
		local startX, startY = self.offsetX, self.offsetY
		cursorX, cursorY = cursorX / scale, cursorY / scale
		self.dragging = true
		-- Move only our own anchor; the world map keeps control of its frames.
		self:SetScript("OnUpdate", function(self)
			local x, y = GetCursorPosition()
			Options:PositionMapButton(startX + x / scale - cursorX, startY + y / scale - cursorY)
		end)
	end)
	button:SetScript("OnDragStop", function() Options:StopMapButtonDrag() end)
	button:SetScript("OnHide", function() Options:StopMapButtonDrag() end)
	button:SetScript("OnShow", function() Options:PositionMapButton() end)
	WorldMapFrame:GetCanvasContainer():HookScript("OnSizeChanged", function()
		Options:StopMapButtonDrag()
		Options:PositionMapButton()
	end)

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(25, 25)
	background:SetPoint("CENTER")

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
	icon:SetSize(20, 20)
	icon:SetPoint("CENTER")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	pcall(icon.SetMask, icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask")

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(54, 54)
	border:SetPoint("TOPLEFT")

	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetScript("OnClick", function(self)
		if not self.dragging and not IsShiftKeyDown() then
			MenuUtil.CreateContextMenu(self, BuildMenu)
		end
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Wayfinder")
		GameTooltip:AddLine("Choose which icons to show.", 1, 1, 1)
		GameTooltip:AddLine("Shift-drag to move this button. Position is saved.", 1, 1, 1)
		GameTooltip:AddLine("Zoom all the way in, then keep scrolling to see minimap detail.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	self.mapButton = button
end

function Options:OnLogin()
	EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", function()
		self:CreateMapButton()
	end)
end
