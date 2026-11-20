-- Mini QoL packaging adapter; upstream source and credits follow.
MiniQoLRuntime:Execute("Wayfinder", function(...)
-- Polestar's guide on Wayfinder's arrow.
--
-- Polestar, a leveling guide with an arrow of its own, lets another addon
-- follow where its guide is going: Polestar.Nav.API, version 1 minor 1
-- (Target, Follow, Unfollow, Dismiss). With "Show Polestar's guide on this
-- arrow" on, Wayfinder follows it with one waypoint of Polestar's, moved along
-- as the guide moves on: to the end of the leg the route is on (the flight
-- master to walk to, the boat to catch), otherwise to the goal itself. Polestar's
-- own "Let a following addon show the way" then hides its arrow while this
-- one shows the way.
--
-- Polestar says when a goal is done, so its waypoint is never cleared on
-- arrival here. Removing it by hand lets the goal go in Polestar as well, until
-- the guide moves on. It goes quietly, with nothing let go, while Shortest Path
-- Forever has the guiding, while the goal lies where Wayfinder's maps can't
-- place it, and when following is turned off. While Wayfinder's own corpse
-- waypoint shows the way back to the body, the guide's waits where it was.
local _, ns = ...

local PolestarFollow = ns:NewModule("PolestarFollow")

local OWNER = "Wayfinder" -- the follower's name, as Polestar is told it
local SOURCE = "Polestar" -- the waypoint's source in the arrow's list
local NOTE = "From Polestar's guide. Removing it lets this goal go until the guide moves on."
local SWITCH = "turn on \"Let a following addon show the way\" in Polestar's options,"
	.. " under Guide, Arrow & routes, Other waypoints"

local following = false
local goal             -- the goal last shown; a different one takes the arrow
local dropping = false -- the waypoint is being taken away here, not by the player

-- Polestar's follower API, when Polestar is loaded and speaks a version this
-- was written for.
local function API()
	local nav = type(Polestar) == "table" and Polestar.Nav
	local api = type(nav) == "table" and nav.API
	if type(api) ~= "table" or api.version ~= 1 or (tonumber(api.minor) or 0) < 1 then
		return nil
	end
	for _, name in ipairs({ "Target", "Follow", "Unfollow", "Dismiss" }) do
		if type(api[name]) ~= "function" then
			return nil
		end
	end
	return api
end

function PolestarFollow:Available()
	return API() ~= nil
end

function PolestarFollow:IsFollowing()
	return following
end

-- Whether Polestar's own arrow steps aside while this one shows the way: its
-- "Let a following addon show the way". nil when Polestar won't say.
function PolestarFollow:OwnArrowStepsAside()
	local get = type(Polestar) == "table" and Polestar.Get
	if type(get) ~= "function" then
		return nil
	end
	local ok, value = pcall(get, "nav.arrowToFollower")
	if not ok then
		return nil
	end
	return value == true
end

-- One line for the settings page.
function PolestarFollow:Status()
	if not self:Available() then
		return "Polestar isn't loaded."
	end
	if not ns:GetSetting("followPolestar") then
		return "Off: Polestar's guide shows on Polestar's own arrow."
	end
	local aside = self:OwnArrowStepsAside()
	if aside == true then
		return "Polestar's arrow steps aside while this one shows its guide."
	elseif aside == false then
		return "Polestar's own arrow still shows as well. To hide it, " .. SWITCH .. "."
	end
	return "If Polestar's own arrow still shows as well, " .. SWITCH .. "."
end

-- A point Polestar gives (a uiMap and 0-1 coordinates) in Wayfinder's world terms.
local function Place(point)
	if type(point) ~= "table" then
		return nil
	end
	local mapID, x, y = tonumber(point.map), tonumber(point.x), tonumber(point.y)
	if not (mapID and x and y) then
		return nil
	end
	local cont, wx, wy = ns.MapToWorld(mapID, x, y)
	if cont then
		return cont, wx, wy, mapID
	end
end

local function Title(point)
	local title = type(point) == "table" and point.title
	return type(title) == "string" and title ~= "" and title or nil
end

-- Takes Polestar's waypoint away without letting the goal go in Polestar.
function PolestarFollow:Drop()
	goal = nil
	local rec = ns.Navigation:GetSourceWaypoint(SOURCE)
	if not rec then
		return false
	end
	dropping = true
	ns.Navigation:RemoveWaypoint(rec, true)
	dropping = false
	return true
end

-- Brings the waypoint in line with where Polestar's guide is going. Polestar
-- calls this the frame after anything changes; nothing here runs per frame.
function PolestarFollow:Sync()
	if not following then
		return
	end
	local api = API()
	local ok, target = false, nil
	if api then
		ok, target = pcall(api.Target)
	end
	if not ok or type(target) ~= "table" or target.handedOff then
		-- No goal, or Shortest Path Forever is the one guiding to it.
		return self:Drop()
	end
	if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") and ns.Navigation:GetCorpseWaypoint() then
		return
	end
	local title = Title(target)
	local stop = target.next
	local cont, wx, wy, mapID = Place(stop)
	local label = Title(stop)
	if not cont then
		stop, label = nil, title
		cont, wx, wy, mapID = Place(target)
	end
	if not cont then
		-- Somewhere Wayfinder's maps can't place, inside a dungeon say.
		return self:Drop()
	end
	local key = ("%s|%s|%s"):format(title or "", tostring(target.quest or ""), tostring(target.map))
	local fresh = key ~= goal
	goal = key
	ns.Navigation:PlaceSourceWaypoint(SOURCE, cont, wx, wy, label, mapID, {
		focus = fresh, kept = true, note = NOTE, goal = stop and title or nil })
end

-- Follows Polestar while the setting is on and Polestar is there to follow.
function PolestarFollow:Refresh()
	local api = ns:GetSetting("followPolestar") and API()
	if api and not following then
		local ok, accepted = pcall(api.Follow, OWNER, function() self:Sync() end, { shows = true })
		following = ok and accepted == true
	elseif not api and following then
		following = false
		local old = API()
		if old then
			pcall(old.Unfollow, OWNER)
		end
	end
	if following then
		self:Sync()
	else
		-- Also one left in the saved list from a session that followed.
		self:Drop()
	end
end

function PolestarFollow:OnLogin()
	ns:On("SETTING_CHANGED", function(key)
		if key ~= "followPolestar" then
			return
		end
		self:Refresh()
		if following and self:OwnArrowStepsAside() == false then
			ns.Print("Polestar's own arrow still shows as well. To hide it, " .. SWITCH .. ".")
		end
	end)
	ns:On("WAYPOINT_REMOVED", function(rec)
		if dropping or not following or type(rec) ~= "table" or rec.source ~= SOURCE then
			return
		end
		-- The player let it go, so Polestar does too, until its guide moves on.
		goal = nil
		local api = API()
		if api then
			pcall(api.Dismiss, OWNER)
		end
	end)
	-- Out of a dungeon, or anywhere new after a loading screen.
	ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		self:Sync()
	end)
	self:Refresh()
end

end)
