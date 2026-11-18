-- Mini QoL packaging adapter; upstream source and credits follow.
MiniQoLRuntime:Execute("Wayfinder", function(...)
-- Built-in locations (town services and transports) that are revealed by exploring.
--
-- A built-in location only shows once the terrain cell it sits in has been explored,
-- which is the moment the minimap would have shown its icon. Each one is a single
-- person or object: a location you have recorded yourself replaces the one it
-- stands on, never the others at the same counter.
local _, ns = ...

local Seeds = ns:NewModule("Seeds")

local floor = math.floor
local GRID = 250
local SAME_SPOT_YARDS = 2     -- the same point listed twice; three bankers in a row are three
local SUPERSEDE_YARDS = 25    -- a recorded location this close can replace a built-in one
local ACCURATE_YARDS = 5      -- placed as well as a built-in location: by talking, not from across a room

local buckets = {}
local bucketCounts = {}
local all = {}
local supersedeVersion = 0
local coverVersion = 0

local function BucketKey(wx, wy)
	return (floor(wx / GRID) + 200) * 1000 + (floor(wy / GRID) + 200)
end

local function Query(cont, minX, maxX, minY, maxY, fn)
	local contBuckets = buckets[cont]
	if not contBuckets then
		return
	end
	local cells = (floor(maxX / GRID) - floor(minX / GRID) + 1) * (floor(maxY / GRID) - floor(minY / GRID) + 1)
	if cells > (bucketCounts[cont] or 0) then
		for _, bucket in pairs(contBuckets) do
			for _, seed in ipairs(bucket) do
				if seed.x >= minX and seed.x <= maxX and seed.y >= minY and seed.y <= maxY then fn(seed) end
			end
		end
		return
	end
	for bx = floor(minX / GRID), floor(maxX / GRID) do
		for by = floor(minY / GRID), floor(maxY / GRID) do
			local bucket = contBuckets[(bx + 200) * 1000 + (by + 200)]
			if bucket then
				for i = 1, #bucket do
					local seed = bucket[i]
					if seed.x >= minX and seed.x <= maxX and seed.y >= minY and seed.y <= maxY then
						fn(seed)
					end
				end
			end
		end
	end
end

local function NearDuplicate(cont, wx, wy, catID)
	local found = false
	Query(cont, wx - SAME_SPOT_YARDS, wx + SAME_SPOT_YARDS, wy - SAME_SPOT_YARDS, wy + SAME_SPOT_YARDS, function(seed)
		if seed.cats[catID] and ns.Distance(wx, wy, seed.x, seed.y) <= SAME_SPOT_YARDS then
			found = true
		end
	end)
	return found
end

local function Add(seed)
	local contBuckets = buckets[seed.c]
	if not contBuckets then
		contBuckets = {}
		buckets[seed.c] = contBuckets
	end
	local key = BucketKey(seed.x, seed.y)
	local bucket = contBuckets[key]
	if not bucket then
		bucket = {}
		contBuckets[key] = bucket
		bucketCounts[seed.c] = (bucketCounts[seed.c] or 0) + 1
	end
	bucket[#bucket + 1] = seed
	all[#all + 1] = seed
end

local function MakeSeed(catID, mapID, x, y, faction, name, extra)
	local cont, wx, wy = ns.MapToWorld(mapID, x / 100, y / 100)
	if not cont or NearDuplicate(cont, wx, wy, catID) then
		return
	end
	local seed = {
		k = ("s:%s:%d:%.1f:%.1f"):format(catID, mapID, x, y),
		kind = "seed",
		seed = true,
		cats = { [catID] = true },
		n = name,
		c = cont,
		x = wx,
		y = wy,
		m = mapID,
		f = faction,
		a = 5,
	}
	if extra then
		for k, v in pairs(extra) do
			seed[k] = v
		end
	end
	Add(seed)
	return seed
end

function Seeds:Build()
	wipe(buckets)
	wipe(bucketCounts)
	wipe(all)
	local replacements, candidates, used = {}, {}, {}
	local function Candidate(cat, map, x, y, faction, name, extra, aliases)
		local candidate = { cat, map, x, y, faction, name, extra, aliases }
		candidates[#candidates + 1] = candidate
		for _, key in ipairs(aliases or {}) do replacements[key] = candidate end
	end
	for _, e in ipairs(ns.IndependentSeedData or {}) do
		for i = 1, #e.pts, 4 do
			Candidate(e.cat, e.pts[i], e.pts[i + 1], e.pts[i + 2], e.pts[i + 3], e.name,
				{ cls = e.class, builtin = true, a = e.accuracy, source = e.source }, e.replaces)
		end
	end
	for _, t in ipairs(ns.IndependentTransportData or {}) do
		Candidate("transport", t[2], t[3], t[4], t[6], t[5],
			{ sub = t[1], a = t.accuracy, source = t.source }, t.replaces)
	end
	local function Install(candidate)
		if used[candidate] then return true end
		local seed = MakeSeed(unpack(candidate, 1, 7))
		if not seed then return false end
		used[candidate] = true
		for _, key in ipairs(candidate[8] or {}) do
			if ns.db.hidden[key] then ns.db.hidden[seed.k] = true end
		end
		return true
	end
	local function Legacy(cat, map, x, y, faction, name, extra)
		local candidate = replacements[("s:%s:%d:%.1f:%.1f"):format(cat, map, x, y)]
		if not candidate or not Install(candidate) then
			MakeSeed(cat, map, x, y, faction, name, extra)
		end
	end
	for _, entry in ipairs(ns.SeedData or {}) do
		local pts, names = entry.pts, entry.names
		for i = 1, #pts, 4 do
			local name = names and names[(i - 1) / 4 + 1] or entry.name
			Legacy(entry.cat, pts[i], pts[i + 1], pts[i + 2], pts[i + 3], name,
				{ cls = entry.class, builtin = true, s = names and entry.name or nil })
		end
	end
	for _, t in ipairs(ns.TransportData or {}) do
		Legacy("transport", t[2], t[3], t[4], t[6], t[5], { sub = t[1] })
	end
	for _, candidate in ipairs(candidates) do Install(candidate) end
	ns.Debug(#all, "built-in locations loaded")
end

function Seeds:OnLogin()
	self:Build()
	local function Invalidate()
		supersedeVersion = supersedeVersion + 1
	end
	ns:On("POI_UPDATED", Invalidate)
	ns:On("POI_REMOVED", Invalidate)
	ns:On("DATA_CHANGED", Invalidate)
	-- What a rough sighting yields to also depends on what has been explored
	-- and on whether built-in locations are in use at all.
	local function Uncover()
		coverVersion = coverVersion + 1
	end
	for _, message in ipairs({ "POI_UPDATED", "POI_REMOVED", "DATA_CHANGED", "EXPLORED", "SETTING_CHANGED" }) do
		ns:On(message, Uncover)
	end
end

-- A record placed as well as a built-in location can stand in for one.
local function Stands(rec, catID)
	return rec.cats[catID] and (rec.a or 30) <= ACCURATE_YARDS
end

-- The recorded location that replaces this built-in one, if any. Each record
-- replaces one built-in location at most, and each built-in location is
-- replaced by one record at most, nearest pairs first. Replacing everything
-- within reach instead is how one auctioneer you had spoken to took the two
-- beside him off the map.
local function Replacement(seed)
	local catID = next(seed.cats)
	local reach = SUPERSEDE_YARDS
	local records, known = {}, {}
	local function Gather(x, y)
		ns.Database:Query(seed.c, x - reach, x + reach, y - reach, y + reach, function(rec)
			if not known[rec] and Stands(rec, catID) and ns.Distance(x, y, rec.x, rec.y) <= reach then
				known[rec] = true
				records[#records + 1] = rec
			end
		end)
	end
	Gather(seed.x, seed.y)
	if #records == 0 then
		return nil
	end
	-- The other built-in locations those records could stand for instead, and
	-- the records competing for those: one counter's worth, however it is laid out.
	local seeds, listed = { seed }, { [seed] = true }
	for index = 1, #records do
		local rec = records[index]
		Query(seed.c, rec.x - reach, rec.x + reach, rec.y - reach, rec.y + reach, function(other)
			if not listed[other] and other.cats[catID] and ns.Distance(rec.x, rec.y, other.x, other.y) <= reach then
				listed[other] = true
				seeds[#seeds + 1] = other
			end
		end)
	end
	for index = 2, #seeds do
		Gather(seeds[index].x, seeds[index].y)
	end
	local candidates = {}
	for _, rec in ipairs(records) do
		for _, other in ipairs(seeds) do
			local distance = ns.Distance(rec.x, rec.y, other.x, other.y)
			if distance <= reach then
				candidates[#candidates + 1] = { rec = rec, seed = other, distance = distance }
			end
		end
	end
	table.sort(candidates, function(a, b)
		if a.distance ~= b.distance then return a.distance < b.distance end
		if a.seed.k ~= b.seed.k then return a.seed.k < b.seed.k end
		return tostring(a.rec.k) < tostring(b.rec.k)
	end)
	local placed, replaced = {}, {}
	for _, candidate in ipairs(candidates) do
		if not placed[candidate.rec] and not replaced[candidate.seed] then
			placed[candidate.rec], replaced[candidate.seed] = true, candidate.rec
		end
	end
	return replaced[seed]
end

-- Whether a recorded location already stands for this built-in one.
local function IsSuperseded(seed)
	if seed._v == supersedeVersion then
		return seed._sup
	end
	seed._v, seed._sup = supersedeVersion, Replacement(seed) ~= nil
	return seed._sup
end

-- There for the player to see, or already replaced by something they recorded.
local function Known(seed)
	if ns.db.hidden[seed.k] then
		return false
	end
	if seed.builtin and not ns:GetSetting("useSeedData") then
		return false
	end
	return ns.Exploration:IsExplored(seed.c, seed.x, seed.y)
end

function Seeds:IsRevealed(seed)
	return Known(seed) and not IsSuperseded(seed)
end

-- An NPC only seen from across a room is recorded where the player stood, so
-- everyone at one counter lands on the same spot. Where a built-in location
-- already marks that kind of service close by, it is the better mark of where
-- they stand, and the rough sighting is not drawn on top of it. Talking to the
-- NPC places it properly, and then it replaces the built-in one instead.
local covers = setmetatable({}, { __mode = "k" })

function Seeds:Covers(rec, catID)
	if rec.kind ~= "npc" or catID == "flight" or (rec.a or 30) <= ACCURATE_YARDS then
		return false
	end
	local cached = covers[rec]
	if not cached or cached.version ~= coverVersion then
		cached = { version = coverVersion }
		covers[rec] = cached
	end
	if cached[catID] == nil then
		local reach, found = math.max(SUPERSEDE_YARDS, (rec.a or 30) + 8), false
		Query(rec.c, rec.x - reach, rec.x + reach, rec.y - reach, rec.y + reach, function(seed)
			if not found and seed.cats[catID] and Known(seed)
				and ns.Distance(rec.x, rec.y, seed.x, seed.y) <= reach then
				found = true
			end
		end)
		cached[catID] = found
	end
	return cached[catID]
end

-- Calls fn(seed) for every revealed built-in location in the box.
function Seeds:Query(cont, minX, maxX, minY, maxY, fn)
	Query(cont, minX, maxX, minY, maxY, function(seed)
		if self:IsRevealed(seed) then
			fn(seed)
		end
	end)
end

function Seeds:Hide(seed)
	ns.db.hidden[seed.k] = true
	ns:Fire("POI_REMOVED", seed)
end

function Seeds:CountRevealed()
	local n = 0
	for i = 1, #all do
		if self:IsRevealed(all[i]) then
			n = n + 1
		end
	end
	return n
end

end)
