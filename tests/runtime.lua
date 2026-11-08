local root = ...
local function equal(actual, expected, label)
    assert(actual == expected, (label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local frames = {}
function CreateFrame()
    local frame = { scripts = {}, hooks = {}, events = {} }
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    function frame:GetScript(event) return self.scripts[event] end
    function frame:HookScript(event, callback) self.hooks[event] = self.hooks[event] or {}; table.insert(self.hooks[event], callback) end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:IsEventRegistered(event) return self.events[event] end
    function frame:Trigger(event, ...)
        if self.scripts.OnEvent then self.scripts.OnEvent(self, event, ...) end
        for _, callback in ipairs(self.hooks.OnEvent or {}) do callback(self, event, ...) end
    end
    frames[#frames + 1] = frame
    return frame
end
function securecallfunction(fn, ...) return fn(...) end
function UnitName() return "Testplayer" end
function InCombatLockdown() return false end
C_AddOns = {
    GetAddOnMetadata = function(name, key) return name == "MiniQoL" and "test" or "native:" .. key end,
    IsAddOnLoaded = function(name) return name == "Blizzard_Test" end,
    GetAddOnInfo = function(name) return name, name, "native", true end,
    GetAddOnEnableState = function() return 2 end,
    IsAddOnLoadable = function() return true end,
    IsAddOnLoadOnDemand = function() return false end,
    LoadAddOn = function(name) return name == "Blizzard_Test" end,
    GetNumAddOns = function() return 0 end,
}
EventUtil = { ContinueOnAddOnLoaded = function(_, callback) callback() end }
SlashCmdList = {}
MiniQoLDB = { minimap = { angle = 19 }, favorites = { example = true } }
local ns = {}
assert(loadfile(root .. "/Core.lua"))("MiniQoL", ns)
ns:Initialize()
assert(loadfile(root .. "/Runtime.lua"))("MiniQoL", ns)
local R = MiniQoLRuntime
local manifest = { order = { "Alpha", "Beta", "Off" }, modules = {
    Alpha = { metadata = { Title = "Alpha title", Version = "7" }, dependencies = {}, optional = {}, defaultEnabled = true },
    Beta = { metadata = { Title = "Beta title" }, dependencies = { "Alpha" }, optional = {}, defaultEnabled = true },
    Off = { metadata = {}, dependencies = {}, optional = {}, defaultEnabled = false },
} }
R:Install(manifest, { Testplayer = { Alpha = true } })
equal(R.api.GetAddOnMetadata("Alpha", "Version"), "7", "virtual metadata")
equal(R.api.GetAddOnMetadata("Blizzard_Test", "Title"), "native:Title", "native API fallback")
equal(select(1, R.api.GetAddOnInfo(2)), "Beta", "virtual enumeration")
equal(R.api.GetAddOnEnableState("Off"), 0, "disabled module")
equal(R.api.IsAddOnLoaded("Blizzard_Test"), true, "native loaded state")
equal(R.api.DoesAddOnExist("Alpha"), true, "virtual existence")
equal(R.api.GetAddOnMemoryUsage("Alpha"), 0, "embedded modules do not duplicate package memory metrics")
equal(R:CanLoad("Beta"), false, "required dependency must load before its module")
equal(C_AddOns.GetNumAddOns(), 0, "native API remains untouched")

local events, hooks, callbacks = {}, 0, 0
R:Execute("Alpha", function(name, private)
    equal(name, "Alpha", "module identity")
    private.retained = 31
    packageGlobal = 42
    _G.proxyGlobal = 43
    equal(rawset(_G, "rawProxyGlobal", 44), _G, "rawset retains table identity")
    equal(rawget(_G, "proxyGlobal"), 43)
    equal(C_AddOns.GetAddOnMetadata(name, "Version"), "7")
    equal(getfenv(0), _G, "custom environments inherit virtual globals")
    equal(assert(loadstring("return C_AddOns.GetAddOnMetadata('Alpha', 'Version')"))(), "7", "dynamic chunks inherit module environment")
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(_, event, addon) events[#events + 1] = addon end)
    f:HookScript("OnEvent", function() hooks = hooks + 1 end)
    EventUtil.ContinueOnAddOnLoaded("Beta", function() callbacks = callbacks + 1 end)
end)
equal(packageGlobal, 42, "global assignments preserved")
equal(proxyGlobal, 43, "_G assignments preserved")
equal(rawProxyGlobal, 44, "raw assignments preserved")
equal(R.api.IsAddOnLoaded("Alpha"), false, "not loaded until complete")
R:Complete("Alpha")
equal(events[1], "Alpha", "own loaded event")
equal(hooks, 1, "synthetic hooked event")
R:Complete("Alpha")
equal(#events, 1, "exactly one loaded event")
R:Execute("Alpha", function(_, private) equal(private.retained, 31, "stable private namespace") end)
R:Execute("Beta", function(name)
    equal(name, "Beta")
    equal(C_AddOns.IsAddOnLoaded("Alpha"), true, "dependency visible")
    EventUtil.ContinueOnAddOnLoaded("Alpha", function() callbacks = callbacks + 1 end)
end)
R:Complete("Beta")
equal(events[2], "Beta", "dependent loaded event")
equal(callbacks, 2, "deferred and immediate callbacks")
for frame in pairs(R.frames) do frame:Trigger("ADDON_LOADED", "MiniQoL") end
equal(#events, 2, "physical package event suppressed")
equal(hooks, 2, "physical hooked event suppressed")
local ran = false
R:Execute("Off", function() ran = true end)
R:Complete("Off")
equal(ran, false, "disabled code skipped")
equal(R.api.IsAddOnLoaded("Off"), false)
R.api.EnableAddOn("Off")
equal(R:Enabled("Off"), true, "persisted module switch")
equal(ns.reloadPending, true, "switch requires reload")
equal(MiniQoLDB.minimap.angle, 19, "existing shell profile retained")
equal(MiniQoLDB.favorites.example, true)

-- UI-independent settings contracts: direct controls call their owners' APIs.
-- The service icon checkboxes are generated from Wayfinder's own category
-- list, so the stand-in has to supply one.
Wayfinder = { db = {}, state = { showMinimapServices = true, unexploredTerrain = 2 }, categories = {},
	CategoryList = { { id = "mailbox", label = "Mailboxes" }, { id = "bank", label = "Bankers" } } }
function Wayfinder:GetSetting(k) return self.state[k] end
function Wayfinder:SetSetting(k, v) self.state[k] = v; self.lastChanged = k end
function Wayfinder:IsCategoryEnabled(k) return self.categories[k] ~= false end
function Wayfinder:SetCategoryEnabled(k, v) self.categories[k] = v end
R.modules.Wayfinder = { metadata = {}, dependencies = {}, optional = {} }
R.loaded.Wayfinder = true
assert(loadfile(root .. "/Integrations.lua"))("MiniQoL", ns)
ns.Refresh = function() end
local index = {}
for _, feature in ipairs(ns.features) do index[feature.id] = feature end
equal(ns:Write(index["wayfinder.showMinimapServices"], false), true)
equal(Wayfinder.state.showMinimapServices, false)
equal(Wayfinder.lastChanged, "showMinimapServices", "owning setter invoked")
ns:Write(index["wayfinder.cat.mailbox"], false)
equal(Wayfinder.categories.mailbox, false, "mailbox category identity")
ns:Write(index["wayfinder.fog"], 2)
equal(Wayfinder.state.unexploredTerrain, 2)
equal(ns:Matches("bank icons", "Bank service icons"), true)
equal(ns:Matches("[", "[literal]"), true, "search treats patterns as text")
equal(ns:Matches("bank flight", "bank icons"), false)
assert(loadfile(root .. "/Panel.lua"))("MiniQoL", ns)
ns:SetModuleEnabled("Alpha", false)
equal(R:Enabled("Alpha"), false, "disable requested module")
equal(R:Enabled("Beta"), false, "disable required dependent")
ns:SetModuleEnabled("Beta", true)
equal(R:Enabled("Beta"), true)
equal(R:Enabled("Alpha"), true, "reenable required dependency")
print("Runtime and settings contracts passed")
