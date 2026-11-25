-- Middle-click a quest to follow it.
--
-- A middle-click on a quest in the quest log, in the objective tracker (its
-- title, its lines or its quest icon) or in Questie's tracker puts one waypoint
-- on the arrow: the nearest place still to do for that quest or, once it is
-- complete, the place to hand it in. The waypoint follows the quest: it moves
-- when an objective is finished, to the turn-in when the quest is complete,
-- and goes when the quest is handed in or abandoned. Arriving doesn't clear it,
-- since among the spawns is where the work is. One quest at a time: another
-- takes its place, and a middle-click on the same quest again stops following.
--
-- Where: Questie's quest data when Questie is loaded (the spots it draws on the
-- map, chosen as its own "Set TomTom target" chooses), else the game's quest
-- markers on the player's continent.
--
-- Hooks are post-hooks on unprotected frames (HookScript on frames that already
-- take the mouse, hooksecurefunc on the tracker and the log's update), so the
-- game's own clicks are left exactly as they were.
local _, ns = ...

local QuestWaypoints = ns:NewModule("QuestWaypoints")

local SOURCE = "quest" -- the waypoint's source in the arrow's list
local NOTE = "Following this quest: it moves on as objectives are done, and to the turn-in once the quest is"
	.. " complete. Middle-click the quest again to stop."
local CHECK_DELAY = 0.3 -- seconds: quest updates come in bursts

local tracked      -- the quest followed
local signature    -- that quest's state when its waypoint was placed
local dropping = false
local checkPending = false
local hooked = setmetatable({}, { __mode = "k" })

local function ValidID(id)
	return ns.Readable(id) and type(id) == "number" and id > 0 and id < math.huge and id == math.floor(id)
end

local function Number(value)
	return ns.Readable(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function Read(fn, ...)
	if type(fn) ~= "function" then return end
	local ok, value, second, third = pcall(fn, ...)
	if ok and ns.Readable(value) then return value, second, third end
end

local function QuestLog(name)
	return C_QuestLog and C_QuestLog[name]
end

local function Title(questID, fallback)
	local title = Read(QuestLog("GetTitleForQuestID"), questID)
	return type(title) == "string" and title ~= "" and title or fallback or ("Quest " .. questID)
end

local function IsComplete(questID)
	return Read(QuestLog("IsComplete"), questID) == true
end

local function OnQuest(questID)
	return Read(QuestLog("IsOnQuest"), questID) == true
end

-- What the waypoint depends on: whether the quest is complete, and which of its
-- objectives are done. Progress within an objective (3 of 8) doesn't move it.
local function Signature(questID)
	local parts = { IsComplete(questID) and "c" or "o" }
	local objectives = Read(QuestLog("GetQuestObjectives"), questID)
	if type(objectives) == "table" then
		for _, objective in ipairs(objectives) do
			local finished = type(objective) == "table" and objective.finished
			parts[#parts + 1] = ns.Readable(finished) and finished == true and "1" or "0"
		end
	end
	return table.concat(parts)
end

---------------------------------------------------------------------------
-- Where a quest leads
---------------------------------------------------------------------------
-- A Questie module, read without creating one: importing a name Questie lacks
-- would add an empty module to its list.
local function QuestieModule(name)
	local modules = type(QuestieLoader) == "table" and QuestieLoader._modules
	local module = type(modules) == "table" and modules[name]
	return type(module) == "table" and module or nil
end

-- The nearest spot Questie knows for the quest: an objective's spawn while it is
-- open, its finisher once complete. uiMapID, x, y (0-1), and what is there.
local function QuestiePlace(questID)
	if not (type(Questie) == "table" and type(Questie.API) == "table" and Questie.API.isReady) then
		return nil
	end
	local eligibility = QuestieModule("TrackerMapEligibility")
	local distance = QuestieModule("DistanceUtils")
	local zones = QuestieModule("ZoneDB")
	if not (eligibility and distance and zones and type(eligibility.RefreshAndGetCapabilities) == "function"
		and type(distance.GetNearestSpawnForQuest) == "function" and type(zones.GetUiMapIdByAreaId) == "function") then
		return nil
	end
	local ok, quest, capabilities = pcall(eligibility.RefreshAndGetCapabilities, questID)
	if not (ok and type(quest) == "table" and type(capabilities) == "table" and capabilities.canNavigateQuest) then
		return nil
	end
	local found, spawn, zone, name = pcall(distance.GetNearestSpawnForQuest, quest)
	if not (found and type(spawn) == "table" and zone) then
		return nil
	end
	local mapped, mapID = pcall(zones.GetUiMapIdByAreaId, zones, zone)
	local x, y = tonumber(spawn[1]), tonumber(spawn[2])
	if not (mapped and mapID and x and y and x >= 0 and y >= 0) then
		return nil
	end
	return mapID, x / 100, y / 100, type(name) == "string" and name ~= "" and name or nil
end

local function MarkerOn(mapID, questID)
	local quests = Read(QuestLog("GetQuestsOnMap"), mapID)
	if type(quests) ~= "table" then return nil end
	for _, info in ipairs(quests) do
		if type(info) == "table" and ns.Readable(info.questID) and info.questID == questID
			and Number(info.x) and Number(info.y) and info.x >= 0 and info.x <= 1 and info.y >= 0 and info.y <= 1 then
			return info.x, info.y
		end
	end
end

-- The game's own marker for the quest: its next waypoint when it gives one,
-- else a marker on the player's map or any zone of the player's continent.
local function GamePlace(questID)
	local mapID, x, y = Read(QuestLog("GetNextWaypoint"), questID)
	if Number(mapID) and Number(x) and Number(y) then
		return mapID, x, y
	end
	local maps, seen = {}, {}
	local function Add(id)
		if Number(id) and id > 0 and not seen[id] then
			seen[id] = true
			maps[#maps + 1] = id
		end
	end
	local current = C_Map.GetBestMapForUnit("player")
	local continent
	for _ = 1, 8 do
		local info = Number(current) and C_Map.GetMapInfo(current)
		if not info then break end
		Add(current)
		if info.mapType == Enum.UIMapType.Continent then
			continent = current
			break
		end
		current = info.parentMapID
	end
	if continent and C_Map.GetMapChildrenInfo then
		local ok, children = pcall(C_Map.GetMapChildrenInfo, continent, Enum.UIMapType.Zone)
		for _, child in ipairs(ok and type(children) == "table" and children or {}) do
			Add(child.mapID)
		end
	end
	for _, id in ipairs(maps) do
		x, y = MarkerOn(id, questID)
		if x then return id, x, y end
	end
end

-- Where the quest leads, in Wayfinder's world terms, and what stands there.
local function Locate(questID)
	local mapID, x, y, name = QuestiePlace(questID)
	if not mapID then
		mapID, x, y = GamePlace(questID)
	end
	if not mapID then return nil end
	local cont, wx, wy = ns.MapToWorld(mapID, x, y)
	if not cont then return nil end
	return cont, wx, wy, mapID, name
end

local function Label(title, name, turnIn)
	if name == title then name = nil end
	if turnIn then
		return name and ("Turn in %s: %s"):format(title, name) or ("Turn in " .. title)
	end
	return name and ("%s: %s"):format(title, name) or title
end

-- A map click stays on the selected spawn. Only use a log objective if the
-- pin identifies its index or there is exactly one unfinished objective.
function QuestWaypoints:MapPinLabel(questID, title, target, turnIn, objectiveIndex, fallback)
	if not ns.Readable(title) or type(title) ~= "string" or title == "" then title = nil end
	if not ValidID(questID) then return title or target end
	if not target and not turnIn and OnQuest(questID) then
		local objectives = Read(QuestLog("GetQuestObjectives"), questID)
		local objective
		if type(objectives) == "table" then
			if ValidID(objectiveIndex) then
				objective = objectives[objectiveIndex]
			else
				for _, candidate in ipairs(objectives) do
					if type(candidate) == "table" and ns.Readable(candidate.finished) and not candidate.finished then
						if objective then objective = nil; break end
						objective = candidate
					end
				end
			end
		end
		local text = type(objective) == "table" and objective.text
		if ns.Readable(text) and type(text) == "string" and text ~= "" then target = text end
	end
	return Label(title or Title(questID, fallback or target), target, turnIn)
end

---------------------------------------------------------------------------
-- Following
---------------------------------------------------------------------------
function QuestWaypoints:GetFollowed()
	return tracked
end

-- Puts the quest's waypoint where it leads now. `again`: the followed quest
-- moving on, which leaves the arrow wherever it is and says nothing on failure.
function QuestWaypoints:Follow(questID, again)
	local cont, wx, wy, mapID, name = Locate(questID)
	if not cont then
		if not again then
			ns.Print(("Wayfinder doesn't know where %s leads%s."):format(Title(questID),
				QuestieModule("DistanceUtils") and "" or "; Questie's quest data would show it"))
		end
		return false
	end
	tracked, signature = questID, Signature(questID)
	local rec = ns.Navigation:PlaceSourceWaypoint(SOURCE, cont, wx, wy, Label(Title(questID), name, IsComplete(questID)), mapID,
		{ focus = not again, kept = true, note = NOTE })
	rec.questID = questID
	return true
end

-- Stops following: the waypoint goes. `quiet` when the quest ended, not the player.
function QuestWaypoints:Stop(quiet)
	tracked, signature = nil, nil
	local rec = ns.Navigation:GetSourceWaypoint(SOURCE)
	if not rec then return false end
	dropping = true
	ns.Navigation:RemoveWaypoint(rec, quiet)
	dropping = false
	return true
end

-- A middle-click on a quest: follow it, or stop following it.
function QuestWaypoints:Click(questID)
	if not ns:GetSetting("questMiddleClick") or not ValidID(questID) or not OnQuest(questID) then
		return false
	end
	if questID == tracked and ns.Navigation:GetSourceWaypoint(SOURCE) then
		return self:Stop()
	end
	return self:Follow(questID)
end

-- After a burst of quest updates: the followed quest moved on, so does its waypoint.
function QuestWaypoints:Check()
	checkPending = false
	if not tracked or not OnQuest(tracked) then return end
	if Signature(tracked) ~= signature then
		self:Follow(tracked, true)
	end
end

local function ScheduleCheck()
	if not tracked or checkPending then return end
	checkPending = true
	C_Timer.After(CHECK_DELAY, function() QuestWaypoints:Check() end)
end

---------------------------------------------------------------------------
-- The quest under a click
---------------------------------------------------------------------------
-- Walks up from what was clicked: a quest log row or a tracker quest icon carry
-- questID, a Questie tracker line its quest, an objective tracker block the id
-- of the quest it shows.
function QuestWaypoints.QuestOf(frame)
	for _ = 1, 10 do
		if type(frame) ~= "table" or (frame.IsForbidden and frame:IsForbidden()) then return nil end
		local id = frame.questID
		if ValidID(id) then return id end
		local quest = frame.Quest
		if type(quest) == "table" and type(quest.IsComplete) == "function" and ValidID(quest.Id) then
			return quest.Id
		end
		local module = frame.parentModule
		if module ~= nil and (module == QuestObjectiveTracker or module == CampaignQuestObjectiveTracker)
			and ValidID(frame.id) then
			return frame.id
		end
		frame = frame.GetParent and frame:GetParent()
	end
end

local function OnMouseUp(frame, button)
	if button == "MiddleButton" then
		QuestWaypoints:Click(QuestWaypoints.QuestOf(frame))
	end
end

-- Only frames that already take clicks: a mouse script on any other frame could
-- start catching clicks meant for what lies under it.
local function Clickable(frame)
	if type(frame) ~= "table" or not frame.HookScript then return false end
	if frame.IsForbidden and frame:IsForbidden() then return false end
	if frame.IsProtected and frame:IsProtected() then return false end
	local enabled = frame.IsMouseClickEnabled or frame.IsMouseEnabled
	return type(enabled) == "function" and enabled(frame) == true
end

local function Hook(frame)
	if hooked[frame] or not Clickable(frame) then return end
	hooked[frame] = true
	frame:HookScript("OnMouseUp", OnMouseUp)
end

local function HookTree(frame, depth)
	if type(frame) ~= "table" or depth > 3 or (frame.IsProtected and frame:IsProtected()) then return end
	Hook(frame)
	if frame.GetChildren then
		for _, child in ipairs({ frame:GetChildren() }) do
			HookTree(child, depth + 1)
		end
	end
end

-- The quest log's rows, after it lays them out.
local function OnLogUpdate()
	local scroll = QuestScrollFrame
	if type(scroll) ~= "table" then return end
	for _, key in ipairs({ "titleFramePool", "objectiveFramePool" }) do
		local pool = scroll[key]
		if type(pool) == "table" and pool.EnumerateActive then
			for frame in pool:EnumerateActive() do
				Hook(frame)
			end
		end
	end
end

-- An objective tracker block, after it shows a quest: its title, lines and quest icon.
local function OnTrackerUpdate(module, quest)
	local id = type(quest) == "table" and quest.GetID and quest:GetID()
	if not ValidID(id) or type(module.GetExistingBlock) ~= "function" then return end
	local block = module:GetExistingBlock(id)
	if type(block) == "table" then
		HookTree(block, 0)
		Hook(block.poiButton)
	end
end

-- Questie's tracker lines: a fixed pool, made before Questie says it is ready.
function QuestWaypoints:HookQuestie()
	local index = 1
	while _G["linePool" .. index] do
		local line = _G["linePool" .. index]
		Hook(line)
		Hook(line.expandQuest)
		Hook(line.questFocus)
		Hook(line.playButton)
		index = index + 1
	end
	return index > 1
end

-- Each surface: ready() once the game defines what install() hooks.
local SURFACES = {
	{
		ready = function() return type(QuestLogQuests_Update) == "function" end,
		install = function() hooksecurefunc("QuestLogQuests_Update", OnLogUpdate) end,
	},
	{
		ready = function()
			return type(QuestObjectiveTracker) == "table" and type(QuestObjectiveTracker.UpdateSingle) == "function"
		end,
		install = function() hooksecurefunc(QuestObjectiveTracker, "UpdateSingle", OnTrackerUpdate) end,
	},
	{
		ready = function()
			return type(CampaignQuestObjectiveTracker) == "table"
				and type(CampaignQuestObjectiveTracker.UpdateSingle) == "function"
		end,
		install = function() hooksecurefunc(CampaignQuestObjectiveTracker, "UpdateSingle", OnTrackerUpdate) end,
	},
}

local function InstallSurfaces()
	for _, surface in ipairs(SURFACES) do
		if not surface.done and surface.ready() then
			surface.done = true
			surface.install()
		end
	end
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
function QuestWaypoints:OnLogin()
	-- A quest followed in the last session goes on being followed.
	local rec = ns.Navigation:GetSourceWaypoint(SOURCE)
	if rec then
		if ns:GetSetting("questMiddleClick") and ValidID(rec.questID) then
			tracked = rec.questID
		else
			self:Stop(true)
		end
	end
	InstallSurfaces()
	ns:RegisterEvent("ADDON_LOADED", InstallSurfaces)
	local questieHooked = false
	if type(Questie) == "table" and type(Questie.API) == "table" and type(Questie.API.RegisterOnReady) == "function" then
		pcall(Questie.API.RegisterOnReady, function() questieHooked = self:HookQuestie() end)
	end
	ns:RegisterEvent("QUEST_LOG_UPDATE", function()
		-- Questie's tracker turned on later builds its lines then.
		if not questieHooked and _G.linePool1 then
			questieHooked = self:HookQuestie()
		end
		ScheduleCheck()
	end)
	ns:RegisterEvent("PLAYER_ENTERING_WORLD", ScheduleCheck)
	local function Ended(_, questID)
		if questID ~= nil and questID == tracked then
			self:Stop(true)
		end
	end
	ns:RegisterEvent("QUEST_TURNED_IN", Ended)
	ns:RegisterEvent("QUEST_REMOVED", Ended)
	ns:On("WAYPOINT_REMOVED", function(removed)
		-- Removed by the player: the quest is no longer followed.
		if not dropping and type(removed) == "table" and removed.source == SOURCE then
			tracked, signature = nil, nil
		end
	end)
	ns:On("SETTING_CHANGED", function(key)
		if key == "questMiddleClick" and not ns:GetSetting("questMiddleClick") then
			self:Stop(true)
		end
	end)
end
