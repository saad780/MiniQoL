local _, ns = ...
local Guarded = ns.Guarded or function(fn) return fn end -- each error once, not every frame (Diagnostics.lua)
-- Regen ticks: a slim bar under the player frame that says when health and
-- power come back, and by how much.
--
-- Health, mana and energy come back in ticks, one every two seconds. Mana
-- waits five seconds after a spell that costs mana before it starts again
-- (the five-second rule), and health only comes back out of combat. Rage goes
-- the other way: out of combat it drains a little every tick. One row for
-- health and one for the power bar, each in one of three states:
--
--   grey       nothing is coming back: full, in combat, or dead;
--   draining   the five-second rule is running, and regen starts as it empties;
--   filling    regen is under way: it fills toward the next tick, flashes as
--              the tick lands, and starts again.
--
-- The number is what the last tick gave. The rows wear the player frame's own
-- bar art by default, and the settings page can change their look, size and
-- place.
--
-- This game can hand addons a secret value for the player's health or power,
-- and Lua can do no sums with one. The change itself still says when a tick
-- lands: ticks fall on a two-second beat, so a change on the beat is a tick
-- and one off it is something else (a potion, a heal, food). The number is
-- then the last tick measured, or worked out from the regen rate the game
-- gives, which it shows out of combat. Forever never lets health be read, so
-- the health number always comes from its rate.
local Regen = {}
ns.Regen = Regen

local TICK = 2             -- seconds between ticks
local RULE = 5             -- the five-second rule
local EARLY, LATE = 0.3, 0.45 -- how far either side of the beat a change still counts as a tick
local STALE = 10           -- a beat older than this isn't trusted to say where the next one falls
local CAST_GRACE = 0.2     -- a change this close to a cast that costs something is that cast
local FLASH = 0.35         -- how long a tick lights its row

-- The bars are drawn with the game's own art: the fill of the player frame's
-- health and power bars, inside the frame and backing of its cast bar, with
-- the numbers in the unit frames' own font. Where a client lacks any of it,
-- the classic flat texture and a plain line stand in.
local UNIT_BAR = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-"
local CAST_BACK, CAST_FRAME, CAST_PIP = "ui-castingbar-background", "ui-castingbar-frame", "ui-castingbar-pip"
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local SPARK_TEXTURE = "Interface\\CastingBar\\UI-CastingBar-Spark"

local DEFAULTS = {
    enabled = true, health = true, power = true, numbers = true,
    texture = "unitframe", border = "castbar",
    textPos = "CENTER", textColor = "white", textSize = 10,
    matchWidth = true, width = 124, height = 10, spacing = 1, gap = 4, offset = 0,
}
-- What "Reset" puts back: everything about the look, size and place.
local LOOK_KEYS = { "texture", "border", "textPos", "textColor", "textSize",
    "matchWidth", "width", "height", "spacing", "gap", "offset" }
-- How far each border reaches outside its row.
local OUTSET = { castbar = 2, thin = 1, none = 0 }

-- Each bar's art on the player frame, and the classic colour the flat texture
-- takes instead. The text colour is a brighter shade, for numbers drawn in
-- the bar's colour rather than the unit frames' white.
local LOOKS = {
    HEALTH = { atlas = UNIT_BAR .. "Health", fill = { 0.00, 1.00, 0.00 }, text = { 0.38, 1.00, 0.38 } },
    MANA = { atlas = UNIT_BAR .. "Mana", fill = { 0.00, 0.00, 1.00 }, text = { 0.45, 0.70, 1.00 } },
    ENERGY = { atlas = UNIT_BAR .. "Energy", fill = { 1.00, 1.00, 0.00 }, text = { 1.00, 0.90, 0.25 } },
    RAGE = { atlas = UNIT_BAR .. "Rage", fill = { 1.00, 0.00, 0.00 }, text = { 1.00, 0.36, 0.30 } },
    FOCUS = { atlas = UNIT_BAR .. "Focus", fill = { 1.00, 0.50, 0.25 }, text = { 1.00, 0.62, 0.30 } },
}
local WHITE = { 1, 1, 1 }
local IDLE_FILL, IDLE_TEXT = { 0.28, 0.28, 0.28 }, { 0.62, 0.62, 0.62 }
local IDLE_SHADE = 0.55    -- the game's art, greyed out, also sits this much darker
local WAIT_SHADE = 0.72    -- the draining fill sits a little darker than the filling one
-- Per second, for when the game won't say.
local DEFAULT_RATE = { ENERGY = 10 }

