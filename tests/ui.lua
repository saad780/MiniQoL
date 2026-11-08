local root = ...
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
C_AddOns = { GetAddOnMetadata = function() return "test" end, IsAddOnLoaded = function() return false end,
    GetNumAddOns = function() return 0 end }
Settings = { RegisterCanvasLayoutCategory = function() return {} end, RegisterAddOnCategory = function() end }
GameTooltip = { SetOwner = function() end, SetText = function() end, AddLine = function() end, Show = function() end, Hide = function() end }
function ReloadUI() reloaded = true end
-- The service icon rows are generated from Wayfinder's own category list. The
-- module itself stays unloaded, so the rows render disabled, which is exactly
-- the state the panel has to lay out correctly.
Wayfinder = { CategoryList = { { id = "bank", label = "Bankers" }, { id = "inn", label = "Innkeepers" } } }
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
local count = #objects
for i = 1, 20 do ns:Render() end
assert(#objects == count, "refresh reuses UI widgets")
ns:Toggle()
assert(not ns.panel:IsShown(), "panel closes")
print("Panel navigation, search, favorites and minimap controls passed")
