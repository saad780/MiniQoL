local root = ...
local nativeRawGet = rawget
local globals = _G

-- Simulate the client's raw mixin lookup in the first Lua caller, including
-- calls made through pcall. Lua's __index fallback must not satisfy this.
local function nativeMixin(name)
    for level = 3, 12 do
        local info = debug.getinfo(level, "Sf")
        if not info then break end
        if info.what == "Lua" then
            local mixin = nativeRawGet(getfenv(info.func), name)
            assert(mixin, "unable to find mixin or metatable (" .. name .. ")")
            return mixin
        end
    end
    error("No Lua caller found")
end

Vector2DMixin = { GetXY = function(self) return self.x, self.y end }
local otherMixins = {
    "ColorMixin", "Vector3DMixin", "ItemLocationMixin", "ItemTransmogInfoMixin",
    "TransmogPendingInfoMixin", "TransmogLocationMixin", "PlayerLocationMixin",
}
for _, name in ipairs(otherMixins) do globals[name] = {} end

C_AddOns = { GetNumAddOns = function() return 0 end }
EventUtil = {}
UnitName = function() return "Testplayer" end
C_Map = {
    GetBestMapForUnit = function() return 1453 end,
    GetPlayerMapPosition = function()
        return setmetatable({ x = 0.4, y = 0.6 }, { __index = nativeMixin("Vector2DMixin") })
    end,
    GetWorldPosFromMapPos = function(_, pos)
        return 0, setmetatable({ x = 1000 - pos.y * 800, y = 2000 - pos.x * 1200 },
            { __index = nativeMixin("Vector2DMixin") })
    end,
}
CreateVector2D = function(x, y)
    return setmetatable({ x = x, y = y }, { __index = Vector2DMixin })
end

assert(loadfile(root .. "/Runtime.lua"))()
local R = MiniQoLRuntime
R:Install({ order = { "Wayfinder" }, modules = {
    Wayfinder = { metadata = {}, dependencies = {}, optional = {} },
} })
assert(loadfile(root .. "/Modules/Wayfinder/Geometry.lua"))()
local ns = R.namespaces.Wayfinder

-- Exercise the exact coordinate path used by Exploration:Sample, with native
-- return values that fail unless the caller exposes Vector2DMixin directly.
for i = 1, 20 do
    local cont, wx, wy, mapID, x, y = ns.GetPlayerWorld()
    assert(cont == 0 and mapID == 1453)
    assert(math.abs(wx - 520) < 0.000001 and math.abs(wy - 1520) < 0.000001)
    assert(x == 0.4 and y == 0.6)
end
local function noPosition()
    assert(ns.GetPlayerWorld() == nil)
end
C_Map.GetPlayerMapPosition = function() return nil end
noPosition()
C_Map.GetPlayerMapPosition = function() return CreateVector2D(0, 0) end
noPosition()
C_Map.GetBestMapForUnit = function() return nil end
noPosition()

for _, module in ipairs({ "Wayfinder", "Gearwise", "Peddler", "XPCounter" }) do
    local env = R:Environment(module)
    assert(nativeRawGet(env, "Vector2DMixin") == Vector2DMixin)
    for _, name in ipairs(otherMixins) do
        assert(nativeRawGet(env, name) == globals[name], module .. " missing " .. name)
    end
end

-- Optional client mixins can be absent without breaking environment creation.
for _, name in ipairs(otherMixins) do globals[name] = nil end
local env = R:Environment("MinimalClient")
assert(nativeRawGet(env, "Vector2DMixin") == Vector2DMixin)
for _, name in ipairs(otherMixins) do assert(nativeRawGet(env, name) == nil) end
print("Native mixin lookups, repeated player sampling and unavailable positions passed")
