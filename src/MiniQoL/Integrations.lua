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
    "Middle-click the map (or any icon) to set a waypoint; a floating arrow then points the way. Several can stand at once: type /way 42 65, or let an addon that speaks TomTom's language add them. Drag the arrow to move it, middle-click it to remove the one it is on, right-click it for the whole list.")
wayfinder("followWalkingRoute", "Waypoints", "Follow walking turns with the arrow",
    "Aim ahead along the walking route to your objective or next transport stop. Turn this off to point straight at that destination.")
feature({ id = "wayfinder.routeStyle", page = "maps", group = "Waypoints", label = "Route style",
    addon = "Wayfinder", kind = "select",
    choices = { { "fastest", "Direct" }, { "balanced", "Balanced" }, { "roads", "Roads Always" } },
    get = function() return Wayfinder.Navigation:GetRouteStyle() end,
    set = function(value) Wayfinder:SetSetting("routeStyle", value) end,
    available = mapReady,
    tooltip = "Direct favors the shortest walkable route. Balanced uses roads when the detour is small. Roads Always strongly favors roads and avoids steep terrain.\n\nWalking maps cover Eastern Kingdoms, Kalimdor, and Zephras Isle." })
wayfinder("antTrails", "Waypoints", "Show ant trails",
    "Follow the dots on the continuous world map and minimap to walk the route to your waypoint or the next transport stop. Outside walking map coverage, the dots lead straight to that point.")
local function antTrails() return mapReady() and Wayfinder:GetSetting("antTrails") and true or false end
feature({ id = "wayfinder.antTrailsWhere", page = "maps", group = "Waypoints", label = "Ant trails on",
    addon = "Wayfinder", kind = "select",
    choices = { { "both", "Map and minimap" }, { "map", "World map" }, { "minimap", "Minimap" } },
    get = function() return Wayfinder:GetSetting("antTrailsWhere") end,
    set = function(value) Wayfinder:SetSetting("antTrailsWhere", value) end,
    available = antTrails,
    tooltip = "Where the ant trails show. The world map's is on the continuous map." })
feature({ id = "wayfinder.antTrailColor", page = "maps", group = "Waypoints", label = "Ant trail color",
    addon = "Wayfinder", kind = "select",
    choices = { { "cyan", "Arrow cyan" }, { "gold", "Gold" }, { "green", "Green" }, { "white", "White" } },
    get = function() return Wayfinder:GetSetting("antTrailColor") end,
    set = function(value) Wayfinder:SetSetting("antTrailColor", value) end,
    available = antTrails,
    tooltip = "The dots' color. Each has a dark edge so it shows on any ground." })
wayfinder("travelHearth", "Waypoints", "Use Hearthstone in travel routes",
    "Suggest your ready Hearthstone when casting it and traveling from your bound inn gets you to the waypoint sooner.")
wayfinder("travelFlights", "Waypoints", "Use flight points in travel routes",
    "Guide you to the flight master and name the destination to select. If a useful departure is new, the arrow prompts you to learn it.")
wayfinder("travelTransports", "Waypoints", "Use boats, zeppelins and other transports",
    "Guide you to the departure for the next boat, zeppelin, airship, tram or portal. Travel times include the expected wait.")
wayfinder("clearOnArrival", "Waypoints", "Remove the waypoint when you arrive")
wayfinder("corpseWaypoint", "Waypoints", "Point the arrow at your corpse",
    "When you release your spirit, a waypoint is set on your corpse and the arrow points to it. Coming back to life completes it, wherever that happens, and the arrow returns to the waypoint it was on before.")
wayfinder("questMiddleClick", "Waypoints", "Middle-click a quest to follow it",
    "Middle-click a quest in the quest log, the objective tracker (its title, lines or quest icon) or Questie's tracker. The arrow then points at the nearest place still to do for it or, once it is complete, at where to hand it in. The waypoint moves on as objectives are done and goes when the quest is handed in. Middle-click the same quest again to stop. Uses Questie's quest data when Questie is loaded, otherwise the game's quest markers.")
wayfinder("questAreas", "Waypoints", "Outline a quest's area once you're in it",
    "A quest you follow by middle-click leads to the camp where its creatures or objects stand thickest, not the nearest stray one. Once you're among them, the arrow rests and the area they're spread over is outlined with the ant trail's dots on the world map and minimap: what you're after is somewhere inside it.")
feature({ id = "wayfinder.targetFinder", page = "maps", group = "Waypoints", addon = "Wayfinder",
    kind = "action", label = "Target Finder", button = "Open", available = mapReady,
    run = function() Wayfinder.TargetFinder:Open() end,
    tooltip = "Search for nearby mobs and objects with all or part of a name. Shift + middle-click a mob in the world or on its nameplate to track it, or a tracker quest to watch its targets." })
