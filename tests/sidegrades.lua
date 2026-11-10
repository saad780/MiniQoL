-- The look preview: the right-hand model has to end up wearing the looted item
-- and the left one what you wear now, loaded the way the game loads them.
local gearwise, shell = ...

local function noop() end

-- Anything not spelled out is a no-op, so the windows build as they would.
local methods = {}
local frame = {}
frame.__index = function(_, key)
    if methods[key] then return methods[key] end
    if type(key) == "string" and key:match("^%u") then return noop end
end
local frames = {}
function methods:SetScript(key, fn) self.handlers[key] = fn end
function methods:GetScript(key) return self.handlers[key] end
function methods:HookScript(key, fn)
    local before = self.handlers[key]
    self.handlers[key] = function(...) if before then before(...) end; fn(...) end
end
function methods:SetShown(value)
    value = value and true or false
    if value == self.shown then return end
    self.shown = value
    local script = self.handlers[value and "OnShow" or "OnHide"]
    if script then script(self) end
end
function methods:Show() self:SetShown(true) end
function methods:Hide() self:SetShown(false) end
function methods:IsShown() return self.shown end
function methods:IsVisible()
    local f = self
    while f do
        if not f.shown then return false end
        f = f.parent
    end
    return true
end
function methods:SetText(value) self.text = value end
function methods:GetText() return self.text end
function methods:GetFrameLevel() return 1 end
function methods:GetWidth() return 1920 end
function methods:GetCenter() return 1800, 900 end
function methods:IsMouseOver() return HOVERING == true end
function methods:CreateTexture() return setmetatable({ handlers = {}, shown = true, parent = self }, frame) end
function methods:CreateFontString() return setmetatable({ handlers = {}, shown = true, parent = self }, frame) end
local function RequiresBackdrop(self, method)
    assert(self.template and self.template:find("BackdropTemplate"), "needs BackdropTemplate to call " .. method)
end
function methods:SetBackdrop() RequiresBackdrop(self, "SetBackdrop") end
function methods:SetBackdropColor() RequiresBackdrop(self, "SetBackdropColor") end
function methods:SetBackdropBorderColor() RequiresBackdrop(self, "SetBackdropBorderColor") end

-- Items: id -> where it goes. Links carry the id, as in game.
ITEMS = {
    [100] = { name = "Old Tunic", loc = "INVTYPE_CHEST" },
    [200] = { name = "New Tunic", loc = "INVTYPE_CHEST" },
    [110] = { name = "Old Leggings", loc = "INVTYPE_LEGS" },
    [210] = { name = "New Leggings", loc = "INVTYPE_LEGS" },
    [300] = { name = "Main Sword", loc = "INVTYPE_WEAPON" },
    [301] = { name = "Off Sword", loc = "INVTYPE_WEAPON" },
    [302] = { name = "New Sword", loc = "INVTYPE_WEAPON" },
    [400] = { name = "Old Ring", loc = "INVTYPE_FINGER" },
    [401] = { name = "New Ring", loc = "INVTYPE_FINGER" },
    [500] = { name = "Old Cap", loc = "INVTYPE_HEAD" },
    [501] = { name = "Tauren Horns Cap", loc = "INVTYPE_HEAD" },
    [502] = { name = "Slow Cap", loc = "INVTYPE_HEAD" },
}
local function Link(id) return "|cff1eff00|Hitem:" .. id .. "::::|h[" .. ITEMS[id].name .. "]|h|r" end
local function ID(link) return link and tonumber(link:match("item:(%d+)")) end
EQUIPPED = { [1] = Link(500), [5] = Link(100), [7] = Link(110), [11] = Link(400), [16] = Link(300), [17] = Link(301) }
REFUSED, LOADING_UNTIL = { [501] = true }, { [502] = 1.5 }
NOW = 0

Enum = { ItemTryOnReason = { Success = 0, WrongRace = 1, NotEquippable = 2, DataPending = 3 } }
local ARMOUR = { INVTYPE_CHEST = 5, INVTYPE_LEGS = 7, INVTYPE_HEAD = 1 }

-- A character model as the game runs one. SetUnit loads in the background;
-- a hidden model loads nothing and reloads when it appears; and on arrival it
-- reports in, then dresses itself in what you wear a frame later -- the worst
-- order for anything tried on before it was ready.
local model = {}
function model:SetUnit(unit)
    if self.unit == unit and self.loaded then return end -- the same character stays loaded
    self.unit, self.loaded, self.wait = unit, false, 2
end
function model:Dress()
    if not self.loaded then return end
    self.wear = {}
    for slot, link in pairs(EQUIPPED) do self.wear[slot] = link end
end
function model:TryOn(link, hand)
    local id = ID(link)
    if REFUSED[id] then return 1 end
    if LOADING_UNTIL[id] and NOW < LOADING_UNTIL[id] then return 3 end
    if not self.loaded then return 0 end -- accepted, then lost when the character arrives
    local loc = ITEMS[id].loc
    local slot = ARMOUR[loc]
    if loc == "INVTYPE_WEAPON" then
        if hand == "SECONDARYHANDSLOT" then slot = 17
        elseif hand == "MAINHANDSLOT" then slot = 16
        else slot = self.wear[16] == link and 17 or 16 end -- a second try fills the other hand
    end
    assert(slot, "tried on something with no look: " .. tostring(loc))
    self.wear[slot] = link
    return 0
