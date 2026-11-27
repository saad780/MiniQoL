-- Sharing the arrow's waypoint with your group.
--
-- The group leader's waypoint (the one their arrow is on) goes to every group
-- member who has Mini QoL, and lands on their arrow as a waypoint of its own.
-- As the leader's arrow moves on, so does the members'; when the leader has no
-- waypoint left, stops sharing or hands the lead on, the members' goes. A member
-- can still remove it, and it stays gone until the leader picks a new one.
-- After a change the leader can be told who got it, who has following turned
-- off, and who didn't answer (no Mini QoL, or an older one).
--
-- Addon messages under PREFIX, tab-separated, on the group's channel:
--   W, version, id, continent, x, y, uiMapID, label, wantReply
--        the leader's waypoint (world yards, x north and y west, as Wayfinder
--        keeps them). `id` names this waypoint of this leader: a session of
--        theirs and a change number, so the same one sent again (to a member
--        who has just joined) is recognised and left alone by the others.
--   C, version, id                the leader has no waypoint to share any more
--   A, version, id, status        a member's answer: "got", or "off"
--   R, version                    a member asks the leader for the waypoint
-- A waypoint on your corpse is never shared, nor one shared with you.
local _, ns = ...

local Group = ns:NewModule("GroupWaypoints")

local PREFIX = "MiniQoLWay"
local VERSION = "2"
local SOURCE = "group"        -- the source of the waypoint a member takes
local CORPSE = "corpse"       -- Navigation's corpse waypoint: not for sharing
local SEND_DELAY = 0.5        -- seconds: waypoint changes come in bursts
local REPLY_WAIT = 4          -- seconds to wait for answers before the report
local RETRY_DELAY = 5         -- seconds between tries while messages are locked down
local LABEL_LIMIT = 120

-- Leader
local session = tostring(math.random(100000, 999999)) -- tells this login's changes from the last one's
local seq = 0                 -- the leader's change counter
local lastSent                -- the leader's last W (or "C"), without its id
local lastID                  -- and its id
local sendPending = false
local replies                 -- [sender] = status, for the leader's last change
local reportFor               -- the id that report is about
-- Member
local taken                   -- { id, leader }: the waypoint taken from the leader
local dismissed = {}          -- [id] = true: removed by the player, not to come back
local dropping = false
local asked                   -- the leader a member last asked for the waypoint
-- Both
local queued                  -- a message that waits out a messaging lockdown
local retrying = false

---------------------------------------------------------------------------
-- The group
---------------------------------------------------------------------------
local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if ok and ns.Readable(a) then return a, b end
end

local function InGroup()
	return Call(IsInGroup) == true
end

local function Channel()
	if LE_PARTY_CATEGORY_INSTANCE and Call(IsInGroup, LE_PARTY_CATEGORY_INSTANCE) == true
		and Call(IsInGroup, LE_PARTY_CATEGORY_HOME) ~= true then
		return "INSTANCE_CHAT"
	end
	if Call(IsInRaid) == true then return "RAID" end
	if InGroup() then return "PARTY" end
end

local function IsLeader()
	return InGroup() and Call(UnitIsGroupLeader, "player") == true
end

