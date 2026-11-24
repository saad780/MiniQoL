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

-- Only the static data packs are indexed. Player position, faction-specific
-- travel and Wayfinder's recorded NPCs are read at query time.
local indexedPacks = { npc = "npcs", quest = "npcs", creature = "creatures", node = "nodes", item = "gear" }
local indexes = {}
local function CreatureDetail(row)
    local detail = ranks[row[5]] or "Creature"
    if row[4] > 0 then
        if row[3] > 0 and row[3] ~= row[4] then return ("%s · Level %d–%d"):format(detail, row[3], row[4]) end
        return ("%s · Level %d"):format(detail, row[4])
    end
    return detail
end

local function NpcDetail(row)
    return row[6] or row[2]:gsub("_", " "):gsub("^%l", string.upper)
end

local function QuestDetail(quest, giver)
    return ("Quest from %s (level %d)"):format(giver[5], quest[4])
end

local function SearchIndex(kind, faction)
    if kind ~= "npc" and kind ~= "quest" then faction = nil end
    local data = E:Data(indexedPacks[kind])
    if not data then return end
    local index = indexes[kind]
    if index and index.data == data and index.faction == faction then return index end
    index = { data = data, faction = faction }
    local function group(mapID)
        local bucket = { mapID = mapID, rows = {}, texts = {}, extra = {} }
        index[#index + 1] = bucket
        local zone = E.MapName(mapID) or ""
        return function(row, name, detail, id, extra)
            local i = #bucket.rows + 1
            bucket.rows[i], bucket.extra[i] = row, extra
            bucket.texts[i] = (name .. " " .. detail .. " " .. zone .. " " .. (id or "")):lower()
        end
    end
    if kind == "item" then
        local add = group(nil)
        for id, row in pairs(data.items) do add(row, row[1], "", id, id) end
    else
        for mapID, rows in pairs(data.maps) do
            local add = group(mapID)
            for _, row in ipairs(rows) do
                if kind == "creature" then
                    add(row, row[2], CreatureDetail(row), row[1])
                elseif kind == "node" then
                    add(row, row[1], row[2] == "herb" and "Herb" or "Ore")
                elseif E.OwnFaction(row[7], faction) then
                    if kind == "npc" then
                        local detail = NpcDetail(row) .. " " .. row[2]:gsub("_", " ")
                        add(row, row[5], detail .. (flightTitles[row[6]] and " flight master" or ""), row[1])
                    else
                        for _, quest in ipairs(row[8] or {}) do
                            if E.OwnFaction(quest[5], faction) then
                                add(quest, quest[2], QuestDetail(quest, row), quest[1], row)
                            end
                        end
                    end
                end
            end
        end
    end
    indexes[kind] = index
    return index
end

local function ContainsWords(text, words)
    for i = 1, #words do
        if not text:find(words[i], 1, true) then return false end
    end
    return true
end

local function NameRank(name, query)
    local first, last = name:lower():find(query, 1, true)
    if first == 1 then return last == #name and 0 or 1 end
    return first and 2 or 3
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
    local words, bestByKey = {}, {}
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

    local function visit(category, emit)
        if not wants(category) then return end
        local index = SearchIndex(category, faction)
        if not index then return end
        for _, bucket in ipairs(index) do
            for i, text in ipairs(bucket.texts) do
                if ContainsWords(text, words) then emit(bucket.rows[i], bucket.mapID, bucket.extra[i]) end
            end
        end
    end

    visit("npc", function(row, mapID)
        add("npc:" .. row[1] .. ":" .. mapID, row[5], NpcDetail(row), mapID, row[3], row[4], NameRank(row[5], query))
    end)
    visit("quest", function(row, mapID, giver)
        add("quest:" .. row[1], row[2], QuestDetail(row, giver), mapID, giver[3], giver[4], NameRank(row[2], query))
    end)

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

    visit("creature", function(row, mapID)
        local x, y = BestPoint(player, mapID, row[6])
        add("npc:" .. row[1] .. ":" .. mapID, row[2], CreatureDetail(row), mapID, x, y, NameRank(row[2], query))
    end)
    visit("node", function(row, mapID)
        local x, y = BestPoint(player, mapID, row[3])
        local detail = row[2] == "herb" and "Herb" or "Ore"
        add("node:" .. row[1] .. ":" .. mapID, row[1], detail, mapID, x, y, NameRank(row[1], query))
    end)
    visit("item", function(item, _, id)
        local rank = NameRank(item[1], query)
        local key = "item:" .. id
        for _, source in ipairs(item[4]) do
            if self.OwnFaction(source[7], faction) then
                add(key, item[1], self.SourceLabel(source), source[2], source[3], source[4], rank, id)
            end
        end
    end)

    if wants("place") then
        local data = self:Data("dungeons")
        for id, dungeon in pairs(data and data.dungeons or {}) do
            local name, mapID = dungeon.name, dungeon.map
            add("dungeon:" .. id, name, "Dungeon entrance", mapID, dungeon.x, dungeon.y, match(name, "Dungeon", mapID))
        end
        local npcs = self:Data("npcs")
        for mapID in pairs(npcs and npcs.maps or {}) do
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

    local results, total = {}, 0
    for _, result in pairs(bestByKey) do
        total = total + 1
        if limit > 0 and (#results < limit or Better(result, results[limit])) then
            local low, high = 1, #results + 1
            while low < high do
                local mid = math.floor((low + high) / 2)
                if Better(result, results[mid]) then high = mid else low = mid + 1 end
            end
            table.insert(results, low, result)
            results[limit + 1] = nil
        end
    end
    return results, total
end
