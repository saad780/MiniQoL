local _, ns = ...
local E, T = ns.Explorer, ns.Theme
local Prep = E.Prep
local selected, message, job
local page, perPage = 1, 12

local function visible()
    return ns.panel and ns.panel:IsShown() and ns.db.page == "prep" and ns.search:GetText() == ""
end

local function currentZone()
    return E.Zone(C_Map.GetBestMapForUnit("player"))
end

local function resolve(text, zones)
    if text == "" then
        local id = currentZone()
        if id then return id end
        return nil, "Enter the name of the zone you want to prepare."
    end
    local number = tonumber(text)
    if number and number > 0 and number == math.floor(number) and E.MapName(number) then return number end
    local query, matches = text:lower(), {}
    local root = C_Map.GetFallbackWorldMapID and C_Map.GetFallbackWorldMapID() or 947
    for _, info in ipairs(C_Map.GetMapChildrenInfo(root, Enum.UIMapType.Zone, true) or {}) do
        local name = info.name:lower()
        if name == query then return info.mapID end
        if name:find(query, 1, true) then matches[#matches + 1] = info end
    end
    local area = zones:GetAreaIdByName(text)
    if area then
        local mapID = zones:GetUiMapIdByAreaId(area)
        if mapID then return mapID end
    end
    if #matches == 1 then return matches[1].mapID end
    if #matches > 1 then
        table.sort(matches, function(a, b) return a.name < b.name end)
        local names = {}
        for i = 1, math.min(4, #matches) do names[i] = matches[i].name end
        return nil, "Several zones match. Enter a longer name (" .. table.concat(names, ", ") .. ")."
    end
    return nil, "No matching zone. Enter a zone name or map ID."
end

local function selectZone(text)
    local db, modules = Prep.Provider()
    if not db then return end
    local mapID, reason = resolve(text:match("^%s*(.-)%s*$"), modules.ZoneDB)
    local ok, area
    if mapID then ok, area = pcall(modules.ZoneDB.GetAreaIdByUiMapId, modules.ZoneDB, mapID) end
    if not (ok and area and area > 0) then
        message = reason or "Questie has no quest area for that map."
        return
    end
    selected, message, page = { mapID = mapID, area = area, name = E.MapName(mapID) }, nil, 1
    job = { zone = selected, dirty = true }
    local key = ns.Characters and ns.Characters.PlayerKey()
    if key then
        ns.db.prepZones = ns.db.prepZones or {}
        ns.db.prepZones[key] = mapID
    end
    if ns.scroll then ns.scroll:SetVerticalScroll(0) end
end

local request
function Prep:Open(text)
    request = text ~= "" and text or nil
    ns:ShowPage("prep")
end

local function run(work)
    if work.pending or work.error or (work.sections and not work.dirty and not work.thread) then return end
    if not work.thread then
        local deadline, operations
        local function tick()
            operations = operations + 1
            if operations >= 40 or debugprofilestop() >= deadline then
                coroutine.yield()
                deadline, operations = debugprofilestop() + 3, 0
            end
        end
        work.thread = coroutine.create(function()
            deadline, operations = debugprofilestop() + 3, 0
            work.records = work.records or Prep.ScanZone(work.zone.area, tick)
            work.dirty = false
            local mapID = C_Map.GetBestMapForUnit("player")
            local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
            local origin = { mapID = mapID, here = E.Zone(mapID) == work.zone.mapID }
            if pos then
                local x, y = pos:GetXY()
                origin.x, origin.y = x, y
            end
            local route, waiting, optional = Prep.Route(work.records, Prep.Character(), origin, tick)
            local counts = { ["Before traveling"] = 0, ["In the zone"] = 0, ["Outside the zone"] = 0 }
            for _, row in ipairs(route) do counts[row.phase] = counts[row.phase] + 1 end
            work.summary = ("%d prep steps  ·  %d in-zone steps  ·  %d later outside  ·  %d to check")
                :format(counts["Before traveling"], counts["In the zone"], counts["Outside the zone"], #waiting)
            if counts["In the zone"] > 0 and counts["Outside the zone"] == 0 then
                work.summary = work.summary .. "\nAfter prep, all mapped steps stay in " .. work.zone.name .. "."
            end
            local sections = { {}, {}, waiting, optional }
            for _, row in ipairs(route) do
                local section = sections[row.phase == "Before traveling" and 1 or 2]
                section[#section + 1] = row
            end
            work.sections = sections
        end)
    end
    work.pending = true
    C_Timer.After(0, function()
        work.pending = false
        if work ~= job or not visible() then return end
        local ok, err = coroutine.resume(work.thread)
        if not ok then
            work.error, work.thread = true, nil
            ns:Print("Location Prep could not read the quest data. " .. tostring(err))
        elseif coroutine.status(work.thread) ~= "dead" then
            run(work)
            return
        else
            work.thread = nil
        end
        ns:Refresh()
    end)
end

local function controls(y)
    local row = ns:Row("prep.zone", 33)
    row:SetPoint("TOPLEFT", 0, -y)
    if not row.edit then
        local field = CreateFrame("Frame", nil, row, "BackdropTemplate")
        T:Chrome(field, T.BG_CARD, T.BORDER)
        field:SetSize(270, 26)
        field:SetPoint("TOPLEFT")
        local edit = CreateFrame("EditBox", nil, field)
        row.edit = edit
        edit:SetAllPoints()
        edit:SetAutoFocus(false)
        edit:SetFontObject("ChatFontNormal")
        edit:SetTextInsets(8, 6, 0, 0)
        edit:SetMaxLetters(80)
        local hint = T:Text(field, "Destination zone", "GameFontDisableSmall", 235, T.MUTED)
        hint:SetPoint("LEFT", 8, 0)
        edit:SetScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "") end)
        local function submit(input)
            edit:ClearFocus()
            selectZone(input)
            if selected and not message then edit:SetText(selected.name) end
            ns:Refresh()
        end
        edit:SetScript("OnEnterPressed", function(self) submit(self:GetText()) end)
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        T:Button(row, "Plan zone", 93, 26, function() submit(edit:GetText()) end):SetPoint("TOPLEFT", 277, 0)
        T:Button(row, "Current zone", 105, 26, function() submit("") end):SetPoint("TOPLEFT", 377, 0)
        row.route = T:Button(row, "Route this zone", 127, 26, function()
            local route = Wayfinder and Wayfinder.QuestRoute
            if not (selected and route) then return end
            if row.routing then route:Stop() else route:Start(selected.mapID) end
            ns:Refresh()
        end)
        row.route:SetPoint("TOPLEFT", 489, 0)
    end
    return y + 34, row.edit, row
end

local function renderStep(i, step, y)
    local row = ns:Row("prep.step." .. i, 45)
    row:SetPoint("TOPLEFT", 0, -y)
    if not row.title then
        row.title = T:Text(row, "", "GameFontHighlight", 495, T.TEXT)
        row.title:SetPoint("TOPLEFT", 4, -3)
        row.title:SetWordWrap(false)
        row.detail = T:Text(row, "", "GameFontHighlightSmall", 495, T.MUTED)
        row.detail:SetPoint("TOPLEFT", 4, -22)
        row.detail:SetWordWrap(false)
        row.pin = T:Button(row, "Waypoint", 94, 23, function()
            if row.routeKey then Wayfinder.QuestRoute:Click(row.routeKey, "follow") else E.Waypoint(row.target) end
        end)
        row.pin:SetPoint("RIGHT", -5, 0)
        T:Tip(row, function() return row.title:GetText() end, function() return row.detail:GetText() end)
    end
    local place = step.place
    local title = step.kind and (step.label .. " · " .. step.quest) or step.quest
    local parts = {}
    row.routeKey = step.routeKey
    if step.routeKey then title = step.title end
    if not step.kind and (not step.routeKey or not title:find(step.label, 1, true)) then parts[#parts + 1] = step.label end
    if step.after and (not step.routeKey or not title:find(step.after, 1, true)) then parts[#parts + 1] = step.after end
    if place then
        if place.name then parts[#parts + 1] = place.name end
        parts[#parts + 1] = (place.mapID and E.MapName(place.mapID)) or C_Map.GetAreaInfo(place.area) or "Unknown area"
        if place.x then parts[#parts + 1] = ("%.1f, %.1f"):format(place.x * 100, place.y * 100) end
    end
    row.title:SetText(title)
    row.detail:SetText(table.concat(parts, " · "))
    row.target = place and { mapID = place.mapID, name = title, x = place.x, y = place.y }
    row.pin:SetText(step.routeKey and "Follow" or "Waypoint")
    row.pin:SetShown((step.routeKey or (place and place.x)) and true or false)
    return y + 45
end

function Prep:Render(y)
    if not Prep.Provider() then
        return ns:Note("prep.provider", Questie and "Waiting for Questie's Forever database to finish loading."
            or "Enable Questie and QuestieDB for WoW Forever to plan a zone.", y)
    end
    local edit, form
    y, edit, form = controls(y)
    if request or (not selected and not message) then
        local key = ns.Characters and ns.Characters.PlayerKey()
        local saved = key and ns.db.prepZones and ns.db.prepZones[key]
        local text = request or (saved and tostring(saved)) or ""
        request = nil
        selectZone(text)
        edit:SetText(selected and not message and selected.name or text)
    end
    local route = Wayfinder and Wayfinder.db and Wayfinder.QuestRoute
    local active = route and route:Enabled()
    local destination = active and (route:Destination() or currentZone())
    form.routing = selected and destination == selected.mapID
    form.route:SetEnabled(not not (selected and not message and route))
    form.route:SetText(form.routing and "Stop zone route" or "Route this zone")
    local live = active and selected and route:GetView()
    if live and live.mapID ~= selected.mapID then live = nil end
    if form.routing then y = ns:Note("prep.routeStatus", route:Status(), y) end
    if message then y = ns:Note("prep.message", message, y) end
    if not job then return y end
    if job.error then return ns:Note("prep.error", "Quest data could not be read. Choose Plan zone to retry.", y) end
    run(job)
    if not job.sections then return ns:Note("prep.progress", "Finding quests and their prerequisites for " .. selected.name .. "…", y) end
    y = ns:Section("prep.zone", selected.name, y)
    y = ns:Note("prep.summary", job.summary, y)
    local sections = {job.sections[1], job.sections[2], job.sections[3], job.sections[4], live and live.stops or {}}
    if not job.view or #sections[job.view] == 0 then
        job.view = nil
        for i, section in ipairs(sections) do
            if #section > 0 then job.view = i; page = 1; break end
        end
    end
    if not job.view then return ns:Note("prep.empty", "No remaining quests found for this character in Questie's zone data.", y) end
    local filter = ns:Row("prep.views", 30)
    filter:SetPoint("TOPLEFT", 0, -y)
    filter.buttons = filter.buttons or {}
    for i, label in ipairs({ "Before travel", "Zone itinerary", "To check", "Shared sources", "Live route" }) do
        local button = filter.buttons[i]
        if not button then
            button = T:Button(filter, "", 118, 23, function()
                job.view, page = i, 1
                ns.scroll:SetVerticalScroll(0)
                ns:Refresh()
            end)
            button:SetPoint("TOPLEFT", (i - 1) * 124, 0)
            filter.buttons[i] = button
        end
        button:SetText(label .. " (" .. #sections[i] .. ")")
        button:SetPrimary(job.view == i)
        button:SetEnabled(#sections[i] > 0)
    end
    y = y + 30
    if job.view == 4 then
        y = ns:Note("prep.optional", "These quests have a source here and in other zones. Their pickups are optional for this trip.", y)
    end
    local rows = sections[job.view]
    local total = #rows
    local pages = math.ceil(total / perPage)
    page = math.min(page, pages)
    if pages > 1 then
        local nav = ns:Row("prep.pages", 30)
        nav:SetPoint("TOPLEFT", 0, -y)
        if not nav.prev then
            local function turn(by) page = page + by; ns.scroll:SetVerticalScroll(0); ns:Refresh() end
            nav.prev = T:Button(nav, "Previous", 84, 22, function() turn(-1) end)
            nav.prev:SetPoint("TOPLEFT")
            nav.next = T:Button(nav, "Next", 80, 22, function() turn(1) end)
            nav.next:SetPoint("TOPLEFT", 91, 0)
            nav.label = T:Text(nav, "", "GameFontHighlightSmall", 130, T.MUTED)
            nav.label:SetPoint("TOPLEFT", 183, -5)
        end
        nav.prev:SetEnabled(page > 1)
        nav.next:SetEnabled(page < pages)
        nav.label:SetText(("Page %d of %d"):format(page, pages))
        y = y + 30
    end
    local phase
    for i = 1, perPage do
        local index = (page - 1) * perPage + i
        local step = rows[index]
        if not step then break end
        if job.view == 5 then
            local t, p = step.task, step.point
            local rect = Wayfinder.GetMapRect(live.mapID)
            local place = { mapID = live.mapID, name = p.name }
            if rect then place.x, place.y = Wayfinder.WorldToMapRect(rect, p.x, p.y) end
            step = { routeKey = t.key, title = index .. ". " .. t.label, label = t.quest,
                after = t.progress, place = place }
        end
        if step.phase ~= phase then
            phase = step.phase
            y = ns:Section("prep.phase." .. i, phase, y)
        end
        y = renderStep(i, step, y)
    end
    return y
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "ZONE_CHANGED_NEW_AREA",
    "PLAYER_LEVEL_UP", "UPDATE_FACTION", "SKILL_LINES_CHANGED", "PLAYER_ENTERING_WORLD" }) do
    events:RegisterEvent(event)
end
local queued
events:SetScript("OnEvent", function()
    if job then job.dirty = true end
    if queued or not visible() then return end
    queued = true
    C_Timer.After(0.4, function()
        queued = false
        if visible() then ns:Refresh() end
    end)
end)
if Questie and Questie.API and Questie.API.RegisterOnReady then
    Questie.API.RegisterOnReady(function() if visible() then ns:Refresh() end end)
end
if Wayfinder and Wayfinder.On and Wayfinder.QuestRoute then
    local shown, status
    Wayfinder:On("QUEST_ROUTE_CHANGED", function()
        local route = Wayfinder.QuestRoute
        local view, nextStatus = route:GetView(), route:Status()
        if view ~= shown or status ~= nextStatus then
            shown, status = view, nextStatus
            if visible() then ns:Refresh() end
        end
    end)
end
