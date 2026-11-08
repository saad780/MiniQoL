local _, ns = ...
-- Every bundled module's settings are declared here and rendered by the Mini
-- QoL panel. The modules register no settings category of their own, so the
-- game's AddOns list holds a single Mini QoL entry and nothing is stranded in
-- a second window.
local function provider(name, page)
    ns.providers[name] = { addon = name, page = page }
end
provider("Wayfinder", "maps")
provider("Gearwise", "bags")
provider("Peddler", "selling")
provider("XPCounter", "quests")

local function feature(spec)
    ns:RegisterFeature(spec)
end

local function checkbox(id, page, group, label, addon, get, set, tooltip, reload, available)
    feature({ id = id, page = page, group = group, label = label, addon = addon,
        kind = "check", get = get, set = set, tooltip = tooltip or label,
        reload = reload, available = available })
end

-- Slider values arrive as floats, so round before formatting rather than
-- handing a fractional number to "%d".
local function Percent(value) return ("%d%%"):format(math.floor(value * 100 + 0.5)) end
local function Yards(value)
    return value == 0 and "Minimap" or ("%d yd"):format(math.floor(value + 0.5))
end

---------------------------------------------------------------------------
-- Mini QoL: NPC dialogue
---------------------------------------------------------------------------
for _, item in ipairs({
    { "enabled", "NPC dialogue hotkeys", "Use 1-9 and 0, including numpad digits, for visible NPC options and reward choices. Existing buttons, icons and confirmations are preserved. Hotkeys yield to typing, combat, popups, settings and gamepad mode." },
    { "hints", "Show dialogue key hints", "Small hints leave native dialogue text, quest icons and reward markers intact." },
    { "advance", "Space advances quests", "Space uses the enabled Accept, Continue or Complete Quest button. Choosing a reward and handing in the quest remain separate actions." },
}) do
    local key, label, tooltip = item[1], item[2], item[3]
    checkbox("dialogue." .. key, "sound", "Hotkeys", label, nil,
        function() return ns.db.dialogue[key] end,
        function(value) ns.db.dialogue[key] = value; if ns.Dialogue then ns.Dialogue:Refresh() end end,
        tooltip)
end

---------------------------------------------------------------------------
-- Wayfinder
---------------------------------------------------------------------------
local function mapReady() return Wayfinder and Wayfinder.db and true or false end

local function wayfinder(key, group, label, tooltip, reload)
    checkbox("wayfinder." .. key, "maps", group, label, "Wayfinder",
        function() return Wayfinder:GetSetting(key) end,
        function(value) Wayfinder:SetSetting(key, value) end,
        tooltip, reload, mapReady)
end

local function wayfinderSlider(key, group, label, tooltip, minValue, maxValue, step, format)
    feature({ id = "wayfinder." .. key, page = "maps", group = group, label = label, addon = "Wayfinder",
        kind = "slider", min = minValue, max = maxValue, step = step, format = format,
        get = function() return Wayfinder:GetSetting(key) end,
        set = function(value) Wayfinder:SetSetting(key, value) end,
        tooltip = tooltip or label, available = mapReady })
end

wayfinder("continuousMap", "Detail view", "Continuous world map",
    "Pan and zoom smoothly across continents, zones and cities, down to minimap terrain.", true)
wayfinder("detailEnabled", "Detail view", "Zoom past the map into minimap detail",
    "Blend into the minimap's own terrain as you zoom closer. With the continuous map off, scrolling past the normal map's limit opens the separate detail view.")
feature({ id = "wayfinder.fog", page = "maps", group = "Detail view", label = "Unexplored terrain",
    addon = "Wayfinder", kind = "select",
    choices = { { 1, "Hidden" }, { 2, "Darkened" }, { 3, "Shown" } },
    get = function() return Wayfinder:GetSetting("unexploredTerrain") end,
    set = function(value) Wayfinder:SetSetting("unexploredTerrain", value) end,
    available = mapReady,
    tooltip = "How unexplored areas appear.\n\nHidden: detailed terrain shows only explored areas.\nDarkened: unexplored areas are dimmed.\nShown: map art and terrain at full brightness." })
