local _, ns = ...
local Compare = { cache = {} }
ns.Compare = Compare

local slots = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
	INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
	INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
	INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_RANGED = { 18 },
	INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 }, INVTYPE_TABARD = { 19 },
}
local hands = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_2HWEAPON = true,
	INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true }
local maxArmor = { WARRIOR = 4, PALADIN = 4, HUNTER = 3, SHAMAN = 3, ROGUE = 2,
	DRUID = 2, PRIEST = 1, MAGE = 1, WARLOCK = 1 }
local weaponTypes = {
	WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
	PALADIN = { 0, 1, 4, 5, 6, 7, 8 }, HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 },
	ROGUE = { 0, 2, 3, 4, 7, 13, 15, 16, 18 }, PRIEST = { 4, 10, 15, 19 },
	SHAMAN = { 0, 1, 4, 5, 10, 13, 15 }, MAGE = { 7, 10, 15, 19 },
	WARLOCK = { 7, 10, 15, 19 }, DRUID = { 4, 5, 6, 10, 13, 15 },
}

function Compare:Clear() wipe(self.cache) end

function Compare:CanEquip(item, profile)
	if item.level > profile.level then return false, "Requires level " .. item.level end
	if item.restriction then return false, item.restriction end
	if item.classID == 4 and item.loc ~= "INVTYPE_CLOAK" then
		local maximum = maxArmor[profile.class] or 1
		if profile.level < 40 and maximum >= 3 then maximum = maximum - 1 end
		if item.subclassID and item.subclassID >= 1 and item.subclassID <= 4 and item.subclassID > maximum then
			return false, "Armor type unavailable to your character"
		end
		if item.subclassID == 6 and profile.class ~= "WARRIOR" and profile.class ~= "PALADIN" and profile.class ~= "SHAMAN" then
			return false, "Your class cannot use shields"
		end
		local relicClass = ({ [7] = "PALADIN", [8] = "DRUID", [9] = "SHAMAN" })[item.subclassID]
		if relicClass and relicClass ~= profile.class then return false, "Relic for another class" end
	elseif item.classID == 2 then
		local allowed = false
		for _, id in ipairs(weaponTypes[profile.class] or {}) do if id == item.subclassID then allowed = true end end
		if not allowed then return false, "Weapon type unavailable to your class" end
	end
	-- Class/profession restrictions and untrained weapon skills are also reflected
	-- in the item's red requirement lines, read from the client's tooltip.
	return true
end

function Compare:Score(item, slot, profile)
	if not item then return 0 end
	local stats, weights, score = item.stats, profile.weights, 0
	for key, weight in pairs(weights) do
		if key ~= "sp" and key ~= "heal" and key ~= "ap" and key ~= "rap" then
			score = score + (stats[key] or 0) * weight
		end
	end
	-- Common spell power and healing values overlap. Healing in Forever also
	-- supplies one third as much damage; credit it once, never as two full bonuses.
	local power = math.max(stats.sp or 0, (stats.heal or 0) / 3)
	local healing = math.max(stats.sp or 0, stats.heal or 0)
	if profile.school then power = power + (stats[profile.school] or 0) end
	if profile.secondarySchool then power = power + (stats[profile.secondarySchool] or 0) * 0.6 end
	score = score + power * (weights.sp or 0) + healing * (weights.heal or 0)
	-- General AP benefits ranged attacks too. The two fields on an item can be
	-- aliases for the same aura, so don't blindly add both for hunters.
	if profile.class == "HUNTER" then score = score + math.max(stats.ap or 0, stats.rap or 0) * (weights.rap or 1)
	else score = score + (stats.ap or 0) * (weights.ap or 0) end
	local dpsWeight = 0
	if slot == 18 then
		dpsWeight = profile.rangedDPS or 0
		if profile.wand and item.subclassID == 19 then
			dpsWeight = profile.level < 20 and 10 or (profile.level < 40 and 5 or 1.5)
		end
	elseif slot == 16 or slot == 17 then
		dpsWeight = (profile.meleeDPS or 0) * (slot == 17 and 0.5 or 1)
	end
	score = score + (stats.dps or 0) * dpsWeight + (stats.bonusArmor or 0) * (weights.armor or 0)
	return score
end

local function Equipped(slot)
	local link = GetInventoryItemLink("player", slot)
	if link then return ns.Items:Get(link) end
	local id = GetInventoryItemID and GetInventoryItemID("player", slot)
	if id then ns.Items:Request(id); return nil, "pending" end
	return nil
end

local function DualWield(profile)
	if CanDualWield then return CanDualWield() end
	if IsPlayerSpell and IsPlayerSpell(674) then return true end
	if IsSpellKnown and IsSpellKnown(674) then return true end
	return profile.class == "ROGUE" and profile.level >= 10
		or ((profile.class == "WARRIOR" or profile.class == "HUNTER") and profile.level >= 20)
end

local function UniqueAllowed(item, replaced, equipped)
	if not item.unique and not item.limit then return true end
	local count = 0
	for slot, other in pairs(equipped) do
		if not replaced[slot] and ((item.unique and item.id == other.id) or (item.limit and item.limit == other.limit)) then
			count = count + 1
		end
	end
	return count < (item.limitMax or 1)
