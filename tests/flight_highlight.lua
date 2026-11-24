local package = ...
local ns = { Travel = {} }
local events, origin, destination = {}
function ns:NewModule(name) self[name] = {}; return self[name] end
function ns:RegisterEvent(name, fn) events[name] = fn end
function ns.Readable(v) return v ~= nil end
function ns.Travel:GetRecommendedFlight() return origin, destination end
MiniQoLRuntime = { Execute = function(_, name, fn) fn(name, ns) end }

local now, ticker, marker, label, reads = 0, nil, nil, nil, 0
local lines = {}
local function noop() end
local widget = {}
local function frame()
	return setmetatable({ shown = true }, { __index = widget })
end
function widget:IsShown() return self.shown end
function widget:Show() self.shown = true end
function widget:Hide() self.shown = false end
function widget:SetParent(parent) self.parent = parent end
function widget:EnableMouse(enabled) self.mouse = enabled end
function widget:GetWidth() return 20 end
function widget:GetFrameLevel() return 10 end
function widget:CreateTexture() return frame() end
function widget:CreateFontString() label = frame(); return label end
function widget:SetText(value) self.text = value end
function widget:CreateLine() local line = frame(); lines[#lines + 1] = line; return line end
function widget:SetStartPoint(_, button) self.start = button end
function widget:SetEndPoint(_, button) self.finish = button end
for _, method in ipairs({ "SetAllPoints", "SetTexture", "SetBlendMode", "SetVertexColor", "SetTextColor",
	"SetShadowColor", "SetShadowOffset", "SetPoint", "ClearAllPoints", "SetSize", "SetFrameLevel",
	"SetColorTexture", "SetThickness" }) do widget[method] = noop end
function CreateFrame() assert(not marker, "reuse the overlay"); marker = frame(); return marker end
function GetTime() return now end
C_Timer = { NewTicker = function(_, fn)
	assert(not ticker or ticker.cancelled, "only one timer per open map")
	ticker = { tick = fn, Cancel = function(self) self.cancelled = true end }
	return ticker
end }
local function tick(delta) now = now + (delta or 0.25); assert(not ticker.cancelled); ticker.tick() end

local bluff = { taxi = 22, n = "Thunder Bluff, Mulgore" }
local camp = { taxi = 77, n = "Camp Taurajo, The Barrens" }
local nodes = { { nodeID=77, slotIndex=3, state=1 }, { nodeID=22, slotIndex=1, state=0 }, { nodeID=25, slotIndex=2, state=1 } }
local names = { bluff.n, camp.n, "Localized destination name" }
local kinds = { "CURRENT", "REACHABLE", "REACHABLE" }
function GetTaxiMapID() return 1 end
C_TaxiMap = { GetAllTaxiNodes = function() reads = reads + 1; return nodes end }
function NumTaxiNodes() return 3 end
function TaxiNodeName(slot) return names[slot] end
function TaxiNodeGetType(slot) return kinds[slot] end
function GetNumRoutes(slot) return slot - 1 end
function TaxiGetNodeSlot(_, hop, start) return start and hop or hop + 1 end
function TakeTaxiNode() error("highlighting must preserve manual flight selection") end
TaxiFrame, TaxiRouteMap, TaxiButton1, TaxiButton2, TaxiButton3 = frame(), frame(), frame(), frame(), frame()
assert(loadfile(package .. "/Modules/Wayfinder/FlightHighlight.lua"))()
ns.FlightHighlight:OnLogin()

-- A pending plan may finish after the map opens. Use the actual node ID,
-- even if a similarly named stop is visible, and wait for the intermediate pin.
events.TAXIMAP_OPENED()
assert(not marker and reads == 0)
origin, destination = bluff, camp
TaxiButton2:Hide()
tick()
assert(marker:IsShown() and marker.parent == TaxiButton3 and marker.mouse == false and label.text == "Recommended")
assert(#lines == 0)
TaxiButton2:Show()
tick()
assert(#lines == 2 and lines[1].start == TaxiButton1 and lines[1].finish == TaxiButton2)
assert(lines[2].start == TaxiButton2 and lines[2].finish == TaxiButton3 and lines[2]:IsShown())
for i = 1, 6 do tick() end
assert(reads == 1, "do not rescan taxi nodes on each update")

-- Changing the route while open moves the marker or clears the entire overlay.
destination = { taxi = 25, n = names[2] }
tick()
assert(marker.parent == TaxiButton2 and lines[1]:IsShown() and not lines[2]:IsShown())
origin, destination = nil, nil
tick()
assert(not marker:IsShown() and not lines[1]:IsShown())
origin, destination = { taxi = 999, n = bluff.n }, camp
tick()
assert(not marker:IsShown(), "wrong departure")
origin = bluff
kinds[3] = "DISTANT"
tick()
assert(not marker:IsShown(), "a matching name cannot override an unavailable node ID")
events.TAXIMAP_CLOSED()
assert(ticker.cancelled)

-- A new map can reuse slot numbers. Older clients expose exact names only.
C_TaxiMap = nil
events.TAXIMAP_OPENED()
assert(marker:IsShown() and marker.parent == TaxiButton2)
events.TAXIMAP_CLOSED()
assert(not marker:IsShown() and ticker.cancelled)

-- Pooled flight-map pins can appear late and then be recycled during zoom.
TaxiFrame:Hide()
FlightMapFrame = frame()
local pin, visible = frame(), {}
function FlightMapFrame:EnumeratePinsByTemplate(template)
	assert(template == "FlightMap_FlightPointPinTemplate")
	local i = 0
	return function() i = i + 1; return visible[i] end
end
C_TaxiMap = { GetAllTaxiNodes = function() return nodes end }
TaxiNodeGetType = nil
events.TAXIMAP_OPENED()
assert(not marker:IsShown())
pin.taxiNodeData = nodes[1]
visible[1] = pin
tick()
assert(marker:IsShown() and marker.parent == pin and not lines[1]:IsShown())
pin.taxiNodeData = { slotIndex = 3, nodeID = 999 }
tick()
assert(not marker:IsShown())
pin.taxiNodeData = nodes[1]
tick()
assert(marker:IsShown())
events.TAXIMAP_CLOSED()
assert(not marker:IsShown() and ticker.cancelled)

print("Flight map: selectable destination, delayed pins, multi-hop lines, route changes and cleanup passed")
