-- Minimap tracking: Wayfinder draws bankers and auctioneers itself and keeps
-- the game's own filters for them off. The game writing those filters back
-- must never turn the player's icons off, and the tracking menu has to change
-- them whether or not the markers happen to be drawing.
local root = ...
local function noop() end

-- The client's tracking list: Banker, Auctioneer, Mailbox.
Enum = { MinimapTrackingFilter = { Banker = 1, Auctioneer = 2, Mailbox = 3 } }
local NAMES = { "Banker", "Auctioneer", "Mailbox" }
NATIVE = { true, true, true }
C_Minimap = {}
function C_Minimap.GetNumTrackingTypes() return #NAMES end
function C_Minimap.GetTrackingInfo(i) return { name = NAMES[i], active = NATIVE[i], type = "other" } end
function C_Minimap.GetTrackingFilter(i) return { filterID = i } end
function C_Minimap.SetTracking(i, on) NATIVE[i] = on and true or false end
function C_Minimap.ClearAllTracking() for i = 1, #NAMES do NATIVE[i] = false end end
function hooksecurefunc(owner, name, hook)
    local original = owner[name]
    owner[name] = function(...) original(...); hook(...) end
end
function InCombatLockdown() return false end
function GetTime() return 0 end
C_Timer = { After = noop } -- redraws; the test syncs by hand
MenuResponse = { Refresh = 2 }
local menuHook
Menu = { ModifyMenu = function(tag, fn) assert(tag == "MENU_MINIMAP_TRACKING"); menuHook = fn end }
MinimapCluster = { Tracking = { Button = { IsMenuOpen = function() return MENU_OPEN == true end } } }

-- Wayfinder's settings, as Core.lua keeps them.
local settings = { showMinimapServices = true, cats = { bank = true, auction = true, mailbox = true } }
local ns = { CategoryList = {
    { id = "bank", filter = "Banker" }, { id = "auction", filter = "Auctioneer" }, { id = "mailbox", filter = "Mailbox" } } }
function ns:NewModule(name) self[name] = {}; return self[name] end
function ns.Readable(value) return value ~= nil end
function ns:GetSetting(key) return settings[key] end
function ns:IsCategoryEnabled(id) return settings.cats[id] ~= false end
function ns:SetCategoryEnabled(id, on) settings.cats[id] = on and true or false end
ns.RegisterEvent, ns.On = noop, noop
MiniQoLRuntime = { Execute = function(_, _, fn) return fn("Wayfinder", ns) end }
assert(loadfile(root .. "/Modules/Wayfinder/MinimapServices.lua"))("Wayfinder", ns)
local Mini = ns.MinimapServices
Mini:InstallTrackingMenu()

local function equal(actual, expected, label)
    assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function sync() Mini.trackingDirty = true; Mini:SyncTracking() end
-- The game's tracking menu, as Blizzard builds it: each entry's data is the
-- GetTrackingInfo table plus its index.
local function openMenu()
    local entries, rootDescription = {}, {}
    for i = 1, #NAMES do
        local entry = { data = { index = i, name = NAMES[i] } }
        function entry:GetData() return self.data end
        function entry:SetIsSelected(fn) self.isSelected = fn end
        function entry:SetResponder(fn) self.responder = fn end
        function entry:EnumerateElementDescriptions() return ipairs({}) end
        entries[i] = entry
    end
    function rootDescription:EnumerateElementDescriptions() return ipairs(entries) end
    menuHook(nil, rootDescription)
    return entries
end

-- Drawing: bank and auction filters are switched off, the rest follow.
Mini.active = true
sync()
equal(NATIVE[1], false, "the game's banker filter is off while Wayfinder draws bankers")
equal(NATIVE[2], false, "and the auctioneer one")
equal(NATIVE[3], true, "other filters follow the setting")

