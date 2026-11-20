-- Elemental Convergences, put on the map as a Skyborne comes across them.
--
-- Skysight, cast within 25 yards of a convergence, leaves its caster Charged
-- for an hour. Those are the game's own figures: Skysight is spell 1259686,
-- Charged 1270893, and the convergence a spell focus 25 yards across. Nothing
-- lists where the convergences are.
--
-- An addon can't see the world, only what the game says about it, and seeing a
-- convergence says nothing of where it is: one is drawn from hundreds of yards
-- off, so the mouse can rest on one that is nowhere near. A convergence goes
-- on the map only by something that says where it is:
--   * the game's own marker for it on the minimap: exactly there, with nothing
--     done, as soon as the game shows it. The game lists some markers for
--     addons; one it only draws is found by asking what is under each point of
--     the minimap, as if the mouse were there;
--   * the mouse held over that marker on the minimap: the spot under the
--     cursor, where the minimap can't be asked;
--   * the game picking it as what the Interact Key would use: beside it;
--   * Skysight leaving the player Charged: within 25 yards of the cast.
-- Each later sign of the same convergence only places it better; there is one
-- record for each. It shows on the maps like any other location, to Skyborne
-- characters only.
--
-- /wf convergence marks one by hand where you stand. Shift-click an icon on
-- the map removes one.
local _, ns = ...

local Convergences = ns:NewModule("Convergences")

local SKYSIGHT = 1259686        -- the Skyborne racial
local CHARGED = 1270893         -- what it leaves its caster with at a convergence
-- The convergence's game objects: the starting zone's, the wider world's, and
-- the unseen one the game sets down beside each. Others are learned as met.
local OBJECTS = { [460001] = true, [616992] = true, [616510] = true }
local RACE = "Skyborne"
local CATEGORY = "convergence"
local NAME = "Elemental Convergence"
local FOCUS_YARDS = 25          -- how near one a cast must be: the game's figure
local LONG_SECONDS = 50 * 60    -- a boon this long was given at a convergence
local FRESH_SECONDS = 3         -- the buff began with the cast, give or take
local CHECKS = { 0.1, 0.5, 1.5 } -- seconds after the cast to look for the buff
local MARKER_YARDS = 3          -- the game's own marker: exact
local MARK_YARDS = 6            -- marked by hand, standing at it
local INTERACT_YARDS = 8        -- within reach of it
local BLIP_PIXELS = 6           -- half the width of a marker on the minimap
local RIM = 0.88                -- a marker further out than this may be one held at the edge for something beyond it
local APPROXIMATE_YARDS = 20    -- placed no better than this, it is still being looked for
local CELL = 12                 -- minimap units between the points asked about: close enough that no marker falls between them
local FINE = 4                  -- and between the points that find its middle
local REACH = 20                -- how far around a find those are tried
local SLICE = 60                -- points of the first kind asked about in one frame
local TICK = 2                  -- seconds between deciding whether to go over the minimap
local MOVED_YARDS = 30          -- it is gone over again once the player has moved this far
local SEEN_SECONDS = 90         -- or, this long after one is seen, wherever the player stands: time to walk up to it
local CAST_SECONDS = 20         -- and this long after a cast finds one: its marker is on the minimap already
local SAME_YARDS = 60           -- signs this close together are of one convergence
local KNOWN_YARDS = 300         -- one on the map this near is the one in sight
local OLD_SIGHTING_YARDS = 40   -- what earlier versions gave one merely seen
local OLD_CAST_YARDS = 10       -- and one Skysight was cast near
local SIGHT_EVERY = 10          -- seconds between looks while the mouse rests on one
local POINT_EVERY = 2           -- and between records while it rests on a marker
local SCAN_DELAY = 1            -- seconds: minimap markers change in bursts
local TRACE_KEPT = 12           -- signs remembered, newest last
local TRACE_MARKERS = 8         -- minimap markers noted with each
local TRACE_GAP = 60            -- seconds within which a repeated sign replaces the last
-- The markers the game gives chests, rares and events: never a convergence's.
local STOCK_MARKERS = { VignetteLoot = true, VignetteLootElite = true, VignetteKill = true,
	VignetteKillElite = true, VignetteEvent = true, VignetteEventElite = true }

