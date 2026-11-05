local ADDON_NAME, ns = ...
MiniQoL = ns
ns.name = ADDON_NAME
ns.version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"
ns.features, ns.providers = {}, {}
ns.components = { Peddler = true, Gearwise = true, Wayfinder = true, XPCounter = true }
ns.pages = {
    { "home", "Overview" }, { "maps", "Maps & travel" },
    { "bags", "Gear advice" }, { "selling", "Selling" }, { "quests", "XP & reputation" },
    { "sound", "NPC dialogue" }, { "miniqol", "Mini QoL" },
}

function ns:Print(message)
    print("|cffe9c46aMini QoL|r: " .. tostring(message))
end

function ns:Initialize()
    MiniQoLDB = type(MiniQoLDB) == "table" and MiniQoLDB or {}
    self.db = MiniQoLDB
    if type(self.db.minimap) ~= "table" then self.db.minimap = {} end
    if type(self.db.minimap.angle) ~= "number" then self.db.minimap.angle = 220 end
    if type(self.db.favorites) ~= "table" then self.db.favorites = {} end
    self.db.page = self.db.page or "home"
    if type(self.db.dialogue) ~= "table" then self.db.dialogue = {} end
    for key, default in pairs({ enabled = true, hints = true, advance = true }) do
        if self.db.dialogue[key] == nil then self.db.dialogue[key] = default end
    end
    -- A reload already applied changes requested in the previous session.
    self.reloadPending = false
end

function ns:Loaded(name)
    local api = MiniQoLRuntime and MiniQoLRuntime.api or C_AddOns
    return api.IsAddOnLoaded(name) and true or false
end

function ns:Refresh()
    if self.panel and self.panel:IsShown() then self:Render() end
end

function ns:RegisterFeature(feature)
    assert(feature.id and feature.label and feature.page, "Incomplete Mini QoL feature")
    self.features[#self.features + 1] = feature
end

function ns:Available(feature)
    return not not ((not feature.addon or self:Loaded(feature.addon))
        and (not feature.available or feature.available()))
end

function ns:Read(feature)
    if not self:Available(feature) then return nil end
    local ok, value = pcall(feature.get)
    if ok then return value end
    self.lastError = tostring(value)
end

function ns:Write(feature, value)
    if not self:Available(feature) then return false end
    if InCombatLockdown and InCombatLockdown() then
        self:Print("Change settings after combat.")
        return false
    end
    local ok, reason = pcall(feature.set, value)
    if not ok then
        self.lastError = tostring(reason)
        self:Print("Could not change " .. feature.label .. ". " .. self.lastError)
        return false
    end
    if feature.reload then self.reloadPending = true end
    self:Refresh()
    return true
end

-- Call the addon's registered command directly. No macros or chat submission.
function ns:Command(command, argument)
    local wanted = command:lower()
    for key, handler in pairs(SlashCmdList) do
        if type(handler) == "function" then
            local index = 1
            while _G["SLASH_" .. key .. index] do
                if _G["SLASH_" .. key .. index]:lower() == wanted then
                    handler(argument or "")
                    return true
                end
                index = index + 1
            end
        end
    end
    return false
end

function ns:Provider(name)
    return self.providers[name]
end

function ns:Addons()
    local result = {}
    local api = MiniQoLRuntime and MiniQoLRuntime.api or C_AddOns
    for index = 1, api.GetNumAddOns() do
        local name, title, notes, loadable, reason = api.GetAddOnInfo(index)
        if name and self.components[name] then
            local provider = self:Provider(name)
            result[#result + 1] = {
                name = name, title = title or name, notes = notes or "",
                version = api.GetAddOnMetadata(name, "Version") or "",
                loaded = self:Loaded(name), loadable = loadable, reason = reason,
                enabled = api.GetAddOnEnableState(name, UnitName("player")) > 0,
                provider = provider, page = provider and provider.page or "tools",
            }
        end
    end
    table.sort(result, function(a, b) return a.name:lower() < b.name:lower() end)
    return result
end

function ns:OpenProvider(provider)
    if InCombatLockdown and InCombatLockdown() then
        self:Print("Open addon settings after combat.")
        return false
    end
    if not provider or not self:Loaded(provider.addon) then
        self:Print("That addon's settings are unavailable. Enable it and reload first.")
        return false
    end
    local ok, opened = pcall(function()
        if provider.open then provider.open(); return true end
        return provider.command and self:Command(provider.command, provider.argument)
    end)
    if not ok or not opened then
        self:Print("Could not open settings for " .. provider.addon .. ".")
        if not ok then self.lastError = tostring(opened) end
        return false
    end
    if self.panel then self.panel:Hide() end
    return true
end

function ns:Matches(query, ...)
    if query == "" then return true end
    local parts = { ... }
    local haystack = table.concat(parts, " "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
    for word in query:lower():gmatch("%S+") do
        if not haystack:find(word, 1, true) then return false end
    end
    return true
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        ns:Initialize()
    elseif event == "PLAYER_LOGIN" then
        if not ns.db then ns:Initialize() end
        ns:CreateMinimapButton()
        ns:RegisterSettings()
        if ns.Dialogue then ns.Dialogue:Initialize() end
    end
end)

SLASH_MINIQOL1, SLASH_MINIQOL2 = "/mqol", "/miniqol"
SlashCmdList.MINIQOL = function(input)
    input = (input or ""):lower():match("^%s*(.-)%s*$")
    if input == "icon" then
        ns.db.minimap.hide = false
        ns:UpdateMinimapButton()
    elseif input == "resetpos" then
        ns.db.position, ns.db.minimap.angle = nil, 220
        if ns.panel then ns.panel:ClearAllPoints(); ns.panel:SetPoint("CENTER") end
        ns:UpdateMinimapButton()
    else
        ns:Toggle()
    end
end