-- Only listed with Polestar installed: there is nothing to follow without it.
local function polestar()
    return mapReady() and Wayfinder.PolestarFollow ~= nil and Wayfinder.PolestarFollow:Available()
end
feature({ id = "wayfinder.followPolestar", page = "maps", group = "Waypoints", addon = "Wayfinder",
    kind = "check", label = "Show Polestar's guide on this arrow",
    get = function() return Wayfinder:GetSetting("followPolestar") end,
    set = function(value) Wayfinder:SetSetting("followPolestar", value) end,
    available = mapReady, hidden = function() return not polestar() end,
    tooltip = "Polestar's next goal becomes a waypoint on this arrow and moves along as the guide does: to the end of the leg you are on (the flight master to walk to, the boat to catch), then the goal itself. Polestar moves it on when a goal is done, so it isn't removed when you arrive. Removing it lets that goal go in Polestar too, until the guide moves on.\n\nTo hide Polestar's own arrow, turn on \"Let a following addon show the way\" in Polestar's options, under Guide, Arrow & routes, Other waypoints." })
feature({ id = "wayfinder.polestarArrow", page = "maps", group = "Waypoints", addon = "Wayfinder",
    kind = "info", label = "Polestar's own arrow", available = mapReady,
    hidden = function() return not (polestar() and Wayfinder:GetSetting("followPolestar")) end,
    get = function() return Wayfinder.PolestarFollow:Status() end })
wayfinder("arrowTime", "Waypoints", "Show the time to get there",
    "Under the arrow's distance, how long the rest of the way takes at the speed you're moving (or would run or ride at, standing still). Along a walking route the distance is the walk itself, not the straight line.")
wayfinderSlider("arrowScale", "Waypoints", "Arrow size", nil, 0.5, 2, 0.1, Percent)

wayfinder("shareGroupWaypoint", "Group waypoint", "Share my waypoint as group leader",
    "When you lead a party or raid, the waypoint your arrow is on goes to the group members who have Mini QoL, and lands on their arrow. Remove yours and theirs goes too. A waypoint on your corpse is never shared.")
wayfinder("reportGroupWaypoint", "Group waypoint", "Tell me who got it",
    "As leader, a few seconds after your waypoint changes, chat lists who got it, who has following turned off, and who didn't answer (no Mini QoL, or an older one).")
wayfinder("followGroupWaypoint", "Group waypoint", "Take the group leader's waypoint",
    "Your arrow takes the waypoint your group leader shares, and lets it go when they remove theirs or you leave the group. You can still remove it yourself.")

wayfinder("showOnWorldMap", "World map", "Show icons on the world map")
wayfinder("showOnContinent", "World map", "Also show icons on continent maps")
wayfinderSlider("iconScale", "World map", "World map icon size", nil, 0.6, 2, 0.1, Percent)
wayfinder("tooltipDistance", "World map", "Distance in icon tooltips",
    "Adds how far away an icon or waypoint is, and in which direction, to its tooltip on the maps: \"240 yd northeast\".")
wayfinder("zoneMap", "Zone map (Shift+M)", "Wayfinder on the zone map",
    "The small zone map (Shift+M) shows Wayfinder's icons, your waypoints, the ant trail to the one the arrow is on and the area of a followed quest, as the world map does. The icons you've switched on are the same on both.")
wayfinder("zoneMapQuests", "Zone map (Shift+M)", "Quest objectives on the zone map",
    "Mark where the quests you're on take you, from the game's own quest markers, which the zone map otherwise leaves out. Hover one for its objectives; middle-click it to follow the quest with the arrow.")
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
        -- A category only one race can use is listed for that race alone.
        feature({ id = "wayfinder.cat." .. id, page = "maps", group = "Icons", label = cat.label,
            addon = "Wayfinder", kind = "check",
            get = function() return Wayfinder:IsCategoryEnabled(id) end,
            set = function(value) Wayfinder:SetCategoryEnabled(id, value) end,
            tooltip = "Show " .. cat.label:lower() .. " on the map and minimap." .. (cat.hint and (" " .. cat.hint) or ""),
            reload = false, available = mapReady,
            hidden = cat.race and function() return Wayfinder.playerRace ~= cat.race end or nil })
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

feature({ id = "gearwise.nearby", page = "bags", group = "Find gear", label = "Nearby upgrades",
    addon = "Gearwise", kind = "action", button = "Open", available = gearReady,
    run = function() ns:ShowPage("nearby") end,
    tooltip = "Find upgrades from local quests, vendors and drops." })

