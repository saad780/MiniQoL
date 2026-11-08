local _, ns = ...
-- The Fishing page in the Mini QoL panel. Settings and the outfit live here;
-- the live readout while you are actually fishing is the floating bar.
local Fishing = ns.Fishing

local EMPTY = "empty"

local function ready() return Fishing.db ~= nil end

local function feature(spec)
    spec.page = "fishing"
    ns:RegisterFeature(spec)
end

local function checkbox(key, group, label, tooltip)
    feature({ id = "fishing." .. key, group = group, label = label, kind = "check",
        tooltip = tooltip, available = ready,
        get = function() return Fishing:Get(key) end,
        set = function(value) Fishing:Set(key, value) end })
end

function Fishing:RegisterPage()
    ---------------------------------------------------------------------
    -- Splash
    ---------------------------------------------------------------------
    checkbox("sound", "Splash", "Turn the sound up while fishing",
        "Raises master and effects volume while the line is out and silences music and ambience, so the splash is unmistakable. Everything is put back when the cast ends -- and at login, if the game closed mid-cast.")
    feature({ id = "fishing.volume", group = "Splash", label = "Volume while fishing", kind = "slider",
        min = 0.1, max = 1, step = 0.05, available = ready,
        format = function(value) return ("%d%%"):format(math.floor(value * 100 + 0.5)) end,
        get = function() return Fishing:Get("volume") end,
        set = function(value) Fishing:Set("volume", value) end,
        tooltip = "How loud to make the game while the line is out." })
    checkbox("soundInBackground", "Splash", "Keep sound playing when alt-tabbed",
        "Lets you hear the splash with the game in the background. Restored with everything else when the cast ends.")

    ---------------------------------------------------------------------
    -- Casting
    ---------------------------------------------------------------------
    feature({ id = "fishing.castMode", group = "Casting", label = "Cast with", kind = "select",
        available = ready,
        choices = { { "doubleClick", "Double right-click" }, { "hotkey", "A key" }, { "none", "Nothing" } },
        get = function() return Fishing:Get("castMode") end,
        set = function(value) Fishing:Set("castMode", value) end,
        tooltip = "How to start a cast with a pole in hand. Double right-click leaves single right-clicks alone, so looting and targeting still work." })
    feature({ id = "fishing.castKey", group = "Casting", label = "Cast key", kind = "select",
        available = function() return ready() and Fishing:Get("castMode") == "hotkey" end,
        choices = { { "BUTTON3", "Middle mouse" }, { "BUTTON4", "Mouse 4" }, { "BUTTON5", "Mouse 5" },
            { "F", "F" }, { "G", "G" }, { "V", "V" }, { "`", "`" } },
        get = function() return Fishing:Get("castKey") end,
        set = function(value) Fishing:Set("castKey", value) end,
        tooltip = "Bound only while a fishing pole is equipped and you are out of combat." })
    checkbox("autoLure", "Casting", "Put a lure on first when there is none",
        "The first cast with a bare pole applies the strongest lure you are carrying and can actually use; the next one casts.")

    ---------------------------------------------------------------------
    -- Reeling in
    ---------------------------------------------------------------------
    checkbox("reelIn", "Reeling in", "Reel in with a key",
        "Binds a key to the game's interact key while the line is out, so you can reel in without clicking the bobber. The game's Interact Key option is switched on for the cast and set back afterwards.")
    feature({ id = "fishing.reelInKey", group = "Reeling in", label = "Reel-in key", kind = "select",
        available = function() return ready() and Fishing:Get("reelIn") end,
        choices = { { "BUTTON2", "Right mouse" }, { "BUTTON3", "Middle mouse" }, { "BUTTON4", "Mouse 4" },
            { "BUTTON5", "Mouse 5" }, { "F", "F" }, { "G", "G" } },
        get = function() return Fishing:Get("reelInKey") end,
        set = function(value) Fishing:Set("reelInKey", value) end,
        tooltip = "Only bound while the line is out." })

    ---------------------------------------------------------------------
    -- The fishing outfit
    ---------------------------------------------------------------------
    feature({ id = "fishing.gearHelp", group = "Fishing outfit", kind = "info", available = ready,
        label = "Save what you are wearing, or set slots one at a time -- or both.",
        get = function()
            if not Fishing:HasGearSet() then
                return "No outfit yet. Put your fishing kit on and press Save below, or set slots by hand."
            end
            local state = Fishing:WearingGear() and "worn now" or "ready"
            return ("Outfit: %d pieces, %s. Swapping back restores exactly what you had on.")
                :format(Fishing:GearCount(), state)
        end })
    feature({ id = "fishing.gearSnapshot", group = "Fishing outfit", label = "Everything I am wearing now",
        kind = "action", button = "Save", available = ready,
        run = function()
            Fishing:SnapshotGear()
            ns:Print(("Saved your outfit: %d pieces. Adjust any slot below."):format(Fishing:GearCount()))
        end,
        tooltip = "Takes a snapshot of every equipped slot as the fishing outfit. Slots you have nothing in are recorded as deliberately empty. You can change any slot afterwards." })
    feature({ id = "fishing.gearClear", group = "Fishing outfit", label = "Start the outfit again",
        kind = "action", button = "Clear", available = ready,
        run = function() Fishing:ClearGear(); ns:Print("Fishing outfit cleared.") end,
        tooltip = "Forgets the whole outfit. Every slot goes back to being left alone." })
    feature({ id = "fishing.gearSwap", group = "Fishing outfit", label = "Swap now",
        kind = "action", button = "Swap", available = function() return ready() and Fishing:HasGearSet() end,
        run = function() Fishing:ToggleGear() end,
        tooltip = "The same thing /mqol fish and the action bar button do: into the fishing outfit, then back to your own gear." })
    feature({ id = "fishing.gearMacro", group = "Fishing outfit", label = "Button for your action bar",
        kind = "action", button = "Pick up", available = ready,
        run = function() Fishing:PickupGearMacro() end,
        tooltip = "An addon cannot create a real ability, so this makes a macro called \"MiniQoL Fish\" and puts it on your cursor. Drop it on any action bar and it behaves like one: click to go fishing, click again to change back." })
    checkbox("announceGear", "Fishing outfit", "Say what changed in chat",
        "Prints a line each time you swap, so you know it took effect.")

    -- One row per slot. The row shows what the outfit uses there, and the
    -- menu offers the three things a slot can do.
    for _, slot in ipairs(Fishing.GEAR_SLOTS) do
        feature({ id = "fishing.slot." .. slot, group = "Outfit slots",
            label = Fishing.SLOT_NAMES[slot] or ("Slot " .. slot), kind = "select", available = ready,
            options = function()
                local list = {}
                local value = Fishing:GearSlotValue(slot)
                if value and value ~= EMPTY then
                    list[#list + 1] = { value, Fishing.LinkName(value) or "Saved item" }
                end
                local worn = Fishing:EquippedLink(slot)
                list[#list + 1] = { "wear", worn and ("Use " .. (Fishing.LinkName(worn) or "what I have on"))
                    or "Use what I have on" }
                list[#list + 1] = { EMPTY, "Take it off when fishing" }
                list[#list + 1] = { "ignore", "Leave this slot alone" }
                return list
            end,
            get = function()
                local value = Fishing:GearSlotValue(slot)
                if value == nil then return "ignore" end
                return value
            end,
            set = function(value)
                if value == "wear" then Fishing:GearSlotFromWorn(slot)
                elseif value == "ignore" then Fishing:ClearGearSlot(slot)
                else Fishing:SetGearSlot(slot, value) end
            end,
            tooltip = "What the fishing outfit does with this slot: wear a particular item, deliberately leave it bare, or leave whatever you already have on untouched." })
    end

    ---------------------------------------------------------------------
    -- The window and the record
    ---------------------------------------------------------------------
    checkbox("bar", "While fishing", "Show the fishing window",
        "A small window with your lures, fishing food, skill breakdown and what you are catching. It appears on its own when you hold a pole.")
    checkbox("statsIncludeMissed", "While fishing", "Count empty casts in the totals",
        "Shows casts that gave nothing alongside the fish, so the percentages are of every cast rather than every catch.")
    feature({ id = "fishing.record", group = "While fishing", kind = "info", available = ready,
        label = "Nothing caught yet.",
        get = function()
            local total = Fishing:TotalCaught()
            if total == 0 then return "Nothing caught yet." end
            local caught, missed, average = Fishing:CastSummary()
            local zone = Fishing:FavouriteZone()
            local parts = { ("%d caught over %d sessions"):format(total, Fishing.db.sessions) }
            if zone then parts[#parts + 1] = ("favourite spot %s (%.0f%%)"):format(zone.name, zone.percent) end
            if average then parts[#parts + 1] = ("%.0fs a catch"):format(average) end
            parts[#parts + 1] = ("%d empty casts"):format(missed)
            return table.concat(parts, "  \194\183  ")
        end })
    feature({ id = "fishing.resetSession", group = "While fishing", label = "This session's record",
        kind = "action", button = "Reset", available = ready,
        run = function() Fishing:ResetSession(); ns:Print("Started a new fishing session.") end,
        tooltip = "Clears what you have caught this sitting. All-time totals are kept." })
    feature({ id = "fishing.resetAll", group = "While fishing", label = "Everything ever caught",
        kind = "action", button = "Erase", available = ready,
        run = function() StaticPopup_Show("MINIQOL_FISHING_RESET") end,
        tooltip = "Forgets every fish, zone and lure recorded, for good. Settings and your outfit are kept." })
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
