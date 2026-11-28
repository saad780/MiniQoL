-- Mini QoL packaging adapter; upstream source and credits follow.
MiniQoLRuntime:Execute("Wayfinder", function(...)
-- Dots on the continuous world map and minimap follow the remaining walking
-- route from the player to the next transport stop or the destination. Once
-- you're inside a followed quest's area (Navigation:GetArea), the same dots
-- march around its outline instead.
local _, ns = ...
local Ants = ns:NewModule("AntTrails")
local Guarded = ns.Guarded or function(fn) return fn end -- each error once, not every frame (Core.lua)

local COLORS = {
	cyan = { 0.35, 0.84, 1 }, -- the arrow's own
	gold = { 1, 0.82, 0.15 },
	green = { 0.45, 0.92, 0.45 },
	white = { 1, 1, 1 },
}
local DOT = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask" -- a white disc
local LIMIT = 400 -- dots on one surface at most
local sqrt, cos, sin, max, min = math.sqrt, math.cos, math.sin, math.max, math.min

local function Number(v)
	return ns.Readable(v) and type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Each surface draws its dots in its own pixels: the world map's from its
-- top-left corner (y down), the minimap's from its centre (y up).
-- Speed is measured in surface pixels per second.
-- Clearance is measured from the player centre to the first dot's centre.
local map = { size = 7, spacing = 18, speed = 27, clearance = 0, dots = {}, shown = 0 }
local mini = { size = 5, spacing = 11, speed = 11, clearance = 16, dots = {}, shown = 0 }
local zone = { size = 5, spacing = 12, speed = 14, clearance = 0, dots = {}, shown = 0 } -- Shift+M
Ants.map, Ants.mini, Ants.zone = map, mini, zone

local function Shows(where)
	if not ns:GetSetting("antTrails") then return false end
	local setting = ns:GetSetting("antTrailsWhere")
	return setting == where or (setting ~= "map" and setting ~= "minimap")
end

-- The quest area's outline: on wherever the trails are, or on both surfaces
-- when the trails themselves are off.
local function ShowsArea(where)
	if not ns:GetSetting("questAreas") then return false end
	return not ns:GetSetting("antTrails") or Shows(where)
end

local function Color()
	return COLORS[ns:GetSetting("antTrailColor")] or COLORS.cyan
end

local function Dot(surface, index)
	local dot = surface.dots[index]
	if dot then return dot end
	local size = surface.size
	local shadow = surface.frame:CreateTexture(nil, "ARTWORK", nil, 0)
	shadow:SetTexture(DOT)
	shadow:SetVertexColor(0, 0, 0, 0.6)
	shadow:SetSize(size + 3, size + 3)
	dot = surface.frame:CreateTexture(nil, "ARTWORK", nil, 1)
	dot:SetTexture(DOT)
	dot:SetSize(size, size)
	for _, texture in ipairs({ shadow, dot }) do
		if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
		if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
	end
	shadow:SetPoint("CENTER", dot, "CENTER")
	local color = Color()
	dot:SetVertexColor(color[1], color[2], color[3], 1)
	dot.shadow = shadow
	surface.dots[index] = dot
	return dot
end

local function Show(surface, count)
	for index = count + 1, surface.shown do
		local dot = surface.dots[index]
		dot:Hide()
		dot.shadow:Hide()
	end
	surface.shown = count
end

-- The trail as pixels on a surface, in these reused lists.
local px, py = {}, {}

-- Places dots every `spacing` pixels along the first n points, starting a
-- little further in each frame so that they march toward the end. Near(a, b)
-- says whether a segment can show at all; Inside(x, y) whether a dot does.
local function March(surface, n, now, Near, Inside)
	local spacing, frame = surface.spacing, surface.frame
	local carry = surface.clearance + (now * surface.speed) % spacing
	local count = 0
	for i = 1, n - 1 do
		local ax, ay = px[i], py[i]
		local dx, dy = px[i + 1] - ax, py[i + 1] - ay
		local length = sqrt(dx * dx + dy * dy)
		if carry >= length then
			carry = carry - length
		elseif Near(ax, ay, px[i + 1], py[i + 1]) then
			local along = carry
			while along < length do
				local t = along / length
				local x, y = ax + dx * t, ay + dy * t
				if Inside(x, y) then
					count = count + 1
					local dot = Dot(surface, count)
					dot:SetPoint("CENTER", frame, surface.point, x, surface.up * y)
					if count > surface.shown then dot:Show(); dot.shadow:Show() end
					if count >= LIMIT then -- (the most there ever are: none to hide)
						surface.shown = count
						return count
					end
				end
				along = along + spacing
			end
			carry = along - length
		else
			carry = (spacing - (length - carry) % spacing) % spacing
		end
	end
	Show(surface, count)
	return count
end

-- Where the player stands, in the trail's world yards: the unit's own
-- position where the game gives it on that continent (it moves every frame),
-- else the map's.
local function PlayerWorld(cont)
	if UnitPosition then
		local ok, north, west, _, instance = pcall(UnitPosition, "player")
		if ok and Number(north) and Number(west) and instance == cont then return north, west end
	end
	local playerCont, wx, wy = ns.GetPlayerWorld()
	if playerCont == cont then return wx, wy end
end

-- The trail's points, in world yards, through To(x, y) into px/py: the player,
-- the route from its next point on, then the end. Returns how many.
local function Points(To, wx, wy, endX, endY, xs, ys, idx, joinX, joinY)
	local n = 1
	px[1], py[1] = To(wx, wy)
	if joinX then
		n = n + 1
		px[n], py[n] = To(joinX, joinY)
	end
	if xs then
		for i = idx, #xs do
			n = n + 1
			px[n], py[n] = To(xs[i], ys[i])
		end
	end
	if endX then
		n = n + 1
		px[n], py[n] = To(endX, endY)
	end
	return n
end

-- An area's outline, closed, through To(x, y) into px/py. Returns how many.
local function AreaPoints(To, xs, ys)
	local n = #xs
	for i = 1, n do px[i], py[i] = To(xs[i], ys[i]) end
	px[n + 1], py[n + 1] = px[1], py[1]
	return n + 1
end

---------------------------------------------------------------------------
-- The continuous world map
---------------------------------------------------------------------------
local mapW, mapH = 0, 0
local ax, bx, cx, ay, by, cy = 0, 0, 0, 0, 0, 0 -- yards to the view's pixels
local function MapPoint(x, y) return ax + bx * x + cx * y, ay + by * x + cy * y end
local function MapNear(x1, y1, x2, y2)
	return max(x1, x2) >= -8 and min(x1, x2) <= mapW + 8 and max(y1, y2) >= -8 and min(y1, y2) <= mapH + 8
end
local function MapInside(x, y) return x >= -4 and x <= mapW + 4 and y >= -4 and y <= mapH + 4 end

function Ants:BuildMap()
	if map.frame or not WorldMapFrame then return end
	local sc = WorldMapFrame.ScrollContainer
	local layer = CreateFrame("Frame", nil, WorldMapFrame:GetCanvasContainer())
	layer:SetAllPoints(sc)
	layer:SetClipsChildren(true)
	layer:EnableMouse(false)
	map.frame, map.point, map.up = layer, "TOPLEFT", -1
	layer:SetScript("OnUpdate", Guarded(function() self:UpdateMap() end, "Wayfinder ant trails (map)"))
end

function Ants:UpdateMap()
	local engine = ns.ContinuousEngine
	local controller = engine and engine:GetModule("worldmap")
	local S = engine and engine.MapStitch
	local cont, endX, endY, xs, ys, idx, joinX, joinY
	local stitched = controller and controller.IsStitched()
	if Shows("map") and stitched then
		cont, endX, endY, xs, ys, idx, joinX, joinY = ns.Navigation:GetTrail()
	end
	local areaCont, areaXs, areaYs
	if not cont and stitched and ShowsArea("map") and ns.Navigation.GetArea then
		areaCont, areaXs, areaYs = ns.Navigation:GetArea()
	end
	local wx, wy
	if cont then wx, wy = PlayerWorld(cont) end
	local u, v, zoom
	if wx or areaCont then u, v, zoom = controller.ViewNow() end
	local u0, v0, u1, v1, u2, v2
	if u then
		local on = cont or areaCont
		u0, v0 = S.FromYards(on, 0, 0)
		u1, v1 = S.FromYards(on, 1000, 0)
		u2, v2 = S.FromYards(on, 0, 1000)
	end
	if not u2 then Show(map, 0); return end
	local sc = WorldMapFrame.ScrollContainer
	mapW, mapH = sc:GetWidth(), sc:GetHeight()
	local hu, hv = controller.ViewHalfExtents(zoom)
	local kx, ky = mapW / (2 * hu), mapH / (2 * hv)
	ax, bx, cx = (u0 - u) * kx + mapW / 2, (u1 - u0) / 1000 * kx, (u2 - u0) / 1000 * kx
	ay, by, cy = (v0 - v) * ky + mapH / 2, (v1 - v0) / 1000 * ky, (v2 - v0) / 1000 * ky
	-- Above the map's art, its terrain and the fog over it; under its icons.
	local level = (S.artTop or sc:GetFrameLevel()) + 2
	if map.frame:GetFrameLevel() ~= level then map.frame:SetFrameLevel(level) end
	if areaCont then
		March(map, AreaPoints(MapPoint, areaXs, areaYs), GetTime(), MapNear, MapInside)
	else
		March(map, Points(MapPoint, wx, wy, endX, endY, xs, ys, idx, joinX, joinY), GetTime(), MapNear, MapInside)
	end
end

---------------------------------------------------------------------------
-- The zone map (Shift+M)
---------------------------------------------------------------------------
-- An ordinary map canvas: one zone's map, panned and zoomed inside its frame.
-- The dots go on a layer over the visible part, placed from where the canvas
-- sits under it, so they keep their size on screen at any zoom.
local zoneW, zoneH = 0, 0
local zax, zcx, zay, zby = 0, 0, 0, 0 -- yards to the layer's pixels
local function ZonePoint(x, y) return zax + zcx * y, zay + zby * x end
local function ZoneNear(x1, y1, x2, y2)
	return max(x1, x2) >= -8 and min(x1, x2) <= zoneW + 8 and max(y1, y2) >= -8 and min(y1, y2) <= zoneH + 8
end
local function ZoneInside(x, y) return x >= -2 and x <= zoneW + 2 and y >= -2 and y <= zoneH + 2 end

function Ants:BuildZone()
	if zone.frame or not BattlefieldMapFrame or not BattlefieldMapFrame.ScrollContainer then return end
	local sc = BattlefieldMapFrame.ScrollContainer
	local layer = CreateFrame("Frame", nil, sc)
	layer:SetAllPoints(sc)
	layer:SetClipsChildren(true)
	layer:EnableMouse(false)
	zone.frame, zone.point, zone.up = layer, "TOPLEFT", -1
	layer:SetScript("OnUpdate", Guarded(function() self:UpdateZone() end, "Wayfinder ant trails (zone map)"))
end

function Ants:UpdateZone()
	local zoneMap = BattlefieldMapFrame
	local canvas = zoneMap and zoneMap:IsShown() and zoneMap.GetCanvas and zoneMap:GetCanvas()
	local mapID = canvas and ns:GetSetting("zoneMap") and zoneMap:GetMapID()
	local rect = mapID and ns.GetMapRect(mapID)
	local cont, endX, endY, xs, ys, idx, joinX, joinY
	if rect and Shows("map") then cont, endX, endY, xs, ys, idx, joinX, joinY = ns.Navigation:GetTrail() end
	if cont and cont ~= rect.cont then cont = nil end
	local areaCont, areaXs, areaYs
	if rect and not cont and ShowsArea("map") and ns.Navigation.GetArea then
		areaCont, areaXs, areaYs = ns.Navigation:GetArea()
		if areaCont ~= rect.cont then areaCont = nil end
	end
	local wx, wy
	if cont then wx, wy = PlayerWorld(cont) end
	local layer = zone.frame
	local cl, ct, ll, lt = canvas and canvas:GetLeft(), canvas and canvas:GetTop(), layer:GetLeft(), layer:GetTop()
	if not ((wx or areaCont) and cl and ct and ll and lt) or rect.width == 0 or rect.height == 0 then
		Show(zone, 0)
		return
	end
	-- The canvas in the layer's units: where its top left is, and its size.
	local k = canvas:GetEffectiveScale() / layer:GetEffectiveScale()
	local cw, ch = canvas:GetWidth() * k, canvas:GetHeight() * k
	local ox, oy = cl * k - ll, lt - ct * k
	zoneW, zoneH = layer:GetWidth(), layer:GetHeight()
	-- (u, v) on the map is ((left - west) / width, (top - north) / height).
	zax, zcx = ox + cw * rect.left / rect.width, -cw / rect.width
	zay, zby = oy + ch * rect.top / rect.height, -ch / rect.height
	-- Over the explored-area art, under the map's icons (MapPins.ZoneTrailLevel).
	local level = (ns.MapPins and ns.MapPins.ZoneTrailLevel and ns.MapPins.ZoneTrailLevel(zoneMap)) or (canvas:GetFrameLevel() + 1)
	if layer:GetFrameLevel() ~= level then layer:SetFrameLevel(level) end
	if areaCont then
		March(zone, AreaPoints(ZonePoint, areaXs, areaYs), GetTime(), ZoneNear, ZoneInside)
	else
		March(zone, Points(ZonePoint, wx, wy, endX, endY, xs, ys, idx, joinX, joinY), GetTime(), ZoneNear, ZoneInside)
	end
end

---------------------------------------------------------------------------
-- The minimap
---------------------------------------------------------------------------
local playerX, playerY, radius, halfW, halfH, cosine, sine, square = 0, 0, 1, 1, 1, 1, 0, false
local function MiniPoint(x, y)
	local east, north = playerY - y, x - playerX
	return (east * cosine + north * sine) / radius * halfW, (north * cosine - east * sine) / radius * halfH
end
-- Keep the player arrow clear even when a later leg crosses the centre again.
local function MiniInside(x, y)
	if x * x + y * y < mini.clearance * mini.clearance then return false end
	local w, h = halfW - mini.size, halfH - mini.size
	if square then return math.abs(x) <= w and math.abs(y) <= h end
	return (x * x) / (w * w) + (y * y) / (h * h) <= 1
end
-- A segment passing within the minimap's reach of its centre.
local function MiniNear(x1, y1, x2, y2)
	local dx, dy = x2 - x1, y2 - y1
	local lengthSq = dx * dx + dy * dy
	local t = lengthSq > 0 and max(0, min(1, -(x1 * dx + y1 * dy) / lengthSq)) or 0
	local x, y = x1 + dx * t, y1 + dy * t
	local reach = max(halfW, halfH) * 1.45 + 8 -- (a square's corners)
	return x * x + y * y <= reach * reach
end

local viewReadAt
local function ReadMinimap(now)
	if viewReadAt and now - viewReadAt < 0.5 then return end
	viewReadAt = now
	local rotate = GetCVarBool and GetCVarBool("rotateMinimap")
	if C_Minimap and C_Minimap.IsRotateMinimapIgnored and C_Minimap.IsRotateMinimapIgnored() then rotate = false end
	mini.rotate = rotate and true or false
	square = GetMinimapShape ~= nil and GetMinimapShape() == "SQUARE"
end

function Ants:BuildMinimap()
	if mini.frame or not Minimap then return end
	local layer = CreateFrame("Frame", nil, Minimap)
	layer:SetAllPoints(Minimap)
	layer:SetFrameLevel(Minimap:GetFrameLevel() + 5) -- under Wayfinder's service icons
	layer:EnableMouse(false)
	mini.frame, mini.point, mini.up = layer, "CENTER", 1
	layer:SetScript("OnUpdate", Guarded(function() self:UpdateMinimap() end, "Wayfinder ant trails (minimap)"))
end

function Ants:UpdateMinimap()
	local cont, endX, endY, xs, ys, idx, joinX, joinY
	if Shows("minimap") then cont, endX, endY, xs, ys, idx, joinX, joinY = ns.Navigation:GetTrail() end
	local areaCont, areaXs, areaYs
	if not cont and ShowsArea("minimap") and ns.Navigation.GetArea then
		areaCont, areaXs, areaYs = ns.Navigation:GetArea()
	end
	local wx, wy
	if cont or areaCont then wx, wy = PlayerWorld(cont or areaCont) end
	local viewRadius = wx and C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
	if not Number(viewRadius) or viewRadius <= 0 then Show(mini, 0); return end
	local now = GetTime()
	ReadMinimap(now)
	local facing = mini.rotate and GetPlayerFacing and GetPlayerFacing() or 0
	if not Number(facing) then facing = 0 end
	playerX, playerY, radius = wx, wy, viewRadius
	halfW, halfH = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
	if halfW < 16 or halfH < 16 then Show(mini, 0); return end
	cosine, sine = cos(facing), sin(facing)
	if areaCont then
		March(mini, AreaPoints(MiniPoint, areaXs, areaYs), now, MiniNear, MiniInside)
	else
		March(mini, Points(MiniPoint, wx, wy, endX, endY, xs, ys, idx, joinX, joinY), now, MiniNear, MiniInside)
	end
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local function Recolor(surface)
	local color = Color()
	for _, dot in ipairs(surface.dots) do dot:SetVertexColor(color[1], color[2], color[3], 1) end
end

function Ants:OnLogin()
	self:BuildMinimap()
	EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", function() self:BuildMap() end)
	EventUtil.ContinueOnAddOnLoaded("Blizzard_BattlefieldMap", function() self:BuildZone() end)
	ns:RegisterEvent("CVAR_UPDATE", function() viewReadAt = nil end)
	ns:On("SETTING_CHANGED", function(key)
		if key == "antTrailColor" then
			Recolor(map)
			Recolor(mini)
			Recolor(zone)
		end
	end)
end

end)