-- Blizzard's tracking button writes every filter's state back after a change.
for i = 1, #NAMES do C_Minimap.SetTracking(i, NATIVE[i]) end
equal(settings.cats.bank, true, "the write-back leaves bankers on")
equal(settings.cats.auction, true, "and auctioneers")
equal(settings.cats.mailbox, true, "mailboxes were in step already")
C_Minimap.SetTracking(3, false)
equal(settings.cats.mailbox, false, "a real change to another filter is still followed")
settings.cats.mailbox = true

-- Not drawing for a moment (no map position): the menu is still Wayfinder's.
Mini.active = false
sync()
equal(NATIVE[1], true, "with nothing drawn, the game's own filter shows bankers")
local entries = openMenu()
assert(entries[1].isSelected, "the banker entry is Wayfinder's even while it isn't drawing")
equal(entries[1].isSelected(entries[1].data), true, "and ticked")
entries[1].responder(entries[1].data)
equal(settings.cats.bank, false, "unticking turns bankers off")
equal(entries[1].isSelected(entries[1].data), false, "and shows unticked")
entries[1].responder(entries[1].data)
equal(settings.cats.bank, true, "ticking turns them back on")

-- Blizzard's own checkbox, if the menu ever comes without Wayfinder's: a
-- click while the menu is open is the player's choice.
Mini.active = true
sync()
MENU_OPEN = true
C_Minimap.SetTracking(2, false)
equal(settings.cats.auction, false, "a click in the open menu counts")
C_Minimap.SetTracking(2, true)
equal(settings.cats.auction, true, "both ways")
MENU_OPEN = false

-- The menu's Uncheck All is a choice too.
C_Minimap.ClearAllTracking()
equal(settings.cats.bank, false, "Uncheck All turns bankers off")
equal(settings.cats.auction, false, "and auctioneers")
equal(settings.cats.mailbox, false, "and everything else")
settings.cats.bank, settings.cats.auction, settings.cats.mailbox = true, true, true

-- Markers switched off: tracking is handed back once and then left alone.
sync()
settings.showMinimapServices = false
Mini.active = false
sync()
equal(NATIVE[1], true, "the banker filter is handed back on")
C_Minimap.SetTracking(1, false)
equal(settings.cats.bank, true, "after which Wayfinder doesn't follow the game's tracking")
assert(not openMenu()[1].isSelected, "and leaves the menu to the game")

-- Gathering the markers again. Nothing announces the player walking, so a
-- tick asks whether what was gathered still fits; it used to gather anyway.
local NOW, RADIUS, HERE = 10, 150, { 1, 100, 200 }
function GetTime() return NOW end
function C_Minimap.GetViewRadius() return RADIUS end
function ns.GetPlayerWorld() return HERE[1], HERE[2], HERE[3] end
Mini.lastUpdate = nil
assert(Mini:Outdated(), "nothing gathered yet is out of date")
Mini.active, Mini.lastUpdate = true, NOW
Mini.scanCont, Mini.scanX, Mini.scanY, Mini.scanRadius = 1, 100, 200, 150
assert(not Mini:Outdated(), "standing where it was gathered, it is current")
NOW = 10.8
assert(not Mini:Outdated(), "and stays current between safeguards")
HERE = { 1, 120, 215 }
assert(not Mini:Outdated(), "a short walk stays inside the margin gathered around the player")
HERE = { 1, 140, 200 }
assert(Mini:Outdated(), "walking past half the margin asks for more")
HERE = { 0, 100, 200 }
assert(Mini:Outdated(), "so does another continent")
HERE = { 1, 100, 200 }
RADIUS = 110
assert(Mini:Outdated(), "and the minimap zooming, or going indoors")
RADIUS = 150
NOW = 11.1
assert(Mini:Outdated(), "and a second having passed, whatever else")
Mini.active, Mini.lastUpdate = false, NOW
HERE = { 1, 900, 900 }
assert(not Mini:Outdated(), "while markers are off only the safeguard looks again")

print("Minimap tracking: bank and auction survive the game's write-back, the menu works while not drawing, Uncheck All; markers are gathered again only when out of date")
