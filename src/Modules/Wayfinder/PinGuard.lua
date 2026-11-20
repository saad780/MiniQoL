-- The game's own world map pins, kept from a blocked call in combat.
--
-- Every pin the map hands out is told which mouse buttons to let through
-- (MapCanvasPinMixin:CheckMouseButtonPassthrough, which calls
-- SetPassThroughButtons), and the game blocks that call during combat once an
-- addon has had a hand in the map: "AddOn 'MiniQoL' tried to call the
-- protected function 'Button:SetPassThroughButtons()'". Wayfinder does have a
-- hand in it. The continuous map puts up the zone the view has moved to, and
-- following the player on the map does the same; the map keeps what that sets
-- (its map ID among it) in the addon's name, out of combat too. From then on
-- a quest pin handed out during a fight, with the map open, raised that error.
--
-- Wayfinder's own pins already wait for the fight to end (MapPins.lua). Here
-- the game's pins on the world map do the same: in combat a pin skips the
-- call, and makes it when combat ends or, if it went back to its pool first,
-- the next time it is handed out. Left exactly as they are: pins that are
-- protected frames (their whole pool, since the guard itself runs in the
-- addon's name), and pins with a passthrough check of their own.
--
-- Armed only once Wayfinder drives the map, so a map it never touched stays
-- untouched. A pool is guarded from its first pin on; a kind of pin first
-- made during a fight can still raise the error that once.
local _, ns = ...

local PinGuard = ns:NewModule("PinGuard")

local armed = false
local pools = setmetatable({}, { __mode = "k" })     -- pool -> true (guarded) or false (left alone)
local originals = setmetatable({}, { __mode = "k" }) -- pin -> the passthrough check it came with
local waiting = setmetatable({}, { __mode = "k" })   -- pin -> the buttons asked for during a fight

local function Guarded(pin, ...)
	if InCombatLockdown() then
		waiting[pin] = { ... }
		return
	end
	waiting[pin] = nil
	return originals[pin](pin, ...)
end

local function Untouchable(frame)
	return type(frame) ~= "table" or (frame.IsForbidden and frame:IsForbidden())
		or (frame.IsProtected and frame:IsProtected()) or false
end

local function GuardPin(pin)
	if Untouchable(pin) or originals[pin] then return end
	local check = pin.CheckMouseButtonPassthrough
	-- A check of its own (Wayfinder's pins, another addon's) already knows what to do.
	if type(check) ~= "function" or check ~= MapCanvasPinMixin.CheckMouseButtonPassthrough then return end
	originals[pin] = check
	pin.CheckMouseButtonPassthrough = Guarded
end

local function AfterAcquire(pin, ...)
	GuardPin(pin)
	return pin, ...
end

-- One of the pool's pins, in use or not, to tell what kind it holds.
local function Sample(pool)
	for _, method in ipairs({ "EnumerateActive", "EnumerateInactive" }) do
		if type(pool[method]) == "function" then
			local ok, iterator, state, control = pcall(pool[method], pool)
			if ok and type(iterator) == "function" then
				local found, first, second = pcall(iterator, state, control)
				if found and type(first) == "table" then return first end
				if found and type(second) == "table" then return second end
			end
		end
	end
end

local function GuardPool(pool)
	if type(pool) ~= "table" or pools[pool] ~= nil or type(pool.Acquire) ~= "function" then return end
	local sample = Sample(pool)
	if not sample then return end -- nothing made yet: looked at again once there is
	if Untouchable(sample) then
		pools[pool] = false
		return
	end
	pools[pool] = true
	local acquire = pool.Acquire
	pool.Acquire = function(self, ...)
		return AfterAcquire(acquire(self, ...))
	end
	if type(pool.EnumerateActive) == "function" then
		-- Pools list their pins as keys, or as values after an index.
		for first, second in pool:EnumerateActive() do
			GuardPin(type(first) == "table" and first or second)
		end
	end
end

function PinGuard:IsArmed()
	return armed
end

function PinGuard:GuardAll()
	if not armed then return end
	for _, pool in pairs(WorldMapFrame.pinPools) do
		GuardPool(pool)
	end
end

-- Pins that skipped the call in a fight make it now. One back in its pool has
-- no map to ask; it waits until it is handed out again.
function PinGuard:CatchUp()
	if InCombatLockdown() then return end
	for pin, buttons in pairs(waiting) do
		if pin.owningMap then
			waiting[pin] = nil
			securecallfunction(originals[pin], pin, unpack(buttons))
		end
	end
end

-- Called when Wayfinder starts driving the world map.
function PinGuard:Arm()
	if armed then return true end
	local map = WorldMapFrame
	if type(map) ~= "table" or type(map.pinPools) ~= "table" or type(map.AcquirePin) ~= "function"
		or type(MapCanvasPinMixin) ~= "table"
		or type(MapCanvasPinMixin.CheckMouseButtonPassthrough) ~= "function" then
		return false
	end
	armed = true
	hooksecurefunc(map, "AcquirePin", function(self, template)
		local pool = self.pinPools and self.pinPools[template]
		if pool and pools[pool] == nil then GuardPool(pool) end
		if next(waiting) and not InCombatLockdown() then PinGuard:CatchUp() end
	end)
	self:GuardAll()
	return true
end

function PinGuard:OnLogin()
	-- Pools that have filled since they were last looked at, before the fight needs them.
	ns:RegisterEvent("PLAYER_REGEN_DISABLED", function() self:GuardAll() end)
	ns:RegisterEvent("PLAYER_REGEN_ENABLED", function() self:CatchUp() end)
end
