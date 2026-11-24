-- Mark the recommended destination on the flight master's open selection map.
local _, ns = ...
local Highlight = ns:NewModule("FlightHighlight")
local ticker, marker, markedButton
local lines = {}
local from, to, startSlot, endSlot, nextRead, drawnHops

local function hide()
	if not markedButton then return end
	markedButton, drawnHops = nil, nil
	marker:Hide()
	for _, line in ipairs(lines) do line:Hide() end
end

local function mark(button)
	if not marker then
		marker = CreateFrame("Frame")
		marker:EnableMouse(false)
		local glow = marker:CreateTexture(nil, "OVERLAY")
		glow:SetAllPoints()
		glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		glow:SetBlendMode("ADD")
		glow:SetVertexColor(0.25, 0.9, 1)
		local label = marker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetText("Recommended")
		label:SetTextColor(0.45, 0.95, 1)
		label:SetShadowColor(0, 0, 0, 1)
		label:SetShadowOffset(1, -1)
		label:SetPoint("BOTTOM", marker, "CENTER", 0, 12)
	end
	marker:SetParent(button)
	marker:ClearAllPoints()
	marker:SetPoint("CENTER", button)
	local size = math.max(38, button:GetWidth() + 16)
	marker:SetSize(size, size)
	marker:SetFrameLevel(button:GetFrameLevel() + 4)
	marker:Show()
	markedButton = button
end

-- Slot indices belong to this open map. IDs survive localization and
-- disambiguate different masters in the same town.
local function slots(origin, destination)
	local mapID = GetTaxiMapID and GetTaxiMapID()
	if mapID and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes then
		local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
		if ok and type(nodes) == "table" then
			local current, reachable
			local count = NumTaxiNodes and NumTaxiNodes()
			for _, node in ipairs(nodes) do
				local id, slot = node.nodeID, node.slotIndex
				if ns.Readable(id) and (id == origin.taxi or id == destination.taxi)
					and ns.Readable(slot) and type(slot) == "number" and slot > 0 and slot % 1 == 0 and (not count or slot <= count) then
					local kind = TaxiNodeGetType and TaxiNodeGetType(slot)
					if not ns.Readable(kind) and ns.Readable(node.state) then
						kind = (node.state == 0 and "CURRENT") or (node.state == 1 and "REACHABLE")
					end
					if ns.Readable(kind) then
						if id == origin.taxi and kind == "CURRENT" then current = slot end
						if id == destination.taxi and kind == "REACHABLE" then reachable = slot end
					end
				end
			end
			if #nodes > 0 then return current, reachable end
		end
	end
	if not (NumTaxiNodes and TaxiNodeName and TaxiNodeGetType) then return end
	local current, reachable
	for slot = 1, NumTaxiNodes() do
		local kind, name = TaxiNodeGetType(slot), TaxiNodeName(slot)
		if ns.Readable(kind) and ns.Readable(name) then
			if kind == "CURRENT" and name == origin.n then current = slot end
			if kind == "REACHABLE" and name == destination.n then reachable = slot end
		end
	end
	return current, reachable
end

local function classicButton(slot)
	local button = _G["TaxiButton" .. slot]
	return button and button:IsShown() and button
end

-- Each line follows the displayed buttons, including Blizzard's offsets for
-- overlapping icons. Draw only a complete sequence from this master to the pin.
local function showHops(hops)
	local previous = startSlot
	for i = 1, hops do
		local a, b = TaxiGetNodeSlot(endSlot, i, true), TaxiGetNodeSlot(endSlot, i, false)
		local first, last = a and classicButton(a), b and classicButton(b)
		if a ~= previous or not first or not last then break end
		local line = lines[i]
		if not line then
			line = TaxiRouteMap:CreateLine(nil, "OVERLAY")
			line:SetColorTexture(0.12, 0.8, 1, 0.9)
			line:SetThickness(3)
			lines[i] = line
		end
		line:SetStartPoint("CENTER", first, 0, 0)
		line:SetEndPoint("CENTER", last, 0, 0)
		line:Show()
		previous = b
		if i == hops and b == endSlot then return true end
	end
	for _, line in ipairs(lines) do line:Hide() end
end

local function matchesPin(pin)
	local node = pin and pin.taxiNodeData
	return node and pin:IsShown() and ns.Readable(node.slotIndex) and node.slotIndex == endSlot
		and (node.nodeID == nil or (ns.Readable(node.nodeID) and node.nodeID == to.taxi))
end

local function refresh()
	local origin, destination = ns.Travel:GetRecommendedFlight()
	local classic = TaxiFrame and TaxiFrame:IsShown()
	local modern = FlightMapFrame and FlightMapFrame:IsShown() and FlightMapFrame.EnumeratePinsByTemplate
	if not origin or not (classic or modern) then
		hide()
		from, to = nil, nil
		return
	end
	local now = GetTime()
	if origin ~= from or destination ~= to or now >= nextRead then
		local a, b = slots(origin, destination)
		if origin ~= from or destination ~= to or a ~= startSlot or b ~= endSlot then hide() end
		from, to, startSlot, endSlot = origin, destination, a, b
		nextRead = now + (a and b and 5 or 1)
	end
	if not (startSlot and endSlot) then return end
	local button
	if classic then
		button = classicButton(endSlot)
	elseif matchesPin(markedButton) then
		button = markedButton
	else
		for pin in FlightMapFrame:EnumeratePinsByTemplate("FlightMap_FlightPointPinTemplate") do
			if matchesPin(pin) then
				button = pin
				break
			end
		end
	end
	if not button then
		hide()
		return
	end
	if markedButton ~= button then
		hide()
		mark(button)
	end
	local hops = classic and TaxiRouteMap and TaxiRouteMap.CreateLine and TaxiGetNodeSlot and GetNumRoutes and GetNumRoutes(endSlot) or 0
	if drawnHops ~= hops then
		for _, line in ipairs(lines) do line:Hide() end
		drawnHops = (hops == 0 or showHops(hops)) and hops or nil
	end
end

local function close()
	if ticker then ticker:Cancel(); ticker = nil end
	hide()
	from, to = nil, nil
end

function Highlight:OnLogin()
	ns:RegisterEvent("TAXIMAP_OPENED", function()
		close()
		refresh()
		-- Pins may appear a frame later, be recycled when zooming, or change
		-- while the asynchronous planner incorporates newly discovered flights.
		ticker = C_Timer.NewTicker(0.25, refresh)
	end)
	ns:RegisterEvent("TAXIMAP_CLOSED", close)
end
