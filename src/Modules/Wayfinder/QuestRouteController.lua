-- Current-zone route lifecycle. Questie is read by the data adapter; the only
-- tracking we change is our own source waypoint. Private jobs can be replaced
-- between yields without cancelling anything else on Wayfinder's work queue.
local _, ns = ...
local Route = ns:NewModule("QuestRoute")
local SOURCE, MOVE_YARDS = "route", 118
local jobs, transient = {}, { skips = {} }
local function setting(key) return ns:GetSetting("questRoute" .. key) end
local function enabled() return ns.db and ns:GetSetting("questRoute") end
local function prefs()
    local key = ns:GetCharacterKey()
    if not key or key == "unknown" then return transient end
    local all = ns.db.questRoutes
    all[key] = all[key] or { skips = {} }
    return all[key]
end

local function queue(slot, fn)
    jobs[slot] = coroutine.create(function()
        local start = debugprofilestop()
        local function tick()
            if debugprofilestop() - start >= 1.4 then
                coroutine.yield()
                start = debugprofilestop()
            end
        end
        fn(tick)
    end)
    ns.Background:Queue("zone quest route " .. slot, function()
        while jobs[slot] do
            local co = jobs[slot]
            local ok, errorText = coroutine.resume(co)
            if jobs[slot] == co and (not ok or coroutine.status(co) == "dead") then jobs[slot] = nil end
            if not ok then
                Route.status = "The quest route could not be calculated."
                error(errorText)
            end
            if jobs[slot] then coroutine.yield("frame") end
        end
    end)
end

local function player()
    local cont, x, y, mapID = ns.GetPlayerWorld()
    if not (ns.Readable(cont) and ns.Readable(x) and ns.Readable(y) and ns.Readable(mapID)) then return end
    -- A micro map/floor shares the zone's route and the player's world position.
    for _ = 1, 10 do
        local info = C_Map.GetMapInfo(mapID)
        if not info or info.mapType ~= Enum.UIMapType.Micro or not info.parentMapID then break end
        mapID = info.parentMapID
    end
    return { x = x, y = y, cont = cont, mapID = mapID }
end

local function removeArrow()
    if InCombatLockdown() then Route.syncAfterCombat = true; return end
    local nav = ns.Navigation
    local rec = nav:GetSourceWaypoint(SOURCE)
    if rec then
        Route.removing = true
        nav:RemoveWaypoint(rec, true)
        Route.removing = nil
    end
end

local function arrow(focus)
    if InCombatLockdown() then
        Route.syncAfterCombat, Route.focusAfterCombat = true, Route.focusAfterCombat or focus
        return
    end
    local v = Route.view
    local target = v and ((Route.followed and v.byKey[Route.followed]) or v.stops[1])
    if not (target and (setting("Arrow") or Route.followed) and Route.dismissed ~= target.task.key) then
        removeArrow()
        return
    end
    local t, p = target.task, target.point
    local active = ns.Navigation:GetWaypoint()
    local label = t.kind == "objective" and t.label ~= t.quest and (t.quest .. " · " .. t.label) or t.label
    local rec = ns.Navigation:PlaceSourceWaypoint(SOURCE, v.cont, p.x, p.y, label, v.mapID,
        { kept = true, focus = focus and not (active and active.source == "corpse"), note = "Location Prep quest route" })
    rec.routeKey, rec.questID = t.key, t.questID
    rec.area = setting("Outline") and p.area or nil
end

function Route:GetView() return self.view end
function Route:MeasuredPath(rec, x, y)
    if self.walk and self.view and rec.c == self.view.cont then
        return self.walk:MeasuredPath({ x = x, y = y }, rec)
    end
end
function Route:Destination() return enabled() and prefs().destination or nil end
function Route:Enabled() return enabled() end
function Route:Status()
    if not enabled() then return "Quest route is off." end
    return self.status or "Finding the quests on your route…"
end
local function announce()
    ns:Fire("QUEST_ROUTE_CHANGED")
end
local function clear(status)
    jobs.collect, jobs.solve = nil, nil
    Route.collectAgain = nil
    if Route.walk then Route.walk:Cancel() end
    Route.view, Route.data, Route.origin, Route.walk = nil, nil, nil, nil
    Route.footprint, Route.signature, Route.context = nil, nil, nil
    Route.lastLearned, Route.rounds, Route.solving = 0, 0, false
    Route.followed, Route.forced, Route.dismissed = nil, nil, nil
    local changed = Route.status ~= status
    Route.status = status
    removeArrow()
    if changed then announce() end
