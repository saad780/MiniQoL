local _, ns = ...
local function provider(name, page, command, open)
    ns.providers[name] = { addon = name, page = page, command = command, open = open }
end
provider("Wayfinder", "maps", nil, function() Wayfinder.Options:Open() end)
provider("Gearwise", "bags", "/gearwise")
provider("Peddler", "selling", "/peddler")
provider("XPCounter", "quests", "/xpcounter")

local function checkbox(id, page, label, addon, get, set, tooltip, reload, available)
    ns:RegisterFeature({ id = id, page = page, label = label, addon = addon,
        kind = "check", get = get, set = set, tooltip = tooltip or label,
        reload = reload, available = available })
end

for _, item in ipairs({
    { "enabled", "NPC dialogue hotkeys", "Use 1-9 and 0, including numpad digits, for visible NPC options and reward choices. Existing buttons, icons and confirmations are preserved. Hotkeys yield to typing, combat, popups, settings and gamepad mode." },
    { "hints", "Show dialogue key hints", "Small hints leave native dialogue text, quest icons and reward markers intact." },
    { "advance", "Space advances quests", "Space uses the enabled Accept, Continue or Complete Quest button. Choosing a reward and handing in the quest remain separate actions." },
}) do
    local key, label, tooltip = item[1], item[2], item[3]
    checkbox("dialogue." .. key, "sound", label, nil,
        function() return ns.db.dialogue[key] end,
        function(value) ns.db.dialogue[key] = value; if ns.Dialogue then ns.Dialogue:Refresh() end end,
        tooltip)
end

local function wayfinder(key, label, category)
    checkbox("wayfinder." .. key, "maps", label, "Wayfinder", function()
        if category then return Wayfinder:IsCategoryEnabled(key) end
        return Wayfinder:GetSetting(key)
    end, function(value)
        if category then Wayfinder:SetCategoryEnabled(key, value) else Wayfinder:SetSetting(key, value) end
    end, "Wayfinder: " .. label, key == "continuousMap", function() return Wayfinder and Wayfinder.db end)
end
for _, item in ipairs({
    { "continuousMap", "Continuous world map" }, { "detailEnabled", "Zoom into minimap detail" },
    { "showOnWorldMap", "World map service icons" }, { "showOnContinent", "Continent service icons" },
    { "showMinimapServices", "Minimap service icons" }, { "nativeMinimapTurnIns", "Native quest turn-in icons" },
    { "shareExploration", "Share exploration across characters" }, { "showLiveQuests", "Live quest markers" },
    { "showArrow", "Waypoint direction arrow" }, { "clearOnArrival", "Clear waypoint on arrival" },
    { "useSeedData", "Built-in town services" }, { "showApproximate", "Approximate NPC positions" },
    { "recordMouseover", "Record nearby service NPCs" }, { "importExploration", "Import discovered terrain" },
    { "showOtherFaction", "Other faction's NPCs" }, { "showAllClassTrainers", "All class trainers" },
}) do wayfinder(item[1], item[2]) end
for _, item in ipairs({ { "bank", "Bankers" }, { "auction", "Auctioneers" }, { "flight", "Flight masters" },
    { "inn", "Innkeepers" }, { "mailbox", "Mailboxes" }, { "repair", "Repair vendors" } }) do wayfinder(item[1], item[2], true) end
ns:RegisterFeature({ id = "wayfinder.fog", page = "maps", label = "Unexplored terrain", addon = "Wayfinder", kind = "choice",
    choices = { { 1, "Hidden" }, { 2, "Darkened" }, { 3, "Shown" } },
    get = function() return Wayfinder:GetSetting("unexploredTerrain") end,
    set = function(value) Wayfinder:SetSetting("unexploredTerrain", value) end,
    available = function() return Wayfinder and Wayfinder.db end,
    tooltip = "Unexplored terrain on the world map and detailed map." })

for _, item in ipairs({ { "bags", "Bag upgrade arrows" }, { "quests", "Quest reward advice" },
    { "unusable", "Shade unusable equipment" }, { "popups", "Upgrade notifications" }, { "tooltips", "Item comparison tooltips" } }) do
    local key, label = item[1], item[2]
    checkbox("gearwise." .. key, "bags", label, "Gearwise", function() return Gearwise.db[key] end,
        function(value) Gearwise:SetOption(key, value) end, "Gearwise: " .. label, false,
        function() return Gearwise and Gearwise.db end)
end

for _, item in ipairs({
    { "AutoSellGreyItems", "Automatically sell junk" }, { "SoulboundOnly", "Restrict automatic marks to soulbound" },
    { "SellLimit", "Respect the buyback item limit" }, { "Silent", "Quiet sale messages" },
    { "SilenceSaleSummary", "Hide sale summaries" }, { "AutoSellWhiteItems", "Automatically mark common equipment" },
    { "AutoSellGreenItems", "Automatically mark uncommon equipment" }, { "AutoSellBlueItems", "Automatically mark rare equipment" },
    { "AutoSellPurpleItems", "Automatically mark epic equipment" }, { "AutoSellUnwantedItems", "Mark equipment unusable by my class" },
}) do
    local key, label = item[1], item[2]
    checkbox("peddler." .. key, "selling", label, "Peddler", function() return not not _G[key] end,
        function(value)
            _G[key] = value
            local module = MiniQoLRuntime and MiniQoLRuntime.namespaces.Peddler
            if module and module.markWares then module.markWares() end
        end, "Peddler: " .. label .. ". Existing defaults and manually marked items are preserved.")
end
checkbox("xp.popups", "quests", "Floating XP and reputation text", "XPCounter",
    function() return XPCounterDB and XPCounterDB.popupsEnabled end,
    function(value) MiniQoLRuntime.namespaces.XPCounter.MiniQoLSetPopups(value) end,
    "XP Counter's floating messages. Chat reports remain enabled.", false,
    function() return MiniQoLRuntime and MiniQoLRuntime.namespaces.XPCounter and MiniQoLRuntime.namespaces.XPCounter.MiniQoLSetPopups end)

checkbox("miniqol.icon", "miniqol", "Show minimap button", nil,
    function() return not ns.db.minimap.hide end,
    function(value) ns.db.minimap.hide = not value; ns:UpdateMinimapButton() end,
    "Use /mqol icon to restore this button. Other addons manage their own minimap buttons.")