wayfinderSlider("unexploredBrightness", "Detail view", "Darkened terrain brightness",
    "How bright unexplored terrain is when it is darkened.", 0.15, 0.8, 0.05, Percent)
wayfinder("shareExploration", "Detail view", "Share exploration between characters",
    "Show terrain explored by any of your characters, not only this one.")
wayfinder("showLiveQuests", "Detail view", "Show quest markers",
    "Mark available quests and completed quests ready to turn in, using the game's map locations.")
wayfinderSlider("detailIconScale", "Detail view", "Detail view icon size", nil, 0.6, 2, 0.1, Percent)
wayfinderSlider("revealRadius", "Detail view", "Reveal radius",
    "How far around you counts as explored. Minimap uses whatever your minimap currently shows.",
    0, 300, 10, Yards)

wayfinder("showMinimapServices", "Live minimap", "Use Wayfinder service markers",
    "Keep Blizzard's native service blips and tracking checkboxes synchronized with Wayfinder. Wayfinder supplies additional service types without duplicating native blips.")
wayfinder("nativeMinimapTurnIns", "Live minimap", "Prefer Blizzard's turn-in markers",
    "Keep the game's quest turn-in tracking on the corner minimap and hide duplicate fixed turn-in pins.")

wayfinder("showArrow", "Waypoints", "Show the waypoint arrow",
    "Middle-click the map (or any icon) to set a waypoint; a floating arrow then points the way. Drag the arrow to move it, right-click it to remove the waypoint.")
wayfinder("clearOnArrival", "Waypoints", "Remove the waypoint when you arrive")
wayfinderSlider("arrowScale", "Waypoints", "Arrow size", nil, 0.5, 2, 0.1, Percent)

wayfinder("showOnWorldMap", "World map", "Show icons on the world map")
wayfinder("showOnContinent", "World map", "Also show icons on continent maps")
wayfinderSlider("iconScale", "World map", "World map icon size", nil, 0.6, 2, 0.1, Percent)
feature({ id = "wayfinder.mapButton", page = "maps", group = "World map", label = "Map menu button",
    addon = "Wayfinder", kind = "action", button = "Reset",
    run = function() Wayfinder.Options:ResetMapButtonPosition() end, available = mapReady,
    tooltip = "Hold Shift and drag the Wayfinder button on the world map to move it. Reset places it beside the top-right buttons." })

-- Every service category Wayfinder knows about, in its own order.
feature({ id = "wayfinder.cats.all", page = "maps", group = "Icons", label = "Every service icon",
    addon = "Wayfinder", kind = "action", button = "Show all",
    run = function()
        for _, cat in ipairs(Wayfinder.CategoryList) do Wayfinder:SetCategoryEnabled(cat.id, true) end
    end, available = mapReady, tooltip = "Turns on every category below." })
feature({ id = "wayfinder.cats.none", page = "maps", group = "Icons", label = "No service icons",
    addon = "Wayfinder", kind = "action", button = "Hide all",
    run = function()
        for _, cat in ipairs(Wayfinder.CategoryList) do Wayfinder:SetCategoryEnabled(cat.id, false) end
    end, available = mapReady, tooltip = "Turns off every category below." })
if Wayfinder and Wayfinder.CategoryList then
    for _, cat in ipairs(Wayfinder.CategoryList) do
        local id = cat.id
        checkbox("wayfinder.cat." .. id, "maps", "Icons", cat.label, "Wayfinder",
            function() return Wayfinder:IsCategoryEnabled(id) end,
            function(value) Wayfinder:SetCategoryEnabled(id, value) end,
            "Show " .. cat.label:lower() .. " on the map and minimap.", false, mapReady)
    end
end

wayfinder("recordMouseover", "Discovery", "Record NPCs you mouse over",
    "Besides NPCs you talk to, remember service NPCs you mouse over or target nearby. Their position is approximate until you get closer or talk to them.")