local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
local GetSpellPowerCost = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost

local function Readable(value)
    return value ~= nil and not (issecretvalue and issecretvalue(value))
        and not (canaccessvalue and not canaccessvalue(value))
end

local function Number(value)
    if Readable(value) and type(value) == "number" then return value end
end

local function Flag(fn, ...)
    if not fn then return false end
    local ok, value = pcall(fn, ...)
    return ok and Readable(value) and value and true or false
end

-- Whether this client has a piece of the game's art. Asked once per name.
local atlases = {}
local function HasAtlas(name)
    if not name then return false end
    if atlases[name] == nil then
        local ok, info = false, nil
        if C_Texture and C_Texture.GetAtlasInfo then ok, info = pcall(C_Texture.GetAtlasInfo, name) end
        atlases[name] = ok and info ~= nil
    end
    return atlases[name]
end

-- A power bar this file doesn't know takes after the game's own entry for it.
local function PowerLook(token)
    if token and LOOKS[token] then return LOOKS[token] end
    local info = token and PowerBarColor and PowerBarColor[token]
    if type(info) == "table" and type(info.r) == "number" then
        local fill = { info.r, info.g or 0, info.b or 0 }
        return { atlas = info.atlasElementName and (UNIT_BAR .. info.atlasElementName) or info.atlas,
            fill = fill, text = fill }
    end
    return LOOKS.MANA
end

---------------------------------------------------------------------------
-- Saved settings
---------------------------------------------------------------------------
local function Track(kind)
    return { kind = kind, look = LOOKS.HEALTH }
end

function Regen:Initialize()
    if type(ns.db.regen) ~= "table" then ns.db.regen = {} end
    self.db = ns.db.regen
    self.health, self.power = Track("health"), Track("power")
    self.tracks = { self.health, self.power }
    self.measured, self.rates = {}, {}
    return self
end

function Regen:Get(key)
    local value = self.db and self.db[key]
    if value == nil then return DEFAULTS[key] end
    return value
end

function Regen:Set(key, value)
    if not self.db then return end
    self.db[key] = value
    self:Layout()
end

---------------------------------------------------------------------------
-- What the game says
---------------------------------------------------------------------------
-- Whether a spell costs this power type (health is a power type too: Life Tap
-- pays with it).
local function Costs(spellID, powerType)
    if powerType == nil or not GetSpellPowerCost or not Readable(spellID) or type(spellID) ~= "number" then
        return false
    end
    local ok, costs = pcall(GetSpellPowerCost, spellID)
    if not ok or not Readable(costs) or type(costs) ~= "table" then return false end
    for _, cost in ipairs(costs) do
        if Readable(cost) and Readable(cost.type) and (powerType == "any" or cost.type == powerType) then
            -- A cost that needs an aura you don't have isn't paid.
            local unpaid = Readable(cost.requiredAuraID) and cost.requiredAuraID ~= 0
                and Readable(cost.hasRequiredAura) and cost.hasRequiredAura == false
            local amount, percent = cost.cost, cost.costPercent
            if not unpaid and (not Readable(amount) or (Number(amount) or 0) > 0 or (Number(percent) or 0) > 0) then
                return true
            end
        end
    end
    return false
end
Regen.Costs = Costs

-- Reads the power bar's type. True when it changed (a druid shifting form).
function Regen:ReadPowerType()
    local power = self.power
    local ok, powerType, token = pcall(UnitPowerType, "player")
    if not ok or not Readable(powerType) then powerType, token = nil, nil end
    if not Readable(token) then token = nil end
    if powerType == power.powerType and token == power.token then return false end
    power.powerType, power.token = powerType, token
    power.look = PowerLook(token)
    power.value, power.max, power.full = nil, nil, nil
    power.tickAt, power.amount, power.expectUntil, power.flashAt = nil, nil, nil, nil
    power.guessAt = nil
    return true
end

function Regen:Values(track)
    if track.kind == "health" then
        return Number(UnitHealth("player")), Number(UnitHealthMax("player"))
    end
    if track.powerType == nil then return nil, nil end
    return Number(UnitPower("player", track.powerType)), Number(UnitPowerMax("player", track.powerType))
