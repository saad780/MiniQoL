local _, ns = ...
-- The Fishing page in the Mini QoL panel. Settings live here; the outfit has
-- its own window, and the live readout while you fish is the floating bar.
local Fishing = ns.Fishing
local T = ns.Theme
local history

local function RefreshHistory()
    if not history or not history:IsShown() then return end
    local zone = history.pickedZone
    if zone == nil then zone = GetRealZoneText() or "" end
    local total, entries = Fishing:FishHistory(zone or nil, history.allLoot)
    local name = zone == "" and "Current zone" or zone or "All zones"
    history.zoneButton:SetText(name .. "  |TInterface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up:12|t")
    local record = Fishing.db.zones[zone]
    local missing = record and record.unidentified or 0
    history.note:SetShown(missing > 0)
    if missing > 0 then
        history.note:SetText(missing == 1 and "One earlier catch lacks item details."
            or ("%d earlier catches lack item details."):format(missing))
    end
    history.total:SetText(history.allLoot and ("%d items caught"):format(total) or ("%d fish caught"):format(total))
    history.fish:SetPrimary(not history.allLoot)
    history.loot:SetPrimary(history.allLoot)
    for i, entry in ipairs(entries) do
        local row = history.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, history.list)
            row:SetSize(310, 21)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * 21)
            row.name = T:Text(row, "", "GameFontHighlightSmall", 202, T.TEXT)
            row.name:SetWordWrap(false)
            row.name:SetPoint("LEFT")
            row.count = T:Text(row, "", "GameFontHighlightSmall", 52, T.TEXT)
            row.count:SetJustifyH("RIGHT")
            row.count:SetPoint("RIGHT", -54, 0)
            row.share = T:Text(row, "", "GameFontHighlightSmall", 52, T.GOLD)
            row.share:SetJustifyH("RIGHT")
            row.share:SetPoint("RIGHT")
            history.rows[i] = row
        end
        row.name:SetText(entry.name or ("Item %d"):format(entry.itemID))
        row.count:SetText(entry.count)
        row.share:SetText(entry.percent < 0.1 and "<0.1%" or ("%.1f%%"):format(entry.percent))
        row:Show()
    end
    for i = #entries + 1, #history.rows do history.rows[i]:Hide() end
    history.list:SetHeight(math.max(1, #entries * 21))
end

local function PickHistoryZone(button)
    local options = {}
    for zone in pairs(Fishing.db.zones) do
        if zone ~= "" then options[#options + 1] = zone end
    end
    table.sort(options)
    local function pick(zone)
        history.pickedZone = zone
        history.scroll:SetVerticalScroll(0)
        RefreshHistory()
    end
    if not (ns.ControllerSafeMenu or (MenuUtil and MenuUtil.CreateContextMenu)) then
        if history.pickedZone == nil then pick(options[1] or false)
        elseif history.pickedZone == false then pick(nil)
        else
            for i, zone in ipairs(options) do
                if zone == history.pickedZone then pick(options[i + 1] or false); return end
            end
            pick(nil)
        end
        return
    end
    ns.ContextMenu(button, function(_, root)
        root:CreateTitle("Fishing zone")
        local function option(label, zone)
            root:CreateRadio(label, function() return history.pickedZone == zone end, function() pick(zone) end)
        end
        option("Follow current zone", nil)
        for _, zone in ipairs(options) do option(zone, zone) end
        option("All zones", false)
    end)
end

function Fishing:OpenHistory()
    if not history then
        history = CreateFrame("Frame", "MiniQoLFishHistory", UIParent, "BackdropTemplate")
        history:Hide()
        history:SetSize(360, 388)
        history:SetPoint("CENTER")
        history:SetFrameStrata("DIALOG")
        history:SetClampedToScreen(true)
        history:SetMovable(true)
        history:EnableMouse(true)
        history:RegisterForDrag("LeftButton")
        history:SetScript("OnDragStart", history.StartMoving)
        history:SetScript("OnDragStop", history.StopMovingOrSizing)
        T:Window(history, 28)
        T:Text(history, "Fishing history by zone", "GameFontNormal", 280, T.GOLD):SetPoint("TOPLEFT", 14, -8)
        T:CloseButton(history, function() history:Hide() end):SetPoint("TOPRIGHT", -4, -4)

        local function selectLoot(all)
            history.allLoot = all
            history.scroll:SetVerticalScroll(0)
            RefreshHistory()
        end
        history.zoneButton = T:Button(history, "", 330, 22, PickHistoryZone)
        history.zoneButton:SetPoint("TOPLEFT", 14, -36)
        history.fish = T:Button(history, "Fish", 56, 22, function() selectLoot(false) end)
        history.fish:SetPoint("TOPLEFT", 14, -66)
        history.loot = T:Button(history, "All catches", 84, 22, function() selectLoot(true) end)
        history.loot:SetPoint("LEFT", history.fish, "RIGHT", 4, 0)
        history.total = T:Text(history, "", "GameFontHighlightSmall", 172, T.TEXT)
        history.total:SetJustifyH("RIGHT")
        history.total:SetPoint("TOPRIGHT", -16, -72)
        history.note = T:Text(history, "", "GameFontDisableSmall", 328, T.MUTED)
        history.note:SetPoint("BOTTOMLEFT", 14, 10)
        history.scroll = CreateFrame("ScrollFrame", "MiniQoLFishHistoryScroll", history, "UIPanelScrollFrameTemplate")
        history.scroll:SetPoint("TOPLEFT", 14, -100)
        history.scroll:SetPoint("BOTTOMRIGHT", -36, 32)
        T:SkinScrollBar(history.scroll, "MiniQoLFishHistoryScroll")
        history.list = CreateFrame("Frame", nil, history.scroll)
        history.list:SetSize(310, 1)
        history.rows = {}
        history.scroll:SetScrollChild(history.list)
        history:SetScript("OnShow", RefreshHistory)
        history:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        history:RegisterEvent("ZONE_CHANGED")
        history:RegisterEvent("PLAYER_ENTERING_WORLD")
        history:SetScript("OnEvent", function()
            if history.pickedZone == nil then RefreshHistory() end
        end)
        self:On("CATCHES_CHANGED", RefreshHistory)
    end
    if not history:IsShown() then
        history.pickedZone = nil
        history.scroll:SetVerticalScroll(0)
        history:Show()
    end
    history:Raise()
end

local function ready() return Fishing.db ~= nil end

local function feature(spec)
    spec.page = "fishing"
    ns:RegisterFeature(spec)
end

local function checkbox(key, group, label, tooltip, extra)
    local spec = { id = "fishing." .. key, group = group, label = label, kind = "check",
        tooltip = tooltip, available = ready,
        get = function() return Fishing:Get(key) end,
        set = function(value) Fishing:Set(key, value) end }
    for field, value in pairs(extra or {}) do spec[field] = value end
    feature(spec)
end

local function soundOn() return ready() and Fishing:Get("sound") end

function Fishing:RegisterPage()
    ---------------------------------------------------------------------
    -- Casting and reeling in
    ---------------------------------------------------------------------
    feature({ id = "fishing.castMode", group = "Casting", label = "Cast with", kind = "select",
        available = ready, controlWidth = 132,
        choices = { { "doubleClick", "Double right-click" }, { "hotkey", "A key" }, { "none", "Your action bar" } },
        get = function() return Fishing:Get("castMode") end,
        set = function(value) Fishing:Set("castMode", value) end,
        tooltip = "How to cast with a pole in hand. Double right-click leaves single right-clicks alone, so looting and targeting still work. Your action bar means Mini QoL adds nothing; cast the spell as usual." })
    feature({ id = "fishing.castKey", group = "Casting", label = "Cast key", kind = "select",
        available = function() return ready() and Fishing:Get("castMode") == "hotkey" end,
        unavailable = "Set Cast with to A key to choose one.",
        choices = { { "BUTTON3", "Middle mouse" }, { "BUTTON4", "Mouse 4" }, { "BUTTON5", "Mouse 5" },
            { "F", "F" }, { "G", "G" }, { "V", "V" }, { "`", "`" } },
        get = function() return Fishing:Get("castKey") end,
        set = function(value) Fishing:Set("castKey", value) end,
        tooltip = "Bound only while a fishing pole is equipped and you are out of combat, so it is free the rest of the time." })
    checkbox("reelIn", "Casting", "Reel in with a key",
        "While the line is out, a key loots the bobber, so you never have to click it. The game's Interact Key option is switched on for the cast and set back afterwards.")
    feature({ id = "fishing.reelInKey", group = "Casting", label = "Reel-in key", kind = "select",
        available = function() return ready() and Fishing:Get("reelIn") end,
        unavailable = "Turn on Reel in with a key first.",
        choices = { { "BUTTON2", "Right mouse" }, { "BUTTON3", "Middle mouse" }, { "BUTTON4", "Mouse 4" },
            { "BUTTON5", "Mouse 5" }, { "F", "F" }, { "G", "G" } },
        get = function() return Fishing:Get("reelInKey") end,
        set = function(value) Fishing:Set("reelInKey", value) end,
        tooltip = "Only bound while the line is out." })
    checkbox("autoLure", "Casting", "Apply a lure if the pole has none",
        "The first cast with a bare pole puts on the strongest lure you carry and can use; the next one casts.")

    ---------------------------------------------------------------------
    -- Splash
    ---------------------------------------------------------------------
    checkbox("sound", "Splash", "Louder splash while fishing",
        "Raises the game and effects volume while the line is out, and mutes music and ambience, so the splash is easy to hear. Everything is put back when the cast ends -- and at login, if the game closed mid-cast.")
    checkbox("soundInBackground", "Splash", "Hear it while alt-tabbed",
        "Keeps the splash audible with the game in the background. Put back with everything else when the cast ends.",
        { available = soundOn, unavailable = "Turn on Louder splash while fishing first." })
    feature({ id = "fishing.volume", group = "Splash", label = "Volume while fishing", kind = "slider",
        min = 0.1, max = 1, step = 0.05, available = soundOn,
        unavailable = "Turn on Louder splash while fishing first.",
        format = function(value) return ("%d%%"):format(math.floor(value * 100 + 0.5)) end,
        get = function() return Fishing:Get("volume") end,
        set = function(value) Fishing:Set("volume", value) end,
        tooltip = "How loud the game gets while the line is out." })

    ---------------------------------------------------------------------
    -- The fishing outfit
    ---------------------------------------------------------------------
    feature({ id = "fishing.outfit", group = "Fishing outfit", label = "Fishing outfit", kind = "action",
        wide = true, button = "Edit outfit", primary = true, available = ready,
        text = function() return Fishing:OutfitSummary() end,
        run = function() Fishing:OpenOutfit() end,
        tooltip = "Opens the outfit: your pole, hat, boots and anything else you fish in. Pick each slot, let it find your fishing gear, or copy what you have on. Swapping puts it on, and swapping again puts back exactly what you wore." })
    feature({ id = "fishing.gearMacro", group = "Swapping", label = "Action bar button",
        kind = "action", button = "Pick up", available = ready,
        run = function() Fishing:PickupGearMacro() end,
        tooltip = "Puts a \"MiniQoL Fish\" macro on your cursor. Drop it on any action bar: click it to change into the outfit, click again to change back. /mqol fish does the same." })
    checkbox("announceGear", "Swapping", "Say in chat when it swaps",
        "Prints a line each time you change in or out of the outfit, so you know it took.")

    ---------------------------------------------------------------------
    -- The window and the record
    ---------------------------------------------------------------------
    checkbox("bar", "Fishing window", "Show it while holding a pole",
        "A small window with your lures, fishing food, skill breakdown, your last catch and everything caught this session. It appears on its own when you equip a pole; /mqol fish show opens it anywhere.")
    checkbox("statsIncludeMissed", "Fishing window", "Count empty casts",
        "Adds the casts that caught nothing to the window's session line, along with the share of casts that caught something.")
    feature({ id = "fishing.history", group = "Catch record", label = "Catch percentages by zone",
        kind = "action", button = "View history", available = ready,
        run = function() Fishing:OpenHistory() end })
    feature({ id = "fishing.resetSession", group = "Catch record", label = "This session",
        kind = "action", button = "Reset", available = ready,
        run = function() Fishing:ResetSession(); ns:Print("Started a new fishing session.") end,
        tooltip = "Clears what you have caught this sitting. All-time totals are kept." })
    feature({ id = "fishing.resetAll", group = "Catch record", label = "Every catch ever",
        kind = "action", button = "Erase...", available = ready,
        run = function() StaticPopup_Show("MINIQOL_FISHING_RESET") end,
        tooltip = "Forgets every fish, zone and lure recorded, for good. Settings and your outfit are kept." })
    feature({ id = "fishing.record", group = "Catch record", kind = "info", available = ready,
        label = "Nothing caught yet.",
        get = function()
            local total = Fishing:TotalCaught()
            if total == 0 then return "Nothing caught yet." end
            local _, missed, average = Fishing:CastSummary()
            local zone = Fishing:FavouriteZone()
            local sessions = Fishing.db.sessions
            local parts = { ("%d caught over %d %s"):format(total, sessions, sessions == 1 and "session" or "sessions") }
            if zone then parts[#parts + 1] = ("most in %s (%.0f%%)"):format(zone.name, zone.percent) end
            if average then parts[#parts + 1] = ("%.0fs a catch"):format(average) end
            if missed > 0 then parts[#parts + 1] = ("%d empty casts"):format(missed) end
            return table.concat(parts, "  \194\183  ")
        end })
end

StaticPopupDialogs.MINIQOL_FISHING_RESET = {
    text = "Mini QoL: erase every fishing record? This cannot be undone.",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        ns.Fishing:ResetAll()
        ns:Print("Fishing records erased.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
