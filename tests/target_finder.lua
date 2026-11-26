local root = ...
local function noop() end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local frames = {}
local combat, shift, ctrl, alt, focus, forbidden = false, false, false, false, nil, 0
function InCombatLockdown() return combat end
function GetTime() return 100 end
function IsShiftKeyDown() return shift end
function IsControlKeyDown() return ctrl end
function IsAltKeyDown() return alt end
function GetMouseFoci() return {focus} end
local function frame(_, name, parent, template)
    local f = { scripts = {}, attrs = {}, shown = true, name = name, parent = parent, template = template }
    function f:SetScript(kind, fn) self.scripts[kind] = fn end
    function f:GetScript(kind) return self.scripts[kind] end
    function f:RegisterForClicks(...)
        self.clicks={}
        for _,v in ipairs({...}) do self.clicks[v]=true end
    end
    function f:GetParent() return self.parent end
    function f:GetFrameLevel() return 2 end
    function f:SetAttribute(key, value)
        assert(not combat, "protected attributes changed in combat")
        self.attrs[key] = value
    end
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
WorldFrame = frame()
function RegisterStateDriver(f, state, rule)
    assert(not combat and state == "visibility"); f.rule = rule; f.shown = rule ~= "hide"
end
function SecureHandlerSetFrameRef(frame, key, ref)
    assert(not combat); frame[key.."Ref"]=ref
