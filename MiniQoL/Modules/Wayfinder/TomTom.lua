-- Mini QoL packaging adapter; upstream source and credits follow.
MiniQoLRuntime:Execute("Wayfinder", function(...)
-- Speaking TomTom's language, so Wayfinder alone is enough: the /way commands
-- guides and Wowhead hand out, the coordinate formats people paste into chat,
-- and the TomTom table that Questie, HandyNotes and the guide addons call into.
local _, ns = ...

local TomTomCompat = ns:NewModule("TomTomCompat")

---------------------------------------------------------------------------
-- Zone names
---------------------------------------------------------------------------
-- "/way Stormwind City 42 65" needs a name to turn back into a uiMapID. The
-- index is built once, the first time a command actually names a zone.
local zoneIndex

local function MapRank(info)
	if not info then return -1 end
	local kinds = Enum.UIMapType
	if not kinds then return 0 end
	-- A real zone wins over the continent and over the dungeon floors that
	-- often share a capital's name.
	if info.mapType == kinds.Zone then return 4 end
	if info.mapType == kinds.Dungeon then return 3 end
	if info.mapType == kinds.Micro then return 2 end
	if info.mapType == kinds.Continent then return 1 end
	return 0
end

local function Record(index, info)
	if type(info) ~= "table" or type(info.name) ~= "string" or info.name == "" then return end
	local mapID = info.mapID or info.uiMapID
	if not mapID or not ns.GetMapRect(mapID) then return end
	local key = info.name:lower()
	local held = index[key]
	local rank, heldRank = MapRank(info), held and MapRank(C_Map.GetMapInfo(held)) or -1
	if not held or rank > heldRank or (rank == heldRank and mapID < held) then
		index[key] = mapID
	end
end

local function BuildZoneIndex()
	if zoneIndex then return zoneIndex end
	local index, counted = {}, 0
	for _, root in ipairs({ 946, 947 }) do -- Cosmic, then Azeroth
		local ok, children = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
		if ok and type(children) == "table" then
			for _, info in ipairs(children) do
				Record(index, info)
				counted = counted + 1
			end
		end
	end
	-- A client that will not walk its own map tree still has to answer by name.
	if counted < 50 then
		for mapID = 1, 3000 do
			local ok, info = pcall(C_Map.GetMapInfo, mapID)
			if ok then Record(index, info) end
		end
	end
	zoneIndex = index
	return index
end

-- Exact first, then a single unambiguous prefix, so "stormwind" finds the city.
local function ZoneToMapID(name)
	local index = BuildZoneIndex()
	local wanted = name:lower():gsub("^%s+", ""):gsub("%s+$", "")
	if index[wanted] then return index[wanted] end
	local found, matches = nil, {}
	for key, mapID in pairs(index) do
		if key:sub(1, #wanted) == wanted then
			matches[#matches + 1] = key
			if not found or mapID < found then found = mapID end
		end
	end
	if #matches == 1 then return found end
	if #matches > 1 then
		table.sort(matches)
		return nil, matches
	end
	return nil
end

ns.ZoneToMapID = ZoneToMapID

---------------------------------------------------------------------------
-- Reading a command
---------------------------------------------------------------------------
local function Trim(text)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Returns mapID, x, y, label with x and y normalized; or nil, reason, detail,
-- options when the text does not name a place.
function ns.ParseWaypoint(text)
	text = Trim(text or "")
	if text == "" then return nil, "empty" end
	if text:find("^%[Wayfinder:") then return nil, "token" end
	-- The game's own map-pin link, which is what shift-clicking a pin hands out.
	local linkMap, linkX, linkY = text:match("worldmap:(%d+):(%d+):(%d+)")
	if linkMap then
		local label = Trim(text:match("|h%[(.-)%]|h") or "")
		return tonumber(linkMap), tonumber(linkX) / 10000, tonumber(linkY) / 10000,
			label ~= "" and label or nil
	end
	local mapID, rest = text:match("^#(%d+)%s+(.+)$")
	if not mapID then rest = text end
	-- Brackets and parentheses are how coordinates get pasted out of guides.
	local prefix, x, y, label =
		rest:match("^(.-)[%[%(]?%s*(%-?%d+%.?%d*)%s*[,%s]%s*(%-?%d+%.?%d*)%s*[%]%)]?%s*(.*)$")
	if not x then return nil, "coordinates" end
	x, y = tonumber(x), tonumber(y)
	if not x or not y or x < 0 or x > 100 or y < 0 or y > 100 then return nil, "coordinates" end
	prefix = Trim(prefix or "")
	if mapID then
		if prefix ~= "" then return nil, "coordinates" end
		mapID = tonumber(mapID)
	elseif prefix ~= "" then
		local resolved, ambiguous = ZoneToMapID(prefix)
		if not resolved then return nil, ambiguous and "ambiguous" or "zone", prefix, ambiguous end
		mapID = resolved
	else
		mapID = C_Map.GetBestMapForUnit("player")
		if not mapID then return nil, "nowhere" end
	end
	if not ns.GetMapRect(mapID) then return nil, "map", mapID end
	label = Trim(label or "")
	return mapID, x / 100, y / 100, label ~= "" and label or nil
end

---------------------------------------------------------------------------
-- The commands
---------------------------------------------------------------------------
local function Usage()
	ns.Print("Waypoints:")
	print("   /way 42.1 65.3 [name]          - in the zone you are in")
	print("   /way Stormwind City 42 65 Bank - in a zone by name")
	print("   /way #1429 42 65 [name]        - in a zone by map id")
	print("   /way reset all|<zone>          - remove waypoints")
	print("   /way list                      - what is set")
	print("   /wayb [name]                   - right where you stand")
	print("   Right-click the arrow for the list, middle-click it to remove one.")
end

local function ListWaypoints()
	local waypoints = ns.Navigation:GetWaypoints()
	if #waypoints == 0 then
		ns.Print("No waypoints set.")
		return
	end
	local active = ns.Navigation:GetWaypoint()
	ns.Print(("%d waypoint%s:"):format(#waypoints, #waypoints == 1 and "" or "s"))
	for index, rec in ipairs(waypoints) do
		print(("   %d. %s%s  |cff808080%s|r"):format(index, rec.n or "Waypoint",
			rec == active and "  |cff4fc3f7(arrow)|r" or "", rec.where or ""))
	end
end

local function Reset(argument)
	argument = Trim(argument or ""):lower()
	if argument == "" or argument == "all" then
		if ns.Navigation:ClearAllWaypoints() then
			ns.Print("Removed every waypoint.")
		else
			ns.Print("No waypoints to remove.")
		end
		return
	end
	local mapID = tonumber(argument:match("^#(%d+)$")) or ZoneToMapID(argument)
	if not mapID then
		ns.Print("No zone called '" .. argument .. "'. Try /way reset all.")
		return
	end
	local removed, waypoints = 0, ns.Navigation:GetWaypoints()
	for index = #waypoints, 1, -1 do
		if waypoints[index].m == mapID then
			ns.Navigation:RemoveWaypoint(waypoints[index])
			removed = removed + 1
		end
	end
	local info = C_Map.GetMapInfo(mapID)
	ns.Print(("Removed %d waypoint%s in %s."):format(removed, removed == 1 and "" or "s",
		info and info.name or ("map " .. mapID)))
end

function ns.HandleWaypointCommand(input)
	input = Trim(input or "")
	if input == "" then
		Usage()
		ListWaypoints()
		return
	end
	local command = (input:match("^(%S+)") or ""):lower()
	if command == "reset" or command == "clear" then
		Reset(input:match("^%S+%s*(.*)$"))
		return
	elseif command == "list" then
		ListWaypoints()
		return
	elseif command == "help" then
		Usage()
		return
	end
	if input:find("^%[Wayfinder:") then
		if not ns.Navigation:ImportWaypointShare(input) then
			ns.Print("That shared waypoint could not be read.")
		end
		return
	end
	local mapID, x, y, label = ns.ParseWaypoint(input)
	if mapID then
		local rec = ns.Navigation:SetWaypointOnMap(mapID, x, y, label)
		if rec then
			ns.Print("Waypoint set: " .. (rec.n or "")
				.. (rec.where and rec.where ~= rec.n and "  |cff808080" .. rec.where .. "|r" or ""))
		end
		return
	end
	local reason, detail, options = x, y, label
	if reason == "zone" then
		ns.Print("No zone called '" .. tostring(detail) .. "'. Use /way #<map id> if you know it.")
	elseif reason == "ambiguous" then
		ns.Print("'" .. tostring(detail) .. "' matches several zones: "
			.. table.concat(options, ", ", 1, math.min(#options, 6)))
	elseif reason == "map" then
		ns.Print("Waypoints can't be placed on that map.")
	elseif reason == "nowhere" then
		ns.Print("The game will not say which map you are on right now.")
	else
		Usage()
	end
end

-- Right where you stand, which is what TomTom's /wayb is for.
local function WayBack(label)
	local cont, wx, wy, mapID = ns.GetPlayerWorld()
	if not cont then
		ns.Print("Your position is not available here.")
		return
	end
	label = Trim(label or "")
	local rec = ns.Navigation:AddWaypoint(cont, wx, wy, label ~= "" and label or "Back here", mapID)
	if rec then ns.Print("Waypoint set where you stand: " .. (rec.n or "")) end
end

ns.WaypointHere = WayBack

---------------------------------------------------------------------------
-- The TomTom table other addons call
---------------------------------------------------------------------------
local REC = {} -- private key: the Wayfinder record behind a TomTom uid

local function RecordOf(uid)
	return type(uid) == "table" and uid[REC] or nil
end

local function Normalize(x, y)
	x, y = tonumber(x), tonumber(y)
	if not x or not y then return nil end
	-- TomTom takes 0..1; enough callers pass percentages that both must work.
	if x > 1 or y > 1 then x, y = x / 100, y / 100 end
	if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
	return x, y
end

local shim = {}
shim.version = "Mini QoL Wayfinder"
shim.waypoints = {}
shim.profile = {
	arrow = { enable = true, goodcolor = { 0.45, 0.92, 0.45 }, badcolor = { 1, 0.2, 0.2 }, arrival = 10 },
	general = { confirmremoveall = false },
	persistence = { cleardistance = 10, savewaypoints = true },
	minimap = { enable = true },
	worldmap = { enable = true },
}
shim.db = { profile = shim.profile }

function shim:AddWaypoint(mapID, x, y, options)
	options = type(options) == "table" and options or {}
	mapID = tonumber(mapID)
	x, y = Normalize(x, y)
	if not (mapID and x) then return nil end
	local title = options.title or options.desc
	if type(title) ~= "string" or title == "" then title = nil end
	local rec = ns.Navigation:SetWaypointOnMap(mapID, x, y, title, {
		-- TomTom only moves its arrow for a "crazy" waypoint; here the newest
		-- takes the arrow unless the caller says otherwise.
		focus = options.crazy ~= false,
		quiet = options.silent,
		source = options.from or "TomTom",
	})
	if type(rec) ~= "table" then return nil end
	local uid = { mapID, x, y, desc = title, title = title, from = options.from }
	uid[REC] = rec
	self.waypoints[mapID] = self.waypoints[mapID] or {}
	self.waypoints[mapID][rec.uid] = uid
	return uid
end

-- The map/floor spelling older callers still use; the floor is ignored.
function shim:AddMFWaypoint(mapID, _, x, y, options)
	return self:AddWaypoint(mapID, x, y, options)
end

-- Continent and zone indices stopped meaning anything long ago.
function shim:AddZWaypoint()
	return nil
end

function shim:RemoveWaypoint(uid)
	local rec = RecordOf(uid)
	if not rec then return false end
	local held = self.waypoints[uid[1]]
	if held then held[rec.uid] = nil end
	return ns.Navigation:RemoveWaypoint(rec)
end

function shim:ClearAllWaypoints()
	for mapID in pairs(self.waypoints) do self.waypoints[mapID] = nil end
	return ns.Navigation:ClearAllWaypoints()
end
shim.ClearWaypoints = shim.ClearAllWaypoints
shim.RemoveAllWaypoints = shim.ClearAllWaypoints
shim.ResetWaypoints = shim.ClearAllWaypoints

function shim:IsValidWaypoint(uid)
	local rec = RecordOf(uid)
	if not rec then return false end
	for _, held in ipairs(ns.Navigation:GetWaypoints()) do
		if held == rec then return true end
	end
	return false
end

function shim:SetCrazyArrow(uid, _, title)
	local rec = RecordOf(uid)
	if not rec then return false end
	if type(title) == "string" and title ~= "" then rec.n = title end
	ns.Navigation:SetActiveWaypoint(rec)
	return ns.Navigation:GetWaypoint() == rec
end

function shim:GetClosestWaypoint()
	local rec = ns.Navigation:ClosestWaypoint()
	if not rec then return nil end
	local held = self.waypoints[rec.m]
	return held and held[rec.uid] or nil
end

function shim:SetClosestWaypoint()
	return ns.Navigation:SetActiveWaypoint(ns.Navigation:ClosestWaypoint())
end

function shim:WaypointExists(mapID, x, y, desc)
	mapID = tonumber(mapID)
	x, y = Normalize(x, y)
	if not (mapID and x) then return false end
	local cont, wx, wy = ns.MapToWorld(mapID, x, y)
	if not cont then return false end
	return ns.Navigation:FindWaypoint(cont, wx, wy, desc) ~= nil
end

function shim:WaypointMFExists(mapID, _, x, y, desc)
	return self:WaypointExists(mapID, x, y, desc)
end

function shim:GetDistanceToWaypoint(uid)
	local rec = RecordOf(uid)
	local cont, wx, wy = ns.GetPlayerWorld()
	if not rec or not cont or rec.c ~= cont then return nil end
	return ns.Distance(rec.x, rec.y, wx, wy)
end

function shim:GetDirectionToWaypoint(uid)
	local rec = RecordOf(uid)
	local cont, wx, wy = ns.GetPlayerWorld()
	if not rec or not cont or rec.c ~= cont then return nil end
	return math.atan2(rec.y - wy, rec.x - wx)
end

-- Nothing is stored the way TomTom stored it, so these have nothing left to do.
function shim:ReloadWaypoints() end
function shim:EnableDisablePOIIntegration() end
function shim:ShowHideCrazyArrow() end

ns.TomTomShim = shim

---------------------------------------------------------------------------
-- Installing
---------------------------------------------------------------------------
function ns.CommandIsTaken(command)
	local wanted = command:lower()
	for key, handler in pairs(SlashCmdList) do
		if type(handler) == "function" then
			local index = 1
			while _G["SLASH_" .. key .. index] do
				if _G["SLASH_" .. key .. index]:lower() == wanted then return true end
				index = index + 1
			end
		end
	end
	return false
end

local function RealTomTomPresent()
	if TomTom ~= nil and TomTom ~= shim then return true end
	local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	local ok, isLoaded = pcall(loaded, "TomTom")
	return ok and isLoaded == true
end

-- Take only the commands nothing else answers, and keep the ones we do take.
local function Claim(key, handler, ...)
	local wanted = {}
	for index = 1, select("#", ...) do
		local command = select(index, ...)
		if not ns.CommandIsTaken(command) then wanted[#wanted + 1] = command end
	end
	if #wanted == 0 then return false end
	for index, command in ipairs(wanted) do
		_G["SLASH_" .. key .. index] = command
	end
	SlashCmdList[key] = handler
	return true
end

function TomTomCompat:OnInitialize()
	if RealTomTomPresent() then
		self.superseded = true
		return
	end
	TomTom = shim
	Claim("WAYFINDERWAY", function(input) ns.HandleWaypointCommand(input) end,
		"/way", "/cway", "/tway", "/tomtomway")
	Claim("WAYFINDERWAYBACK", function(input) WayBack(input) end, "/wayb", "/tomtomwayb")
end

function TomTomCompat:OnLogin()
	-- The real TomTom loading after us keeps its own table and its own commands.
	if TomTom ~= shim and not self.superseded then
		self.superseded = true
		if SlashCmdList.WAYFINDERWAY then
			SlashCmdList.WAYFINDERWAY = function(input)
				local handler = SlashCmdList.TOMTOM_WAY
				if type(handler) == "function" then return handler(input) end
				ns.HandleWaypointCommand(input)
			end
		end
	end
end

end)
