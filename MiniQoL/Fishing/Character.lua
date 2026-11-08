local _, ns = ...
-- What you are holding and how good you are at fishing: the pole, the skill and
-- where it comes from, the buffs, and the best food in your bags.
local Fishing = ns.Fishing

local WEAPON_CLASS, POLE_SUBCLASS = 2, 20

function Fishing:HasPole()
    local itemID = GetInventoryItemID("player", self.MAIN_HAND_SLOT)
    if not itemID then return false end
    local _, _, _, _, _, classID, subclassID = self.GetItemInfoInstant(itemID)
    return classID == WEAPON_CLASS and subclassID == POLE_SUBCLASS
end

function Fishing:IsPoleItem(itemID)
    if not itemID then return false end
    local _, _, _, _, _, classID, subclassID = self.GetItemInfoInstant(itemID)
    return classID == WEAPON_CLASS and subclassID == POLE_SUBCLASS
end

-- The trained rank, plus the temporary bonus which in practice is the lure.
local function RankAndLure()
    if GetProfessions then
        local fishing = select(4, GetProfessions()) -- the fourth profession slot
        if fishing then
            local _, _, rank, _, _, _, _, modifier = GetProfessionInfo(fishing)
            return rank, modifier or 0
        end
    elseif GetNumSkillLines then
        for index = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, modifier = GetSkillLineInfo(index)
            if not isHeader and name == Fishing:SpellName() then return rank, modifier end
        end
    end
end

-- "Increased Fishing +3" -> 3
local function FishingNumber(line)
    return tonumber(line and line:match("[Ff]ishing[^%d]-(%d+)"))
end

-- Everything worn: "Equip: Increased Fishing +3" lines and fishing enchants.
local function GearBonus()
    if not C_TooltipInfo then return 0 end
    local total = 0
    for slot = Fishing.FIRST_SLOT, Fishing.LAST_SLOT do
        local tooltip = C_TooltipInfo.GetInventoryItem("player", slot)
        for _, line in ipairs(tooltip and tooltip.lines or {}) do
            local text = line.leftText
            -- "Requires Fishing (1)" is a requirement, not a bonus.
            if text and (text:match("^Equip:") or text:match("[Ff]ishing %+%d")) then
                total = total + (FishingNumber(text) or 0)
            end
        end
    end
    return total
end

-- Stricter, so "Uncommon Fishing" and similar are not counted as a skill bonus.
local function SkillNumber(line)
    return tonumber(line and line:match("[Ff]ishing [Ss]kill[^%d]-(%d+)"))
end

local function ScanBuffs()
    local total, expires, others = 0, nil, {}
    for index = 1, 40 do
        local aura = C_UnitAuras.GetBuffDataByIndex("player", index)
        if not aura then break end
        local tooltip = C_TooltipInfo.GetUnitBuffByAuraInstanceID("player", aura.auraInstanceID)
        local bonus
        for _, line in ipairs(tooltip and tooltip.lines or {}) do
            bonus = SkillNumber(line.leftText)
            if bonus then break end
        end
        local auraExpires = aura.expirationTime and aura.expirationTime > 0 and aura.expirationTime or nil
        if bonus then
            total = total + bonus
            if auraExpires then expires = math.max(expires or 0, auraExpires) end
        elseif aura.name and aura.name:find("Fishing") then
            table.insert(others, { name = aura.name, icon = aura.icon, expires = auraExpires })
        end
    end
    return total, expires, others
end

-- Buffs cannot be read in combat, so the last good reading is kept.
local lastBonus, lastExpires, lastOthers = 0, nil, {}

local function BuffBonus()
    if not (C_UnitAuras and C_TooltipInfo) or InCombatLockdown() then return lastBonus end
    local ok, bonus, expires, others = pcall(ScanBuffs)
    if ok then lastBonus, lastExpires, lastOthers = bonus, expires, others end
    return lastBonus
end

-- { rank, lure, gear, buffs, total }, or nil when Fishing is not trained.
function Fishing:Skill()
    local rank, lure = RankAndLure()
    if not rank then return nil end
    local skill = { rank = rank, lure = lure or 0, gear = GearBonus(), buffs = BuffBonus() }
    skill.total = skill.rank + skill.lure + skill.gear + skill.buffs
    return skill
end

-- A fishing buff that does not raise the skill, such as "Uncommon Fishing".
function Fishing:OtherBuff()
    local buff = lastOthers[1]
    if not buff then return nil end
    local timeLeft = buff.expires and buff.expires - GetTime()
    if timeLeft and timeLeft <= 0 then return nil end
    return { name = buff.name, icon = buff.icon, timeLeft = timeLeft }
end

function Fishing:FoodTimeLeft()
    local left = lastExpires and lastExpires - GetTime()
    return left and left > 0 and left or nil
end

function Fishing:BestFood()
    for _, itemID in ipairs(self.FOODS) do
        if self.GetItemCount(itemID) > 0 then return itemID end
    end
end
