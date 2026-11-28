-- Indoor view: inside a building, cave or tunnel the world map shows only the
-- roof, or the hill above you. The game keeps a small picture of every room of
-- every building: the ones its corner minimap draws indoors. While you're
-- indoors, an inset in a corner of the map draws the rooms around you from
-- those pictures, north up, with you in the middle.
--
-- Data\Interiors.lua, made by tools/build_interiors.py from the game's own
-- files, says where each building stands and where each room's pictures go.
--
-- What is known and what is worked out. Where you stand is known
-- (UnitPosition), and so is the building under you and which of its rooms
-- have floor there (each room's floor plan, read from its pictures). How high
-- you stand is not: Forever gives addons no usable height. Where rooms stand
-- over one another (an inn's upper floor over its tap room), the floor shown
-- is inferred, like this:
--   * Coming in from outside, you're on the ground floor: the lowest floor near
--     you with a door to the outside (else the nearest to it with a room where
--     you are).
--   * Staircases change it. The data has, for each square yard of a
--     staircase (or a ramp in a cave), how far up it is, traced from the
--     rooms' walkable surfaces. Step onto one at the end on the floor shown and
--     climb past 60% of it (or go down past 40%), and the floor changes. Where
--     you're on a staircase but not from that end (walking under its upper
--     half, or along a landing beside it), and wherever its height jumps more
--     than a step, you're taken to be passing over or under it.
--   * Otherwise it stays while you're in the same room. Walking into another
--     room, the floor stays if a room of the floor shown has floor there, and
--     else becomes that room's: preferably one with a doorway (portal) from the
--     room you were in.
--   * Small floor buttons let you pick a floor; your pick holds until you walk
--     a few yards on or take a staircase, and the guessing goes on from it.
-- None of this can see a ladder, a lift or a fall, and a staircase the data
-- missed changes nothing until you walk into a room of another floor: the
-- buttons are there for those.
local _, ns = ...
local Interiors = ns:NewModule("Interiors")
local Guarded = ns.Guarded or function(fn) return fn end -- each error once, not every frame (Core.lua)

local floor, max, min, abs, huge = math.floor, math.max, math.min, math.abs, math.huge
local cos, sin, rad = math.cos, math.sin, math.rad

local CELL = 2            -- yards per square of a room's floor plan
local BLOCK = 128         -- yards per picture block
local GRID = 256          -- yards per square of the lookup grid
local ZOOMS = { 30, 45, 70, 100, 150, 220 } -- yards across the view
local DEFAULT_ZOOM = 3
local PICKED_REACH = 6    -- yards you walk before a floor you picked gives way
local GRACE = 5           -- yards past the last room before the view lets go
local TRACK_EVERY = 0.2   -- seconds between checks while the map is closed
local DRAW_EVERY = 0.05   -- and while an inset shows
local ARROW = 20          -- pixels
local MAX_FLOOR_BUTTONS = 8
local ZONE_INSET = 104    -- pixels: the inset on the zone map (Shift+M), which is 300 by 200
local NEAR_FLOORS = 30    -- yards: the floors of rooms this close are "this building's"

---------------------------------------------------------------------------
-- The data, decoded a building at a time
---------------------------------------------------------------------------
local DIGITS = {}
do
	local alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+/"
	for i = 1, #alphabet do DIGITS[alphabet:byte(i)] = i - 1 end
end

local function Data()
	return ns.InteriorData
end

local models = {} -- index -> decoded model

-- A kind of building: its places (each a list of floor labels, bottom up, and
-- which is the ground floor) and its rooms. See Data\Interiors.lua for the
-- packed form.
local function Model(index)
	local model = models[index]
	if model ~= nil then return model or nil end
	local source = Data() and Data().models[index]
	if not source then
		models[index] = false
		return nil
	end
	model = { places = {}, rooms = {} }
	for labels in (source[1] .. "|"):gmatch("([^|]*)|") do
		local place = { ground = 1 }
		for label in labels:gmatch("[^,]+") do
			place[#place + 1] = label
			if label == "G" then place.ground, place.hasGround = #place, true end
		end
		model.places[#model.places + 1] = place
	end
	local minX, minY, maxX, maxY = huge, huge, -huge, -huge
	for i = 2, #source do
		local r = source[i]
		local room = {
			x = r[1], y = r[2], columns = r[3], rows = r[4], place = r[5], floor = r[6],
			shown = r[7], faint = r[8], bits = r[9], near = r[10], pictures = {},
		}
		room.x1, room.y1 = room.x + room.columns * CELL, room.y + room.rows * CELL
		room.area = room.columns * room.rows
		room.isNear = {}
		for _, n in ipairs(room.near) do room.isNear[n] = true end
		room.door = r[11] == 1
		for k = 12, #r - 2, 3 do
			local block, size = r[k + 1], r[k + 2]
			-- The picture is 2 pixels a yard; its bottom left is the block's corner.
			room.pictures[#room.pictures + 1] = {
				file = r[k],
				x = room.x + (block % 16) * BLOCK, y = room.y + floor(block / 16) * BLOCK,
				w = 2 ^ (size % 16) / 2, h = 2 ^ floor(size / 16) / 2,
			}
		end
		model.rooms[#model.rooms + 1] = room
		minX, minY = min(minX, room.x), min(minY, room.y)
		maxX, maxY = max(maxX, room.x1), max(maxY, room.y1)
	end
	model.minX, model.minY, model.maxX, model.maxY = minX, minY, maxX, maxY
	-- Staircases: place, the floors at its foot and head, its corner, size
	-- and, per square row by row, how far up it is in tenths; a letter is a
	-- run of squares that aren't on it ("a" one, "b" two ...), "." one.
	model.stairs = {}
	local size = Data().stairCell or 1
	for _, s in ipairs(source.stairs or {}) do
		local stair = {
			place = s[1], low = s[2], high = s[3], x = s[4], y = s[5], columns = s[6], rows = s[7],
			size = size, up = {},
		}
		local index = 0
		for k = 1, #s[8] do
			local byte = s[8]:byte(k)
			if byte >= 48 and byte <= 57 then
				stair.up[index] = (byte - 48 + 0.5) / 10
				index = index + 1
			elseif byte >= 97 and byte <= 122 then
				index = index + byte - 96
			else
				index = index + 1
			end
		end
		model.stairs[#model.stairs + 1] = stair
	end
	models[index] = model
	return model
end

-- How far up a staircase (a, b) is, 0 to 1; nil off it. A square with
-- nothing (a gap in the data) takes the squares around it.
local function StepAt(stair, i, j)
	if i < 0 or j < 0 or i >= stair.columns or j >= stair.rows then return end
	return stair.up[j * stair.columns + i]
end

local function UpStair(stair, a, b)
	local i, j = floor((a - stair.x) / stair.size), floor((b - stair.y) / stair.size)
	local t = StepAt(stair, i, j)
	if t then return t end
	local sum, count = 0, 0
	for dj = -1, 1 do
		for di = -1, 1 do
			local near = StepAt(stair, i + di, j + dj)
			if near then sum, count = sum + near, count + 1 end
		end
	end
	if count > 0 then return sum / count end
end

-- Whether floor plan square (i, j) of a room has floor in it.
local function Filled(room, i, j)
	if i < 0 or j < 0 or i >= room.columns or j >= room.rows then return false end
	local index = j * room.columns + i
	local byte = room.bits:byte(floor(index / 6) + 1)
	if not byte then return false end -- (trailing empty squares are left off)
	return floor((DIGITS[byte] or 0) / 2 ^ (index % 6)) % 2 == 1
end

-- Whether a room has floor at (a, b), in the building's own yards, or within
-- `slack` squares of it.
local function Covers(room, a, b, slack)
	local reach = slack * CELL
	if a < room.x - reach or a > room.x1 + reach or b < room.y - reach or b > room.y1 + reach then
		return false
	end
	local i, j = floor((a - room.x) / CELL), floor((b - room.y) / CELL)
	for dj = -slack, slack do
		for di = -slack, slack do
			if Filled(room, i + di, j + dj) then return true end
		end
	end
	return false
end

local function OnFloor(mask, floorIndex)
	return floor(mask / 2 ^ (floorIndex - 1)) % 2 == 1
end

---------------------------------------------------------------------------
-- Where buildings stand
---------------------------------------------------------------------------
-- placed[continent] is a flat list: model, north, west, yaw (degrees), scale.
local grids = {} -- continent -> { [square] = { placement, ... } }

-- A point (a, b) of the building is at
--   north = N - (a cos(yaw) - b sin(yaw)) * scale
--   west  = W - (a sin(yaw) + b cos(yaw)) * scale
-- and this is the way back.
local function ToLocal(placement, north, west)
	local dn, dw = (north - placement.north) / placement.scale, (west - placement.west) / placement.scale
	local c, s = placement.cos, placement.sin
	return -(dn * c + dw * s), dn * s - dw * c
end
Interiors.ToLocal = ToLocal

local function ToWorld(placement, a, b)
	local c, s, k = placement.cos, placement.sin, placement.scale
	return placement.north - (a * c - b * s) * k, placement.west - (a * s + b * c) * k
end
Interiors.ToWorld = ToWorld

local function Square(north, west)
	return floor(north / GRID) * 1000 + floor(west / GRID)
end

-- The lookup grid of a continent, made the first time it's needed: every
-- square a building's rooms reach lists that building.
-- A model's outline in its own yards, read without decoding the rest of it.
local outlines = {}
local function Outline(index)
	local outline = outlines[index]
	if outline ~= nil then return outline or nil end
	local source = Data() and Data().models[index]
	outline = false
	if source and source[2] then
		local minX, minY, maxX, maxY = huge, huge, -huge, -huge
		for i = 2, #source do
			local r = source[i]
			minX, minY = min(minX, r[1]), min(minY, r[2])
			maxX, maxY = max(maxX, r[1] + r[3] * CELL), max(maxY, r[2] + r[4] * CELL)
		end
		outline = { minX = minX, minY = minY, maxX = maxX, maxY = maxY }
	end
	outlines[index] = outline
	return outline or nil
end

local function Grid(cont)
	local grid = grids[cont]
	if grid ~= nil then return grid or nil end
	local list = Data() and Data().placed[cont]
	if not list then
		grids[cont] = false
		return nil
	end
	grid = {}
	for k = 1, #list - 4, 5 do
		local model = Outline(list[k])
		if model then
			local yaw = rad(list[k + 3])
			local placement = {
				model = list[k], north = list[k + 1], west = list[k + 2], yaw = yaw,
				scale = list[k + 4], cos = cos(yaw), sin = sin(yaw),
			}
			local n0, n1, w0, w1 = huge, -huge, huge, -huge
			for _, corner in ipairs({ { model.minX, model.minY }, { model.maxX, model.minY },
				{ model.minX, model.maxY }, { model.maxX, model.maxY } }) do
				local n, w = ToWorld(placement, corner[1], corner[2])
				n0, n1, w0, w1 = min(n0, n), max(n1, n), min(w0, w), max(w1, w)
			end
			for gn = floor(n0 / GRID), floor(n1 / GRID) do
				for gw = floor(w0 / GRID), floor(w1 / GRID) do
					local key = gn * 1000 + gw
					local cell = grid[key]
					if not cell then
						cell = {}
						grid[key] = cell
					end
					cell[#cell + 1] = placement
				end
			end
		end
	end
	grids[cont] = grid
	return grid
end

---------------------------------------------------------------------------
-- Floors near you
---------------------------------------------------------------------------
-- A place is every room that opens into another, so in a city it can be a
-- whole district of buildings on a hillside, its floors counted through all
-- of them. The buttons and their labels only count the floors of rooms near
-- you: G is the lowest of them with a door to the outside near you, then 2, 3
-- above and B (or B1, B2 ...) below; with no door near, 1, 2, 3 from the bottom.
local function Distance(room, a, b)
	local dx = max(room.x - a, 0, a - room.x1)
	local dy = max(room.y - b, 0, b - room.y1)
	return (dx * dx + dy * dy) ^ 0.5
end

-- Floors of `place` with a room near (a, b), bottom up, and the near ground floor.
local function NearFloors(model, place, a, b, list, also)
	for i = #list, 1, -1 do list[i] = nil end
	local seen, ground = {}, nil
	for _, room in ipairs(model.rooms) do
		if room.place == place and Distance(room, a, b) <= NEAR_FLOORS then
			if not seen[room.floor] then
				seen[room.floor] = true
				list[#list + 1] = room.floor
			end
			if room.door and (not ground or room.floor < ground) then ground = room.floor end
		end
	end
	if also and not seen[also] then list[#list + 1] = also end
	table.sort(list)
	return list, ground
end

-- Labels for the floors in `list` (bottom up), by floor number.
local function Labels(list, ground, labels)
	for k in pairs(labels) do labels[k] = nil end
	local at
	for i, f in ipairs(list) do
		if f == ground then at = i end
	end
	for i, f in ipairs(list) do
		if not at then
			labels[f] = tostring(i)
		elseif i == at then
			labels[f] = "G"
		elseif i > at then
			labels[f] = tostring(i - at + 1)
		else
			labels[f] = at == 2 and "B" or "B" .. (at - i)
		end
	end
	return labels
end

---------------------------------------------------------------------------
-- Which room you're in, and which floor to show
---------------------------------------------------------------------------
-- One state for the whole game: every inset shows the same building and floor.
local state = {}
Interiors.state = state

local function Clear()
	state.placement, state.model, state.room, state.place, state.floor = nil, nil, nil, nil, nil
	state.picked, state.pickedNorth, state.pickedWest = nil, nil, nil
	state.stairs, state.stairSpots = {}, {}
	state.version = (state.version or 0) + 1
end
Clear()

local function Changed()
	state.version = state.version + 1
end

-- The rooms of a building with floor at (a, b): exactly there, else nearby.
local function RoomsAt(model, a, b, list)
	for i = #list, 1, -1 do list[i] = nil end
	for slack = 0, 1 do
		for index, room in ipairs(model.rooms) do
			if Covers(room, a, b, slack) then list[#list + 1] = index end
		end
		if list[1] then return list end
	end
	return list
end

local function GroundOf(model, room)
	local place = model.places[room.place]
	return place and place.ground or 1
end

-- Coming in: the room on the ground floor near you, else the nearest floor
-- to it; the smaller room where two tie (a room inside a bigger one's outline).
local enterFloors = {}
local function EnterScore(model, room, a, b)
	local _, ground = NearFloors(model, room.place, a, b, enterFloors)
	return abs(room.floor - (ground or GroundOf(model, room))) * 1e6 + room.area
end

-- Moving on from the room you were in: a room of the floor shown (its own
-- before a hall open to it from below), else the room you were in, else one
-- it has a doorway to, else one a doorway further on, else the nearest floor
-- of the place.
local function MoveScore(model, room, index, from, place, shown)
	local score
	if room.place == place and OnFloor(room.shown, shown) then
		score = room.floor == shown and 0 or 1
	elseif room == from then
		score = 5
	elseif from and from.isNear[index] then
		score = 10
	else
		for _, n in ipairs(from and from.near or {}) do
			if model.rooms[n].isNear[index] then score = 20; break end
		end
		if not score then
			if room.place == place then
				score = 30 + abs(room.floor - shown)
			else
				score = 100 + abs(room.floor - GroundOf(model, room))
			end
		end
	end
	return score * 1e6 + room.area
end

local candidates = {}

-- Staircases under (a, b) in the place you're in. Each remembers how you got
-- onto it: from its foot on the floor shown ("low"), from its head ("high"),
-- or not from an end of the floor shown: passing over or under it (false),
-- until you reach such an end. A gap of a yard or two in its squares (where
-- it passes over itself) doesn't count as leaving it.
local STAIR_GAP = 2
function Interiors:Climb(a, b)
	local model = state.model
	for _, stair in ipairs(model.stairs) do
		if stair.place == state.place then
			local t = UpStair(stair, a, b)
			local last = state.stairSpots[stair]
			if not t and last and (a - last[1]) ^ 2 + (b - last[2]) ^ 2 <= STAIR_GAP * STAIR_GAP then
				-- in a gap: still on it, nothing changes
			elseif t then
				local on = state.stairs[stair]
				-- Climbing, the height changes a little at a time. A jump means
				-- you've stepped under or over another part of it (the foot of a
				-- staircase that turns back on itself is beside its head).
				if on and last and abs(t - last[3]) > 0.25 + 0.15 * ((a - last[1]) ^ 2 + (b - last[2]) ^ 2) ^ 0.5 then
					on = false
				end
				state.stairSpots[stair] = { a, b, t }
				-- Not climbing it: are you at the end that's on the floor shown?
				-- (Walking under its top half to its foot, you are, once there.)
				if not on then
					if state.floor == stair.low and t <= 0.35 then
						on = "low"
					elseif state.floor == stair.high and t >= 0.65 then
						on = "high"
					else
						on = false
					end
				end
				if on == "low" and t >= 0.6 then
					state.floor, on, state.picked = stair.high, "high", nil
					Changed()
				elseif on == "high" and t <= 0.4 then
					state.floor, on, state.picked = stair.low, "low", nil
					Changed()
				end
				state.stairs[stair] = on
			else
				state.stairs[stair], state.stairSpots[stair] = nil, nil
			end
		end
	end
end

-- The room you're in, from those with floor at (a, b). While you're still in
-- the room you were in, the floor stays (a staircase or your pick may have
-- just changed it); a room of the floor shown that has floor here is taken
-- instead, if there is one. Walking into another room, the floor follows it
-- when it isn't on the floor shown (but not while a floor you picked holds).
-- You can only walk into a room through a doorway: one of another floor
-- that isn't a doorway or two from yours (the room over the stairwell you
-- stand in) is taken only once you're well away from your own room.
local STRAY = 6 -- yards
function Interiors:Settle(a, b)
	local model = state.model
	local room = model.rooms[state.room]
	local staying = room.place == state.place and Covers(room, a, b, 1)
	if staying and OnFloor(room.shown, state.floor) then return end
	RoomsAt(model, a, b, candidates)
	local best, bestScore
	for _, index in ipairs(candidates) do
		local candidate = model.rooms[index]
		if not staying or (candidate.place == state.place and OnFloor(candidate.shown, state.floor)) then
			local score = MoveScore(model, candidate, index, room, state.place, state.floor)
			if not bestScore or score < bestScore then best, bestScore = index, score end
		end
	end
	if not best then return end -- between rooms, or staying: keep the last
	if bestScore >= 30e6 and Distance(room, a, b) <= STRAY then return end -- (no doorway to it from here)
	local new = model.rooms[best]
	local was, wasFloor, wasPlace = state.room, state.floor, state.place
	state.room = best
	if new.place ~= state.place then
		state.place, state.floor, state.picked = new.place, new.floor, nil
		state.stairs, state.stairSpots = {}, {}
	elseif not state.picked and not OnFloor(new.shown, state.floor) then
		state.floor = new.floor
	end
	if state.room ~= was or state.floor ~= wasFloor or state.place ~= wasPlace then Changed() end
end

-- Finds the building and room under (north, west) and the floor to show.
-- Returns whether there is a building.
function Interiors:Track(cont, north, west)
	local placement, model = state.placement, state.model
	local a, b
	if placement and state.cont == cont then
		a, b = ToLocal(placement, north, west)
		if not Covers(model.rooms[state.room], a, b, 1) and not RoomsAt(model, a, b, candidates)[1] then
			placement = nil -- out of this building: look for another
		end
	else
		placement = nil
	end
	if not placement then
		-- A building under you, and the room to start in.
		local grid = Grid(cont)
		local cell = grid and grid[Square(north, west)]
		local best, bestScore
		for _, candidate in ipairs(cell or {}) do
			local o = Outline(candidate.model)
			local ca, cb = ToLocal(candidate, north, west)
			if ca >= o.minX - CELL and ca <= o.maxX + CELL and cb >= o.minY - CELL and cb <= o.maxY + CELL then
				local m = Model(candidate.model)
				for _, index in ipairs(RoomsAt(m, ca, cb, candidates)) do
					local score = EnterScore(m, m.rooms[index], ca, cb)
					if not bestScore or score < bestScore then
						best, bestScore, placement, a, b = index, score, candidate, ca, cb
					end
				end
			end
		end
		if not best then
			-- Between rooms (a doorway the floor plans miss, a step outside
			-- them): stay with the last building for a few yards.
			if state.placement and state.cont == cont and state.lastNorth
				and ns.Distance(north, west, state.lastNorth, state.lastWest) <= GRACE then
				return true
			end
			if state.placement then Clear() end
			return false
		end
		Clear()
		model = Model(placement.model)
		local room = model.rooms[best]
		state.cont, state.placement, state.model, state.room = cont, placement, model, best
		state.place, state.floor = room.place, room.floor
	end
	state.lastNorth, state.lastWest = north, west
	self:KeepPicked(north, west)
	self:Climb(a, b)
	self:Settle(a, b)
	return true
end

-- A floor you picked holds until you've walked a few yards from where you
-- picked it; then the guessing goes on from it.
function Interiors:KeepPicked(north, west)
	if not state.picked then return end
	if not state.pickedNorth then
		state.pickedNorth, state.pickedWest = north, west
	elseif ns.Distance(north, west, state.pickedNorth, state.pickedWest) > PICKED_REACH then
		state.picked, state.pickedNorth, state.pickedWest = nil, nil, nil
	end
end

function Interiors:ShownFloor()
	return state.floor
end

-- Show another floor of the place you're in. If a room of that floor has
-- floor where you stand, you're taken to be in it from now on.
function Interiors:PickFloor(floorIndex)
	local model, placement = state.model, state.placement
	if not model then return end
	local place = model.places[state.place]
	if not place or floorIndex < 1 or floorIndex > #place then return end
	state.floor, state.picked = floorIndex, true
	state.pickedNorth, state.pickedWest = state.lastNorth, state.lastWest
	state.stairs, state.stairSpots = {}, {}
	if state.lastNorth then
		local a, b = ToLocal(placement, state.lastNorth, state.lastWest)
		local best, bestScore
		for index, room in ipairs(model.rooms) do
			if room.place == state.place and OnFloor(room.shown, floorIndex) and Covers(room, a, b, 1) then
				local score = (room.floor == floorIndex and 0 or 1e6) + room.area
				if not bestScore or score < bestScore then best, bestScore = index, score end
			end
		end
		if best then state.room = best end
	end
	Changed()
end

-- The floors near you, bottom up, and a label for each (by floor number).
local nearList, nearLabels = {}, {}
function Interiors:NearFloors()
	local model = state.model
	if not model or not state.lastNorth then return {}, {} end
	local a, b = ToLocal(state.placement, state.lastNorth, state.lastWest)
	local list, ground = NearFloors(model, state.place, a, b, nearList, state.floor)
	if not ground then
		-- No door near: the place's own ground floor, if it's one of these.
		local place = model.places[state.place]
		for _, f in ipairs(list) do
			if place and place.hasGround and f == place.ground then ground = f end
		end
	end
	return list, Labels(list, ground, nearLabels)
end

-- Floors of the place you're in that have a room where you stand: a set.
function Interiors:FloorsHere(set)
	local model, placement = state.model, state.placement
	if not model or not state.lastNorth then return set end
	local a, b = ToLocal(placement, state.lastNorth, state.lastWest)
	for _, room in ipairs(model.rooms) do
		if room.place == state.place and Covers(room, a, b, 1) then
			local place = model.places[room.place] or {}
			for f = 1, #place do
				if OnFloor(room.shown, f) then set[f] = true end
			end
		end
	end
	return set
end

---------------------------------------------------------------------------
-- Reading the player
---------------------------------------------------------------------------
local function Number(v)
	return ns.Readable(v) and type(v) == "number" and v == v and v > -huge and v < huge
end

local function PlayerPosition()
	if UnitPosition then
		local ok, north, west, _, cont = pcall(UnitPosition, "player")
		if ok and Number(north) and Number(west) and Number(cont) then return cont, north, west end
	end
	local cont, north, west = ns.GetPlayerWorld()
	if cont then return cont, north, west end
end

local function Indoors()
	local indoors = IsIndoors and IsIndoors()
	if ns.Readable(indoors) then return indoors and true or false end
end

-- The x hides the view until you next come in from outside.
local dismissed, seenOutside = false, false
local refreshedAt

function Interiors:Dismiss()
	dismissed, seenOutside = true, false
	refreshedAt = nil -- (now, not at the next read)
	state.version = (state.version or 0) + 1
end

function Interiors:IsDismissed() return dismissed end

-- Reads where you are and updates the state; at most once each `every` seconds.
function Interiors:Refresh(every)
	local now = GetTime()
	if refreshedAt and now - refreshedAt < (every or 0) then return state.visible end
	refreshedAt = now
	local visible = false
	local indoors = ns:GetSetting("indoorView") and Data() and Indoors()
	if indoors == false then
		if dismissed then seenOutside = true end
		if state.placement then Clear() end
	elseif indoors then
		if dismissed and seenOutside then dismissed = false end
		local cont, north, west = PlayerPosition()
		if cont and self:Track(cont, north, west) then
			self.lastNorth, self.lastWest, self.lastCont = north, west, cont
			visible = not dismissed
		end
	end
	state.visible = visible
	return visible
end

---------------------------------------------------------------------------
-- The inset
---------------------------------------------------------------------------
local Inset = {}
Inset.__index = Inset
local insets = {}
Interiors.insets = insets

local FONT = "GameFontNormalSmall"

local function SmallButton(parent, text, tooltip, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(16, 16)
	button:SetFrameLevel(parent:GetFrameLevel() + 3) -- over the rooms
	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0, 0, 0, 0.6)
	button.background = background
	local label = button:CreateFontString(nil, "OVERLAY", FONT)
	label:SetPoint("CENTER", 0, 0)
	label:SetText(text)
	button.label = label
	button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(type(tooltip) == "function" and tooltip(self) or tooltip, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return button
end

local function NoSnap(texture)
	if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
	if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
end

-- options: point, x, y (where the inset sits on its parent; default its
-- bottom right), size (pixels; default a third of the parent's shorter side)
-- and enabled (a function; while it returns false the inset stays hidden).
function Interiors:CreateInset(parent, options)
	options = options or {}
	local inset = setmetatable({ parent = parent, options = options, zoom = DEFAULT_ZOOM,
		textures = {}, used = 0, floorButtons = {} }, Inset)

	-- The driver runs while the parent shows, so the inset can come and go.
	local driver = CreateFrame("Frame", nil, parent)
	driver:SetSize(1, 1)
	driver:SetPoint("BOTTOMRIGHT")
	driver:EnableMouse(false)
	driver:SetScript("OnUpdate", Guarded(function() inset:Update() end, "Wayfinder indoor view"))
	inset.driver = driver

	local frame = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	frame:SetPoint(options.point or "BOTTOMRIGHT", parent, options.point or "BOTTOMRIGHT", options.x or -6, options.y or 6)
	frame:SetFrameLevel(parent:GetFrameLevel() + (options.level or 1500))
	frame:EnableMouse(true)
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta) inset:Zoom(delta > 0 and -1 or 1) end)
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Indoor view", 1, 1, 1)
		GameTooltip:AddLine("The rooms around you, north up. Scroll to zoom.", nil, nil, nil, true)
		GameTooltip:AddLine("The floor is worked out from the stairs and doorways you take; if it's wrong, pick one with the buttons on the left.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		frame:SetBackdropColor(0.03, 0.03, 0.04, 0.92)
		frame:SetBackdropBorderColor(0.85, 0.7, 0.35, 1)
	end
	frame:Hide()
	inset.frame = frame

	-- The rooms, cut off at the frame's edge.
	local view = CreateFrame("Frame", nil, frame)
	view:SetFrameLevel(frame:GetFrameLevel() + 1)
	view:SetPoint("TOPLEFT", 4, -4)
	view:SetPoint("BOTTOMRIGHT", -4, 4)
	view:SetClipsChildren(true)
	inset.view = view

	local arrow = view:CreateTexture(nil, "OVERLAY")
	arrow:SetTexture(ns.Categories:GetMediaPath("PlayerArrow"))
	arrow:SetSize(ARROW, ARROW)
	arrow:SetPoint("CENTER", view, "CENTER", 0, 0)
	inset.arrow = arrow

	-- Out, in and close in the top right corner.
	inset.close = SmallButton(frame, "x", "Hide the indoor view until you next go indoors.", function()
		Interiors:Dismiss()
	end)
	inset.close:SetPoint("TOPRIGHT", -5, -5)
	inset.zoomIn = SmallButton(frame, "+", "Zoom in", function() inset:Zoom(-1) end)
	inset.zoomIn:SetPoint("RIGHT", inset.close, "LEFT", -2, 0)
	inset.zoomOut = SmallButton(frame, "-", "Zoom out", function() inset:Zoom(1) end)
	inset.zoomOut:SetPoint("RIGHT", inset.zoomIn, "LEFT", -2, 0)

	insets[#insets + 1] = inset
	return inset
end

function Inset:Zoom(step)
	local zoom = max(1, min(#ZOOMS, self.zoom + step))
	if zoom ~= self.zoom then
		self.zoom = zoom
		self.drawn = nil
	end
end

function Inset:YardsAcross()
	return ZOOMS[self.zoom]
end

function Inset:Size()
	if self.options.size then return self.options.size end
	local w, h = self.parent:GetWidth() or 0, self.parent:GetHeight() or 0
	return floor(max(120, min(280, min(w, h) * 0.32)))
end

local function FloorTooltip(button)
	local inset, index = button.inset, button.floorIndex
	local label = button.label.text or button.floorLabel or "?"
	local name = label == "G" and "the ground floor" or label:sub(1, 1) == "B" and "basement " .. label
		or "floor " .. label
	local text = "Show " .. name .. "."
	if not inset.here[index] then text = text .. "\nNo room of it where you stand." end
	return text .. "\nYour pick stays until you walk on a few yards."
end

function Inset:FloorButton(index)
	local button = self.floorButtons[index]
	if button then return button end
	button = SmallButton(self.frame, "", FloorTooltip, function(b) Interiors:PickFloor(b.floorIndex) end)
	button:SetSize(20, 16)
	button.inset = self
	self.floorButtons[index] = button
	return button
end

-- Floor buttons up the left side, bottom floor at the bottom, like a lift's:
-- the one shown lit, those with no room where you stand dimmed.
function Inset:LayoutFloors()
	self.here = self.here or {}
	for k in pairs(self.here) do self.here[k] = nil end
	local list, labels = Interiors:NearFloors()
	local count = #list
	if count < 2 then count = 0 end
	Interiors:FloorsHere(self.here)
	local shown = Interiors:ShownFloor()
	local first, at = 1, 1
	for i, f in ipairs(list) do
		if f == shown then at = i end
	end
	-- As many as fit up the side (a small inset holds fewer).
	local most = max(2, min(MAX_FLOOR_BUTTONS, floor(((self.size or 0) - 26) / 18) + 1))
	if count > most then -- (keep the shown floor among them)
		first = max(1, min(count - most + 1, at - floor(most / 2)))
	end
	local slot = 0
	for position = first, min(count, first + most - 1) do
		local index = list[position]
		slot = slot + 1
		local button = self:FloorButton(slot)
		button.floorIndex = index
		button.floorLabel = labels[index]
		button.label:SetText(labels[index])
		button:ClearAllPoints()
		button:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 5, 5 + (slot - 1) * 18)
		if index == shown then
			button.background:SetColorTexture(0.85, 0.65, 0.2, 0.9)
			button.label:SetTextColor(0, 0, 0)
		else
			button.background:SetColorTexture(0, 0, 0, 0.6)
			local bright = self.here[index] and 1 or 0.45
			button.label:SetTextColor(bright, bright * 0.82, 0)
		end
		button:Show()
	end
	for slotIndex = slot + 1, #self.floorButtons do self.floorButtons[slotIndex]:Hide() end
end

function Inset:Texture(index)
	local texture = self.textures[index]
	if not texture then
		texture = self.view:CreateTexture(nil, "ARTWORK")
		NoSnap(texture)
		self.textures[index] = texture
	end
	return texture
end

-- Two ways to draw a picture turned with its building. "coords" (the usual):
-- the texture covers the box around the turned picture, and its corners are
-- given the picture positions that land there; outside the picture they are
-- out of range and clamped to clear. "rotate": the texture is the picture's
-- own size and SetRotation turns it. /wf indoors rotate switches, in case a
-- client draws one of them wrong.
Interiors.drawMode = "coords"

local function SetFile(texture, file)
	if texture.interiorFile ~= file then
		texture.interiorFile = file
		texture:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "LINEAR")
	end
end

local corners = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }
function Inset:Picture(picture, placement, ox, oy, k, alpha, layer, half)
	local c, s, scale = placement.cos, placement.sin, placement.scale * k
	-- A point (a, b) of the building lies at x = ox + (s a + c b) scale (east),
	-- y = oy + (s b - c a) scale (north), in pixels from the view's middle.
	local left, right, bottom, top = huge, -huge, huge, -huge
	for _, corner in ipairs(corners) do
		local a, b = picture.x + corner[1] * picture.w, picture.y + (1 - corner[2]) * picture.h
		local x, y = ox + (s * a + c * b) * scale, oy + (s * b - c * a) * scale
		left, right, bottom, top = min(left, x), max(right, x), min(bottom, y), max(top, y)
	end
	if right < -half or left > half or top < -half or bottom > half then return end
	self.used = self.used + 1
	local texture = self:Texture(self.used)
	SetFile(texture, picture.file)
	texture:SetDrawLayer("ARTWORK", layer)
	texture:SetVertexColor(1, 1, 1, alpha)
	texture:ClearAllPoints()
	texture:Show()
	if Interiors.drawMode == "rotate" then
		-- The picture's middle, and its right edge's heading on the map: the
		-- building's +x, which is the yaw less a quarter turn from east.
		local a, b = picture.x + picture.w / 2, picture.y + picture.h / 2
		texture:SetTexCoord(0, 1, 0, 1)
		texture:SetSize(picture.w * scale, picture.h * scale)
		texture:SetPoint("CENTER", self.view, "CENTER", ox + (s * a + c * b) * scale, oy + (s * b - c * a) * scale)
		texture:SetRotation(placement.yaw - math.pi / 2)
		return
	end
	if texture.SetRotation then texture:SetRotation(0) end
	local function UV(x, y)
		local dx, dy = (x - ox) / scale, (y - oy) / scale
		local a, b = s * dx - c * dy, c * dx + s * dy
		return (a - picture.x) / picture.w, 1 - (b - picture.y) / picture.h
	end
	local ulx, uly = UV(left, top)
	local llx, lly = UV(left, bottom)
	local urx, ury = UV(right, top)
	local lrx, lry = UV(right, bottom)
	texture:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
	texture:SetPoint("TOPLEFT", self.view, "CENTER", left, top)
	texture:SetSize(max(right - left, 0.01), max(top - bottom, 0.01))
end

function Inset:Draw()
	local placement, model = state.placement, state.model
	local width = self.view:GetWidth() or 0
	self.used = 0
	if placement and width > 0 then
		local k = width / self:YardsAcross() -- pixels per yard
		local north, west = Interiors.lastNorth, Interiors.lastWest
		local ox, oy = (west - placement.west) * k, (placement.north - north) * k
		local shown = Interiors:ShownFloor()
		local half = width / 2
		for _, room in ipairs(model.rooms) do
			if room.place == state.place then
				local alpha, layer
				if room.floor == shown then
					alpha, layer = 1, 0
				elseif OnFloor(room.shown, shown) then
					alpha, layer = 0.75, -1 -- open to this floor from below
				elseif OnFloor(room.faint, shown) then
					alpha, layer = 0.35, -2 -- another floor, with nothing over or under it here
				end
				if alpha then
					for _, picture in ipairs(room.pictures) do
						self:Picture(picture, placement, ox, oy, k, alpha, layer, half)
					end
				end
			end
		end
	end
	for index = self.used + 1, #self.textures do self.textures[index]:Hide() end
	self:LayoutFloors()
end

function Inset:Update()
	local frame = self.frame
	local enabled = self.options.enabled
	if (enabled and not enabled()) or not Interiors:Refresh(DRAW_EVERY) then
		if frame:IsShown() then frame:Hide() end
		self.drawn = nil
		return
	end
	local size = self:Size()
	if size ~= self.size then
		self.size = size
		frame:SetSize(size, size)
		self.drawn = nil
	end
	if not frame:IsShown() then frame:Show() end
	local north, west = Interiors.lastNorth, Interiors.lastWest
	if self.drawn ~= state.version or self.drawnNorth ~= north or self.drawnWest ~= west
		or self.drawnFloor ~= Interiors:ShownFloor() then
		self.drawn, self.drawnNorth, self.drawnWest, self.drawnFloor = state.version, north, west, Interiors:ShownFloor()
		self:Draw()
	end
	local facing = GetPlayerFacing and GetPlayerFacing()
	if Number(facing) then
		self.arrow:SetRotation(facing)
		self.arrow:Show()
	else
		self.arrow:Hide()
	end
end

---------------------------------------------------------------------------
-- Debugging and setup
---------------------------------------------------------------------------
function Interiors:Describe()
	if not Data() then return "No interior data loaded." end
	local indoors = Indoors()
	local cont, north, west = PlayerPosition()
	local text = ("indoors %s, position %s %s %s"):format(tostring(indoors), tostring(cont),
		north and ("%.1f"):format(north) or "?", west and ("%.1f"):format(west) or "?")
	if dismissed then text = text .. ", hidden with x" end
	local placement = state.placement
	if not placement then return text .. "; no building with room pictures here." end
	local model = state.model
	local a, b = ToLocal(placement, state.lastNorth, state.lastWest)
	local list, labels = self:NearFloors()
	local near = {}
	for i, f in ipairs(list) do near[i] = labels[f] end
	return text .. ("; building %d (%d rooms) at %.1f, %.1f yaw %.1f; you at %.1f, %.1f in its yards; room %d, place %d; floor %s (number %d) of %s near you%s; %d staircases")
		:format(placement.model, #model.rooms, placement.north, placement.west, math.deg(placement.yaw), a, b,
			state.room, state.place, tostring(labels[state.floor]), state.floor, table.concat(near, " "),
			state.picked and " (picked)" or "", #model.stairs)
end

-- /wf indoors [rotate]
function Interiors:Command(rest)
	if rest == "rotate" then
		self.drawMode = self.drawMode == "rotate" and "coords" or "rotate"
		for _, inset in ipairs(insets) do inset.drawn = nil end
		ns.Print("Indoor view draws rooms by " .. (self.drawMode == "rotate" and "turning each picture (SetRotation)."
			or "texture coordinates (the usual way)."))
		return
	end
	ns.Print(self:Describe())
end

function Interiors:OnLogin()
	EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", function()
		-- Left of the map's quest log toggle in its bottom right corner.
		self.worldMap = self:CreateInset(WorldMapFrame:GetCanvasContainer(), { x = -38, y = 4 })
	end)
	-- A smaller one in the zone map's (Shift+M) bottom right, with its other
	-- Wayfinder markings.
	EventUtil.ContinueOnAddOnLoaded("Blizzard_BattlefieldMap", function()
		if not (BattlefieldMapFrame and BattlefieldMapFrame.GetCanvasContainer) then return end
		self.zoneMap = self:CreateInset(BattlefieldMapFrame:GetCanvasContainer(), {
			size = ZONE_INSET, x = -4, y = 4,
			enabled = function() return ns:GetSetting("zoneMap") end,
		})
	end)
	-- Follow the rooms you walk through while the map is closed too, so the
	-- floor is right when it opens.
	if C_Timer and C_Timer.NewTicker then
		self.ticker = C_Timer.NewTicker(TRACK_EVERY,
			Guarded(function() Interiors:Refresh(TRACK_EVERY * 0.5) end, "Wayfinder indoor tracking"))
	end
	ns:On("SETTING_CHANGED", function(key)
		if key == "indoorView" then refreshedAt = nil end
	end)
end
