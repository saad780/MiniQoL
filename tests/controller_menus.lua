-- Menus with the game's Gamepad UI on: Mini QoL's right-click menus and
-- dropdowns go through ControllerSafeMenu, which hands them to the game's own
-- menu system while the Gamepad UI is off and draws its own while it is on.
local root = ...
local function noop() end

---------------------------------------------------------------------------
-- Just enough of the game's frames for the vendored menu to draw itself
---------------------------------------------------------------------------
local function Frame()
    local f = { scripts = {}, shown = false, events = {} }
    setmetatable(f, { __index = function(_, key)
        if type(key) == "string" and key:find("^%u") then return noop end
    end })
    function f:SetScript(name, fn) self.scripts[name] = fn end
    function f:GetScript(name) return self.scripts[name] end
    function f:HookScript(name, fn)
        local before = self.scripts[name]
        self.scripts[name] = function(...) if before then before(...) end; fn(...) end
    end
    function f:Show() self.shown = true end
    function f:Hide()
        local was = self.shown
        self.shown = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function f:IsShown() return self.shown end
    function f:SetShown(value) if value then self:Show() else self:Hide() end end
    function f:IsMouseOver() return false end
    function f:RegisterEvent(name) self.events[name] = true end
    function f:CreateTexture() return Frame() end
    function f:CreateFontString()
        local text = Frame()
        function text:SetText(value) self.text = value end
        function text:GetStringWidth() return #(self.text or "") * 6 end
        return text
    end
    return f
