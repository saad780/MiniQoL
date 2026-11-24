-- Getting around: a "track my location" button on the map, middle-click waypoints,
-- a waypoint on your corpse, and a floating arrow that points the way to the waypoint.
local _, ns = ...

local Navigation = ns:NewModule("Navigation")

local MEDIA = "Interface\\AddOns\\Wayfinder\\Media\\"
local NEAR_YARDS = 40      -- arrow turns green inside this distance
local ARRIVE_YARDS = 10    -- close enough to count as arrived
local LABEL_WIDTH = 200    -- the waypoint's name under the arrow wraps at this width
local CYAN = { 0.35, 0.84, 1 }
local GREEN = { 0.45, 0.92, 0.45 }

local sqrt, atan2, min, max = math.sqrt, math.atan2, math.min, math.max

local current -- the waypoint the arrow follows: one of the records in list
local list = {} -- every waypoint set: { waypoint, c, x, y, m, n, where, cats, uid }
local beforeCorpse -- the waypoint the arrow was on when your corpse took it

local function Sound(name)
	if SOUNDKIT and SOUNDKIT[name] then
		PlaySound(SOUNDKIT[name])
	end
end

---------------------------------------------------------------------------
-- Describing a place
---------------------------------------------------------------------------
-- "Elwynn Forest 42.1, 65.3" for a world point. Uses the zone the game assigns to
-- the spot, or the hint map when the game only names the continent.
function ns.DescribeLocation(cont, wx, wy, hintMapID)
	local ok, mapID = pcall(C_Map.GetMapPosFromWorldPos, cont, CreateVector2D(wx, wy))
	local info = ok and mapID and C_Map.GetMapInfo(mapID)
	if not (info and info.mapType >= Enum.UIMapType.Zone) then
		mapID = hintMapID
		info = mapID and C_Map.GetMapInfo(mapID)
	end
	local rect = mapID and ns.GetMapRect(mapID)
	if info and rect and rect.cont == cont then
		local x, y = ns.WorldToMapRect(rect, wx, wy)
		return ("%s %.1f, %.1f"):format(info.name, x * 100, y * 100), mapID
	end
	return UNKNOWN or "Unknown", hintMapID
end

---------------------------------------------------------------------------
-- The waypoints
---------------------------------------------------------------------------
-- Several waypoints stand at once, the way TomTom and every guide that speaks
-- its language expect. The arrow follows one of them; the rest wait on the map
-- until you pick one from the arrow's list.
local MAX_WAYPOINTS = 50
local SAME_SPOT_YARDS = 8
local CORPSE = "corpse" -- the source of the waypoint set on your corpse
local nextUID = 0

local function NewUID()
	nextUID = nextUID + 1
	return "wf" .. nextUID
end

local function IndexOf(rec)
	for index = 1, #list do
		if list[index] == rec then
			return index
		end
	end
end

local function Save()
	-- Mutating list in place is what persists; this only records which one the
	-- arrow is on. Guarded so the module still loads without a character.
	if not (ns.db and ns.db.waypoints and ns.GetCharacterKey) then
		return
	end
	ns.db.waypoints[ns:GetCharacterKey()] = { list = list, active = current and IndexOf(current) or nil }
end

function Navigation:GetWaypoint()
	return current
end

function Navigation:GetWaypoints()
	return list
end

