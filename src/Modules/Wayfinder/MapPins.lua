-- Icons on Blizzard's world map, plus the tooltip shared with the detail view.
local _, ns = ...

local MapPins = ns:NewModule("MapPins")

local PIN_TEMPLATE = "WayfinderMapPinTemplate"
local APPROXIMATE_YARDS = 20

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
local Tooltip = {}
ns.Tooltip = Tooltip

local COMPASS = { "east", "northeast", "north", "northwest", "west", "southwest", "south", "southeast" }

-- "240 yd northeast": how far a world point is from you, and which way.
-- Nothing on another continent or where the game gives no position.
function ns.DistanceAndDirection(cont, x, y)
	local here, wx, wy = ns.GetPlayerWorld()
	if not (here and cont == here and x and y) then return nil end
	local north, east = x - wx, wy - y -- (world y counts westward)
	local yards = math.sqrt(north * north + east * east)
	if yards < 5 then return "Here" end
	local sector = math.floor((math.atan2(north, east) / (math.pi / 4)) + 0.5) % 8
	local distance = yards >= 10000 and ("%.1fk yd"):format(yards / 1000) or ("%d yd"):format(yards + 0.5)
	return distance .. " " .. COMPASS[sector + 1]
end

local function AddDistance(rec)
	if not ns:GetSetting("tooltipDistance") then return end
	local text = ns.DistanceAndDirection(rec.c, rec.x, rec.y)
	if text then GameTooltip:AddLine(text, 1, 1, 1) end
end

