-- Controller Safe Menu
-- A context menu an addon can open without breaking the game's controller UI.
--
-- Why: with the controller UI on, the game's menus (MenuUtil) join its
-- controller focus system (Blizzard_GamepadSharedUtility's
-- FrameControlsManager, on "MenuProxy.OnShow"). A menu that an addon opens
-- taints that system as it opens and closes, and the game then blocks
-- SetPreferredGamepadInteractTarget: "Interface action failed", and the chat
-- after it. Seen on WoW Forever, 2026-11-25.
--
-- What it does: ControllerSafeMenu.CreateContextMenu(owner, generator) takes
-- the same arguments as MenuUtil.CreateContextMenu.
--   • Controller UI off: it calls MenuUtil.CreateContextMenu, nothing changes.
--   • Controller UI on: it draws a small menu of its own, outside the
--     controller system, from the same generator. Nothing of the game's is
--     replaced or hooked.
-- The generator may use: CreateTitle, CreateButton, CreateCheckbox,
-- CreateRadio, CreateDivider, CreateSpacer, and on an element SetEnabled,
-- SetTooltip and SetResponse. Children of an element (a submenu) are listed
-- under it, indented. Other element methods are accepted and do nothing.
-- The menu closes on a click outside it, on a second open, or when its
-- owner hides. It's used with the mouse: the controller can't move through
-- it (it isn't in the game's controller system, on purpose).
--
-- Use, either way:
--   • embedded: copy this file into your addon, list it in your .toc before
--     the files that use it, and use addonTable.ControllerSafeMenu;
--   • as its own addon: ## Dependencies: ControllerSafeMenu, then use the
--     global ControllerSafeMenu.
-- Then replace MenuUtil.CreateContextMenu(owner, generator) with
-- ControllerSafeMenu.CreateContextMenu(owner, generator).
--
-- https://github.com/ArtisanGW/ControllerSafeMenu (MIT license)
local addonName, addonTable = ...

local ControllerSafeMenu = {}
ControllerSafeMenu.VERSION = 1
if type(addonTable) == "table" then addonTable.ControllerSafeMenu = ControllerSafeMenu end
if addonName == "ControllerSafeMenu" then _G.ControllerSafeMenu = ControllerSafeMenu end

local ROW_HEIGHT = 18
local TITLE_HEIGHT = 20
local DIVIDER_HEIGHT = 10
local SPACER_HEIGHT = 8
local INDENT = 12
local PADDING = 10
local MIN_WIDTH = 120
local CHECK_SIZE = 16

-- The game's answers a callback can give (MenuResponse). Fallbacks for a
-- client without the menu system.
local RESPONSE = {
    Open = MenuResponse and MenuResponse.Open or 1,
    Refresh = MenuResponse and MenuResponse.Refresh or 2,
    Close = MenuResponse and MenuResponse.Close or 3,
    CloseAll = MenuResponse and MenuResponse.CloseAll or 4,
}

-- ── Whether to draw our own ───────────────────────────────────────────────

function ControllerSafeMenu.IsControllerUIOn()
    return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() and true or false
end

local function GameMenuAvailable()
    return MenuUtil and MenuUtil.CreateContextMenu and true or false
end

-- ── The description the generator fills ───────────────────────────────────
-- A tree of plain tables: { kind, text, isSelected, setSelected, callback,
-- data, enabled, tooltip, response, children }.

local Element = {}
local elementMetatable = {
    __index = function(_, key)
        if Element[key] then return Element[key] end
        -- A method of the game's menu we don't draw (methods start with a
        -- capital letter; a missing field, such as text, stays nil).
        if type(key) == "string" and key:match("^%u") then return function() end end
    end,
}

local function NewElement(kind, fields)
    local element = fields or {}
    element.kind, element.enabled, element.children = kind, true, {}
    return setmetatable(element, elementMetatable)
end