end

local function refreshPaths()
    local v, walk = Route.view, Route.walk
    if not (v and walk) then return end
    local previous = v.origin
    local paths = {}
    for i, stop in ipairs(v.stops) do
        paths[i] = walk:Line(previous, stop.point)
        previous = stop.point
    end
    v.paths = paths
end

local function measure()
    local v, walk = Route.view, Route.walk
    if not (v and walk and setting("Walk")) or walk.busy or InCombatLockdown() then return end
    local previous = v.origin
    for _, stop in ipairs(v.stops) do
        if walk:Measure(previous, stop.point, function()
            -- The engine may call back immediately. Yield to the game between legs.
            C_Timer.After(0, function()
                if Route.walk ~= walk then return end
                refreshPaths()
                ns:Fire("QUEST_ROUTE_PATHS_CHANGED")
                measure()
            end)
        end) then return end
        previous = stop.point
    end
    if not Route.solving and walk.revision > Route.lastLearned and Route.rounds < 3 then
        Route.lastLearned, Route.rounds = walk.revision, Route.rounds + 1
        Route:Solve(false)
    end
end

function Route:Solve(progressOnly)
    local data, origin, walk = self.data, self.origin, self.walk
    if not data then return end
    local old = self.view
    local previous = {}
    for _, stop in ipairs(old and old.stops or {}) do previous[#previous + 1] = stop.task.key end
    local skipped = prefs().skips
    local forced = self.forced
    self.solving = true
    queue("solve", function(tick)
        local metric = walk:Snapshot(tick)
        local function publish(plan)
            local v = { stops = plan.stops, byKey = {}, skipped = {}, origin = origin, cont = origin.cont,
                mapID = origin.mapID, forced = forced, why = {}, levels = data.levels }
            for _, stop in ipairs(v.stops) do v.byKey[stop.task.key] = stop end
            for _, t in ipairs(data.tasks) do
                if skipped[t.key] and t.candidates[1] then
                    local pt = t.candidates[1]
                    for _, p in ipairs(t.candidates) do
                        if ns.Distance(p.x,p.y,origin.x,origin.y) < ns.Distance(pt.x,pt.y,origin.x,origin.y) then pt = p end
                    end
                    local stop = { task = t, point = pt }
                    v.skipped[#v.skipped + 1] = stop
                    v.byKey[t.key] = stop
                end
            end
            for _, reasons in ipairs({data.why or {}, plan.why or {}}) do
                for _, why in ipairs(reasons) do v.why[#v.why + 1] = why end
            end
            self.view = v
            self.status = ("%d route stops in %s."):format(#v.stops, (C_Map.GetMapInfo(v.mapID) or {}).name or "this zone")
            if v.levels then self.status = self.status .. " Usual quest levels " .. v.levels .. "." end
            self.plannerWhy = plan.why
            if self.followed and not v.byKey[self.followed] then self.followed = nil end
            if self.forced and not v.byKey[self.forced] then self.forced = nil; v.forced = nil end
            refreshPaths()
            arrow(self.takeFocus)
            self.takeFocus = nil
            announce()
        end
        local options = { previous = previous, forced = forced, skips = skipped, slots = data.slots,
            worth = setting("Worth"), progressOnly = progressOnly and #previous > 0,
            previousWhy = self.plannerWhy, tick = tick, distance = function(a,b) return metric:Estimate(a,b) end,
            publish = function(plan) publish(plan); measure() end }
        local plan = ns.RoutePlanner.Plan(data.tasks, origin, options)
        publish(plan)
        self.solving = false
        measure()
    end)
end

-- Differentiate an ordinary kill from a changed task set. A repeated
-- QUEST_LOG_UPDATE with identical evidence must not restart the optimizer.
local function signatures(data, tick)
    local structure, progress = {}, {}
    for _, t in ipairs(data.tasks) do
        local camps = {}
        for i, p in ipairs(t.candidates) do
            camps[i] = ("%.1f/%.1f/%.1f"):format(p.x, p.y, p.penalty or 0)
        end
        table.sort(camps)
        structure[#structure+1] = table.concat({t.key, t.optional and "?" or "+", table.concat(t.after or {}, ",")}, ":")
        progress[#progress+1] = table.concat({t.key, t.label, t.progress or "", table.concat(camps, ";")}, ":")
        tick()
    end
    table.sort(structure)
    table.sort(progress)
    return table.concat(structure, "|"), table.concat(progress, "|") .. "|" .. table.concat(data.why or {}, "|")
end

local function collect(force)
    if not enabled() then clear("Quest route is off."); return end
    local pos = player()
    if not pos then clear("Waiting for your position."); return end
    local target = prefs().destination
    if target and pos.mapID ~= target then
        clear("Your quest route starts when you enter " .. ((C_Map.GetMapInfo(target) or {}).name or "the selected zone") .. ".")
        return
    end
    if Route.context ~= pos.mapID or (Route.origin and pos.cont ~= Route.origin.cont) then
        clear("Finding quests in this zone…")
        Route.context = pos.mapID
        ns.QuestRouteData:Invalidate()
    end
    if not Route.walk then Route.walk = ns.QuestRouteWalking.New(pos.cont, pos.mapID) end
    if jobs.collect and not force then Route.collectAgain = true; return end
    queue("collect", function(tick)
        local data, reason = ns.QuestRouteData:Collect(pos.mapID, pos, {
            turnins = setting("Turnins"), pickups = setting("Pickups"), avoidTowns = setting("AvoidTowns"),
            levelWindow = setting("LevelWindow"), levelAbove = setting("Above"), levelBelow = setting("Below"),
        }, tick)
        if not data then
            clear(reason or "Waiting for Questie.")
            Route.context = pos.mapID
            return
        end
        if Route.collectAgain then
            Route.collectAgain = nil
            Route:Request(0.2)
        end
        local shape, stamp = signatures(data, tick)
        local same = shape == Route.footprint
        local oldOrigin = Route.origin
        local moved = setting("Move") and oldOrigin and ns.Distance(pos.x,pos.y,oldOrigin.x,oldOrigin.y) >= MOVE_YARDS
        local progressOnly = same and not force and not moved and data.slots == (Route.data and Route.data.slots)
        if not same or moved or not Route.data or data.slots ~= Route.data.slots then Route.rounds = 0 end
        local skips = prefs().skips
        for k, entry in pairs(skips) do
            if data.activeIDs[entry.id] then
                entry.logged = true
            elseif entry.logged then
                local ok, logged = pcall(C_QuestLog and C_QuestLog.IsOnQuest, entry.id)
                if ok and ns.Readable(logged) and logged == false then skips[k] = nil end
            elseif C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
                local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, entry.id)
                if ok and ns.Readable(done) and done == true then skips[k] = nil end
            end
        end
        Route.walk:SetTowns(data.towns, tick)
        if progressOnly and stamp == Route.signature and (Route.view or Route.solving) then
            Route.data = data
            return
        end
        Route.data, Route.origin = data, pos
        Route.footprint, Route.signature = shape, stamp
        Route:Solve(progressOnly)
    end)
end

function Route:Request(delay, force)
    if not enabled() then return end
    self.pendingForce = self.pendingForce or force
    if self.timer and delay > 0 then return end
    local ticket = {}
    self.timer = ticket
    C_Timer.After(delay, function()
        if Route.timer ~= ticket then return end
        Route.timer = nil
        local needed = Route.pendingForce
        Route.pendingForce = false
        collect(needed)
    end)
end

function Route:Start(mapID)
    prefs().destination = mapID
    self.takeFocus, self.dismissed = true, nil
    if enabled() then self:Request(0, true) else ns:SetSetting("questRoute", true) end
end
function Route:Stop()
    ns:SetSetting("questRoute", false)
end

function Route:Click(key, action)
    local stop = self.view and self.view.byKey[key]
    if not stop then return end
    local skips = prefs().skips
    if action == "follow" then
        self.followed, self.dismissed = key, nil
        arrow(true)
        return
    elseif action == "skip" then
        if skips[key] then skips[key] = nil
        else skips[key] = { id = stop.task.questID, logged = not stop.task.optional } end
        if self.forced == key then self.forced = nil end
        if self.followed == key then self.followed = nil end
    elseif action == "next" then
        self.forced = self.forced ~= key and key or nil
        self.followed, self.dismissed, self.takeFocus = nil, nil, true
        skips[key] = nil
    else return end
    self.rounds = 0
    self:Solve(false)
end

function Route:Command(arg)
    if arg == "" or arg == "on" then self:Start(); ns.Print("Zone quest route enabled for your current zone.")
    elseif arg == "off" then self:Stop(); ns.Print("Zone quest route off.")
    elseif arg == "reset" then
        prefs().skips = {}
        self.forced, self.followed, self.dismissed = nil, nil, nil
        self:Request(0, true)
        ns.Print("Restored skipped quest route stops.")
    elseif arg == "why" or arg:match("^why%s+%d+$") then
        local list = self.view and self.view.why
        if not list or #list == 0 then ns.Print(self:Status() .. (self.view and " No omitted quests reported." or "")); return end
        local n = math.max(1, math.min(math.ceil(#list / 12), tonumber(arg:match("^why%s+(%d+)$")) or 1))
        ns.Print(("Quest route exclusions, page %d of %d"):format(n, math.ceil(#list / 12)))
        for i = (n-1)*12+1, math.min(n*12,#list) do ns.Print(list[i]) end
        if n*12 < #list then ns.Print("More: /mqol route why " .. (n+1)) end
    else ns.Print("Use /mqol route, /mqol route off, /mqol route reset or /mqol route why.") end
end

function Route:OnLogin()
    local function update() self:Request(0.95) end
    for _, event in ipairs({"QUEST_LOG_UPDATE","PLAYER_LEVEL_UP","SKILL_LINES_CHANGED","UPDATE_FACTION"}) do
        ns:RegisterEvent(event, update)
    end
    ns:RegisterEvent("QUEST_ACCEPTED", function()
        if enabled() then ns.QuestRouteData:Invalidate(); update() end
    end)
    for _, event in ipairs({"QUEST_TURNED_IN","QUEST_REMOVED"}) do
        ns:RegisterEvent(event, function(_, id)
            if ns.Readable(id) then
                for k, e in pairs(prefs().skips) do if e.id == id then prefs().skips[k] = nil end end
            end
            if enabled() then ns.QuestRouteData:Invalidate(); update() end
        end)
    end
    for _, event in ipairs({"PLAYER_ENTERING_WORLD","ZONE_CHANGED_NEW_AREA","UNIT_PHASE"}) do
        ns:RegisterEvent(event, function(_, unit)
            if enabled() and (event ~= "UNIT_PHASE" or ns.Readable(unit) and unit == "player") then
                ns.QuestRouteData:Invalidate()
                self:Request(0.2, true)
            end
        end)
    end
    ns:On("SETTING_CHANGED", function(key)
        if key == "questRoute" then
            if enabled() then self.takeFocus = true; self:Request(0, true)
            else self.timer = nil; clear("Quest route is off.") end
        elseif enabled() and (key:match("^questRoute") or key == "routeStyle") then
            if key == "questRouteArrow" or key == "questRouteOutline" then
                self.followed, self.dismissed = nil, nil
                arrow(key == "questRouteArrow" and setting("Arrow"))
                announce()
            elseif key == "questRouteDashed" or key == "questRouteShowSkipped" or key == "questRouteOpacity"
                or key == "questRouteMarkerSize" then announce()
            else
                if self.walk then self.walk:Cancel(); self.walk = nil end
                self.rounds, self.lastLearned = 0, 0
                self:Request(0, true)
            end
        end
    end)
    ns:On("WAYPOINT_REMOVED", function(rec)
        if not self.removing and rec and rec.source == SOURCE then self.dismissed = rec.routeKey; self.followed = nil end
    end)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if self.syncAfterCombat then
            arrow(self.focusAfterCombat)
            self.syncAfterCombat, self.focusAfterCombat = nil, nil
        end
        measure()
    end)
    if enabled() then self:Request(0, true) else removeArrow() end
    C_Timer.NewTicker(1.25, ns.Guarded(function()
        if not enabled() or self.timer or jobs.collect then return end
        local pos = player()
        if not pos then return end
        local target = prefs().destination
        if target and pos.mapID ~= target and not self.view then return end
        if not self.origin or pos.mapID ~= self.origin.mapID
            or setting("Move") and ns.Distance(pos.x,pos.y,self.origin.x,self.origin.y) >= MOVE_YARDS then
            self:Request(0, true)
        end
    end, "Wayfinder zone quest route"))
end