-- The one nearest the player, which is the one worth pointing at.
function Navigation:ClosestWaypoint()
	local cont, wx, wy = ns.GetPlayerWorld()
	local best, shortest
	for _, rec in ipairs(list) do
		if cont and rec.c == cont then
			local distance = ns.Distance(rec.x, rec.y, wx, wy)
			if not shortest or distance < shortest then
				best, shortest = rec, distance
			end
		end
	end
	return best or list[#list]
end

-- Repeatedly feeding in the same spot (a quest tracker refreshing, a guide
-- pasted twice) must not pile up identical pins.
function Navigation:FindWaypoint(cont, wx, wy, label)
	for _, rec in ipairs(list) do
		if rec.c == cont and ns.Distance(rec.x, rec.y, wx, wy) <= SAME_SPOT_YARDS
			and (label == nil or rec.n == label) then
			return rec
		end
	end
end

function Navigation:SetActiveWaypoint(rec)
	if rec == current or (rec and not IndexOf(rec)) then
		return false
	end
	current = rec
	Save()
	ns:Fire("WAYPOINT_CHANGED", current)
	self:RefreshArrow()
	return true
end

-- `kept`: never cleared on arrival, since whoever set it says when it is done
-- (a guide's goal). `goal` and `note` are extra lines for the arrow's tooltip.
local function NewRecord(cont, wx, wy, label, mapID, options)
	local where, zone = ns.DescribeLocation(cont, wx, wy, mapID)
	return { waypoint = true, c = cont, x = wx, y = wy, m = zone, n = label or where,
		where = where, cats = {}, uid = NewUID(), source = options.source,
		kept = options.kept and true or nil, goal = options.goal, note = options.note }
end

-- Keep the oldest from piling up forever when an addon feeds them in.
local function Append(rec)
	list[#list + 1] = rec
	while #list > MAX_WAYPOINTS do
		table.remove(list, list[1] == current and 2 or 1)
	end
end

-- Every waypoint arrives here. Adding rather than replacing is what lets a
-- guide's five coordinates, or a quest's several objectives, all stand at once.
function Navigation:AddWaypoint(cont, wx, wy, label, mapID, options)
	options = options or {}
	local existing = self:FindWaypoint(cont, wx, wy, label)
	if existing then
		if options.focus ~= false then
			self:SetActiveWaypoint(existing)
		end
		return existing
	end
	local rec = NewRecord(cont, wx, wy, label, mapID, options)
	Append(rec)
	if options.focus ~= false or not current then
		current = rec
	end
	Save()
	if not options.quiet then
		Sound("UI_MAP_WAYPOINT_CLICK_TO_PLACE")
	end
	ns:Fire("WAYPOINT_CHANGED", current)
	self:RefreshArrow()
	return rec
end

-- Kept for everything written when there was only ever one.
function Navigation:SetWaypoint(cont, wx, wy, label, mapID, options)
	return self:AddWaypoint(cont, wx, wy, label, mapID, options)
end

-- A waypoint at a normalized position on a uiMap.
function Navigation:SetWaypointOnMap(mapID, x, y, label, options)
	local cont, wx, wy = ns.MapToWorld(mapID, x, y)
	if not cont then
		ns.Print("Waypoints can't be placed on this map.")
		return false
	end
	return self:AddWaypoint(cont, wx, wy, label, mapID, options)
end

-- A waypoint at a recorded location (vendor, mailbox...).
function Navigation:SetWaypointTo(rec, catID)
	local cat = catID and ns.CategoryByID[catID]
	return self:AddWaypoint(rec.c, rec.x, rec.y, rec.n or (cat and cat.label), rec.m)
end

-- The one waypoint a source keeps for itself, such as a guide's goal.
function Navigation:GetSourceWaypoint(source)
	for _, rec in ipairs(list) do
		if rec.source == source then
			return rec
		end
	end
end

-- Puts a source's one waypoint somewhere new: a guide moving on has a single
-- waypoint that moves along, not a trail of old goals. The moved waypoint is a
-- new record in the old one's place, so nothing worked out about where the old
-- one lay (the map its pin belongs on) carries over. `focus` takes the arrow;
-- without it the arrow stays where it is, unless it has nowhere else to be.
-- Not deduplicated against other waypoints: the record is always the source's own.
function Navigation:PlaceSourceWaypoint(source, cont, wx, wy, label, mapID, options)
	options = options or {}
	local old = self:GetSourceWaypoint(source)
	local rec = NewRecord(cont, wx, wy, label, mapID, options)
	rec.source = source
	if old and old.c == rec.c and ns.Distance(old.x, old.y, rec.x, rec.y) < 1 and old.n == rec.n
		and old.goal == rec.goal and old.note == rec.note and old.kept == rec.kept then
		if options.focus then
			self:SetActiveWaypoint(old)
		end
		return old
	end
	if old then
		list[IndexOf(old)] = rec
		if current == old then
			current = rec
		end
		if beforeCorpse == old then
			beforeCorpse = rec
		end
	else
		Append(rec)
	end
	if options.focus or not current then
		current = rec
	end
	Save()
	ns:Fire("WAYPOINT_CHANGED", current)
	self:RefreshArrow()
	return rec
end

-- `quiet`: taken away by the addon that set it, not by the player, so no sound.
-- WAYPOINT_REMOVED tells whoever set it that it is gone.
function Navigation:RemoveWaypoint(rec, quiet)
	local index = rec and IndexOf(rec)
	if not index then
		return false
	end
	table.remove(list, index)
	if current == rec then
		current = self:ClosestWaypoint()
	end
	Save()
	if not quiet then
		Sound("UI_MAP_WAYPOINT_REMOVE")
	end
	ns:Fire("WAYPOINT_CHANGED", current)
	ns:Fire("WAYPOINT_REMOVED", rec)
	self:RefreshArrow()
	return true
end

-- The one the arrow is on, which is what removing "the waypoint" has always meant.
function Navigation:ClearWaypoint()
	return self:RemoveWaypoint(current)
end

function Navigation:ClearAllWaypoints()
	if #list == 0 then
		return false
	end
	local removed = {}
	for index = #list, 1, -1 do
		removed[#removed + 1] = list[index]
		list[index] = nil
	end
	current = nil
	Save()
	Sound("UI_MAP_WAYPOINT_REMOVE")
	ns:Fire("WAYPOINT_CHANGED", nil)
	for _, rec in ipairs(removed) do
		ns:Fire("WAYPOINT_REMOVED", rec)
	end
	self:RefreshArrow()
	return true
end

-- What a middle-click on a map icon does: a waypoint is removed, anything
-- else becomes one.
function Navigation:ToggleWaypointAt(rec, catID)
	if rec.waypoint then
		self:RemoveWaypoint(rec)
	else
		self:SetWaypointTo(rec, catID)
	end
end

-- Read back what the character left behind, in either shape.
function Navigation:LoadWaypoints()
	local saved = ns.db.waypoints[ns:GetCharacterKey()]
	if type(saved) == "table" then
		if type(saved.list) == "table" then
			list = saved.list
			current = list[tonumber(saved.active) or 0]
		elseif saved.c then
			-- Before this, each character kept exactly one waypoint.
			list, current = { saved }, saved
		end
	end
	for _, rec in ipairs(list) do
		rec.waypoint, rec.cats, rec.uid = true, rec.cats or {}, rec.uid or NewUID()
	end
	current = current or list[#list]
	Save()
end

---------------------------------------------------------------------------
-- Your corpse
---------------------------------------------------------------------------
-- Releasing your spirit sets a waypoint on your corpse and puts the arrow on
-- it. Coming back to life completes it, however that happens: at the corpse,
-- at a spirit healer or from someone's resurrection. Walking up to it does
-- not, since the body is still needed until you are alive again.
local CORPSE_LABEL = "Your corpse"
local CORPSE_TRIES = 10 -- once a second while the game has yet to place the body
local corpseCheck = 0   -- each new check retires the retries of the one before

-- The corpse on the player's map, or on a map above it when the spirit was
-- sent to a graveyard in the next zone over.
local function CorpseOnMap()
	if not (C_DeathInfo and C_DeathInfo.GetCorpseMapPosition) then return end
	local mapID = C_Map.GetBestMapForUnit("player")
	for _ = 1, 12 do
		if not mapID or mapID == 0 then return end
		local ok, position = pcall(C_DeathInfo.GetCorpseMapPosition, mapID)
		if ok and type(position) == "table" and position.GetXY then
			local x, y = position:GetXY()
			if ns.Readable(x) and ns.Readable(y) and type(x) == "number" and type(y) == "number"
				and (x ~= 0 or y ~= 0) then
				return mapID, x, y
			end
		end
		local info = C_Map.GetMapInfo(mapID)
		mapID = info and info.parentMapID
	end
end

function Navigation:GetCorpseWaypoint()
	for _, rec in ipairs(list) do
		if rec.source == CORPSE then
			return rec
		end
	end
end

-- Sets the corpse waypoint; false while the game can't yet say where it is.
function Navigation:MarkCorpse()
	local mapID, x, y = CorpseOnMap()
	local cont, wx, wy
	if mapID then
		cont, wx, wy = ns.MapToWorld(mapID, x, y)
	end
	if not cont then
		return false
	end
	local old = self:GetCorpseWaypoint()
	if old and old.c == cont and ns.Distance(old.x, old.y, wx, wy) <= SAME_SPOT_YARDS then
		-- Already marked: a reload or a loading screen as a ghost. The arrow
		-- stays wherever the player has since put it.
		return true
	end
	if old then
		-- Left over from a death that ended while Wayfinder wasn't watching.
		table.remove(list, IndexOf(old))
		if current == old then
			current = nil
		end
	end
	if current then
		beforeCorpse = current
	end
	self:AddWaypoint(cont, wx, wy, CORPSE_LABEL, mapID, { source = CORPSE })
	return true
end

-- Alive again: the corpse waypoint is done, and the arrow goes back to what it
-- was following before.
function Navigation:ClearCorpse()
	local rec = self:GetCorpseWaypoint()
	local before = beforeCorpse
	beforeCorpse = nil
	if not rec then
		return false
	end
	if current == rec and before and IndexOf(before) then
		current = before
	end
	return self:RemoveWaypoint(rec)
end

-- Run on every change between alive, dead and ghost. The game can take a
-- moment after the release, or a loading screen, to place the body, so a ghost
-- with no corpse found yet is checked again for a few seconds.
function Navigation:CheckCorpse(attempt)
	if not attempt then
		corpseCheck = corpseCheck + 1
		attempt = 1
	end
	if not (UnitIsDeadOrGhost and UnitIsGhost) then
		return
	end
	if not UnitIsDeadOrGhost("player") then
		self:ClearCorpse()
		return
	end
	if not ns:GetSetting("corpseWaypoint") then
		return
	end
	local ghost = UnitIsGhost("player")
	if ghost and self:MarkCorpse() then
		return
	end
	if attempt < CORPSE_TRIES and C_Timer then
		local check = corpseCheck
		C_Timer.After(1, function()
			if check == corpseCheck then
				self:CheckCorpse(attempt + 1)
			end
		end)
	elseif ghost then
		ns.Print("Your corpse isn't on a map Wayfinder can read, so the arrow can't point to it.")
	end
end

---------------------------------------------------------------------------
-- Copyable waypoint text, made clickable locally by the receiving addon
---------------------------------------------------------------------------
local function LinkLabel(label)
	-- Labels are display text, never hyperlink markup. Keep room for the payload
	-- in a chat message, without cutting a UTF-8 character in half.
	label = (label or "Waypoint"):gsub("|", ""):gsub("[%c%[%]]", " ")
	local parts, length = {}, 0
	for char in label:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		if length + #char > 80 then break end
		parts[#parts + 1], length = char, length + #char
	end
	return table.concat(parts)
end

function Navigation:GetWaypointLink(rec)
	rec = rec or current
	if not rec then return nil end
	local mapID = rec.m
	-- Detail-view points can lie outside the map it opened from. Use a parent
	-- map that contains the point so the link has valid normalized coordinates.
	for _ = 1, 12 do
		local rect = ns.GetMapRect(mapID)
		if rect and rect.cont == rec.c then
			local x, y = ns.WorldToMapRect(rect, rec.x, rec.y)
			if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
				-- The visible text carries the coordinates too: clipboard copies and
				-- chat transports must not need to preserve hidden hyperlink markup.
				return ("[Wayfinder:%d:%d:%d:%s]"):format(
					mapID, math.floor(x * 10000 + 0.5), math.floor(y * 10000 + 0.5), LinkLabel(rec.n))
			end
		end
		local info = mapID and C_Map.GetMapInfo(mapID)
		mapID = info and info.parentMapID
		if not mapID or mapID == 0 then break end
	end
	return nil
end

local function ValidPosition(mapID, x, y)
	mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
	if not mapID or not x or not y or mapID < 1 or mapID > 2147483647
		or x < 0 or x > 10000 or y < 0 or y > 10000 then return nil end
	if not C_Map.GetMapInfo(mapID) or not ns.GetMapRect(mapID) then return nil end
	return mapID, x, y
end

local function ParseShare(text)
	if type(text) ~= "string" or #text > 128 then return nil end
	local mapID, x, y, label = text:match("^%[Wayfinder:(%d+):(%d+):(%d+):([^|%c%[%]]*)%]$")
	mapID, x, y = ValidPosition(mapID, x, y)
	if not mapID or #label > 80 then return nil end
	return mapID, x, y, label
end

-- A message filter changes only the local rendering. The wire/clipboard format
-- remains ordinary text, and receiving a message never creates a waypoint.
function Navigation:FormatWaypointMessage(message)
	if not ns.Readable(message) or type(message) ~= "string" then return message end
	local function Decorate(plain)
		return (plain:gsub("%[Wayfinder:[^%]]*%]", function(token)
			local mapID, x, y, label = ParseShare(token)
			if not mapID then return token end
			return ("|cffffff00|Hwayfinder:%d:%d:%d:%s|h%s|h|r"):format(mapID, x, y, label, token)
		end))
	end
	-- Don't nest links if another filter (or another chat window) already
	-- formatted the token, or if it appears in an unrelated hyperlink.
	local parts, cursor = {}, 1
	while true do
		local first, last = message:find("|H[^|]*|h.-|h", cursor)
		if not first then
			parts[#parts + 1] = Decorate(message:sub(cursor))
			break
		end
		parts[#parts + 1] = Decorate(message:sub(cursor, first - 1))
		parts[#parts + 1] = message:sub(first, last)
		cursor = last + 1
	end
	return table.concat(parts)
end

function Navigation:ImportWaypointShare(text)
	local mapID, x, y, label = ParseShare(text)
	if not mapID then return false end
	return self:SetWaypointOnMap(mapID, x / 10000, y / 10000, label ~= "" and label or nil)
end

-- Putting text in the chat box is awkward to do reliably: the helpers moved
-- from globals into ChatFrameUtil, their return values are not a dependable
-- report of success, and recent clients refuse chat messaging outright while
-- locked down. So try every route and then check the edit box itself.
local function ActiveChatText()
	local getter = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow) or ChatEdit_GetActiveWindow
	if type(getter) ~= "function" then return nil end
	local ok, box = pcall(getter)
	if not ok or type(box) ~= "table" or not box.IsShown or not box:IsShown() then return nil end
	local fine, text = pcall(box.GetText, box)
	return fine and type(text) == "string" and text or nil
end

local function InsertIntoChat(text)
	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
		return false
	end
	local function landed()
		local content = ActiveChatText()
		return content ~= nil and content:find(text, 1, true) ~= nil
	end
	-- Into the draft the player already has open, keeping their channel.
	local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
	if type(insert) == "function" then pcall(insert, text) end
	if landed() then return true end
	-- Otherwise open chat with the link ready to send.
	local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
	if type(open) == "function" then pcall(open, text) end
	return landed()
end

-- Last resort, so a link is never simply swallowed: show it ready to copy.
StaticPopupDialogs.WAYFINDER_SHARE = {
	text = "Wayfinder: copy this waypoint, then paste it wherever you like.",
	button1 = CLOSE or "Close",
	hasEditBox = true,
	editBoxWidth = 350,
	OnShow = function(self, data)
		local box = self.editBox or (self.GetEditBox and self:GetEditBox())
		if not box then return end
		box:SetText(data or "")
		box:HighlightText()
		box:SetFocus()
	end,
	-- The box exists to be copied from, not edited.
	EditBoxOnTextChanged = function(self, data)
		if data and self:GetText() ~= data then
			self:SetText(data)
			self:HighlightText()
		end
	end,
	EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function Navigation:ShareText(text)
	if InsertIntoChat(text) then return true end
	StaticPopup_Show("WAYFINDER_SHARE", nil, nil, text)
	ns.Print("Chat would not accept the link; copy it from the box instead.")
	return false
end

function Navigation:CopyWaypoint(rec)
	local link = self:GetWaypointLink(rec)
	if not link then
		ns.Print((rec or current) and "That spot has no place on a map that can be linked."
			or "Set a waypoint first, or left-click any map pin to share it.")
		return false
	end
	-- The player still chooses when to send it.
	return self:ShareText(link)
end

function Navigation:ReceiveWaypointLink(link, text, button)
	-- Modified clicks retain the game's normal copy/dress-up behavior.
	if button ~= "LeftButton" or IsModifiedClick() or type(link) ~= "string" or #link > 128 then
		return false
	end
	local share = link:match("^wayfinder:(.*)$")
	if share then
		return self:ImportWaypointShare("[Wayfinder:" .. share .. "]")
	end
	-- Continue to accept standard game map-pin links and 1.3.1's links.
	local mapID, x, y = link:match("^worldmap:(%d+):(%d+):(%d+)$")
	mapID, x, y = ValidPosition(mapID, x, y)
	if not mapID then return false end
	local label = type(text) == "string" and text:match("|h%[Wayfinder: (.-)%]|h")
	label = label and LinkLabel(label)
	return self:SetWaypointOnMap(mapID, x / 10000, y / 10000, label ~= "" and label or nil)
end

---------------------------------------------------------------------------
-- The arrow
---------------------------------------------------------------------------
local arrow
local ARROW_FRAMES, ARROW_COLUMNS, ARROW_ROWS = 128, 16, 8
local TURN = 2 * math.pi

local function ShowBearing(angle)
	-- Projected facets keep a fixed camera/light; rotate by selecting a yaw frame.
	local index = math.floor((angle % TURN) / TURN * ARROW_FRAMES + 0.5) % ARROW_FRAMES
	arrow.bearingFrame = index
	if arrow.useAtlas then
		if arrow.drawnFrame ~= index then
			local column, row = index % ARROW_COLUMNS, math.floor(index / ARROW_COLUMNS)
			arrow.head:SetTexCoord(column / ARROW_COLUMNS, (column + 1) / ARROW_COLUMNS,
				row / ARROW_ROWS, (row + 1) / ARROW_ROWS)
			arrow.drawnFrame = index
		end
	else
		-- A running client may not see newly installed texture files until restarted.
		arrow.head:SetRotation(angle)
	end
end

local function FormatDistance(yards)
	if yards >= 10000 then
		return ("%.1fk yd"):format(yards / 1000)
	end
	return ("%d yd"):format(yards + 0.5)
end

local function Tint(colour)
	arrow.head:SetVertexColor(colour[1], colour[2], colour[3])
	arrow.distance:SetTextColor(colour[1], colour[2], colour[3])
end

-- The waypoint's whole name under the arrow, on as many lines as it takes, and
-- on a guide's route the goal it leads to. Set only when it changes, since
-- this runs every few frames.
local function ShowNames(name, detail)
	if arrow.shownName ~= name then
		arrow.shownName = name
		arrow.label:SetText(name)
	end
	detail = detail or ""
	if arrow.shownGoal ~= detail then
		arrow.shownGoal = detail
		arrow.goal:SetText(detail)
	end
end

---------------------------------------------------------------------------
-- Walking routes from Wayfinder's bundled router.
---------------------------------------------------------------------------
local walk
local REROUTE_YARDS = 25
-- The walking leg shown on the maps, including an approach to a transport.
local trailCont, trailX, trailY, trailWalk

function Navigation:GetRouteStyle()
	local style = ns:GetSetting("routeStyle")
	return (style == "fastest" or style == "roads") and style or "balanced"
end

local function ClearWalk()
	local old = walk
	walk = nil
	if old and old.job then old.engine.Cancel(old.job) end
end

local function PlayerHeight(compat, cont)
	if not (compat and compat.GetPlayerUnitPosition) then return end
	local _, _, height, instance = compat.GetPlayerUnitPosition()
	if instance == cont then return height end
end

local function AskWalk(engine, follow, compat, danger, cont, wx, wy, mapID, style, ghost, rec)
	local route = { waypoint = rec, engine = engine, style = style, ghost = ghost,
		x = wx, y = wy, asked = GetTime(), pending = true }
	walk = route
	local level = danger and danger.Level and danger.Level()
	local profile = compat and compat.GetPlayerFaction and compat.GetPlayerFaction()
	local options = { style = style, waterWalking = ghost, profile = profile,
		walkLevel = profile and danger and danger.Blocked and (level or 0) or nil,
		danger = level and danger.Table and danger.Table(level, mapID, rec.m) }
	local function Finished(points, reason, result)
		if walk ~= route then return end
		route.job, route.pending = nil, false
		if not points or #points == 0 then
			if reason ~= "nodata" and reason ~= "outside" then
				route.status = "No walking route"
				if ns.Travel and (reason == "unreachable" or reason == "no safe walking route") then
					ns.Travel:WalkFailed(rec)
				end
			end
			return
		end
		local xs, ys, zs, left, state = {}, {}, {}, {}, {}
		local count = #points
		xs.absoluteDry = points.absoluteDry
		for i = count, 1, -1 do
			local point = points[i]
			xs[i], ys[i], zs[i] = point.x, point.y, point.z or false
			if point.detail then
				xs.detail = xs.detail or {}
				xs.detail[i] = true
			end
			if i == count then
				left[i] = ns.Distance(point.x, point.y, rec.x, rec.y)
			else
				left[i] = left[i + 1] + ns.Distance(point.x, point.y, xs[i + 1], ys[i + 1])
			end
		end
		follow.Reset(state)
		follow.Mark(xs, ys, zs, left, count, state)
		route.xs, route.ys, route.zs, route.left, route.state = xs, ys, zs, left, state
		route.partial = result and result.reached
	end
	local ok, job = pcall(engine.Find, cont, { x = wx, y = wy, z = PlayerHeight(compat, cont) },
		{ x = rec.x, y = rec.y, z = rec.z }, Finished, options)
	if route.pending then
		if ok and job then route.job = job else Finished(nil, "nodata") end
	end
end

local function UpdateWalk(cont, wx, wy, mapID, rec)
	local routing = ns.Walking
	local nav = routing and routing.Nav
	if not (nav and nav.Path and nav.follow) or routing.Compat.IsOnTaxi() then
		ClearWalk()
		return
	end
	local engine, follow, compat, danger = nav.Path, nav.follow, routing.Compat, nav.danger
	local style = Navigation:GetRouteStyle()
	local ghost = UnitIsGhost and UnitIsGhost("player")
	ghost = ns.Readable(ghost) and ghost == true
	if walk and (walk.waypoint ~= rec or walk.style ~= style or walk.ghost ~= ghost) then
		ClearWalk()
	end
	local hasNext, yards, stray, retryAfter
	if walk and walk.xs then
		local xs, ys, zs, left, state = walk.xs, walk.ys, walk.zs, walk.left, walk.state
		if not walk.caught then
			follow.Catch(xs, ys, zs, left, #xs, state, wx, wy,
				ns.Distance(wx, wy, walk.x, walk.y), REROUTE_YARDS, nil, PlayerHeight(compat, cont))
			walk.caught = true
		end
		local outdoors = compat and compat.IsIndoors and compat.IsIndoors() == false
		hasNext = follow.Step(xs, ys, zs, left, #xs, state, wx, wy, nil, nil, nil, outdoors) ~= nil
		local nextPoint = min(state.idx, #xs)
		yards = ns.Distance(wx, wy, xs[nextPoint], ys[nextPoint]) + left[nextPoint]
		stray = hasNext and state.off or ns.Distance(wx, wy, xs[#xs], ys[#xs])
		retryAfter = yards > 2000 and 10 or 2
	elseif walk and not walk.job then
		stray, retryAfter = ns.Distance(wx, wy, walk.x, walk.y), 15
	end
	local needsWalk = not walk or (stray and stray > REROUTE_YARDS and GetTime() - walk.asked >= retryAfter)
	if needsWalk and not InCombatLockdown() and engine.Available(cont) then
		AskWalk(engine, follow, compat, danger, cont, wx, wy, mapID, style, ghost, rec)
		hasNext, yards = false, nil
	end
	local status = walk and (walk.pending and "Finding walking route…" or walk.status)
	if walk and walk.partial and not hasNext then status = "No walking route" end
	return hasNext and walk or nil, yards, status
end

-- World coordinates of the remaining walk, starting at the next path point.
-- A partial route ends at its last known walkable point.
function Navigation:GetTrail()
	if not (current and trailCont and arrow and arrow:IsShown()) then return end
	local route = trailWalk
	if route and route == walk and route.xs and #route.xs > 0 then
		local endX, endY
		if not route.partial then endX, endY = trailX, trailY end
		return trailCont, endX, endY, route.xs, route.ys, min(route.state.idx or 1, #route.xs)
	end
	return trailCont, trailX, trailY
end

-- Points the arrow from the player toward the waypoint.
function Navigation:UpdateArrow()
	if not current then
		return
	end
	trailCont, trailWalk = nil, nil
	local cont, wx, wy, mapID = ns.GetPlayerWorld()
	local stop, instruction, caption, usingTransport
	if ns.Travel then stop, instruction, caption, usingTransport = ns.Travel:Aim(current, cont, wx, wy, mapID) end
	-- Both displays lead to this leg's endpoint. Only the trail follows its turns.
	local leg = stop or current
	local away = cont and cont ~= leg.c
	local step = instruction or caption
	if stop or usingTransport or current.goal or away or not cont then
		local onward = current.goal or (step and current.n)
		ShowNames(step or (away and (leg.n .. " (another continent)") or leg.n),
			onward and ("On the way to " .. onward))
	else
		ShowNames(leg.n, step)
	end

	local walkDistance, status
	if cont and cont == leg.c and not instruction then
		trailWalk, walkDistance, status = UpdateWalk(cont, wx, wy, mapID, leg)
		if not status then trailCont, trailX, trailY = cont, leg.x, leg.y end
	else
		ClearWalk()
	end
	if not cont or away or usingTransport then
		arrow.head:Hide()
		arrow.distance:SetText(instruction and "" or (cont and "Far away" or "?"))
		Tint(CYAN)
		return
	end
	local dx, dy = leg.x - wx, leg.y - wy -- yards north, yards west
	local distance = sqrt(dx * dx + dy * dy)
	-- Standing at your corpse is not the end of that one: coming back to life is.
	-- Nor is reaching a guide's goal: the guide moves it on when it is done.
	if not stop and not instruction and not status and max(distance, walkDistance or 0) <= ARRIVE_YARDS
		and current.source ~= CORPSE and not current.kept and ns:GetSetting("clearOnArrival") then
		ns.Print("Arrived at " .. current.n .. ".")
		Sound("MAP_PING")
		self:ClearWaypoint()
		return
	end
	-- Both bearing and player facing count counter-clockwise from north.
	ShowBearing(atan2(dy, dx) - (GetPlayerFacing() or 0))
	arrow.head:Show()
	arrow.distance:SetText(status or FormatDistance(distance))
	Tint(distance <= NEAR_YARDS and GREEN or CYAN)
end

---------------------------------------------------------------------------
-- Moving the arrow: while it is dragged, a line runs down the middle of the
-- screen, and the arrow snaps onto it when it comes close.
---------------------------------------------------------------------------
local SNAP_DISTANCE = 16 -- screen units either side of the middle
local GUIDE_FAINT, GUIDE_SNAPPED = 0.35, 0.9
local guide

local function Guide(f)
	if guide then return guide end
	guide = CreateFrame("Frame", nil, UIParent)
	guide:SetFrameStrata(f:GetFrameStrata())
	guide:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1)) -- behind the arrow
	guide:SetWidth(2)
	guide:SetPoint("TOP", UIParent, "TOP", 0, 0)
	guide:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
	guide.line = guide:CreateTexture(nil, "ARTWORK")
	guide.line:SetAllPoints()
	guide:Hide()
	return guide
end

-- The arrow has a scale of its own, so everything is measured in its units.
local function CursorFor(f)
	local x, y = GetCursorPosition()
	local scale = f:GetEffectiveScale()
	return x / scale, y / scale
end

-- The middle of the screen, and how many of the arrow's units make one of
-- the screen's.
local function MiddleFor(f)
	local x, y = UIParent:GetCenter()
	local ratio = UIParent:GetEffectiveScale() / f:GetEffectiveScale()
	return x * ratio, y * ratio, ratio
end

-- Puts the arrow under the cursor, where it was picked up, snapping it to the
-- middle when near. Returns its offset from the middle of the screen.
function Navigation:FollowCursor(f)
	local x, y = CursorFor(f)
	local middleX, middleY, ratio = MiddleFor(f)
	local dx, dy = x - f.grab[1] - middleX, y - f.grab[2] - middleY
	local snapped = math.abs(dx) <= SNAP_DISTANCE * ratio
	if snapped then dx = 0 end
	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent, "CENTER", dx, dy)
	local line = Guide(f)
	local color = snapped and CYAN or { 1, 1, 1 }
	line.line:SetColorTexture(color[1], color[2], color[3], snapped and GUIDE_SNAPPED or GUIDE_FAINT)
	line:Show()
	return dx, dy
end

function Navigation:StartDrag(f)
	local cx, cy = f:GetCenter()
	if not cx then return end
	local x, y = CursorFor(f)
	f.grab = { x - cx, y - cy }
	self:FollowCursor(f)
end

-- Kept as an offset from the middle of the screen, so an arrow snapped there
-- stays in the middle at any resolution.
function Navigation:StopDrag(f)
	if not f.grab then return end
	local dx, dy = self:FollowCursor(f)
	f.grab = nil
	guide:Hide()
	ns.db.arrowPosition = { "CENTER", "CENTER", dx, dy }
end

local function CreateArrow()
	local f = CreateFrame("Button", "WayfinderArrow", UIParent)
	f:SetSize(110, 94)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:RegisterForClicks("RightButtonUp", "MiddleButtonUp")
	-- Moved by hand rather than by the game, so it can snap while dragged.
	f:SetScript("OnDragStart", function(self) Navigation:StartDrag(self) end)
	f:SetScript("OnDragStop", function(self) Navigation:StopDrag(self) end)
	f:SetScript("OnHide", function(self) Navigation:StopDrag(self) end)
	f:SetScript("OnClick", function(self, button)
		if button == "MiddleButton" then
			Navigation:ClearWaypoint()
		elseif button == "RightButton" then
			Navigation:OpenWaypointMenu(self)
		end
	end)
	f:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(current and current.n or "Wayfinder", 1, 0.82, 0)
		if current and current.where and current.where ~= current.n then
			GameTooltip:AddLine(current.where, 0.8, 0.8, 0.8)
		end
		if current and current.goal then
			GameTooltip:AddLine("On the way to " .. current.goal, 0.8, 0.8, 0.8, true)
		end
		if current and current.note then
			GameTooltip:AddLine(current.note, 0.6, 0.85, 1, true)
		end
		if #list > 1 then
			GameTooltip:AddLine(("%d waypoints set."):format(#list), 0.6, 0.85, 1)
		end
		GameTooltip:AddLine("Drag to move; it snaps to the middle of the screen. Middle-click to remove this waypoint.", 1, 1, 1, true)
		GameTooltip:AddLine("Right-click for the whole list.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", GameTooltip_Hide)

	local hub = CreateFrame("Frame", nil, f)
	hub:SetSize(80, 62)
	hub:SetPoint("TOP")
	local function Layer(file, layer, subLevel, size)
		local tex = f:CreateTexture(nil, layer, nil, subLevel)
		local loaded = tex:SetTexture(MEDIA .. "Arrow\\" .. file)
		tex:SetSize(size, size)
		tex:SetPoint("CENTER", hub, "CENTER")
		return tex, loaded ~= false
	end
	f.head, f.useAtlas = Layer("NeedleAtlas", "ARTWORK", 0, 100)
	if not f.useAtlas then
		f.head:SetTexture(MEDIA .. "PlayerArrow")
		f.head:SetSize(64, 64)
		ns.Print("Restart the game to load the waypoint arrow artwork; a simple pointer is shown until then.")
	end

	-- Keep the useful readout without an opaque panel covering the world.
	f.distance = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.distance:SetPoint("TOP", hub, "BOTTOM", 0, -1)
	f.distance:SetShadowColor(0, 0, 0, 1)
	f.distance:SetShadowOffset(1, -1)
	-- Wider than the arrow, and wrapped rather than cut off: a guide's step
	-- ("Accept ...", "Learn the flight path at ..., then fly to ...") is read
	-- off the arrow, and only the start of it said nothing.
	local function Line(template, anchor)
		local text = f:CreateFontString(nil, "OVERLAY", template)
		text:SetPoint("TOP", anchor, "BOTTOM", 0, -1)
		text:SetWidth(LABEL_WIDTH)
		text:SetJustifyH("CENTER")
		text:SetWordWrap(true)
		text:SetNonSpaceWrap(true)
		text:SetShadowColor(0, 0, 0, 1)
		text:SetShadowOffset(1, -1)
		return text
	end
	f.label = Line("GameFontHighlightSmall", f.distance)
	f.goal = Line("GameFontHighlightSmall", f.label)
	f.goal:SetTextColor(0.75, 0.75, 0.75)

	local elapsedSince = 0
	f:SetScript("OnUpdate", function(self, elapsed)
		if self.grab then Navigation:FollowCursor(self) end
		elapsedSince = elapsedSince + elapsed
		if elapsedSince >= 0.03 then
			elapsedSince = 0
			Navigation:UpdateArrow()
		end
	end)
	f:Hide()
	return f
end

function Navigation:PlaceArrow()
	arrow:ClearAllPoints()
	local position = ns.db.arrowPosition
	if position then
		arrow:SetPoint(position[1], UIParent, position[2], position[3], position[4])
	else
		arrow:SetPoint("TOP", UIParent, "TOP", 0, -140)
	end
	arrow:SetScale(ns:GetSetting("arrowScale") or 1)
end

function Navigation:RefreshArrow()
	if not arrow then
		return
	end
	if current and ns:GetSetting("showArrow") then
		arrow:Show()
		self:UpdateArrow()
	else
		ClearWalk()
		trailCont, trailWalk = nil, nil
		if ns.Travel then ns.Travel:Reset() end
		arrow:Hide()
	end
end

---------------------------------------------------------------------------
-- The arrow's waypoint list
---------------------------------------------------------------------------
local function MenuLabel(rec)
	local text = rec.n or "Waypoint"
	local cont, wx, wy = ns.GetPlayerWorld()
	if cont and rec.c == cont then
		return text .. "  |cff808080" .. FormatDistance(ns.Distance(rec.x, rec.y, wx, wy)) .. "|r"
	elseif rec.where and rec.where ~= text then
		return text .. "  |cff808080" .. rec.where .. "|r"
	end
	return text
end

local function CloseMenus()
	if not (Menu and Menu.GetManager) then
		return false
	end
	local ok, manager = pcall(Menu.GetManager)
	if not (ok and type(manager) == "table" and manager.CloseMenus) then
		return false
	end
	return pcall(manager.CloseMenus, manager) == true
end

local function CloseButton(parent)
	local ok, button = pcall(CreateFrame, "Button", nil, parent, "UIPanelCloseButton")
	if ok and type(button) == "table" then
		return button
	end
	button = CreateFrame("Button", nil, parent)
	button:SetNormalTexture("Interface\Buttons\UI-StopButton")
	button:SetHighlightTexture("Interface\Buttons\UI-StopButton", "ADD")
	return button
end

-- A small x on the row, so a waypoint can go without first becoming the one
-- the arrow follows. Menu rows are pooled and handed on to other addons, so
-- the button hides itself the moment its row does.
local function AddRemoveButton(row, rec)
	if type(row) ~= "table" or type(row.AddInitializer) ~= "function" then
		return false
	end
	row:AddInitializer(function(frame)
		local remove = frame.wayfinderRemove
		if not remove then
			remove = CloseButton(frame)
			remove:SetSize(18, 18)
			remove:SetPoint("RIGHT", -2, 0)
			remove:RegisterForClicks("LeftButtonUp")
			frame:HookScript("OnHide", function() remove:Hide() end)
			frame.wayfinderRemove = remove
		end
		remove:SetScript("OnClick", function()
			Navigation:RemoveWaypoint(rec)
			-- Reopened so several can go one after another, but only once the
			-- old list is gone: two menus at once is worse than none.
			if CloseMenus() and #list > 0 and arrow and C_Timer then
				C_Timer.After(0, function() Navigation:OpenWaypointMenu(arrow) end)
			end
		end)
		remove:Show()
	end)
	return true
end

function Navigation:OpenWaypointMenu(owner)
	if #list == 0 then
		ns.Print("No waypoints. Middle-click the map, or type /way 42 65, to set one.")
		return false
	end
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		-- No menu system: step the arrow along the list rather than do nothing.
		self:SetActiveWaypoint(list[(IndexOf(current) or #list) % #list + 1])
		return false
	end
	MenuUtil.CreateContextMenu(owner or arrow, function(_, root)
		root:CreateTitle(#list == 1 and "Waypoint" or (#list .. " waypoints"))
		for _, rec in ipairs(list) do
			local row = root:CreateRadio(MenuLabel(rec),
				function() return rec == current end,
				function() Navigation:SetActiveWaypoint(rec) end)
			if not AddRemoveButton(row, rec) then
				-- Without row initializers, give each one its own removal line.
				root:CreateButton("      Remove " .. (rec.n or "waypoint"), function()
					Navigation:RemoveWaypoint(rec)
				end)
			end
		end
		root:CreateDivider()
		root:CreateButton("Clear all waypoints", function() Navigation:ClearAllWaypoints() end)
		if root.SetScrollMode and #list > 12 then
			root:SetScrollMode(320)
		end
	end)
	return true
end

---------------------------------------------------------------------------
-- The world map: middle-click and "track my location"
---------------------------------------------------------------------------
-- Tracking lasts for the session and only the locate button toggles it.
-- Holding the map temporarily pauses following so it can still be dragged.
local FOLLOW_EVERY = 0.05 -- seconds between moves; the map eases in between
local tracking = false

local function PlayerMap()
	return (MapUtil and MapUtil.GetDisplayableMapForPlayer and MapUtil.GetDisplayableMapForPlayer())
		or C_Map.GetBestMapForUnit("player")
end

-- Whether a button is held on the map: the canvas's own record, which
-- also catches presses that reach it through a map icon.
function Navigation:IsMapInputHeld()
	local container = WorldMapFrame and WorldMapFrame.ScrollContainer
	local info = container and container.mouseButtonInfo
	local left = info and info.LeftButton
	local right = info and info.RightButton
	return (left and left.down == true) or (right and right.down == true)
		or (container and container.HasGamepadScrollSpeed and container:HasGamepadScrollSpeed())
		or ns.DetailView:IsDragging() == true
end

-- Puts another map up. The game keeps what that sets in the addon's name, and
-- its own pins would pay for it with a blocked call in the next fight, so
-- they are guarded from the first time this happens (PinGuard.lua).
local function ShowMap(mapID)
	if ns.PinGuard then
		ns.PinGuard:Arm()
	end
	WorldMapFrame:SetMapID(mapID)
end

-- Already on your map: if zoomed in, slide over to you.
local function PanToPlayer(mapID)
	local position = C_Map.GetPlayerMapPosition(mapID, "player")
	if position and not WorldMapFrame:IsAtMinZoom() then
		local x, y = position:GetXY()
		local container = WorldMapFrame.ScrollContainer
		local minX, maxX, minY, maxY = container:CalculateScrollExtentsAtScale(container:GetCanvasScale())
		WorldMapFrame:PanTo(min(max(x, minX), maxX), min(max(y, minY), maxY))
	end
end

function Navigation:ShowPlayerOnMap()
	if ns.DetailView:IsActive() then
		if ns.DetailView:CenterOnPlayer() then
			return
		end
		ns.DetailView:Exit(true)
	end
	if ns.OpenMapCompat:ShowPlayer() then return end
	local mapID = PlayerMap()
	if not mapID then
		return
	end
	if WorldMapFrame:GetMapID() ~= mapID then
		ShowMap(mapID)
		return
	end
	PanToPlayer(mapID)
end

-- One step of tracking: the same moves as showing the player, made gently
-- enough to repeat while you walk.
function Navigation:FollowPlayer()
	if ns.DetailView:IsActive() then
		if ns.DetailView:CenterOnPlayer() then
			return
		end
		ns.DetailView:Exit(true)
	end
	if ns.OpenMapCompat:FollowPlayer() then return end
	local mapID = PlayerMap()
	if not mapID then
		return
	end
	if WorldMapFrame:GetMapID() ~= mapID then
		-- Over the border into the next zone. Not mid-fight: the map is the
		-- game's, and changing it from here then is asking for blocked actions.
		if not InCombatLockdown() then
			ShowMap(mapID)
		end
		return
	end
	PanToPlayer(mapID)
end

function Navigation:IsTracking()
	return tracking
end

function Navigation:SetTracking(on)
	on = on == true
	if tracking == on then
		return
	end
	tracking = on
	self.followElapsed = 0
	if on then
		ns.ContinuousMap:ClearPositionMemory()
		self:ShowPlayerOnMap()
	end
	self:RefreshLocateButton()
end

-- Runs while the map is open: the button that owns it is the map's child.
function Navigation:OnTrackingUpdate(elapsed)
	if not tracking then
		return
	end
	if self:IsMapInputHeld() then
		return
	end
	self.followElapsed = (self.followElapsed or 0) + elapsed
	if self.followElapsed >= FOLLOW_EVERY then
		self.followElapsed = 0
		self:FollowPlayer()
	end
end

function Navigation:ShowLocateTooltip(button)
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	if tracking then
		GameTooltip:SetText("Tracking my location")
		GameTooltip:AddLine("The map follows you as you move. Click again to stop.", 1, 1, 1, true)
	else
		GameTooltip:SetText("Track my location")
		GameTooltip:AddLine("Moves the map to you and follows you as you move, even after reopening it.", 1, 1, 1, true)
	end
	GameTooltip:AddLine("Middle-click anywhere on the map to set a waypoint.", 0.8, 0.8, 0.8, true)
	GameTooltip:Show()
end

-- Lit and blue while tracking, the plain gold crosshair otherwise.
function Navigation:RefreshLocateButton()
	local button = self.locateButton
	if not button then
		return
	end
	button.lit:SetShown(tracking)
	button.icon:SetDesaturated(tracking)
	if tracking then
		button.icon:SetVertexColor(0.45, 0.85, 1)
	else
		button.icon:SetVertexColor(1, 1, 1)
	end
	if GameTooltip.IsOwned and GameTooltip:IsOwned(button) then
		self:ShowLocateTooltip(button)
	end
end

function Navigation:CreateLocateButton()
	local button = CreateFrame("Button", "WayfinderLocateButton", WorldMapFrame)
	button:SetSize(32, 32)
	button:SetFrameStrata("HIGH")
	-- Forever puts Blizzard's map pin button in the top-left corner; sit beside it.
	local pinButton = WorldMapFrame.WorldMapTrackingPinButton
	if pinButton then
		button:SetPoint("LEFT", pinButton, "RIGHT", 2, 0)
	else
		button:SetPoint("TOPLEFT", WorldMapFrame:GetCanvasContainer(), "TOPLEFT", 3, 0)
	end

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(25, 25)
	background:SetPoint("TOPLEFT", 3, -4)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(MEDIA .. "Locate")
	icon:SetSize(20, 20)
	icon:SetPoint("TOPLEFT", 7, -6)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(54, 54)
	border:SetPoint("TOPLEFT")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
	-- The hover glow, kept on while tracking.
	local lit = button:CreateTexture(nil, "OVERLAY", nil, 1)
	lit:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	lit:SetBlendMode("ADD")
	lit:SetAllPoints()
	lit:Hide()
	button.icon, button.lit = icon, lit

	button:SetScript("OnMouseDown", function()
		icon:SetPoint("TOPLEFT", 8, -7)
	end)
	button:SetScript("OnMouseUp", function()
		icon:SetPoint("TOPLEFT", 7, -6)
	end)
	button:SetScript("OnClick", function()
		Navigation:SetTracking(not tracking)
	end)
	button:SetScript("OnEnter", function(self)
		Navigation:ShowLocateTooltip(self)
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnUpdate", function(_, elapsed)
		Navigation:OnTrackingUpdate(elapsed)
	end)
	self.locateButton = button

	WorldMapFrame:HookScript("OnShow", function()
		-- Resume on the first update, after the map and its providers have opened.
		Navigation.followElapsed = FOLLOW_EVERY
	end)
	self:RefreshLocateButton()
end

-- Shift-clicking the game's own map pin puts its link in chat and copies a
-- /way command to the clipboard. Wayfinder moves Blizzard's map about, which
-- leaves its pins tainted, and the clipboard is closed to addons outright, so
-- the click was blocked. Share the link here and stop the game's handler.
local function WaypointPinUnderCursor()
	local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
	for _, focus in ipairs(foci) do
		if type(focus) == "table" and focus.pinTemplate == "WaypointLocationPinTemplate" then return focus end
	end
end

function Navigation:OnMapPinAction(action)
	if action ~= MapCanvasMixin.MouseAction.Click or not IsModifiedClick("CHATLINK") then return false end
	if not WaypointPinUnderCursor() then return false end
	local link = C_Map.GetUserWaypointHyperlink and C_Map.GetUserWaypointHyperlink()
	if link then
		self:ShareText(link)
		if SOUNDKIT and SOUNDKIT.UI_MAP_WAYPOINT_CHAT_SHARE then PlaySound(SOUNDKIT.UI_MAP_WAYPOINT_CHAT_SHARE) end
	end
	return true
end

function Navigation:HookWorldMap()
	if WorldMapFrame.AddGlobalPinMouseActionHandler and MapCanvasMixin and MapCanvasMixin.MouseAction then
		WorldMapFrame:AddGlobalPinMouseActionHandler(function(_, action) return self:OnMapPinAction(action) end, 2000)
	end
	local container = WorldMapFrame.ScrollContainer
	container:HookScript("OnMouseUp", function(_, button)
		if button ~= "MiddleButton" then
			return
		end
		if ns.OpenMapCompat:IsActive() then return end -- handled before OpenMap recentres
		local x, y = container:GetNormalizedCursorPosition()
		if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
			self:SetWaypointOnMap(WorldMapFrame:GetMapID(), x, y)
		end
	end)
	self:CreateLocateButton()
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
function Navigation:OnLogin()
	self:LoadWaypoints()
	arrow = CreateArrow()
	self.arrow = arrow
	self:PlaceArrow()
	self:RefreshArrow()
	-- Register our local link type so Blizzard won't try to show an item tooltip.
	LinkUtil.RegisterLinkHandler("wayfinder", function(link, text, _, context)
		if context.button == "LeftButton" and IsModifiedClick("CHATLINK") then
			-- Re-sharing uses the copyable token, never a custom link on the wire.
			local token = "[Wayfinder:" .. link:sub(11) .. "]"
			if ParseShare(token) then self:ShareText(token) end
		else
			self:ReceiveWaypointLink(link, text, context.button)
		end
	end)
	local function ChatFilter(_, _, message, ...)
		return false, self:FormatWaypointMessage(message), ...
	end
	for _, event in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
		"CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
		"CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
		"CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_COMMUNITIES_CHANNEL" }) do
		-- Same namespace move as the insert helpers; a missing filter must not
		-- abort the rest of this setup.
		local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
			or ChatFrame_AddMessageEventFilter
		if type(addFilter) == "function" then pcall(addFilter, event, ChatFilter) end
	end
	-- Keep the game's handler intact for native map-pin links.
	hooksecurefunc("SetItemRef", function(link, text, button)
		if type(link) == "string" and link:match("^worldmap:") then
			self:ReceiveWaypointLink(link, text, button)
		end
	end)
	ns:On("SETTING_CHANGED", function(key)
		if key == "arrowScale" then
			arrow:SetScale(ns:GetSetting("arrowScale") or 1)
		elseif key == "showArrow" or key == "routeStyle" then
			self:RefreshArrow()
		elseif key == "corpseWaypoint" then
			if ns:GetSetting("corpseWaypoint") then
				self:CheckCorpse()
			else
				self:ClearCorpse()
			end
		end
	end)
	-- Releasing your spirit (PLAYER_ALIVE as a ghost), coming back to life
	-- (PLAYER_UNGHOST, or PLAYER_ALIVE from a resurrection taken before
	-- releasing), and arriving in the world as a ghost.
	local function Check() self:CheckCorpse() end
	ns:RegisterEvent("PLAYER_ALIVE", Check)
	ns:RegisterEvent("PLAYER_UNGHOST", Check)
	ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		ClearWalk()
		Check()
	end)
	ns:RegisterEvent("PLAYER_LEVEL_UP", ClearWalk)
	ns:On("TRAVEL_ORIGIN_CHANGED", ClearWalk)
	EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", function()
		self:HookWorldMap()
	end)
end
