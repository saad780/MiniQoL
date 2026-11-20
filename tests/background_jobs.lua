-- Background jobs walking a table that changes under them: the minimap's turn-in
-- jobs walk Questie's frames with Entries while Questie adds and removes them.
-- When a change rehashes the table, the walk starts over and passes the keys it
-- has seen. That used to yield inside the iterator, which Lua 5.1 refuses
-- ("attempt to yield across metamethod/C-call boundary") and the job died.
local root = ...

local errors = {}
function geterrorhandler() return function(message) errors[#errors + 1] = tostring(message) end end
function debugprofilestop() return 0 end
local function NewFrame()
    local frame = { scripts = {} }
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    function frame:Show() end
    function frame:Hide() end
    return frame
end
function CreateFrame() return NewFrame() end
MiniQoLRuntime = { Execute = function(_, _, fn) return fn("Wayfinder", ns) end }

ns = { db = { settings = {} } }
function ns:NewModule(name) self[name] = { name = name }; return self[name] end
function ns:GetSetting(key) return self.db.settings[key] end
function ns:On() end
function ns:RegisterEvent() end
ns.Print = print

assert(loadfile(root .. "/Modules/Wayfinder/Background.lua"))("Wayfinder", ns)
assert(loadfile(root .. "/Modules/Wayfinder/MinimapTurnIns.lua"))("Wayfinder", ns)
local Work, Entries = ns.Background, ns.MinimapTurnIns.Entries
assert(type(Entries) == "function", "the walk is reachable")

local function equal(actual, expected, label)
    assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function settle()
    for _ = 1, 10000 do
        if Work:IsIdle() then return end
        Work:Run()
    end
    error("the job never finished")
end

-- A walk where, a few entries in, the entry just visited goes and enough new
-- ones arrive to rehash the table: `next` can't go on from the old key.
local frames, visited, added = {}, {}, {}
for i = 1, 20 do frames["frame" .. i] = i end
local changed = false
Work:Queue("minimap ownership", function()
    local steps = 0
    for name in Entries(frames) do
        visited[#visited + 1] = name
        steps = steps + 1
        if steps == 5 and not changed then
            changed = true
            frames[name] = nil
            for i = 1, 200 do
                local key = "new" .. i
                frames[key], added[key] = i, true
            end
        end
        coroutine.yield()
    end
end)
settle()
equal(#errors, 0, "the job runs to the end: " .. tostring(errors[1]))
assert(changed, "the table changed under the walk")

local count = {}
for _, name in ipairs(visited) do count[name] = (count[name] or 0) + 1 end
for name, times in pairs(count) do equal(times, 1, name .. " is visited once") end
for i = 1, 20 do
    local name = "frame" .. i
    assert(count[name] or frames[name] == nil, name .. " is visited")
end
local seenAdded = 0
for name in pairs(added) do
    if count[name] then seenAdded = seenAdded + 1 end
end
equal(seenAdded, 200, "and so is everything added on the way")

print("Background jobs: a walk over a table that changes mid-way restarts without yielding inside its iterator")