local pending          -- the cast whose buff is being looked for
local lastSight, lastPoint = -math.huge, -math.huge
local seenMarkers = {} -- minimap markers already recorded this session
local scanPending = false
local hinted = false   -- said once a session, when one in sight can't be placed
local sweep            -- the going-over of the minimap under way: { cells, index, found }
local lastSweep        -- where the player stood for the last one
local searchUntil = -math.huge -- a sign said one is near: look for its marker until then
local sweepBroken = false      -- the game refused the asking: not tried again this session

local function Number(value)
	return ns.Readable(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function Position()
	local cont, wx, wy, mapID = ns.GetPlayerWorld()
	if cont then
		return { cont = cont, wx = wx, wy = wy, mapID = mapID }
	end
end

-- What has been learned of how the game marks convergences, and the last few
-- signs of one. The signs are kept because none of this can be tried outside
-- the game: when a convergence goes unrecorded, they say what the game showed.
local function Store()
	local store = ns.db.convergence
	if type(store) ~= "table" then
		store = {}
		ns.db.convergence = store
	end
	store.objects = store.objects or {}
	store.markers = store.markers or {}
	store.trace = store.trace or {}
	return store
end

-- A GUID's kind and entry: "GameObject-0-<server>-<instance>-<zone>-<entry>-<spawn>".
local function ObjectOf(guid)
	if not ns.Readable(guid) or type(guid) ~= "string" then return nil end
	local kind, entry = guid:match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)")
	return kind, tonumber(entry)
end

local function IsConvergenceObject(guid)
	local kind, entry = ObjectOf(guid)
	return kind == "GameObject" and entry ~= nil and (OBJECTS[entry] or Store().objects[entry]) == true
end

-- "Elemental Convergence", and what the languages near English make of it.
local function IsItsName(name)
	return ns.Readable(name) and type(name) == "string" and name:lower():find("[ck]onverg") ~= nil
end

function Convergences:IsSkyborne()
	return ns.playerRace == RACE
end

-- The convergence already on the map within `yards` of `pos`, if any.
function Convergences:Near(pos, yards)
	return (ns.Database:FindNearest(pos.cont, pos.wx, pos.wy, yards, function(rec)
		return rec.kind == "obj" and rec.cats[CATEGORY] == true
	end))
end

-- Puts a convergence on the map at `pos`, or places the one already there better.
function Convergences:Record(pos, accuracy, source)
	local rec, isNew = ns.Database:RecordObject({
		cat = CATEGORY, source = source, name = NAME,
		cont = pos.cont, wx = pos.wx, wy = pos.wy, mapID = pos.mapID,
		accuracy = accuracy, within = SAME_YARDS,
	})
	if rec and isNew and source then
		if accuracy > APPROXIMATE_YARDS then
			ns.Print(("Elemental Convergence found within %d yards of here. It is on your map as approximate until the game shows its place; /wf convergence, standing in it, places it by hand."):format(accuracy))
		else
			ns.Print("Elemental Convergence found. It is on your map now; Shift-click its icon to remove it.")
		end
	end
	return rec, isNew
end

---------------------------------------------------------------------------
-- The game's marker on the minimap
---------------------------------------------------------------------------
local function Markers()
	local api = C_VignetteInfo
	if not (api and api.GetVignettes and api.GetVignetteInfo and api.GetVignettePosition) then return {} end
	local ok, list = pcall(api.GetVignettes)
	return ok and type(list) == "table" and list or {}
end

local function MarkerInfo(marker)
	if not ns.Readable(marker) then return nil end
	local ok, info = pcall(C_VignetteInfo.GetVignetteInfo, marker)
	if ok and ns.Readable(info) and type(info) == "table" then return info end
end

-- The marker's place on the player's map, or on the first parent map that has it.
local function MarkerPosition(marker)
	local mapID = C_Map.GetBestMapForUnit("player")
	for _ = 1, 4 do
		if not Number(mapID) or mapID == 0 then return nil end
		local ok, position = pcall(C_VignetteInfo.GetVignettePosition, marker, mapID)
		if ok and ns.Readable(position) and type(position) == "table" then
			local x, y = position.x, position.y
			if position.GetXY then x, y = position:GetXY() end
			if Number(x) and Number(y) and (x ~= 0 or y ~= 0) then
				local cont, wx, wy = ns.MapToWorld(mapID, x, y)
				if cont then
					return { cont = cont, wx = wx, wy = wy, mapID = mapID }
				end
			end
		end
		local info = C_Map.GetMapInfo(mapID)
		mapID = info and info.parentMapID
	end