end
function model:Tick()
    local visible = self:IsVisible()
    if visible and not self.wasVisible and self.unit then self.loaded, self.wait = false, 2 end
    self.wasVisible = visible
    if not visible then return end
    if self.redress then self.redress = nil; self.loaded = true; model.Dress(self) end
    if self.loaded or not self.unit then return end
    self.wait = self.wait - 1
    if self.wait > 0 then return end
    self.loaded = true
    model.Dress(self)
    if self.handlers.OnModelLoaded then self.handlers.OnModelLoaded(self) end
    self.redress = true
end
function model:SetFacing(facing) self.facing = facing end

function CreateFrame(kind, name, parent, template)
    local f = setmetatable({ kind = kind, handlers = {}, shown = true, parent = parent, template = template, wear = {} }, frame)
    if kind == "DressUpModel" then
        for key, fn in pairs(model) do rawset(f, key, fn) end
    end
    frames[#frames + 1] = f
    if name then _G[name] = f end
    return f
end
UIParent = CreateFrame("Frame")
GameTooltip = { SetOwner = noop, SetHyperlink = noop, SetText = noop, AddLine = noop, Show = noop, Hide = noop }
function InCombatLockdown() return false end
function GetCursorPosition() return CURSOR_X or 0, 0 end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end

local function Frame(seconds)
    for _ = 1, math.floor(seconds * 60 + 0.5) do
        NOW = NOW + 1 / 60
        for _, f in ipairs(frames) do
            if f.kind == "DressUpModel" then f:Tick() end
        end
        for _, f in ipairs(frames) do
            if f.handlers.OnUpdate and f:IsVisible() then f.handlers.OnUpdate(f, 1 / 60) end
        end
    end
end

local shellNs = {}
assert(loadfile(shell .. "/Theme.lua"))("MiniQoL", shellNs)
MiniQoL = shellNs

local ns = {
    db = { styles = true },
    slotNames = { [1] = "Head", [5] = "Chest", [7] = "Legs", [11] = "Ring", [16] = "Main Hand", [17] = "Off Hand" },
    profile = { label = "Arms" },
    Items = { Get = function(_, link) local item = ITEMS[ID(link)]; return item and { name = item.name, icon = 1, loc = item.loc } end },
    Upgrades = { Schedule = noop },
    Print = noop,
}
-- The packaged copy runs inside the bundle's module adapter.
MiniQoLRuntime = { Execute = function(_, name, chunk) return chunk(name, ns) end }
assert(loadfile(gearwise .. "/Sidegrades.lua"))("Gearwise", ns)
local S = ns.Sidegrades

local function Offer(key, id, slot)
    return { key = key, link = Link(id), id = id, result = { status = "equal", slot = slot, oldLinks = { EQUIPPED[slot] } } }
end
local function Hover(offer)
    S.offers, S.shown[offer.key] = { offer }, true
    S:Layout()
    HOVERING = true
    S.badges[1].handlers.OnEnter(S.badges[1])
end
local function Models() return S.panel.currentModel, S.panel.previewModel end
local function Note(m) return m.note:IsShown() and m.note.text:GetText() or nil end

-- A chest piece: the preview wears it, the other model what you have on.
local chest = Offer("b1", 200, 5)
Hover(chest)
Frame(2.5)
local current, preview = Models()
assert(S.panel:IsShown(), "the panel opens on hover")
assert(preview.wear[5] == Link(200), "the preview wears the new item, not " .. tostring(preview.wear[5]))
assert(current.wear[5] == Link(100), "the other model wears what you have on")
assert(preview.wear[7] == Link(110), "the rest of the preview is what you wear")
assert(not Note(preview), "nothing to explain")

-- Turning, then coming back over the badge, keeps the turn.
S:SetFacing(2)
S.badges[1].handlers.OnEnter(S.badges[1])
assert(S.facing == 2 and preview.facing == 2, "the same badge leaves the models as they were")

-- Another offer with the panel still open: the last try-on comes off.
local legs = Offer("b2", 210, 7)
Hover(legs)
Frame(2.5)
assert(preview.wear[7] == Link(210), "the new offer is worn")
assert(preview.wear[5] == Link(100), "and the last one's item came off")
assert(S.facing == 0.4, "a new offer starts from the front")

-- An off-hand weapon goes in the off hand, and only there.
S:HidePanel()
Hover(Offer("b3", 302, 17))
Frame(2.5)
assert(preview.wear[17] == Link(302), "the off-hand offer is in the off hand")
assert(preview.wear[16] == Link(300), "the main hand is untouched, not " .. tostring(preview.wear[16]))

-- A ring has no look: say so, instead of two identical models.
S:HidePanel()
Hover(Offer("b4", 401, 11))
Frame(2.5)
assert(Note(preview) == "This doesn't show on your character.", "a ring says it does not show")
assert(not Note(current), "only on the preview")

-- Something the character cannot be shown in.
S:HidePanel()
Hover(Offer("b5", 501, 1))
Frame(0.1)
assert(not Note(preview), "no verdict while the model is still loading")
Frame(2.5)
assert(Note(preview) == "Can't be shown on your character.", "a refusal is explained")
assert(preview.wear[1] == Link(500), "and the model keeps what you wear")

-- An item whose look loads late still ends up on the model.
S:HidePanel()
Hover(Offer("b6", 502, 1))
Frame(3)
assert(preview.wear[1] == Link(502), "a late look is put on once it arrives")
assert(not Note(preview), "with nothing to explain")

-- A note from one offer does not carry over to the next.
S:HidePanel()
Hover(chest)
Frame(2.5)
assert(not Note(preview) and preview.wear[5] == Link(200), "a fresh offer starts clean")

-- Leaving the badge and the panel closes it.
HOVERING = false
Frame(0.5)
assert(not S.panel:IsShown(), "the panel closes once the pointer leaves")
print("Look preview: try-ons survive the model loading, hands and unseen slots passed")
