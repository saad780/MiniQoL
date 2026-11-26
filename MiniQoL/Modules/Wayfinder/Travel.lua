-- Mini QoL packaging adapter; upstream source and credits follow.
MiniQoLRuntime:Execute("Wayfinder", function(...)
-- Travel to an ordinary Wayfinder waypoint. The final pin belongs to Navigation.
-- Only the next boarding point is sent to the walking router.
local _, ns = ...
local Travel = ns:NewModule("Travel")
local network = ns.TravelNetwork
local huge = math.huge
local HEARTH_SECONDS = 15 -- casting and loading into the inn
-- A walk the terrain search could not find is priced at this many times its
-- straight line, not ruled out. The search refuses any start it cannot verify
-- (rough ground, with no player height on Forever), which says nothing about
-- the destination. A transport wins only when it is much faster.
local FAILED_WALK = 3
local labels = { boat = "boat", zeppelin = "zeppelin", airship = "airship", tram = "tram", portal = "portal" }
local graph, journey, known, bound, rejected
local revision = 0
local undiscovered, nextHintCheck, nearby = {}, 0, nil
local position = { samples = 0 } -- last valid position observed while guiding

-- These landmasses share Kalimdor's instance but require a crossing. Rut'theran
-- is at sea level below Teldrassil. Its world bounds come from Polestar's crossing data.
local function land(c, x, y, map)
	if c == 1 then
		if x >= 8437.5 and x <= 9065.3 and y >= 352.3 and y <= 1523.3 then return "Rut'theran" end
		if map == 1438 or map == 1457 or (x > 9065 and y > 0) then return "Teldrassil" end
	end
	return c
end

local function point(c, x, y, map, name, z)
	return { c = c, x = x, y = y, m = map, n = name, z = z, land = land(c, x, y, map) }
end

local function endpoint(row)
	local board = row[10]
	if type(board) == "table" then return point(row[2], board.wx, board.wy, row[5], row[1], board.z) end
	return point(row[2], row[3], row[4], row[5], row[1], board)
end

local function available(mask)
	return mask == 3 or mask == ns.playerFaction
end

local function buildGraph()
	local g = { nodes = {}, taxi = {}, inns = {}, incoming = {}, docks = {} }
	local function add(p)
		local i = #g.nodes + 1
		g.nodes[i], g.incoming[i], p.index = p, {}, i
		return p
	end
	local function edge(kind, a, b, seconds, item)
		local list = g.incoming[b.index]
		list[#list + 1] = { kind = kind, from = a, to = b, seconds = seconds, item = item }
	end
	for _, row in ipairs(network.taxi) do
		if available(row[8]) and (not row[10] or row[10] == ns.playerClass) then
			local p = add(point(row[2], row[3], row[4], row[5], row[9], network.taxiZ[row[1]]))
			p.taxi, p.class = row[1], row[10]
			g.taxi[p.taxi] = p
		end
	end
	local flights = network.flights
	for i = 1, #flights, 3 do
		local a, b = g.taxi[flights[i]], g.taxi[flights[i + 1]]
		if a and b then edge("fly", a, b, 4 + flights[i + 2] / 30) end
	end
	for _, r in ipairs(network.transports) do
		if available(r.faction) then
			local a, b = add(endpoint(r.a)), add(endpoint(r.b))
			g.docks[#g.docks + 1] = a
			g.docks[#g.docks + 1] = b
			edge(r.kind, a, b, r.waitA + r.ab)
			edge(r.kind, b, a, r.waitB + r.ba)
		end
	end
	for _, r in ipairs(network.portals) do
		-- Map-click waypoints have no floor. Two ends stacked in the same
		-- tower cannot be distinguished by XY, so do not offer that shortcut.
		if r.id ~= "portal-sanctum-chamber" and r.id ~= "portal-sanctum-tower" then
			edge("portal", add(endpoint(r.a)), add(endpoint(r.b)), r.seconds, r.item)
		end
	end
	for _, inn in ipairs(network.inns) do
		local p = point(inn.c, inn.wx, inn.wy, inn.map, inn.names[1])
		for _, name in ipairs(inn.names) do g.inns[name] = p end
		local localized = C_Map.GetAreaInfo and C_Map.GetAreaInfo(inn.area)
		if localized and localized ~= "" then g.inns[localized] = p end
	end
	return g
end

local function hasItem(id)
	local count = (C_Item and C_Item.GetItemCount) or GetItemCount
	local n = count and count(id)
	return ns.Readable(n) and type(n) == "number" and n > 0
end

local function readyInn(g)
	if not ns:GetSetting("travelHearth") or not GetBindLocation or not hasItem(6948) then return end
	local location = GetBindLocation()
	local inn = bound and bound.n == location and bound or g.inns[location]
	if not inn then return end
	local cooldown = (C_Container and C_Container.GetItemCooldown) or (C_Item and C_Item.GetItemCooldown) or GetItemCooldown
	if not cooldown then return end
	local start, duration, enabled = cooldown(6948)
	if ns.Readable(start) and ns.Readable(duration) and type(start) == "number" and type(duration) == "number"
		and (enabled == nil or (ns.Readable(enabled) and enabled ~= 0 and enabled ~= false))
		and (duration <= 1.5 or start + duration <= GetTime()) then return inn end
end

local function walkTime(a, b, rate)
	if a.land == b.land then return ns.Distance(a.x, a.y, b.x, b.y) * rate end
	return huge
end

-- One reverse shortest-path search prices both starts (here and the bound inn).
-- Each expansion yields to the same frame budget as the background taxi scan.
local function plan(g, start, goal, inn, opts, pause)
	local nodes, dist, first, settled = g.nodes, {}, {}, {}
	local rate = 1.25 / opts.speed
	local function from(p, skip)
		local cost, action = walkTime(p, goal, rate), nil
		if skip and skip.direct then cost = cost * FAILED_WALK end
		for i, n in ipairs(nodes) do
			if first[i] and first[i].from == n then
				local walk = walkTime(p, n, rate)
				if skip and skip[n] then walk = walk * FAILED_WALK end
				local t = walk + dist[i]
				if t < cost then cost, action = t, first[i] end
			end
		end
		return cost, action
	end
	for i, n in ipairs(nodes) do dist[i] = walkTime(n, goal, rate) end
	while true do
		local u, best = nil, huge
		for i, cost in ipairs(dist) do
			if not settled[i] and cost < best then u, best = i, cost end
		end
		if not u then break end
		settled[u] = true
		local n = nodes[u]
		for _, e in ipairs(g.incoming[u]) do
			local flying = e.kind == "fly"
			local usable = flying and opts.flights and (opts.known[n.taxi] or n.class)
				or (not flying and opts.transports and (not e.item or opts.items[e.item]))
			if usable then
				local i = e.from.index
				local cost = best + e.seconds
				if flying and not opts.known[e.from.taxi] and not e.from.class then cost = cost + 8 end
				if cost < dist[i] then dist[i], first[i] = cost, e end
			end
		end
		if first[u] then
			for i, other in ipairs(nodes) do
				if not settled[i] then
					local cost = best + walkTime(n, other, rate)
					if cost < dist[i] then dist[i], first[i] = cost, first[u] end
				end
			end
		end
		if not pause() then return end
	end
	local best, action = from(start, opts.skip)
	if inn then
		local via = HEARTH_SECONDS + from(inn)
		if via < best then return { kind = "hearth", to = inn } end
	end
	if action and action.kind == "fly" then
		-- The taxi map accepts the final known stop of a connected flight.
		local dest = action.to
		while first[dest.index] and first[dest.index].kind == "fly" and first[dest.index].from == dest do
			dest = first[dest.index].to
		end
		return { kind = "fly", from = action.from, to = dest }
	end
	return action, best == huge
end

local function settings()
	local speed
	if GetUnitSpeed then speed = select(2, GetUnitSpeed("player")) end
	return { flights = ns:GetSetting("travelFlights"), transports = ns:GetSetting("travelTransports"),
		known = known or {}, speed = ns.Readable(speed) and type(speed) == "number" and math.max(7, math.min(14, speed)) or 7,
		items = { [9173] = hasItem(9173) } }
end

-- The active selectable flight, including the final stop of a multi-hop taxi.
-- Opening the taxi map may precede completion of the background route search.
function Travel:GetRecommendedFlight()
	local j = journey
	if not j or j.pending or not ns:GetSetting("travelFlights") or j.target ~= ns.Navigation:GetWaypoint() then return end
	local action = j.action
	if action and action.kind == "fly" then return action.from, action.to end
end

function Travel:Reset()
	journey, rejected = nil, nil
end

-- A failed terrain search makes this approach dearer from here (FAILED_WALK).
-- Keep those marks only near this origin and only for this destination.
-- A leg already marked is already priced in, so it is not planned again.
function Travel:WalkFailed(stop)
	local j = journey
	if not j or j.pending or j.unreachable then return end
	local expected = j.action and j.action.from or j.target
	if stop ~= expected then return end
	local c, x, y, map = ns.GetPlayerWorld()
	if not c then return end
	local leg = stop == j.target and "direct" or stop
	if rejected and rejected[leg] then return end
	rejected = rejected or { target = j.target, start = point(c, x, y, map) }
	rejected[leg] = true
	journey = nil
end

function Travel:ObserveTaxi(id, missing)
	if missing then
		if not (known and known[id]) then undiscovered[id] = true end
		return
	end
	self:RememberTaxi(id)
end

function Travel:RememberTaxi(id)
	undiscovered[id] = nil
	if known and not known[id] then
		known[id] = true
		revision = revision + 1
	end
end

local function near(p, c, x, y, radius)
	return p.c == c and ns.Distance(p.x, p.y, x, y) <= radius
end

-- A flight point the client explicitly marks undiscovered is worth mentioning
-- when the player passes its master. This hint does not change the walking aim.
local function flightHint(c, x, y, now)
	if not graph or not ns:GetSetting("travelFlights") then return end
	if now >= nextHintCheck then
		nextHintCheck, nearby = now + 1, nil
		for id in pairs(undiscovered) do
			local p = graph.taxi[id]
			if p and not p.class and near(p, c, x, y, 18) then
				nearby = p
				break
			end
		end
	end
	if nearby and undiscovered[nearby.taxi] and near(nearby, c, x, y, 18) then
		return "Learn the flight point at " .. nearby.n
	end
end

local function begin(target, c, x, y, map)
	if ns.Background:Has("waypoint travel") or InCombatLockdown() then return end
	local j = { target = target, start = point(c, x, y, map), at = GetTime(), revision = revision, pending = true }
	journey = j
	ns.Background:Queue("waypoint travel", function()
		if journey ~= j then return end
		graph = graph or buildGraph()
		local goal = point(target.c, target.x, target.y, target.m)
		j.inn = readyInn(graph)
		local opts = settings()
		if rejected and (rejected.target ~= target or not near(rejected.start, c, x, y, 150)) then rejected = nil end
		opts.skip = rejected
		j.action, j.unreachable = plan(graph, j.start, goal, j.inn, opts, function()
			coroutine.yield()
			return journey == j
		end)
		local a = j.action
		if a then
			if a.kind == "fly" then
				j.caption = "Flight master at " .. a.from.n
				j.instruction = "Fly to " .. a.to.n
				j.learn = "Learn the flight point if needed, then fly to " .. a.to.n
				j.riding = "Flying to " .. a.to.n
			elseif a.kind == "hearth" then
				j.instruction = "Use Hearthstone to " .. a.to.n
			else
				j.caption = a.from.n .. " – " .. labels[a.kind] .. " to " .. a.to.n
				j.instruction = "Take the " .. labels[a.kind] .. " to " .. a.to.n
			end
		end
		j.pending = false
	end)
end

-- Ships and zeppelins have no taxi flag. While standing on a moving deck,
-- world coordinates advance even though the player's own speed is zero.
-- Two successive samples exclude one-off coordinate corrections or knockbacks.
local function carriedBetweenSamples(distance2)
	if distance2 < 4 or not GetUnitSpeed then return false end
	local speed = GetUnitSpeed("player")
	if not ns.Readable(speed) or speed ~= 0 then return false end
	local falling = IsFalling and IsFalling()
	return not (ns.Readable(falling) and falling)
end

-- Recognize the actual port even if the player ran around on a ship's deck
-- or the client never supplied usable speed. Separate enter/leave radii keep
-- waves or a few steps near the dock from repeatedly triggering the search.
local function observedDock(c, x, y, previous)
	if previous and near(previous, c, x, y, 100) then return previous end
	for _, dock in ipairs(graph.docks) do
		if near(dock, c, x, y, 55) then return dock end
	end
	return false
end

local function locationChanged(c, x, y, map, taxi, now)
	local p = position
	if not c or taxi then
		p.gap = p.c ~= nil
		if taxi then p.carried, p.samples = false, 0 end
		return false
	end
	local dx, dy = x - (p.x or x), y - (p.y or y)
	local distance2 = dx*dx + dy*dy
	local elapsed = now - (p.at or now)
	-- A short portal hop can stay on the same map. Allow for normal motion
	-- between samples, including frames delayed by the client.
	local jumpYards = math.max(40, math.min(100, elapsed * 40))
	local jump = distance2 > jumpYards*jumpYards
	local transition = p.gap or (p.c and (p.c ~= c or p.map ~= map or jump))
	local zoneEvent = p.zoneAt and now >= p.zoneAt
	if p.at and elapsed < 0.5 and not transition and not zoneEvent then return false end

	local wasCarried = p.carried
	if p.gap or p.c ~= c or jump then
		p.samples = 0 -- resume observing the ride on the far side of a loading screen
	elseif elapsed >= 0.5 then
		if carriedBetweenSamples(distance2) then
			p.samples = p.samples + 1
			p.carried = wasCarried or p.samples >= 2
		else
			p.samples, p.carried = 0, false
		end
	end
	local dockChanged
	if graph and (p.dock == nil or distance2 > 0 or p.c ~= c) then
		local dock = observedDock(c, x, y, p.dock)
		-- Also reconsider if the player walked away after being told to board.
		dockChanged = p.dock ~= nil and dock ~= p.dock and (dock or (journey and journey.boarded))
		p.dock = dock
	end
	local changed = p.c and (transition or zoneEvent or dockChanged or (wasCarried and not p.carried))
	p.c, p.x, p.y, p.map, p.at, p.gap = c, x, y, map, now, nil
	if transition or zoneEvent then p.zoneAt = nil end
	return changed
end

-- Returns the walking stop, action text, approach caption, and whether the
-- player is boarding or riding. A fresh search from the landing handles missed stops.
function Travel:Aim(target, c, x, y, map)
	local now = GetTime()
	local taxi = ns.Walking.Compat.IsOnTaxi()
	local relocated = locationChanged(c, x, y, map, taxi, now)
	if relocated and not position.carried then
		self:Reset()
		ns:Fire("TRAVEL_ORIGIN_CHANGED")
	end
	local dead = UnitIsDeadOrGhost("player")
	if target.source == "Polestar" or target.source == "corpse" or (ns.Readable(dead) and dead)
		or (not ns:GetSetting("travelFlights") and not ns:GetSetting("travelHearth") and not ns:GetSetting("travelTransports")) then
		journey = nil
		return
	end
	local j = journey
	if j and j.target ~= target then
		self:Reset()
		j = nil
	end
	local a = j and j.action
	if taxi then return nil, j and j.riding or "In flight", nil, true end
	if position.carried then
		local namedRide = a and j.boarded and labels[a.kind] and a.kind ~= "portal"
		return nil, namedRide and j.instruction or "Riding transport", nil, true
	end
	if not c then return nil, j and j.boarded and j.instruction or nil end
	if near(target, c, x, y, 10) and land(c, x, y, map) == land(target.c, target.x, target.y, target.m) then
		self:Reset()
		return
	end
	local arrived = a and near(a.to, c, x, y, a.kind == "portal" and 36 or 85)
	if arrived and a.kind == "hearth" then
		-- Starting near the inn does not mean the suggested cast already landed.
		arrived = not near(a.to, j.start.c, j.start.x, j.start.y, 85)
	end
	if arrived then
		self:Reset()
		j, a = nil, nil
	elseif j and not j.pending then
		-- Commit to a ride through the loading screen. Walking away from the
		-- departure on foot can also be a missed boat. Reprice after a grace period.
		if j.boarded and ((a.kind == "fly" and not near(a.from, c, x, y, 35))
			or now - j.boarded > (a.seconds or 0) + 90) then j.boarded = nil end
		local committed = j.boarded
		local check = now >= (j.checkAt or 0)
		local detour = false
		if check and not committed and now - j.at > 30 then
			local dest = a and a.from or target
			if not near(j.start, c, x, y, 600) then
				detour = true
			elseif dest.c == c then
				local via = ns.Distance(j.start.x, j.start.y, x, y) + ns.Distance(x, y, dest.x, dest.y)
				detour = via > ns.Distance(j.start.x, j.start.y, dest.x, dest.y) * 1.3 + 300
			end
		end
		local leftBlockedArea = check and rejected and not near(rejected.start, c, x, y, 150)
		-- A taxi is committed only after takeoff (handled above). While the
		-- player stands at its master, a newly ready hearth can still win.
		local canHearth = not committed or a.kind == "fly"
		local hearthChanged = check and canHearth and readyInn(graph) ~= j.inn
		if hearthChanged or (not committed and (j.revision ~= revision or detour or leftBlockedArea)) then
			self:Reset()
			j, a = nil, nil
		elseif check then
			j.checkAt = now + 3
		end
	end
	if not j then
		-- Even on foot, the estimated walk over 80 yards takes less than a hearth cast and load.
		if near(target, c, x, y, 80) and land(c, x, y, map) == land(target.c, target.x, target.y, target.m) then return end
		begin(target, c, x, y, map)
		j = journey
	end
	if not j then
		if ns.Background:Has("waypoint travel") then return nil, "Planning travel…" end
		return
	end
	if j.pending then return nil, "Planning travel…" end
	if j.unreachable then return nil, "No known route" end
	if not a then return nil, nil, flightHint(c, x, y, now) end
	if a.kind == "hearth" then return nil, j.instruction end
	local dep = a.from
	local flight = a.kind == "fly"
	local close = near(dep, c, x, y, flight and 12 or 20)
	if close and dep.z then
		local _, _, z, instance = ns.Walking.Compat.GetPlayerUnitPosition()
		if instance == c and z and math.abs(z - dep.z) > 10 then close = false end
	end
	if close then j.boarded = now end
	if j.boarded then
		local learn = flight and not known[dep.taxi] and not dep.class
		return nil, learn and j.learn or j.instruction, nil, true
	end
	if c ~= dep.c then self:Reset(); return nil, "Planning travel…" end
	return dep, nil, j.caption
end

function Travel:OnLogin()
	local function zoneChanged()
		-- Several events can describe one arrival. Read the coordinates on
		-- the arrow's next settled update, after the game switches maps.
		if position.c then position.zoneAt = GetTime() + 0.35 end
	end
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }) do
		ns:RegisterEvent(event, zoneChanged)
	end
	ns.db.knownFlights = ns.db.knownFlights or {}
	local key = ns:GetCharacterKey()
	ns.db.knownFlights[key] = ns.db.knownFlights[key] or {}
	known = ns.db.knownFlights[key]
	ns.db.hearthBinds = ns.db.hearthBinds or {}
	bound = ns.db.hearthBinds[key]
	ns:RegisterEvent("HEARTHSTONE_BOUND", function()
		local name = GetBindLocation and GetBindLocation()
		local c, x, y, map = ns.GetPlayerWorld()
		bound = c and name and point(c, x, y, map, name) or nil
		ns.db.hearthBinds[key] = bound
		self:Reset()
	end)
	-- Polestar may already have this character's discoveries before the
	-- first taxi map opens. Its read-only API is an optional warm start.
	local nav = type(Polestar) == "table" and Polestar.Nav
	if nav and type(nav.GetKnownTaxiNodes) == "function" then
		local ok, ids = pcall(nav.GetKnownTaxiNodes)
		if ok and type(ids) == "table" then
			for id, learned in pairs(ids) do
				if type(id) == "number" and learned == true then self:RememberTaxi(id) end
			end
		end
	end
	ns:RegisterEvent("TAXIMAP_OPENED", function()
		local id = GetTaxiMapID and GetTaxiMapID()
		if not (id and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then return end
		local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, id)
		if ok and type(nodes) == "table" then
			for _, node in ipairs(nodes) do
				if ns.Readable(node.nodeID) and type(node.nodeID) == "number" and ns.Readable(node.state)
					and (node.state == 0 or node.state == 1) then self:RememberTaxi(node.nodeID) end
			end
		end
	end)
	ns:On("SETTING_CHANGED", function(key)
		if key == "travelHearth" or key == "travelFlights" or key == "travelTransports" then self:Reset() end
	end)
end

end)
