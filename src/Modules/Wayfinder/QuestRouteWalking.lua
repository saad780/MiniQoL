-- Price a leg in world yards, then replace the estimate with the router's measurement.
local _, ns = ...
local Walk = {}
ns.QuestRouteWalking = Walk
local floor, min, max = math.floor, math.min, math.max

local function length(a, b)
    return ns.Distance(a.x, a.y, b.x, b.y)
end

-- A visibility graph uses the corners of octagons circumscribed around the
-- town circles. Every edge is tested against every town, including towns
-- beside a detour. Overlapping circles share the same graph.
local empty = {}
local function noop() end
local function squared(a, b)
    return (a.x - b.x)^2 + (a.y - b.y)^2
end

local function clear(a, b, towns, source, destination)
    local dx, dy = b.x - a.x, b.y - a.y
    local span = dx*dx + dy*dy
    for _, c in ipairs(towns) do
        local r2 = c.radius*c.radius
        if not (source and squared(source,c) < r2 or destination and squared(destination,c) < r2) then
            local t = span > 0 and ((c.x-a.x)*dx + (c.y-a.y)*dy) / span or 0
            t = max(0, min(1, t))
            if (a.x - c.x + t*dx)^2 + (a.y - c.y + t*dy)^2 < r2 then return false end
        end
    end
    return true
end

