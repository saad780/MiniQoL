local root = ...
local ns = {}
function ns:NewModule(name) self[name] = {}; return self[name] end
local secret = {}
function ns.Readable(x) return x ~= nil and x ~= secret end
function ns.MapToWorld(map, x, y) return 1, x * 1000, y * 1000 end
function ns.Distance(x, y, xx, yy) return ((xx-x)^2+(yy-y)^2)^0.5 end
MiniQoLRuntime = { Execute=function(_, _, fn) return fn("Wayfinder", ns) end }
assert(loadfile(root .. "/Modules/Wayfinder/QuestWaypoints.lua"))("Wayfinder", ns)
assert(loadfile(root .. "/Modules/Wayfinder/QuestRouteData.lua"))("Wayfinder", ns)
local data = ns.QuestRouteData
local opts = {pickups=true, turnins=true, avoidTowns=true, levelWindow="range", levelBelow=4, levelAbove=4}
local origin = {cont=1,x=0,y=0}
assert(data:Collect(106, origin, opts) == nil)
local function where(x, area) return {[area or 6]={{x,20}}} end
local npcs = {
	[1]={name="Guide", spawns=where(10)}, [2]={name="Cook", spawns=where(20)},
	[3]={name="Foreign mayor", spawns=where(3), friendlyToFaction="H"},
	[4]={name="Border agent", spawns=where(80,9)},
	[5]={name="Hostile flight master", spawns=where(5), friendlyToFaction="H"},
	[6]={name="Banker",spawns=where(40),friendlyToFaction="A"},
	[7]={name="Wolves",spawns={[6]={{5,10,7},{30,30},{30.2,30},{30.4,30}},[9]={{90,1}}}}
}
local objects = {[5]={name="Fallen branch",spawns=where(34)}}
local function get(rows) return function(id,k) return rows[id] and rows[id][k] end end
local quests, active, available = {}, {}, {}
local function quest(id, name, targets, pickup)
	local q = { Id=id, name=name, questLevel=19, zoneOrSort=6, startedBy={{1}},
		Finisher={NPC={3,2}}, ObjectiveData=targets or {}, SpecialObjectives={} }
	quests[id]=q
	if pickup then available[id]=true else active[id]={quest=q} end
	return q
end
local here = {Type="monster", Id=7, Text="Kill wolves"}
local there = {Type="monster", Id=4, Text="Speak with the border agent"}
local gather = {Type="item", Id=6, Text="Gather branches"}
local log = quest(81, "Wolves at the gate", {here, gather})
log.Objectives={
	{NativeIndex=1,Description="Wolves",Collected=1,Needed=7,Completed=false,
		spawnList={{Name="Wolf",Spawns=npcs[7].spawns}}},
	{NativeIndex=2,Description="Branches",Collected=2,Needed=2,Completed=true}
}
local partly = quest(82,"Border troubles",{here,there})
partly.Objectives={{NativeIndex=1,Needed=2},{NativeIndex=2,Needed=1}}
local ready = quest(83,"Already complete"); ready.isComplete=true
local completeMarker = {questID=83,x=0.51,y=0.4}
local localQuest = quest(90,"Gather in the valley",{gather},true)
localQuest.startedBy={nil,{5}}
local external = quest(91,"Cross-zone chain",{here,there},true)
local expert = quest(92,"Seasoned smith",{},true); expert.requiredSkill={164,100}
local high = quest(93,"Hard road",{},true); high.questLevel=33
local phase = quest(94,"Phased quest",{{Type="event",Coordinates={[6]={{10,15,7},{-1,-1}}}}},true)
local distant = quest(95,"Distant giver",{},true); distant.startedBy={{4}}
local gated = quest(96,"Unavailable",{},true)
local other = quest(97,"Other finisher",{here},true); other.Finisher={NPC={4}}
local hints = quest(98,"Hidden lever",{{Type="spell",Id=123}},true)
hints.SpecialObjectives={{RealObjectiveIndex=1,spawnList={{Name="Lever",Spawns=where(16)}}}}
local itemStarter = quest(99,"Read the note",{},true); itemStarter.startedBy={[3]={6}}
local tradeCategory = quest(100,"Trade commission",{},true); tradeCategory.zoneOrSort=-121
C_QuestLog={
	IsComplete=function(id) return id==83 end,
	GetQuestsOnMap=function() return {completeMarker, {questID=secret,x=0,y=0}} end,
	GetNumQuestLogEntries=function() return 24,10 end, GetMaxNumQuestsCanAccept=function() return 15 end
}
local db = {QueryNPCSingle=get(npcs),QueryObjectSingle=get(objects),QueryQuestSingle=get(quests),
	GetQuest=function(id) return quests[id] end, QuestPointers=quests,
	IsDoable=function(id) return id~=96 end,IsFriendlyToPlayer=function(f) return f~="H" end,
	GetItem=function() return {Sources={{Type="object",Id=5}}} end}