end
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
local raid, party = false, false
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
function IsInGroup() return raid or party end
function UnitIsGroupLeader() return false end
function UnitIsGroupAssistant() return false end
function GetRaidTargetIndex(u) return units[u].mark end
function SetRaidTarget() forbidden = forbidden+1; error("protected call from addon Lua") end
C_NamePlate = { GetNamePlates = function() return visible end, GetNamePlateForUnit = function(u)
    for _, p in ipairs(visible) do
        if (p.namePlateUnitToken or p.unitToken or (p.UnitFrame and p.UnitFrame.unit)) == u then return p end
    end
end }
C_Map = { GetBestMapForUnit = function() return 42 end }
function ns.MapToWorld(map, x, y) return 1, x*1000, y*1000 end
ns.Navigation = { SetWaypoint = function(_, c, x, y, name, map) points[#points+1] = {x=x, name=name, map=map} end }
function ns.Navigation:PlaceSourceWaypoint(source, c, x, y, name, map, options)
    assert(options.focus)
    self.pin = {source=source, x=x, name=name}
    return self.pin
end
function ns.Navigation:GetSourceWaypoint(source) return self.pin and self.pin.source == source and self.pin end
function ns.Navigation:RemoveWaypoint(pin) assert(pin == self.pin); self.pin=nil end
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
for _, file in ipairs({ "TargetFinder", "TargetFinderQuests", "TargetFinderUI", "TargetFinderRows" }) do
    assert(loadfile(root .. "/Modules/Wayfinder/" .. file .. ".lua"))("Wayfinder", ns)
end
local finder = ns.TargetFinder
finder:OnLogin()
-- Model the client's targeting restrictions. Seeing a nameplate token through
-- UnitGUID does not make /target nameplateN legal. /targetexact uses the name.
function TargetUnit() forbidden=forbidden+1; error("insecure targeting") end
local function click(button, mouse, exactResult)
    mouse=mouse or "LeftButton"
    assert(button:IsShown() and button.template:find("SecureActionButtonTemplate",1,true))
    assert(button.clicks[mouse.."Up"])
    button.scripts.PreClick(button,mouse)
    local previous=units.target
    local macro=button.attrs[mouse=="LeftButton" and "macrotext1" or mouse=="RightButton" and "macrotext2" or "macrotext3"] or ""
    for line in macro:gmatch("[^\n]+") do
        local token=line:match("^/target %[@(%w+),exists,nodead%] %1$")
        local exact=line:match("^/targetexact (.+)$")
        local clear=line:match("^/tm %[nocombat,@(%w+),exists%] 0$")
        if token then
            assert(not token:match("^nameplate") and units[token] and not units[token].dead)
            units.target=units[token]
        elseif exact then
            local onlyCombat=exact:match("^%[combat%] (.+)$")
            if not onlyCombat or combat then
                exact=onlyCombat or exact
                if exactResult~=false then
                    local match=exactResult and units[exactResult]
                    if not match then
                        for u,v in pairs(units) do
                            if v.name==exact and not v.dead and (not match or (v.x or math.huge)<(match.x or math.huge)) then match=v end
                        end
                    end
                    if match then assert(match.name==exact); units.target=match end
                end
            end
        elseif line=="/cleartarget" then units.target=nil
        elseif line=="/cleartarget [dead]" or line=="/cleartarget [combat,dead]" then
            if units.target and units.target.dead and (combat or line=="/cleartarget [dead]") then units.target=nil end
        elseif line=="/targetlasttarget [noexists]" then units.target=units.target or previous
        elseif line=="/tm [@target,exists,nodead] ~8" then
            if units.target and not units.target.dead and not units.target.mark then
                for _,u in pairs(units) do if u.mark==8 then u.mark=nil end end
                units.target.mark=8
                marks[#marks+1]=units.target.guid:match("([^-]+)$")
            end
        elseif clear then
            assert(not combat and mouse=="RightButton" and units[clear].mark==8)
            units[clear].mark=nil
        else error("unexpected macro line: "..line) end
    end
    if mouse=="MiddleButton" then
        assert(button.attrs.type3=="untrack")
        local handle={Hide=function() button:Hide() end, GetAttribute=function(_, k) return button.attrs[k] end,
            GetFrameRef=function(_, key)
                local ref=assert(button[key.."Ref"])
                return {GetAttribute=function(_,k) return ref.attrs[k] end,SetAttribute=function(_,k,v) ref.attrs[k]=v end}
            end}
        local run=assert(loadstring(button.attrs._untrack))
        setfenv(run,{self=handle}); run()
    end
    button.scripts.PostClick(button,mouse)
    assert(forbidden==0 and not button.attrs.macrotext2 and button.attrs.macrotext1==button.combatMacro)
end
local function markClick(mouse,exactResult) click(finder.markButton,mouse,exactResult) end
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
visible = {frame(),frame(),frame()}
visible[1].namePlateUnitToken,visible[2].unitToken,visible[3].UnitFrame="nameplate1","nameplate2",{unit="nameplate3"}
finder.button.scripts.OnUpdate(nil, 0.31)
assert(finder.best.unit == "nameplate2" and finder.button.glow:IsShown() and #marks==0)
unit("nameplate2", 12, "Boar", 102) -- recycled between glow and hardware click
markClick()
assert(#marks==1 and marks[1]=="nameplate1" and units.nameplate1.mark==8 and units.target==units.nameplate1)
markClick()
assert(#marks==1, "repeat clicks preserve the existing mark")
units.nameplate1.mark=nil
raid=true
markClick()
assert(#marks==1 and finder.localSkull:IsShown(), "raid without marking permission gets a personal nameplate mark")
combat=true
raid=false
units.nameplate1.x=104
markClick()
assert(#marks==1 and finder.markedUnit=="nameplate1" and finder.localSkull:IsShown(), "combat marks the live nameplate")
unit("nameplate1",10,"Wolf",172)
units.nameplate1.guid=units.nameplate1.guid.."-recycled"
units.target=nil
finder:Scan()
assert(not finder.localSkull:IsShown(), "personal mark clears when the plate recycles")
combat=false
events.PLAYER_REGEN_ENABLED()
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
markClick()
assert(ns.Navigation.pin.name=="Ancient Chest" and ns.Navigation.pin.x==117 and #marks==1)
markers={}
unit("softinteract",75,"Ancient Chest",nil,"GameObject")
markClick()
assert(ns.Navigation.pin.name=="Ancient Chest (nearby)" and ns.Navigation.pin.x==100)
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

finder:Add("  OpErAtOr  ")
unit("nameplate1",81,"Venture Co. Operator",123)
unit("nameplate2",82,"SENIOR OPERATOR",104)
assert(finder:Scan().name=="SENIOR OPERATOR" and finder.best.distance==16, "a partial name matches the nearest live full name")
markClick()
assert(marks[#marks]=="nameplate2")
units.target=nil
finder:Add("winch [")
unit("nameplate2",82,"Winch [East]",104)
assert(finder:Scan().name=="Winch [East]", "punctuation is a literal part of the search")
units.nameplate1, units.nameplate2 = nil, nil
unit("softenemy",81,"Venture Co. Operator")
assert(finder:Scan().name=="Venture Co. Operator", "the client's soft target counts even without a distance")
units.softenemy=nil
unit("mouseover",83,"Tunnel Foreman")
local function gesture(on, release)
    focus=on
    events.GLOBAL_MOUSE_DOWN(nil,"MiddleButton")
    focus=release or on
    events.GLOBAL_MOUSE_UP(nil,"MiddleButton")
end
local count=#finder.db.manual
gesture(WorldFrame)
assert(#finder.db.manual==count, "plain middle click is untouched")
shift=true
gesture(frame("Frame",nil,UIParent)) -- tracker or popup over a mob
gesture(WorldFrame,frame("Frame",nil,UIParent))
assert(#finder.db.manual==count, "UI clicks and cancelled world presses do not add the mouseover")
gesture(WorldFrame)
assert(#finder.db.manual==count+1 and finder.db.manual[count+1].id==83)
assert(finder:Scan().unit=="mouseover", "world mouseover without a distance or nameplate is discoverable")
gesture(WorldFrame)
assert(#finder.db.manual==count+1, "duplicate world clicks are idempotent")
local plate=frame("Frame",nil,WorldFrame)
plate.namePlateUnitToken="nameplate5"
visible={plate}
unit("nameplate5",84,"Excavator",105)
local child=frame("Frame",nil,plate)
gesture(child)
assert(finder.db.manual[count+2].id==84 and finder.db.manual[count+2].name=="Excavator", "nameplate under the cursor wins over stale mouseover")
alt=true
unit("nameplate5",85,"Another Mob",108)
gesture(child)
assert(#finder.db.manual==count+2)
alt=false
units.mouseover.guid="Player-1-abc"
gesture(WorldFrame)
assert(#finder.db.manual==count+2 and forbidden==0, "players are not added")
visible={}
units.mouseover=nil
unit("nameplate7",91,"Tunnel Operator",102)
assert(finder:Scan().name=="Tunnel Operator", "public nameplate units still work when no frames are enumerated")
visible={plate}
units.nameplate7.x=160
local edge=finder:Scan()
assert(edge and edge.unit=="nameplate7", "a partial frame list still finds a watched mob exactly 60 yards away")
units.nameplate7.x=161
assert(not finder:Scan(), "a measurable mob beyond 60 yards stays out even if its token is readable")
local extraPlate=frame()
extraPlate.namePlateUnitToken="nameplate52"
visible[2]=extraPlate
unit("nameplate52",92,"Mill Operator",110)
assert(finder:Scan().unit=="nameplate52", "frame-reported tokens above the numbered scan are included")

local function nameRow(name)
    for _, row in ipairs(finder.nameRows) do
        if row:IsShown() and row.displayName == name then return row end
    end
end
local rowClick=click

units,visible={},{}
for i=1,4 do
    local token="nameplate"..i
    visible[i]=frame(); visible[i].namePlateUnitToken=token
    unit(token,100+i,i==4 and "Senior Operator" or "Tunnel Operator",({148,105,122,101})[i])
end
units.softenemy=units.nameplate2
finder:Scan()
local tunnel,senior=assert(nameRow("Tunnel Operator")),assert(nameRow("Senior Operator"))
assert(tunnel.count.text=="3" and senior.count.text=="1" and not nameRow("OpErAtOr") and not units.target)
party=true
rowClick(tunnel)
assert(units.target==units.nameplate2 and units.target.mark==8, "first click picks the nearest of the chosen name")
rowClick(senior)
assert(units.target==units.nameplate4 and units.target.mark==8)
rowClick(tunnel,"RightButton")
assert(units.target==units.nameplate4 and units.target.mark==8,"unmarking a different name preserves the active skull")
units.party1target=units.nameplate3
rowClick(tunnel)
assert(units.target==units.nameplate3 and units.target.mark==8,"each name remembers its own cycle")
units.target=units.nameplate4
rowClick(tunnel,"RightButton")
assert(not units.nameplate3.mark and units.target==units.nameplate4,"unmark preserves target and watch")
rowClick(tunnel,"LeftButton","nameplate1")
assert(units.target==units.nameplate1)
rowClick(tunnel)
assert(units.target==units.nameplate2,"cycle wraps at the farthest mob")
units.nameplate1.x=110
units.focus=units.nameplate1
rowClick(tunnel)
assert(units.target==units.nameplate1,"cycle uses current distances")
unit("nameplate1",121,"Burrower",101)
units.focus=nil
units.target=nil
units.nameplate2.dead=true
units.nameplate3.mark=4
rowClick(tunnel)
assert(units.target==units.nameplate3 and units.target.mark==4 and not units.nameplate1.mark,"recycled and dead candidates skipped")
rowClick(tunnel,"RightButton")
assert(units.target.mark==4, "another player's mark is preserved")
units.nameplate3.mark=8
rowClick(tunnel); rowClick(tunnel,"RightButton")
assert(units.target.mark==8,"an existing skull on a newly selected mob remains owned by its original marker")
units.nameplate3.mark=nil
combat=true
rowClick(tunnel,"LeftButton","nameplate3")
assert(finder.localSkull:IsShown() and finder.markedGUID==units.nameplate3.guid)
rowClick(tunnel,"RightButton")
assert(not finder.localSkull:IsShown() and units.target==units.nameplate3)
units.target=units.nameplate1
units.nameplate3.dead=true
rowClick(tunnel)
assert(not finder.localSkull:IsShown() and not units.nameplate1.mark,"failed combat acquisition never marks the unrelated target")
combat=false
events.PLAYER_REGEN_ENABLED()
party=false
units.nameplate3.dead=false
finder:Scan()
tunnel=assert(nameRow("Tunnel Operator"))
rowClick(tunnel)
assert(finder.markedGUID==units.nameplate3.guid and not units.nameplate3.mark,"solo click marks the selected nameplate")
combat=true
rowClick(tunnel,"RightButton")
assert(not finder.localSkull:IsShown() and units.target==units.nameplate3,"a solo mark made before a pull clears during the fight")
combat=false
events.PLAYER_REGEN_ENABLED()

markers.a={name="Ancient Chest",objectGUID="GameObject-0-1-2-3-75-1",pos={x=.117,y=.1}}
markers.b={name="Ancient Chest",objectGUID="GameObject-0-1-2-3-75-2",pos={x=.129,y=.1}}
events.VIGNETTES_UPDATED(); finder:Scan()
local chest=assert(nameRow("Ancient Chest"))
local previous=units.target
rowClick(chest)
assert(ns.Navigation.pin.x==117 and units.target==previous)
rowClick(chest)
assert(ns.Navigation.pin.x==129)
markers={}
events.VIGNETTES_UPDATED(); finder:Scan()
chest=assert(nameRow("Ancient Chest"))
rowClick(chest,"RightButton")
assert(not ns.Navigation.pin and units.target==previous and nameRow("Ancient Chest"),"after despawn the dim search still clears its waypoint")
assert(finder.namePages>1)
chest.scripts.OnMouseWheel(chest,-1)
assert(finder.namePage==2 and nameRow("Search 9"))
finder.db.manual, finder.db.quests = {}, {}
finder:Reindex()
for _,row in ipairs(finder.nameRows) do assert(not row:IsShown()) end

units,visible,markers={},{},{}
for i=1,3 do
    local token="nameplate"..i
    visible[i]=frame(); visible[i].namePlateUnitToken=token
    unit(token,200+i,i==1 and "Senior Operator" or "Tunnel Operator",100+i*2)
end
unit("target",700,"Boar",112)
local boar=units.target
finder:Add("operator")
tunnel,senior=assert(nameRow("Tunnel Operator")),assert(nameRow("Senior Operator"))
party=true
rowClick(tunnel,"LeftButton",false); flush()
assert(units.target==boar and not boar.mark and not units.nameplate2.mark and not finder.markedGUID,
    "an unsuccessful nameplate-only lookup restores the old target and draws no skull")
party=false
rowClick(tunnel,"LeftButton","nameplate3")
assert(units.target==units.nameplate3 and finder.markedGUID==units.nameplate3.guid,
    "a different same-name spawn chosen by WoW receives the personal skull")
rowClick(tunnel,"RightButton")
assert(not finder.markedGUID and nameRow("Tunnel Operator"))
-- The unit becomes the client's hard target only after PostClick.
units.target=boar
rowClick(tunnel,"LeftButton",false)
units.target=units.nameplate2
flush()
assert(finder.markedGUID==units.nameplate2.guid)
rowClick(tunnel,"RightButton")
-- Removing a partial-name result also suppresses matching quest entries, while
-- the other result and the quest itself remain tracked across live refreshes.
log[405]={{type="monster",text="Senior Operator slain: 0/4",finished=false}}
finder:ImportQuest(405)
finder:Add("Senior Operator",201)
senior=assert(nameRow("Senior Operator"))
local selected=units.target
combat=true
rowClick(senior,"MiddleButton")
assert(not senior:IsShown() and units.target==selected and not finder.hitsByGUID[units.nameplate1.guid])
assert(not finder.markButton.attrs.macrotext1,"middle click disarms the removed name on the locked icon")
combat=false; events.PLAYER_REGEN_ENABLED()
finder:ResolveQuest(405,finder.db.quests[405],true); finder:Reindex()
assert(#finder.db.manual==1 and finder.db.manual[1].name=="operator" and not nameRow("Senior Operator"))
assert(nameRow("Tunnel Operator") and finder.db.quests[405] and finder.db.quests[405].excluded["mob:senior operator"])
finder:Add("Senior Operator")
assert(nameRow("Senior Operator"),"explicitly tracking a removed name restores it")
rowClick(assert(nameRow("Senior Operator")),"MiddleButton")
finder:ImportQuest(405)
assert(nameRow("Senior Operator"),"manually importing the quest again restores its targets")
units,visible={},{}
finder:Scan()
rowClick(assert(nameRow("operator")),"MiddleButton")
assert(#finder.db.manual==0 and finder.db.quests[405],"middle click on a dim typed search removes the search")
print("Target Finder: confirmed hardware targeting, nameplate-only searches, cycling, right-click clearing, middle-click untracking, combat and quest refresh passed")