function Tooltip:Show(owner, rec, catID)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if rec.questObjective then
		GameTooltip:SetText(rec.n, 1, 0.82, 0)
		AddDistance(rec)
		local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, rec.questID)
		for _, objective in ipairs(ok and type(objectives) == "table" and objectives or {}) do
			local text = type(objective) == "table" and objective.text
			if ns.Readable(text) and type(text) == "string" and text ~= "" then
				local done = ns.Readable(objective.finished) and objective.finished
				GameTooltip:AddLine("- " .. text, done and 0.5 or 1, done and 0.5 or 1, done and 0.5 or 1, true)
			end
		end
		GameTooltip:AddLine("Middle-click to follow this quest with the arrow", 0.5, 0.5, 0.5)
		GameTooltip:Show()
		return
	end
	if rec.waypoint then
		GameTooltip:SetText(rec.n, 1, 0.82, 0)
		if rec.where and rec.where ~= rec.n then
			GameTooltip:AddLine(rec.where, 0.8, 0.8, 0.8)
		end
		AddDistance(rec)
		GameTooltip:AddLine(rec == ns.Navigation:GetWaypoint() and "Waypoint, the arrow is on this one"
			or "Waypoint", 0.6, 0.85, 1)
		GameTooltip:AddLine("Left-click to copy a link to chat", 0.5, 0.5, 0.5)
		GameTooltip:AddLine("Middle-click to remove", 0.5, 0.5, 0.5)
		GameTooltip:Show()
		return
	end
	local cat = ns.CategoryByID[catID]
	GameTooltip:SetText(rec.n or (cat and cat.label) or UNKNOWN, 1, 0.82, 0)
	if rec.s and rec.s ~= rec.n then
		GameTooltip:AddLine("<" .. rec.s .. ">", 0.8, 0.8, 0.8)
	end
	AddDistance(rec)
	local services = {}
	for _, c in ipairs(ns.CategoryList) do
		if rec.cats[c.id] and (c.id ~= "quest" or ns.QuestAvailability:HasAvailableQuest(rec)) then
			services[#services + 1] = c.label
		end
	end
	if #services > 1 or (rec.n and #services == 1) then
		GameTooltip:AddLine(table.concat(services, ", "), 0.6, 0.85, 1, true)
	end
	if cat and cat.hint then
		GameTooltip:AddLine(cat.hint, 0.8, 0.8, 0.8, true)
	end
	if rec.seed then
		GameTooltip:AddLine("Built-in location, revealed by exploring", 0.5, 0.5, 0.5)
	elseif (rec.a or 0) > APPROXIMATE_YARDS then
		GameTooltip:AddLine(("Approximate (within ~%d yards)"):format(rec.a), 1, 0.6, 0.2)
	end
	GameTooltip:AddLine("Left-click to copy a link to chat", 0.5, 0.5, 0.5)
	GameTooltip:AddLine("Middle-click to set a waypoint here", 0.5, 0.5, 0.5)
	GameTooltip:AddLine("Shift-click to remove", 0.5, 0.5, 0.5)
	GameTooltip:Show()
end

function ns:RemoveLocation(rec)
	if rec.ephemeral then
		self.db.hidden[rec.k] = true
		self:Fire("POI_REMOVED", rec)
	elseif rec.seed then
		ns.Seeds:Hide(rec)
	else
		ns.Database:Remove(rec)
	end
	GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- Which map a location belongs on
---------------------------------------------------------------------------
-- The game decides which uiMap owns each world position (Stormwind City vs. the
-- Elwynn Forest map around it); we show a location on that map and its parents.
local bestMapOf = setmetatable({}, { __mode = "k" })
local ancestry = {} -- [childMapID][mapID] = bool

local function BestMap(rec)
	local mapID = bestMapOf[rec]
	if mapID == nil then
		mapID = false
		local ok, found = pcall(C_Map.GetMapPosFromWorldPos, rec.c, CreateVector2D(rec.x, rec.y))
		-- Only an answer at zone level or finer says which zone owns the spot.
		local info = ok and found and C_Map.GetMapInfo(found)
		if info and info.mapType >= Enum.UIMapType.Zone then
			mapID = found
		end
		bestMapOf[rec] = mapID
	end
	-- Fall back to the map the location was recorded on; with neither, show it
	-- wherever it falls inside the map.
	return mapID or rec.m
end

local function IsWithin(childMapID, mapID)
	if not childMapID then
		return true
	end
	local cache = ancestry[childMapID]
	if not cache then
		cache = {}
		ancestry[childMapID] = cache
	end
	local result = cache[mapID]
	if result == nil then
		result = false
		local current, depth = childMapID, 0
		while current and depth < 12 do
			if current == mapID then
				result = true
				break
			end
			local info = C_Map.GetMapInfo(current)
			current = info and info.parentMapID
			depth = depth + 1
		end
		cache[mapID] = result
	end
	return result
end

ns.BelongsToMap = function(rec, mapID)
	return IsWithin(BestMap(rec), mapID)
end

---------------------------------------------------------------------------
-- Pin
---------------------------------------------------------------------------
WayfinderMapPinMixin = CreateFromMixins(MapCanvasPinMixin)

function WayfinderMapPinMixin:OnLoad()
	-- Keep whatever the base mixin sets up; overriding OnLoad outright is how a
	-- pin ends up never being offered clicks.
	if MapCanvasPinMixin.OnLoad then MapCanvasPinMixin.OnLoad(self) end
	if self.SetMouseClickEnabled then self:SetMouseClickEnabled(true) end
	if self.SetMouseMotionEnabled then self:SetMouseMotionEnabled(true) end
	if self.RegisterForClicks then self:RegisterForClicks("AnyUp") end
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	self:SetScalingLimits(1, 1.0, 1.2)
end

-- A frame level kind the pin's map knows: the zone map (Shift+M) registers
-- fewer than the world map, and an unknown kind puts a pin at the map's
-- default level, under the explored-area art. Read only, never added to:
-- the levels belong to the game's map.
local function LevelType(map, wanted, fallback)
	local manager = map and map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
	local definitions = type(manager) == "table" and manager.definitions
	if type(definitions) ~= "table" or definitions[wanted] then return wanted end
	return fallback
end
MapPins.LevelType = LevelType

-- Where the zone map's ant trail layer sits: the level kept for debug pins,
-- which lies over the explored-area art, fog and highlight and under every
-- icon. Nothing when the map doesn't say.
function MapPins.ZoneTrailLevel(map)
	local manager = map and map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
	local definitions = type(manager) == "table" and manager.definitions
	if type(definitions) ~= "table" or not definitions.PIN_FRAME_LEVEL_DEBUG then return nil end
	local ok, level = pcall(manager.GetFrameLevelStart, manager, "PIN_FRAME_LEVEL_DEBUG")
	return ok and type(level) == "number" and level or nil
end

-- The game's quest objective markers on the zone map (see ZoneMap below).
local QUEST_OBJECTIVE_ATLASES = { "Quest-In-Progress-Icon-yellow", "QuestNormal" }
local function QuestIcon(texture, rec)
	if rec.complete and ns.Categories.questTurnInAtlas then
		texture:SetAtlas(ns.Categories.questTurnInAtlas)
		return
	end
	for _, atlas in ipairs(QUEST_OBJECTIVE_ATLASES) do
		if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
			texture:SetAtlas(atlas)
			return
		end
	end
	texture:SetTexture("Interface\\GossipFrame\\IncompleteQuestIcon")
end

function WayfinderMapPinMixin:OnAcquired(rec, catID, x, y)
	self.rec, self.catID = rec, catID
	local map = self.GetMap and self:GetMap()
	-- the waypoint sits above everything else
	if rec.waypoint then
		self:UseFrameLevelType(LevelType(map, "PIN_FRAME_LEVEL_WAYPOINT_LOCATION", "PIN_FRAME_LEVEL_CORPSE"))
	elseif catID == "quest" or rec.questObjective then
		self:UseFrameLevelType(LevelType(map, "PIN_FRAME_LEVEL_ACTIVE_QUEST", "PIN_FRAME_LEVEL_ENCOUNTER"))
	else
		self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	end
	local size = (rec.waypoint and 24 or 18) * (ns:GetSetting("iconScale") or 1)
	self:SetSize(size, size)
	if rec.questObjective then
		QuestIcon(self.Icon, rec)
		QuestIcon(self.Highlight, rec)
	else
		ns.Categories:ApplyIcon(self.Icon, catID, rec)
		ns.Categories:ApplyIcon(self.Highlight, catID, rec)
	end
	self.Icon:SetAlpha((not rec.seed and (rec.a or 0) > APPROXIMATE_YARDS) and 0.7 or 1)
	self:SetPosition(x, y)
	ns.OpenMapCompat:RaisePin(self)
end

-- AcquirePin sets every pin's click passthrough, and SetPassThroughButtons is
-- blocked in combat, so opening the map mid-fight was blocked. Pins are pooled
-- and always ask for the same buttons, so each pin is set once, out of combat;
-- one first shown during a fight catches up when it ends.
function WayfinderMapPinMixin:CheckMouseButtonPassthrough(...)
	local wanted = table.concat({ ... }, ",")
	if self.passThrough == wanted then return end
	if InCombatLockdown() then
		self.passThroughLater = { ... }
		return
	end
	MapCanvasPinMixin.CheckMouseButtonPassthrough(self, ...)
	self.passThrough, self.passThroughLater = wanted, nil
end

function WayfinderMapPinMixin:OnMouseEnter()
	Tooltip:Show(self, self.rec, self.catID)
end

function WayfinderMapPinMixin:OnMouseLeave()
	GameTooltip:Hide()
end

-- Depending on the client, a pin is told about a click through the canvas's
-- mouse-action dispatch, through OnClick, or through plain OnMouseUp. Take
-- whichever arrives and drop the duplicates: several can fire for one press,
-- and GetTime is constant within a frame, so the same press is easy to spot.
function WayfinderMapPinMixin:HandleClick(button)
	local now = GetTime()
	if self.clickButton == button and self.clickAt == now then return end
	self.clickButton, self.clickAt = button, now
	self:OnPinClicked(button)
end

function WayfinderMapPinMixin:OnMouseClickAction(button) self:HandleClick(button) end
function WayfinderMapPinMixin:OnClick(button) self:HandleClick(button) end
function WayfinderMapPinMixin:OnMouseUp(button) self:HandleClick(button) end

function WayfinderMapPinMixin:OnPinClicked(button)
	if self.rec.questObjective then
		if button == "MiddleButton" and ns.QuestWaypoints then ns.QuestWaypoints:Click(self.rec.questID) end
		return
	end
	if button == "MiddleButton" then
		ns.Navigation:ToggleWaypointAt(self.rec, self.catID)
	elseif button == "LeftButton" and IsShiftKeyDown() then
		if self.rec.waypoint then
			ns.Navigation:RemoveWaypoint(self.rec)
		else
			ns:RemoveLocation(self.rec)
		end
	elseif button == "LeftButton" then
		-- Any pin can be shared, not only the one that happens to be the
		-- current waypoint: left-click meaning nothing on most pins is the
		-- reason sharing looked broken.
		ns.Navigation:CopyWaypoint(self.rec)
	end
end

---------------------------------------------------------------------------
-- What a map at zone level shows
---------------------------------------------------------------------------
-- Every visible location on a zone map (or a continent, with the setting), as
-- collect(rec, catID, x, y) with x, y on the map. Returns the map's rect, or
-- nothing for a map that shows none.
local function EachLocation(mapID, collect)
	local info = mapID and C_Map.GetMapInfo(mapID)
	if not info then
		return
	end
	local mapType = info.mapType
	if mapType < Enum.UIMapType.Zone
		and not (mapType == Enum.UIMapType.Continent and ns:GetSetting("showOnContinent")) then
		return
	end
	local rect = ns.GetMapRect(mapID)
	if not rect then
		return
	end
	local minX, maxX = rect.top - rect.height, rect.top
	local minY, maxY = rect.left - rect.width, rect.left
	local function Add(rec)
		local catID = ns.Categories:GetVisibleCategory(rec)
		if catID and ns.BelongsToMap(rec, mapID) then
			local x, y = ns.WorldToMapRect(rect, rec.x, rec.y)
			if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
				collect(rec, catID, x, y)
			end
		end
	end
	ns.Database:Query(rect.cont, minX, maxX, minY, maxY, Add)
	ns.Seeds:Query(rect.cont, minX, maxX, minY, maxY, Add)
	ns.MinimapTurnIns:QueryServices(rect.cont, minX, maxX, minY, maxY, Add)
	return rect
end

local function EachWaypoint(mapID, rect, fn)
	for _, waypoint in ipairs(ns.Navigation:GetWaypoints()) do
		if waypoint.c == rect.cont and ns.BelongsToMap(waypoint, mapID) then
			local x, y = ns.WorldToMapRect(rect, waypoint.x, waypoint.y)
			if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
				fn(waypoint, x, y)
			end
		end
	end
end

-- Icons are thinned out where they crowd on screen (ServiceLocations), so
-- each is measured in its map's own view.
local function Collector(map, entries)
	local sc = map.ScrollContainer
	local view = sc:GetViewRect()
	return function(rec, catID, x, y)
		entries[#entries+1] = {rec=rec,cat=catID,c=rec.c,id=rec.id,n=rec.n,kind=rec.kind,
			seed=rec.seed,cats=rec.cats,x=rec.x,y=rec.y,mx=x,my=y,
			screenX=x*sc:GetWidth()/(view.right-view.left),screenY=y*sc:GetHeight()/(view.bottom-view.top)}
	end
end

---------------------------------------------------------------------------
-- Data provider
---------------------------------------------------------------------------
local provider = CreateFromMixins(MapCanvasDataProviderMixin)

function provider:RemoveAllData()
	self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
	ns.OpenMapCompat.built = nil -- nothing stands until RefreshPins says what does
end

function provider:RefreshAllData()
	self:RemoveAllData()
	if not ns.db or not ns:GetSetting("showOnWorldMap") or ns.DetailView:IsFollowingMap() then
		return
	end
	local map = self:GetMap()
	local entries = {}
	local Collect = Collector(map, entries)
	local function Flush()
		-- Every icon sits on the spot it marks, the one under the player included.
		for _, entry in ipairs(ns.ServiceLocations:Select(entries)) do
			map:AcquirePin(PIN_TEMPLATE, entry.rec, entry.cat, entry.mx, entry.my)
		end
	end
	if ns.OpenMapCompat:RefreshPins(map, function(rec, catID, x, y)
		if rec.waypoint then map:AcquirePin(PIN_TEMPLATE, rec, catID, x, y)
		else Collect(rec,catID,x,y) end
	end) then Flush(); return end
	local mapID = map:GetMapID()
	local rect = EachLocation(mapID, Collect)
	if not rect then return end
	Flush()
	EachWaypoint(mapID, rect, function(waypoint, x, y)
		map:AcquirePin(PIN_TEMPLATE, waypoint, "waypoint", x, y)
	end)
end

---------------------------------------------------------------------------
-- The zone map (Shift+M)
---------------------------------------------------------------------------
-- The game's small zone map shows flight points and points of interest, but
-- none of Wayfinder's icons, no waypoints and no quest objectives. This adds
-- them through a provider of Wayfinder's own: the map runs each provider in
-- its own secure call, so nothing here reaches the game's own pins, and these
-- pins wait out combat for their click passthrough as on the world map.
-- Quest objectives are Wayfinder pins too, read from C_QuestLog directly, not
-- the game's quest provider: that one shares caches with the world map and
-- the quest log, and anything an addon puts in them is blamed on the addon.
local zoneProvider = CreateFromMixins(MapCanvasDataProviderMixin)

local function ZoneQuests(map, mapID, rect)
	local ok, quests = pcall(C_QuestLog.GetQuestsOnMap, mapID)
	if not (ok and type(quests) == "table") then return end
	for _, info in ipairs(quests) do
		local questID, x, y = info.questID, info.x, info.y
		if ns.Readable(questID) and ns.Readable(x) and ns.Readable(y) and type(x) == "number" and type(y) == "number"
			and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
			local done, complete = pcall(C_QuestLog.IsComplete, questID)
			complete = done and complete == true
			-- A finished quest's turn-in is already an icon of Wayfinder's own (Quests to turn in).
			if not complete then
				local named, title = pcall(C_QuestLog.GetTitleForQuestID, questID)
				local wx, wy = rect.top - y * rect.height, rect.left - x * rect.width
				local rec = { questObjective = true, questID = questID, c = rect.cont, x = wx, y = wy,
					n = named and ns.Readable(title) and type(title) == "string" and title or ("Quest " .. questID) }
				map:AcquirePin(PIN_TEMPLATE, rec, "questObjective", x, y)
			end
		end
	end
end

function zoneProvider:RemoveAllData()
	self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
end

function zoneProvider:RefreshAllData()
	self:RemoveAllData()
	if not ns.db or not ns:GetSetting("zoneMap") then return end
	local map = self:GetMap()
	local mapID = map:GetMapID()
	local entries = {}
	local rect = EachLocation(mapID, Collector(map, entries))
	if not rect then return end
	for _, entry in ipairs(ns.ServiceLocations:Select(entries)) do
		map:AcquirePin(PIN_TEMPLATE, entry.rec, entry.cat, entry.mx, entry.my)
	end
	if ns:GetSetting("zoneMapQuests") then ZoneQuests(map, mapID, rect) end
	EachWaypoint(mapID, rect, function(waypoint, x, y)
		map:AcquirePin(PIN_TEMPLATE, waypoint, "waypoint", x, y)
	end)
end

function MapPins:RefreshZoneMap()
	if self.zonePending or not (BattlefieldMapFrame and BattlefieldMapFrame:IsShown() and self.zoneAdded) then
		return
	end
	self.zonePending = true
	C_Timer.After(0, function()
		self.zonePending = false
		if BattlefieldMapFrame:IsShown() then zoneProvider:RefreshAllData() end
	end)
end

function MapPins:AddToZoneMap()
	if self.zoneAdded or not BattlefieldMapFrame then return end
	self.zoneAdded = true
	BattlefieldMapFrame:AddDataProvider(zoneProvider)
end

function MapPins:OwnsServiceSources()
	return ns.db and ns:GetSetting("showOnWorldMap") and WorldMapFrame and WorldMapFrame:IsShown()
		and (ns.OpenMapCompat:IsActive() or ns.GetMapRect(WorldMapFrame:GetMapID()) ~= nil)
end

function MapPins:RefreshNow()
	if WorldMapFrame then provider:RefreshAllData() end
end

function MapPins:Refresh()
	self:RefreshZoneMap()
	if self.pending or not WorldMapFrame or not WorldMapFrame:IsShown() then
		return
	end
	-- Coalesce bursts of updates (walking reveals cells every half second).
	self.pending = true
	C_Timer.After(0, function()
		self.pending = false
		if WorldMapFrame:IsShown() then
			provider:RefreshAllData()
		end
	end)
end

function MapPins:OnLogin()
	EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", function()
		WorldMapFrame:AddDataProvider(provider)
	end)
	EventUtil.ContinueOnAddOnLoaded("Blizzard_BattlefieldMap", function() self:AddToZoneMap() end)
	-- Quest objectives move as quests do; the world map has its own markers for them.
	ns:RegisterEvent("QUEST_LOG_UPDATE", function() self:RefreshZoneMap() end)
	local function Refresh()
		self:Refresh()
	end
	ns:On("POI_UPDATED", function(rec)
		bestMapOf[rec] = nil
		Refresh()
	end)
	ns:On("POI_REMOVED", Refresh)
	ns:On("SETTING_CHANGED", Refresh)
	ns:On("DATA_CHANGED", Refresh)
	ns:On("EXPLORED", Refresh)
	ns:On("WAYPOINT_CHANGED", Refresh)
	ns:On("QUEST_AVAILABILITY_CHANGED", Refresh)
	ns:On("MAP_LAYER_CHANGED", Refresh)
	ns:On("SERVICE_SOURCES_CHANGED", Refresh)
	ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		for _, map in ipairs({ WorldMapFrame or false, self.zoneAdded and BattlefieldMapFrame or false }) do
			if map then
				for pin in map:EnumeratePinsByTemplate(PIN_TEMPLATE) do
					if pin.passThroughLater then pin:CheckMouseButtonPassthrough(unpack(pin.passThroughLater)) end
				end
			end
		end
	end)
end
