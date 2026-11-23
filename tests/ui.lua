local root, gearwise = ...
local objects = {}
local methods = {}
function methods:SetScript(key, value) self.scripts[key] = value end
function methods:GetScript(key) return self.scripts[key] end
function methods:HookScript(key, value)
    local before = self.scripts[key]
    self.scripts[key] = function(...) if before then before(...) end; value(...) end
end
function methods:SetShown(value)
    value = not not value
    local previous = self.shown
    self.shown = value
    if value ~= previous and self.scripts[value and "OnShow" or "OnHide"] then
        self.scripts[value and "OnShow" or "OnHide"](self)
    end
end
function methods:Show() self:SetShown(true) end
function methods:Hide() self:SetShown(false) end
function methods:IsShown() return self.shown end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:GetWidth() return self.width or 100 end
function methods:GetHeight() return self.height or 280 end
function methods:SetText(value)
    self.value = value
    if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
end
function methods:GetText() return self.value or "" end
function methods:SetPoint(...) self.point = { ... } end
function methods:GetPoint() return "CENTER", UIParent, "CENTER", 0, 0 end
function methods:ClearAllPoints() self.point = nil end
function methods:SetEnabled(value) assert(type(value) == "boolean", "UI enabled state must be a boolean"); self.enabled = value end
function methods:SetChecked(value) assert(type(value) == "boolean", "checked must be boolean"); self.checked = value end
function methods:GetChecked() return self.checked end
function methods:SetVerticalScroll(value) self.offset = value end
function methods:GetVerticalScroll() return self.offset or 0 end
function methods:GetFrameLevel() return 1 end
function methods:GetEffectiveScale() return 1 end
function methods:GetCenter() return 1800, 900 end
function methods:RegisterEvent() end
function methods:GetStringHeight()
    local lines = 1
    for _ in tostring(self.value or ""):gmatch("\n") do lines = lines + 1 end
    return lines * 12
end
function methods:IsMouseOver() return false end
function methods:IsEnabled() return self.enabled ~= false end
function methods:IsVisible() return self.shown end
function methods:SetValue(value) self.sliderValue = value
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value, false) end end
function methods:GetValue() return self.sliderValue or 0 end
local noops = { "SetJustifyH", "SetJustifyV", "SetWordWrap", "SetTextColor", "SetColorTexture", "SetAllPoints", "SetTexture", "SetTexCoord",
    "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetClampedToScreen", "SetFrameStrata", "SetMovable",
    "EnableMouse", "RegisterForDrag", "SetHighlightTexture", "SetAutoFocus", "SetMaxLetters", "SetScrollChild",
    "SetAlpha", "StartMoving", "StopMovingOrSizing", "ClearFocus", "SetFrameLevel", "RegisterForClicks",
    -- Widgets the themed panel adds: sliders, drawn carets and the plain edit box.
    "SetFontObject", "SetTextInsets", "SetOrientation", "SetObeyStepOnDrag", "SetThumbTexture",
    "SetMinMaxValues", "SetValueStep", "SetThickness", "SetStartPoint", "SetEndPoint",
    "SetVertexColor", "SetRotation", "EnableMouseWheel", "SetClipsChildren", "SetPassThroughButtons" }
