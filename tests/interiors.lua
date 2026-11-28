-- Indoor view: the building and room under the player, the floor shown, and
-- the inset that draws the rooms' pictures on a map.
local root = ...
local function noop() end
local function equal(actual, expected, label)
	assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function near(actual, expected, label, tolerance)
	assert(type(actual) == "number" and math.abs(actual - expected) < (tolerance or 1e-6),
		label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

---------------------------------------------------------------------------
-- Frames, textures and buttons that remember what was done to them
---------------------------------------------------------------------------
local methods = {}
local function New(parent)
	return setmetatable({ parent = parent, scripts = {}, shown = true, level = 1, children = {} },
		{ __index = methods })
end
function methods:SetScript(name, fn) self.scripts[name] = fn end
function methods:GetScript(name) return self.scripts[name] end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetPoint(point, relativeTo, relativePoint, x, y)
	self.points = self.points or {}
	if type(relativeTo) == "number" then -- SetPoint(point, x, y)
		relativeTo, relativePoint, x, y = nil, point, relativeTo, relativePoint
	end
	self.points[#self.points + 1] = { point, relativeTo, relativePoint, x or 0, y or 0 }
	self.point = self.points[#self.points]
end
function methods:ClearAllPoints() self.points = nil; self.point = nil end
-- A frame pinned at two corners of its parent is the parent's size less the
-- offsets; otherwise its own.
function methods:GetWidth()
	if self.width then return self.width end
	if self.points and #self.points == 2 and self.parent then
		return self.parent:GetWidth() + self.points[2][4] - self.points[1][4]
	end
	return 0
end
function methods:GetHeight()
	if self.height then return self.height end
	if self.points and #self.points == 2 and self.parent then
		return self.parent:GetHeight() - self.points[2][5] + self.points[1][5]
	end
	return 0
end
function methods:SetFrameLevel(level) self.level = level end
function methods:GetFrameLevel() return self.level end
function methods:SetTexture(file, wrapH, wrapV, filter) self.file, self.wrap, self.filter = file, { wrapH, wrapV }, filter end
function methods:SetTexCoord(...) self.coords = { ... } end
function methods:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
function methods:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function methods:SetDrawLayer(layer, sublevel) self.layer, self.sublevel = layer, sublevel end
function methods:SetRotation(angle) self.rotation = angle end
function methods:SetText(text) self.text = text end
function methods:SetTextColor(r, g, b) self.textColor = { r, g, b } end
function methods:CreateTexture() local t = New(self); self.children[#self.children + 1] = t; return t end
function methods:CreateFontString() return New(self) end
for _, name in ipairs({ "SetAllPoints", "EnableMouse", "EnableMouseWheel", "SetClipsChildren",
	"SetSnapToPixelGrid", "SetTexelSnappingBias", "SetHighlightTexture" }) do
	methods[name] = noop
end
function CreateFrame(_, _, parent)
	local frame = New(parent)
	if parent then frame.level = parent.level + 1 end
	return frame
end
GameTooltip = { SetOwner = noop, SetText = noop, AddLine = noop, Show = noop, Hide = noop }

local now = 0
function GetTime() return now end
local tickers = {}
C_Timer = { NewTicker = function(_, fn) tickers[#tickers + 1] = fn; return {} end }
EventUtil = { ContinueOnAddOnLoaded = function(_, fn) fn() end }
local canvas = New()
canvas.width, canvas.height, canvas.level = 900, 600, 10
WorldMapFrame = New()
function WorldMapFrame:GetCanvasContainer() return canvas end
local zoneCanvas = New()
zoneCanvas.width, zoneCanvas.height, zoneCanvas.level = 300, 200, 10
BattlefieldMapFrame = New()
function BattlefieldMapFrame:GetCanvasContainer() return zoneCanvas end

local indoors, north, west, cont, facing = true, 0, 0, 0, 0
function IsIndoors() return indoors end
function UnitPosition() return north, west, 0, cont end
function GetPlayerFacing() return facing end

local settings = { indoorView = true, zoneMap = true }
local function Namespace()
	local ns = { Categories = { GetMediaPath = function(_, name) return "Media\\" .. name end } }
	function ns:NewModule(name) self[name] = {}; return self[name] end
	function ns:GetSetting(key) return settings[key] end
	function ns:On() end
	function ns:RegisterEvent() end
	function ns.Readable(value) return value ~= nil end
	function ns.GetPlayerWorld() end
	function ns.Distance(a, b, c, d) return ((a - c) ^ 2 + (b - d) ^ 2) ^ 0.5 end
	function ns.Print(text) ns.printed = text end
	return ns
end
MiniQoLRuntime = { Execute = function(_, _, fn) return fn("Wayfinder", ns) end }

---------------------------------------------------------------------------
-- A two-storey inn with a cellar, in its own yards
---------------------------------------------------------------------------
-- Footprint squares, row by row, 6 to a character, lowest bit first.
local ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+/"
local function Bits(columns, rows, filled)
	local out, value, count = {}, 0, 0
	for j = 0, rows - 1 do
		for i = 0, columns - 1 do
			if filled(i, j) then value = value + 2 ^ count end
			count = count + 1
			if count == 6 then
				out[#out + 1] = ALPHABET:sub(value + 1, value + 1)
				value, count = 0, 0
			end
		end
	end
	if count > 0 then out[#out + 1] = ALPHABET:sub(value + 1, value + 1) end
	return table.concat(out)
end
local function All() return true end
-- size = log2(width) + 16 * log2(height) of the picture, in pixels
local function Size(w, h) return math.floor(math.log(w) / math.log(2) + 0.5) + 16 * math.floor(math.log(h) / math.log(2) + 0.5) end

-- Floors of the one place: B (1), G (2), 2 (3).
--   1 hall: 20 x 20 yards from (0, 0), on G and open to floor 2 above
--   2 side room: 10 x 10 from (20, 0), on G
--   3 upper room: 20 x 10 from (0, 0), on 2, over the hall's south half
--   4 cellar: 10 x 10 from (20, 0), on B, under the side room
-- Staircases: 1 from G to 2 along the hall's north side; 2 from B up to G in
-- the side room, its foot to the west.
local INN = {
	"B,G,2",
	{ 0, 0, 10, 10, 1, 2, 6, 0, Bits(10, 10, All), { 2, 3 }, 1, 1001, 0, Size(64, 64) },
	{ 20, 0, 5, 5, 1, 2, 2, 0, Bits(5, 5, All), { 1, 4 }, 0, 1002, 0, Size(32, 32) },
	{ 0, 0, 10, 5, 1, 3, 4, 0, Bits(10, 5, All), { 1 }, 0, 1003, 0, Size(64, 32) },
	{ 20, 0, 5, 5, 1, 1, 1, 0, Bits(5, 5, All), { 2 }, 0, 1004, 0, Size(32, 32) },
	-- 5 a balcony on floor 2 outside the hall's west wall, up a ladder: no doorway
	{ -6, 0, 3, 5, 1, 3, 4, 0, Bits(3, 5, All), {}, 0, 1005, 0, Size(16, 32) },
	stairs = {
		{ 1, 2, 3, 2, 14, 8, 2, "1234567812345678" },
		{ 1, 1, 2, 22, 2, 6, 1, "123468" },
	},
}
-- A cave with two levels that never pass over one another: drawn whole. Its
-- ramp up runs through the lower level's room, with a gap where the data has
-- no height (it passes over itself).
local CAVE = {
	"1,2|1",
	stairs = { { 1, 1, 2, 0, 4, 9, 1, "12c6789" }, { 1, 1, 2, 0, 0, 4, 2, "12349876" } },
	{ 0, 0, 5, 5, 1, 1, 1, 2, Bits(5, 5, All), { 2 }, 0, 2001, 0, Size(32, 32) },
	{ 10, 0, 5, 5, 1, 2, 2, 1, Bits(5, 5, All), { 1 }, 0, 2002, 0, Size(32, 32) },
	-- a big room cut into blocks: its second block starts 128 yards along
	{ 0, 200, 70, 2, 2, 1, 1, 0, Bits(70, 2, All), {}, 0, 2003, 0, Size(256, 8), 2004, 1, Size(16, 8) },
}
-- A district of a city model: one place, two houses 100 yards apart on a
-- slope, each a ground floor with a door and a floor over it. The place's
-- floors count through both (B, G, 2, 3); near either house, its two are G and 2.
local DISTRICT = {
	"B,G,2,3",
	{ 0, 0, 5, 5, 1, 1, 1, 0, Bits(5, 5, All), { 2 }, 1, 3001, 0, Size(32, 32) },
	{ 0, 0, 5, 5, 1, 2, 2, 0, Bits(5, 5, All), { 1 }, 0, 3002, 0, Size(32, 32) },
	{ 100, 0, 5, 5, 1, 3, 4, 0, Bits(5, 5, All), { 4 }, 1, 3003, 0, Size(32, 32) },
	{ 100, 0, 5, 5, 1, 4, 8, 0, Bits(5, 5, All), { 3 }, 0, 3004, 0, Size(32, 32) },
}
local YAW = 263
local data = {
	build = "test",
	models = { INN, CAVE, DISTRICT },
	-- the inn at north 1000, west 2000, turned 263 degrees; the cave far off
	placed = { [0] = { 1, 1000, 2000, YAW, 1, 2, 5000, 5000, 0, 1, 3, 8000, 8000, 0, 1 } },
}

local ns = Namespace()
ns.InteriorData = data
MiniQoLRuntime = { Execute = function(_, _, fn) return fn("Wayfinder", ns) end }
assert(loadfile(root .. "/Modules/Wayfinder/Interiors.lua"))("Wayfinder", ns)
local I = ns.Interiors
local state = I.state
local inn = { north = 1000, west = 2000, scale = 1, cos = math.cos(math.rad(YAW)), sin = math.sin(math.rad(YAW)) }
-- Stand at (a, b) in the inn's own yards.
local function At(a, b)
	north, west = I.ToWorld(inn, a, b)
	now = now + 1
	return I:Refresh(0)
end
local function Floor() return state.model.places[state.place][I:ShownFloor()] end

---------------------------------------------------------------------------
-- 1. The building's own yards and the world's
---------------------------------------------------------------------------
local n, w = I.ToWorld(inn, 3, 4)
local a, b = I.ToLocal(inn, n, w)
near(a, 3, "back from the world: a")
near(b, 4, "back from the world: b")
-- Turned 263 degrees, the building's +x points a little north of west.
n, w = I.ToWorld(inn, 10, 0)
near(n - 1000, -10 * math.cos(math.rad(YAW)), "+x 10 yards: north")
near(w - 2000, -10 * math.sin(math.rad(YAW)), "+x 10 yards: west")
assert(n > 1000 and w > 2000 + 9.9, "+x heads west, a touch north")

---------------------------------------------------------------------------
-- 2. Coming in: the ground floor; through a doorway: the side room
---------------------------------------------------------------------------
I:OnLogin()
assert(I.worldMap, "an inset on the world map")
equal(I.worldMap.parent, canvas, "on the map's canvas")
assert(I.zoneMap, "and a smaller one on the zone map")
equal(I.zoneMap.parent, zoneCanvas, "on the zone map's canvas")
equal(#tickers, 1, "a ticker follows the rooms while the map is closed")
assert(At(5, 5), "the hall, where the upper room is over it too")
equal(state.room, 1, "came in to the hall")
equal(Floor(), "G", "on the ground floor")
assert(At(25, 5), "into the side room")
equal(state.room, 2, "the side room, through the hall's doorway (not the cellar under it)")
equal(Floor(), "G", "still the ground floor")

-- A room of another floor with no doorway from yours is only taken once
-- you're well away from your own.
At(5, 5)
At(1, 5)
At(-3, 5)
equal(Floor(), "G", "past the hall's wall only the balcony has floor; no doorway to it: still G")
equal(state.room, 1, "and still the hall")
At(-7.5, 5)
equal(Floor(), "2", "well away from the hall: the balcony it must be")
indoors = false
At(25, 5)
indoors = true
At(25, 5)
equal(Floor(), "G", "back in through the side room")

---------------------------------------------------------------------------
-- 3. Down the cellar stairs from their head, and back up
---------------------------------------------------------------------------
At(27.5, 2.5) -- the staircase's head: 85% up
equal(Floor(), "G", "at the head of the cellar stairs")
At(25.5, 2.5) -- 45%
equal(Floor(), "G", "halfway down")
At(22.5, 2.5) -- 15%
equal(Floor(), "B", "past 40% down: the cellar")
equal(state.room, 4, "in the cellar room")
At(26.5, 2.5) -- 65%
equal(Floor(), "G", "back up past 60%")
equal(state.room, 2, "in the side room again")
At(25, 7)

---------------------------------------------------------------------------
-- 4. A staircase stepped onto partway is passing over or under you
---------------------------------------------------------------------------
At(10, 15)
equal(state.room, 1, "back in the hall")
At(6.5, 14.5) -- 45% up the hall's staircase, from the side
At(9.5, 14.5) -- 85%
equal(Floor(), "G", "never on its foot: no climb")
At(10, 18) -- off it
At(2.5, 14.5) -- its foot, 15%
At(5.5, 14.5) -- 45%
equal(Floor(), "G", "not yet")
At(8.5, 14.5) -- 75%
equal(Floor(), "2", "climbed: floor 2")
equal(state.room, 1, "still the hall, which is open to floor 2")
At(5, 5)
equal(Floor(), "2", "over the hall's south half: the upper room is here on floor 2")
At(9.5, 14.5)
At(3.5, 14.5) -- back down to 25%
equal(Floor(), "G", "down past 40%")

---------------------------------------------------------------------------
-- 5. A floor picked by hand
---------------------------------------------------------------------------
At(5, 5)
equal(Floor(), "G", "the hall")
I:PickFloor(3)
equal(Floor(), "2", "picked floor 2")
equal(state.room, 3, "the upper room has floor here, so you're in it")
At(8, 5)
equal(Floor(), "2", "stays a few yards on")
I:PickFloor(1)
equal(Floor(), "B", "picked the cellar floor, though no cellar room is here")
At(9, 6)
equal(Floor(), "B", "the pick holds within a few yards")
At(14, 14)
equal(Floor(), "G", "walked on: nothing of B here, so the hall's floor again")
assert(not state.picked, "the pick has given way")
I:PickFloor(3)
At(2.5, 14.5); At(3.5, 14.5)
equal(Floor(), "2", "a picked floor 2 at the staircase's foot doesn't climb down")

---------------------------------------------------------------------------
-- 6. Outdoors, out of the building, the x, the setting
---------------------------------------------------------------------------
indoors = false
assert(not At(5, 5), "outdoors: nothing to show")
assert(not state.placement, "and no building")
indoors = true
assert(At(5, 5), "indoors again")
equal(Floor(), "G", "coming in again: the ground floor")
assert(not At(60, 60), "well outside every room: nothing")
assert(At(5, 5), "back in")
assert(At(5, 19), "at the hall's north wall")
assert(At(5, 23), "a step past the rooms' outline (3 yards): kept")
equal(state.room, 1, "the hall")
assert(not At(5, 30), "10 yards out: let go")
At(5, 5)
I:Dismiss()
assert(not At(6, 5), "the x hides it")
assert(not At(7, 5), "while you stay indoors")
indoors = false
At(7, 5)
indoors = true
assert(At(7, 5), "until you next come in from outside")
settings.indoorView = false
assert(not At(7, 5), "the setting turns it off")
settings.indoorView = true
assert(At(7, 5), "and on")

---------------------------------------------------------------------------
-- 7. The inset: the pictures, turned with the building, north up
---------------------------------------------------------------------------
local inset = I.worldMap
local function Update() inset.driver.scripts.OnUpdate(inset.driver) end
At(5, 5)
facing = 1.25
Update()
assert(inset.frame.shown, "shown indoors")
equal(inset.frame.width, 192, "a third of the map's shorter side")
equal(inset.frame.point[1], "BOTTOMRIGHT", "in the map's bottom right corner")
equal(inset.frame.point[4], -38, "left of the quest log toggle")
equal(inset.arrow.rotation, 1.25, "the arrow turns with you")
local function Drawn()
	local list = {}
	for _, texture in ipairs(inset.textures) do
		if texture.shown then list[texture.file] = texture end
	end
	return list
end
local drawn = Drawn()
assert(drawn[1001] and drawn[1002] and not drawn[1003] and not drawn[1004], "the ground floor's rooms only")
equal(drawn[1001].wrap[1], "CLAMPTOBLACKADDITIVE", "clear outside the picture")
equal(drawn[1001].color[4], 1, "its own floor at full strength")

-- Where a texture puts picture position (u, v), from its box and corner coords.
local function PictureAt(texture, u, v)
	-- corners: UL, LL, UR, LR; the box is affine, so solve from three of them
	local c = texture.coords
	local left, top = texture.point[4], texture.point[5]
	local width, height = texture.width, texture.height
	-- x along the box from UL to UR, y from UL down to LL: (u, v) = UL + x (UR - UL) + y (LL - UL)
	local ax, ay = c[5] - c[1], c[6] - c[2]
	local bx, by = c[3] - c[1], c[4] - c[2]
	local det = ax * by - ay * bx
	local du, dv = u - c[1], v - c[2]
	local x, y = (du * by - dv * bx) / det, (ax * dv - ay * du) / det
	return left + x * width, top - y * height
end
local half = inset.view:GetWidth() / 2
local k = inset.view:GetWidth() / inset:YardsAcross()
-- Each picture's corners land where its room's are on the map (east right, north up).
local function Check(texture, picture, label)
	for _, corner in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 }, { 0.3, 0.6 } }) do
		local u, v = corner[1], corner[2]
		local x, y = PictureAt(texture, u, v)
		local pn, pw = I.ToWorld(inn, picture.x + u * picture.w, picture.y + (1 - v) * picture.h)
		near(x, (west - pw) * k, label .. " corner " .. u .. "," .. v .. " east", 1e-6)
		near(y, (pn - north) * k, label .. " corner " .. u .. "," .. v .. " north", 1e-6)
	end
end
Check(drawn[1001], { x = 0, y = 0, w = 32, h = 32 }, "hall")
Check(drawn[1002], { x = 20, y = 0, w = 16, h = 16 }, "side room")
-- The box is the picture's own outline turned, no bigger.
local box = drawn[1001]
local turned = 32 * k * (math.abs(math.cos(math.rad(YAW))) + math.abs(math.sin(math.rad(YAW))))
near(box.width, turned, "box across", 1e-6)
equal(box.rotation, 0, "not turned itself")

-- The other way (/wf indoors rotate): the picture's own size, turned about
-- its middle, which lands on the room's.
I:Command("rotate")
equal(I.drawMode, "rotate", "switched")
Update()
box = Drawn()[1001]
equal(box.point[1], "CENTER", "placed by its middle")
near(box.width, 32 * k, "its own width")
local cn, cw = I.ToWorld(inn, 16, 16)
near(box.point[4], (west - cw) * k, "middle east")
near(box.point[5], (cn - north) * k, "middle north")
near(box.rotation, math.rad(YAW) - math.pi / 2, "turned with the building")
equal(box.coords[1], 0, "the whole picture")
I:Command("rotate")
Update()
equal(Drawn()[1001].rotation, 0, "and back")

-- Floor 2: the upper room on top, the hall (open from below) under it, fainter.
I:PickFloor(3)
Update()
drawn = Drawn()
assert(drawn[1003] and drawn[1001] and not drawn[1002], "floor 2: the upper room and the hall under it")
equal(drawn[1003].sublevel, 0, "the upper room on top")
equal(drawn[1001].sublevel, -1, "the hall beneath")
assert(drawn[1001].color[4] < 1, "and fainter")

-- Floor buttons: B, G and 2, bottom up; the one shown lit.
local buttons = inset.floorButtons
equal(buttons[1].label.text, "B", "bottom button")
equal(buttons[3].label.text, "2", "top button")
assert(buttons[3].background.color[1] > 0.5, "floor 2 lit")
assert(buttons[1].label.textColor[1] < 1, "no cellar room here: dimmed")
buttons[2].scripts.OnClick(buttons[2])
equal(Floor(), "G", "the G button")

-- Zoom: the wheel and the buttons, within limits.
local yards = inset:YardsAcross()
inset.frame.scripts.OnMouseWheel(inset.frame, 1)
assert(inset:YardsAcross() < yards, "wheel up zooms in")
inset.zoomOut.scripts.OnClick(inset.zoomOut)
equal(inset:YardsAcross(), yards, "the - button zooms out")
for _ = 1, 10 do inset.zoomIn.scripts.OnClick(inset.zoomIn) end
equal(inset:YardsAcross(), 30, "no closer than 30 yards")
Update()
k = inset.view:GetWidth() / inset:YardsAcross()
Check(Drawn()[1001], { x = 0, y = 0, w = 32, h = 32 }, "hall, zoomed")

-- The x hides the inset; outdoors it's hidden too.
inset.close.scripts.OnClick(inset.close)
Update()
assert(not inset.frame.shown, "x: hidden")
indoors = false
now = now + 1
Update()
indoors = true
now = now + 1
Update()
assert(inset.frame.shown, "shown again on coming back in")

-- Any parent can have one: it only needs a frame and draws itself.
local other = New()
other.width, other.height, other.level = 300, 300, 5
local second = I:CreateInset(other, { size = 150 })
second.driver.scripts.OnUpdate(second.driver)
assert(second.frame.shown and second.frame.width == 150, "a second inset, its own size")

-- The zone map's: small, so fewer floor buttons fit up its side; and it
-- follows the zone map setting.
local zone = I.zoneMap
zone.driver.scripts.OnUpdate(zone.driver)
assert(zone.frame.shown and zone.frame.width == 104, "the zone map's inset, small")
local zoneButtons = 0
for _, button in ipairs(zone.floorButtons) do
	if button.shown then
		zoneButtons = zoneButtons + 1
		assert(button.points and button.points[1], "placed")
	end
end
assert(zoneButtons <= 5, "no more floor buttons than fit 104 pixels: " .. zoneButtons)
settings.zoneMap = false
zone.driver.scripts.OnUpdate(zone.driver)
assert(not zone.frame.shown, "hidden with the zone map setting off")
assert(inset.frame.shown, "the world map's stays")
settings.zoneMap = true
zone.driver.scripts.OnUpdate(zone.driver)
assert(zone.frame.shown, "back with it on")

---------------------------------------------------------------------------
-- 8. A cave whose levels never overlap is drawn whole; blocks of a big room
---------------------------------------------------------------------------
local cave = { north = 5000, west = 5000, scale = 1, cos = 1, sin = 0 }
local function InCave(a, b)
	north, west = I.ToWorld(cave, a, b)
	now = now + 1
	I:Refresh(0)
	return state.model.places[state.place][I:ShownFloor()]
end
equal(InCave(0.5, 6), "1", "the cave's lower level")
InCave(0.5, 4.5) -- the ramp's foot
InCave(1.5, 4.5)
InCave(2.5, 4.5)
equal(InCave(3.5, 4.5), "1", "in the ramp's gap: still the lower level")
equal(InCave(4.5, 4.5), "2", "past 60%, over the gap: the upper level")
equal(state.room, 1, "still in the lower level's room, which the ramp runs through")
equal(InCave(5.5, 6), "2", "off the ramp, still in that room: the climb holds")
equal(InCave(12, 2), "2", "into the upper level's room")
equal(InCave(6, 2), "1", "back into the lower room, off the ramp: its level")
-- A staircase that turns back on itself: east along y 0-1, then back west
-- along y 1-2, its head beside its foot.
equal(InCave(0.5, 0.5), "1", "at the turning staircase's foot")
equal(InCave(0.5, 1.5), "1", "a yard over, under its head: a jump in height, no climb")
InCave(0.5, 0.5)
InCave(1.5, 0.5)
InCave(2.5, 0.5)
InCave(3.5, 0.5) -- 45%, the turn
equal(InCave(3.5, 1.5), "2", "up its second flight past 60%: climbed")
InCave(3.5, 0.5)
equal(InCave(2.5, 0.5), "1", "back down its first flight past 40%")
equal(InCave(2, 7), "1", "the cave's first level")
Update()
drawn = Drawn()
assert(drawn[2001] and drawn[2002], "both levels drawn")
assert(drawn[2002].color[4] < 0.5, "the other level faintly")
north, west = I.ToWorld(cave, 130, 201)
now = now + 1
I:Refresh(0)
equal(state.room, 3, "the long room, past its first block")
inset:Zoom(10)
Update()
drawn = Drawn()
assert(drawn[2003] and drawn[2004], "both blocks of the long room")
k = inset.view:GetWidth() / inset:YardsAcross()
inn = cave
Check(drawn[2004], { x = 128, y = 200, w = 8, h = 4 }, "second block")

---------------------------------------------------------------------------
-- 8b. Floors near you, in a district counted as one place
---------------------------------------------------------------------------
local district = { north = 8000, west = 8000, scale = 1, cos = 1, sin = 0 }
local function InDistrict(a, b)
	indoors = false
	north, west = I.ToWorld(district, a, b)
	now = now + 1
	I:Refresh(0)
	indoors = true
	now = now + 1
	I:Refresh(0)
	inset.drawn = nil
	Update()
	local labels = {}
	for i, button in ipairs(inset.floorButtons) do
		if button.shown then labels[#labels + 1] = button.label.text end
	end
	return table.concat(labels, " ")
end
equal(InDistrict(5, 5), "G 2", "the lower house: its own two floors")
equal(state.floor, 1, "on its ground floor")
assert(inset.floorButtons[1].background.color[1] > 0.5, "G lit")
equal(InDistrict(105, 5), "G 2", "the house up the slope: G and 2, not 2 and 3")
equal(state.floor, 3, "on its ground floor, the place's third")
local list, labels = I:NearFloors()
equal(labels[3], "G", "its label")
assert(I:Describe():find("floor G", 1, true), "/wf indoors names the floor as the buttons do")

---------------------------------------------------------------------------
-- 9. The game's own data: Lion's Pride Inn, Goldshire
---------------------------------------------------------------------------
local file = io.open(root .. "/Modules/Wayfinder/Data/Interiors.lua")
if file then
	file:close()
	local real = Namespace()
	MiniQoLRuntime = { Execute = function(_, _, fn) return fn("Wayfinder", real) end }
	assert(loadfile(root .. "/Modules/Wayfinder/Data/Interiors.lua"))("Wayfinder", real)
	assert(loadfile(root .. "/Modules/Wayfinder/Interiors.lua"))("Wayfinder", real)
	local R = real.Interiors
	-- Innkeeper Farley stands behind the bar in the tap room: Elwynn Forest 43.77, 65.82.
	north, west, cont, indoors = -9463.04, 16.24, 0, true
	now = now + 1
	assert(R:Refresh(0), "Goldshire's inn is found under the innkeeper")
	local s = R.state
	local room = s.model.rooms[s.room]
	local files = {}
	for _, picture in ipairs(room.pictures) do files[picture.file] = true end
	assert(files[8505350], "in the tap room (the hall)")
	equal(s.model.places[s.place][R:ShownFloor()], "G", "on the ground floor")
	equal(table.concat(s.model.places[s.place], ","), "B,G,2", "a cellar, the ground floor and one above")
	assert(#s.model.stairs >= 2, "with its staircases")
	-- Outside on the road in front: no building.
	north, west = -9440, 60
	now = now + 1
	assert(not R:Refresh(0), "nothing on the road outside")
end
print("interiors: ok")
