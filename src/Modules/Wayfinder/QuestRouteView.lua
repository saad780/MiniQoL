-- The three trail layers are fixed to their viewports. Draw on our own frames
-- so a route refresh never acquires a Blizzard pin or changes the map's state.
local _, ns = ...
local View = ns:NewModule("QuestRouteView")
local surfaces, groups, revision = {}, {}, 0
local abs, ceil, floor, min, max, sqrt = math.abs, math.ceil, math.floor, math.min, math.max, math.sqrt
local DISC = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local STROKES, PINS = 320, 160
local PALETTE = {
    objective = { 0.12, 0.16, 0.21, 1, 1, 1 },
    pickup = { 1.0, 0.97, 0.78, 0.14, 0.10, 0.06 },
    turnin = { 1.0, 0.74, 0.16, 0.17, 0.10, 0.04 },
    skipped = { 0.28, 0.28, 0.28, 0.93, 0.93, 0.93 },
}
local function Round(n) return floor(n + 0.5) end

-- A shared meeting point has a single hit target. Preserve the original stop
-- numbers: two visits to the same quest giver can be separated by field work.
local function GroupStops(view, showSkipped)
    local result = {}
    local function add(stop, ordinal)
        local point, task = stop.point, stop.task
        local closest, best = nil, math.huge
        for _, group in ipairs(result) do
            local dx, dy = point.x - group.x, point.y - group.y
            local distance = dx * dx + dy * dy
            local sameObjective = task.kind == "objective" and group.objectives[task.questID]
            local radius = sameObjective and 96 or 32
            if distance <= radius * radius and distance < best then closest, best = group, distance end
        end
        if not closest then
            closest = { x = point.x, y = point.y, members = {}, objectives = {}, ordinal = ordinal }
            result[#result+1] = closest
        end
        local members = closest.members
        members[#members+1] = { task = task, ordinal = ordinal }
        closest.x = closest.x + (point.x - closest.x) / #members
        closest.y = closest.y + (point.y - closest.y) / #members
        if task.kind == "objective" then closest.objectives[task.questID] = true end
        if task.key == view.forced then closest.forced = task.key end
    end
    for i, stop in ipairs(view.stops) do add(stop, i) end
    if showSkipped then for _, stop in ipairs(view.skipped or {}) do add(stop) end end
    return result
end

local function Interact(pin)
    if InCombatLockdown() then return end
    local group = pin.group
    if not group then return end
    if IsControlKeyDown() then
        -- A mixed marker skips the remaining active stops. A gray marker
        -- restores its skipped stops together.
        for _, member in ipairs(group.members) do
            if (member.ordinal ~= nil) == (group.ordinal ~= nil) then
                ns.QuestRoute:Click(member.task.key, "skip")
            end
        end
    elseif group.ordinal and IsShiftKeyDown() then
        ns.QuestRoute:Click(group.forced or group.members[1].task.key, "next")
    elseif group.ordinal then
        local choices, seen = {}, {}
        for _, member in ipairs(group.members) do
            local task = member.task
            if member.ordinal and not seen[task.questID] then
                choices[#choices+1], seen[task.questID] = task, true
            end
        end
        local nextIndex = 1
        for i, task in ipairs(choices) do
            if task.questID == pin.lastQuest then nextIndex = i % #choices + 1; break end
        end
        pin.lastQuest = choices[nextIndex].questID
        ns.QuestRoute:Click(choices[nextIndex].key, "follow")
    end
end

local function Tooltip(pin)
    if not pin.group then return end
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:SetText("Location Prep", 1, 0.84, 0.43)
    for _, member in ipairs(pin.group.members) do
        local task = member.task
        local action = task.kind == "pickup" and "Pick up" or task.kind == "turnin" and "Turn in" or "Objective"
        local prefix = member.ordinal and tostring(member.ordinal) or "Skipped"
        GameTooltip:AddLine(prefix .. "  " .. action .. " · " .. task.quest, 1, 1, 1, true)
        local detail = task.label and task.label ~= task.quest and task.label or ""
        if task.progress and task.progress ~= "" and not detail:find(task.progress, 1, true) then
            detail = detail .. "  " .. task.progress
        end
        if detail ~= "" then GameTooltip:AddLine(detail, 0.81, 0.84, 0.87, true) end
    end
    GameTooltip:AddLine(pin.group.ordinal and
        "Click to follow a quest · Ctrl-click to skip · Shift-click for next stop" or "Ctrl-click to restore",
        0.67, 0.82, 0.92, true)
    GameTooltip:Show()
end

local function CloseTooltip(pin)
    if GameTooltip:IsOwned(pin) then GameTooltip:Hide() end
end

local function Marker(surface, index)
    local pin = surface.pins[index]
    if pin then return pin end
    pin = CreateFrame("Button", nil, surface.markerLayer)
    for _, name in ipairs({ "ring", "disc" }) do
        local texture = pin:CreateTexture(nil, name == "ring" and "BACKGROUND" or "ARTWORK")
        texture:SetTexture(DISC)
        texture:SetPoint("CENTER")
        pin[name] = texture
    end
    pin.text = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pin.text:SetPoint("CENTER")
    pin:RegisterForClicks("LeftButtonUp")
    if pin.SetPassThroughButtons then pin:SetPassThroughButtons("RightButton", "MiddleButton") end
    pin:SetScript("OnClick", Interact)
    pin:SetScript("OnEnter", Tooltip)
    pin:SetScript("OnLeave", CloseTooltip)
    pin:SetScript("OnHide", CloseTooltip)
    surface.pins[index] = pin
    return pin
end

local function HideRemainder(list, used, wasUsed)
    for i = used + 1, wasUsed do list[i]:Hide() end
end

local function Clear(surface)
    HideRemainder(surface.pins, 0, surface.pinCount)
    HideRemainder(surface.lines, 0, surface.lineCount)
    surface.pinCount, surface.lineCount = 0, 0
    surface.version = nil
end

local function InViewport(s, x, y, inset)
    if s.name == "mini" then
        local w, h = s.w / 2 - inset, s.h / 2 - inset
        if w <= 0 or h <= 0 or abs(x) > w or abs(y) > h then return false end
        if s.round and (x / w)^2 + (y / h)^2 > 1 then return false end
        return true
    end
    return x >= 0 and x <= s.w and y >= 0 and y <= s.h
end

local function Pins(s, project, size)
    local count = 0
    local scale = s.frame:GetEffectiveScale()
    for _, group in ipairs(groups) do
        local x, y = project(group.x, group.y)
        if s.name == "mini" then
            -- Give the player blip its own space, keeping a stop directly
            -- underfoot visible and clickable at the blip's edge.
            local gap = 8 + size / 2
            local distance = sqrt(x*x + y*y)
            if distance < 0.01 then x, y = 0, gap
            elseif distance < gap then x, y = x*gap/distance, y*gap/distance end
        end
        if InViewport(s, x, y, size / 2) then
            count = count + 1
            local pin = Marker(s, count)
            local task = group.members[1].task
            local kind = group.ordinal and task.kind or "skipped"
            local label = group.ordinal and tostring(group.ordinal) or "×"
            if kind == "pickup" then label = label .. "!"
            elseif kind == "turnin" then label = label .. "?" end
            if pin.group ~= group or pin.size ~= size then
                local color = PALETTE[kind]
                local diameter = max(size, #label * 6 + 5)
                pin.group, pin.size = group, size
                pin:SetSize(diameter, diameter)
                pin.disc:SetSize(diameter-3, diameter-3)
                pin.ring:SetSize(diameter, diameter)
                if group.forced then pin.ring:SetVertexColor(0.22, 0.65, 1)
                else pin.ring:SetVertexColor(0.62, 0.54, 0.31) end
                pin.disc:SetVertexColor(color[1], color[2], color[3])
                pin.text:SetTextColor(color[4], color[5], color[6])
                pin.text:SetText(label)
                if GameTooltip and GameTooltip:IsOwned(pin) then Tooltip(pin) end
            end
            pin:SetPoint("CENTER", s.frame, s.point, Round(x*scale)/scale, Round(y*scale)/scale * s.up)
            pin:Show()
            if count >= PINS then break end
        end
    end
    HideRemainder(s.pins, count, s.pinCount)
    s.pinCount = count
end

-- Parametric clipping works even when both ends are off screen. Clipping before
-- splitting into dashes bounds work when a long leg crosses a zoomed viewport.
local function Slab(lo, hi, a, d, extent)
    if d == 0 then
        if abs(a) <= extent then return lo, hi end
        return 1, 0
    end
    local t0, t1 = (-extent-a)/d, (extent-a)/d
    return max(lo, min(t0, t1)), min(hi, max(t0, t1))
end

local function Ellipse(ax, ay, dx, dy, w, h)
    local x, y, vx, vy = ax/w, ay/h, dx/w, dy/h
    local a, b = vx*vx + vy*vy, x*vx + y*vy
    local disc = b*b - a*(x*x + y*y - 1)
    if disc < 0 or a == 0 then return end
    local root = sqrt(disc)
    return (-b-root)/a, (-b+root)/a
end

local function VisiblePart(s, ax, ay, dx, dy, lo, hi, mode, length)
    if hi <= lo then return end
    s.n = s.n + 1
    local part = s.parts[s.n]
    if not part then part = {}; s.parts[s.n] = part end
    part.x, part.y = ax + lo*dx, ay + lo*dy
    part.dx, part.dy = dx/length, dy/length
    part.length, part.tail, part.mode = (hi-lo)*length, (1-hi)*length, mode
    s.length = s.length + part.length
end

local function Clip(s, ax, ay, bx, by, mode)
    local w, h, dx, dy = s.w / 2, s.h / 2, bx-ax, by-ay
    local length = sqrt(dx*dx + dy*dy)
    if length < 0.6 then return end
    local lo, hi
    if s.name == "mini" and s.round then
        lo, hi = Ellipse(ax, ay, dx, dy, w-2, h-2)
        if not lo then return end
        lo, hi = max(0, lo), min(1, hi)
    else
        local cx, cy = 0, 0
        if s.name ~= "mini" then cx, cy = w, h end
        lo, hi = Slab(0, 1, ax-cx, dx, w)
        lo, hi = Slab(lo, hi, ay-cy, dy, h)
    end
    if hi <= lo then return end
    if s.name == "mini" then
        local enter, leave = Ellipse(ax, ay, dx, dy, 9, 9)
        if enter and leave > lo and enter < hi then
            VisiblePart(s, ax, ay, dx, dy, lo, min(enter, hi), mode, length)
            lo = max(leave, lo)
        end
    end
    VisiblePart(s, ax, ay, dx, dy, lo, hi, mode, length)
end

local function Stroke(s, part, start, finish, opacity)
    if finish - start < 0.6 or s.used >= STROKES then return end
    s.used = s.used + 1
    local line = s.lines[s.used]
    if not line then
        line = s.frame:CreateLine(nil, "ARTWORK")
        s.lines[s.used] = line
    end
    line:SetStartPoint(s.point, s.frame, part.x + start*part.dx, (part.y + start*part.dy)*s.up)
    line:SetEndPoint(s.point, s.frame, part.x + finish*part.dx, (part.y + finish*part.dy)*s.up)
    line:SetColorTexture(1, part.mode == "outline" and 0.88 or 0.69, 0.23, opacity * (part.mode == "later" and 0.72 or 1))
    line:SetThickness(part.mode == "later" and 2 or 3)
    line:Show()
end

local function Lines(s, dashed, opacity)
    s.used = 0
    -- Each clipped segment gets at least one stroke. Spend the remaining
    -- budget on dashes in proportion to visible length, across the whole route.
    local period = max(15, s.length / max(1, STROKES - 2*s.n))
    for i = 1, s.n do
        local part = s.parts[i]
        if not dashed or part.length < 7 or period > 65 or part.mode == "outline" then
            Stroke(s, part, 0, part.length, opacity)
        else
            local ending = part.length - ((period - part.tail % period) % period)
            if ending + period - period*0.64 < part.length then ending = ending + period end
            while ending > 0 do
                Stroke(s, part, max(0, ending - period*0.64), min(ending, part.length), opacity)
                ending = ending - period
            end
        end
    end
    HideRemainder(s.lines, s.used, s.lineCount)
    s.lineCount = s.used
end

local function XY(p) return p.x or p[1], p.y or p[2] end

-- The player can move along the first path while the next plan is pending.
-- Find their join on its opening stretch to avoid drawing a line back to start.
local function Join(path, origin, wx, wy)
    local best = (wx-origin.x)^2 + (wy-origin.y)^2
    local at, jx, jy = 1, origin.x, origin.y
    local ax, ay, walked = origin.x, origin.y, 0
    for i=1, #path do
        local x, y = XY(path[i])
        local dx, dy = x-ax, y-ay
        local length2 = dx*dx + dy*dy
        if length2 > 0 then
            local t = max(0, min(1, ((wx-ax)*dx + (wy-ay)*dy) / length2))
            local tx, ty = ax+t*dx, ay+t*dy
            local distance = (wx-tx)^2 + (wy-ty)^2
            if distance < best then at, jx, jy, best = i, tx, ty, distance end
            walked = walked + sqrt(length2)
            if walked > 200 then break end
        end
        ax, ay = x, y
    end
    return at, jx, jy
end

local function Legs(s, view, project, wx, wy)
    s.n, s.length = 0, 0
    local from = view.origin
    local quota = max(1, floor((STROKES-48)/max(1, #view.stops)))
    for i, stop in ipairs(view.stops) do
        local target = stop.point
        local ax, ay = project(from.x, from.y)
        local area = i == 1 and ns:GetSetting("questRouteOutline") and target.area
        if area and wx and ns.Navigation.InArea(area, wx, wy) then
            local xs, ys = area.xs, area.ys
            local bx, by = project(xs[#xs], ys[#ys])
            for j = 1, #xs do
                local x, y = project(xs[j], ys[j])
                Clip(s, bx, by, x, y, "outline")
                bx, by = x, y
            end
        else
            local mode = i == 1 and "first" or "later"
            local path = view.paths and view.paths[i]
            local start = 1
            if i == 1 and wx then
                ax, ay = project(wx, wy)
                if path and #path > 0 then
                    local jx, jy
                    start, jx, jy = Join(path, from, wx, wy)
                    local x, y = project(jx, jy)
                    Clip(s, ax, ay, x, y, mode)
                    ax, ay = x, y
                end
            end
            if path and quota > 1 then
                local stride = max(1, ceil((#path-start+1) / (quota-1)))
                for j=start, #path, stride do
                    local x, y = project(XY(path[j]))
                    if (x-ax)^2 + (y-ay)^2 > 9 then
                        Clip(s, ax, ay, x, y, mode)
                        ax, ay = x, y
                    end
                end
            end
            -- An empty path means the town bypass found no safe connection.
            if not path or #path > 0 then
                local x, y = project(target.x, target.y)
                Clip(s, ax, ay, x, y, mode)
            end
        end
        from = target
    end
end

local current, lastStops, lastSkipped, lastForced, lastShowSkipped
local function Draw(s)
    if not current or InCombatLockdown() then return end
    local ants = ns.AntTrails
    local wx, wy = ants.PlayerWorld(current.cont)
    local project, w, h, round = ants:RouteProjection(s.name, current.cont, wx, wy)
    if not project or w < 8 or h < 8 then Clear(s); return end

    -- Sampling the transform also catches pans, zooms and minimap rotation.
    local a, b = project(current.origin.x, current.origin.y)
    local c, d = project(current.origin.x+64, current.origin.y+64)
    if s.version == revision and s.a == a and s.b == b and s.c == c and s.d == d
        and wx == s.wx and wy == s.wy and w == s.w and h == s.h and s.round == round then return end
    s.a, s.b, s.c, s.d, s.wx, s.wy = a, b, c, d, wx, wy
    s.w, s.h, s.round, s.version = w, h, round, revision

    local level = s.frame:GetFrameLevel() + 12
    if s.name == "map" then
        local playerLayer = ns.ContinuousEngine.MapStitch.playerLayer
        if playerLayer then level = max(s.frame:GetFrameLevel()+1, playerLayer:GetFrameLevel()-2) end
    elseif s.name == "zone" then
        local manager = BattlefieldMapFrame.GetPinFrameLevelsManager and BattlefieldMapFrame:GetPinFrameLevelsManager()
        if manager and type(manager.maxLevel) == "number" then level = max(level, manager.maxLevel+1) end
    end
    if s.markerLayer:GetFrameLevel() ~= level then s.markerLayer:SetFrameLevel(level) end
    Legs(s, current, project, wx, wy)
    Lines(s, ns:GetSetting("questRouteDashed"), ns:GetSetting("questRouteOpacity") or 0.85)
    Pins(s, project, ns:GetSetting("questRouteMarkerSize") or 20)
end

local function Refresh()
    revision = revision + 1
    current = ns.QuestRoute and ns.QuestRoute:GetView()
    local stops, skipped, forced = current and current.stops, current and current.skipped, current and current.forced
    local showSkipped = ns:GetSetting("questRouteShowSkipped")
    -- Each walking leg can publish its path separately for the same set of
    -- stops. Only rebuild hit targets when their order or membership changes.
    if lastStops ~= stops or lastSkipped ~= skipped or lastForced ~= forced or lastShowSkipped ~= showSkipped then
        groups = current and GroupStops(current, showSkipped) or {}
        lastStops, lastSkipped, lastForced, lastShowSkipped = stops, skipped, forced, showSkipped
    end
    for _, s in pairs(surfaces) do
        s.frame:SetShown(#groups > 0 and not InCombatLockdown())
        s.elapsed = 1
    end
end

function View:Attach(name, trail)
    local frame = CreateFrame("Frame", nil, trail.frame)
    frame:SetAllPoints(trail.frame)
    frame:EnableMouse(false)
    local layer = CreateFrame("Frame", nil, frame)
    layer:SetAllPoints(frame)
    layer:EnableMouse(false)
    local s = {name=name, frame=frame, markerLayer=layer, point=trail.point, up=trail.up,
        parts={}, pins={}, lines={}, pinCount=0, lineCount=0, elapsed=1}
    surfaces[name] = s
    frame:SetScript("OnUpdate", ns.Guarded(function(_, elapsed)
        s.elapsed = s.elapsed + elapsed
        if s.elapsed < 0.045 then return end
        s.elapsed = 0
        Draw(s)
    end, "Wayfinder quest route (" .. name .. ")"))
    frame:SetShown(#groups > 0 and not InCombatLockdown())
end

function View:OnLogin()
    ns:On("QUEST_ROUTE_CHANGED", Refresh)
    ns:On("QUEST_ROUTE_PATHS_CHANGED", function() revision = revision + 1 end)
    ns:On("SETTING_CHANGED", function(key)
        if key:match("^questRoute") or key == "zoneMap" then Refresh() end
    end)
    -- All frames here belong to Wayfinder. Hide them during combat so stale
    -- overlays cannot intercept map clicks while the protected map changes.
    ns:RegisterEvent("PLAYER_REGEN_DISABLED", function()
        for _, surface in pairs(surfaces) do surface.frame:Hide() end
    end)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED", Refresh)
    Refresh()
end
