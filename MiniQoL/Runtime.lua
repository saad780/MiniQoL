-- Compatibility boundary for modules physically embedded in the single MiniQoL addon.
-- The client sees one addon; existing module namespaces and saved profiles stay intact.
local real = _G
local native = C_AddOns
local R = { modules = {}, order = {}, namespaces = {}, environments = {}, loaded = {}, frames = {}, continuations = {}, bridges = {} }
MiniQoLRuntime = R
local originalCreateFrame, originalGetFenv = CreateFrame, getfenv
local originalRawGet, originalRawSet, originalPairs = rawget, rawset, pairs
local originalNext = next
local nativeMemory = C_AddOns.GetAddOnMemoryUsage or GetAddOnMemoryUsage
local nativeCPU = GetAddOnCPUUsage
local nativeProfiler = C_AddOnProfiler

function R:Enabled(name)
    local module = self.modules[name]
    if not module then return false end
    local char = self.character or ""
    local settings = MiniQoLDB and MiniQoLDB.modules
    if settings and settings[name] ~= nil then return settings[name] end
    if self.characterStates and self.characterStates[char] and self.characterStates[char][name] ~= nil then
        return self.characterStates[char][name]
    end
    return module.defaultEnabled ~= false
end

function R:CanLoad(name)
    if not self:Enabled(name) then return false end
    for _, dependency in ipairs(self.modules[name].dependencies) do
        if self.modules[dependency] then
            if not self.loaded[dependency] then return false end
        elseif not native.IsAddOnLoaded(dependency) then
            return false
        end
    end
    return true
end

