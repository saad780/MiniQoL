local _, ns = ...
---------------------------------------------------------------------------
-- Tips: one line in chat about something easy to miss, each time you log in
-- or reload and at no other time. Much of Mini QoL is a click or a command
-- nothing on screen points to (middle-clicking a quest, Shift-dragging the
-- map button), so each tip is shown once per account, in the order below,
-- and then they stop. "/mqol tip" shows the next one at once.
---------------------------------------------------------------------------
local Tips = {}
ns.Tips = Tips

local KEY = "|cffffd100" -- what to press, click or type
local OFF = "|r"

local function Wayfinder()
    return type(_G.Wayfinder) == "table" and _G.Wayfinder.db ~= nil
end
local function WayfinderSetting(key)
    return function() return Wayfinder() and _G.Wayfinder:GetSetting(key) and true or false end
end
local function Questie()
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Questie") and true or false
end

-- `id` is what's saved once a tip has been shown: keep it when the text
-- changes. `when` leaves a tip out while it doesn't apply; it is tried again
-- at a later login.
Tips.LIST = {
    { id = "panel", text = "Every setting is in one place: " .. KEY .. "/mqol" .. OFF
        .. " or the gear button by the minimap. Its search box finds a setting by any word in it." },
    { id = "waypoint", when = Wayfinder, text = KEY .. "Middle-click" .. OFF
        .. " the world map, or any icon on it, to set a waypoint; an arrow then points the way. "
        .. KEY .. "/way 42 65" .. OFF .. " works too, and so do the coordinates guides paste into chat." },
    { id = "questFollow", when = WayfinderSetting("questMiddleClick"), text = KEY .. "Middle-click" .. OFF
        .. " a quest in the quest log or the objective tracker to follow it: the arrow leads to where its creatures"
        .. " stand thickest, then to the turn-in. Middle-click it again to stop." },
    { id = "arrowMenu", when = WayfinderSetting("showArrow"), text = KEY .. "Right-click" .. OFF
        .. " the waypoint arrow for every waypoint you've set, " .. KEY .. "middle-click" .. OFF
        .. " it to remove the one it's on, and drag it anywhere: it snaps to the middle of the screen." },
    { id = "detail", when = WayfinderSetting("detailEnabled"), text = "Zoom the world map all the way in and"
        .. " keep scrolling: it carries on into the minimap's own terrain, roads and buildings included." },
    { id = "targetFinder", when = Wayfinder, text = KEY .. "Shift + middle-click" .. OFF
        .. " a creature (or its nameplate) to track it with Target Finder, or type " .. KEY .. "/mqol track"
        .. OFF .. " and part of a name. " .. KEY .. "Shift + middle-click" .. OFF
        .. " a tracked quest to watch for its targets." },
    { id = "antTrails", when = WayfinderSetting("antTrails"), text = "The dots marching across the world map"
        .. " and minimap are the walking route to your waypoint. Their color, and where they show, are under"
        .. " Maps & travel in " .. KEY .. "/mqol" .. OFF .. "." },
    { id = "mapButton", when = Wayfinder, text = "The map button in the world map's corner switches each kind"
        .. " of icon on or off. " .. KEY .. "Shift-drag" .. OFF .. " it to move it." },
    { id = "find", text = KEY .. "/mqol find" .. OFF .. " searches NPCs, creatures, quests, items and"
        .. " gathering spots, and " .. KEY .. "/mqol nearby" .. OFF .. " lists gear upgrades around you." },
    { id = "dialogue", when = function() return ns.db.dialogue and ns.db.dialogue.enabled == true end, text = "At an NPC, " .. KEY .. "1" .. OFF .. " to " .. KEY .. "9" .. OFF
        .. " pick the options in order and " .. KEY .. "Space" .. OFF .. " accepts or continues a quest." },
    { id = "fishing", text = KEY .. "/mqol fish" .. OFF .. " puts on your fishing outfit and back again;"
        .. " " .. KEY .. "/mqol fish gear" .. OFF .. " chooses what's in it." },
    { id = "questie", when = Questie, text = KEY .. "Middle-click" .. OFF
        .. " a quest in Questie's tracker follows it with the arrow too." },
    { id = "blocked", text = "Seen \"Interface action failed\"? " .. KEY .. "/mqol blocked" .. OFF
        .. " lists which addon the game blamed, and for what." },
}

local function Seen()
    if type(ns.db.tipsSeen) ~= "table" then ns.db.tipsSeen = {} end
    return ns.db.tipsSeen
end

local function Applies(tip)
    if not tip.when then return true end
    local ok, result = pcall(tip.when)
    return ok and result == true
end

-- The first tip not shown yet that applies now.
function Tips.Next()
    local seen = Seen()
    for _, tip in ipairs(Tips.LIST) do
        if not seen[tip.id] and Applies(tip) then return tip end
    end
end

local function Show(tip)
    Seen()[tip.id] = true
    ns:Print("Tip: " .. tip.text)
end

-- At login: one tip, unless they're switched off or all seen.
function Tips.OnLogin()
    if ns.db.tips == false then return end
    local tip = Tips.Next()
    -- after the login messages, so it isn't scrolled away at once
    if tip and C_Timer then C_Timer.After(8, function() if ns.db.tips ~= false then Show(tip) end end) end
end

-- /mqol tip: the next one now. Once every tip has been shown, they start over.
function Tips.ShowNext()
    local tip = Tips.Next()
    if not tip then
        ns.db.tipsSeen = {}
        tip = Tips.Next()
    end
    if tip then Show(tip) end
end
