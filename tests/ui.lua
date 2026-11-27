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
    "SetAlpha", "StartMoving", "StopMovingOrSizing", "ClearFocus", "SetFocus", "SetFrameLevel", "RegisterForClicks", "SetNormalTexture",
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
assert(loadfile(root .. "/Menus.lua"))("MiniQoL", ns)
assert(loadfile(root .. "/Theme.lua"))("MiniQoL", ns)
ns:Initialize()
for _, file in ipairs({ "Core", "Search", "Upgrades", "Page" }) do
    assert(loadfile(root .. "/Explorer/" .. file .. ".lua"))("MiniQoL", ns)
end
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

-- Exercise both new pages through their slash commands using two zones and
-- multiple sources for the same item and NPC.
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
function GetTime() return 10 end
function UnitFactionGroup() return "Horde" end
local maps = { [1] = { name = "Barrens", mapType = 3 }, [2] = { name = "Durotar", mapType = 3 } }
C_Map = { GetMapInfo = function(id) return maps[id] end, GetBestMapForUnit = function() return 1 end,
    GetPlayerMapPosition = function() return { GetXY = function() return 0.4, 0.4 end } end }
C_QuestLog = { IsQuestFlaggedCompleted = function(id) return id == 77 end }
local pin
Wayfinder.db = {}
Wayfinder.MapToWorld = function(map, x, y) return 1, map * 1000 + x * 300, y * 300 end
Wayfinder.Navigation = { SetWaypointOnMap = function(_, map, x, y, name) pin = { map, x, y, name } end }
ns.Explorer.loaders.npcs = function()
    return { maps = {
        [1] = { { 20, "inn", 0.5, 0.5, "Innkeeper Byula", "Innkeeper", "Horde" },
                { 21, "inn", 0.3, 0.2, "Innkeeper Test", "Innkeeper", "Alliance" } },
        [2] = { { 20, "inn", 0.4, 0.4, "Innkeeper Byula", "Innkeeper", "Horde" } },
    } }
end
ns.Explorer.loaders.gear = function()
    return { items = {
        [123] = { "Local Blade", 57, 60, { { "vendor", 2, 0.5, 0.5, "Remote Vendor" },
            { "quest", 1, 0.3, 0.3, "Done Quest", 58, nil, 77 }, { "drop", 1, 0.6, 0.6, "Local Mob" } } },
        [456] = { "Regional Ring", 58, 62, { { "vendor", 2, 0.5, 0.5, "Remote Vendor" } } },
        [789] = { "Enemy Blade", 57, 60, { { "vendor", 1, 0.5, 0.5, "Enemy Vendor", nil, "Alliance" } } },
    } }
end
SlashCmdList.MINIQOL("find Innkeeper")
local npc = ns.rows["explorer.search.1"]
assert(npc.result.name == "Innkeeper Byula" and npc.result.mapID == 1, "world search prefers local faction matches")
assert(ns.rows["explorer.search.2"].result.mapID == 2 and not ns.rows["explorer.search.3"], "other known spawn maps remain searchable")
npc.waypoint.scripts.OnClick()
assert(pin[1] == 1 and pin[2] == 0.5 and pin[4] == "Innkeeper Byula", "results use Wayfinder's waypoint entry point")
Gearwise = gear
Gearwise.profile = {}
Gearwise.Compare = { Get = function(_, link)
    assert(link ~= "item:789", "excluded faction items must not be scored")
    return { status = "upgrade", slot = link == "item:456" and 12 or 16, percent = 20, delta = 5, item = { icon = 1234 } }
end }
SlashCmdList.MINIQOL("nearby")
while #timers > 0 do table.remove(timers, 1)() end
local nearby = ns.rows["explorer.gear.local.1"].result
assert(nearby.name == "Local Blade" and nearby.source[1] == "drop", "nearby gear retains a viable same-zone source")
assert(ns.rows["explorer.gear.outside.1"].result.slot == 11, "a regional fallback combines equivalent ring slots")

-- An equipped item can also be the missing input for a candidate. Deliver
-- both client item events and check that only the waiting comparison runs.
local calls, equippedReady = {}, false
function GetInventoryItemID(_, slot) if slot == 16 then return 555 end end
local compare = gear.Compare.Get
gear.Compare.Get = function(self, link)
    calls[link] = (calls[link] or 0) + 1
    if link == "item:123" and not equippedReady then return { status = "pending" } end
    return compare(self, link)