end

-- Whether there is nothing left to come back (for rage, nothing left to
-- lose). Nil when the game keeps the numbers secret.
local function Full(track, value, maximum)
    if not value then return nil end
    if track.token == "RAGE" then return value <= 0 end
    if not maximum or maximum <= 0 then return nil end
    return value >= maximum
end

-- Reads the numbers again without counting the change as a tick.
function Regen:Sync(track)
    local value, maximum = self:Values(track)
    track.value, track.max, track.full = value, maximum, Full(track, value, maximum)
end

---------------------------------------------------------------------------
-- The beat
---------------------------------------------------------------------------
-- The mana rule's "rule" and "free" regen differ; everything else is "free".
function Regen:Mode(track, now)
    if track.token == "MANA" and self.ruleEnds and now < self.ruleEnds then return "rule" end
    return "free"
end

local function Key(track, mode)
    return (track.kind == "health" and "HEALTH" or track.token or "POWER") .. ":" .. mode
end

-- When a tick last landed that the next one keeps time with: this row's own,
-- or failing that any row's, since the game ticks them together.
function Regen:Beat(track, now)
    if track.tickAt and now - track.tickAt < STALE then return track.tickAt end
    if self.clock and now - self.clock < STALE then return self.clock end
end

local function OnBeat(beat, now)
    local offset = (now - beat) % TICK
    return offset <= LATE or offset >= TICK - EARLY
end

-- Whether ticks are still landing. One may go missing under a cast, so a cast
-- since the last one allows for a second.
function Regen:Ticking(track, now)
    if not track.tickAt then return false end
    local limit = TICK + LATE
    if self.castAt and self.castAt > track.tickAt then limit = limit + TICK end
    return now - track.tickAt < limit
end

-- Whether a change at `at` was a tick. `delta` is how much it moved, or nil
-- when the game keeps the numbers secret.
function Regen:IsTick(track, at, delta)
    if self.dead then return false end
    local drains = track.token == "RAGE"
    if (track.kind == "health" or drains) and self.inCombat then return false end
    -- One tick a beat.
    if track.tickAt and at - track.tickAt < TICK - EARLY then return false end
    if delta ~= nil then
        if delta == 0 or (delta < 0) ~= drains then return false end
    end
    -- A cast that costs something moves health or power at once.
    if self.castAt and math.abs(at - self.castAt) <= CAST_GRACE then return false end
    local beat = self:Beat(track, at)
    if beat and OnBeat(beat, at) then return true end
    -- Off the beat, or none known yet. That starts a new beat, unless this
    -- row has been ticking all along: then it was something else.
    return not self:Ticking(track, at)
end

function Regen:Tick(track, at, delta, full)
    track.tickAt, self.clock = at, at
    track.flashAt = GetTime()
    local mode = self:Mode(track, at)
    if delta ~= nil then
        local amount = math.abs(delta)
        track.amount = amount
        -- A tick cut short by reaching full says less than the rate.
        if not full then self.measured[Key(track, mode)] = amount end
    else
        track.amount = self:Estimate(track, mode)
    end
end

-- Per second, from the game while it says (out of combat), else the last it
-- said.
function Regen:Rate(track, mode)
    local key = Key(track, mode)
    local base, casting
    if track.kind == "health" then
        -- Forever keeps the player's health secret, so this is all there is to
        -- go on: its own GetHealthRegen (out of combat, then in), taken to be
        -- per second like GetManaRegen; an older client's spirit rate else.
        local ok, rate
        if GetHealthRegen then
            ok, rate = pcall(GetHealthRegen)
        elseif GetUnitHealthRegenRateFromSpirit then
            ok, rate = pcall(GetUnitHealthRegenRateFromSpirit, "player")
        end
        if ok then base = Number(rate) end
        casting = base
    elseif track.token ~= "RAGE" then
        local ok, b, c
        if GetPowerRegenForPowerType and track.powerType then
            ok, b, c = pcall(GetPowerRegenForPowerType, track.powerType)
        elseif GetPowerRegen then
            ok, b, c = pcall(GetPowerRegen)
        end
        if ok then base, casting = Number(b), Number(c) end
    end
    local rate = mode == "rule" and casting or base
    if rate and rate > 0 then self.rates[key] = rate end
    return self.rates[key] or DEFAULT_RATE[track.token or ""]