local service = {townsfolk={Innkeeper={3},["Flight Master"]={5},Banker={6},Auctioneer={}}}
local m={QuestieDB=db,ActiveQuests={GetAll=function() return active end},AvailableQuests={__availableQuests=available},
	QuestiePlayer={GetPlayerLevel=function() return 20 end, faction="Alliance"},
	Phasing={IsSpawnVisible=function(p) return p~=7 end},Townsfolk=service,
	ZoneDB={GetUiMapIdByAreaId=function(_,a) return a+100 end,GetAreaIdByUiMapId=function(_,a) return a-100 end},
	TrackerMapEligibility={RefreshAndGetCapabilities=function(id) return quests[id] end},
	QuestieProfessions={HasProfessionAndSkillLevel=function() return false,false end,
		professionKeys={BLACKSMITHING=164}, GetSortIdByProfessionId=function() return -121 end}}
QuestieLoader={_modules=m}; Questie={API={isReady=true}}
local calls=0
local original=ns.QuestWaypoints.Camps
ns.QuestWaypoints.Camps=function(...) calls=calls+1; return original(...) end
local ticks=0
local function collect()
	local report=assert(data:Collect(106,origin,opts,function() ticks=ticks+1 end))
	local rows={}
	for _,t in ipairs(report.tasks) do
		assert(not rows[t.key] and #t.candidates>0)
		rows[t.key]=t
	end
	return report,rows
end
local r,rows=collect()
assert(r.slots==5 and r.activeIDs[81] and r.availableIDs[95] and r.levels=="19")
assert(#r.towns==1 and r.towns[1].radius>=100 and ticks>0)
assert(rows["81:o1:106"].progress=="1/7" and not rows["81:o2:106"])
assert(rows["81:end:106"].after[1]=="81:o1:106" and rows["81:end:106"].candidates[1].name=="Cook")
assert(rows["81:o1:106"].candidates[1].x>=300 and rows["81:o1:106"].candidates[1].area)
assert(rows["82:o1:106"] and not rows["82:end:106"] and rows["83:end:106"].candidates[1].name=="Cook")
assert(rows["90:o1:106"].after[1]=="90:start:106" and rows["90:end:106"].after[1]=="90:o1:106")
assert(rows["99:start:106"].candidates[1].name=="Fallen branch")
assert(rows["91:start:106"] and not rows["91:o1:106"] and not rows["91:end:106"])
assert(rows["94:start:106"] and not rows["94:end:106"])
assert(not rows["92:start:106"] and not rows["93:start:106"] and not rows["95:start:106"] and not rows["96:start:106"])
assert(not rows["100:start:106"], "a profession category can identify the required trade without a skill pair")
assert(rows["97:start:106"] and not rows["97:o1:106"] and rows["98:o1:106"])
local why=table.concat(r.why," ")
assert(why:find("Border troubles") and why:find("required profession") and why:find("level window"))
local before=calls
log.Objectives[1].Collected=4
origin.x=250
r,rows=collect()
assert(rows["81:o1:106"].progress=="4/7" and calls==before, "reuse static camp geometry during movement and progress")
log.Objectives[1].Description=secret; log.Objectives[1].Collected=secret
data:Invalidate(81)
r,rows=collect()
assert(calls>before and not rows["81:o1:106"].progress and rows["81:o1:106"].label=="Kill wolves")
opts.pickups,opts.turnins=false,false
r,rows=collect()
assert(not rows["90:start:106"] and not rows["83:end:106"] and rows["81:o1:106"])
print("Quest route data: local camps, progress, outside work, special objectives, real log slots, filters and hostile towns passed")