for _, name in ipairs(noops) do methods[name] = function() end end
local function object(kind, name, parent)
    local obj = setmetatable({ kind = kind, name = name, parent = parent, shown = true, scripts = {} }, { __index = methods })
    if name then _G[name] = obj end
    objects[#objects + 1] = obj
    return obj
end
function CreateFrame(kind, name, parent) return object(kind, name, parent) end
function methods:CreateFontString(name) return object("FontString", name, self) end
function methods:CreateTexture(name) return object("Texture", name, self) end
function methods:CreateLine(name) return object("Line", name, self) end
UIParent, Minimap = object("Frame", "UIParent"), object("Frame", "Minimap")
Minimap:SetSize(200, 200)
UISpecialFrames, SlashCmdList = {}, {}
function UnitName() return "Testplayer" end
function InCombatLockdown() return false end
LOADED = {}
C_AddOns = { GetAddOnMetadata = function() return "test" end, IsAddOnLoaded = function(name) return LOADED[name] == true end,
    GetNumAddOns = function() return 0 end }
Settings = { RegisterCanvasLayoutCategory = function() return {} end, RegisterAddOnCategory = function() end }
GameTooltip = { SetOwner = function() end, SetText = function() end, AddLine = function(_, text) tip = text end,
    Show = function() end, Hide = function() end }
function ReloadUI() reloaded = true end
-- The service icon rows are generated from Wayfinder's own category list. The
-- module itself stays unloaded, so the rows render disabled, which is exactly
-- the state the panel has to lay out correctly.
Wayfinder = { CategoryList = { { id = "bank", label = "Bankers" }, { id = "inn", label = "Innkeepers" } } }
-- Gearwise's stat values are declared from its own list, so the real Core and
-- Profiles are loaded. It stays switched off (no saved data) until the end.
local gear = {}
function UnitClass() return CLASS_NAME or "Rogue", CLASS or "ROGUE" end
function UnitLevel() return 60 end
if gearwise then
    MiniQoLRuntime = { order = {}, modules = {}, namespaces = {},
        Execute = function(_, name, chunk) return chunk(name, gear) end }
    for _, file in ipairs({ "Core.lua", "Profiles.lua" }) do
        assert(loadfile(gearwise .. "/" .. file))("Gearwise", gear)
    end
    gear.Compare, gear.Display, gear.Options = { Clear = function() end }, { Schedule = function() end }, {}
    gear.Print = function(text) GEAR_SAID = text end
end
local ns = {}
assert(loadfile(root .. "/Core.lua"))("MiniQoL", ns)
assert(loadfile(root .. "/Theme.lua"))("MiniQoL", ns)
ns:Initialize()
assert(loadfile(root .. "/Integrations.lua"))("MiniQoL", ns)
assert(loadfile(root .. "/Panel.lua"))("MiniQoL", ns)
assert(loadfile(root .. "/Minimap.lua"))("MiniQoL", ns)
ns:CreateMinimapButton()
assert(ns.minimapButton:IsShown(), "minimap button visible by default")
ns:Toggle()
assert(ns.panel:IsShown(), "panel opens")
assert(ns.panel:GetWidth() == 880 and ns.panel:GetHeight() == 520, "panel dimensions")
for _, page in ipairs(ns.pages) do ns:ShowPage(page.id); assert(ns.db.page == page.id) end
ns.search:SetText("bank")
assert(ns.rows["section.controls"].label:GetText() == "SEARCH RESULTS", "global search view")
assert(ns.rows["feature.wayfinder.cat.bank"]:IsShown(), "search includes settings outside current page")
ns.search:SetText("zzzz-no-match")
assert(ns.rows["note.empty"]:IsShown(), "empty search state")
ns:ShowPage("home")
local row = ns.rows["feature.wayfinder.showMinimapServices"]
row.favorite.scripts.OnClick()
assert(ns.db.favorites["wayfinder.showMinimapServices"], "favorites persist")
ns:ShowPage("miniqol")
-- The themed tick box owns its own state, so a click toggles it and then
-- writes: start from "shown" and one click must hide the button.
local icon = ns.rows["feature.miniqol.icon"].check
icon:SetChecked(true); icon.scripts.OnClick(icon)
assert(icon:GetChecked() == false, "clicking toggles the box")
assert(not ns.minimapButton:IsShown(), "minimap visibility setting")
SlashCmdList.MINIQOL("icon")
assert(ns.minimapButton:IsShown(), "slash command restores hidden icon")
ns.reload.scripts.OnClick()
assert(reloaded, "reload button")

-- A summary row spans the page with its label worked out at repaint, and
-- labels stop short of their buttons instead of running underneath.
ns:RegisterFeature({ id = "test.summary", page = "fishing", group = "Layout", label = "Summary", kind = "action",
    wide = true, primary = true, button = "Edit", text = function() return "3 pieces, 1 slot taken off" end,
    run = function() ranSummary = true end })
ns:RegisterFeature({ id = "test.choice", page = "fishing", group = "Layout", label = "Choice", kind = "select",
    controlWidth = 132, choices = { { "a", "A rather long option name" } },
    get = function() return "a" end, set = function() end,
    available = function() return false end, unavailable = "Turn the other setting on first." })
ns:RegisterFeature({ id = "test.plain", page = "fishing", group = "Layout", label = "Plain", kind = "action",
    button = "Run", run = function() end })
ns:ShowPage("fishing")
local summary = ns.rows["feature.test.summary"]
assert(summary.label:GetText() == "3 pieces, 1 slot taken off", "a row's label can be worked out at repaint")
assert(summary.width == 620, "a wide action spans the page")
assert(summary.label.width == 620 - 25 - 18 - 100 - 6, "its label stops short of the button")
assert(summary.control.primary, "and its button can lead")
summary.control.scripts.OnClick()
assert(ranSummary, "the wide button runs")
local choice = ns.rows["feature.test.choice"]
assert(choice.control.width == 132 and choice.label.width == 307 - 25 - 18 - 132 - 6, "selects can be wider")
assert(choice.control.label.width == 132 - 26, "and the value stays inside the button")
assert(choice.label:GetText() == "Choice", "an unavailable row shows its plain label")
choice.scripts.OnEnter(choice)
assert(tip and tip:find("Turn the other setting on first"), "an unavailable setting says why")
assert(ns.rows["feature.test.plain"].label.width == 307 - 25 - 18 - 100 - 6, "plain actions keep clear of their button")
local count = #objects
for i = 1, 20 do ns:Render() end
assert(#objects == count, "refresh reuses UI widgets")
-- Stat values: what one point of each stat is worth to the build in use, one
-- row per stat that build weighs.
if gearwise then
    assert(not ns.rows["feature.gearwise.value.agi"] or not ns.rows["feature.gearwise.value.agi"]:IsShown(),
        "no stat values while the module is off")
    LOADED.Gearwise = true
    gear.db = { spec = "auto", mode = "standard" }
    gear.profile = gear.Profiles:Detect()
    ns:ShowPage("bags")
    local function Row(id) local row = ns.rows["feature.gearwise." .. id]; return row and row:IsShown() and row or nil end
    local agi = Row("value.agi")
    assert(agi, "a rogue can set what Agility is worth")
    assert(Row("value.meleeDPS") and Row("value.rangedDPS"), "and weapon damage, both kinds")
    assert(not Row("value.sp") and not Row("value.defense") and not Row("value.heal"), "but not stats a rogue has no use for")
    assert(Row("values.about").label:GetText():find("Combat Rogue", 1, true), "the list says whose it is")
    assert(agi.label:GetText() == "Agility" and agi.value:GetText() == "2.30", "it starts on the build's own value")
    assert(Row("value.armor").value:GetText() == "0.015", "small values keep their decimals")
    assert(Row("value.meleeDPS").value:GetText() == "15.00", "and quarter steps theirs")
    local reset = Row("values.reset")
    assert(reset.control.enabled == false, "with nothing changed there is nothing to reset")
    -- Dragging the slider sets the value; the row then names the default.
    agi.control.slider:SetValue(3.0000001)
    assert(gear.db.custom.combat.agi == 3, "a dragged value is kept: " .. tostring(gear.db.custom.combat.agi))
    assert(gear.profile.weights.agi == 3 and gear.profile.custom, "and scores with at once")
    assert(agi.label:GetText():find("(default 2.3)", 1, true), "the row shows what it replaced: " .. agi.label:GetText())
    assert(agi.value:GetText() == "3.00", "beside the new value")
    assert(ns.rows["feature.gearwise.status"].label:GetText():find("your values", 1, true), "the build line says the values are yours")
    assert(reset.control.enabled == true and reset.label:GetText() == "1 of Combat's values is yours", "and reset counts them")
    reset.control.scripts.OnClick()
    assert(gear.db.custom.combat == nil and gear.profile.weights.agi == 2.3, "reset puts the build's own back")
    assert(agi.label:GetText() == "Agility" and agi.value:GetText() == "2.30", "on the page as well")
    assert(GEAR_SAID == "Combat is back on its own values.", "and says so")
    -- A drag writes every step at once but leaves repainting the page until
    -- the button comes up, and a repaint never hides a row that stays on the
    -- page: hiding the slider under the mouse would drop the drag.
    local renders, hides, render = 0, 0, ns.Render
    ns.Render = function(...) renders = renders + 1; return render(...) end
    agi:HookScript("OnHide", function() hides = hides + 1 end)
    local slider = agi.control.slider
    slider.scripts.OnMouseDown(slider, "LeftButton")
    slider:SetValue(2.5)
    assert(gear.db.custom.combat.agi == 2.5, "the first step of a drag is kept")
    slider:SetValue(3)
    assert(gear.db.custom.combat.agi == 3, "and every step after it")
    assert(agi.value:GetText() == "3.00", "the row's number follows the thumb")
    assert(renders == 0, "but the page isn't repainted under the mouse")
    agi.control:Apply(2.3)
    assert(slider:GetValue() == 3, "nor is the thumb pulled back mid-drag")
    slider.scripts.OnMouseUp(slider, "LeftButton")
    assert(renders == 1, "letting go repaints the page")
    assert(agi.label:GetText():find("(default 2.3)", 1, true), "with what the drag changed")
    ns:Render()
    assert(hides == 0 and agi:IsShown(), "repaints leave rows that stay on the page alone")
    ns.Render = render
    reset.control.scripts.OnClick()
    -- Another class has another list.
    CLASS_NAME, CLASS = "Priest", "PRIEST"
    gear.profile = gear.Profiles:Detect()
    ns:Render()
    assert(Row("value.sp") and Row("value.int") and Row("value.mp5"), "a priest sets spell power, intellect and mana")
    assert(not Row("value.agi") and not Row("value.meleeDPS"), "and is not asked about agility or melee damage")
    -- A pinned value follows the same rule on the Overview.
    ns.db.favorites["gearwise.value.agi"], ns.db.favorites["gearwise.value.sp"] = true, true
    ns:ShowPage("home")
    assert(Row("value.sp") and not Row("value.agi"), "a pinned value only shows for a build that has it")
    ns.db.favorites["gearwise.value.agi"], ns.db.favorites["gearwise.value.sp"] = nil, nil
end

ns:Toggle()
assert(not ns.panel:IsShown(), "panel closes")
print("Panel navigation, search, favorites, minimap controls and stat values passed")