end

-- What a tick gives, when it can't be measured: the last one that was, or
-- the rate over one tick.
function Regen:Estimate(track, mode)
    local measured = self.measured[Key(track, mode)]
    if measured then return measured end
    local rate = self:Rate(track, mode)
    if rate and rate > 0 then return math.floor(rate * TICK + 0.5) end
end

-- Health or power moved.
function Regen:Changed(track)
    if track.kind == "power" and track.powerType == nil then return end
    local now = GetTime()
    local value, maximum = self:Values(track)
    local before = track.value
    track.value, track.max = value, maximum
    track.full = Full(track, value, maximum)
    local drains = track.token == "RAGE"
    local delta
    if value then
        -- The first readable number is only somewhere to measure from.
        if not before then return self:Refresh() end
        delta = value - before
        -- Regen only goes up (rage only down), so the rest is spending or damage.
        if delta == 0 or (delta < 0) ~= drains then return self:Refresh() end
    end
    -- Cheap refusals first: health changes a lot in combat.
    if self.dead or ((track.kind == "health" or drains) and self.inCombat) then
        return self:Refresh()
    end
    -- A cast's cost can arrive a moment before the cast does, so the change
    -- is judged once that moment has passed.
    local full = track.full
    C_Timer.After(CAST_GRACE, function()
        if self:IsTick(track, now, delta) then
            self:Tick(track, now, delta, full)
            self:Refresh()
        end
    end)
    self:Refresh()
end

function Regen:Cast(spellID)
    local now = GetTime()
    if not Costs(spellID, "any") then return end
    self.castAt = now
    local power = self.power
    -- Spending means there is something to come back.
    if power.token ~= "RAGE" and Costs(spellID, power.powerType) then
        power.expectUntil = now + TICK + LATE
    end
    if Costs(spellID, MANA) then
        self.ruleEnds = now + RULE
        if power.token == "MANA" then power.expectUntil = self.ruleEnds + TICK + LATE end
    end
    self:Refresh()
end

---------------------------------------------------------------------------
-- States
---------------------------------------------------------------------------
function Regen:State(track, now)
    if self.dead or track.full then return "idle" end
    if track.kind == "power" and self:Mode(track, now) == "rule" then return "wait" end
    if (track.kind == "health" or track.token == "RAGE") and self.inCombat then return "idle" end
    if self:Ticking(track, now) then return "regen" end
    if track.expectUntil and now < track.expectUntil then return "regen" end
    -- Known to be short of full: regen is under way, or about to be.
    if track.full == false then return "regen" end
    return "idle"
end

-- How far toward the next tick, 0 to 1.
function Regen:Progress(track, now)
    local beat = self:Beat(track, now) or track.since or now
    local elapsed = now - beat
    -- A tick running a little late holds the row full rather than starting
    -- it over before it lands.
    if beat == track.tickAt and elapsed >= TICK and elapsed < TICK + LATE then return 1 end
    return (elapsed % TICK) / TICK
end

-- The number a row shows: the last tick, or what one would give. That guess
-- asks the game, so it is asked once a second, not every frame.
function Regen:Amount(track, now)
    if track.amount then return track.amount end
    if not track.guessAt or now - track.guessAt >= 1 then
        track.guess, track.guessAt = self:Estimate(track, "free"), now
    end
    return track.guess
end

---------------------------------------------------------------------------
-- The bar
---------------------------------------------------------------------------
-- The unit frames' own number font (white, outlined), at the chosen size.
local function StyleNumber(text, size)
    local object = TextStatusBarText or GameFontHighlightSmall
    -- A font object first, so the text has a font even if the file below won't load.
    if object then text:SetFontObject(object) end
    local file, flags
    if object and object.GetFont then
        local ok, f, _, fl = pcall(object.GetFont, object)
        if ok then file, flags = f, fl end
    end
    text:SetFont(file or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size,
        (flags and flags ~= "") and flags or "OUTLINE")
end

-- Places a texture a few pixels outside a region all round.
local function Around(texture, region, by)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", region, "TOPLEFT", -by, by)
    texture:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", by, -by)
end

