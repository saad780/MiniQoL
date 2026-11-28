local _, ns = ...
---------------------------------------------------------------------------
-- Diagnostics
---------------------------------------------------------------------------
-- Two things that make an in-game problem easier to pin down:
--
-- * Code that runs every frame (an OnUpdate) raises the same error sixty
--   times a second when it breaks, burying the first report and tripping the
--   game's "large number of errors" warning. ns.Guarded wraps such a handler
--   so each distinct error is reported once, then only counted.
-- * "Interface action failed" names no culprit. Every blocked or forbidden
--   action since login, by any addon, is kept here; /mqol blocked lists them
--   along with the repeated errors that were counted rather than reported.
local Diagnostics = {}
ns.Diagnostics = Diagnostics

local errors = {}   -- message -> { count, label }, in the order first seen
local errorOrder = {}
local blocked = {}  -- "addon|function|kind" -> { addon, func, kind, count, combat, last }
local blockedOrder = {}

local function Now()
    return GetTime and GetTime() or 0
end

-- The first line of an error: "file:line: what went wrong". Stack traces
-- differ from frame to frame, the place and the message don't.
local function Key(message)
    message = tostring(message)
    return message:match("^[^\n]*") or message
end

-- Reports an error the first time it is seen; after that, only counts it.
-- Returns whether it was reported.
function Diagnostics.Report(message, label)
    local key = Key(message)
    local entry = errors[key]
    if entry then
        entry.count = entry.count + 1
        return false
    end
    errors[key] = { count = 1, label = label }
    errorOrder[#errorOrder + 1] = key
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        handler(label and (label .. ": " .. tostring(message)) or tostring(message))
    end
    return true
end

-- A handler that reports each distinct error of `fn` once and keeps going,
-- for code that runs again and again. pcall rather than xpcall: no table or
-- closure is made per call, which matters at sixty calls a second.
function ns.Guarded(fn, label)
    if type(fn) ~= "function" then return fn end
    local report = Diagnostics.Report
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then report(err, label) end
    end
end

function Diagnostics.Errors()
    local list = {}
    for i, key in ipairs(errorOrder) do
        local entry = errors[key]
        list[i] = { message = key, count = entry.count, label = entry.label }
    end
    return list
end

---------------------------------------------------------------------------
-- Blocked actions
---------------------------------------------------------------------------
function Diagnostics.Blocked(kind, addon, func)
    addon = tostring(addon or "?")
    func = tostring(func or "?")
    local key = addon .. "|" .. func .. "|" .. kind
    local entry = blocked[key]
    if not entry then
        entry = { addon = addon, func = func, kind = kind, count = 0 }
        blocked[key] = entry
        blockedOrder[#blockedOrder + 1] = key
    end
    entry.count = entry.count + 1
    entry.last = Now()
    entry.combat = InCombatLockdown and InCombatLockdown() and true or entry.combat
end

function Diagnostics.BlockedList()
    local list = {}
    for i, key in ipairs(blockedOrder) do list[i] = blocked[key] end
    return list
end

local function Ago(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    if seconds < 60 then return seconds .. " s ago" end
    if seconds < 3600 then return math.floor(seconds / 60) .. " min ago" end
    return math.floor(seconds / 3600) .. " h ago"
end

-- /mqol blocked
function Diagnostics.Print()
    local now = Now()
    local list = Diagnostics.BlockedList()
    if #list == 0 then
        ns:Print("No addon has been blocked from an action since login.")
    else
        ns:Print("Blocked actions since login (the addon the game blamed, and what it tried):")
        for _, entry in ipairs(list) do
            -- (the game names the function with its brackets: "Button:SetPassThroughButtons()")
            print(("  %s  %s  %s%s, last %s%s"):format(entry.addon, entry.func,
                entry.kind == "forbidden" and "forbidden " or "", entry.count == 1 and "once" or (entry.count .. " times"),
                Ago(now - (entry.last or now)), entry.combat and ", in combat" or ""))
        end
    end
    local repeated = 0
    for _, entry in ipairs(Diagnostics.Errors()) do
        if entry.count > 1 then
            if repeated == 0 then ns:Print("Errors reported once and counted since:") end
            repeated = repeated + 1
            print(("  %s  (%d times)"):format(entry.message, entry.count))
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:SetScript("OnEvent", function(_, event, addon, func)
    Diagnostics.Blocked(event == "ADDON_ACTION_FORBIDDEN" and "forbidden" or "blocked", addon, func)
end)
