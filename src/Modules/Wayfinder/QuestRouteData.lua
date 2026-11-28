-- Questie owns its records. Cache only our zone geometry and read character
-- progress afresh each pass. Nothing here changes the tracker or a map frame.
local _, ns = ...
local Data = ns:NewModule("QuestRouteData")
local QW = ns.QuestWaypoints
local empty = {}
local function noop() end
local function safe(value)
	if ns.Readable(value) then return value end
end
local function number(value)
	value = safe(value)
	if type(value) == "number" and value == value and math.abs(value) < math.huge then return value end
end
local function text(value)
	value = safe(value)
	if type(value) == "string" and value ~= "" then return value end
end
local function call(fn, ...)
	if type(fn) ~= "function" then return end
	local ok, a, b = pcall(fn, ...)
	if ok then return safe(a), safe(b) end
end
local function sortedKeys(rows)
	local keys = {}
	for key in pairs(rows or empty) do
		if number(key) then keys[#keys + 1] = key end
	end
	table.sort(keys)
	return keys
end

local geometry, levelsByArea
function Data:Invalidate(id)
	if id and geometry then
		geometry.quests[id], geometry.offers[id] = nil, nil
	else
		geometry = nil
	end
end

-- Questie's spawns are in percent on its AreaTable ID. A dungeon sentinel
-- (-1,-1) and a phased-out coordinate have no outdoor world position.
local function readSpawns(c, groups)
	local points, elsewhere, seen, count = {}, false, {}, 0
	for _, source in pairs(groups or empty) do
		for area, coords in pairs(source.Spawns or empty) do
			local mapped = c.maps[area]
			if mapped == nil then
				mapped = call(c.zones.GetUiMapIdByAreaId, c.zones, area) or false
				c.maps[area] = mapped
			end
			if mapped ~= c.mapID then
				if mapped and next(coords) then elsewhere = true end
			else
				for _, xy in ipairs(coords) do
					count = count + 1
					if count % 48 == 0 then c.tick() end
					local x, y = number(xy[1]), number(xy[2])
					local phase = safe(xy[3])
					if x and y and (x < 0 or y < 0) then elsewhere = true end
					if x and y and x >= 0 and y >= 0 and x <= 100 and y <= 100
						and (not phase or not c.phased or call(c.phased, phase)) then
						local ys = seen[x]
						if not ys then ys = {}; seen[x] = ys end
						if not ys[y] then
							ys[y] = true
							local cont, wx, wy = ns.MapToWorld(mapped, x / 100, y / 100)
							if cont == c.origin.cont and number(wx) and number(wy) then
								points[#points + 1] = { x = wx, y = wy, name = text(source.Name) }
							end
						end
					end
				end
			end
		end
	end
	return points, elsewhere
end

local function addEntity(c, groups, kind, id, friendly)
	if not number(id) or id <= 0 then return end
	local db = c.db
	local get = kind == "object" and db.QueryObjectSingle or db.QueryNPCSingle
	if friendly and kind ~= "object" and not db.IsFriendlyToPlayer(get(id, "friendlyToFaction")) then return end
	local list = get(id, "spawns")
	if list then groups[#groups + 1] = { Name = get(id, "name"), Spawns = list } end
end

local function itemSources(c, groups, itemID)
	local item = c.db:GetItem(itemID)
	if not item or item.Hidden then return end
	for i, source in ipairs(item.Sources or empty) do
		if i % 24 == 0 then c.tick() end
		if source.Type == "monster" or source.Type == "object" then
			addEntity(c, groups, source.Type, source.Id, source.Vendor)
		end
	end
end

local function participantPoints(c, who)
	if not who then return {} end
	local groups = {}
	for _, id in ipairs(who.NPC or who[1] or empty) do addEntity(c, groups, "monster", id, true) end
	for _, id in ipairs(who.GameObject or who[2] or empty) do addEntity(c, groups, "object", id) end
	for _, id in ipairs(who.Item or who[3] or empty) do itemSources(c, groups, id) end
	return readSpawns(c, groups)
end

local function objectiveSources(c, obj)
	if obj.spawnList and next(obj.spawnList) then return obj.spawnList end
	local kind, id = obj.Type, obj.Id
	local groups = {}
	if kind == "monster" or kind == "object" then addEntity(c, groups, kind, id)
	elseif kind == "item" then itemSources(c, groups, id)
	elseif kind == "killcredit" then
		for _, npc in ipairs(obj.IdList or empty) do addEntity(c, groups, "monster", npc) end
	elseif kind == "event" and obj.Coordinates then
		groups[1] = { Spawns = obj.Coordinates, Name = obj.Text }
	elseif kind == "spell" and number(obj.ItemSourceId) and obj.ItemSourceId > 0 then
		itemSources(c, groups, obj.ItemSourceId)
	end
	return groups
end

-- Geometry is immutable until invalidated; candidate ranking is re-evaluated
-- from the current player position. Dense fields keep their best camp even
-- when there are several more isolated camps much closer to the player.
local function d2(a, b) return (a.x - b.x)^2 + (a.y - b.y)^2 end
local function nearer(a, b)
	if a.rank ~= b.rank then return a.rank < b.rank end
	if a.x ~= b.x then return a.x < b.x end
	return a.y < b.y
end
local function keepNearest(choices, candidate, limit)
	local j = #choices
	if j < limit or nearer(candidate, choices[j]) then
		while j > 0 and nearer(candidate, choices[j]) do j = j - 1 end
		table.insert(choices, j + 1, candidate)
		choices[limit + 1] = nil
	end
end
local function nearest(c, points, anchor)
	local choices = {}
	for i, p in ipairs(points) do
		if i % 64 == 0 then c.tick() end
		local candidate = { x = p.x, y = p.y, name = p.name, rank = d2(p, anchor) }
		keepNearest(choices, candidate, 6)
	end
	return choices
end

local function outline(c, camp)
	if camp.outline == nil then
		camp.outline = false
		if #camp.spawns >= 3 then
			-- A fixed number of boundary points keeps hull work bounded even
			-- for a particularly dense nest of creatures.
			local edge = {}
			for i = 1, 12 do
				local angle = i * math.pi / 6
				local dx, dy = math.cos(angle), math.sin(angle)
				local best, score
				for index, p in ipairs(camp.spawns) do
					if index % 96 == 0 then c.tick() end
					local projection = p.x * dx + p.y * dy
					if not score or projection > score then best, score = p, projection end
				end
				edge[i] = best
			end
			local xs, ys = QW.Outline(edge)
			camp.outline = { c = c.origin.cont, xs = xs, ys = ys }
		end
	end
	return camp.outline or nil
end
local function campChoices(c, row, left)
	local choices, densest = {}, row.densest
	for i, camp in ipairs(row.camps) do
		if i % 48 == 0 then c.tick() end
		if left <= 1 or camp.weight >= math.min(left, densest.weight * 0.36) then
			local penalty = QW.CampCost(camp, left, camp.x, camp.y)
			local candidate = { x = camp.x, y = camp.y, penalty = penalty,
				rank = math.sqrt(d2(camp, c.origin)) + penalty, camp = camp }
			keepNearest(choices, candidate, 9)
		end
	end
	local candidates, kept = choices, false
	for _, p in ipairs(candidates) do if p.camp == densest then kept = true end end
	if not kept and densest then
		candidates[#candidates + 1] = { x = densest.x, y = densest.y, camp = densest,
			penalty = QW.CampCost(densest, left, densest.x, densest.y) }
	end
	for _, p in ipairs(candidates) do
		p.area = outline(c, p.camp)
		p.camp, p.rank = nil, nil
	end
	return candidates
end

local function key(c, id, role) return id .. ":" .. role .. ":" .. c.mapID end
local function task(c, quest, role, kind, label, candidates, after, optional)
	local t = { key = key(c, quest.Id, role), questID = quest.Id, quest = quest.name or ("Quest " .. quest.Id),
		label = label, kind = kind, candidates = candidates, after = after, optional = optional }
	return t
end

local function objectives(c, quest, display, cache, after, optional)
	local tasks, missing = {}, nil
	local function add(role, live, metadata, hints)
		if not optional and safe(live.Completed) == true then return end
		local need, got
		if not optional then need, got = number(live.Needed), number(live.Collected) end
		if safe(live.Completed) == nil and need and got and need > 0 and got >= need then return end
		local left = need and math.max(1, need - (got or 0)) or (optional and 5 or 1)
		local label = text(live.Description) or text(metadata.Text) or text(metadata.Description)
		local identity = live.spawnList and next(live.spawnList) and live.spawnList or metadata
		local row = cache[role]
		if not row or row.identity ~= identity or row.hint ~= hints then
			local groups = live.spawnList
			if not groups or not next(groups) then groups = objectiveSources(c, metadata) end
			local points, outside = readSpawns(c, groups)
			if #points == 0 and hints then
				local fallback, off = readSpawns(c, objectiveSources(c, hints))
				points, outside = fallback, outside or off
			end
			local camps = QW.Camps(points, c.tick)
			local densest
			for _, camp in ipairs(camps) do
				if not densest or camp.weight > densest.weight then densest = camp end
			end
			row = { identity = identity, hint = hints, camps = camps, densest = densest,
				target = points[1] and points[1].name, outside = outside }
			cache[role] = row
		end
		label = label or row.target or "Quest objective"
		if not row.densest then
			missing = label .. (row.outside and " is outside this zone" or " has no visible local spawn")
			return
		end
		local t = task(c, quest, role, "objective", label, campChoices(c, row, left), after, optional)
		if got and need and need > 0 then t.progress = ("%d/%d"):format(got, need) end
		tasks[#tasks + 1] = t
	end
	local specials = display.SpecialObjectives or empty
	local hints = {}
	for _, index in ipairs(sortedKeys(specials)) do
		local obj = specials[index]
		if number(obj.RealObjectiveIndex) and obj.RealObjectiveIndex > 0 then hints[obj.RealObjectiveIndex] = obj end
	end
	local rows = optional and quest.ObjectiveData or display.Objectives
	for _, index in ipairs(sortedKeys(rows)) do
		local row = rows[index]
		local nativeIndex = number(row.NativeIndex) or index
		add("o" .. nativeIndex, row, quest.ObjectiveData and quest.ObjectiveData[nativeIndex] or row, hints[nativeIndex])
	end
	for _, index in ipairs(sortedKeys(specials)) do
		local obj = specials[index]
		if not number(obj.RealObjectiveIndex) or obj.RealObjectiveIndex <= 0 then add("s" .. index, obj, obj) end
	end
	return tasks, missing
end

local function markerPositions(c)
	local result = {}
	local markers = call(C_QuestLog and C_QuestLog.GetQuestsOnMap, c.mapID)
	for _, marker in ipairs(markers or empty) do
		local id, x, y = number(marker.questID), number(marker.x), number(marker.y)
		if id and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
			local cont, wx, wy = ns.MapToWorld(c.mapID, x, y)
			if cont == c.origin.cont then result[id] = { x = wx, y = wy } end
		end
	end
	return result
end

local function addQuest(c, result, quest, display, pickup, complete)
	local id, optional = quest.Id, pickup ~= nil
	local cache = c.cache.quests[id]
	if not cache then cache = {}; c.cache.quests[id] = cache end
	local after = pickup and {pickup.key} or {}
	local work, missing = {}, nil
	if not complete then
		work, missing = objectives(c, quest, display, cache, after, optional)
		if optional and #work == 0 and math.floor((quest.specialFlags or 0) / 2) % 2 == 1 then
			missing = missing or "event location unknown"
		elseif not optional and #work == 0 then
			missing = missing or "waiting for Questie to locate the remaining work"
		end
	end
	if optional then result.tasks[#result.tasks + 1] = pickup end
	local finisher
	if c.opts.turnins ~= false and not missing then
		cache.finish = cache.finish or participantPoints(c, quest.Finisher or quest.finishedBy)
		local marker = complete and c.markers[id]
		local candidates = nearest(c, cache.finish, marker or c.origin)
		-- Use the native hint only to resolve alternate Questie finishers.
		-- A generic or stale map marker must not invent a local hand-in.
		if marker and candidates[1] and d2(marker, candidates[1]) < 100^2 then candidates = {candidates[1]} end
		if candidates[1] then
			local deps = {}
			for _, t in ipairs(work) do deps[#deps + 1] = t.key end
			if pickup and #deps == 0 then deps[1] = pickup.key end
			finisher = task(c, quest, "end", "turnin", "Turn in " .. quest.name, candidates, deps, optional)
		else
			result.why[#result.why + 1] = quest.name .. " — turn-in outside this zone or unknown"
			if optional then return end
		end
	end
	if missing then result.why[#result.why + 1] = quest.name .. " — " .. missing end
	if optional and missing then return end
	for _, t in ipairs(work) do result.tasks[#result.tasks + 1] = t end
	if finisher then result.tasks[#result.tasks + 1] = finisher end
end

local function allowsLevel(c, id, level)
	local mode = c.opts.levelWindow or "range"
	if mode == "any" then return true end
	if mode == "green" then
		local compat = c.modules.QuestieCompat
		local difficulty = compat and call(compat.GetQuestDifficulty, id)
		if number(difficulty) and Enum and Enum.RelativeContentDifficulty then
			return difficulty == Enum.RelativeContentDifficulty.Easy
		end
		local green = compat and call(compat.GetQuestGreenRange)
		return number(green) and level < c.level - 2 and level >= c.level - green
	end
	local above, below = c.opts.levelAbove or 3, c.opts.levelBelow or 6
	if mode == "above" then return level <= c.level + above end
	if mode == "below" then return level >= c.level - below end
	return level >= c.level - below and level <= c.level + above
end

local function addOffer(c, result, id)
	local points = c.cache.offers[id]
	if not points then
		points = participantPoints(c, c.db.QueryQuestSingle(id, "startedBy"))
		c.cache.offers[id] = points
	end
	if #points == 0 then return end
	local quest = c.db.GetQuest(id)
	if not quest or not text(quest.name) then return end
	local why
	local level = number(quest.level) or number(quest.questLevel) or c.level
	if level <= 0 then level = c.level end
	if not allowsLevel(c, id, level) then
		why = "outside the pickup level window"
	elseif c.modules.QuestieProfessions then
		local prof = c.modules.QuestieProfessions
		local required = quest.requiredSkill or c.professions[quest.zoneOrSort]
		if required then
			local learned, skilled = call(prof.HasProfessionAndSkillLevel, prof, required)
			if not learned or not skilled then why = "required profession or skill missing" end
		end
	end
	if not why and c.db.IsDoable and call(c.db.IsDoable, id) ~= true then why = "Questie reports unmet requirements" end
	if why then result.why[#result.why + 1] = quest.name .. " — " .. why; return end
	local pickup = task(c, quest, "start", "pickup", "Pick up " .. quest.name, nearest(c, points, c.origin), {}, true)
	addQuest(c, result, quest, quest, pickup, false)
end

local function hostileTowns(c)
	local module = c.modules.Townsfolk
	local groups = module and module.townsfolk
	if not groups or not groups.Innkeeper then return {} end
	if c.cache.towns then return c.cache.towns end
	local faction = c.modules.QuestiePlayer.faction
	local enemy = faction == "Alliance" and "H" or faction == "Horde" and "A"
	if not enemy then return {} end
	local ids = {}
	for _, category in ipairs({"Flight Master", "Innkeeper", "Banker", "Auctioneer"}) do
		for _, id in ipairs(groups[category] or empty) do ids[id] = true end
	end
	local towns = {}
	for _, id in ipairs(sortedKeys(ids)) do
		c.tick()
		local get = c.db.QueryNPCSingle
		if get(id, "friendlyToFaction") == enemy then
			local points = readSpawns(c, {{Spawns = get(id, "spawns")}})
			for _, p in ipairs(points) do
				local closest, best = nil, 170^2
				for _, town in ipairs(towns) do
					local d = d2(p, town)
					if d < best then closest, best = town, d end
				end
				if closest then closest.radius = math.max(closest.radius, math.sqrt(best) + 95)
				else towns[#towns + 1] = {x=p.x, y=p.y, radius=95} end
			end
		end
	end
	c.cache.towns = towns
	return towns
end

-- Compute a zone's usual quest levels independently of the player's log
-- size or current availability filters. Count repeated levels in a histogram.
local function levelRange(c)
	if not c.db.QuestPointers or not c.zones.GetAreaIdByUiMapId then return end
	if not levelsByArea or levelsByArea.ids ~= c.db.QuestPointers then
		local histograms = {}
		local count = 0
		for id in pairs(c.db.QuestPointers) do
			count = count + 1
			if count % 12 == 0 then c.tick() end
			local area = c.db.QueryQuestSingle(id, "zoneOrSort")
			if number(area) and area > 0 then
				local level = c.db.QueryQuestSingle(id, "questLevel")
				if number(level) and level > 0 then
					local hist = histograms[area]
					if not hist then hist = { total = 0 }; histograms[area] = hist end
					hist[level] = (hist[level] or 0) + 1
					hist.total = hist.total + 1
				end
			end
		end
		levelsByArea = {ids=c.db.QuestPointers, histograms=histograms}
	end
	local zone = call(c.zones.GetAreaIdByUiMapId, c.zones, c.mapID)
	local hist = levelsByArea.histograms[zone]
	if not hist then return end
	local count, low = 0, nil
	for _, level in ipairs(sortedKeys(hist)) do
		count = count + hist[level]
		if not low and count >= hist.total * 0.1 then low = level end
		if count >= hist.total * 0.9 then
			return low == level and tostring(level) or ("%d–%d"):format(low, level)
		end
	end
end

local function collectActive(c, result, id, acceptance)
	local quest = acceptance.quest or c.db.GetQuest(id)
	if not quest or not text(quest.name) then
		result.why[#result.why + 1] = ("Quest %d — waiting for Questie data"):format(id)
		return
	end
	local display = call(c.modules.TrackerMapEligibility and c.modules.TrackerMapEligibility.RefreshAndGetCapabilities, id)
	display = display or quest
	local nativeComplete = call(C_QuestLog and C_QuestLog.IsComplete, id)
	if safe(display.completionState) == -1 then
		result.why[#result.why + 1] = quest.name .. " — quest failed"
	elseif safe(display.objectivesLoaded) == false and not nativeComplete then
		result.why[#result.why + 1] = quest.name .. " — waiting for quest objectives"
	else
		addQuest(c, result, quest, display, nil, nativeComplete == true or safe(display.isComplete) == true
			or safe(display.completionState) == 1)
	end
end

function Data:Collect(mapID, origin, opts, tick)
	local modules = QuestieLoader and QuestieLoader._modules
	if not (Questie and Questie.API and Questie.API.isReady and modules and modules.QuestieDB
		and modules.ActiveQuests and modules.ActiveQuests.GetAll and modules.ZoneDB and modules.QuestiePlayer) then
		return nil, "Waiting for Questie and its Forever quest database"
	end
	local db = modules.QuestieDB
	if not (db.QueryQuestSingle and db.QueryNPCSingle and db.QueryObjectSingle and db.GetQuest and db.IsFriendlyToPlayer) then
		return nil, "Questie's Forever quest API is unavailable"
	end
	if not geometry or geometry.mapID ~= mapID or geometry.db ~= db then
		geometry = { mapID = mapID, db = db, quests = {}, offers = {}, maps = {} }
	end
	local c = { mapID=mapID, origin=origin, opts=opts or {}, tick=tick or noop, db=db,
		modules=modules, zones=modules.ZoneDB, maps=geometry.maps, cache=geometry,
		level=call(modules.QuestiePlayer.GetPlayerLevel) or 1, phased=modules.Phasing and modules.Phasing.IsSpawnVisible }
	c.markers, c.professions = markerPositions(c), {}
	local professions = modules.QuestieProfessions
	if c.opts.pickups and professions and professions.GetSortIdByProfessionId then
		for _, skill in pairs(professions.professionKeys or empty) do
			local sort = professions:GetSortIdByProfessionId(skill)
			if sort then c.professions[sort] = {skill, 1} end
		end
	end
	local result = {tasks={}, why={}, towns={}, slots=0, activeIDs={}, availableIDs={}}
	local active = modules.ActiveQuests.GetAll()
	local ids = sortedKeys(active)
	-- Snapshot map membership before yielding. Questie replaces its active
	-- map during rebuilds and mutates the available set as quests change.
	local offers = modules.AvailableQuests and modules.AvailableQuests.__availableQuests
	for id, yes in pairs(offers or empty) do if yes then result.availableIDs[id] = true end end
	for _, id in ipairs(ids) do result.activeIDs[id] = true end
	local max = call(C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept) or number(MAX_QUESTLOG_QUESTS)
	local _, used = call(C_QuestLog and C_QuestLog.GetNumQuestLogEntries)
	if number(max) then result.slots = math.max(0, max - math.max(number(used) or 0, #ids)) end
	for _, id in ipairs(ids) do
		c.tick()
		if active[id] then collectActive(c, result, id, active[id]) end
	end
	if c.opts.pickups then
		for _, id in ipairs(sortedKeys(result.availableIDs)) do
			c.tick()
			if not result.activeIDs[id] then addOffer(c, result, id) end
		end
	end
	if c.opts.avoidTowns then result.towns = hostileTowns(c) end
	result.levels = levelRange(c)
	return result
end
