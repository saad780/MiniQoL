-- Sharing the arrow's waypoint with your group.
--
-- The group leader's waypoint (the one their arrow is on) goes to every group
-- member who has Mini QoL, and lands on their arrow as a waypoint of its own;
-- when the leader removes theirs, the members' goes too. Members can still
-- remove it themselves, and each side has its own switch. After a change the
-- leader can be told who got it, who has following turned off, and who didn't
-- answer (no Mini QoL, or an older one).
--
-- Addon messages under PREFIX, tab-separated, on the group's channel:
--   W, version, seq, continent, x, y, uiMapID, label, wantReply
--        the leader's waypoint (world yards, x north and y west, as Wayfinder
--        keeps them)
--   C, version, seq, wantReply    the leader has no waypoint any more
--   A, version, seq, status       a member's answer: "got", or "off"
--   R, version                    a member asks the leader for the waypoint
-- A waypoint on your corpse is never shared, nor one shared with you.
local _, ns = ...

local Group = ns:NewModule("GroupWaypoints")

local PREFIX = "MiniQoLWay"
local VERSION = "1"
local SOURCE = "group"        -- the source of the waypoint a member takes
local CORPSE = "corpse"       -- Navigation's corpse waypoint: not for sharing
local SEND_DELAY = 0.5        -- seconds: waypoint changes come in bursts
local REPLY_WAIT = 4          -- seconds to wait for answers before the report
local RETRY_DELAY = 5         -- seconds between tries while messages are locked down
local LABEL_LIMIT = 120

local seq = 0                 -- the leader's change counter
local lastSent                -- the text of the leader's last W or C, without its seq
local sendPending = false
local queued                  -- a message that waits out a messaging lockdown
local retrying = false
local replies                 -- [sender] = status, for the leader's last change
local asked                   -- the leader a member last asked for the waypoint

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

-- Lower case, without spaces, so "Deathor Cake" and "Deathor-Cake" compare.
local function Plain(text)
	return type(text) == "string" and (text:gsub("[%s]", ""):lower()) or nil
end

-- Whether a message's sender is `unit`. Senders come as "Name-Realm"; on
-- Forever's nameless realms the part after the dash is the surname, which
-- UnitName gives as its second value. Elsewhere UnitName leaves out the realm
-- of someone on your own, so the first names decide, and the rest only when
-- both sides have one.
local function IsSender(sender, unit)
	local name, rest = Call(UnitName, unit)
	if type(name) ~= "string" or type(sender) ~= "string" then return false end
	local first, other = sender:match("^([^%-]+)%-?(.*)$")
	if Plain(first) ~= Plain(name) then return false end
	rest = ns.Readable(rest) and type(rest) == "string" and rest or ""
	return other == "" or rest == "" or Plain(other) == Plain(rest)
end

local function Display(unit)
	local name, rest = Call(UnitName, unit)
	if type(name) ~= "string" then return "?" end
	if ns.Readable(rest) and type(rest) == "string" and rest ~= "" then return name .. " " .. rest end
	return name
end

-- The unit that leads the group, if it's the sender.
local function FromLeader(sender)
	for _, unit in ipairs(Others()) do
		if Call(UnitIsGroupLeader, unit) == true then return IsSender(sender, unit) and unit or nil end
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

-- What the leader would share now: the W or C message without its seq, or
-- nil to leave the members' waypoint as it is (the arrow is on your corpse).
local function Current()
	local rec = ns.Navigation:GetWaypoint()
	if not rec then return "C" end
	if rec.source == CORPSE or rec.source == SOURCE then return nil end
	if not (rec.c and rec.x and rec.y) then return nil end
	local label = tostring(rec.n or "Waypoint"):gsub("[\t\n|]", " "):sub(1, LABEL_LIMIT)
	return Join("W", rec.c, Round(rec.x), Round(rec.y), tonumber(rec.m) or 0, label)
end

