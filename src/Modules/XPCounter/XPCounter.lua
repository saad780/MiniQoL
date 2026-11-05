local addonName, addon = ...
addon = addon or {}
local frame = CreateFrame("Frame")
local prefix = "|cff55ccffXP Counter|r: "

local previousXP, previousXPMax, previousLevel
local reputation = {}
local factionIDs = {}
local markers = {}
local pendingXP = {}
local xpHistory = {}
local scanScheduled = false
local initialized = false
local paceNoticeShown = false

local PACE_WINDOW_SECONDS = 300
local MIN_PACE_SECONDS = 30

-- The eight original race capital reputations share the standing discount.
-- Faction IDs are stable; using IDs also works with localized faction names.
local capitalFactions = {
    [47] = true,   -- Ironforge
    [54] = true,   -- Gnomeregan Exiles
    [68] = true,   -- Undercity
    [69] = true,   -- Darnassus
    [72] = true,   -- Stormwind
    [76] = true,   -- Orgrimmar
    [81] = true,   -- Thunder Bluff
    [530] = true,  -- Darkspear Trolls
}

local function say(message, popupMessage)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. message)
    end
    if addon.ShowPopup then
        addon.ShowPopup(popupMessage or message)
    end
end

local function number(value)
    if BreakUpLargeNumbers then
        return BreakUpLargeNumbers(value)
    end
    return tostring(value)
end

local function standingName(reaction)
    return _G["FACTION_STANDING_LABEL" .. tostring(reaction)] or ("standing " .. tostring(reaction))
end

local function perkText(factionID, reaction)
    if capitalFactions[factionID] and reaction >= 5 and reaction <= 8 then
        local discount = (reaction - 4) * 5
        if reaction == 5 then
            return "Perk: 5% faction vendor discount is listed, but may not apply yet in the Forever beta."
        end
        if reaction == 8 then
            return "Perks: 20% discount with this faction's vendors; this race's mounts may now be purchasable if riding requirements are met."
        end
        return "Perk: " .. discount .. "% discount with this faction's vendors."
    end
    return "No verified automatic perk for this standing; check the faction's vendors for rewards."
end