end

-- A convergence's marker: one on a convergence's object, of a kind learned to
-- be one, or named as one.
local function IsConvergenceMarker(info)
	if IsConvergenceObject(info.objectGUID) then return true end
	if Number(info.vignetteID) and Store().markers[info.vignetteID] then return true end
	return IsItsName(info.name)
end

function Convergences:OnMarker(marker)
	if not ns.Readable(marker) or seenMarkers[marker] then return false end
	local info = MarkerInfo(marker)
	if not info or not IsConvergenceMarker(info) then return false end
	-- A marker the game hasn't placed yet is looked at again when it next changes.
	local pos = MarkerPosition(marker)
	if not pos then return false end
	seenMarkers[marker] = true
	-- The game lists convergences' markers: there is no need to go looking for them.
	Store().listed = true
	return self:Record(pos, MARKER_YARDS, "vignette") ~= nil
end

function Convergences:ScanMarkers()
	scanPending = false
	for _, marker in ipairs(Markers()) do
		self:OnMarker(marker)
	end
end

-- A convergence is known to be within `reach` yards of `pos`. A marker the
-- game lists that near, and not a chest's or a rare's, is the convergence's:
-- its place is returned, and its kind is remembered so the next one is known
-- the moment the game shows it.
function Convergences:LearnMarker(pos, reach)
	local best, bestInfo, bestDistance
	for _, marker in ipairs(Markers()) do
		local info = MarkerInfo(marker)
		local kind = info and ObjectOf(info.objectGUID)
		if info and (kind == nil or kind == "GameObject") and not IsConvergenceMarker(info)
			and not (ns.Readable(info.atlasName) and STOCK_MARKERS[info.atlasName]) then
			local where = MarkerPosition(marker)
			local distance = where and where.cont == pos.cont and ns.Distance(where.wx, where.wy, pos.wx, pos.wy)
			if distance and distance <= reach and (not bestDistance or distance < bestDistance) then
				best, bestInfo, bestDistance = where, info, distance
			end
		end
	end
	if not best then return nil end
	local store = Store()
	local kind, entry = ObjectOf(bestInfo.objectGUID)
	if kind == "GameObject" and entry then store.objects[entry] = true end
	if Number(bestInfo.vignetteID) then store.markers[bestInfo.vignetteID] = true end
	return best
end

