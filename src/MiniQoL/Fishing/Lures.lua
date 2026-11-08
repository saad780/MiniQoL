local _, ns = ...
-- Lures go on the pole as a temporary enchant, so applying one is a macro:
-- use the lure, then use the main hand.
local Fishing = ns.Fishing

function Fishing:LureMacro(itemID)
    return "/use item:" .. itemID .. "\n/use " .. self.MAIN_HAND_SLOT
end

local USE_TIMEOUT, CHECK_INTERVAL = 10, 0.5
local watching = {}

-- A lure counts as used once one actually leaves the bags, so extra clicks,
-- failed casts and refused replacements are not counted.
function Fishing:WatchLure(itemID)
    if watching[itemID] then return end
    watching[itemID] = true
    local before, checks = self.GetItemCount(itemID), 0
    local ticker
    ticker = C_Timer.NewTicker(CHECK_INTERVAL, function()
        checks = checks + 1
        if self.GetItemCount(itemID) < before then
            local _, link = self.GetItemInfo(itemID)
            self:RecordLureUsed(itemID, link, self.GetItemIcon(itemID))
            self:Fire("CATCHES_CHANGED")
        elseif checks < USE_TIMEOUT / CHECK_INTERVAL then
            return
        end
        watching[itemID] = nil
        ticker:Cancel()
    end)
end

-- The game paints requirements you do not meet in red, which works in any
-- language. When the tooltip cannot be read, assume it is usable.
local function IsRed(color)
    return color and color.r > 0.99 and color.g < 0.2 and color.b < 0.2
end

function Fishing:CanUseLure(itemID)
    local tooltip = C_TooltipInfo and C_TooltipInfo.GetItemByID(itemID)
    for _, line in ipairs(tooltip and tooltip.lines or {}) do
        if line.leftText and IsRed(line.leftColor) then return false end
    end
    return true
end

-- Every lure you are carrying, strongest first.
function Fishing:CarriedLures()
    local carried = {}
    for _, itemID in ipairs(self.LURES) do
        local count = self.GetItemCount(itemID)
        if count > 0 then
            carried[#carried + 1] = { itemID = itemID, count = count, usable = self:CanUseLure(itemID) }
        end
    end
    return carried
end

function Fishing:BestLure()
    for _, itemID in ipairs(self.LURES) do
        if self.GetItemCount(itemID) > 0 and self:CanUseLure(itemID) then return itemID end
    end
end

-- Seconds left on the lure already on the pole, or nil.
function Fishing:LureTimeLeft()
    local hasEnchant, expiration = GetWeaponEnchantInfo()
    if hasEnchant and expiration then return expiration / 1000 end
end