end

local function TotalStats(loadout)
	local stats = {}
	for _, item in pairs(loadout) do
		for key, value in pairs(item.stats) do stats[key] = (stats[key] or 0) + value end
	end
	return stats
end

function Compare:Evaluate(link)
	if self.cache[link] then return self.cache[link] end
	local profile = ns.profile
	if not profile then return { status = "unsupported", reason = "Class data unavailable" } end
	local item, status = ns.Items:Get(link)
	if not item then return { status = status or "pending" } end
	if item.tool then return { status = "irrelevant", reason = "Profession tool", item = item } end
	if not slots[item.loc] and not hands[item.loc] then return { status = "irrelevant" } end
	if item.loc == "INVTYPE_BODY" or item.loc == "INVTYPE_TABARD" then return { status = "irrelevant" } end
	local allowed, reason = self:CanEquip(item, profile)
	if not allowed then return { status = "unusable", reason = reason, item = item } end
	if profile.shield and item.loc == "INVTYPE_2HWEAPON" then
		return { status = "unsupported", reason = "This build uses a shield", item = item }
	end
	local targets = hands[item.loc] and { 16, 17 } or slots[item.loc]
	local equipped = {}
	for _, slot in ipairs(targets) do
		local other, pending = Equipped(slot)
		if pending then return { status = "pending" } end
		equipped[slot] = other
	end
	-- A limit category can span different slots, not just the two ring slots.
	if item.unique or item.limit then
		for slot = 1, 19 do
			if not equipped[slot] then
				local other, pending = Equipped(slot)
				if pending then return { status = "pending" } end
				equipped[slot] = other
			end
		end
	end
	local alternatives = {}
	if hands[item.loc] then
		local mh, oh = equipped[16], equipped[17]
		if item.loc == "INVTYPE_2HWEAPON" then
			alternatives[1] = { slot = 16, replaced = { [16] = true, [17] = true }, old = { [16] = mh, [17] = oh } }
		elseif item.loc == "INVTYPE_SHIELD" or item.loc == "INVTYPE_HOLDABLE" or item.loc == "INVTYPE_WEAPONOFFHAND" then
			if mh and mh.loc == "INVTYPE_2HWEAPON" then
				return { status = "unsupported", reason = "Requires a one-handed main hand", item = item }
			end
			if item.loc == "INVTYPE_WEAPONOFFHAND" and not DualWield(profile) then
				return { status = "unusable", reason = "Dual wield is not available", item = item }
			end
			alternatives[1] = { slot = 17, replaced = { [17] = true }, old = { [17] = oh } }
		else
			alternatives[1] = { slot = 16, replaced = { [16] = true }, old = { [16] = mh } }
			if item.loc == "INVTYPE_WEAPON" and mh and mh.loc ~= "INVTYPE_2HWEAPON" and DualWield(profile) then
				alternatives[2] = { slot = 17, replaced = { [17] = true }, old = { [17] = oh } }
			end
		end
	else
		for _, slot in ipairs(targets) do
			alternatives[#alternatives + 1] = { slot = slot, replaced = { [slot] = true }, old = { [slot] = equipped[slot] } }
		end
	end
	local best
	for _, alternative in ipairs(alternatives) do
		if UniqueAllowed(item, alternative.replaced, equipped) then
			local oldScore = 0
			for slot, old in pairs(alternative.old) do oldScore = oldScore + self:Score(old, slot, profile) end
			local newScore = self:Score(item, alternative.slot, profile)
			local delta = newScore - oldScore
			if not best or delta > best.delta then
				local oldStats = TotalStats(alternative.old)
				local newStats = TotalStats({ item })
				local changes = {}
				for key, value in pairs(newStats) do changes[key] = value - (oldStats[key] or 0) end
				for key, value in pairs(oldStats) do if newStats[key] == nil then changes[key] = -value end end
				local effects = item.effects or (ns.Number(item.setID) and item.setID > 0)
				local oldLinks = {}
				for oldSlot = 1, 19 do
					local old = alternative.old[oldSlot]
					if old then
						oldLinks[#oldLinks + 1] = old.link
						effects = effects or old.effects or (ns.Number(old.setID) and old.setID > 0)
					end
				end
				-- Armor has a small score weight, especially for casters. A real
				-- +1/+2 armor gain still counts; ignore only floating-point noise.
				local threshold = math.max(0.000001, math.abs(oldScore) * 0.000000001)
				best = { status = delta > threshold and "upgrade" or (delta < -threshold and "downgrade" or "equal"),
					item = item, slot = alternative.slot, delta = delta, oldScore = oldScore, newScore = newScore,
					percent = oldScore > 0 and delta / oldScore * 100 or nil, changes = changes,
					oldLinks = oldLinks, effects = effects, empty = #oldLinks == 0 }
			end
		end
	end
	best = best or { status = "unusable", reason = "Unique-equipped limit", item = item }
	self.cache[link] = best
	return best
end

function Compare:Get(link)
	if not ns.Text(link) then return { status = "irrelevant" } end
	local ok, result = pcall(self.Evaluate, self, link)
	if not ok then self.lastError = tostring(result) end
	return ok and result or { status = "pending" }
end
