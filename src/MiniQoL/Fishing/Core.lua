local _, ns = ...
-- Fishing: a louder splash, one-key casting, lure and food buttons, a skill
-- breakdown, a gear swap, and a record of everything you pull out of the water.
-- Everything lives under MiniQoLDB.fishing so there is one saved variable.
local Fishing = {}
ns.Fishing = Fishing

Fishing.SPELL_ID = 7620
Fishing.MAIN_HAND_SLOT = 16
Fishing.FIRST_SLOT, Fishing.LAST_SLOT = 1, 19

-- Lures, strongest first. Each one you are carrying gets a button.
Fishing.LURES = {
    6533,  -- Aquadynamic Fish Attractor
    34861, -- Sharpened Fish Hook
    46006, -- Glow Worm
    62673, -- Feathered Lure
    68049, -- Heat-Treated Spinning Lure
    7307,  -- Flesh Eating Worm
    6532,  -- Bright Baubles
    6811,  -- Aquadynamic Fish Lens
    6530,  -- Nightcrawlers
    6529,  -- Shiny Bauble
}

-- Food that raises fishing skill, best first.
Fishing.FOODS = { 4593 }

Fishing.BOOST_DELAY = 0.5      -- skip the sound of the cast itself
Fishing.LOOT_GRACE = 1         -- before a cast counts as a miss
Fishing.RECAST_WINDOW = 0.3    -- a restart this soon is a recast, not a miss
Fishing.DOUBLE_CLICK_TIME = 0.4
Fishing.RECENT_CATCHES = 8

local DEFAULTS = {
    sound = true,
    volume = 0.85,
    soundInBackground = true,
    -- "doubleClick", "hotkey" or "none"
    castMode = "doubleClick",
    castKey = "BUTTON4",
    autoLure = true,
    reelIn = true,
    reelInKey = "BUTTON2",
    bar = true,
    statsIncludeMissed = false,
    announceGear = true,
}

Fishing.defaults = DEFAULTS

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
local GetItemIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetSpellName = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
Fishing.GetItemInfo, Fishing.GetItemCount = GetItemInfo, GetItemCount
Fishing.GetItemIcon, Fishing.GetItemInfoInstant = GetItemIcon, GetItemInfoInstant

function Fishing:SpellName()
    if not self.spellName then self.spellName = GetSpellName(self.SPELL_ID) end
    return self.spellName
end

function Fishing:IsFishingSpell(spellID)
    return spellID ~= nil and GetSpellName(spellID) == self:SpellName()
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
function Fishing:Initialize()
    local db = ns.db
    if type(db.fishing) ~= "table" then db.fishing = {} end
    self.db = db.fishing
    local data = self.db
    if type(data.settings) ~= "table" then data.settings = {} end
    -- Totals that outlive a session.
    for _, key in ipairs({ "items", "zones", "areaItems", "lureUsed", "hours" }) do
        if type(data[key]) ~= "table" then data[key] = {} end
    end
    for _, key in ipairs({ "caughtCasts", "missedCasts", "catchSeconds" }) do
        if type(data[key]) ~= "number" then data[key] = 0 end
    end
    if type(data.sessions) ~= "number" then data.sessions = 0 end
    -- This session only.
    data.catches, data.casts, data.sessionStart = {}, {}, nil
    data.sessions = data.sessions + 1
    if type(data.gear) ~= "table" then data.gear = {} end
    if type(data.gear.set) ~= "table" then data.gear.set = {} end
    return self
end

function Fishing:Get(key)
    local value = self.db and self.db.settings[key]
    if value == nil then return DEFAULTS[key] end
    return value
end

function Fishing:Set(key, value)
    if not self.db then return end
    self.db.settings[key] = value
    self:Fire("SETTING_CHANGED", key, value)
end

---------------------------------------------------------------------------
-- A small event bus, so the bar and the panel redraw without polling.
---------------------------------------------------------------------------
local listeners = {}

function Fishing:On(event, callback)
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], callback)
end

function Fishing:Fire(event, ...)
    for _, callback in ipairs(listeners[event] or {}) do
        local ok, err = pcall(callback, ...)
        if not ok then ns.lastError = tostring(err) end
    end
end

---------------------------------------------------------------------------
-- Formatting shared by the bar and the panel
---------------------------------------------------------------------------
function Fishing.Duration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    if seconds < 3600 then return ("%dm %02ds"):format(seconds / 60, seconds % 60) end
    return ("%dh %02dm"):format(seconds / 3600, seconds % 3600 / 60)
end

function Fishing.Short(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    if seconds < 60 then return seconds .. "s" end
    if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
    return math.floor(seconds / 3600) .. "h"
end

function Fishing.Since(timestamp)
    return Fishing.Short(time() - (timestamp or 0)) .. " ago"
end

function Fishing.LinkName(link)
    return link and link:match("%[(.-)%]") or nil
end

-- Called once the saved variables and the panel exist.
function Fishing:Start()
    self:Initialize()
    self:SetupCatches()
    self:SetupSound()
    self:SetupEasyCast()
    self:SetupGear()
    self:RegisterPage()
    self:SetupBar()
end