-- Layers as the game's cast bar has them: backing, fill, then its frame over
-- the fill's ends, with the flash, spark and number on top.
function Regen:Row(box)
    local row = CreateFrame("StatusBar", nil, box)
    row:SetStatusBarTexture(BAR_TEXTURE)
    row:SetMinMaxValues(0, 1)
    row:SetValue(1)
    row:EnableMouse(false)
    row.edge = row:CreateTexture(nil, "BACKGROUND", nil, -8)
    row.back = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.border = row:CreateTexture(nil, "ARTWORK", nil, 4)
    row.flash = row:CreateTexture(nil, "OVERLAY", nil, 1)
    row.flash:SetAllPoints(row)
    row.flash:SetColorTexture(1, 1, 1, 1)
    row.flash:SetBlendMode("ADD")
    row.flash:SetAlpha(0)
    row.spark = row:CreateTexture(nil, "OVERLAY", nil, 2)
    row.spark:Hide()
    row.text = row:CreateFontString(nil, "OVERLAY")
    row.text:SetDrawLayer("OVERLAY", 7)
    row:Hide()
    return row
end

function Regen:Build()
    if self.box then return end
    local box = CreateFrame("Frame", "MiniQoLRegenBar", PlayerFrame or UIParent)
    box:EnableMouse(false)
    box:Hide()
    self.box = box
    self.health.row = self:Row(box)
    self.power.row = self:Row(box)
end

-- The border in use: the cast bar's frame needs the game's art for it.
function Regen:Border()
    local border = self:Get("border")
    if not OUTSET[border] then border = DEFAULTS.border end
    if border == "castbar" and not (HasAtlas(CAST_BACK) and HasAtlas(CAST_FRAME)) then return "thin" end
    return border
end

-- Puts a row in the chosen look. Runs when the look or the power bar changes,
-- never per frame.
function Regen:Dress(track)
    local row, look, height = track.row, track.look, self:Get("height")
    local atlas = self:Get("texture") == "unitframe" and HasAtlas(look.atlas) and look.atlas or nil
    row:SetStatusBarTexture(atlas or BAR_TEXTURE)
    row.atlas = atlas
    row.fillColor = nil -- so the next paint colours the new fill
    local fill = row:GetStatusBarTexture()

    local spark = row.spark
    spark:ClearAllPoints()
    if atlas and HasAtlas(CAST_PIP) then
        -- The cast bar's pip is 8 by 20 on its 11-pixel bar.
        spark:SetAtlas(CAST_PIP)
        spark:SetBlendMode("BLEND")
        spark:SetSize(math.max(3, math.floor(height * 8 / 11 + 0.5)), math.floor(height * 20 / 11 + 0.5))
    else
        spark:SetTexture(SPARK_TEXTURE)
        spark:SetBlendMode("ADD")
        spark:SetSize(8, height + 6)
    end
    spark:SetPoint("CENTER", fill or row, "RIGHT", 0, 0)

    local border = self:Border()
    if border == "castbar" then
        row.back:SetAtlas(CAST_BACK)
        Around(row.back, row, 1)
        row.border:SetAtlas(CAST_FRAME)
        Around(row.border, row, 2)
        row.border:Show()
        row.edge:Hide()
    else
        row.back:SetColorTexture(0, 0, 0, 0.5)
        Around(row.back, row, 0)
        row.border:Hide()
        if border == "thin" then
            row.edge:SetColorTexture(0, 0, 0, 0.9)
            Around(row.edge, row, 1)
        end
        row.edge:SetShown(border == "thin")
    end

    local text, at = row.text, self:Get("textPos")
    if at ~= "LEFT" and at ~= "RIGHT" then at = "CENTER" end
    StyleNumber(text, self:Get("textSize"))
    text:ClearAllPoints()
    text:SetPoint(at, row, at, at == "LEFT" and 3 or at == "RIGHT" and -3 or 0, 0)
    text:SetJustifyH(at)
    text.ink = nil
end

-- The player frame's mana (or energy, or rage) bar, which the box hangs from.
local function PowerBar()
    local ok, bar = pcall(function()
        return (PlayerFrame_GetManaBar and PlayerFrame_GetManaBar())
            or (PlayerFrame and PlayerFrame.manabar) or PlayerFrameManaBar
    end)
    return ok and bar or nil
end

