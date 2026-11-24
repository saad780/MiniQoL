-- Mini QoL packaging adapter; upstream source and credits follow.
MiniQoLRuntime:Execute("Gearwise", function(...)
local _, ns = ...
local Effects = { waitingForStorage = {} }
ns.Effects = Effects

local attributes = { strength = "str", agility = "agi", stamina = "sta", intellect = "int", spirit = "spi",
    ["attack power"] = "ap", ["ranged attack power"] = "rap", ["spell power"] = "sp", armor = "armor",
    defense = "defense", health = "health", mana = "mana", ["hit rating"] = "hitRating",
    ["critical strike rating"] = "critRating", ["haste rating"] = "hasteRating" }
local chances = { ["hit"] = "hit", ["get a critical strike"] = "crit", ["dodge"] = "dodge",
    ["parry"] = "parry", ["block attacks with a shield"] = "block" }

-- Match the whole bonus. A class ability or a trigger can also mention a stat.
local function FlatStats(text)
    local value, name = text:match("^%+([%d%.]+) (.+)$")
    if not value then name, value = text:match("^increases (.-) by ([%d%.]+)$") end
    if name then name = name:gsub("^your ", "") end
    value = tonumber(value)
    if value and attributes[name] then return { [attributes[name]] = value } end
    if value and name == "all stats" then return { str=value, agi=value, sta=value, int=value, spi=value } end
    name, value = text:match("^improves your chance to (.-) by ([%d%.]+)%%$")
    if chances[name] then return { [chances[name]] = tonumber(value) } end
    value = text:match("^increases critical strike chance by ([%d%.]+)%%$")
    if value then return { crit = tonumber(value) } end
    name, value = text:match("^improves your (.- rating) by (%d+)$")
    if name and attributes[name] then return { [attributes[name]] = tonumber(value) } end
    value = text:match("^increases damage and healing done by magical spells and effects by up to (%d+)$")
    if value then return { sp = tonumber(value) } end
    value = text:match("^restores (%d+) mana per 5 sec$")
    if value then return { mp5 = tonumber(value) } end
end

local schools = { fire=true, frost=true, arcane=true, shadow=true, holy=true, nature=true, physical=true }
local function WeaponProc(text)
    -- Only a single immediate hit or a single, non-stacking self buff. Mixed
    -- effects, extra attacks, area hits and damage over time need other models.
    if text:find(" and ", 1, true) or text:find(" plus ", 1, true) or text:find(" nearby", 1, true)
        or text:find(" enemies", 1, true) or text:find(" targets", 1, true) or text:find(" up to ", 1, true)
        or text:find(" every ", 1, true) or text:find(" over ", 1, true) or text:find(" against ", 1, true)
        or text:find(" stacks", 1, true) or text:find("stacking", 1, true) or text:find(" if ", 1, true)
        or text:find(" when ", 1, true) or text:find(" undead", 1, true) or text:find("each ", 1, true) then return end
    local chance = tonumber(text:match("^([%d%.]+)%% chance "))
    if chance then text = text:gsub("^[%d%.]+%% chance to ", "") end
    text = text:gsub(" seconds?%.?$", " sec."):gsub("(%d)s%.?$", "%1 sec.")
    local name, amount, seconds = text:match("^increases? (.-) by (%d+) for (%d+) sec%.?$")
    if name then name = name:gsub("^your ", "") end
    if name and attributes[name] then
        return { stat = attributes[name], amount = tonumber(amount), seconds = tonumber(seconds), chance = chance }
    end
    local low, high, school = text:match("(%d+) to (%d+) (%a+) damage%.?$")
    if not low then low, high, school = text:match("(%d+)%s*%-%s*(%d+) (%a+) damage%.?$") end
    if not low then low, school = text:match("(%d+) (%a+) damage%.?$"); high = low end
    if low and schools[school] and not text:find("%%") and not text:find("%d+ sec")
        and not text:find("reduces", 1, true) and not text:find("increases", 1, true) then
        return { damage = (tonumber(low) + tonumber(high)) / 2, chance = chance }
    end
end

local byItem, learned = {}, {}
for setID, members in pairs(ns.setMembers or {}) do
    for _, id in ipairs(members) do byItem[id] = setID end
end

function Effects:Line(item, line)
    local name, worn, total = line:match("^%s*(.-)%s+%((%d+)%s*/%s*(%d+)%)%s*$")
    if name and tonumber(total) > 0 and tonumber(worn) <= tonumber(total) then
        item.setName, item.setSize, item.setWorn, item.memberNames = name, tonumber(total), tonumber(worn), {}
        return true
    end
    local pieces, bonus = line:match("^%s*%((%d+)%)%s*set:%s*(.+)$")
    bonus = bonus or line:match("^%s*set:%s*(.+)$")
    if bonus then
        bonus = bonus:gsub("%.$", "")
        item.bonuses = item.bonuses or {}
        item.bonuses[#item.bonuses+1] = { pieces = tonumber(pieces), text = bonus, stats = FlatStats(bonus) }
        return true
    end
    local effect = line:match("^%s*chance on hit:%s*(.+)$")
    local trigger, chance, action = line:match("^equip: your (.-) have a ([%d%.]+)%% chance to (.+)$")
    if not trigger then chance, trigger, action = line:match("^equip: ([%d%.]+)%% chance on (.-) to (.+)$") end
    local triggerSlot
    if trigger == "melee attacks" or trigger == "melee hit" then triggerSlot = 16
    elseif trigger == "ranged attacks" or trigger == "ranged hit" then triggerSlot = 18 end
    if triggerSlot then effect = action end
    if effect then
        local proc = WeaponProc(effect)
        if proc and triggerSlot then proc.chance, proc.triggerSlot = tonumber(chance), triggerSlot end
        if item.proc then item.proc, item.multipleProcs = nil, true end
        if proc and not item.multipleProcs then item.proc = proc else item.effects = true end
        return true
    end
    if item.memberNames and not item.bonuses and #item.memberNames < item.setSize then
        local member = line:match("^%s*(.-)%s*$")
        if member ~= "" then item.memberNames[#item.memberNames+1] = member end
    end
end

function Effects:Finish(item)
    item.setKey = (ns.Number(item.setID) and item.setID > 0 and item.setID) or byItem[item.id] or (item.bonuses and item.setName)
    if not item.setKey or not item.bonuses then return end
    local known = learned[item.setKey] or {}
    learned[item.setKey] = known
    local tiers = ns.setThresholds and ns.setThresholds[item.setKey]
    local matches = tiers and #tiers == #item.bonuses
    for i, bonus in ipairs(item.bonuses) do
        if bonus.pieces then
            if matches and tiers[i] ~= bonus.pieces then matches = false end
            if known[bonus.text] ~= nil and known[bonus.text] ~= bonus.pieces then known[bonus.text] = false
            else known[bonus.text] = bonus.pieces end
        elseif matches and item.setWorn and tiers[i] > item.setWorn then
            matches = false
        end
    end
    for i, bonus in ipairs(item.bonuses) do
        bonus.pieces = bonus.pieces or (matches and tiers[i]) or known[bonus.text] or nil
    end
end

function Effects:Proc(item, slot, profile)
    local proc = item.proc
    if not proc then return 0 end
    if not proc.triggerSlot and (item.classID ~= 2 or (slot ~= 16 and slot ~= 17 and slot ~= 18)
        or (profile.feral and profile.level >= 10)) then
        return 0, nil, true
    end
    local damageSlot = proc.triggerSlot or (slot == 17 and 16 or slot)
    local data = ns.weaponProcRates and ns.weaponProcRates[item.id]
    local rate, unit, source, cooldown
    if proc.chance and proc.chance > 0 and proc.chance <= 100 then
        rate, unit, source, cooldown = proc.chance, "%", "tooltip", data and data[4] or 0
    elseif data then rate, unit, source, cooldown = unpack(data) end
    local perSecond
    if unit == "PPM" then perSecond = rate / 60
    elseif rate then
        if proc.triggerSlot then
            local speed = proc.triggerSlot == 16 and UnitAttackSpeed or nil
            if proc.triggerSlot == 18 then speed = UnitRangedDamage end
            -- For a proc on armor/jewelry both wielded weapons may trigger it.
            -- A weapon changing those speeds needs a hypothetical attack table.
            if speed and item.classID ~= 2 then
                local ok, main, off = pcall(speed, "player")
                if ok and ns.Number(main) and main > 0 then
                    local swings = 1 / main
                    if proc.triggerSlot == 16 and ns.Number(off) and off > 0 then swings = swings + 1 / off end
                    perSecond = rate / 100 * swings
                end
            end
        elseif item.speed and item.speed > 0 then perSecond = rate / (100 * item.speed) end
    end
    if not perSecond then
        if proc.damage then
            local perPPM = proc.damage / 60
            local weight = ns.Compare:DamageWeight(item, damageSlot, profile)
            return 0, ("%.2f DPS per proc/min (unknown trigger rate)."):format(perPPM), true, perPPM * weight
        end
        return 0, nil, true
    end
    if cooldown > 0 then perSecond = perSecond / (1 + cooldown * perSecond) end
    local assumption = ("%g%s, %s"):format(rate, unit == "%" and "% per landed swing" or " procs/min", source)
    if proc.damage then
        local dps = proc.damage * perSecond
        -- Magic damage per proc does not take the physical off-hand penalty.
        local weight = ns.Compare:DamageWeight(item, damageSlot, profile)
        return dps * weight, ("On hit ~%.2f DPS before mitigation (%s)."):format(dps, assumption)
    end
    -- Poisson refresh model for a single buff. A cooldown longer than the
    -- buff makes overlap impossible and uptime is then simply rate * time.
    local uptime = cooldown >= proc.seconds and math.min(1, perSecond * proc.seconds)
        or 1 - math.exp(-perSecond * proc.seconds)
    local gain = ns.Compare:Score({stats = {[proc.stat] = proc.amount * uptime}}, 1, profile)
    return gain, ("On-hit buff ~%.0f%% uptime, %+.1f score (%s)."):format(100 * uptime, gain, assumption)
end

local function CountSet(worn, key, replaced, candidate)
    local ids, count = {}, 0
    for slot, item in pairs(worn) do
        if item.setKey == key and not (replaced and replaced[slot]) and not ids[item.id] then
            ids[item.id], count = true, count + 1
        end
    end
    if candidate and candidate.setKey == key and not ids[candidate.id] then ids[candidate.id], count = true, count + 1 end
    return count
end

local function CountOwned(key, includeBank)
    local get = C_Item and C_Item.GetItemCount or GetItemCount
    if not get then return end
    local ok, n = pcall(get, key, includeBank)
    if ok and ns.Number(n) then return n end
end

-- Use the player's last complete MiniQoL bank visit, including an empty
-- bank. Syndicator can fill the gap before that first visit.
local function RecordedBank()
    if BankFrame and BankFrame:IsShown() then return end
    local characters = MiniQoL and MiniQoL.Characters
    local current = characters and characters:Current()
    if current and current.bankSeen then return current.bankLinks end
    if Effects.bank then return Effects.bank end
    local api = Syndicator and Syndicator.API
    if not (api and api.GetCurrentCharacter and api.GetCharacter) then return end
    local key = api.GetCurrentCharacter()
    local record = key and api.GetCharacter(key)
    if not record then return end
    local ids = {}
    local function add(slots)
        for _, slot in pairs(slots or {}) do
            if type(slot) == "table" and ns.Number(slot.itemID) then ids[slot.itemID] = ns.Text(slot.itemLink) or true end
        end
    end
    for _, bag in pairs(record.bank or {}) do add(bag) end
    for _, tab in pairs(record.bankTabs or {}) do add(tab.slots) end
    Effects.bank = ids
    return ids
end

local function BagLink(id)
    if not Effects.bagLinks then
        local links = {}
        local container = C_Container
        if container and container.GetContainerNumSlots and container.GetContainerItemLink then
            for bag = 0, NUM_BAG_SLOTS or 4 do
                for slot = 1, container.GetContainerNumSlots(bag) or 0 do
                    local link = ns.Text(container.GetContainerItemLink(bag, slot))
                    local itemID = link and tonumber(link:match("item:(%d+)"))
                    if itemID then links[itemID] = link end
                end
            end
        end
        Effects.bagLinks = links
    end
    return Effects.bagLinks[id]
end

local function Stored(item, worn, alternative, profile)
    local members = ns.setMembers and ns.setMembers[item.setKey] or item.memberNames
    local bags, bank, options, names = 0, 0, {}, {}
    if not members then return bags, bank, options end
    local seen, reserved = {}, { [alternative.slot] = item }
    for slot, other in pairs(worn) do
        seen[other.id], seen[other.name:lower()] = true, true
        if not alternative.replaced[slot] and other.setKey == item.setKey then reserved[slot] = other end
    end
    seen[item.id], seen[item.name:lower()] = true, true
    for _, key in ipairs(members) do
        if not seen[key] then
            seen[key] = true
            local carried = CountOwned(key, false)
            local location
            if carried and carried > 0 then location = "bags"; bags = bags + 1
            elseif (CountOwned(key, true) or 0) > 0 then location = "bank"; bank = bank + 1
            elseif type(key) == "number" and (RecordedBank() or {})[key] then location = "bank, last seen"; bank = bank + 1 end
            if location then
                local link
                if type(key) == "number" then
                    local recorded = location ~= "bags" and RecordedBank()
                    link = (location == "bags" and BagLink(key)) or (recorded and ns.Text(recorded[key])) or "item:" .. key
                else
                    local info = C_Item and C_Item.GetItemInfo or GetItemInfo
                    if info then link = select(2, info(key)) end
                end
                local piece, status
                if link then piece, status = ns.Items:Get(link) end
                if type(key) == "number" then Effects.waitingForStorage[key] = status == "pending" or nil end
                names[#names+1] = (piece and piece.name or tostring(key)) .. " (" .. location .. ")"
                local slot = piece and piece.setKey == item.setKey and not piece.limit and not piece.unique
                    and ns.Compare:ReserveSetSlot(piece, profile, reserved)
                if slot then
                    local old = worn[slot]
                    local option = { name = piece.name, id = piece.id, base = link == "item:" .. piece.id }
                    -- Complex weapons, other lost sets and unmodeled effects
                    -- still get a threshold preview, without a combined score.
                    if slot < 16 and not (piece.effects or piece.proc)
                        and not (old and (old.setKey or old.effects or old.proc)) then
                        option.delta = ns.Compare:Score(piece, slot, profile) - ns.Compare:Score(old, slot, profile)
                    end
                    options[#options+1] = option
                end
            end
        end
    end
    return bags, bank, options, table.concat(names, ", ")
end

local function PlanSwaps(options, needed, value)
    if #options < needed or not value or value <= 0 then return end
    local plan = { value = value }
    table.sort(options, function(a, b)
        if a.delta ~= b.delta then return (a.delta or -math.huge) > (b.delta or -math.huge) end
        return a.id < b.id
    end)
    local names, delta = {}, value
    for i = 1, needed do
        if not options[i].delta then return plan end
        delta = delta + options[i].delta
        names[i] = options[i].name
        plan.base = plan.base or options[i].base
    end
    plan.extraDelta, plan.names = delta, table.concat(names, " + ")
    return plan
end

function Effects:Sets(candidate, alternative, worn, profile, notes)
    local sets, lost, gained, review, plan = {}, 0, 0, false, nil
    for _, old in pairs(alternative.old) do if old.setKey then sets[old.setKey] = old end end
    if candidate.setKey then sets[candidate.setKey] = candidate end
    for key, item in pairs(sets) do
        local before = CountSet(worn, key)
        local after = CountSet(worn, key, alternative.replaced, candidate)
        local title = item.setName or item.name
        notes[#notes+1] = ("%s: %d → %d worn."):format(title, before, after)
        local nextBonus
        for _, bonus in ipairs(item.bonuses or {}) do
            local n = bonus.pieces
            if n and n > after and (not nextBonus or n < nextBonus.pieces) then nextBonus = bonus end
            if before ~= after and not n then review = true end
            if n and (before >= n) ~= (after >= n) then
                local value = bonus.stats and ns.Compare:Score({stats=bonus.stats}, 1, profile)
                if value then
                    if after >= n then gained = gained + value else lost = lost + value end
                else review = true end
                notes[#notes+1] = ("%s %d-piece: %s%s."):format(after >= n and "Gain" or "Lose", n, bonus.text,
                    value and (" (%+.1f score)"):format(after >= n and value or -value) or " (unscored)")
            end
        end
        if not item.bonuses and before ~= after then review = true end
        if key == candidate.setKey and nextBonus then
            local bags, bank, options, names = Stored(candidate, worn, alternative, profile)
            if bags + bank > 0 then
                local value = nextBonus.stats and ns.Compare:Score({stats=nextBonus.stats}, 1, profile)
                local text = ("%d in bags, %d in bank. %d-piece: %s%s."):format(bags, bank, nextBonus.pieces,
                    nextBonus.text, value and (" (%+.1f bonus score before other swaps)"):format(value) or "")
                notes[#notes+1] = text
                notes[#notes+1] = names
                if after > before then
                    -- A tier with multiple bonuses needs all its terms for a net estimate.
                    local combined, complete = 0, true
                    for _, bonus in ipairs(item.bonuses) do
                        if bonus.pieces == nextBonus.pieces then
                            if bonus.stats then combined = combined + ns.Compare:Score({stats=bonus.stats}, 1, profile)
                            else complete = false end
                        end
                    end
                    plan = PlanSwaps(options, nextBonus.pieces - after, combined)
                    if plan and not complete then plan.extraDelta = nil end
                end
            end
        end
    end
    return lost, gained, review, plan
end

end)