-- The leader's report on who got the waypoint, a moment after a change.
local function Report(changeSeq)
	if changeSeq ~= seq or not replies then return end
	local got, off, silent = {}, {}, {}
	for _, unit in ipairs(Others()) do
		local status
		for sender, answer in pairs(replies) do
			if IsSender(sender, unit) then status = answer end
		end
		local list = status == "got" and got or status == "off" and off or silent
		list[#list + 1] = Display(unit)
	end
	replies = nil
	if #got + #off + #silent == 0 then return end
	local parts = {}
	if #got > 0 then parts[#parts + 1] = "got it: " .. table.concat(got, ", ") end
	if #off > 0 then parts[#parts + 1] = "following turned off: " .. table.concat(off, ", ") end
	if #silent > 0 then parts[#parts + 1] = "no answer (no Mini QoL?): " .. table.concat(silent, ", ") end
	ns.Print("Shared your waypoint. " .. table.concat(parts, "; ") .. ".")
end

-- `quiet`: answering a member's request, so no answers are asked for and the
-- unchanged waypoint goes out again.
function Group:Share(quiet)
	sendPending = false
	if not (IsLeader() and ns:GetSetting("shareGroupWaypoint")) then return false end
	local state = Current()
	if not state then return false end
	if not quiet and state == lastSent then return false end
	if state == "C" and not lastSent then return false end -- nothing was ever shared
	local wantReply = not quiet and ns:GetSetting("reportGroupWaypoint") and "1" or "0"
	seq = seq + 1
	lastSent = state
	local kind, rest = state:match("^(%a)\t?(.*)$")
	local text = rest ~= "" and Join(kind, VERSION, seq, rest, wantReply) or Join(kind, VERSION, seq, wantReply)
	if wantReply == "1" then
		replies = {}
		local changeSeq = seq
		if C_Timer then C_Timer.After(REPLY_WAIT, function() Report(changeSeq) end) end
	end
	Send(text)
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
local function Answer(changeSeq, status)
	Send(Join("A", VERSION, changeSeq, status))
end

local function Take(unit, fields)
	local cont, x, y, mapID = tonumber(fields[4]), tonumber(fields[5]), tonumber(fields[6]), tonumber(fields[7])
	if not (cont and x and y) then return false end
	local label = fields[8] ~= "" and fields[8] or "Waypoint"
	local leader = Display(unit)
	ns.Navigation:PlaceSourceWaypoint(SOURCE, cont, x, y, label, mapID ~= 0 and mapID or nil,
		{ focus = true, note = ("Shared by %s, your group leader. Middle-click the arrow to let it go."):format(leader) })
	return true
end

local function Drop()
	local rec = ns.Navigation:GetSourceWaypoint(SOURCE)
	if rec then ns.Navigation:RemoveWaypoint(rec, true) end
end

function Group:OnMessage(prefix, text, _, sender)
	if prefix ~= PREFIX or type(text) ~= "string" or FromSelf(sender) then return end
	local fields = {}
	for field in (text .. "\t"):gmatch("([^\t]*)\t") do fields[#fields + 1] = field end
	local kind, version = fields[1], fields[2]
	if version ~= VERSION then return end
	if kind == "A" then
		if IsLeader() and replies and tonumber(fields[3]) == seq and (fields[4] == "got" or fields[4] == "off") then
			replies[sender] = fields[4]
		end
		return
	end
	if kind == "R" then
		if IsLeader() then self:Share(true) end
		return
	end
	if kind ~= "W" and kind ~= "C" then return end
	local unit = FromLeader(sender)
	if not unit then return end
	local wantReply = fields[#fields] == "1"
	local follow = ns:GetSetting("followGroupWaypoint")
	if follow then
		if kind == "W" then Take(unit, fields) else Drop() end
	end
	if wantReply then Answer(fields[3], follow and "got" or "off") end
end

-- A member who joins (or reloads) asks the leader once for the waypoint.
local function LeaderName()
	for _, unit in ipairs(Others()) do
		if Call(UnitIsGroupLeader, unit) == true then return Display(unit) end
	end
end

function Group:OnRoster()
	if not InGroup() then
		asked, lastSent, replies = nil, nil, nil
		Drop()
		return
	end
	if IsLeader() then
		asked = nil
		ScheduleShare()
		return
	end
	lastSent = nil -- someone else leads now
	local leader = LeaderName()
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
	ns:On("SETTING_CHANGED", function(key)
		if key == "shareGroupWaypoint" and ns:GetSetting(key) then ScheduleShare()
		elseif key == "followGroupWaypoint" and not ns:GetSetting(key) then Drop() end
	end)
end