-- The box takes in the rows and their borders. `out` is how far a border
-- reaches outside its row, so the rows themselves line up with the player
-- frame's bars when the widths match.
function Regen:Anchor(out)
    local box, gap, offset = self.box, self:Get("gap"), self:Get("offset")
    box:ClearAllPoints()
    local bar = PowerBar()
    if bar and self:Get("matchWidth") then
        box:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", offset - out, -gap)
        box:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", offset + out, -gap)
    else
        -- Centred under the bars, at the width asked for.
        box:SetWidth(self:Get("width") + out * 2)
        box:SetPoint("TOP", bar or PlayerFrame or UIParent, "BOTTOM", offset, -gap)
    end
end

function Regen:Layout()
    if not self.box then return end
    local box, rows = self.box, {}
    if self:Get("health") then rows[#rows + 1] = self.health end
    if self:Get("power") and self.power.powerType ~= nil then rows[#rows + 1] = self.power end
    self.health.row:Hide()
    self.power.row:Hide()
    if not self:Get("enabled") or #rows == 0 then
        box:Hide()
        self:Animate(false)
        return
    end
    local height, out = self:Get("height"), OUTSET[self:Border()]
    -- The space between rows is the space between their borders.
    local between = self:Get("spacing") + out * 2
    self.barInk = self:Get("textColor") == "bar"
    for index, track in ipairs(rows) do
        self:Dress(track)
        local row, top = track.row, -(out + (index - 1) * (height + between))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", box, "TOPLEFT", out, top)
        row:SetPoint("TOPRIGHT", box, "TOPRIGHT", -out, top)
        row:SetHeight(height)
        row:Show()
    end
    box:SetHeight(out * 2 + #rows * height + (#rows - 1) * between)
    self:Anchor(out)
    box:Show()
    self:Refresh(true)
end

-- Puts a look back to the defaults.
function Regen:ResetLook()
    if not self.db then return end
    for _, key in ipairs(LOOK_KEYS) do self.db[key] = nil end
    self:Layout()
end

-- These set what changed only, since they run every frame while a row moves.
-- The game's art is tinted white to show as drawn, darker to shade it, and
-- greyed out (as the game greys a dead player's bars) when idle.
local function Fill(row, color, shade, grey)
    if row.fillColor == color and row.fillShade == shade and row.fillGrey == grey then return end
    row.fillColor, row.fillShade, row.fillGrey = color, shade, grey
    row:SetStatusBarColor(color[1] * shade, color[2] * shade, color[3] * shade)
    local fill = row:GetStatusBarTexture()
    if fill and fill.SetDesaturated then fill:SetDesaturated(grey) end
end

local function Ink(text, color)
    if text.ink == color then return end
    text.ink = color
    text:SetTextColor(color[1], color[2], color[3])
end

function Regen:Paint(track, state, now, force)
    local row, look = track.row, track.look
    local color = row.atlas and WHITE or look.fill
    local value
    if state == "wait" then
        value = math.max(0, math.min(1, (self.ruleEnds - now) / RULE))
        Fill(row, color, WAIT_SHADE, false)
    elseif state == "regen" then
        value = self:Progress(track, now)
        Fill(row, color, 1, false)
    else
        value = 1
        if row.atlas then Fill(row, WHITE, IDLE_SHADE, true) else Fill(row, IDLE_FILL, 1, false) end
    end
    row:SetValue(value)
    row.spark:SetShown(state ~= "idle" and value > 0.02 and value < 0.98)

    local lit = track.flashAt and now - track.flashAt < FLASH and (1 - (now - track.flashAt) / FLASH) or 0
    if lit > 0 or row.lit ~= 0 then
        row.flash:SetAlpha(lit * 0.35)
        row.lit = lit
    end

    local amount = self:Get("numbers") and self:Amount(track, now) or nil
    local sign = track.token == "RAGE" and "-" or "+"
    if force or amount ~= row.amount or sign ~= row.sign then
        row.amount, row.sign = amount, sign
        row.text:SetText(amount and ("%s%d"):format(sign, amount) or "")
        row.text:SetShown(amount ~= nil)
    end
    Ink(row.text, state == "idle" and IDLE_TEXT or self.barInk and look.text or WHITE)
end

function Regen:Refresh(force)
    if not self.box or not self.box:IsShown() then return end
    local now, busy = GetTime(), false
    for _, track in ipairs(self.tracks) do
        if track.row:IsShown() then
            local state = self:State(track, now)
            if state ~= track.state then track.state, track.since = state, now end
            self:Paint(track, state, now, force)
            busy = busy or state ~= "idle" or (track.flashAt ~= nil and now - track.flashAt < FLASH)
        end
    end
    self:Animate(busy)
end

-- Moves the rows every frame, only while one of them is moving.
function Regen:Animate(on)
    if not self.box or (on and true or false) == (self.animating or false) then return end
    self.animating = on and true or false
    self.box:SetScript("OnUpdate", on and Guarded(function() self:Refresh() end, "Regen ticks") or nil)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
function Regen:Reset()
    self.dead = Flag(UnitIsDeadOrGhost, "player")
    self.inCombat = Flag(InCombatLockdown) or Flag(UnitAffectingCombat, "player")
    self.ruleEnds, self.castAt, self.clock = nil, nil, nil
    self:ReadPowerType()
    for _, track in ipairs(self.tracks) do
        track.tickAt, track.expectUntil, track.flashAt, track.guessAt = nil, nil, nil, nil
        self:Sync(track)
    end
    self:Layout()
end

function Regen:OnEvent(event, ...)
    if event == "UNIT_HEALTH" then
        self:Changed(self.health)
    elseif event == "UNIT_POWER_FREQUENT" then
        local _, token = ...
        if Readable(token) and self.power.token and token ~= self.power.token then return end
        self:Changed(self.power)
    elseif event == "UNIT_MAXHEALTH" then
        self:Sync(self.health)
        self:Refresh()
    elseif event == "UNIT_MAXPOWER" then
        self:Sync(self.power)
        self:Refresh()
    elseif event == "UNIT_DISPLAYPOWER" then
        if self:ReadPowerType() then
            self:Sync(self.power)
            self:Layout()
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellID = ...
        self:Cast(spellID)
    elseif event == "PLAYER_REGEN_DISABLED" then
        self.inCombat = true
        self:Refresh()
    elseif event == "PLAYER_REGEN_ENABLED" then
        self.inCombat = false
        self:Refresh()
    else
        -- Entering the world, dying or coming back: start over.
        self:Reset()
    end
end

---------------------------------------------------------------------------
-- The settings page
---------------------------------------------------------------------------
function Regen:Reading()
    local now, parts = GetTime(), {}
    local function add(track, name)
        local amount = self:Amount(track, now)
        if amount then
            parts[#parts + 1] = ("%s %s%d"):format(name, track.token == "RAGE" and "-" or "+", amount)
        end
    end
    add(self.health, "health")
    add(self.power, self.power.token and self.power.token:lower() or "power")
    if #parts == 0 then return "No tick seen yet this session." end
    return "A tick gives " .. table.concat(parts, ", ") .. "."
end

-- What the game lets an addon read right now, and the regen rate it gives.
-- /mqol regen prints it.
function Regen:Report()
    local function says(track, name, value)
        local text = name .. (Readable(value) and " readable" or " secret")
        self:Rate(track, "free")
        local rate = self.rates[Key(track, "free")]
        if rate then text = text .. (" (the game's rate: %.1f a second)"):format(rate) end
        return text
    end
    local health = says(self.health, "health", UnitHealth("player"))
    local power = self.power.powerType
        and says(self.power, self.power.token and self.power.token:lower() or "power",
            UnitPower("player", self.power.powerType))
        or "no power bar"
    local beat = self.clock and ("%.1fs ago"):format(GetTime() - self.clock) or "not yet"
    ns:Print(("Regen: %s, %s, last tick %s. %s"):format(health, power, beat, self:Reading()))
end

function Regen:RegisterPage()
    local WAIT = "Turn on Show the regen bar first."
    local function ready() return self.db ~= nil end
    local function on() return ready() and self:Get("enabled") end
    local function feature(spec)
        spec.page, spec.group = "regen", spec.group or "Regen bar"
        if spec.available == nil then spec.available, spec.unavailable = on, WAIT end
        ns:RegisterFeature(spec)
    end
    local function check(key, label, tooltip, needsBar, group)
        feature({ id = "regen." .. key, kind = "check", label = label, tooltip = tooltip, group = group,
            available = needsBar and on or ready, unavailable = needsBar and WAIT or nil,
            get = function() return self:Get(key) end,
            set = function(value) self:Set(key, value) end })
    end
    local function choose(key, group, label, choices, tooltip)
        feature({ id = "regen." .. key, kind = "select", group = group, label = label, choices = choices,
            tooltip = tooltip,
            get = function() return self:Get(key) end,
            set = function(value) self:Set(key, value) end })
    end
    local function pixels(value) return ("%d px"):format(math.floor(value + 0.5)) end
    local function slide(key, group, label, low, high, tooltip, available, unavailable)
        feature({ id = "regen." .. key, kind = "slider", group = group, label = label,
            min = low, max = high, step = 1, format = pixels, tooltip = tooltip,
            available = available, unavailable = unavailable,
            get = function() return self:Get(key) end,
            set = function(value) self:Set(key, math.floor(value + 0.5)) end })
    end

    check("enabled", "Show the regen bar",
        "A slim bar under your player frame: one row for health, one for mana, energy or rage.\n\n"
        .. "Grey: nothing is coming back (full, in combat, or dead).\n"
        .. "Draining: the five-second rule after a spell that costs mana. Regen starts as it empties.\n"
        .. "Filling: regen is under way. It fills toward the next tick, flashes as the tick lands, and starts again.")
    check("health", "Health row",
        "Health comes back every two seconds out of combat. Its number is what the last tick gave.", true)
    check("power", "Mana, energy or rage row",
        "Mana waits out the five-second rule after each spell that costs mana; energy fills toward every tick; rage counts down what you lose each tick out of combat.", true)
    check("numbers", "Show what each tick gives",
        "The number on each row. When the game keeps your health or power secret from addons, it is the last tick measured, or what your regen rate gives over one tick.", true)
    feature({ id = "regen.reading", kind = "info", label = "No tick seen yet this session.",
        get = function() return self:Reading() end })

    local LOOK, SIZE = "Look", "Size and position"
    choose("texture", LOOK, "Bar texture", { { "unitframe", "Unit frame" }, { "flat", "Classic flat" } },
        "Unit frame: the same art as your player frame's health and power bars.\n"
        .. "Classic flat: the old plain texture in solid colours.")
    choose("border", LOOK, "Border", { { "castbar", "Cast bar" }, { "thin", "Thin line" }, { "none", "None" } },
        "Cast bar: each row framed like the game's own cast bar.\n"
        .. "Thin line: a dark one-pixel edge.\nNone: just a dark backing.")
    choose("textPos", LOOK, "Number position", { { "CENTER", "Center" }, { "RIGHT", "Right" }, { "LEFT", "Left" } },
        "Where on each row the number sits. The player frame centres its own.")
    choose("textColor", LOOK, "Number color", { { "white", "White" }, { "bar", "Bar color" } },
        "White, like the numbers on the player frame, or green for health, blue for mana, yellow for energy and red for rage.")
    feature({ id = "regen.reset", kind = "action", group = LOOK, label = "Default look and size", button = "Reset",
        tooltip = "Puts the texture, border, number, size and position back as they started.",
        run = function() self:ResetLook() end })
    slide("textSize", LOOK, "Number size", 6, 18, "The size of the number on each row.")

    check("matchWidth", "Match the player frame's width",
        "Lines the rows up with the player frame's health and power bars. Turn off to set your own width.",
        true, SIZE)
    slide("width", SIZE, "Width", 40, 400, "How wide each row is, centred under the player frame's bars.",
        function() return on() and not self:Get("matchWidth") end,
        "Turn off Match the player frame's width first.")
    slide("height", SIZE, "Row height", 4, 24, "How tall each row is. The player frame's power bar is 10.")
    slide("spacing", SIZE, "Space between rows", 0, 12, "The gap between the health row and the power row.")
    slide("gap", SIZE, "Gap below the player frame", 0, 60, "How far under the player frame's bars the regen bar sits.")
    slide("offset", SIZE, "Sideways nudge", -150, 150, "Moves the regen bar left (below zero) or right.")
end

-- Called once the saved variables and the panel exist.
function Regen:Start()
    self:Initialize()
    self:RegisterPage()
    self:Build()
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER",
        "UNIT_DISPLAYPOWER", "UNIT_SPELLCAST_SUCCEEDED" }) do
        events:RegisterUnitEvent(event, "player")
    end
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event, ...) self:OnEvent(event, ...) end)
    self.events = events
    self:Reset()
end