local function AddChild(parent, element)
    parent.children[#parent.children + 1] = element
    return element
end

function Element:CreateTitle(text)
    return AddChild(self, NewElement("title", { text = text }))
end

function Element:CreateButton(text, callback, data)
    return AddChild(self, NewElement("button", { text = text, callback = callback, data = data }))
end

function Element:CreateCheckbox(text, isSelected, setSelected, data)
    return AddChild(self, NewElement("checkbox",
        { text = text, isSelected = isSelected, setSelected = setSelected, data = data }))
end

function Element:CreateRadio(text, isSelected, setSelected, data)
    return AddChild(self, NewElement("radio",
        { text = text, isSelected = isSelected, setSelected = setSelected, data = data }))
end

function Element:CreateDivider()
    return AddChild(self, NewElement("divider"))
end

function Element:CreateSpacer()
    return AddChild(self, NewElement("spacer"))
end

function Element:SetEnabled(enabled)
    self.enabled = enabled
end

function Element:IsEnabled()
    if type(self.enabled) == "function" then return self.enabled(self) and true or false end
    return self.enabled ~= false
end

function Element:SetTooltip(tooltipFunction)
    self.tooltip = tooltipFunction
end

function Element:SetResponse(response)
    self.response = response
end

-- Builds the tree a generator describes.
function ControllerSafeMenu.Describe(owner, generator)
    local root = NewElement("root")
    generator(owner, root)
    return root
end

-- The rows to draw, in order, each with its depth (submenus are indented).
function ControllerSafeMenu.Flatten(root)
    local rows = {}
    local function Add(element, depth)
        for _, child in ipairs(element.children) do
            rows[#rows + 1] = { element = child, depth = depth }
            Add(child, depth + 1)
        end
    end
    Add(root, 0)
    return rows
end

local function IsSelected(element)
    if type(element.isSelected) ~= "function" then return false end
    return element.isSelected(element.data) and true or false
end

-- What a click on a row does. Returns whether the menu stays open: a button
-- closes it, a checkbox or radio stays open for the next choice, and the
-- callback's answer (or SetResponse) wins over both.
function ControllerSafeMenu.Activate(element)
    if not element:IsEnabled() then return true end
    local answer
    if element.kind == "button" and element.callback then
        answer = element.callback(element.data)
    elseif element.kind == "checkbox" or element.kind == "radio" then
        if element.setSelected then answer = element.setSelected(element.data) end
    else
        return true
    end
    answer = answer or element.response
    if answer == RESPONSE.Open or answer == RESPONSE.Refresh then return true end
    if answer == RESPONSE.Close or answer == RESPONSE.CloseAll then return false end
    return element.kind ~= "button"
end

-- ── Drawing it ────────────────────────────────────────────────────────────

local menuFrame, rowPool
local openOwner, openGenerator
local hookedOwners = setmetatable({}, { __mode = "k" })

local function HideMenu()
    if menuFrame then menuFrame:Hide() end
    openOwner, openGenerator = nil, nil
end

local function ShowRowTooltip(row)
    local element = row.element
    if not (element and element.tooltip and GameTooltip) then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    element.tooltip(GameTooltip, element)
    GameTooltip:Show()
end

local function HideRowTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

local Redraw

local function OnRowClick(row)
    local staysOpen = ControllerSafeMenu.Activate(row.element)
    if staysOpen then Redraw() else HideMenu() end
end

local function InitRow(row)
    row:SetHeight(ROW_HEIGHT)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetJustifyH("LEFT")
    row.check = row:CreateTexture(nil, "ARTWORK")
    row.check:SetSize(CHECK_SIZE, CHECK_SIZE)
    row.line = row:CreateTexture(nil, "ARTWORK")
    row.line:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
    row.line:SetHeight(8)
    row.line:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.line:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:SetScript("OnClick", OnRowClick)
    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", HideRowTooltip)
end

local function ResetRow(_, row)
    row:Hide()
    row:ClearAllPoints()
    row.element = nil
end

local function CreateMenuFrame()
    menuFrame = CreateFrame("Frame", nil, UIParent, "TooltipBackdropTemplate")
    menuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    menuFrame:SetClampedToScreen(true)
    menuFrame:EnableMouse(true)
    menuFrame:Hide()
    rowPool = CreateFramePool("Button", menuFrame, nil, ResetRow)

    -- A click anywhere outside closes it, like the game's menus.
    menuFrame:RegisterEvent("GLOBAL_MOUSE_DOWN")
    menuFrame:SetScript("OnEvent", function(self)
        if self:IsShown() and not self:IsMouseOver() then HideMenu() end
    end)
    menuFrame:SetScript("OnHide", HideRowTooltip)
end

local function AcquireRow()
    local row, isNew = rowPool:Acquire()
    if isNew or not row.label then InitRow(row) end
    return row
end

local function DrawRow(row, entry, top)
    local element, indent = entry.element, PADDING + entry.depth * INDENT
    local kind = element.kind
    row.element = element
    row.label:SetText(element.text or "")
    row.label:ClearAllPoints()
    row.check:Hide()
    row.line:SetShown(kind == "divider")
    row.label:SetShown(kind ~= "divider" and kind ~= "spacer")

    local height = ROW_HEIGHT
    if kind == "title" then height = TITLE_HEIGHT
    elseif kind == "divider" then height = DIVIDER_HEIGHT
    elseif kind == "spacer" then height = SPACER_HEIGHT end
    row:SetHeight(height)

    local textLeft = indent
    if kind == "checkbox" or kind == "radio" then
        row.check:ClearAllPoints()
        row.check:SetPoint("LEFT", row, "LEFT", indent, 0)
        if kind == "checkbox" then
            row.check:SetTexture(IsSelected(element) and "Interface\\Buttons\\UI-CheckBox-Check" or nil)
            row.check:SetTexCoord(0, 1, 0, 1)
        else
            row.check:SetTexture("Interface\\Buttons\\UI-RadioButton")
            local left = IsSelected(element) and 0.25 or 0
            row.check:SetTexCoord(left, left + 0.25, 0, 1)
        end
        row.check:Show()
        textLeft = indent + CHECK_SIZE + 4
    end
    row.label:SetPoint("LEFT", row, "LEFT", textLeft, 0)
    row.label:SetFontObject(kind == "title" and "GameFontNormalSmall" or "GameFontHighlightSmall")

    local clickable = kind == "button" or kind == "checkbox" or kind == "radio"
    row:EnableMouse(clickable or element.tooltip ~= nil)
    row:SetEnabled(clickable and element:IsEnabled())
    if clickable and not element:IsEnabled() then row.label:SetFontObject("GameFontDisableSmall") end

    row:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 0, -top)
    row:SetPoint("RIGHT", menuFrame, "RIGHT", 0, 0)
    row:Show()
    return height, textLeft + (row.label:GetStringWidth() or 0) + PADDING
end

function Redraw()
    if not (openOwner and openGenerator) then return end
    rowPool:ReleaseAll()
    local root = ControllerSafeMenu.Describe(openOwner, openGenerator)
    local top, width = PADDING, MIN_WIDTH
    for _, entry in ipairs(ControllerSafeMenu.Flatten(root)) do
        local height, rowWidth = DrawRow(AcquireRow(), entry, top)
        top = top + height
        width = math.max(width, rowWidth)
    end
    menuFrame:SetSize(width, top + PADDING)
end

local function ShowOwnMenu(owner, generator)
    if not menuFrame then CreateMenuFrame() end
    -- A second open from the same owner closes it, like the game's.
    if menuFrame:IsShown() and openOwner == owner then
        HideMenu()
        return
    end
    openOwner, openGenerator = owner, generator
    menuFrame:ClearAllPoints()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    menuFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    Redraw()
    menuFrame:Show()

    -- Closes with its owner (a window that hides, say). Kept here, not on the
    -- owner: writing a field on a game frame would taint it.
    if owner and owner ~= UIParent and owner.HookScript and not hookedOwners[owner] then
        owner:HookScript("OnHide", function(self) if openOwner == self then HideMenu() end end)
        hookedOwners[owner] = true
    end
end

-- ── The one call ──────────────────────────────────────────────────────────

function ControllerSafeMenu.CreateContextMenu(owner, generator)
    if not ControllerSafeMenu.IsControllerUIOn() and GameMenuAvailable() then
        return MenuUtil.CreateContextMenu(owner, generator)
    end
    ShowOwnMenu(owner, generator)
end

function ControllerSafeMenu.Close()
    HideMenu()
end

function ControllerSafeMenu.IsOpen()
    return menuFrame ~= nil and menuFrame:IsShown()
end