end
local function drain() while #timers > 0 do table.remove(timers, 1)() end end
local explorer = ns.Explorer
explorer:CancelUpgrades()
ns:Render()
drain()
assert(explorer.scan.pending[123] and #explorer.scan.nearby == 0)
equippedReady = true
explorer:UpgradeItemArrived(555)
explorer:UpgradeItemArrived(555)
drain()
assert(calls["item:123"] == 2 and calls["item:456"] == 1, "retry pending gear once without rescanning resolved items")
assert(#explorer.scan.nearby == 1 and not next(explorer.scan.pending))
explorer:CancelUpgrades()
ns:Render()
ns:ShowPage("home")
drain()
assert(not explorer.scan and calls["item:123"] == 2, "leaving the page cancels scheduled comparisons")

-- The first local pass saw six uncached pieces. If those resolve before the
-- regional batch, it should publish the six locals without touching remote gear.
local items, loaded, remoteReads = {}, false, 0
for id = 1, 7 do
    items[id] = { "Piece " .. id, 58, 60, { { "drop", id == 7 and 2 or 1, 0.5, 0.5, "Mob" } } }
end
explorer.gear = { items = items }
gear.Compare.Get = function(self, link)
    if link == "item:7" then remoteReads = remoteReads + 1 end
    if not loaded then return { status = "pending" } end
    return compare(self, link)
end
SlashCmdList.MINIQOL("nearby")
table.remove(timers, 1)()
assert(explorer.scan.checkingElsewhere)
loaded = true
for id = 1, 6 do explorer:UpgradeItemArrived(id) end
drain()
assert(remoteReads == 0 and #explorer.scan.nearby == 6, "resolved local gear ends the regional fallback")

local rows, total = explorer:Search("innkeeper", "npc", 1)
assert(#rows == 1 and total == 2 and rows[1].mapID == 1, "result limits preserve the count and nearest result")
function UnitFactionGroup() return "Alliance" end
rows, total = explorer:Search("test innkeeper", "npc", 40)
assert(total == 1 and rows[1].name == "Innkeeper Test", "cached text respects faction and unordered search words")
print("World search ranking, faction filtering, gear comparison and waypoint integration passed")

-- The score stub makes availability and cross-slot ordering independent of
-- stat weights. Gearwise's comparison and tooltip suites exercise the scores.
do
    local level, classID, raceID = 26, 3, 6
    function UnitLevel() return level end
    function UnitClass() return "Hunter", "HUNTER", classID end
    function UnitRace() return "Tauren", "Tauren", raceID end
    function UnitFactionGroup() return "Horde" end
    local function source(id, suggested, group)
        return { "quest", 1, 0.4, 0.5, "Quest", suggested, "Horde", id, 14, {}, group }
    end
    local function drop(zone) return { "drop", zone, 0.5, 0.5, "Mob" } end
    explorer.npcs = { maps = { [1] = { { [8] = {
        { 6129, "Curing the Sick", 14, 14, "Horde", 1024, {}, {}, 32 },
        { 90, "Active", 14, 40, "Horde", 0, {}, {}, 0 },
        { 91, "Chain", 14, 20, "Horde", 0, {}, {}, 0 },
        { 92, "Faction races", 14, 20, "Horde", 0, {}, {}, 178 },
        { 93, "High race bit", 14, 20, "Horde", 0, {}, {}, 2^33 },
        { 94, "Repeatable", 14, 20, "Horde", 0, {}, {}, 0 },
    } } } } }
    explorer.gear = { items = {
        [6469] = { "Venomstrike", 19, 24, { drop(1) } },
        [15866] = { "Veildust Medicine Bag", 0, 15, { source(6129, 14) } },
        [100] = { "Minor gain", 24, 26, { drop(1) } },
        [101] = { "Unlisted item level", 0, 0, { source(90, 40, { 4 }) } },
        [102] = { "Earlier quest", 0, 0, { source(91, 20, { -7 }) } },
        [103] = { "Missing giver record", 0, 0, { source(89, 20) } },
        [104] = { "Alternate drop", 24, 26, { source(6129, 14), drop(2) } },
        [105] = { "Faction quest", 0, 0, { source(92, 20) } },
        [106] = { "Race-specific quest", 0, 0, { source(93, 20) } },
        [107] = { "Repeatable quest", 0, 0, { source(94, 20) } },
    } }
    local log = {
        IsOnQuest = function(id) return id == 90 end,
        IsQuestFlaggedCompleted = function(id) assert(id > 0); return id == 7 or id == 94 end,
        IsRepeatableQuest = function(id) return id == 94 end,
    }
    C_QuestLog = log
    gear.profile = { key = "test", weights = { agi = 1 } }
    gear.Compare.Get = function(_, link)
        local result = { status = "upgrade", slot = 11, delta = 2, percent = 200, item = {} }
        if link == "item:6469" then
            result.delta, result.percent, result.empty, result.effects = 20, nil, true, true
        end
        return result
    end
    local function scan()
        local found = {}
        explorer:CancelUpgrades()
        ns:Render()
        drain()
        for _, group in ipairs({ explorer.scan.nearby, explorer.scan.elsewhere }) do
            for _, item in ipairs(group) do found[item.itemID] = item end
        end
        return found
    end
    local found = scan()
    assert(found[6469] and explorer.scan.nearby[1].itemID == 6469, "an older empty-slot upgrade wins by score gain")
    local row = ns.rows["explorer.gear.local.1"]
    row.scripts.OnEnter(row)
    assert(row.gain:GetText() == "+20.0 score" and tip:find("empty slot") and tip:find("outside the score"))
    assert(not found[15866] and not found[106], "enforce class and race restrictions on the quest")
    assert(found[101] and not found[101].note, "an accepted quest overrides estimated difficulty and prerequisites")
    assert(found[102] and not found[102].note, "check signed group prerequisites by their positive quest ID")
    assert(found[103].note == "Check quest eligibility" and found[107], "qualify missing records and allow repeatables")
    local oldScan = explorer.scan
    gear.profile = { key = "test", weights = { agi = 1 } }
    ns:Render()
    assert(explorer.scan == oldScan, "rebuilding identical weights preserves a scan")
    gear.profile = { key = "test", weights = { agi = 2 } }
    ns:Render()
    assert(explorer.scan ~= oldScan, "changing a weight immediately invalidates ranked results")
    drain()
    classID, raceID = 11, 2
    assert(not scan()[15866], "a druid of the wrong race cannot get this quest reward")
    raceID = 6
    assert(scan()[15866], "the eligible druid still sees it")
    raceID = 34
    found = scan()
    assert(found[105] and found[106], "support high race bits and old faction-wide race masks")
    C_QuestLog = nil
    found = scan()
    assert(found[102].note == "Check quest eligibility", "missing quest APIs leave the result unconfirmed")
    assert(found[104] and found[104].mapID == 2, "an inaccessible quest cannot hide a reachable alternate drop")
    C_QuestLog = log
    local locked = {}
    for id = 1, 7 do locked[id] = { "Locked reward", 0, 0, { source(91, 20, { 8 }) } } end
    locked[7][4][2] = drop(2)
    locked[8] = { "Distant ring", 24, 26, { drop(2) } }
    explorer.gear = { items = locked }
    found = scan()
    assert(#explorer.scan.nearby == 6 and found[1].note == "Earlier quest required")
    assert(found[7] and found[7].mapID == 2 and not found[7].note,
        "six locked sources cannot suppress a usable regional alternate for an older reward")
end
print("Nearby upgrade level coverage, quest eligibility, score ranking and build changes passed")

-- A set possibility or an unknown proc rate must never turn the individual
-- item into a confirmed upgrade, even when the list needs regional fallback.
explorer.gear = {items = {
    [501] = {"Set chest", 25, 26, {{"drop",1,0.3,0.4,"Mob"}}},
    [502] = {"Proc bow", 25, 26, {{"drop",1,0.3,0.4,"Mob"}}},
}}
gear.Compare.Get = function(_, link)
    return { status = "downgrade", slot = 5, item = {}, delta = -5,
        setPlan = link == "item:501" and 10 or nil, breakEven = link == "item:502" and 1.5 or nil,
        effectNotes = {"Example estimate"} }
end
explorer:CancelUpgrades()
ns:Render()
drain()
assert(#explorer.scan.nearby == 0 and #explorer.scan.elsewhere == 0)
assert(ns.rows["explorer.gear.sets.1"].gain:GetText() == "Set option")
local procRow = ns.rows["explorer.gear.procs.1"]
procRow.scripts.OnEnter(procRow)
assert(procRow.gain:GetText() == "1.50/min" and tip:find("Example estimate"))
