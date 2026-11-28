-- Exercise the shipped controller, planner and walking adapter together.
local package = ...
local ns = { db = {questRoutes={}}, Navigation = {}, Background = {}, QuestRouteData = {} }
MiniQoLRuntime = { Execute = function(_, _, fn) fn("Wayfinder", ns) end }
local settings = {questRoute=false, questRouteArrow=true, questRouteWalk=true, questRouteOutline=true,
    questRouteTurnins=true, questRoutePickups=true, questRouteMove=true, questRouteWorth=500, questRouteDry=true}
local timers, ticker, jobs, events, messages, chat = {}, nil, {}, {}, {}, {}
local now, clock = 0, 0
function debugprofilestop() clock=clock+0.04; return clock end
function ns:NewModule(k) self[k]={}; return self[k] end
function ns.Guarded(fn) return fn end
function ns.Readable(v) return v~=nil end
function ns.Distance(x,y,a,b) return ((a-x)^2+(b-y)^2)^0.5 end
function ns:GetSetting(k) return settings[k] end
function ns:SetSetting(k,v) settings[k]=v; self:Fire("SETTING_CHANGED",k,v) end
function ns:GetCharacterKey() return "Birch@12345" end
function ns.Print(s) chat[#chat+1]=s end
local function register(list,k,f) list[k]=list[k] or {}; table.insert(list[k],f) end
function ns:On(k,f) register(messages,k,f) end
function ns:RegisterEvent(k,f) register(events,k,f) end
function ns:Fire(k,...) for _,f in ipairs(messages[k] or {}) do f(...) end end
local function event(k,...) for _,f in ipairs(events[k] or {}) do f(k,...) end end
function ns.Background:Queue(k,f)
    if jobs[k] then return false end
    jobs[k]=coroutine.create(f)
    return true
end
C_Timer = {
    After=function(delay,f) timers[#timers+1]={t=now+delay,f=f} end,
    NewTicker=function(_,f) ticker=f; return {} end,
}
local function advance(seconds)
    local limit=now+seconds
    for turn=1,20000 do
        local nextTime
        for i=#timers,1,-1 do
            local timer=timers[i]
            if timer.t<=now then table.remove(timers,i); timer.f()
            elseif not nextTime or timer.t<nextTime then nextTime=timer.t end
        end
        for k,job in pairs(jobs) do
            local ok,err=coroutine.resume(job); assert(ok,err)
            if coroutine.status(job)=="dead" then jobs[k]=nil end
        end
        if not next(jobs) then
            nextTime=nil
            for _,t in ipairs(timers) do if not nextTime or t.t<nextTime then nextTime=t.t end end
            if not nextTime or nextTime>limit then now=limit; return end
            now=nextTime
        end
    end
    error("route work failed to settle")
end
local map,x,inCombat=17,0,false
function InCombatLockdown() return inCombat end
Enum={UIMapType={Micro=5,Zone=3}}
C_Map={GetMapInfo=function(id) return {mapType=3,name=id==406 and "Stonetalon Mountains" or "The Barrens"} end}
function ns.GetPlayerWorld() return 1,x,0,map end
local pin,focus,places=nil,nil,0
function ns.Navigation:GetWaypoint() return focus end
function ns.Navigation:GetSourceWaypoint(k) assert(k=="route"); return pin end
function ns.Navigation:GetRouteStyle() return "balanced" end
function ns.Navigation:PlaceSourceWaypoint(k,c,wx,wy,label,m,o)
    assert(not inCombat and k=="route" and o.kept and m==406)
    local owned=focus==pin
    pin={source=k,c=c,x=wx,y=wy,n=label}
    if owned or o.focus or not focus then focus=pin end
    places=places+1
    return pin
end
function ns.Navigation:RemoveWaypoint(rec)
    assert(not inCombat and rec==pin)
    pin=nil
    if focus==rec then focus=nil end
    ns:Fire("WAYPOINT_REMOVED",rec)
end
local reads, dropped, ready, waiting, requestedWalks = 0,false,false,false,0
local function t(k,kind,id,wx,after)
    return {key=k,kind=kind,questID=id,quest="Quest "..id,label=kind.." "..id,
        after=after or {},candidates={{x=wx,y=0}}}
end
function ns.QuestRouteData:Invalidate() end
function ns.QuestRouteData:Collect(id,origin,opts,tick)
    reads=reads+1
    if waiting then return nil,"Waiting for Questie" end
    local tasks={t("camp","objective",1,350),t("return","turnin",1,270,{"camp"}),t("near","objective",2,22)}
    if ready then tasks={t("return","turnin",1,270),tasks[3]} end
    if dropped then table.remove(tasks) end
    return {tasks=tasks,activeIDs={[1]=true,[2]=not dropped},towns={},slots=2,why={"A quest outside this zone"}}
end
ns.Walking = { Compat={GetPlayerFaction=function() return "Horde" end},Nav={Path={
    Find=function(_,a,b,cb)
        requestedWalks=requestedWalks+1
        C_Timer.After(0.02,function() cb({a,{x=(a.x+b.x)/2,y=10},b}) end)
        return {}
    end, Cancel=function() end,
}}}
C_QuestLog={IsQuestFlaggedCompleted=function() return false end,IsOnQuest=function(id) return id==1 or not dropped end}
for _,file in ipairs({"QuestRoute","QuestRouteWalking","QuestRouteController"}) do
    assert(loadfile(package.."/Modules/Wayfinder/"..file..".lua"))()
end
local r=ns.QuestRoute
r:OnLogin()
assert(not r:GetView() and not pin)
r:Start(406)
advance(0)
assert(r:Status():find("when you enter") and not r:GetView() and reads==0)
map=406
event("ZONE_CHANGED_NEW_AREA")
advance(3)
local view=r:GetView()
assert(view and #view.stops==3 and view.stops[1].task.key=="near" and pin.routeKey=="near")
assert(requestedWalks>=2 and #view.paths[1]>2 and r:MeasuredPath(pin,0,0))
local before=reads
for i=1,12 do event("QUEST_LOG_UPDATE") end
advance(0.75); assert(reads==before)
advance(0.4); assert(reads==before+1)
r:Click("return","next")
advance(1)
assert(r:GetView().stops[1].task.key=="camp" and r:GetView().stops[2].task.key=="return")
r:Click("near","follow"); assert(pin.questID==2 and focus==pin)
r:Click("near","skip"); advance(1)
assert(#r:GetView().skipped==1 and ns.db.questRoutes["Birch@12345"].skips.near)
r:Click("near","skip"); advance(1)
assert(#r:GetView().skipped==0)
r:Click("near","skip"); advance(1)
dropped=true; event("QUEST_REMOVED",2); advance(2)
assert(not ns.db.questRoutes["Birch@12345"].skips.near)
ready=true; event("QUEST_LOG_UPDATE"); advance(2)
assert(#r:GetView().stops==1 and r:GetView().stops[1].task.key=="return")
before=reads; x=45; ticker(); advance(1); assert(reads==before)
x=155; ticker(); advance(2); assert(reads>before and r:GetView().origin.x==155)
r:Command("why"); assert(chat[#chat]=="A quest outside this zone")
inCombat=true
local calls=places
r:Click("return","follow"); assert(places==calls)
r:Command("off"); advance(0); assert(not r:GetView() and pin)
inCombat=false; event("PLAYER_REGEN_ENABLED"); assert(not pin)
r:Start(406); advance(0)
r:Stop(); advance(3); assert(not r:GetView() and not pin, "a late walking callback resurrected a stopped route")
waiting=true; r:Start(406); advance(1); assert(not r:GetView() and r:Status()=="Waiting for Questie")
waiting=false; ticker(); advance(2); assert(r:GetView())
r:Command("reset"); advance(2); assert(not r:GetView().forced)
print("Zone quest route: arrival handoff, quest changes, movement, walking feedback, safe arrow, actions and cleanup passed")