end
function CreateFrame() return Frame() end
function CreateFramePool(_, _, _, reset)
    local pool = { active = {}, free = {} }
    function pool:Acquire()
        local frame = table.remove(self.free)
        local new = frame == nil
        frame = frame or Frame()
        self.active[#self.active + 1] = frame
        return frame, new
    end
    function pool:ReleaseAll()
        for _, frame in ipairs(self.active) do
            reset(self, frame)
            self.free[#self.free + 1] = frame
        end
        self.active = {}
    end
    return pool
end
UIParent = Frame()
function UIParent:GetEffectiveScale() return 1 end
function GetCursorPosition() return 100, 200 end
GameTooltip = Frame()
MenuResponse = { Open = 1, Refresh = 2, Close = 3, CloseAll = 4 }

local gamepad = false
InputUtil = { IsGamepadUIEnabled = function() return gamepad end }
local gameMenus = {}
MenuUtil = { CreateContextMenu = function(owner, generator)
    gameMenus[#gameMenus + 1] = { owner = owner, generator = generator }
end }

local function equal(actual, expected, label)
    assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

local ns = {}
assert(loadfile(root .. "/Vendor/ControllerSafeMenu/ControllerSafeMenu.lua"))("MiniQoL", ns)
assert(loadfile(root .. "/Menus.lua"))("MiniQoL", ns)
local Safe = ns.ControllerSafeMenu
assert(Safe, "the vendored menu joins Mini QoL's namespace")
MiniQoL = ns

---------------------------------------------------------------------------
-- 1. A context menu: the game's while the Gamepad UI is off, our own while on
---------------------------------------------------------------------------
local picked = 0
local function Generator(_, rootMenu)
    rootMenu:CreateTitle("Pick one")
    rootMenu:CreateRadio("First", function() return picked == 1 end, function() picked = 1 end)
    rootMenu:CreateButton("Clear", function() picked = 0 end)
end
local owner = Frame()
equal(ns.OwnMenus(), false, "Gamepad UI off: the game draws menus")
ns.ContextMenu(owner, Generator)
equal(#gameMenus, 1, "through the game's MenuUtil")
equal(gameMenus[1].generator, Generator, "with the same generator")

gamepad = true
equal(ns.OwnMenus(), true, "Gamepad UI on: menus are our own")
ns.ContextMenu(owner, Generator)
equal(#gameMenus, 1, "the game's menu system is left alone")
equal(Safe.IsOpen(), true, "the safe menu is drawn")
ns.ContextMenu(owner, Generator)
equal(Safe.IsOpen(), false, "a second open from the same owner closes it, as the game's does")

---------------------------------------------------------------------------
-- 2. Dropdowns: the game's dropdown until the Gamepad UI is on, then the safe
-- menu, with the dropdown's text brought up to date after a choice
---------------------------------------------------------------------------
local dropdown = Frame()
local generated, opened = 0, 0
function dropdown:SetupMenu(generator) self.generator = generator end
function dropdown:GenerateMenu() generated = generated + 1 end
function dropdown:IsEnabled() return true end
dropdown:SetScript("OnMouseDown", function() opened = opened + 1 end)
local choice
ns.SetupDropdown(dropdown, function(_, rootMenu)
    rootMenu:CreateRadio("Alpha", function(value) return choice == value end, function(value) choice = value end, "a")
    rootMenu:CreateRadio("Beta", function(value) return choice == value end, function(value) choice = value end, "b")
end)
assert(dropdown.generator, "the dropdown is set up as usual")

gamepad = false
dropdown.scripts.OnMouseDown(dropdown, "LeftButton")
equal(opened, 1, "Gamepad UI off: the dropdown opens its own menu")

gamepad = true
local captured
local draw = Safe.CreateContextMenu
Safe.CreateContextMenu = function(menuOwner, generator) captured = { owner = menuOwner, generator = generator } end
dropdown.scripts.OnMouseDown(dropdown, "LeftButton")
equal(opened, 1, "Gamepad UI on: not the game's menu")
assert(captured and captured.owner == dropdown, "the safe menu opens on the dropdown")
local rows = Safe.Flatten(Safe.Describe(dropdown, captured.generator))
equal(#rows, 2, "with the dropdown's choices")
local before = generated
equal(Safe.Activate(rows[2].element), true, "a radio leaves the menu open for another choice")
equal(choice, "b", "the choice is made")
equal(generated, before + 1, "and the dropdown's text catches up")

---------------------------------------------------------------------------
-- 3. The arrow's waypoint list: without row frames to put an x on, each
-- waypoint gets a removal line of its own
---------------------------------------------------------------------------
local wf = { db = { waypoints = {}, settings = {} } }
function wf:NewModule(name) self[name] = { name = name } return self[name] end
function wf.Print() end
function wf.Readable() return true end
function wf:GetSetting(key) return self.db.settings[key] end
function wf:Fire() end
function wf.GetPlayerWorld() end
function wf.GetMapRect() end
function wf.Distance(x1, y1, x2, y2) return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) end
function wf:GetCharacterKey() return "Tester" end
wf.ContextMenu = ns.ContextMenu
wf.OwnMenus = ns.OwnMenus
Enum = { UIMapType = { Zone = 3 } }
StaticPopupDialogs = {}
C_Map = { GetMapPosFromWorldPos = function() return nil end, GetMapInfo = function() return nil end }
function CreateVector2D(x, y) return { x = x, y = y } end
MiniQoLRuntime = { Execute = function(_, _, fn) return fn("Wayfinder", wf) end }
assert(loadfile(root .. "/Modules/Wayfinder/Navigation.lua"))()
local Navigation = wf.Navigation
Navigation:AddWaypoint(1, 10, 10, "Inn", nil, { quiet = true })
Navigation:AddWaypoint(1, 50, 50, "Mailbox", nil, { quiet = true })
captured = nil
Navigation:OpenWaypointMenu(owner)
assert(captured, "the list opens through the safe menu")
local removals, radios = 0, 0
for _, row in ipairs(Safe.Flatten(Safe.Describe(owner, captured.generator))) do
    if row.element.kind == "radio" then radios = radios + 1 end
    if row.element.kind == "button" and (row.element.text or ""):find("Remove", 1, true) then removals = removals + 1 end
end
equal(radios, 2, "a row for each waypoint")
equal(removals, 2, "and a line to remove each")
Safe.CreateContextMenu = draw

print("Controller menus: game menus with the Gamepad UI off, our own with it on, dropdowns refreshed, the waypoint list's removal lines passed")