local function geometry(towns, tick)
    local points, edges = {}, {}
    for _, c in ipairs(towns) do
        local radius = c.radius / math.cos(math.pi/8) + 2
        for i = 1, 8 do
            local angle = i * math.pi / 4
            local p = { x = c.x + radius*math.cos(angle), y = c.y + radius*math.sin(angle) }
            if clear(p, p, towns) then points[#points+1] = p end
        end
        tick()
    end
    for i = 1, #points do edges[i] = {} end
    for i, p in ipairs(points) do
        for j = 1, i-1 do
            if clear(p, points[j], towns) then
                local d = length(p, points[j])
                edges[i][#edges[i]+1] = {j, d}
                edges[j][#edges[j]+1] = {i, d}
            end
            if j % 12 == 0 then tick() end
        end
    end
    -- Entries are keyed by candidate identity. Replacing quest data releases
    -- its trees and visibility lists without invalidating the town geometry.
    return {towns=towns, points=points, edges=edges, access=setmetatable({}, {__mode="k"}),
        trees=setmetatable({}, {__mode="k"})}
end

local function sameTowns(a, b)
    if a == b then return true end
    if not a or #a ~= #b then return false end
    for i, c in ipairs(a) do
        local other = b[i]
        if other.x ~= c.x or other.y ~= c.y or other.radius ~= c.radius then return false end
    end
    return true
end

function Walk:SetTowns(towns, tick)
    towns = towns or empty
    if self.obstacles and sameTowns(self.obstacles.towns, towns) then
        self.towns = self.obstacles.towns
        return
    end
    local index = geometry(towns, tick or noop)
    self.towns, self.obstacles = towns, index
    self.epoch = (self.epoch or 0) + 1
    -- A newly discovered enemy service can invalidate a previously safe leg.
    local job = self.job
    self.busy, self.job = false, nil
    if job and self.engine then self.engine.Cancel(job) end
    self.legs, self.keys, self.cursor, self.samples, self.ratio = {}, {}, 1, 0, 1
end

local function obstacles(self)
    if not self.obstacles or self.obstacles.towns ~= (self.towns or empty) then self:SetTowns(self.towns) end
    return self.obstacles
end

local function access(index, p, tick)
    local visible = index.access[p]
    if visible then return visible end
    visible = {}
    for i, corner in ipairs(index.points) do
        if clear(p, corner, index.towns, p) then visible[#visible+1] = {i, length(p, corner)} end
        if i % 16 == 0 then tick() end
    end
    index.access[p] = visible
    return visible
end

-- One shortest-path tree per source candidate serves all of its obstructed
-- outgoing legs. Direct, unobstructed legs never need this search.
local function treeFrom(index, source, tick)
    if index.trees[source] then return index.trees[source] end
    local distance, prev, done = {}, {}, {}
    for _, portal in ipairs(access(index, source, tick)) do distance[portal[1]] = portal[2] end
    while true do
        local nextVertex, best
        for i = 1, #index.points do
            local d = distance[i]
            if d and not done[i] and (not best or d < best) then nextVertex, best = i, d end
        end
        if not nextVertex then break end
        done[nextVertex] = true
        for _, edge in ipairs(index.edges[nextVertex]) do
            local v, d = edge[1], best + edge[2]
            if not distance[v] or d < distance[v] then distance[v], prev[v] = d, nextVertex end
        end
        tick()
    end
    local tree = {distance=distance, prev=prev}
    index.trees[source] = tree
    return tree
end

local function bypass(self, a, b, needPath)
    local index = obstacles(self)
    if #index.towns == 0 or clear(a, b, index.towns, a, b) then
        return length(a, b), needPath and {a, b}
    end
    local tick = self.tick or noop
    local tree = treeFrom(index, a, tick)
    local cost, last
    for _, endpoint in ipairs(access(index, b, tick)) do
        local d = tree.distance[endpoint[1]]
        if d then
            d = d + endpoint[2]
            if not cost or d < cost then cost, last = d, endpoint[1] end
        end
    end
    if not cost then return 3 * length(a,b), needPath and {} end
    if not needPath then return cost end
    local reverse, points = {}, {a}
    while last do
        reverse[#reverse+1] = index.points[last]
        last = tree.prev[last]
    end
    for i = #reverse,1,-1 do points[#points+1] = reverse[i] end
    points[#points+1] = b
    return cost, points
end

function Walk.Options(mapID, ghost)
    local routing = ns.Walking
    local danger = routing and routing.Nav.danger
    local avoid = ns:GetSetting("questRouteAvoidTowns")
    local profile = avoid and routing and routing.Compat.GetPlayerFaction() or nil
    local level = danger and danger.Level and danger.Level()
    return {
        profile = profile, style = ns:GetSetting("questRouteRoads") and "roads" or ns.Navigation:GetRouteStyle(),
        waterWalking = ghost or not ns:GetSetting("questRouteDry"),
        walkLevel = profile and danger and danger.Blocked and (level or 0) or nil,
        danger = level and danger.Table and danger.Table(level, mapID, mapID) or nil,
    }
end

function Walk.New(cont, mapID)
    return setmetatable({ cont = cont, mapID = mapID, legs = {}, keys = {}, cursor = 1, ratio = 1,
        samples = 0, revision = 0 }, { __index = Walk })
end

local function cell(p)
    return floor(p.x / 12) .. "," .. floor(p.y / 12)
end

-- Directed pairs: stairs and ledges can have different costs on the way back.
local function key(a, b)
    return cell(a) .. ">" .. cell(b)
end

local function cached(self, a, b)
    local index = obstacles(self)
    local k = key(a,b)
    local leg = self.legs[k]
    if leg and #index.towns > 0 and (not clear(a,leg.from,index.towns,a) or not clear(leg.to,b,index.towns,b)) then
        -- The same grid cell can straddle a town boundary. Measure this pair
        -- separately if joining the old endpoints would cut through the town.
        k = ("%s:%.2f,%.2f>%.2f,%.2f"):format(k,a.x,a.y,b.x,b.y)
        leg = self.legs[k]
    end
    return leg, k
end

function Walk:Estimate(a, b)
    local leg = cached(self, a, b)
    if leg then return leg.cost + length(a, leg.from) + length(b, leg.to) end
    local cost = bypass(self, a, b, false)
    return cost * self.ratio
end

-- A path may arrive while the optimizer yields. One solve must compare all
-- alternatives against the same measured legs and the same detour estimate.
function Walk:Snapshot(tick)
    local index, legs = obstacles(self), {}
    for k, leg in pairs(self.legs) do legs[k] = leg end
    return setmetatable({ legs = legs, obstacles = index, towns = index.towns, ratio = self.ratio, tick = tick }, { __index = Walk })
end

function Walk:MeasuredPath(a, b)
    local leg = cached(self, a, b)
    if not leg or not leg.points then return end
    local fromChanged, toChanged = squared(a,leg.from) > 0, squared(b,leg.to) > 0
    if not fromChanged and not toChanged then return leg.points end
    local path = {absoluteDry = leg.points.absoluteDry}
    if fromChanged then path[1] = a end
    for _, p in ipairs(leg.points) do path[#path+1] = p end
    if toChanged then path[#path+1] = b end
    return path
end

function Walk:Line(a, b)
    local measured = self:MeasuredPath(a, b)
    if measured then return measured end
    local _, points = bypass(self, a, b, true)
    return points
end

function Walk:Cancel()
    self.cancelled = true
    if self.job and self.engine then self.engine.Cancel(self.job) end
    self.job, self.busy = nil, false
end

-- Only one speculative path competes with the live arrow at a time.
-- The callback can run synchronously, including when there is no terrain.
function Walk:Measure(a, b, notify)
    local known, k = cached(self, a, b)
    local engine = ns.Walking and ns.Walking.Nav.Path
    if not engine or known or self.busy or self.cancelled then return false end
    self.engine, self.busy = engine, true
    local estimated, fallback = bypass(self, a, b, true)
    -- A candidate may own thousands of spawns. The measured cache needs its
    -- position only, even after the player switches quests or levels up.
    a, b = {x=a.x, y=a.y, z=a.z}, {x=b.x, y=b.y, z=b.z}
    local path, cost, index, epoch = {a}, 0, 1, self.epoch
    local function cancelled() return self.cancelled or self.epoch ~= epoch end
    local function finish(ok)
        if cancelled() then return end
        self.busy, self.job = false, nil
        local old = self.keys[self.cursor]
        if old then self.legs[old] = nil end
        self.keys[self.cursor] = k
        self.cursor = self.cursor % 384 + 1
        self.legs[k] = { from = a, to = b, cost = ok and cost or 3 * estimated, points = ok and path or nil }
        if ok and estimated > 5 then
            self.samples = min(32, self.samples + 1)
            self.ratio = self.ratio + (max(1, min(4, cost / estimated)) - self.ratio) / self.samples
        end
        self.revision = self.revision + 1
        notify()
    end
    if #fallback < 2 then
        estimated = length(a,b)
        finish(false)
        return true
    end
    fallback[1], fallback[#fallback] = a, b
    local rawGhost = UnitIsGhost and UnitIsGhost("player")
    local options = Walk.Options(self.mapID, ns.Readable(rawGhost) and rawGhost == true)
    local function nextPart()
        if cancelled() then return end
        local start, goal = fallback[index], fallback[index + 1]
        if not goal then finish(true); return end
        -- Avoid creating a search for two markers at the same point.
        if length(start, goal) < 1 then
            path[#path + 1] = goal
            cost = cost + length(start, goal)
            index = index + 1
            nextPart()
            return
        end
        local answered = false
        local function result(points, _, job)
            if answered or cancelled() then return end
            answered, self.job = true, nil
            if not points or #points == 0 or (job and job.reached) then finish(false); return end
            for _, p in ipairs(points) do
                if not clear(path[#path], p, self.towns, a, b) then finish(false); return end
                cost = cost + length(path[#path], p)
                path[#path + 1] = p
            end
            if not clear(path[#path], goal, self.towns, a, b) then finish(false); return end
            cost = cost + length(path[#path], goal)
            path[#path + 1] = goal
            index = index + 1
            if index == #fallback then finish(true) else C_Timer.After(0, nextPart) end
        end
        local ok, handle = pcall(engine.Find, self.cont, start, goal, result, options)
        if not answered then
            if ok and handle then self.job = handle else result(nil) end
        end
    end
    nextPart()
    return true
end
