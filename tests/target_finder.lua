local root = ...
local function noop() end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local frames = {}
local function frame(_, name, parent)
    local f = { scripts = {}, shown = true, name = name, parent = parent }
    function f:SetScript(kind, fn) self.scripts[kind] = fn end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:SetShown(v) self.shown = v end
    function f:IsShown() return self.shown end
    function f:GetName() return self.name end
    function f:SetText(text) self.text = text end
    function f:GetText() return self.text end
    function f:SetDesaturated(value) self.dim = value end
    function f:CreateTexture() return frame() end
    setmetatable(f, { __index = function(_, k) if k:match("^%u") then return noop end end })
    if name then frames[name] = f end
    return f
end
CreateFrame, UIParent, Minimap, UISpecialFrames = frame, frame(), frame(), {}
GameTooltip = { IsOwned = function() return false end }
MiniQoL = { Theme = { Window = noop, Tip = noop, Chrome = noop, Text = function() return frame() end,
    Color = function() return 1, 1, 1 end,
    CloseButton = function(_, parent, fn) local b = frame(); b.scripts.OnClick = fn; return b end,
    Button = function(_, parent, label, w, h, fn) local b = frame(); b.scripts.OnClick = fn; return b end } }
local events, timers = {}, {}
local ns = { db = {}, Print = noop }
local secret = {}
function ns.Readable(x) return x ~= nil and x ~= secret end
function ns:NewModule(key) self[key] = {}; return self[key] end
function ns:GetCharacterKey() return "Test-Realm" end
function ns:RegisterEvent(event, fn) events[event] = fn end
C_Timer = { After = function(_, fn) timers[#timers+1] = fn end }
local function flush() while #timers > 0 do table.remove(timers, 1)() end end
local units, visible, marks, points, log, markers = {}, {}, {}, {}, {}, {}
local raid = false
local function unit(token, id, name, x, kind)
    units[token] = { guid = (kind or "Creature") .. "-0-1-2-3-" .. id .. "-" .. token, name = name, x = x }
end
function UnitGUID(u) return units[u] and units[u].guid end
function UnitName(u) return units[u] and units[u].name end
function UnitIsDeadOrGhost(u) return units[u].dead == true end
function UnitPosition(u)
    if u == "player" then return 100, 100, 0, 1 end
    if units[u] and units[u].x then return units[u].x, 100, 0, 1 end
end
function UnitDistanceSquared() return 0, false end
function IsInRaid() return raid end
function UnitIsGroupLeader() return false end
function UnitIsGroupAssistant() return false end
function GetRaidTargetIndex(u) return units[u].mark end
function SetRaidTarget(u, n) units[u].mark = n; marks[#marks+1] = u end
C_NamePlate = { GetNamePlates = function() return visible end }
C_Map = { GetBestMapForUnit = function() return 42 end }
function ns.MapToWorld(map, x, y) return 1, x*1000, y*1000 end
ns.Navigation = { SetWaypoint = function(_, c, x, y, name, map) points[#points+1] = {x=x, name=name, map=map} end }
C_VignetteInfo = {
    GetVignettes = function() local keys = {}; for k in pairs(markers) do keys[#keys+1]=k end; return keys end,
    GetVignetteInfo = function(k) return markers[k] end,
    GetVignettePosition = function(k) return markers[k].pos end,
}
C_QuestLog = {
    GetQuestObjectives = function(id) return log[id] end,
    IsComplete = function() return false end,
    GetTitleForQuestID = function() return "Test hunt" end,
}
MiniQoLRuntime = { Execute = function(_, _, fn) return fn("Wayfinder", ns) end }
for _, file in ipairs({ "TargetFinder", "TargetFinderQuests", "TargetFinderUI" }) do
    assert(loadfile(root .. "/Modules/Wayfinder/" .. file .. ".lua"))("Wayfinder", ns)
end
local finder = ns.TargetFinder
finder:OnLogin()
assert(not finder.button:IsShown())
finder:Open()
finder.input:SetText("  Wolf  ")
finder.input.scripts.OnEnterPressed()
finder:Add("wolf")
assert(#finder.db.manual == 1 and finder.button:IsShown() and finder.button.icon.dim)
assert(not finder:Add("Wolf\n/target Player") and not finder:Add("|Hquest:123|h"))
unit("nameplate1", 10, "Wolf", 145)
unit("nameplate2", 10, "Wolf", 106)
unit("nameplate3", 10, "Wolf", 101)
units.nameplate3.dead = true
visible = {{namePlateUnitToken="nameplate1"}, {unitToken="nameplate2"}, {UnitFrame={unit="nameplate3"}}}
finder.button.scripts.OnUpdate(nil, 0.31)
assert(finder.best.unit == "nameplate2" and finder.button.glow:IsShown() and #marks==0)
unit("nameplate2", 12, "Boar", 102) -- recycled between glow and hardware click
finder.button.scripts.OnClick(nil, "LeftButton")
assert(#marks==1 and marks[1]=="nameplate1" and units.nameplate1.mark==8)
finder:Mark()
assert(#marks==1, "repeat clicks preserve the existing mark")
units.nameplate1.mark=nil
raid=true
finder:Mark()
assert(#marks==1 and points[1].x==145, "raid without marking permission gets a waypoint")
raid=false
units.nameplate1.x=172
assert(not finder:Scan() and not finder.button.glow:IsShown(), "distant or dead mobs do not light the icon")
units.nameplate1.guid=secret
assert(not finder:Scan(), "restricted units are ignored")
finder:Add("Ancient Chest")
markers.a = {name="Ancient Chest",objectGUID="GameObject-0-1-2-3-75-1",pos={x=.117,y=.1}}
markers.b = {name="Ancient Chest",objectGUID="GameObject-0-1-2-3-75-2",pos={x=.129,y=.1}}
events.VIGNETTES_UPDATED()
assert(finder:Scan().distance==17^2)
finder:Mark()
assert(points[#points].name=="Ancient Chest" and points[#points].x==117 and #marks==1)
markers={}
unit("softinteract",75,"Ancient Chest",nil,"GameObject")
finder:Mark()
assert(points[#points].name=="Ancient Chest (nearby)" and points[#points].x==100)
units.softinteract=nil
assert(not finder:Scan())

log[101] = {{type="monster",text="Wolf slain: 0/2",finished=false},
    {type="item",text="Pearl: 0/1",finished=false}, {type="monster",text="Rats slain: 2/2",finished=true}}
local questieSources = { {NativeIndex=2, spawnList = {
    {Name="Sand Crab",TooltipKey="m_67"}, {Name="Clam",TooltipKey="o_67"}, {Name="Sand Crab",TooltipKey="m_67"} } } }
QuestieLoader = {_modules={TrackerData={RefreshQuest=function() return {Objectives=questieSources} end}}}
finder:ImportQuest(101)
local group = finder.db.quests[101]
assert(#group.targets==3 and group.targets[1].name=="Clam" and group.targets[2].name=="Sand Crab" and group.targets[3].name=="Wolf")
finder:ImportQuest(101)
assert(#group.targets==3)
unit("nameplate1",81,"Sand Crab",101)
assert(not finder:Scan(), "an unrelated same-name NPC does not match a quest creature ID")
unit("nameplate1",67,"Localized crab",103)
assert(finder:Scan().name=="Sand Crab", "verified creature IDs work across languages")
questieSources[1].Completed=true
log[101][2].finished=true
events.QUEST_LOG_UPDATE(); flush()
assert(#group.targets==1 and group.targets[1].name=="Wolf" and not finder:Scan())
events.QUEST_TURNED_IN(nil,101)
assert(not finder.db.quests[101] and #finder.db.manual==2)

QuestieLoader=nil
log[202]={{type="item",text="Relic: 0/1",finished=false}}
Polestar={QuestDB={GetQuest=function() return {objectives={{kind="item",id=5}}} end,
    GetItem=function() return {droppers={{id=2,name="Watcher"}},objects={{id=3,name="Cache"}},vendors={}} end}}
finder:ImportQuest(202)
assert(#finder.db.quests[202].targets==2)
Polestar=nil
log[303]={{type="monster",text="0/4 Kobold slain",finished=false}}
finder:ImportQuest(303)
assert(finder.db.quests[303].targets[1].name=="Kobold", "native tracker works without either database")
for i=1,9 do finder:Add("Search "..i) end
finder:Open()
assert(finder.next:IsShown())
finder.next.scripts.OnClick()
assert(finder.page==2 and finder.prev:IsShown())
finder.prev.scripts.OnClick()
finder.rows[1].remove.scripts.OnClick()
assert(finder.db.manual[1].name=="Ancient Chest")
assert(ns.db.targetFinder["Test-Realm"]==finder.db)
print("Target Finder: quest imports, popup, nearest live units, marks, object waypoints, range, stale tokens and cleanup passed")
