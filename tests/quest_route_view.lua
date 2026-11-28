-- Packaged addon entry points and the same three projections as the walking trail.
local root = ...
local events, listeners, frames = {}, {}, {}
local combat, ctrl, shift, stitched, square = false, false, false, true, false
local rotation, viewX, now = 0, 0, 0
local wx, wy, instance = 0, 0, 1
local live, clicked, tips = nil, {}, {}
local settings = { zoneMap=true, questRouteOutline=true, questRouteShowSkipped=true, questRouteOpacity=0.8 }
local methods = {}
local function New(kind, parent)
    local obj = setmetatable({kind=kind, parent=parent, children={}, scripts={}, shown=true, level=1,
        width=200, height=200, left=0, top=200}, {__index=methods})
    if parent then parent.children[#parent.children+1] = obj end
    frames[#frames+1] = obj
    return obj
end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:GetFrameLevel() return self.level end
function methods:SetFrameLevel(v) self.level=v end
function methods:GetLeft() return self.left end
function methods:GetTop() return self.top end
function methods:GetEffectiveScale() return 1 end
function methods:IsShown() return self.shown end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:SetShown(v) self.shown=v end
function methods:SetScript(k,v) self.scripts[k]=v end
function methods:CreateTexture() return New("Texture",self) end
function methods:CreateLine() return New("Line",self) end
function methods:CreateFontString() return New("Font",self) end
function methods:SetText(v) self.value=v end
function methods:SetSize(w,h) self.width,self.height=w,h end
function methods:SetPoint(p,relative,anchor,x,y) self.anchor,self.x,self.y=anchor,x,y end
function methods:SetStartPoint(a,relative,x,y) self.ax,self.ay=x,y end
function methods:SetEndPoint(a,relative,x,y) self.bx,self.by=x,y end
function methods:SetColorTexture(r,g,b,a) self.color={r,g,b,a} end
function methods:SetVertexColor(r,g,b) self.color={r,g,b} end
function methods:SetThickness(v) self.weight=v end
function methods:SetPassThroughButtons() assert(not combat, "combat passthrough") end
for _,k in ipairs({"SetAllPoints","SetClipsChildren","EnableMouse","SetTexture","RegisterForClicks","SetTextColor"}) do
    methods[k]=function() end
end
CreateFrame = function(kind, _, parent) return New(kind,parent) end
function InCombatLockdown() return combat end
function IsControlKeyDown() return ctrl end
function IsShiftKeyDown() return shift end
function GetTime() return now end
function UnitPosition() return wx,wy,nil,instance end
function GetPlayerFacing() return rotation end
function GetCVarBool() return true end
function GetMinimapShape() return square and "SQUARE" or "ROUND" end
C_Minimap={GetViewRadius=function() return 100 end}
GameTooltip={
    SetOwner=function(self,pin) self.owner=pin end,
    IsOwned=function(self,pin) return self.owner==pin end,
    SetText=function(_,text) tips={text} end, AddLine=function(_,text) tips[#tips+1]=text end,
    Show=function() end, Hide=function(self) self.owner=nil end,
}
Minimap, WorldMapFrame, BattlefieldMapFrame = New("Map"),New("Map"),New("Map")
for _,map in ipairs({WorldMapFrame,BattlefieldMapFrame}) do map.ScrollContainer=New("Scroll",map) end
function WorldMapFrame:GetCanvasContainer() return self end
local canvas=New("Canvas",BattlefieldMapFrame)
function BattlefieldMapFrame:GetCanvas() return canvas end
function BattlefieldMapFrame:GetMapID() return 2 end
function BattlefieldMapFrame:GetPinFrameLevelsManager() return {maxLevel=24} end
local rect={cont=1,left=100,top=100,width=200,height=200}
local ns={QuestRoute={GetView=function() return live end, Click=function(_,key,action) clicked[#clicked+1]=key.."/"..action end}}
function ns:NewModule(k) self[k]={}; return self[k] end
function ns:GetSetting(k) return settings[k] end
function ns:RegisterEvent(k,fn) events[k]=events[k] or {}; table.insert(events[k],fn) end
function ns:On(k,fn) listeners[k]=listeners[k] or {}; table.insert(listeners[k],fn) end
function ns.Readable(value) return value~=nil end
function ns.GetPlayerWorld() return instance,wx,wy end
function ns.GetMapRect() return rect end
function ns.Guarded(fn) return fn end
ns.Navigation={InArea=function(_,x,y) return x==0 and y==0 end}
local world={IsStitched=function() return stitched end, ViewNow=function() return viewX,0,1 end,
    ViewHalfExtents=function() return 0.1,0.1 end}
ns.ContinuousEngine={GetModule=function() return world end,
    MapStitch={artTop=100,FromYards=function(cont,x,y) return y/1000,x/1000 end}}
EventUtil={ContinueOnAddOnLoaded=function(_,fn) fn() end}
MiniQoLRuntime={Execute=function(_,_,fn) fn("Wayfinder",ns) end}
for _,name in ipairs({"QuestRouteView","AntTrails"}) do
    assert(loadfile(root.."/Modules/Wayfinder/"..name..".lua"))("Wayfinder",ns)
end
ns.QuestRouteView:OnLogin()
ns.AntTrails:OnLogin()
local function fire(list, key, ...)
    for _,fn in ipairs(list[key] or {}) do fn(...) end
end
local map, mini, zone = ns.AntTrails.map.frame.children[1], ns.AntTrails.mini.frame.children[1], ns.AntTrails.zone.frame.children[1]
local function draw(frame) if frame.shown then now=now+0.1; frame.scripts.OnUpdate(frame,0.1) end end
local function shown(objects, kind)
    local result={}
    for _,obj in ipairs(objects) do if obj.kind==kind and obj.shown then result[#result+1]=obj end end
    return result
end
local function pins(frame) return shown(frame.children[1].children,"Button") end
local function lines(frame) return shown(frame.children,"Line") end
local function stop(key,id,kind,x,y)
    return {task={key=key,questID=id,kind=kind,label="Speak to "..key,quest="Quest "..id,progress="1/6"},point={x=x,y=y}}
end
local function update()
    fire(listeners,"QUEST_ROUTE_CHANGED")
    for _,frame in ipairs({map,mini,zone}) do draw(frame) end
end
assert(not map.shown and not mini.shown and not zone.shown)
local a,b,c=stop("one",1,"pickup",40,35),stop("two",2,"objective",42,34),stop("three",1,"turnin",-45,-35)
live={cont=1,mapID=2,origin={x=0,y=0},stops={a,b,c},forced="two",skipped={},
    paths={{{x=0,y=0},{x=5,y=40},{x=40,y=35}}}}
update()
for _,frame in ipairs({map,mini,zone}) do
    local markers,segments=pins(frame),lines(frame)
    assert(#markers==2 and #segments>=3)
    assert(markers[1].text.value=="1!" and markers[2].text.value=="3?")
    assert(markers[1].ring.color[3]==1)
    assert(segments[1].weight==3 and segments[#segments].weight==2)
end
assert(pins(map)[1].x==135 and pins(map)[1].y==-141)
assert(pins(zone)[1].x==66 and pins(zone)[1].y==-59)
assert(pins(mini)[1].x==-34 and pins(mini)[1].y==41)
local first=pins(map)[1]
first.scripts.OnEnter(first)
assert(table.concat(tips," "):find("1/6") and table.concat(tips," "):find("Quest 2"))
first.scripts.OnClick(first); first.scripts.OnClick(first)
assert(clicked[1]=="one/follow" and clicked[2]=="two/follow")
shift=true; first.scripts.OnClick(first); shift=false
assert(clicked[3]=="two/next","shift-click on a group toggles its existing forced stop")
ctrl=true; first.scripts.OnClick(first); ctrl=false
assert(clicked[4]=="one/skip" and clicked[5]=="two/skip")
live.stops,live.skipped,live.paths={c},{a,b},nil
update()
assert(pins(map)[2].text.value=="×")
ctrl=true; pins(map)[2].scripts.OnClick(pins(map)[2]); ctrl=false
assert(clicked[6]=="one/skip" and clicked[7]=="two/skip")
settings.questRouteShowSkipped=false
fire(listeners,"SETTING_CHANGED","questRouteShowSkipped")
draw(map)
assert(#pins(map)==1)
a.point.area={xs={-10,10,10,-10},ys={-10,-10,10,10},c=1}
live.stops,live.skipped={a},{}
update()
assert(#lines(map)==4 and lines(map)[1].color[2]==0.88,"inside the camp the map outlines it")
settings.questRouteOutline=false
settings.questRouteDashed=true
update()
assert(#lines(map)>1 and lines(map)[1].color[2]~=0.88,"leg returns with the dashed style")
live.paths={{}}
update()
assert(#lines(map)==0 and #pins(map)==1,"an unreachable leg keeps its stop without a line through a hostile town")
live.paths=nil
update()
-- Project on a changed viewport even while the route, player and level stay fixed.
viewX=0.04; draw(map)
assert(pins(map)[1].x==95)
rotation=math.pi/2; draw(mini)
assert(pins(mini)[1].x==40 and pins(mini)[1].y==35)
stitched=false; draw(map)
assert(#pins(map)==0 and #lines(map)==0)
rect.cont=2; draw(zone)
assert(#pins(zone)==0 and #lines(zone)==0)
combat=true; fire(events,"PLAYER_REGEN_DISABLED"); update()
assert(not mini.shown and not map.shown and not zone.shown)
local prev=#clicked; first.scripts.OnClick(first); assert(#clicked==prev)
combat=false; stitched=true; rect.cont=1; viewX=0; fire(events,"PLAYER_REGEN_ENABLED"); draw(map)
-- A dense polyline may straddle the entire viewport; no off-screen dashes or unbounded pools.
local path={}
for i=1,9500 do path[i]={x=i%2==0 and 9500 or -9500,y=i%180-90} end
live.paths={path}; live.stops[1].point.x=40000
update()
for _,frame in ipairs({map,mini,zone}) do assert(#lines(frame)<=320) end
for _,line in ipairs(lines(map)) do assert(line.ax>=-0.01 and line.ax<=200.01 and line.bx>=-0.01 and line.bx<=200.01) end
live=nil; update()
assert(not map.shown and not zone.shown and not mini.shown)
print("Quest route view: three map projections, merged clicks, area outline, combat and bounded clipped paths passed")
