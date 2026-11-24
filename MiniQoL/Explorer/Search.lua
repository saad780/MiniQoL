local _, ns = ...
local E = ns.Explorer

E.searchKinds = {
    { "all", "All" }, { "npc", "NPCs" }, { "creature", "Creatures" }, { "quest", "Quests" },
    { "item", "Items" }, { "node", "Gathering" }, { "place", "Places" },
}

local ranks = { [1] = "Elite", [2] = "Rare elite", [3] = "Boss", [4] = "Rare" }
local flightTitles = { ["Wind Rider Master"] = true, ["Gryphon Master"] = true, ["Hippogryph Master"] = true,
    ["Bat Handler"] = true, ["Flight Master"] = true }
local function Match(name, words, query, ...)
    local lower = name:lower()
    if lower == query then return 0 end
    if lower:sub(1, #query) == query then return 1 end
    if lower:find(query, 1, true) then return 2 end
    local text = table.concat({ lower, ... }, " "):lower()
    for _, word in ipairs(words) do
        if not text:find(word, 1, true) then return end
    end
    return 3
end

local function Better(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.tier ~= b.tier then return a.tier < b.tier end
    if a.distance ~= b.distance then return a.distance < b.distance end
    if a.name ~= b.name then return a.name < b.name end
    return a.key < b.key
end

local function BestPoint(player, mapID, points)
    local x, y, tier, distance
    for i = 1, #points - 1, 2 do
        local t, d = E.Distance(player, mapID, points[i], points[i + 1])
        if not tier or t < tier or (t == tier and d < distance) then
            x, y, tier, distance = points[i], points[i + 1], t, d
        end
    end
    return x, y
end

local function MapPoint(row)
    local board = type(row[10]) == "table" and row[10]
    local mapID, x, y = row[5], board and board.wx or row[3], board and board.wy or row[4]
    local rect = Wayfinder.GetMapRect(mapID)
    if rect and rect.cont == row[2] then
        x, y = Wayfinder.WorldToMapRect(rect, x, y)
        return mapID, x, y
    end
end

function E:Search(text, kind, limit)
    local query = text:lower():match("^%s*(.-)%s*$")
    if #query < 2 then return {}, 0 end
    local words, bestByKey, zones = {}, {}, {}
    for word in query:gmatch("%S+") do words[#words + 1] = word end
    local player = self.PlayerPosition()
    local faction = UnitFactionGroup("player")
    local network = Wayfinder and Wayfinder.TravelNetwork
    local function wants(category) return kind == "all" or kind == category end
    local function match(name, detail, mapID, id)
        if name then return Match(name, words, query, detail or "", self.MapName(mapID) or "", tostring(id or "")) end
    end
    local function add(key, name, detail, mapID, x, y, rank, itemID)
        if not rank then return end
        local tier, distance = self.Distance(player, mapID, x, y)
        local candidate = { name = name, detail = detail, mapID = mapID, x = x, y = y, rank = rank,
            tier = tier, distance = distance, key = key, itemID = itemID }
        local prior = bestByKey[key]
        if not prior or Better(candidate, prior) then bestByKey[key] = candidate end
    end

    if wants("npc") or wants("quest") or wants("place") then
        local data = self:Data("npcs")
        for mapID, rows in pairs(data and data.maps or {}) do
            zones[mapID] = true
            for _, row in ipairs(rows) do
                local id, role, x, y, name, title, side, quests = unpack(row, 1, 8)
                if self.OwnFaction(side, faction) then
                    if wants("npc") then
                        local detail = title or role:gsub("_", " "):gsub("^%l", string.upper)
                        local keywords = detail .. " " .. role:gsub("_", " ") .. (flightTitles[title] and " flight master" or "")
                        add("npc:" .. id .. ":" .. mapID, name, detail, mapID, x, y, match(name, keywords, mapID, id))
                    end
                    if wants("quest") then
                        for _, quest in ipairs(quests or {}) do
                            if self.OwnFaction(quest[5], faction) then
                                local detail = ("Quest from %s (level %d)"):format(name, quest[4])
                                add("quest:" .. quest[1], quest[2], detail, mapID, x, y, match(quest[2], detail, mapID, quest[1]))
                            end
                        end
                    end
                end
            end
        end
    end

    if wants("npc") or wants("place") then
        for _, row in ipairs(network and network.taxi or {}) do
            if (row[8] == 3 or row[8] == Wayfinder.playerFaction) and (not row[10] or row[10] == Wayfinder.playerClass) then
                local name, mapID = row[9], row[5]
                add("flight:" .. row[1], name, "Flight master", mapID, row[6], row[7], match(name, "Flight master", mapID))
            end
        end
    end

    if wants("npc") and Wayfinder and Wayfinder.db then
        for _, rec in pairs(Wayfinder.db.pois or {}) do
            if rec.kind == "npc" and rec.n and rec.m and (not rec.f or rec.f == 0 or rec.f == Wayfinder.playerFaction) then
                local tags = { rec.s or "" }
                for category in pairs(rec.cats or {}) do
                    local def = Wayfinder.CategoryByID and Wayfinder.CategoryByID[category]
                    if def then tags[#tags + 1] = def.label end
                end
                local detail = rec.s or tags[2] or "NPC"
                local rank = match(rec.n, table.concat(tags, " "), rec.m, rec.id)
                local rect = rank and Wayfinder.GetMapRect(rec.m)
                if rect and rect.cont == rec.c then
                    local x, y = Wayfinder.WorldToMapRect(rect, rec.x, rec.y)
                    local key = rec.id and ("npc:" .. rec.id .. ":" .. rec.m) or ("recorded:" .. rec.k)
                    add(key, rec.n, detail, rec.m, x, y, rank)
                end
            end
        end
    end

    if wants("creature") then
        local data = self:Data("creatures")
        for mapID, rows in pairs(data and data.maps or {}) do
            for _, row in ipairs(rows) do
                local id, name, low, high, rank, points = unpack(row)
                local detail = ranks[rank] or "Creature"
                if high > 0 then
                    detail = detail .. (low > 0 and low ~= high and (" · Level %d–%d"):format(low, high) or (" · Level %d"):format(high))
                end
                local rating = match(name, detail, mapID, id)
                if rating then
                    local x, y = BestPoint(player, mapID, points)
                    add("npc:" .. id .. ":" .. mapID, name, detail, mapID, x, y, rating)
                end
            end
        end
    end

    if wants("node") then
        local data = self:Data("nodes")
        for mapID, rows in pairs(data and data.maps or {}) do
            for _, row in ipairs(rows) do
                local name, node, points = unpack(row)
                local detail = node == "herb" and "Herb" or "Ore"
                local rank = match(name, detail, mapID)
                if rank then
                    local x, y = BestPoint(player, mapID, points)
                    add("node:" .. name .. ":" .. mapID, name, detail, mapID, x, y, rank)
                end
            end
        end
    end

    if wants("item") then
        local data = self:Data("gear")
        for id, item in pairs(data and data.items or {}) do
            -- Item searches match item names and IDs. A vendor in Elwynn
            -- should not return every item on their inventory as a match.
            local rank = match(item[1], nil, nil, id)
            if rank then
                local key = "item:" .. id
                for _, source in ipairs(item[4]) do
                    if self.OwnFaction(source[7], faction) then
                        add(key, item[1], self.SourceLabel(source), source[2], source[3], source[4], rank, id)
                    end
                end
            end
        end
    end

    if wants("place") then
        local data = self:Data("dungeons")
        for id, dungeon in pairs(data and data.dungeons or {}) do
            local name, mapID = dungeon.name, dungeon.map
            add("dungeon:" .. id, name, "Dungeon entrance", mapID, dungeon.x, dungeon.y, match(name, "Dungeon", mapID))
        end
        for mapID in pairs(zones) do
            local name = self.MapName(mapID)
            add("zone:" .. mapID, name, "Zone", mapID, nil, nil, match(name, "Zone"))
        end
        local function route(kind, from, to)
            local mapID, x, y = MapPoint(from)
            if not mapID then return end
            local name = from[1] .. " to " .. to[1]
            local detail = kind:gsub("^%l", string.upper)
            add(kind .. ":" .. name, name, detail, mapID, x, y, match(name, detail, mapID))
        end
        for _, data in ipairs(network and network.transports or {}) do
            if data.faction == 3 or data.faction == Wayfinder.playerFaction then
                route(data.kind, data.a, data.b)
                route(data.kind, data.b, data.a)
            end
        end
        for _, data in ipairs(network and network.portals or {}) do route("portal", data.a, data.b) end
    end

    local results = {}
    for _, result in pairs(bestByKey) do results[#results + 1] = result end
    table.sort(results, Better)
    local total = #results
    for i = total, limit + 1, -1 do results[i] = nil end
    return results, total
end