function R:Install(manifest, states)
    self.modules, self.order, self.characterStates = manifest.modules, manifest.order, states
    self.character = UnitName("player") or ""
    self.index = {}
    for i = 1, native.GetNumAddOns() do
        local name = native.GetAddOnInfo(i)
        if name and not self.modules[name] then self.index[#self.index + 1] = name end
    end
    for _, name in ipairs(self.order) do self.index[#self.index + 1] = name end
    self.api = setmetatable({}, { __index = native })
    local api = self.api
    function api.GetAddOnMetadata(name, field)
        local m = R.modules[name]
        if m then return m.metadata[field] end
        return native.GetAddOnMetadata(name, field)
    end
    function api.IsAddOnLoaded(name)
        if R.modules[name] then return R.loaded[name] == true, R.loaded[name] == true end
        return native.IsAddOnLoaded(name)
    end
    function api.GetNumAddOns() return #R.index end
    function api.GetAddOnInfo(value)
        local name = type(value) == "number" and R.index[value] or value
        local m = R.modules[name]
        if not m then return native.GetAddOnInfo(name) end
        local enabled = R:Enabled(name)
        return name, m.metadata.Title or name, m.metadata.Notes or "", enabled,
            not enabled and "DISABLED" or nil, "INSECURE", false
    end
    function api.GetAddOnEnableState(name, character)
        if R.modules[name] then return R:Enabled(name) and 2 or 0 end
        return native.GetAddOnEnableState(name, character)
    end
    function api.DoesAddOnExist(name)
        if R.modules[name] then return true end
        if native.DoesAddOnExist then return native.DoesAddOnExist(name) end
        return native.GetAddOnInfo(name) ~= nil
    end
    function api.GetAddOnMemoryUsage(value)
        local name = type(value) == "number" and R.index[value] or value
        if R.modules[name] then return 0 end
        return nativeMemory and nativeMemory(name) or 0
    end
    function api.IsAddOnLoadable(name, character, demand)
        if R.modules[name] then return R:Enabled(name), R:Enabled(name) and nil or "DISABLED" end
        return native.IsAddOnLoadable(name, character, demand)
    end
    function api.IsAddOnLoadOnDemand(name)
        if R.modules[name] then return R.modules[name].metadata.LoadOnDemand == "1" end
        return native.IsAddOnLoadOnDemand(name)
    end
    function api.GetAddOnDependencies(name)
        if R.modules[name] then return unpack(R.modules[name].dependencies) end
        return native.GetAddOnDependencies(name)
    end
    function api.GetAddOnOptionalDependencies(name)
        if R.modules[name] then return unpack(R.modules[name].optional) end
        return native.GetAddOnOptionalDependencies(name)
    end
    function api.LoadAddOn(name)
        if R.modules[name] then
            if not R:Enabled(name) then return nil, "DISABLED" end
            if R.loaded[name] then return true end
            -- Eager loading completes in dependency order before PLAYER_LOGIN.
            return nil, "NOT_FINISHED"
        end
        return native.LoadAddOn(name)
    end
    function api.EnableAddOn(name, character)
        if not R.modules[name] then return native.EnableAddOn(name, character) end
        MiniQoLDB.modules = MiniQoLDB.modules or {}
        MiniQoLDB.modules[name] = true
        MiniQoL.reloadPending = true
    end
    function api.DisableAddOn(name, character)
        if not R.modules[name] then return native.DisableAddOn(name, character) end
        MiniQoLDB.modules = MiniQoLDB.modules or {}
        MiniQoLDB.modules[name] = false
        MiniQoL.reloadPending = true
    end
end

function R:TrackFrame(frame, owner)
    if self.frames[frame] then return frame end
    local record = { frame = frame, owner = owner, hooks = {} }
    self.frames[frame] = record
    local setScript, hookScript = frame.SetScript, frame.HookScript
    local function wrap(handler)
        if not handler then return nil end
        return function(self, event, ...)
            -- Logical ADDON_LOADED events are delivered once, below, in dependency order.
            if event == "ADDON_LOADED" and (...) == "MiniQoL" then return end
            return handler(self, event, ...)
        end
    end
    record.handler = frame:GetScript("OnEvent")
    if record.handler then setScript(frame, "OnEvent", wrap(record.handler)) end
    frame.SetScript = function(self, script, handler)
        if script == "OnEvent" then
            record.handler = handler
            return setScript(self, script, wrap(handler))
        end
        return setScript(self, script, handler)
    end
    frame.HookScript = function(self, script, handler)
        if script == "OnEvent" then record.hooks[#record.hooks + 1] = handler; return hookScript(self, script, wrap(handler)) end
        return hookScript(self, script, handler)
    end
    return frame
end

function R:Environment(name)
    if self.environments[name] then return self.environments[name] end
    local env = { C_AddOns = self.api }
    env._G = env
    env.CreateFrame = function(...) return R:TrackFrame(originalCreateFrame(...), name) end
    env.getfenv = function(level)
        if level == 0 then return env end
        return originalGetFenv(type(level) == "number" and level + 1 or level)
    end
    env.rawget = function(t, key)
        if t == env then
            local value = originalRawGet(env, key)
            if value ~= nil then return value end
            return originalRawGet(real, key)
        end
        return originalRawGet(t, key)
    end
    env.rawset = function(t, key, value)
        if t == env and originalRawGet(env, key) == nil then originalRawSet(real, key, value); return env end
        return originalRawSet(t, key, value)
    end
    env.pairs = function(t) return originalPairs(t == env and real or t) end
    env.next = function(t, key) return originalNext(t == env and real or t, key) end
    env.getglobal = function(key) return env[key] end
    env.GetAddOnMemoryUsage = self.api.GetAddOnMemoryUsage
    env.GetAddOnCPUUsage = function(value)
        local addon = type(value) == "number" and R.index[value] or value
        if R.modules[addon] or not nativeCPU then return 0, 0 end
        return nativeCPU(addon)
    end
    if nativeProfiler then
        env.C_AddOnProfiler = setmetatable({}, { __index = nativeProfiler })
        env.C_AddOnProfiler.GetAddOnMetric = function(addon, metric)
            if R.modules[addon] then return 0 end
            return nativeProfiler.GetAddOnMetric(addon, metric)
        end
    end
    env.loadstring = function(...)
        local chunk, reason = loadstring(...)
        if chunk then setfenv(chunk, env) end
        return chunk, reason
    end
    env.EventUtil = setmetatable({}, { __index = EventUtil })
    env.EventUtil.ContinueOnAddOnLoaded = function(addon, callback)
        if not R.modules[addon] then return EventUtil.ContinueOnAddOnLoaded(addon, callback) end
        if R.loaded[addon] then callback(); return end
        local list = R.continuations[addon] or {}
        R.continuations[addon] = list
        list[#list + 1] = callback
    end
    for _, key in ipairs({ "GetAddOnMetadata", "IsAddOnLoaded", "GetNumAddOns", "GetAddOnInfo",
        "GetAddOnEnableState", "LoadAddOn", "EnableAddOn", "DisableAddOn", "IsAddOnLoadOnDemand",
        "GetAddOnDependencies", "GetAddOnOptionalDependencies" }) do env[key] = self.api[key] end
    setmetatable(env, { __index = real, __newindex = real })
    self.environments[name] = env
    return env
end

function R:Execute(name, chunk)
    if not self:CanLoad(name) then return end
    self.namespaces[name] = self.namespaces[name] or {}
    return setfenv(chunk, self:Environment(name))(name, self.namespaces[name])
end

function R:ExecuteSource(name, source, chunkName)
    if not self:CanLoad(name) then return end
    local chunk, reason = loadstring(source, chunkName)
    if not chunk then error(reason, 0) end
    return self:Execute(name, chunk)
end

function R:Complete(name)
    if self.loaded[name] or not self:CanLoad(name) then return end
    self.loaded[name] = true
    -- Take a snapshot: handlers may create frames while processing this event.
    local pending = {}
    for _, record in pairs(self.frames) do pending[#pending + 1] = record end
    for _, record in ipairs(pending) do
        if record.frame:IsEventRegistered("ADDON_LOADED") then
            if record.handler then securecallfunction(record.handler, record.frame, "ADDON_LOADED", name) end
            for _, handler in ipairs(record.hooks) do securecallfunction(handler, record.frame, "ADDON_LOADED", name) end
        end
    end
    local callbacks = self.continuations[name]
    self.continuations[name] = nil
    if callbacks then for _, callback in ipairs(callbacks) do securecallfunction(callback) end end
end
