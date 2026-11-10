local ADDON_NAME, ns = ...
MiniQoL = ns
ns.name = ADDON_NAME
ns.version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"
ns.features, ns.providers = {}, {}
-- One description of the panel's shape: sidebar grouping, page blurb, and which
-- bundled module (if any) a page belongs to.
ns.pages = {
    { id = "home", label = "Overview",
      description = "Pinned settings and the state of every module." },
    { id = "maps", label = "Maps & travel", group = "Modules", module = "Wayfinder",
      description = "Exploration, service icons, navigation and travel." },
    { id = "bags", label = "Gear advice", group = "Modules", module = "Gearwise",
      description = "Item comparisons, upgrade arrows and quest reward advice." },
    { id = "selling", label = "Selling", group = "Modules", module = "Peddler",
      description = "Item marking and automatic selling at vendors." },
    { id = "quests", label = "XP & reputation", group = "Modules", module = "XPCounter",
      description = "Chat reports, kill estimates and floating text." },
    { id = "sound", label = "NPC dialogue", group = "Mini QoL",
      description = "Keyboard shortcuts for Blizzard's gossip and quest windows." },
    { id = "fishing", label = "Fishing", group = "Mini QoL",
      description = "A louder splash, one-key casting, lures, an outfit swap and a record of your catch." },
    { id = "miniqol", label = "Mini QoL", group = "Mini QoL",
      description = "Panel preferences, module switches and source credits." },
}

function ns:Page(id)
    for _, page in ipairs(self.pages) do if page.id == id then return page end end
end

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

-- Action features do something rather than hold a value.
function ns:Run(feature)
    if not self:Available(feature) then return false end
    if InCombatLockdown and InCombatLockdown() then
        self:Print("Try that after combat.")
        return false
    end
    local ok, reason = pcall(feature.run)
    if not ok then
        self.lastError = tostring(reason)
        self:Print("Could not run " .. feature.label .. ". " .. self.lastError)
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

-- The bundled modules, in load order. They are not separate addons to the
-- client, so read them from the runtime manifest rather than scanning every
-- installed addon on every repaint.
function ns:Addons()
    local runtime = MiniQoLRuntime
    local result = {}
    if not runtime then return result end
    for _, name in ipairs(runtime.order) do
        local module = runtime.modules[name]
        local provider = self:Provider(name)
        result[#result + 1] = {
            name = name,
            title = module.metadata.Title or name,
            notes = module.metadata.Notes or "",
            author = module.metadata.Author or "See source credits",
            version = module.metadata.Version or "",
            loaded = self:Loaded(name),
            enabled = runtime:Enabled(name) and true or false,
            provider = provider,
            page = provider and provider.page or "miniqol",
        }
    end
    return result
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
        if ns.Fishing then ns.Fishing:Start() end
    end
end)

SLASH_MINIQOL1, SLASH_MINIQOL2 = "/mqol", "/miniqol"
SlashCmdList.MINIQOL = function(input)
    input = (input or ""):lower():match("^%s*(.-)%s*$")
    local command, rest = input:match("^(%S*)%s*(.-)$")
    if command == "fish" then
        -- The whole point is one action: into the fishing outfit, then back.
        if not ns.Fishing or not ns.Fishing.db then return end
        if rest == "show" then ns.Fishing:ToggleBar()
        elseif rest == "gear" or rest == "outfit" then ns.Fishing:ToggleOutfit()
        elseif rest == "bar" then ns.Fishing:Set("bar", not ns.Fishing:Get("bar"))
        else ns.Fishing:ToggleGear() end
    elseif input == "icon" then
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
