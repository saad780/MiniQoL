-- Mini QoL packaging adapter; upstream source and credits follow.
MiniQoLRuntime:Execute("Wayfinder", function(...)
-- A character's watch list. Only live unit tokens and client-reported object
-- markers can light the button. Quest databases supply names, never sightings.
local _, ns = ...
local Finder = ns:NewModule("TargetFinder")
local RANGE = 60 -- yards for sightings with a measurable position
local byName, byID, terms = {}, {}, {}
local function EntryKey(entry)
	return entry.kind .. ":" .. (entry.id or entry.name:lower())
end
Finder.EntryKey = EntryKey
local fixedUnits = { "softinteract", "softenemy", "target", "mouseover" }
local plates = {}
for i = 1, 40 do plates[i] = "nameplate" .. i end

local function Read(fn, ...)
	if type(fn) ~= "function" then return end
	local ok, a, b, c, d = pcall(fn, ...)
	if ok and ns.Readable(a) then return a, b, c, d end
end
Finder.Read = Read

local function Text(s)
	if ns.Readable(s) and type(s) == "string" and not s:find("[%c|]") then
		local text = s:match("^%s*(.-)%s*$")
		if text ~= "" then return text end
	end
end
Finder.Text = Text

function Finder:Reindex()
	wipe(byName)
	wipe(byID)
	wipe(terms)
	self.watches = {}
	self.markers = nil
	local function index(entry)
		self.watches[#self.watches + 1] = entry
		if entry.id then byID[entry.kind .. entry.id] = entry end
		local name = entry.name:lower()
		local names = byName[name] or {}
		if not names[entry.kind] or not entry.id then names[entry.kind] = entry end
		byName[name] = names
		if entry.kind == "any" then terms[#terms+1] = { text = name, entry = entry } end
	end
	for _, entry in ipairs(self.db.manual) do index(entry) end
	for _, group in pairs(self.db.quests) do
		for _, entry in ipairs(group.targets) do
			if not (group.excluded and group.excluded[EntryKey(entry)]) then index(entry) end
		end
	end
	self:UpdateList()
	self.button:SetShown(next(byName) ~= nil)
	self:SyncMarkButton()
	self:Scan()
end

function Finder:Add(name, mobID)
	name = Text(name)
	if not name or #name > 120 then return false end
	local lower = name:lower()
	-- Explicitly tracking a name again also restores it to matching searches.
	for _, entry in ipairs(self.db.manual) do
		if entry.excluded then
			entry.excluded["mob:" .. lower], entry.excluded["object:" .. lower] = nil, nil
			if not mobID and entry.name:lower() == lower then entry.excluded = nil end
		end
	end
	for _, entry in ipairs(self.db.manual) do
		if (mobID and entry.id == mobID and entry.kind == "mob")
			or (not mobID and entry.kind == "any" and entry.name:lower() == lower) then self:Reindex(); return true end
	end
	table.insert(self.db.manual, { name = name, kind = mobID and "mob" or "any", id = mobID })
	self:Reindex()
	return true
end

local function Identity(guid)
	if not ns.Readable(guid) or type(guid) ~= "string" then return end
	local kind, id = guid:match("^(%a+)%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)")
	if kind == "GameObject" then return "object", tonumber(id) end
	if kind == "Creature" or kind == "Vehicle" then return "mob", tonumber(id) end
end

function Finder:Untrack(key, name)
	local kind, lower = key:match("^([^:]+):(.+)$")
	if not kind then return end
	local ids = {}
	for _, hit in ipairs(self.hits) do
		if hit.key == key then
			local _, id = Identity(hit.guid)
			if id then ids[id] = true end
		end
	end
	local function exact(entry)
		return (entry.kind == kind or entry.kind == "any")
			and (entry.name:lower() == lower or (entry.id and ids[entry.id]))
	end
	for i = #self.db.manual, 1, -1 do
		local entry = self.db.manual[i]
		if exact(entry) then
			table.remove(self.db.manual, i)
		elseif entry.kind == "any" and lower:find(entry.name:lower(), 1, true) then
			entry.excluded = entry.excluded or {}
			entry.excluded[key] = true
		end
	end
	for _, group in pairs(self.db.quests) do
		for _, entry in ipairs(group.targets) do
			if exact(entry) then
				group.excluded = group.excluded or {}
				group.excluded[EntryKey(entry)] = true
			end
		end
	end
	if self.markedKey == key then self:ClearLocalMark() end
	self:Reindex()
	self:PaintNames(true)
	ns.Print("Stopped tracking " .. name .. ".")
end

local function Match(kind, id, name)
	local entry = id and byID[kind .. id]
	if entry then return entry end
	if not name then return end
	local lower = name:lower()
	local names = byName[lower]
	-- An imported ID distinguishes entities with identical display names.
	if names then
		local typed = names[kind]
		if typed and (not typed.id or not id) then return typed end
		if names.any and not (names.any.excluded and names.any.excluded[kind .. ":" .. lower]) then return names.any end
	end
	for _, term in ipairs(terms) do
		if lower:find(term.text, 1, true) and not (term.entry.excluded and term.entry.excluded[kind .. ":" .. lower]) then return term.entry end
	end
end

local function PlateToken(plate)
	local unit = plate.namePlateUnitToken
	if not ns.Readable(unit) then unit = plate.unitToken end
	if not ns.Readable(unit) and type(plate.UnitFrame) == "table" then unit = plate.UnitFrame.unit end
	if ns.Readable(unit) and type(unit) == "string" and unit:match("^nameplate%d+$") then return unit end
end
Finder.PlateToken = PlateToken

-- Only the top mouse focus owns this gesture. A tracker row can sit over a
-- world unit and already uses Shift-middle for quest imports.
local function WorldMouseUnit()
	local foci = GetMouseFoci and GetMouseFoci()
	local focus = foci and foci[1] or (not foci and GetMouseFocus and GetMouseFocus())
	if not focus or focus == WorldFrame then return "mouseover" end
	local hoveredPlate = Read(C_NamePlate and C_NamePlate.GetNamePlateForUnit, "mouseover")
	local frame = focus
	for _ = 1, 12 do
		if frame and frame == hoveredPlate then return "mouseover" end
		if not frame or frame == UIParent or frame == WorldFrame or (frame.IsForbidden and frame:IsForbidden()) then return end
		local unit = PlateToken(frame)
		if unit and Read(C_NamePlate and C_NamePlate.GetNamePlateForUnit, unit) == frame then return unit end
		frame = frame.GetParent and frame:GetParent()
	end
end

function Finder:WatchWorldClicks()
	local pressed
	local function shifted() return IsShiftKeyDown() and not IsControlKeyDown() and not IsAltKeyDown() end
	ns:RegisterEvent("GLOBAL_MOUSE_DOWN", function(_, button)
		if button ~= "MiddleButton" then return end
		pressed = nil
		local unit = shifted() and WorldMouseUnit()
		local guid = unit and Read(UnitGUID, unit)
		if Identity(guid) == "mob" then pressed = guid end
	end)
	ns:RegisterEvent("GLOBAL_MOUSE_UP", function(_, button)
		if button ~= "MiddleButton" then return end
		local guid = pressed
		pressed = nil
		local unit = guid and shifted() and WorldMouseUnit()
		if not unit or Read(UnitGUID, unit) ~= guid then return end
		local _, id = Identity(guid)
		local name = Text(Read(UnitName, unit))
		if self:Add(name, id) then ns.Print("Tracking " .. name .. ".") end
	end)
end

local function Number(x)
	return ns.Readable(x) and type(x) == "number" and x == x and math.abs(x) < math.huge
end

local function Position(unit)
	local x, y, z, c = Read(UnitPosition, unit)
	if Number(x) and Number(y) and Number(c) and (x ~= 0 or y ~= 0) then return c, x, y, Number(z) and z or nil end
end

function Finder:ClearLocalMark()
	if self.localSkull then self.localSkull:Hide() end
	self.markedUnit, self.markedGUID, self.markedPlate, self.markedKey = nil, nil, nil, nil
end

-- Unit tokens are recycled. Resolve them again on the click and never mark
-- the current target merely because the intended target has disappeared.
local function Nearer(a, b)
	if a.rank ~= b.rank then return a.rank < b.rank end
	return a.guid < b.guid
end

function Finder:Scan(quiet)
	self.best = nil
	local hits, byGUID = self.hits or {}, self.hitsByGUID or {}
	wipe(hits)
	wipe(byGUID)
	self.hits, self.hitsByGUID = hits, byGUID
	if self.markedUnit then
		local guid = Read(UnitGUID, self.markedUnit)
		local kind, id = Identity(guid)
		local raidMark = Read(GetRaidTargetIndex, self.markedUnit)
		if guid ~= self.markedGUID or not self.markedPlate:IsShown()
			or (Number(raidMark) and raidMark > 0)
			or Read(UnitIsDeadOrGhost or UnitIsDead, self.markedUnit) ~= false
			or not Match(kind, id, Text(Read(UnitName, self.markedUnit))) then
			self:ClearLocalMark()
		end
	end
	if not next(byName) then
		if not quiet then self:Paint() end
		return
	end
	local c, px, py, pz = Position("player")
	local mapID = Read(C_Map and C_Map.GetBestMapForUnit, "player")
	if not c then c, px, py, mapID = ns.GetPlayerWorld() end
	local function offer(entry, guid, unit, kind, distance, x, y, approximate, bound, liveName)
		if distance and distance > RANGE * RANGE then return end
		-- A visible nameplate can be readable even where the client withholds
		-- distances. Prefer measured matches, then a stable visible fallback.
		local hit = byGUID[guid]
		if not hit then
			hit = { entry = entry, name = entry.kind == "any" and liveName or entry.name,
				displayName = liveName or entry.name, guid = guid, kind = kind, c = c, m = mapID }
			hits[#hits + 1] = hit
			byGUID[guid] = hit
		end
		-- Prefer a stable plate over target/mouseover aliases for the same mob.
		if unit and (not hit.unit or unit:match("^nameplate")) then hit.unit = unit end
		if x and (not hit.x or not approximate) then hit.x, hit.y, hit.approximate = x, y, approximate end
		hit.distance = distance or hit.distance
		hit.bound = math.min(bound or math.huge, hit.bound or math.huge)
		hit.rank = hit.distance or hit.bound
		hit.key = kind .. ":" .. hit.displayName:lower()
	end
	local function unitMatch(unit, plate)
		local guid = Read(UnitGUID, unit)
		local kind, id = Identity(guid)
		if not kind then return end
		local name = Text(Read(UnitName, unit))
		local entry = Match(kind, id, name)
		if not entry and kind == "object" and unit == "softinteract" then
			local tip = Read(C_TooltipInfo and C_TooltipInfo.GetUnit, unit)
			local line = tip and tip.lines and tip.lines[1]
			name = line and Text(line.leftText)
			entry = Match(kind, id, name)
		end
		if not entry then return end
		if kind == "mob" and Read(UnitIsDeadOrGhost or UnitIsDead, unit) ~= false then return end
		local uc, x, y, z = Position(unit)
		local distance, bound
		if not uc and mapID then
			local pos = Read(C_Map and C_Map.GetPlayerMapPosition, mapID, unit)
			if pos and Number(pos.x) and Number(pos.y) and (pos.x ~= 0 or pos.y ~= 0) then
				uc, x, y = ns.MapToWorld(mapID, pos.x, pos.y)
			end
		end
		if uc and c then
			if uc ~= c then return end
			distance = (px-x)^2 + (py-y)^2
			if pz and z then distance = distance + (pz-z)^2 end
		else
			x, y = nil, nil
			local d, checked = Read(UnitDistanceSquared, unit)
			if Number(d) and d >= 0 and ns.Readable(checked) and checked then distance = d end
			if not distance and not (InCombatLockdown and InCombatLockdown()) then
				if Read(CheckInteractDistance, unit, 3) then bound = 10^2
				elseif Read(CheckInteractDistance, unit, 4) then bound = 28^2 end
			end
		end
		if not distance and not bound and not plate and unit ~= "softinteract" and unit ~= "softenemy"
			and unit ~= "mouseover" and not Read(UnitIsVisible, unit) then return end
		if kind == "object" and not x then
			if unit ~= "softinteract" or not c then return end
			offer(entry, guid, unit, kind, distance, px, py, true, bound, name)
		else
			offer(entry, guid, unit, kind, distance, x, y, nil, bound, name)
		end
	end
	for _, unit in ipairs(fixedUnits) do unitMatch(unit) end
	local visible = Read(C_NamePlate and C_NamePlate.GetNamePlates)
	local foundPlate = false
	if type(visible) == "table" then
		for _, plate in ipairs(visible) do
			if not (plate.IsForbidden and plate:IsForbidden()) then
				local unit = PlateToken(plate)
				if unit then foundPlate = true; unitMatch(unit, true) end
			end
		end
	end
	if not foundPlate then
		for _, unit in ipairs(plates) do unitMatch(unit, true) end
	end
	local v = C_VignetteInfo
	if c and mapID and v then
		-- Only ask about the whole list when the markers or the search change.
		if not self.markers then
			self.markers = {}
			for _, marker in ipairs(Read(v.GetVignettes) or {}) do
				local info = Read(v.GetVignetteInfo, marker)
				if info and not (ns.Readable(info.isDead) and info.isDead) then
					local guid = info.objectGUID
					local kind, id = Identity(guid)
					local atlas = Text(info.atlasName)
					if not kind and atlas and atlas:find("VignetteLoot", 1, true) then kind, guid = "object", marker end
					local entry = kind == "object" and Match(kind, id, Text(info.name))
					if entry then self.markers[#self.markers+1] = { token = marker, guid = guid, entry = entry, name = Text(info.name) } end
				end
			end
		end
		for _, marker in ipairs(self.markers) do
			local pos = Read(v.GetVignettePosition, marker.token, mapID)
			if pos and Number(pos.x) and Number(pos.y) and (pos.x ~= 0 or pos.y ~= 0) then
				local vc, x, y = ns.MapToWorld(mapID, pos.x, pos.y)
				if vc == c then offer(marker.entry, marker.guid, nil, "object", (px-x)^2 + (py-y)^2, x, y, nil, nil, marker.name) end
			end
		end
	end
	table.sort(hits, Nearer)
	self.best = hits[1]
	self:CheckRowSkull()
	if not quiet then self:Paint() end
	return self.best
end


function Finder:OnLogin()
	ns.db.targetFinder = ns.db.targetFinder or {}
	local key = ns:GetCharacterKey()
	local saved = ns.db.targetFinder[key] or { manual = {}, quests = {} }
	ns.db.targetFinder[key], self.db = saved, saved
	self:BuildButton()
	self:Reindex()
	self:WatchQuests()
	self:WatchWorldClicks()
	ns:RegisterEvent("PLAYER_REGEN_ENABLED", function() self:SyncMarkButton(); self:Scan() end)
	ns:RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, unit)
		if unit == self.markedUnit then self:ClearLocalMark() end
	end)
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "VIGNETTES_UPDATED", "VIGNETTE_MINIMAP_UPDATED" }) do
		ns:RegisterEvent(event, function() self.markers = nil end)
	end
end

end)