feature({ id = "gearwise.status", page = "bags", group = "Build", label = "Reading your talents...",
    addon = "Gearwise", kind = "info", available = gearReady,
    get = function()
        local p = Gearwise.profile
        if not p then return "Class data unavailable." end
        return ("Scoring for %s %s  \194\183  %s  \194\183  %s  \194\183  level %d%s")
            :format(p.label, p.className, p.source, p.leveling and "Leveling" or "Standard", p.level,
                p.custom and "  \194\183  your values" or "")
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

-- Stat values: what one point of each stat is worth to the build in use. One
-- row per stat Gearwise knows; a row steps aside where the build does not
-- weigh that stat, so a rogue and a priest see different lists. The rows are
-- only declared when the module is loaded, since the stat list is its own.
if Gearwise and Gearwise.Profiles and Gearwise.Profiles.STATS then
    local Profiles = Gearwise.Profiles
    local function Build()
        local p = gearReady() and Gearwise.profile
        if p then return p.class, p.key, p end
    end
    -- As many decimals as the step needs: 0.5 is one, 0.25 two, 0.005 three.
    local function Places(step)
        for places = 0, 3 do
            local scaled = step * 10 ^ places
            if math.abs(scaled - math.floor(scaled + 0.5)) < 0.0001 then return "%." .. places .. "f" end
        end
        return "%.3f"
    end
    local function Plain(value, step)
        -- "2" rather than "2.00", "0.015" rather than "0.0150".
        return (Places(step):format(value):gsub("(%..-)0+$", "%1"):gsub("%.$", ""))
    end

    feature({ id = "gearwise.values.about", page = "bags", group = "Stat values", label = "Stat values",
        addon = "Gearwise", kind = "info", available = gearReady,
        hidden = function() return Build() == nil end,
        get = function()
            local _, _, p = Build()
            return ("%s %s: what one point of each stat is worth when two items are compared.")
                :format(p.label, p.className)
        end })
    for _, stat in ipairs(Profiles.STATS) do
        feature({ id = "gearwise.value." .. stat.key, page = "bags", group = "Stat values", label = stat.label,
            addon = "Gearwise", kind = "slider", min = 0, max = stat.max, step = stat.step, available = gearReady,
            -- Only what the build weighs is listed.
            hidden = function()
                local class, key = Build()
                return not key or Profiles:Default(class, key, stat.key) == nil
            end,
            -- A changed value names the default it replaced.
            text = function()
                local class, key = Build()
                local value, default = Profiles:Value(class, key, stat.key)
                if value == default then return stat.label end
                return ("%s  |cff9d9d9d(default %s)|r"):format(stat.label, Plain(default, stat.step))
            end,
            format = function(value) return Places(stat.step):format(value) end,
            get = function()
                local class, key = Build()
                return (Profiles:Value(class, key, stat.key))
            end,
            set = function(value)
                local class, key = Build()
                Profiles:SetValue(class, key, stat.key, value)
                Gearwise:Invalidate(false)
            end,
            tooltip = stat.hint .. "\n\nGearwise adds these up to compare two items, so a higher number makes this stat count for more. "
                .. "It applies to this build on this character; the build's own value comes back when you set it back or reset." })
    end
    feature({ id = "gearwise.values.reset", page = "bags", group = "Stat values", label = "Reset stat values",
        addon = "Gearwise", kind = "action", button = "Reset", wide = true,
        hidden = function() return Build() == nil end,
        available = function()
            local class, key = Build()
            return key ~= nil and Profiles:Changed(class, key) > 0
        end,
        unavailable = "Every value is the build's own.",
        text = function()
            local class, key, p = Build()
            local count = Profiles:Changed(class, key)
            return ("%d of %s's values %s yours"):format(count, p.label, count == 1 and "is" or "are")
        end,
        run = function()
            local _, key, p = Build()
            Profiles:Reset(key)
            Gearwise:Invalidate(false)
            Gearwise.Print(p.label .. " is back on its own values.")
        end,
        tooltip = "Puts every value for this build back to Gearwise's own. Other builds keep what you set for them." })
end

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
    "Marks every poor quality item for sale as soon as it reaches your bags. Set for this character only; a new character starts with it off.")
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
checkbox("miniqol.tips", "miniqol", "Panel", "A tip in chat when you log in", nil,
    function() return ns.db.tips ~= false end,
    function(value) ns.db.tips = value and true or false end,
    "One line in chat at login about a click or command that's easy to miss. Each tip shows once, and they stop when you've seen them all. /mqol tip shows the next one now.")
feature({ id = "miniqol.resetpos", page = "miniqol", group = "Panel", label = "Panel and button position",
    kind = "action", button = "Reset",
    run = function()
        ns.db.position, ns.db.minimap.angle = nil, 220
        if ns.panel then ns.panel:ClearAllPoints(); ns.panel:SetPoint("CENTER") end
        ns:UpdateMinimapButton()
    end,
    tooltip = "Moves this panel back to the centre of the screen and the minimap button back to its default spot." })