wayfinder("showApproximate", "Discovery", "Show approximate locations",
    "Show NPCs whose position is only known roughly (drawn slightly faded).")
wayfinder("useSeedData", "Discovery", "Built-in town services",
    "Mailboxes, bankers, innkeepers, trainers and flight masters known in advance. Each one only appears once you have explored the spot.")
wayfinder("importExploration", "Discovery", "Import explored areas from the world map",
    "Count every area the world map shows as discovered as explored terrain, so characters who explored before installing Wayfinder start with their map filled in.")
wayfinder("showOtherFaction", "Discovery", "Show the other faction's NPCs")
wayfinder("showAllClassTrainers", "Discovery", "Show trainers for every class")

feature({ id = "wayfinder.reimport", page = "maps", group = "Map data", label = "Explored areas",
    addon = "Wayfinder", kind = "action", button = "Re-import", available = mapReady,
    run = function()
        Wayfinder.Exploration:QueueImportAll(true)
        Wayfinder.Print("Re-importing explored areas from the world map in the background.")
    end, tooltip = "Read the world map's discovered areas again for this character." })
feature({ id = "wayfinder.erasePois", page = "maps", group = "Map data", label = "Recorded locations",
    addon = "Wayfinder", kind = "action", button = "Erase...", available = mapReady,
    run = function() Wayfinder:ConfirmReset("pois") end,
    tooltip = "Forget every location you have recorded. Built-in ones come back." })
feature({ id = "wayfinder.eraseExploration", page = "maps", group = "Map data", label = "Exploration",
    addon = "Wayfinder", kind = "action", button = "Erase...", available = mapReady,
    run = function() Wayfinder:ConfirmReset("exploration") end,
    tooltip = "Forget this character's explored terrain." })

---------------------------------------------------------------------------
-- Gearwise
---------------------------------------------------------------------------
local function gearReady() return Gearwise and Gearwise.db and true or false end

feature({ id = "gearwise.status", page = "bags", group = "Build", label = "Reading your talents...",
    addon = "Gearwise", kind = "info", available = gearReady,
    get = function()
        local p = Gearwise.profile
        if not p then return "Class data unavailable." end
        return ("Scoring for %s %s  \194\183  %s  \194\183  %s  \194\183  level %d")
            :format(p.label, p.className, p.source, p.leveling and "Leveling" or "Standard", p.level)
    end })