-- The units of everyone else in the group.
local function Others()
	local units = {}
	local raid = Call(IsInRaid) == true
	local prefix, count = raid and "raid" or "party", raid and 40 or 4
	for i = 1, count do
		local unit = prefix .. i
		if Call(UnitExists, unit) == true and Call(UnitIsUnit, unit, "player") ~= true then
			units[#units + 1] = unit
		end
	end
	return units
end

local function Plain(text)
	return type(text) == "string" and (text:gsub("%s", ""):lower()) or ""
end

-- A name as a first name and the rest: "Deathor-Cake", "Deathor Cake" and
-- "Deathor-Realm" all come apart at the first dash or space.
local function Split(name)
	local first, rest = name:match("^([^%-%s]+)[%-%s]*(.*)$")
	return Plain(first or name), Plain(rest)
end

-- Whether a message's sender is `unit`. Senders come as "Name-Realm"; on
-- Forever's nameless realms what follows the name is the surname (or, it may
-- be, the server's number), and UnitName gives the surname as its second value
-- or inside its first. So the first names decide, and the rest only when both
-- sides have one that is a name and not a number.
local function IsSender(sender, unit)
	local name, rest = Call(UnitName, unit)
	if type(name) ~= "string" or type(sender) ~= "string" then return false end
	local senderFirst, senderRest = Split(sender)
	local unitFirst, unitRest = Split(name)
	if ns.Readable(rest) and type(rest) == "string" and rest ~= "" then unitRest = Plain(rest) end
	if senderFirst ~= unitFirst then return false end
	if senderRest == "" or unitRest == "" or senderRest:find("^%d+$") or unitRest:find("^%d+$") then return true end
	return senderRest == unitRest
end
Group.IsSender = IsSender

local function Display(unit)
	local name, rest = Call(UnitName, unit)
	if type(name) ~= "string" then return "?" end
	if ns.Readable(rest) and type(rest) == "string" and rest ~= "" then return name .. " " .. rest end
	return name
end

local function LeaderUnit()
	for _, unit in ipairs(Others()) do
		if Call(UnitIsGroupLeader, unit) == true then return unit end
	end
end

local function FromSelf(sender)
	return IsSender(sender, "player")
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
local function Locked()
	return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and Call(C_ChatInfo.InChatMessagingLockdown) == true
end

local Flush

-- Sends now, or once messages are allowed again (a boss fight locks them):
-- only the newest message waits, since it says all there is to say.
local function Send(text)
	local channel = Channel()
	if not (channel and C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
	if Locked() then
		queued = text
		if not retrying and C_Timer then
			retrying = true
			C_Timer.After(RETRY_DELAY, function() retrying = false; Flush() end)
		end
		return false
	end
	local ok = pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, channel)
	return ok
end

function Flush()
	if not queued then return end
	local text = queued
	queued = nil
	Send(text)
end
Group.Flush = Flush

local function Join(...)
	return table.concat({ ... }, "\t")
end

local function Round(value)
	return ("%.1f"):format(value)
end

-- What the leader would share now: the waypoint's fields, "C" for none, or
-- nil to leave the members' waypoint as it is (the arrow is on your corpse).
local function Current()
	local rec = ns.Navigation:GetWaypoint()
	if not rec then return "C" end
	if rec.source == CORPSE or rec.source == SOURCE then return nil end
	if not (rec.c and rec.x and rec.y) then return nil end
	local label = tostring(rec.n or "Waypoint"):gsub("[\t\n|]", " "):sub(1, LABEL_LIMIT)
	return Join(rec.c, Round(rec.x), Round(rec.y), tonumber(rec.m) or 0, label)
end

-- The leader's report on who got the waypoint, a moment after a change.
local function Report(id)
	if id ~= reportFor or not replies then return end
	local got, off, silent = {}, {}, {}
	for _, unit in ipairs(Others()) do
		local status
		for sender, answer in pairs(replies) do
			if IsSender(sender, unit) then status = answer end
		end
		local list = status == "got" and got or status == "off" and off or silent
		list[#list + 1] = Display(unit)
	end
	replies, reportFor = nil, nil
	if #got + #off + #silent == 0 then return end
	local parts = {}
	if #got > 0 then parts[#parts + 1] = "got it: " .. table.concat(got, ", ") end
	if #off > 0 then parts[#parts + 1] = "following turned off: " .. table.concat(off, ", ") end
	if #silent > 0 then parts[#parts + 1] = "no answer (no Mini QoL?): " .. table.concat(silent, ", ") end
	ns.Print("Shared your waypoint. " .. table.concat(parts, "; ") .. ".")
end

local function NextID()
	seq = seq + 1
	return session .. "." .. seq
end

-- The members' waypoint goes: no waypoint to share, sharing turned off, or the
-- lead handed on.
function Group:Withdraw()
	if not lastSent or lastSent == "C" then return false end
	lastSent, lastID = "C", NextID()
	replies, reportFor = nil, nil
	Send(Join("C", VERSION, lastID))
	return true
end

-- `quiet`: answering a member who asked, so the same waypoint goes out again
-- under the same id, and no answers are asked for.
function Group:Share(quiet)
	sendPending = false
	if not (IsLeader() and ns:GetSetting("shareGroupWaypoint")) then return false end
	if quiet then
		if not lastSent or lastSent == "C" then return false end
		Send(Join("W", VERSION, lastID, lastSent, "0"))
		return true
	end
	local state = Current()
	if not state or state == lastSent then return false end
	if state == "C" then return self:Withdraw() end
	lastSent, lastID = state, NextID()
	local wantReply = ns:GetSetting("reportGroupWaypoint") and "1" or "0"
	if wantReply == "1" then
		replies, reportFor = {}, lastID
		local id = lastID
		if C_Timer then C_Timer.After(REPLY_WAIT, function() Report(id) end) end
	end
	Send(Join("W", VERSION, lastID, state, wantReply))
	return true
end

local function ScheduleShare()
	if sendPending or not IsLeader() then return end
	sendPending = true
	if C_Timer then C_Timer.After(SEND_DELAY, function() Group:Share() end) else Group:Share() end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function Drop()
	local rec = ns.Navigation:GetSourceWaypoint(SOURCE)
	taken = nil
	if rec then
		dropping = true
		ns.Navigation:RemoveWaypoint(rec, true)
		dropping = false
	end
end

local function Take(unit, id, fields)
	local cont, x, y, mapID = tonumber(fields[4]), tonumber(fields[5]), tonumber(fields[6]), tonumber(fields[7])
	if not (cont and x and y) then return false end
	local leader = Display(unit)
	-- The same waypoint again, sent to someone who has just joined: leave
	-- yours where it is, or gone if you removed it.
	if dismissed[id] or (taken and taken.id == id and ns.Navigation:GetSourceWaypoint(SOURCE)) then return true end
	local label = fields[8] ~= "" and fields[8] or "Waypoint"
	ns.Navigation:PlaceSourceWaypoint(SOURCE, cont, x, y, label, mapID ~= 0 and mapID or nil,
		{ focus = true, note = ("Shared by %s, your group leader. Middle-click the arrow to let it go."):format(leader) })
	taken = { id = id, leader = leader }
	return true
end

function Group:OnMessage(prefix, text, _, sender)
	if prefix ~= PREFIX or type(text) ~= "string" or FromSelf(sender) then return end
	local fields = {}
	for field in (text .. "\t"):gmatch("([^\t]*)\t") do fields[#fields + 1] = field end
	local kind, version, id = fields[1], fields[2], fields[3]
	if version ~= VERSION then return end
	if kind == "A" then
		if IsLeader() and replies and id == reportFor and (fields[4] == "got" or fields[4] == "off") then
			replies[sender] = fields[4]
		end
		return
	end
	if kind == "R" then
		if IsLeader() then self:Share(true) end
		return
	end
	if kind ~= "W" and kind ~= "C" then return end
	local unit = LeaderUnit()
	if not (unit and IsSender(sender, unit)) then return end
	local follow = ns:GetSetting("followGroupWaypoint")
	if kind == "C" then
		if follow then Drop() end
		return
	end
	if follow then Take(unit, id, fields) end
	if fields[9] == "1" then Send(Join("A", VERSION, id, follow and "got" or "off")) end
end

-- Joining, the lead changing hands, or a reload: a member asks the (new)
-- leader once for the waypoint, and lets the last leader's go.
function Group:OnRoster()
	if not InGroup() then
		asked, lastSent, lastID, replies = nil, nil, nil, nil
		Drop()
		return
	end
	if IsLeader() then
		asked = nil
		if taken then Drop() end
		ScheduleShare()
		return
	end
	-- someone else leads now: what this one shared was for the old group
	lastSent, lastID, replies = nil, nil, nil
	local unit = LeaderUnit()
	local leader = unit and Display(unit)
	if taken and leader and taken.leader ~= leader then Drop() end
	if leader and leader ~= asked and ns:GetSetting("followGroupWaypoint") then
		asked = leader
		Send(Join("R", VERSION))
	end
end

function Group:OnLogin()
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
	end
	ns:RegisterEvent("CHAT_MSG_ADDON", function(_, ...) Group:OnMessage(...) end)
	ns:RegisterEvent("GROUP_ROSTER_UPDATE", function() Group:OnRoster() end)
	ns:RegisterEvent("PARTY_LEADER_CHANGED", function() Group:OnRoster() end)
	ns:RegisterEvent("PLAYER_ENTERING_WORLD", function() Group:OnRoster() end)
	ns:RegisterEvent("PLAYER_REGEN_ENABLED", Flush)
	ns:RegisterEvent("ENCOUNTER_END", Flush)
	ns:On("WAYPOINT_CHANGED", ScheduleShare)
	ns:On("WAYPOINT_REMOVED", function(rec)
		-- removed by the player: it stays gone until the leader picks another
		if not dropping and type(rec) == "table" and rec.source == SOURCE and taken then
			dismissed[taken.id] = true
			taken = nil
		end
	end)
	ns:On("SETTING_CHANGED", function(key)
		if key == "shareGroupWaypoint" then
			if ns:GetSetting(key) then ScheduleShare() elseif IsLeader() then Group:Withdraw() end
		elseif key == "followGroupWaypoint" and not ns:GetSetting(key) then
			Drop()
		end
	end)
end