---------------------------------------------------------------------------
-- The mouse: on one in the world, and on its marker on the minimap
---------------------------------------------------------------------------
-- Whether a tooltip names a convergence: on its name line, the line marked as
-- one or else the first (a world object's tooltip); or on any line (the
-- minimap's, which lists every marker under the mouse).
local function Names(data, anyLine)
	if not ns.Readable(data) or type(data) ~= "table" or type(data.lines) ~= "table" then return false end
	local nameLine = data.lines[1]
	local nameType = Enum.TooltipDataLineType and Enum.TooltipDataLineType.UnitName
	for _, line in ipairs(data.lines) do
		if type(line) == "table" then
			if anyLine then
				if IsItsName(line.leftText) then return true end
			elseif nameType ~= nil and ns.Readable(line.type) and line.type == nameType then
				nameLine = line
				break
			end
		end
	end
	return not anyLine and type(nameLine) == "table" and IsItsName(nameLine.leftText)
end

-- The mouse is on a convergence somewhere in view. That places nothing, but it
-- is a moment to look at what the game is marking, and to say how one gets
-- placed if this one hasn't been.
function Convergences:OnSight()
	local now = GetTime()
	if now - lastSight < SIGHT_EVERY then return false end
	lastSight = now
	self:ScanMarkers()
	local pos = Position()
	if not pos then return false end
	self:Trace("sight", pos)
	local known = self:Near(pos, KNOWN_YARDS)
	if not (known and (known.a or 0) <= APPROXIMATE_YARDS) then self:Search(SEEN_SECONDS) end
	if not hinted and not known then
		hinted = true
		ns.Print("Elemental Convergence in sight. It is added to your map once it shows on your minimap; holding the mouse over it there, or casting Skysight beside it, adds it too.")
	end
	return true
end

-- How the minimap lies over the world just now, or nil where that can't be told.
local function MinimapView()
	if not (Minimap and Minimap.GetCenter and C_Minimap and C_Minimap.GetViewRadius) then return nil end
	local radius = C_Minimap.GetViewRadius()
	local halfW, halfH = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
	local centreX, centreY = Minimap:GetCenter()
	local scale = Minimap:GetEffectiveScale()
	if not (Number(radius) and radius > 0 and Number(halfW) and halfW >= 16 and Number(halfH) and halfH >= 16
		and Number(centreX) and Number(centreY) and Number(scale) and scale > 0) then
		return nil
	end
	local facing = 0
	if GetCVarBool and GetCVarBool("rotateMinimap")
		and not (C_Minimap.IsRotateMinimapIgnored and C_Minimap.IsRotateMinimapIgnored()) then
		-- A minimap that turns with the player can't be read without the facing.
		facing = GetPlayerFacing and GetPlayerFacing()
		if not Number(facing) then return nil end
	end
	local pos = Position()
	if not pos then return nil end
	return { radius = radius, halfW = halfW, halfH = halfH, centreX = centreX, centreY = centreY, scale = scale,
		cosine = math.cos(facing), sine = math.sin(facing), pos = pos,
		square = GetMinimapShape ~= nil and GetMinimapShape() == "SQUARE" }
end

-- The place in the world `px`, `py` minimap units right of and above its middle.
local function PlaceOn(view, px, py)
	local x, y = px / view.halfW * view.radius, py / view.halfH * view.radius
	local east, north = x * view.cosine - y * view.sine, x * view.sine + y * view.cosine
	return { cont = view.pos.cont, wx = view.pos.wx + north, wy = view.pos.wy - east, mapID = view.pos.mapID }
end

-- Whether that point is well inside the minimap. The game holds some markers
-- at its edge for things beyond it; one there says which way, not where.
local function WellInside(view, px, py)
	local x, y = px / view.halfW, py / view.halfH
	if view.square then return math.abs(x) <= RIM and math.abs(y) <= RIM end
	return x * x + y * y <= RIM * RIM
end

-- The place under the mouse on the minimap, and how far off that may be.
local function UnderMinimapCursor()
	local view = MinimapView()
	if not view or not GetCursorPosition then return nil end
	local cursorX, cursorY = GetCursorPosition()
	if not (Number(cursorX) and Number(cursorY)) then return nil end
	local px, py = cursorX / view.scale - view.centreX, cursorY / view.scale - view.centreY
	if not WellInside(view, px, py) then return nil end
	return PlaceOn(view, px, py), math.max(MARKER_YARDS, BLIP_PIXELS / view.halfW * view.radius)
end

-- The mouse is on a convergence's marker on the minimap: the spot under it is
-- where the convergence is, to within the marker's own width.
function Convergences:OnMinimapPoint()
	local now = GetTime()
	if now - lastPoint < POINT_EVERY then return false end
	local pos, accuracy = UnderMinimapCursor()
	if not pos then return false end
	lastPoint = now
	self:ScanMarkers()
	local rec = self:Record(pos, accuracy, "minimap")
	self:Trace("minimap", pos)
	return rec ~= nil
end

---------------------------------------------------------------------------
-- Asking the minimap
---------------------------------------------------------------------------
-- The game draws a convergence's marker on the minimap whether or not it lists
-- one for addons. What is under any point of the minimap can be asked for, as
-- if the mouse were there, so the minimap is gone over point by point for a
-- marker named as a convergence, and where one answers is where it is.
local function CanAsk()
	return Minimap ~= nil and Minimap.UpdateMouseoverAtPoint ~= nil and Minimap.SetUsingSoftCursor ~= nil
		and C_TooltipInfo ~= nil and C_TooltipInfo.GetMinimapMouseover ~= nil
end

-- Whether what is under that point of the minimap is a convergence's marker.
local function Answers(view, px, py)
	Minimap:UpdateMouseoverAtPoint((view.centreX + px) * view.scale, (view.centreY + py) * view.scale)
	return Names(C_TooltipInfo.GetMinimapMouseover(), true)
end

-- The points to ask about: a grid over the minimap, close enough that no
-- marker falls between them.
local function Cells(view)
	local cells = {}
	for py = -view.halfH + CELL / 2, view.halfH, CELL do
		for px = -view.halfW + CELL / 2, view.halfW, CELL do
			if WellInside(view, px, py) then
				cells[#cells + 1] = { px, py }
			end
		end
	end
	return cells
end

-- Not in a fight, with the minimap hidden, or while the mouse is on it: the
-- asking stands in for the mouse there.
function Convergences:CanSweep()
	if sweepBroken or not CanAsk() then return false end
	if InCombatLockdown and InCombatLockdown() then return false end
	if Minimap.IsVisible and not Minimap:IsVisible() then return false end
	if Minimap.IsMouseOver and Minimap:IsMouseOver() then return false end
	return true
end

-- A sign that a convergence is near without saying where: look for its
-- marker for `seconds`, starting now.
function Convergences:Search(seconds)
	searchUntil = math.max(searchUntil, GetTime() + seconds)
	C_Timer.After(0, function() self:OnTick() end)
end

-- Goes over some of the minimap, and the rest in the frames that follow.
function Convergences:ContinueSweep()
	local job = sweep
	if not job then return end
	local view = self:CanSweep() and MinimapView()
	if not view then
		sweep = nil
		return
	end
	local finds, asked = {}, 0
	local ok, problem = pcall(function()
		Minimap:SetUsingSoftCursor(true)
		while job.index <= #job.cells and asked < SLICE do
			local cell = job.cells[job.index]
			job.index, asked = job.index + 1, asked + 1
			local fresh = true
			for _, found in ipairs(job.found) do
				if math.abs(cell[1] - found[1]) <= REACH + CELL and math.abs(cell[2] - found[2]) <= REACH + CELL then
					fresh = false
					break
				end
			end
			if fresh and Answers(view, cell[1], cell[2]) then
				-- Its middle: the middle of the points around here that answer for it.
				local sumX, sumY, count = 0, 0, 0
				for dy = -REACH, REACH, FINE do
					for dx = -REACH, REACH, FINE do
						if Answers(view, cell[1] + dx, cell[2] + dy) then
							sumX, sumY, count = sumX + cell[1] + dx, sumY + cell[2] + dy, count + 1
						end
					end
				end
				if count > 0 then
					job.found[#job.found + 1] = { sumX / count, sumY / count }
					if WellInside(view, sumX / count, sumY / count) then
						finds[#finds + 1] = PlaceOn(view, sumX / count, sumY / count)
					end
				end
			end
		end
	end)
	pcall(Minimap.SetUsingSoftCursor, Minimap, false)
	local store = Store()
	if not ok then
		sweep, sweepBroken = nil, true
		store.sweepProblem = tostring(problem):sub(1, 200)
		return
	end
	local accuracy = math.max(MARKER_YARDS, FINE / view.halfW * view.radius)
	for _, where in ipairs(finds) do
		store.sweepFinds = (store.sweepFinds or 0) + 1
		self:Record(where, accuracy, "minimap")
		-- A marker the game lists at that spot is this one: its own place is
		-- exact, and its kind is learned for the next.
		local exact = self:LearnMarker(where, accuracy + MARKER_YARDS)
		if exact then self:Record(exact, MARKER_YARDS, "vignette") end
		self:Trace("sweep", where)
	end
	if job.index > #job.cells then
		sweep = nil
		store.sweeps = (store.sweeps or 0) + 1
	else
		C_Timer.After(0, function() self:ContinueSweep() end)
	end
end

-- Every couple of seconds: is the minimap worth going over? Yes while a sign
-- says a convergence is near, or once the player has moved on; no where one
-- is already placed, and no, with nothing saying one is near, once the game
-- is known to list their markers itself.
function Convergences:OnTick()
	if sweep or not self:CanSweep() then return end
	local view = MinimapView()
	if not view then return end
	local pos = view.pos
	local searching = GetTime() < searchUntil
	local moved = not lastSweep or lastSweep.cont ~= pos.cont
		or ns.Distance(lastSweep.wx, lastSweep.wy, pos.wx, pos.wy) >= MOVED_YARDS
	if not searching and not moved then return end
	local known = self:Near(pos, view.radius)
	if known and (known.a or 0) <= APPROXIMATE_YARDS then return end
	if not known and not searching and Store().listed then return end
	lastSweep = pos
	sweep = { cells = Cells(view), index = 1, found = {} }
	self:ContinueSweep()
end

---------------------------------------------------------------------------
-- The Interact Key's pick
---------------------------------------------------------------------------
function Convergences:OnInteractPick(guid)
	local kind, entry = ObjectOf(guid)
	if kind ~= "GameObject" or not entry then return false end
	if not IsConvergenceObject(guid) then
		-- An object not met before: the game names what it picked.
		if type(UnitName) ~= "function" then return false end
		local ok, name = pcall(UnitName, "softinteract")
		if not ok or not IsItsName(name) then return false end
		Store().objects[entry] = true
	end
	local pos = Position()
	return pos ~= nil and self:Record(pos, INTERACT_YARDS, "interact") ~= nil
end

---------------------------------------------------------------------------
-- Skysight leaving the player Charged
---------------------------------------------------------------------------
-- Whether the player has been Charged since the cast at `castAt`: by the
-- buff's ID or, should the game give it under another, by any buff of the
-- player's own making that runs most of an hour. One carried away from an
-- earlier convergence began long before this cast, so a cast elsewhere marks
-- nothing.
local function ChargedSince(castAt)
	local read = C_UnitAuras and C_UnitAuras.GetBuffDataByIndex
	if type(read) ~= "function" then return false end
	for index = 1, 80 do
		local ok, aura = pcall(read, "player", index)
		if not ok or not ns.Readable(aura) or type(aura) ~= "table" then break end
		local duration, expires = aura.duration, aura.expirationTime
		if Number(duration) and Number(expires) and math.abs((expires - duration) - castAt) <= FRESH_SECONDS then
			if ns.Readable(aura.spellId) and aura.spellId == CHARGED then return true end
			if duration >= LONG_SECONDS and ns.Readable(aura.sourceUnit) and aura.sourceUnit == "player" then
				return true
			end
		end
	end
	return false
end

-- A convergence is within FOCUS_YARDS of `pos`. The game's marker for it, if
-- it shows one, says exactly where; without one, the cast's own place stands.
function Convergences:OnCharged(pos)
	self:ScanMarkers()
	-- With a marker already known for the one here, no other marker is it.
	local known = self:Near(pos, FOCUS_YARDS + MARKER_YARDS)
	if not (known and (known.a or math.huge) <= MARKER_YARDS) then
		local where = self:LearnMarker(pos, FOCUS_YARDS + MARKER_YARDS)
		if where then self:Record(where, MARKER_YARDS, "vignette") end
	end
	local rec = self:Record(pos, FOCUS_YARDS, "skysight")
	self:Trace("charged", pos)
	-- Placed only by the cast: its marker is on the minimap, if it has one.
	if rec and (rec.a or 0) > APPROXIMATE_YARDS then self:Search(CAST_SECONDS) end
end

function Convergences:OnSkysight()
	local pos = Position()
	if not pos then return end
	local cast = { at = GetTime(), pos = pos }
	pending = cast
	for index, delay in ipairs(CHECKS) do
		C_Timer.After(delay, function()
			if pending ~= cast then return end
			if ChargedSince(cast.at) then
				pending = nil
				self:OnCharged(cast.pos)
			elseif index == #CHECKS then
				pending = nil
			end
		end)
	end
end

---------------------------------------------------------------------------
-- What the game showed
---------------------------------------------------------------------------
-- A value as it can be saved: itself if plain, a note of what it was if not.
local function Plain(value)
	if value == nil then return nil end
	if not ns.Readable(value) then return "(unreadable)" end
	local kind = type(value)
	if kind == "number" or kind == "string" or kind == "boolean" then return value end
	return "(" .. kind .. ")"
end

local function Rounded(value)
	return value and math.floor(value + 0.5) or nil
end

-- Notes a sign of a convergence with the minimap markers the game is showing
-- just then: which exist, what they are on, where, and whether they were
-- taken for a convergence's.
function Convergences:Trace(why, pos)
	local entry = { why = why, at = time(), map = pos.mapID, x = Rounded(pos.wx), y = Rounded(pos.wy), markers = {} }
	for index, marker in ipairs(Markers()) do
		if index > TRACE_MARKERS then break end
		local info = MarkerInfo(marker)
		if info then
			local kind, id = ObjectOf(info.objectGUID)
			local where = MarkerPosition(marker)
			entry.markers[#entry.markers + 1] = {
				name = Plain(info.name), id = Plain(info.vignetteID), atlas = Plain(info.atlasName),
				object = kind and (kind .. ":" .. tostring(id)) or Plain(info.objectGUID),
				onMinimap = Plain(info.onMinimap),
				x = where and Rounded(where.wx), y = where and Rounded(where.wy),
				taken = IsConvergenceMarker(info) or nil,
			}
		end
	end
	if type(UnitGUID) == "function" then
		local ok, guid = pcall(UnitGUID, "softinteract")
		local kind, id = ObjectOf(ok and guid or nil)
		entry.pick = kind and (kind .. ":" .. tostring(id)) or nil
	end
	local trace = Store().trace
	local last = trace[#trace]
	if last and last.why == why and entry.at - (last.at or 0) < TRACE_GAP then
		trace[#trace] = entry
	else
		trace[#trace + 1] = entry
	end
	while #trace > TRACE_KEPT do table.remove(trace, 1) end
end

---------------------------------------------------------------------------
-- By hand, earlier versions' marks, and wiring
---------------------------------------------------------------------------
-- /wf convergence: here, whatever was thought before.
function Convergences:MarkHere()
	if not self:IsSkyborne() then
		ns.Print("Elemental Convergences are for Skyborne: only they are shown them.")
		return false
	end
	local pos = Position()
	if not pos then
		ns.Print("Position unavailable here.")
		return false
	end
	local old = self:Near(pos, SAME_YARDS)
	if old then ns.Database:Remove(old) end
	if not self:Record(pos, MARK_YARDS) then return false end
	self:Trace("hand", pos)
	ns.Print(old and "The Elemental Convergence here is now marked where you stand."
		or "Elemental Convergence marked where you stand.")
	return true
end

-- Earlier versions put a convergence where the player stood on first seeing
-- it, which could be anywhere in view of it, and called a Skysight cast's
-- place exact to ten yards. Once: the first are taken off the map, and the
-- second given the game's 25 yards so that a better sign can replace them.
function Convergences:CorrectOldMarks()
	local store = Store()
	if store.corrected then return end
	store.corrected = true
	local seenOnly = {}
	for _, rec in pairs(ns.db.pois) do
		if rec.kind == "obj" and type(rec.cats) == "table" and rec.cats[CATEGORY] then
			if (rec.a or 0) >= OLD_SIGHTING_YARDS then
				seenOnly[#seenOnly + 1] = rec
			elseif rec.a == OLD_CAST_YARDS then
				rec.a, rec.w = FOCUS_YARDS, 1 / (FOCUS_YARDS * FOCUS_YARDS)
			end
		end
	end
	for _, rec in ipairs(seenOnly) do
		ns.Database:Remove(rec)
	end
	for key, seen in pairs(ns.db.observations or {}) do
		if type(seen) == "table" and seen.cat == CATEGORY and seen.method == "sight" then
			ns.db.observations[key] = nil
		end
	end
end

function Convergences:OnLogin()
	self:CorrectOldMarks()
	if not self:IsSkyborne() then return end
	-- Which of the ways of telling this game has.
	Store().can = {
		markers = C_VignetteInfo ~= nil and C_VignetteInfo.GetVignettes ~= nil,
		point = Enum.TooltipDataType ~= nil and Enum.TooltipDataType.MinimapMouseover ~= nil,
		ask = CanAsk(),
	}
	if C_VignetteInfo and C_VignetteInfo.GetVignetteInfo and C_VignetteInfo.GetVignettePosition then
		ns:RegisterEvent("VIGNETTE_MINIMAP_UPDATED", function(_, marker) self:OnMarker(marker) end)
		if C_VignetteInfo.GetVignettes then
			local function Scan()
				if scanPending then return end
				scanPending = true
				C_Timer.After(SCAN_DELAY, function() self:ScanMarkers() end)
			end
			ns:RegisterEvent("VIGNETTES_UPDATED", Scan)
			ns:RegisterEvent("PLAYER_ENTERING_WORLD", Scan)
		end
	end
	local kinds = TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType
	if kinds and kinds.Object then
		TooltipDataProcessor.AddTooltipPostCall(kinds.Object, function(_, data)
			if Names(data) then self:OnSight() end
		end)
	end
	if kinds and kinds.MinimapMouseover then
		TooltipDataProcessor.AddTooltipPostCall(kinds.MinimapMouseover, function(_, data)
			if Names(data, true) then self:OnMinimapPoint() end
		end)
	end
	if CanAsk() then
		local function Tick()
			self:OnTick()
			C_Timer.After(TICK, Tick)
		end
		C_Timer.After(TICK, Tick)
	end
	ns:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED", function(_, _, guid) self:OnInteractPick(guid) end)
	ns:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
		if ns.Readable(unit) and unit == "player" and ns.Readable(spellID) and spellID == SKYSIGHT then
			self:OnSkysight()
		end
	end)
end
