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

print("Peddler: new characters start unmarked and each keeps its own junk rule passed")
