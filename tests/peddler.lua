-- Peddler's marks belong to the character that made them. A character it has
-- not seen before starts with nothing marked -- junk included -- and each
-- character's own choice of the junk rule is kept.
local peddlerDir = ...

local function noop() end
local function Frame()
    local f = { handlers = {} }
    function f:SetScript(key, fn) self.handlers[key] = fn end
    f.RegisterEvent, f.UnregisterEvent, f.HookScript = noop, noop, noop
    return f
end
local frames = {}
function CreateFrame()
    local f = Frame()
    frames[#frames + 1] = f
    return f
end
UIParent = Frame()
QuestInfoRewardsFrame, MapQuestInfoRewardsFrame = Frame(), Frame()
ContainerFrameItemButtonMixin = { OnModifiedClick = noop }
function hooksecurefunc() end
function UnitClass() return "Warrior", "WARRIOR" end
function IsAddOnLoaded() return false end
C_Timer = { After = noop }
function strsplit(sep, text)
    local parts = {}
    for part in (text .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do parts[#parts + 1] = part end
    return unpack(parts)
end

-- id -> quality, type, sub-type; every item has a vendor price.
local ITEMS = {
    [3300] = { 0, "Miscellaneous", "Junk" },   -- a grey vendor-trash item
    [4540] = { 1, "Consumable", "Food & Drink" },
}
function GetItemInfo(id)
    local item = ITEMS[id]
    return "Item", "link", item[1], 1, 1, item[2], item[3], 20, "", 1, 25
end

-- Log a character in: its saved variables, then Peddler loading as the game
-- would load it inside the bundle.
local function Login(saved)
    ItemsToSell, UnmarkedItems, AutoSellGreyItems = saved.ItemsToSell, saved.UnmarkedItems, saved.AutoSellGreyItems
    frames = {}
    local ns = {}
    MiniQoLRuntime = { Execute = function(_, name, chunk) return chunk(name, ns) end }
    assert(loadfile(peddlerDir .. "/vo/WantedItems.lua"))("Peddler", ns)
    assert(loadfile(peddlerDir .. "/Peddler.lua"))("Peddler", ns)
    for _, f in ipairs(frames) do
        if f.handlers.OnEvent then f.handlers.OnEvent(f, "ADDON_LOADED", "Peddler") end
    end
    return function(id) return ns.itemIsToBeSold(id, id, false) and true or false end
end

-- A brand-new character: nothing saved yet.
local sells = Login({})
assert(type(ItemsToSell) == "table" and next(ItemsToSell) == nil, "a new character has no marks")
assert(not AutoSellGreyItems, "a new character does not mark junk on its own")
assert(not sells(3300), "so its grey items carry no coin")
assert(not sells(4540), "nor anything else")

-- A character that turned the junk rule on, and marked bread by hand.
sells = Login({ ItemsToSell = { [4540] = 1 }, UnmarkedItems = {}, AutoSellGreyItems = true })
assert(AutoSellGreyItems == true, "a character's own junk rule is kept")
assert(sells(3300) and sells(4540), "its junk and its hand-marked bread are for sale")

-- A character that turned the junk rule off stays off.
sells = Login({ ItemsToSell = {}, UnmarkedItems = {}, AutoSellGreyItems = false })
assert(AutoSellGreyItems == false and not sells(3300), "turning the rule off sticks")

-- Marking the bags. Each bag that changes raises its own event, and each used
-- to queue its own pass over every slot; a burst is now one pass, a second
-- after the last of it.
local passes, slots, timers = 0, {}, {}
function ContainerFrameUtil_EnumerateContainerFrames()
    passes = passes + 1
    local container = { IsShown = function() return true end }
    function container:EnumerateValidItems()
        return ipairs({ {
            GetBagID = function() return 0 end, GetID = function() return 1 end,
            CreateTexture = function() return { SetTexture = noop, SetSize = noop, SetPoint = noop, Show = noop } end,
        } })
    end
    return ipairs({ container })
end
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
-- The slot is asked about through one reused location, not a new object.
local made = 0
ItemLocation = { CreateEmpty = function()
    made = made + 1
    return { SetBagAndSlot = function(self, bag, slot) self.bag, self.slot = bag, slot end }
end }
C_Item = {
    DoesItemExist = function(location) slots[#slots + 1] = location.bag .. ":" .. location.slot; return true end,
    IsBound = function() return false end,
}
C_Container = {
    GetContainerItemInfo = function() return { itemID = 4540, stackCount = 1 } end,
    GetContainerItemLink = function() return "|cffffffff|Hitem:4540::::::::|h[Bread]|h|r" end,
}
sells = Login({ ItemsToSell = { [4540] = 1 }, UnmarkedItems = {} })
local listener
for _, f in ipairs(frames) do if f.handlers.OnEvent then listener = f end end
passes, slots = 0, {}
for _ = 1, 5 do listener.handlers.OnEvent(listener, "BAG_UPDATE", 0) end
assert(passes == 0, "nothing is marked inside the events")
local due = timers
timers = {}
for _, fn in ipairs(due) do fn() end
assert(passes == 1, "five bag updates are one marking pass: " .. passes)
assert(#slots == 1 and slots[1] == "0:1", "which asked about the slot it was shown")
assert(made == 1, "through the one location Peddler keeps: " .. made)

print("Peddler: new characters start unmarked, each keeps its own junk rule, a burst of bag updates is one pass")
