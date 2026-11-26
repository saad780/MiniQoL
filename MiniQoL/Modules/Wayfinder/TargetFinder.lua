-- Mini QoL packaging adapter; upstream source and credits follow.
MiniQoLRuntime:Execute("Wayfinder", function(...)
-- A character's watch list. Only live unit tokens and client-reported object
-- markers can light the button. Quest databases supply names, never sightings.
local _, ns = ...
local Finder = ns:NewModule("TargetFinder")
local RANGE = 60 -- yards for sightings with a measurable position
local byName, byID = {}, {}
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
	self.markers = nil
	local function index(entry)
		if entry.id then byID[entry.kind .. entry.id] = entry end
		local name = entry.name:lower()
		local names = byName[name] or {}
		if not names[entry.kind] or not entry.id then names[entry.kind] = entry end
		byName[name] = names
	end
	for _, entry in ipairs(self.db.manual) do index(entry) end
	for _, group in pairs(self.db.quests) do
		for _, entry in ipairs(group.targets) do index(entry) end
	end
	self:UpdateList()
	self.button:SetShown(next(byName) ~= nil)
	self:Scan()
end

function Finder:Add(name)
	name = Text(name)
	if not name or #name > 120 then return false end
	for _, entry in ipairs(self.db.manual) do
		if entry.name:lower() == name:lower() then return true end
	end
	table.insert(self.db.manual, { name = name, kind = "any" })
	self:Reindex()
	return true
end

local function Identity(guid)
	if not ns.Readable(guid) or type(guid) ~= "string" then return end
	local kind, id = guid:match("^(%a+)%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)")
	if kind == "GameObject" then return "object", tonumber(id) end
	if kind == "Creature" or kind == "Vehicle" then return "mob", tonumber(id) end
end

local function Match(kind, id, name)
	local entry = id and byID[kind .. id]
	if entry then return entry end
	local names = name and byName[name:lower()]
	-- An imported ID distinguishes entities with identical display names.
	if names then
		local typed = names[kind]
		return (typed and (not typed.id or not id) and typed) or names.any
	end
end

local function Number(x)
	return ns.Readable(x) and type(x) == "number" and x == x and math.abs(x) < math.huge
end

local function Position(unit)
	local x, y, z, c = Read(UnitPosition, unit)
	if Number(x) and Number(y) and Number(c) then return c, x, y, Number(z) and z or nil end
end

-- Unit tokens are recycled. Resolve them again on the click and never mark
-- the current target merely because the intended target has disappeared.
function Finder:Scan()
	self.best = nil
	if not next(byName) then self:Paint(); return end
	local c, px, py, pz = Position("player")
	local mapID = Read(C_Map and C_Map.GetBestMapForUnit, "player")
	if not c then c, px, py, mapID = ns.GetPlayerWorld() end
	local best
	local function offer(entry, guid, unit, kind, distance, x, y, approximate, bound)
		if distance and distance > RANGE * RANGE then return end
		-- A visible nameplate can be readable even where the client withholds
		-- distances. Prefer measured matches, then a stable visible fallback.
		local rank = distance or bound or math.huge
		if best and best.guid == guid then
			unit = unit or best.unit
			if best.x and (not x or (approximate and not best.approximate)) then x, y, approximate = best.x, best.y, best.approximate end
			distance = distance or best.distance
			rank = math.min(rank, best.rank)
		elseif best and (rank > best.rank or (rank == best.rank and guid >= best.guid)) then
			return
		end
		best = { entry = entry, name = entry.name, guid = guid, unit = unit, kind = kind,
			rank = rank, distance = distance, c = c, x = x, y = y, m = mapID, approximate = approximate }
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
			entry = line and Match(kind, id, Text(line.leftText))
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
		if not distance and not bound and not plate and unit ~= "softinteract" then return end
		if kind == "object" and not x then
			if unit ~= "softinteract" or not c then return end
			offer(entry, guid, unit, kind, distance, px, py, true, bound)
		else
			offer(entry, guid, unit, kind, distance, x, y, nil, bound)
		end
	end
	for _, unit in ipairs(fixedUnits) do unitMatch(unit) end
	local visible = Read(C_NamePlate and C_NamePlate.GetNamePlates)
	if type(visible) == "table" then
		for _, plate in ipairs(visible) do
			if not (plate.IsForbidden and plate:IsForbidden()) then
				local unit = plate.namePlateUnitToken
				if not ns.Readable(unit) then unit = plate.unitToken end
				if not ns.Readable(unit) and plate.UnitFrame then unit = plate.UnitFrame.unit end
				if ns.Readable(unit) and type(unit) == "string" then unitMatch(unit, true) end
			end
		end
	else
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
					if entry then self.markers[#self.markers+1] = { token = marker, guid = guid, entry = entry } end
				end
			end
		end
		for _, marker in ipairs(self.markers) do
			local pos = Read(v.GetVignettePosition, marker.token, mapID)
			if pos and Number(pos.x) and Number(pos.y) and (pos.x ~= 0 or pos.y ~= 0) then
				local vc, x, y = ns.MapToWorld(mapID, pos.x, pos.y)
				if vc == c then offer(marker.entry, marker.guid, nil, "object", (px-x)^2 + (py-y)^2, x, y) end
			end
		end
	end
	self.best = best
	self:Paint()
	return best
end

function Finder:Mark()
	self.markers = nil
	local hit = self:Scan()
	if not hit then return end
	if hit.kind == "mob" then
		if Read(UnitGUID, hit.unit) ~= hit.guid then return end
		local mark = Read(GetRaidTargetIndex, hit.unit)
		if Number(mark) and mark > 0 then return end
		if not (IsInRaid and IsInRaid()) or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
			local ok = SetRaidTarget and pcall(SetRaidTarget, hit.unit, 8)
			if ok then return end
		end
		if not hit.x then ns.Print("The game could not place a raid mark on " .. hit.name .. "."); return end
	end
	if hit.x then
		local name = hit.approximate and (hit.name .. " (nearby)") or hit.name
		ns.Navigation:SetWaypoint(hit.c, hit.x, hit.y, name, hit.m)
	end
end

function Finder:OnLogin()
	ns.db.targetFinder = ns.db.targetFinder or {}
	local key = ns:GetCharacterKey()
	local saved = ns.db.targetFinder[key] or { manual = {}, quests = {} }
	ns.db.targetFinder[key], self.db = saved, saved
	self:BuildButton()
	self:Reindex()
	self:WatchQuests()
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "VIGNETTES_UPDATED", "VIGNETTE_MINIMAP_UPDATED" }) do
		ns:RegisterEvent(event, function() self.markers = nil end)
	end
end

end)
