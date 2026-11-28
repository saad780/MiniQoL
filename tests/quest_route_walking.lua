local root = ...
local ns, timers = {}, {}
MiniQoLRuntime = { Execute = function(_, _, fn) return fn("Wayfinder", ns) end }
function ns.Distance(x, y, X, Y) return math.sqrt((x-X)^2 + (y-Y)^2) end
function ns:GetSetting(k) return k == "questRouteDry" or k == "questRouteAvoidTowns" end
ns.Navigation = { GetRouteStyle = function() return "balanced" end }
ns.Readable = function(value) return value ~= nil end
C_Timer = { After = function(_, fn) timers[#timers+1] = fn end }
assert(loadfile(root .. "/Modules/Wayfinder/QuestRouteWalking.lua"))("Wayfinder", ns)
local Walker = ns.QuestRouteWalking
local function p(x,y) return { x=x, y=y } end
local function norm(a,b) return ns.Distance(a.x,a.y,b.x,b.y) end
local function pathLength(path)
    local yards = 0
    for i=2,#path do yards = yards + norm(path[i-1],path[i]) end
    return yards
end
local function closest(a,b,c)
    local dx,dy = b.x-a.x,b.y-a.y
    local d2 = dx^2 + dy^2
    local t = d2 > 0 and math.min(1,math.max(0,((c.x-a.x)*dx+(c.y-a.y)*dy)/d2)) or 0
    return norm(p(a.x+t*dx,a.y+t*dy),c)
end
local function avoids(path,towns)
    for i=2,#path do for _, town in ipairs(towns) do
        assert(closest(path[i-1],path[i],town) >= town.radius-0.0001, "leg crossed a hostile town")
    end end
end
local walk = Walker.New(1,2)
local a,b = p(0,0),p(1000,0)
local towns = {{x=400,y=50,radius=100},{x=550,y=-50,radius=100},{x=610,y=149,radius=80}}
walk:SetTowns(towns)
local line = walk:Line(a,b)
assert(#line >= 3 and line[1]==a and line[#line]==b)
avoids(line,towns)
assert(math.abs(pathLength(line)-walk:Estimate(a,b)) < 0.001)
local inside = p(418,64)
local toInside = walk:Line(b,inside)
assert(#toInside >= 2 and toInside[#toInside]==inside, "quest giver inside a town remains reachable")
avoids(toInside,{towns[2],towns[3]})

local requests, callbacks = {}, 0
local function done() callbacks=callbacks+1 end
local engine = { Cancel=function(job) job.cancelled=true end,
    Find=function(cont,from,to,reply,opts)
        assert(cont==1 and opts.style=="balanced")
        local job = {from=from,to=to,reply=reply}
        requests[#requests+1]=job
        return job
    end }
ns.Walking = { Nav={Path=engine},Compat={GetPlayerFaction=function() return "Horde" end} }
local src,dst = p(12,60),p(84,60)
walk:SetTowns({})
local before = walk:Snapshot()
assert(walk:Measure(src,dst,done) and not walk:Measure(src,dst,done))
local job = requests[#requests]
job.reply({src,p(36,100),dst},nil,{})
assert(callbacks == 1 and walk.revision == 1 and not walk.busy)
assert(walk:MeasuredPath(src,dst) and not walk:MeasuredPath(dst,src), "directional measurement")
assert(walk:Estimate(src,dst) > 72 and before:Estimate(src,dst) == 72, "solve snapshot freezes learned costs")
local nearA,nearB=p(15,62),p(86,61)
local adjusted=walk:Line(nearA,nearB)
assert(adjusted[1]==nearA and adjusted[#adjusted]==nearB and #adjusted > #walk:MeasuredPath(src,dst))
assert(math.abs(pathLength(adjusted)-walk:Estimate(nearA,nearB)) < 0.001)
job.reply({src,dst},nil,{})
assert(callbacks == 1, "duplicate callback ignored")
assert(walk:Measure(dst,src,done))
requests[#requests].reply(nil,"unreachable")
assert(walk:Estimate(dst,src) == 3 * norm(dst,src) and not walk:MeasuredPath(dst,src))
engine.Find = function(_,from,to,reply) reply({p(from.x,from.y),p(to.x,to.y)},nil,{}); return {} end
walk:SetTowns(towns)
assert(walk:Measure(a,b,done))
while #timers>0 do table.remove(timers,1)() end
assert(walk:MeasuredPath(a,b) and not walk.job and not walk.busy)
avoids(walk:MeasuredPath(a,b),towns)

-- A router shortcut between two safe points still needs testing against the
-- towns. Reject it and keep the collision-free geometric line.
walk=Walker.New(1,2)
walk:SetTowns(towns)
engine.Find = function(_,from,to,reply) reply({p(400,50),p(to.x,to.y)},nil,{}); return {} end
walk:Measure(a,b,done)
assert(not walk:MeasuredPath(a,b) and walk:Estimate(a,b) >= 3*norm(a,b))
avoids(walk:Line(a,b),towns)

engine.Find = function(_,from,to,reply)
    local j={reply=reply};requests[#requests+1]=j;return j
end
local notices=callbacks
walk:Measure(src,dst,done)
job=requests[#requests]
walk:SetTowns({})
job.reply({src,dst},nil,{})
assert(job.cancelled and callbacks == notices and not walk:MeasuredPath(src,dst), "town change supersedes a pending path")
walk:Measure(src,dst,done)
job=requests[#requests]
walk:Cancel()
job.reply({src,dst},nil,{})
assert(job.cancelled and callbacks == notices and not walk.busy and not walk:Measure(src,dst,done), "stale callbacks after cancellation")
print("Quest route walking: overlapping towns, inside-town targets, directional costs, endpoint bridges, fallback and stale path callbacks passed")