local function rememberMarker(kind)
    markers[#markers + 1] = { kind = kind, time = GetTime() }
end

local function classifyXP(at)
    local chosen, chosenDistance, chosenPriority
    for _, marker in ipairs(markers) do
        if not marker.used then
            local distance = math.abs(marker.time - at)
            if distance <= 0.6 then
                local priority = marker.kind == "kill" and 1 or 2
                if not chosen or priority > chosenPriority or (priority == chosenPriority and distance < chosenDistance) then
                    chosen, chosenDistance, chosenPriority = marker, distance, priority
                end
            end
        end
    end
    if not chosen then return "other" end
    chosen.used = true
    -- A quest or exploration can also generate an XP combat chat line.
    if chosen.kind ~= "kill" then
        for _, marker in ipairs(markers) do
            if marker.kind == "kill" and math.abs(marker.time - chosen.time) <= 0.3 then
                marker.used = true
            end
        end
    end
    return chosen.kind
end

local function recordPace(amount, at)
    xpHistory[#xpHistory + 1] = { amount = amount, time = at }
    while xpHistory[1] and at - xpHistory[1].time > PACE_WINDOW_SECONDS do
        table.remove(xpHistory, 1)
    end
    local elapsed = at - xpHistory[1].time
    if elapsed < MIN_PACE_SECONDS then return nil end

    local totalXP = 0
    for _, entry in ipairs(xpHistory) do
        totalXP = totalXP + entry.amount
    end
    return totalXP * 60 / elapsed
end

local function formatDuration(seconds)
    local wholeSeconds = math.ceil(seconds)
    if wholeSeconds < 60 then return wholeSeconds .. "s" end
    local minutes = math.floor(wholeSeconds / 60)
    local remainder = wholeSeconds % 60
    if minutes < 60 then return minutes .. "m " .. remainder .. "s" end
    local hours = math.floor(minutes / 60)
    return hours .. "h " .. (minutes % 60) .. "m"
end

local function flushXP()
    local now = GetTime()
    for _, gain in ipairs(pendingXP) do
        local source = classifyXP(gain.time)
        local label = source == "kill" and "Kill" or (source == "quest" and "Quest" or (source == "exploration" and "Discovery" or "Other"))
        local message = label .. ": +" .. number(gain.amount) .. " XP (level " .. gain.level .. ")"
        local popupMessage = number(gain.amount) .. " XP"
        if source == "kill" then
            if gain.remaining and gain.amount > 0 then
                local kills = math.ceil(gain.remaining / gain.amount)
                message = message .. " - about " .. number(kills) .. " more kills at this XP rate"
                popupMessage = popupMessage .. " - " .. number(kills) .. " more"
                if gain.xpPerMinute then
                    local duration = formatDuration(gain.remaining * 60 / gain.xpPerMinute)
                    message = message .. "; ~" .. duration .. " at " .. number(math.floor(gain.xpPerMinute + 0.5)) .. " XP/min"
                    popupMessage = popupMessage .. " (~" .. duration .. ")"
                elseif not paceNoticeShown then
                    message = message .. "; timing starts after 30 seconds of XP gains"
                    paceNoticeShown = true
                end
            end
        end
        say(message, popupMessage)
    end
    wipe(pendingXP)
    for index = #markers, 1, -1 do
        if markers[index].used or now - markers[index].time > 2 then
            table.remove(markers, index)
        end
    end
end

local xpFlushScheduled = false
local function scheduleXPFlush()
    if xpFlushScheduled then return end
    xpFlushScheduled = true
    C_Timer.After(0.2, function()
        xpFlushScheduled = false
        flushXP()
    end)
end

local function captureXP()
    local currentXP, maximumXP, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    if type(currentXP) ~= "number" or type(maximumXP) ~= "number" or type(level) ~= "number" then return end
    if previousXP == nil then
        previousXP, previousXPMax, previousLevel = currentXP, maximumXP, level
        return
    end

    local gain
    if level == previousLevel then
        gain = currentXP - previousXP
        if gain < 0 then
            -- XP can wrap before PLAYER_LEVEL_UP updates UnitLevel.
            return
        end
    elseif level == previousLevel + 1 and previousXPMax and previousXPMax > 0 then
        gain = (previousXPMax - previousXP) + currentXP
    end
    previousXP, previousXPMax, previousLevel = currentXP, maximumXP, level
    if gain and gain > 0 then
        local remaining = maximumXP > 0 and math.max(0, maximumXP - currentXP) or nil
        local at = GetTime()
        local xpPerMinute = recordPace(gain, at)
        pendingXP[#pendingXP + 1] = { amount = gain, time = at, level = level, remaining = remaining, xpPerMinute = xpPerMinute }
        scheduleXPFlush()
    end
end

local function readFaction(factionID)
    local data = C_Reputation.GetFactionDataByID(factionID)
    if data and (not data.isHeader or data.isHeaderWithRep) and type(data.currentStanding) == "number" then
        return data
    end
end

local function scanReputation()
    local count = C_Reputation.GetNumFactions()
    for index = 1, count do
        local data = C_Reputation.GetFactionDataByIndex(index)
        if data and data.factionID and (not data.isHeader or data.isHeaderWithRep) then
            factionIDs[data.factionID] = true
        end
    end

    for factionID in pairs(factionIDs) do
        local data = readFaction(factionID)
        if data then
            local old = reputation[factionID]
            local current = data.currentStanding
            local reaction = data.reaction
            if old then
                local difference = current - old.standing
                if difference > 0 then
                    say("+" .. number(difference) .. " reputation with " .. data.name .. " (level " .. UnitLevel("player") .. ")",
                        "+" .. number(difference) .. " " .. data.name .. " rep")
                elseif difference < 0 then
                    say(number(difference) .. " reputation with " .. data.name .. " (level " .. UnitLevel("player") .. ")",
                        number(difference) .. " " .. data.name .. " rep")
                end
                if reaction > old.reaction then
                    say(data.name .. " reached " .. standingName(reaction) .. "! " .. perkText(factionID, reaction),
                        data.name .. ": " .. standingName(reaction))
                end
            end
            reputation[factionID] = { standing = current, reaction = reaction }
        end
    end
end

local function scheduleReputationScan()
    if scanScheduled then return end
    scanScheduled = true
    C_Timer.After(0.1, function()
        scanScheduled = false
        scanReputation()
    end)
end

-- Capture factions inside collapsed headers without changing the player's UI.
-- Forever's faction IDs currently fit below 3200. Spread the one-time scan
-- over frames so loading the character stays responsive.
local function discoverFactionIDs(first)
    local last = math.min(first + 99, 3200)
    for factionID = first, last do
        local data = readFaction(factionID)
        if data then
            factionIDs[factionID] = true
            if not reputation[factionID] then
                reputation[factionID] = { standing = data.currentStanding, reaction = data.reaction }
            end
        end
    end
    if last < 3200 then
        C_Timer.After(0, function() discoverFactionIDs(last + 1) end)
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        if not initialized then
            initialized = true
            wipe(xpHistory)
            paceNoticeShown = false
            previousXP, previousXPMax, previousLevel = nil, nil, nil
            captureXP()
            scanReputation()
            discoverFactionIDs(1)
        else
            captureXP()
            scheduleReputationScan()
        end
    elseif event == "PLAYER_XP_UPDATE" then
        local unit = ...
        if unit == "player" then captureXP() end
    elseif event == "PLAYER_LEVEL_UP" then
        C_Timer.After(0, captureXP)
    elseif event == "QUEST_TURNED_IN" then
        rememberMarker("quest")
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        rememberMarker("kill")
    elseif event == "UI_INFO_MESSAGE" then
        local messageType = ...
        -- Resolve the message name because numeric IDs can shift between builds.
        if GetGameMessageInfo(messageType) == "ERR_ZONE_EXPLORED_XP" then
            rememberMarker("exploration")
        end
    elseif event == "UPDATE_FACTION" or event == "CHAT_MSG_COMBAT_FACTION_CHANGE" or event == "FACTION_STANDING_CHANGED" then
        if event == "FACTION_STANDING_CHANGED" then
            local factionID = ...
            if type(factionID) == "number" then factionIDs[factionID] = true end
        end
        scheduleReputationScan()
    end
end)

for _, event in ipairs({
    "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP",
    "QUEST_TURNED_IN", "CHAT_MSG_COMBAT_XP_GAIN", "UI_INFO_MESSAGE",
    "UPDATE_FACTION", "CHAT_MSG_COMBAT_FACTION_CHANGE", "FACTION_STANDING_CHANGED",
}) do
    frame:RegisterEvent(event)
end

SLASH_XPCOUNTER1 = "/xpcounter"
SLASH_XPCOUNTER2 = "/xpc"
SlashCmdList.XPCOUNTER = function()
    if addon.OpenSettings then
        addon.OpenSettings()
    else
        say("Tracking XP and reputation. Kill estimates use the XP from your most recent kill.")
    end
end