feature({ id = "gearwise.spec", page = "bags", group = "Build", label = "Build", addon = "Gearwise",
    kind = "select", available = gearReady,
    options = function()
        local _, class = UnitClass("player")
        local list = { { "auto", "Automatic (talents)" } }
        for _, profile in ipairs(Gearwise.Profiles.classes[class] or {}) do
            list[#list + 1] = { profile.key, profile.label }
        end
        return list
    end,
    get = function() return Gearwise.db.spec end,
    set = function(value) Gearwise:SetOption("spec", value) end,
    tooltip = "Which build the scores are for. Automatic follows where your talent points went." })
feature({ id = "gearwise.mode", page = "bags", group = "Build", label = "Stat priorities", addon = "Gearwise",
    kind = "select", available = gearReady,
    choices = { { "auto", "Automatic" }, { "leveling", "Leveling" }, { "standard", "Standard" } },
    get = function() return Gearwise.db.mode end,
    set = function(value) Gearwise:SetOption("mode", value) end,
    tooltip = "Leveling gives health and recovery more value. Automatic uses it below level 60." })

for _, item in ipairs({
    { "bags", "Bag upgrade arrows", "An arrow on every bag item that beats what you are wearing." },
    { "quests", "Quest reward advice", "Arrows on quest rewards, and a coin on the one worth the most gold." },
    { "unusable", "Shade unusable equipment", "Tints equipment your class or level cannot use." },
    { "popups", "Upgrade notifications", "A prompt when something you loot scores higher than your current gear." },
    { "spaceToEquip", "Space equips the upgrade", "While the upgrade prompt is open, Space equips the item instead of jumping, the way it accepts a quest at an NPC. It yields to typing, combat, popups and NPC windows, and the prompt shows a Space chip when this is on." },
    { "styles", "Equal-value look offers", "When a looted item ties with what you are wearing, a small badge appears at the edge of the screen. Hover it to see your character in both versions, then keep either one. Declined items never ask again." },
    { "tooltips", "Item comparison tooltips", "Adds the score difference and stat changes to item tooltips." },
}) do
    local key, label, tooltip = item[1], item[2], item[3]
    checkbox("gearwise." .. key, "bags", "Advice", label, "Gearwise",
        function() return Gearwise.db[key] end,
        function(value)
            Gearwise:SetOption(key, value)
            -- The hotkey has to be armed or cleared on a prompt that is
            -- already open, not only on the next one.
            if key == "spaceToEquip" then Gearwise.Upgrades:RefreshKeys() end
        end, tooltip, false, gearReady)
end

feature({ id = "gearwise.reviewUpgrades", page = "bags", group = "Bag review", label = "Upgrades in your bags",
    addon = "Gearwise", kind = "action", button = "Review", available = gearReady,
    run = function()
        if Gearwise.db.popups then Gearwise.Upgrades:Review()
        else Gearwise.Print("Turn on upgrade notifications first.") end
    end, tooltip = "Compares everything in your bags and prompts for each upgrade." })
feature({ id = "gearwise.reviewStyles", page = "bags", group = "Bag review", label = "Equal-value looks",
    addon = "Gearwise", kind = "action", button = "Review", available = gearReady,
    run = function() Gearwise.Sidegrades:Review() end,
    tooltip = "Offers every bag item worth exactly what you are wearing, so you can choose on looks." })
feature({ id = "gearwise.forgetStyles", page = "bags", group = "Bag review", label = "Declined looks",
    addon = "Gearwise", kind = "action", button = "Forget", available = gearReady,
    run = function()
        local count = Gearwise.Sidegrades:ClearDeclined()
        Gearwise.Print(("Forgot %d declined item%s."):format(count, count == 1 and "" or "s"))
    end, tooltip = "Lets items you turned down ask again next time you loot one." })

---------------------------------------------------------------------------
-- Peddler
---------------------------------------------------------------------------
local function sellReady() return ns:Loaded("Peddler") end

local function remark()
    local module = MiniQoLRuntime and MiniQoLRuntime.namespaces.Peddler
    if module and module.markWares then module.markWares() end
end

local function peddler(key, group, label, tooltip, reload)
    checkbox("peddler." .. key, "selling", group, label, "Peddler",
        function() return not not _G[key] end,
        function(value) _G[key] = value; remark() end,
        tooltip, reload, sellReady)
end

peddler("AutoSellGreyItems", "Automatic marking", "Automatically sell junk",
    "Marks every poor quality item for sale as soon as it reaches your bags.")
peddler("SoulboundOnly", "Automatic marking", "Restrict automatic marks to soulbound",
    "Automatic marks skip anything you could still sell or trade. Junk is always marked.")
peddler("AutoSellWhiteItems", "Automatic marking", "Automatically mark common equipment")
peddler("AutoSellGreenItems", "Automatic marking", "Automatically mark uncommon equipment")
peddler("AutoSellBlueItems", "Automatic marking", "Automatically mark rare equipment")
peddler("AutoSellPurpleItems", "Automatic marking", "Automatically mark epic equipment")
peddler("AutoSellUnwantedItems", "Automatic marking", "Mark equipment unusable by my class",
    "For example, a priest marks every piece of plate.")

peddler("SellLimit", "At the vendor", "Respect the buyback item limit",
    "Sells at most twelve items at a time, so everything stays in the buyback tab.")
peddler("Silent", "At the vendor", "Quiet sale messages",
    "Stops the per-item price lines in chat.")
peddler("SilenceSaleSummary", "At the vendor", "Hide sale summaries",
    "Stops the total earned line after a sale.")

feature({ id = "peddler.modifier", page = "selling", group = "Marking by hand", label = "Marking modifier",
    addon = "Peddler", kind = "select", available = sellReady,
    choices = { { "CTRL", "Ctrl" }, { "ALT", "Alt" }, { "SHIFT", "Shift" },
        { "CTRL-SHIFT", "Ctrl-Shift" }, { "CTRL-ALT", "Ctrl-Alt" }, { "ALT-SHIFT", "Alt-Shift" } },
    get = function() return ModifierKey or "CTRL" end,
    set = function(value) ModifierKey = value end,
    tooltip = "Hold this and right-click an item in your bags to mark or unmark it for sale." })
feature({ id = "peddler.icon", page = "selling", group = "Marking by hand", label = "Coin icon corner",
    addon = "Peddler", kind = "select", available = sellReady, reload = true,
    choices = { { "TOPLEFT", "Top left" }, { "TOPRIGHT", "Top right" },
        { "BOTTOMLEFT", "Bottom left" }, { "BOTTOMRIGHT", "Bottom right" } },
    get = function() return IconPlacement or "BOTTOMLEFT" end,
    set = function(value) IconPlacement = value end,
    tooltip = "Which corner of a bag slot shows the coin on items marked for sale." })
feature({ id = "peddler.clear", page = "selling", group = "Marking by hand", label = "Items you marked",
    addon = "Peddler", kind = "action", button = "Clear", available = sellReady,
    run = function() ItemsToSell = {}; remark() end,
    tooltip = "Forgets every item you marked by hand on this character. Automatic marking rules are untouched." })

---------------------------------------------------------------------------
-- XP Counter
---------------------------------------------------------------------------
local function xp()
    return MiniQoLRuntime and MiniQoLRuntime.namespaces.XPCounter
end
local function xpReady()
    local module = xp()
    return module ~= nil and module.MiniQoLSetPopups ~= nil
end

checkbox("xp.popups", "quests", "Floating text", "Floating XP and reputation text", "XPCounter",
    function() return XPCounterDB and XPCounterDB.popupsEnabled end,
    function(value) xp().MiniQoLSetPopups(value) end,
    "Shows each gain on screen as well as in chat. Chat reports stay on either way.",
    false, xpReady)
feature({ id = "xp.move", page = "quests", group = "Floating text", label = "On-screen position",
    addon = "XPCounter", kind = "action", button = "Move", available = xpReady,
    run = function()
        if not (XPCounterDB and XPCounterDB.popupsEnabled) then
            ns:Print("Turn floating text on first.")
            return
        end
        if ns.panel then ns.panel:Hide() end
        xp().MiniQoLStartMoving()
    end,
    tooltip = "Closes this panel and lets you drag the floating text. Right-click it when you are done." })
feature({ id = "xp.test", page = "quests", group = "Floating text", label = "Sample message",
    addon = "XPCounter", kind = "action", button = "Show", available = xpReady,
    run = function() xp().MiniQoLPreview() end,
    tooltip = "Shows one example message where the floating text will appear." })
feature({ id = "xp.reset", page = "quests", group = "Floating text", label = "Text position",
    addon = "XPCounter", kind = "action", button = "Reset", available = xpReady,
    run = function() xp().MiniQoLResetPosition() end,
    tooltip = "Puts the floating text back above the centre of the screen." })

---------------------------------------------------------------------------
-- Mini QoL itself
---------------------------------------------------------------------------
checkbox("miniqol.icon", "miniqol", "Panel", "Show minimap button", nil,
    function() return not ns.db.minimap.hide end,
    function(value) ns.db.minimap.hide = not value; ns:UpdateMinimapButton() end,
    "The gear button beside the minimap opens this panel. Use /mqol icon to bring it back.")
feature({ id = "miniqol.resetpos", page = "miniqol", group = "Panel", label = "Panel and button position",
    kind = "action", button = "Reset",
    run = function()
        ns.db.position, ns.db.minimap.angle = nil, 220
        if ns.panel then ns.panel:ClearAllPoints(); ns.panel:SetPoint("CENTER") end
        ns:UpdateMinimapButton()
    end,
    tooltip = "Moves this panel back to the centre of the screen and the minimap button back to its default spot." })
