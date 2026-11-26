-- Mini QoL packaging adapter; upstream source and credits follow.
MiniQoLRuntime:Execute("Wayfinder", function(...)
local _, ns = ...
local Finder = ns.TargetFinder
local Read, Text = Finder.Read, Finder.Text

local function ObjectiveName(text)
	text = Text(text)
	if not text then return end
	text = text:gsub("^%d+%s*/%s*%d+%s+", ""):gsub("%s*:%s*%d+%s*/%s*%d+%s*$", "")
	return Text((text:gsub("%s+slain$", "")))
end

-- Questie's live tracker matches each displayed row to its sources, including
-- alternate kill credits, item droppers, vendors and lootable objects.
local function QuestieTargets(id, add, found)
	local modules = QuestieLoader and QuestieLoader._modules
	local tracker = modules and modules.TrackerData
	local quest = tracker and Read(tracker.RefreshQuest, id)
	if not quest then return end
	local function sources(row, index)
		if row.Completed then return end
		for _, spawn in pairs(row.spawnList or {}) do
			local key = Text(spawn.TooltipKey)
			local kind, entry
			if key then kind, entry = key:match("^([mo])_(%d+)$") end
			if kind and add(spawn.Name, kind == "m" and "mob" or "object", tonumber(entry)) and index then
				found[index] = true
			end
		end
	end
	for i, row in ipairs(quest.Objectives or {}) do sources(row, row.NativeIndex or i) end
	for _, row in pairs(quest.SpecialObjectives or {}) do sources(row) end
	return quest
end

local function PolestarTargets(db, objective, add)
	if objective.kind == "item" then
		local item = Read(db.GetItem, objective.id)
		if not item then return end
		local any = false
		for _, key in ipairs({ "droppers", "objects", "vendors" }) do
			for _, entity in ipairs(item[key] or {}) do
				if add(entity.name, key == "objects" and "object" or "mob", entity.id) then any = true end
			end
		end
		return any
	elseif objective.kind == "kill" or objective.kind == "talk" or objective.kind == "object" then
		local object = objective.kind == "object"
		return add(Read(db.EntityName, object and -objective.id or objective.id), object and "object" or "mob", objective.id)
	end
end

function Finder:ResolveQuest(id, group, force)
	local log = C_QuestLog
	local native = Read(log and log.GetQuestObjectives, id)
	local complete = Read(log and log.IsComplete, id) == true
	local signature = { complete and "turnin" or "open" }
	for _, row in ipairs(native or {}) do
		signature[#signature + 1] = (Text(row.type) or "") .. (ObjectiveName(row.text) or "")
			.. (ns.Readable(row.finished) and row.finished and "+" or "-")
	end
	local state = table.concat(signature, "\n")
	if not force and self.signatures[id] == state and #group.targets > 0 then return end
	self.signatures[id] = state
	local list, seen, found = {}, {}, {}
	local function add(name, kind, entityID)
		name = Text(name)
		if not name then return false end
		local key = kind .. ":" .. (entityID or name:lower())
		if not seen[key] then
			seen[key] = true
			list[#list+1] = { name = name, kind = kind, id = entityID }
		end
		return true
	end
	local ps = Polestar and Polestar.QuestDB
	local quest = ps and Read(ps.GetQuest, id)
	if complete then
		local modules = QuestieLoader and QuestieLoader._modules
		local db = modules and modules.QuestieDB
		local q = db and Read(db.GetQuest, id)
		for _, kind in ipairs({ "mob", "object" }) do
			local mob = kind == "mob"
			local lookup = db and (mob and db.QueryNPCSingle or db.QueryObjectSingle)
			for _, entry in pairs(q and q.Finisher and q.Finisher[mob and "NPC" or "GameObject"] or {}) do
				add(Read(lookup, entry, "name"), kind, entry)
			end
			for _, entry in ipairs(quest and quest.finish and quest.finish[mob and "npc" or "object"] or {}) do
				add(Read(ps.EntityName, mob and entry or -entry), kind, entry)
			end
		end
	else
		QuestieTargets(id, add, found)
		for index, row in ipairs(native or {}) do
			if ns.Readable(row.finished) and not row.finished and not found[index] then
				local objective = quest and quest.objectives and quest.objectives[index]
				local kind = Text(row.type)
				-- Only use a database row of the corresponding objective type.
				local mapped = objective and (kind == objective.kind or (kind == "monster" and
					(objective.kind == "kill" or objective.kind == "talk")))
				if not (mapped and PolestarTargets(ps, objective, add)) then
					-- A collection line alone identifies no dropper. It can still
					-- match a live ground object bearing the item's exact name.
					if kind == "monster" or kind == "object" or kind == "item" then
						add(ObjectiveName(row.text), kind == "monster" and "mob" or "object")
					end
				end
			end
		end
	end
	table.sort(list, function(a,b)
		if a.name ~= b.name then return a.name < b.name end
		if a.kind ~= b.kind then return a.kind < b.kind end
		return (a.id or 0) < (b.id or 0)
	end)
	group.title = Text(Read(log and log.GetTitleForQuestID, id)) or group.title or ("Quest " .. id)
	group.targets = list
	return true
end

function Finder:ImportQuest(id)
	if type(id) ~= "number" or not self.db then return end
	local group = self.db.quests[id] or { targets = {} }
	group.excluded = nil
	self:ResolveQuest(id, group, true)
	self.db.quests[id] = group
	self:Reindex()
	self:Open()
end

function Finder:WatchQuests()
	self.signatures = {}
	local pending
	local function update()
		if pending or not next(self.db.quests) then return end
		pending = true
		C_Timer.After(0.4, function()
			pending = false
			local changed = false
			for id, group in pairs(self.db.quests) do
				if Read(C_QuestLog and C_QuestLog.IsOnQuest, id) == false
					and (Read(C_QuestLog.GetNumQuestLogEntries) or 0) > 0 then
					self.db.quests[id], self.signatures[id] = nil, nil
					changed = true
				elseif self:ResolveQuest(id, group) then changed = true end
			end
			if changed then self:Reindex() end
		end)
	end
	for _, event in ipairs({ "QUEST_LOG_UPDATE", "PLAYER_ENTERING_WORLD" }) do ns:RegisterEvent(event, update) end
	ns:RegisterEvent("ADDON_LOADED", function(_, addon)
		if addon == "Polestar_QuestDB" or addon == "Questie" then wipe(self.signatures); update() end
	end)
	for _, event in ipairs({ "QUEST_TURNED_IN", "QUEST_REMOVED" }) do
		ns:RegisterEvent(event, function(_, id)
			if id and self.db.quests[id] then
				self.db.quests[id], self.signatures[id] = nil, nil
				self:Reindex()
			end
		end)
	end
	if Questie and Questie.API and Questie.API.RegisterOnReady then
		pcall(Questie.API.RegisterOnReady, function() wipe(self.signatures); update() end)
	end
	update()
end

end)
