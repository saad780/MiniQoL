-- Regen ticks: a slim bar under the player frame. Grey while nothing comes
-- back, draining through the five-second rule, filling toward each tick; the
-- number is what the last tick gave. Health or power may be secret, and then
-- the beat says which changes are ticks.
local root = ...
local function noop() end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local methods = {}
local function NewFrame(kind, parent)
    local frame = { kind = kind, parent = parent, scripts = {}, points = {}, shown = true, alpha = 1 }
    return setmetatable(frame, { __index = function(_, key)
        if methods[key] then return methods[key] end
        if type(key) == "string" and key:find("^%u") then return noop end
    end })
end
function methods:SetScript(name, fn) self.scripts[name] = fn end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(value) self.shown = value and true or false end
function methods:IsShown() return self.shown end
function methods:SetPoint(...) self.points[#self.points + 1] = { ... } end
function methods:ClearAllPoints() self.points = {} end
function methods:SetHeight(height) self.height = height end
function methods:SetValue(value) self.value = value end
function methods:SetStatusBarColor(r, g, b) self.color = { r, g, b } end
function methods:GetStatusBarTexture()
    self.fill = self.fill or NewFrame("Texture", self)
    return self.fill
end
function methods:SetText(text) self.text = text end
function methods:SetTextColor(r, g, b) self.color = { r, g, b } end
function methods:SetAlpha(alpha) self.alpha = alpha end
function methods:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
function methods:RegisterUnitEvent(event, unit)
    assert(unit == "player", "only the player's own events")
    self.events = self.events or {}
    self.events[event] = true
end
function methods:CreateTexture() return NewFrame("Texture", self) end
function methods:CreateFontString() return NewFrame("FontString", self) end
function CreateFrame(kind, name, parent)
    local frame = NewFrame(kind, parent)
    if name then _G[name] = frame end
    return frame
end
UIParent = NewFrame("Frame")
PlayerFrame = NewFrame("Frame", UIParent)
PlayerFrame.manabar = NewFrame("StatusBar", PlayerFrame)

---------------------------------------------------------------------------
-- The game
---------------------------------------------------------------------------
local clock = 1000
function GetTime() return clock end
local timers = {}
C_Timer = { After = function(delay, fn) timers[#timers + 1] = { at = clock + delay, fn = fn } end }
local R -- the module, once started
local function frame()
    local update = R.box.scripts.OnUpdate
    if update then update(R.box, 0.016) end
end
-- Moves the clock on, running timers on the way and the bar's frame updates.
local function advance(seconds)
    local target = clock + seconds
    while true do
        local nextIndex
        for index, timer in ipairs(timers) do
            if timer.at <= target and (not nextIndex or timer.at < timers[nextIndex].at) then nextIndex = index end
        end
        if not nextIndex then break end
        local timer = table.remove(timers, nextIndex)
        clock = math.max(clock, timer.at)
        timer.fn()
    end
    clock = target
    frame()
end

function issecretvalue(value) return value == "SECRET" end
Enum = { PowerType = { Health = -2, Mana = 0, Rage = 1, Focus = 2, Energy = 3 } }
local TOKENS = { [0] = "MANA", [1] = "RAGE", [3] = "ENERGY" }

local me -- the logged-in character
local secretHealth, secretPower = false, false
function UnitHealth() return secretHealth and "SECRET" or me.health end
function UnitHealthMax() return secretHealth and "SECRET" or me.healthMax end
function UnitPower(_, powerType)
    assert(powerType == me.powerType, "asks for the power bar's own type")
    return secretPower and "SECRET" or me.power
end
function UnitPowerMax() return secretPower and "SECRET" or me.powerMax end
function UnitPowerType() return me.powerType, TOKENS[me.powerType] end
function UnitIsDeadOrGhost() return me.dead end
function InCombatLockdown() return me.combat end
function UnitAffectingCombat() return me.combat end
-- Out of combat the game gives the regen rate; in combat it is secret.
function GetPowerRegenForPowerType(powerType)
    if me.combat then return "SECRET", "SECRET" end
    if powerType == Enum.PowerType.Energy then return 10, 10 end
    if powerType == Enum.PowerType.Mana then return 14, 2 end
    return 0, 0
end
-- Forever's own health regen rate, per second; secret in combat too.
function GetHealthRegen()
    if me.combat then return "SECRET", "SECRET" end
    return me.healthRegen or 0, 0
end

local SPELLS = {
    [1752] = { { type = 3, cost = 40 } },          -- Sinister Strike: energy
    [686] = { { type = 0, cost = 25 } },           -- Shadow Bolt: mana
    [1454] = { { type = -2, cost = 30 } },         -- Life Tap: health
    [5019] = {},                                   -- Shoot (a wand): nothing
    [5308] = { { type = 1, cost = 15 } },          -- Execute: rage
}
C_Spell = { GetSpellPowerCost = function(id) return SPELLS[id] end }

---------------------------------------------------------------------------
-- Mini QoL
---------------------------------------------------------------------------
MiniQoLDB = {}
local features, printed = {}, {}
local function Session(character)
    me = character
    secretHealth, secretPower = false, false
    timers, features, printed = {}, {}, {}
    local ns = { db = MiniQoLDB }
    function ns:RegisterFeature(spec) features[spec.id] = spec end
    function ns:Print(message) printed[#printed + 1] = message end
    assert(loadfile(root .. "/Regen.lua"))("MiniQoL", ns)
    R = ns.Regen
    R:Start()
    return R
end
local function fire(event, ...)
    assert(R.events.events[event], "listens for " .. event)
    R.events.scripts.OnEvent(R.events, event, ...)
end
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function near(actual, expected, label)
    assert(type(actual) == "number" and math.abs(actual - expected) < 0.03,
        label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function power(value) me.power = value; fire("UNIT_POWER_FREQUENT", "player", TOKENS[me.powerType]) end
local function health(value) me.health = value; fire("UNIT_HEALTH", "player") end
local function cast(id) fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-GUID", id) end
local function grey(row) return row.color[1] == row.color[2] and row.color[2] == row.color[3] end
local function shown(row) return row.text.shown and row.text.text or nil end

---------------------------------------------------------------------------
-- 1. A rogue at full energy: two grey rows under the player frame
---------------------------------------------------------------------------
local rogue = { health = 893, healthMax = 893, healthRegen = 4.5, power = 105, powerMax = 105, powerType = 3, combat = false }
Session(rogue)
local box = R.box
assert(box.shown, "the bar shows")
equal(box.parent, PlayerFrame, "it belongs to the player frame, so it scales and hides with it")
local top = box.points[1]
equal(top[2], PlayerFrame.manabar, "it hangs from the player frame's power bar")
equal(top[5], -4, "four pixels down to start with")
equal(box.height, 2 * 2 + 2 * 9 + 1, "two rows high")
local hp, pw = R.health.row, R.power.row
assert(hp.shown and pw.shown, "a row each for health and energy")
equal(R:State(R.health, clock), "idle", "health is full")
equal(R:State(R.power, clock), "idle", "energy is full")
assert(grey(hp) and grey(pw), "both rows are grey")
equal(pw.value, 1, "a grey row is filled across")
equal(shown(pw), "+20", "energy says what a tick gives before one lands, from the game's regen rate")
assert(grey(pw.text), "in grey while nothing comes back")
equal(shown(hp), "+9", "and health, from the game's health regen rate")
assert(grey(hp.text), "in grey too")
equal(box.scripts.OnUpdate, nil, "nothing moves, so nothing runs each frame")

---------------------------------------------------------------------------
-- 2. Spending energy, then ticks on the beat
---------------------------------------------------------------------------
local start = clock
cast(1752)
power(65)
equal(R:State(R.power, clock), "regen", "spent energy comes back")
assert(box.scripts.OnUpdate, "the row moves each frame")
assert(not grey(pw), "in energy's colour")
advance(0.9)
power(85)
advance(0.2)
near(R.power.tickAt, start + 0.9, "a rise away from the cast is the first tick, and sets the beat")
equal(shown(pw), "+20", "the number is what it gave")
equal(pw.text.color[1], 1, "in yellow")
near(pw.flash.alpha, 0.35, "the row flashes as the tick is counted")
advance(0.2)
near(pw.flash.alpha, 0.35 * (1 - 0.2 / 0.35), "and fades")
advance(0.6)
near(pw.value, 0.5, "half way to the next tick a second after the last")
advance(0.95) -- start + 2.85
power(105 - 5)
advance(0.2)
near(R.power.tickAt, start + 2.85, "the next tick lands on the beat")
advance(0.5) -- start + 3.55: Thistle Tea
power(105)
advance(0.2)
near(R.power.tickAt, start + 2.85, "a rise off the beat while ticks are landing is something else")
equal(R:State(R.power, clock), "idle", "energy is full again: grey at once")
assert(grey(pw), "the row is grey")
equal(shown(pw), "+15", "and still says what the last tick gave")
advance(1)
equal(box.scripts.OnUpdate, nil, "and it stops running each frame")

-- A tick that fills energy shows what it gave, but isn't kept as the rate.
near(clock, start + 4.75, "the clock")
cast(1752)
power(65)
advance(2.1) -- start + 6.85: on the beat, two ticks after start + 2.85
power(85)
advance(0.2)
equal(shown(pw), "+20", "a tick")
equal(R.measured["ENERGY:free"], 20, "kept as what a tick gives")
me.powerMax = 100
fire("UNIT_MAXPOWER", "player")
advance(1.8)
power(100)
advance(0.2)
equal(shown(pw), "+15", "the tick that filled energy says what it gave")
equal(R.measured["ENERGY:free"], 20, "but a tick cut short by full isn't kept")
cast(1752)
power(65)
advance(1.8)
power(70)
advance(0.2)
equal(shown(pw), "+5", "a small tick shows what it gave")
equal(R.measured["ENERGY:free"], 5, "and is kept while short of full")

---------------------------------------------------------------------------
-- 3. Health comes back out of combat only
---------------------------------------------------------------------------
me.combat = true
fire("PLAYER_REGEN_DISABLED")
health(700)
equal(R:State(R.health, clock), "idle", "no health comes back in combat")
assert(grey(hp), "so the row stays grey")
advance(2)
health(720)
advance(0.2)
equal(R.health.tickAt, nil, "a heal in combat is no tick")
me.combat = false
fire("PLAYER_REGEN_ENABLED")
equal(R:State(R.health, clock), "regen", "out of combat, short of full, it comes back")
local beat = R.clock
local wait = 2 - ((clock - beat) % 2)
advance(wait)
health(732)
advance(0.2)
near(R.health.tickAt, clock - 0.2, "on the beat the energy ticks keep")
equal(shown(hp), "+12", "health says what its tick gave")
equal(hp.text.color[2], 1, "in green")

---------------------------------------------------------------------------
-- 4. Secret health: the beat says which changes are ticks
---------------------------------------------------------------------------
secretHealth = true
advance(1.8)
fire("UNIT_HEALTH", "player")
advance(0.2)
near(R.health.tickAt, clock - 0.2, "a change on the beat is a tick, though the number is secret")
equal(shown(hp), "+12", "and gives what the last measured tick did")
-- Forever never lets health be read, so nothing is ever measured there: the
-- game's rate says what a tick gives.
R.measured["HEALTH:free"] = nil
advance(1.8)
fire("UNIT_HEALTH", "player")
advance(0.2)
near(R.health.tickAt, clock - 0.2, "the next tick on the beat")
equal(shown(hp), "+9", "gives what the game's health regen rate does over a tick")
equal(hp.text.color[2], 1, "in green")
advance(0.8)
fire("UNIT_HEALTH", "player") -- food, off the beat
advance(0.2)
near(R.health.tickAt, clock - 1.2, "a change off the beat isn't")
equal(R:State(R.health, clock), "regen", "ticks are landing, so health is coming back")
advance(3)
equal(R:State(R.health, clock), "idle", "no tick for a beat and a bit: it is full")
me.combat = true
fire("PLAYER_REGEN_DISABLED")
fire("UNIT_HEALTH", "player")
advance(0.2)
equal(R:State(R.health, clock), "idle", "secret health in combat is never a tick")
me.combat = false
fire("PLAYER_REGEN_ENABLED")
secretHealth = false
health(893)

-- Secret energy: the cost can arrive just before the cast does.
secretPower = true
me.power = 105
fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
cast(1752)
advance(0.2)
local spent = R.power.tickAt
assert(spent == nil or spent < clock - 0.3, "a change just before a cast is its cost, not a tick")
equal(R:State(R.power, clock), "regen", "spending says energy is coming back")
local at = R.clock + 2 * math.ceil((clock - R.clock) / 2)
advance(at - clock)
fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
advance(0.2)
near(R.power.tickAt, at, "the tick on the beat counts")
equal(shown(pw), "+5", "with the last measured amount")
secretPower = false

---------------------------------------------------------------------------
-- 5. Settings
---------------------------------------------------------------------------
for _, id in ipairs({ "regen.enabled", "regen.health", "regen.power", "regen.numbers", "regen.gap", "regen.reading" }) do
    assert(features[id], id .. " is on the panel")
    equal(features[id].page, "regen", id .. " is on the Regen ticks page")
end
features["regen.health"].set(false)
assert(not hp.shown and pw.shown, "the health row can go")
equal(box.height, 2 * 2 + 9, "one row high")
equal(pw.points[1][5], -2, "the power row moves up")
features["regen.health"].set(true)
features["regen.gap"].set(10.4)
equal(box.points[1][5], -10, "the gap is whole pixels")
equal(features["regen.gap"].format(10), "10 px", "and says so")
features["regen.numbers"].set(false)
equal(shown(pw), nil, "the numbers can go")
features["regen.numbers"].set(true)
features["regen.enabled"].set(false)
assert(not box.shown, "the bar can go")
equal(box.scripts.OnUpdate, nil, "taking its frame updates with it")
equal(features["regen.health"].available(), false, "rows wait for the bar")
features["regen.enabled"].set(true)
assert(box.shown, "and come back")
assert(features["regen.reading"].get():find("energy %+"), "the page says what a tick gives")

---------------------------------------------------------------------------
-- 6. A warlock: the five-second rule
---------------------------------------------------------------------------
MiniQoLDB = {}
local warlock = { health = 600, healthMax = 600, power = 1000, powerMax = 1000, powerType = 0, combat = false }
Session(warlock)
hp, pw, box = R.health.row, R.power.row, R.box
equal(shown(pw), "+28", "mana says what a tick gives, from the game's rate")
cast(5019)
equal(R.castAt, nil, "a wand costs nothing, so it moves nothing")
equal(R:State(R.power, clock), "idle", "and starts no rule")
start = clock
cast(686)
power(900)
equal(R:State(R.power, clock), "wait", "a spell that costs mana starts the five-second rule")
near(pw.value, 1, "the row starts full")
near(pw.color[3], 0.85 * 0.72, "in a darker blue")
advance(2.5)
near(pw.value, 0.5, "and drains with the rule")
advance(1.5)
near(pw.value, 0.2, "a second left")
advance(1.01)
equal(R:State(R.power, clock), "regen", "the rule is over and regen is under way")
assert(pw.value < 0.1, "filling from empty toward the first tick")
advance(0.4)
power(928)
advance(0.2)
equal(shown(pw), "+28", "the first tick after the rule")
equal(pw.text.color[3], 1, "in blue")

-- Life Tap pays with health and gives mana at once; neither is a tick.
local lastHealth, lastMana = R.health.tickAt, R.power.tickAt
advance(1.6)
cast(1454)
health(570)
power(1000 - 3)
advance(0.2)
equal(R.power.tickAt, lastMana, "Life Tap's mana isn't a tick")
equal(R.health.tickAt, lastHealth, "nor its health")
equal(R:State(R.power, clock), "regen", "it costs no mana, so no rule")

-- Out of combat at full: grey.
me.power = 1000
me.powerMax = 1000
fire("UNIT_MAXPOWER", "player")
advance(3)
equal(R:State(R.power, clock), "idle", "full mana is grey")
cast(686)
me.power = 1000
equal(R:State(R.power, clock), "idle", "and stays grey under the rule while still full")
power(975)
equal(R:State(R.power, clock), "wait", "until the cost lands")

---------------------------------------------------------------------------
-- 7. A druid shifting form, a warrior's rage, and dying
---------------------------------------------------------------------------
me.powerType, me.power, me.powerMax = 3, 100, 100
fire("UNIT_DISPLAYPOWER", "player")
equal(R.power.token, "ENERGY", "the power row follows the form")
equal(R:State(R.power, clock), "idle", "full energy, whatever the mana rule says")
equal(shown(pw), "+20", "energy's tick")

local warrior = { health = 900, healthMax = 900, healthRegen = 6, power = 30, powerMax = 100, powerType = 1, combat = false }
MiniQoLDB = {}
Session(warrior)
hp, pw = R.health.row, R.power.row
equal(R:State(R.power, clock), "regen", "rage out of combat drains")
equal(shown(pw), nil, "with nothing to say until it does")
advance(1)
power(27)
advance(0.2)
equal(shown(pw), "-3", "rage counts what it loses")
equal(pw.text.color[1], 1, "in red")
advance(1.8)
power(29)
advance(0.2)
equal(shown(pw), "-3", "rage gained isn't a tick")
me.combat = true
fire("PLAYER_REGEN_DISABLED")
equal(R:State(R.power, clock), "idle", "rage holds in combat")
cast(5308)
power(14)
equal(R:State(R.power, clock), "idle", "spending it starts nothing")
me.combat = false
fire("PLAYER_REGEN_ENABLED")
me.dead = true
fire("PLAYER_DEAD")
equal(R:State(R.health, clock), "idle", "nothing comes back while dead")
equal(R:State(R.power, clock), "idle", "nothing drains either")
me.dead, me.health = false, 450
fire("PLAYER_UNGHOST")
equal(R:State(R.health, clock), "regen", "back to life, short of full")

R:Report()
assert(printed[1]:find("health readable"), "/mqol regen says what the game lets addons read: " .. printed[1])
assert(printed[1]:find("health readable %(the game's rate: 6%.0 a second%)"), "and the rate it gives: " .. printed[1])
assert(printed[1]:find("rage readable,"), "rage has no rate: " .. printed[1])

print("Regen ticks: rows, the rule, the beat and secret values behave")
