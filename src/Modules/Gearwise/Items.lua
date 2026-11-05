local _, ns = ...
local Items = { cache = {}, requested = {} }
ns.Items = Items

local professionTools = {
	[2901] = true, -- Mining Pick
	[5956] = true, -- Blacksmith Hammer
	[6219] = true, -- Arclight Spanner
	[7005] = true, -- Skinning Knife
}

local aliases = {
	ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STAMINA_SHORT = "sta",
	ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi", ITEM_MOD_HEALTH_SHORT = "health",
	ITEM_MOD_MANA_SHORT = "mana", ITEM_MOD_ATTACK_POWER_SHORT = "ap", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap",
	ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "feralAP", ITEM_MOD_SPELL_POWER_SHORT = "sp",
	ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "sp", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal",
	ITEM_MOD_MANA_REGENERATION_SHORT = "mp5", ITEM_MOD_HEALTH_REGENERATION_SHORT = "hp5",
	ITEM_MOD_ARMOR_SHORT = "armor", RESISTANCE0_NAME = "armor", ITEM_MOD_EXTRA_ARMOR_SHORT = "bonusArmor",
	ITEM_MOD_ARMOR_MODIFIER_SHORT = "bonusArmor",
	ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps", ITEM_MOD_BLOCK_VALUE_SHORT = "blockValue",
	RESISTANCE1_NAME = "holyResist", RESISTANCE2_NAME = "fireResist", RESISTANCE3_NAME = "natureResist",
	RESISTANCE4_NAME = "frostResist", RESISTANCE5_NAME = "shadowResist", RESISTANCE6_NAME = "arcaneResist",
	ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "defense", ITEM_MOD_CRIT_RATING_SHORT = "critRating",
	ITEM_MOD_CRIT_MELEE_RATING_SHORT = "critRating", ITEM_MOD_CRIT_RANGED_RATING_SHORT = "critRating",
	ITEM_MOD_CRIT_SPELL_RATING_SHORT = "critRating", ITEM_MOD_SPELL_CRIT_RATING_SHORT = "critRating",
	ITEM_MOD_HIT_RATING_SHORT = "hitRating", ITEM_MOD_HIT_MELEE_RATING_SHORT = "hitRating",
	ITEM_MOD_HIT_RANGED_RATING_SHORT = "hitRating", ITEM_MOD_HIT_SPELL_RATING_SHORT = "hitRating",
	ITEM_MOD_SPELL_HIT_RATING_SHORT = "hitRating", ITEM_MOD_SPELL_HASTE_RATING_SHORT = "hasteRating",
	ITEM_MOD_HASTE_RATING_SHORT = "hasteRating", ITEM_MOD_HASTE_SPELL_RATING_SHORT = "hasteRating",
	ITEM_MOD_EXPERTISE_RATING_SHORT = "expertiseRating", ITEM_MOD_DODGE_RATING_SHORT = "dodgeRating",
	ITEM_MOD_PARRY_RATING_SHORT = "parryRating", ITEM_MOD_BLOCK_RATING_SHORT = "blockRating",
}
for _, school in ipairs({ "FIRE", "FROST", "SHADOW", "NATURE", "ARCANE", "HOLY" }) do
	aliases["ITEM_MOD_" .. school .. "_DAMAGE_SHORT"] = school:lower()
end

local names = { strength = "str", agility = "agi", stamina = "sta", intellect = "int", spirit = "spi",
	["attack power"] = "ap", ["ranged attack power"] = "rap", ["spell power"] = "sp",
	["spell damage"] = "sp", ["spell damage and healing"] = "sp", healing = "heal",
	["healing spells"] = "heal", armor = "armor", health = "health", mana = "mana" }
for _, school in ipairs({ "fire", "frost", "shadow", "nature", "arcane", "holy" }) do
	names[school .. " damage"], names[school .. " spell damage"] = school, school
	names[school .. " resistance"] = school .. "Resist"
end
for key, stat in pairs(aliases) do
	local localized = _G[key]
	if ns.Text(localized) and not localized:find("%%") then names[localized:lower()] = stat end
end

local function Clean(text)
	return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
		:gsub("|A.-|a", ""):gsub("\194\160", " "):lower()
end

local function Add(stats, key, value)
	if key and ns.Number(value) then stats[key] = (stats[key] or 0) + value end
end

local function ParseLine(text, out, item)
	if not ns.Text(text) then return end
	local line = Clean(text)
	if line:find("unique%-equipped") then item.unique = true end
	if line:match("^use:") or line:match("^chance on hit:") or line:find("set:", 1, true)
		or line:match("^%(%d+%) set") then item.effects = true; return end
	local dps = tonumber(line:match("%(([%d%.]+) damage per second%)"))
	if dps then out.dps = dps; return end
	local low, high = line:match("^([%d%.]+)%s*%-%s*([%d%.]+)%s+damage$")
	if low and high then
		item.minDamage, item.maxDamage = tonumber(low), tonumber(high)
		return
	end
	local amount, name = line:match("^%+?([%d%.]+)%s+(.+)$")
	if amount and names[name] then Add(out, names[name], tonumber(amount)); return end
	local all = tonumber(line:match("^%+(%d+) all stats$"))
	if all then for _, key in ipairs({ "str", "agi", "sta", "int", "spi" }) do Add(out, key, all) end; return end
	local value = tonumber(line:match("([%d%.]+)%%")) or tonumber(line:match("by up to ([%d%.]+)"))
		or tonumber(line:match("by ([%d%.]+)")) or tonumber(line:match("^%+([%d%.]+)"))
	if not value then
		local regen = tonumber(line:match("restores ([%d%.]+) mana per 5")) or tonumber(line:match("restores ([%d%.]+) mana every 5"))
		if regen then Add(out, "mp5", regen); return end
		regen = tonumber(line:match("restores ([%d%.]+) health per 5")) or tonumber(line:match("restores ([%d%.]+) health every 5"))
		if regen then Add(out, "hp5", regen); return end
		if line:match("^equip:") then item.effects = true end
		return
	end
	local rating = line:find("rating", 1, true) ~= nil and not line:find("%%")
	if line:find("critical", 1, true) then Add(out, rating and "critRating" or "crit", value)
	elseif line:find("chance to hit", 1, true) or line:find("hit rating", 1, true) then Add(out, rating and "hitRating" or "hit", value)
	elseif line:find("chance to dodge", 1, true) or line:find("dodge rating", 1, true) then Add(out, rating and "dodgeRating" or "dodge", value)
	elseif line:find("chance to parry", 1, true) or line:find("parry rating", 1, true) then Add(out, rating and "parryRating" or "parry", value)
	elseif line:find("block value", 1, true) or line:find("block value of", 1, true) then Add(out, "blockValue", value)
	elseif line:find("chance to block", 1, true) or line:find("block rating", 1, true) then Add(out, rating and "blockRating" or "block", value)
	elseif line:find("defense", 1, true) then Add(out, "defense", value)
	elseif line:find("attack power in cat", 1, true) or line:find("feral attack power", 1, true) then Add(out, "feralAP", value)
	elseif line:find("ranged attack power", 1, true) then Add(out, "rap", value)
	elseif line:find("attack power", 1, true) then Add(out, "ap", value)
	elseif line:find("mana per 5", 1, true) then Add(out, "mp5", value)
	elseif line:find("spell", 1, true) or line:find("healing", 1, true) then
		local school
		for _, key in ipairs({ "fire", "frost", "shadow", "nature", "arcane", "holy" }) do
			if line:find(key, 1, true) then school = key; break end
		end
		if line:find("healing", 1, true) and line:find("damage", 1, true) then
			local heal = tonumber(line:match("healing.-by up to ([%d%.]+)")) or tonumber(line:match("([%d%.]+) healing"))
			local damage = tonumber(line:match("damage.-by up to ([%d%.]+)")) or tonumber(line:match("([%d%.]+) spell damage"))
			if heal and damage and heal ~= damage then
				Add(out, "heal", heal); Add(out, "sp", damage)
			elseif line:find("damage and healing", 1, true) or (heal and damage and heal == damage) then
				Add(out, "sp", value)
			else item.effects = true end
		elseif school then Add(out, school, value)
		elseif line:find("damage", 1, true) or line:find("spell power", 1, true) then Add(out, "sp", value)
		else Add(out, "heal", value) end
	elseif line:match("^equip:") then item.effects = true end
end

function Items:Clear()
	wipe(self.cache)
end

function Items:Request(id)
	if not id or not C_Item or not C_Item.RequestLoadItemDataByID then return end
	local now = GetTime()
	if not self.requested[id] or now - self.requested[id] > 5 then
		self.requested[id] = now
		C_Item.RequestLoadItemDataByID(id)
	end
end

local function Restriction(text, color, item, requirement)
	if not ns.Text(text) or not color then return end
	local r, g = color.r, color.g
	if color.GetRGB then r, g = color:GetRGB() end
	if not ns.Number(r) or not ns.Number(g) or r < 0.8 or g > 0.3 then return end
	local line = Clean(text)
	-- The right side contains weapon/armor proficiency; red names and flavor
	-- text are not requirements. Requirements can appear on either side.
	if requirement or line:match("^requires ") or line:match("^classes:") or line:match("^races:") then
		item.restriction = text
	end
end

function Items:TooltipLines(link)
	if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
		local data = C_TooltipInfo.GetHyperlink(link)
		return data and data.lines
	end
	if not self.scanner then
		self.scanner = CreateFrame("GameTooltip", "GearwiseScannerTooltip", UIParent, "GameTooltipTemplate")
	end
	local tip = self.scanner
	tip:SetOwner(UIParent, "ANCHOR_NONE")
	tip:ClearLines()
	tip:SetHyperlink(link)
	local lines = {}
	for index = 1, tip:NumLines() do
		local left, right = _G["GearwiseScannerTooltipTextLeft" .. index], _G["GearwiseScannerTooltipTextRight" .. index]
		local lr, lg, lb = left:GetTextColor()
		local rr, rg, rb = right:GetTextColor()
		lines[index] = { leftText = left:GetText(), rightText = right:GetText(),
			leftColor = { r = lr, g = lg, b = lb }, rightColor = { r = rr, g = rg, b = rb } }
	end
	tip:Hide()
	return lines
end

function Items:Read(link)
	if not ns.Text(link) then return nil, "pending" end
	if self.cache[link] then return self.cache[link] end
	local id = tonumber(link:match("item:(%d+)"))
	if not id then return nil, "irrelevant" end
	local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
	if not getInfo then return nil, "pending" end
	local info = { getInfo(link) }
	if not ns.Text(info[1]) then self:Request(id); return nil, "pending" end
	local item = { id = id, link = link, name = info[1], level = info[5] or 0, loc = info[9],
		classID = info[12], subclassID = info[13], setID = info[16], icon = info[10],
		stats = {} }
	if item.classID == nil or item.subclassID == nil then
		local instant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
		if instant then
			local _, _, _, _, _, classID, subclassID = instant(link)
			item.classID, item.subclassID = classID, subclassID
		end
	end
	-- Forever still classifies picks, hammers, spanners and chisels as generic
	-- weapons (14), and fishing poles as weapons (20). They are utility items,
	-- not combat gear the character lacks proficiency for. Resolve this after
	-- the instant-info fallback so localized names and new tool IDs work too.
	item.tool = professionTools[id] or item.loc == "INVTYPE_PROFESSION_TOOL"
		or item.loc == "INVTYPE_PROFESSION_GEAR" or item.classID == 19
		or (item.classID == 2 and (item.subclassID == 14 or item.subclassID == 20))
	if not ns.Text(item.loc) then return nil, "irrelevant" end
	local getStats = C_Item and C_Item.GetItemStats or GetItemStats
	local raw = getStats and getStats(link) or {}
	if type(raw) ~= "table" then raw = {} end
	for key, value in pairs(raw) do
		if ns.Text(key) and ns.Number(value) then
			local stat = aliases[key]
			if key == "ITEM_MOD_ALL_STATS_SHORT" then
				for _, attribute in ipairs({ "str", "agi", "sta", "int", "spi" }) do
					item.stats[attribute] = math.max(item.stats[attribute] or 0, value)
				end
			elseif stat then item.stats[stat] = math.max(item.stats[stat] or 0, value)
			else
				local parsed = {}
				ParseLine(key, parsed, item)
				for statKey, amount in pairs(parsed) do item.stats[statKey] = math.max(item.stats[statKey] or 0, amount) end
			end
		end
	end
	local parsed = {}
	do
		local ok, lines = pcall(self.TooltipLines, self, link)
		if not ok or type(lines) ~= "table" or #lines == 0 then
			if not ok then self.lastError = tostring(lines) end
			self:Request(id)
			return nil, "pending"
		end
		for index, line in ipairs(lines) do
			Restriction(line.leftText, line.leftColor, item)
			Restriction(line.rightText, line.rightColor, item, index > 1 and ns.Text(line.leftText)
				and Clean(line.leftText):match("^%+?[%d%.]+%s") == nil)
			ParseLine(line.leftText, parsed, item)
			-- Weapon speed is on the right; all actual stats are on the left.
			if ns.Text(line.rightText) then item.speed = tonumber(line.rightText:match("[Ss]peed%s+([%d%.]+)")) or item.speed end
		end
	end
	for key, value in pairs(parsed) do
		-- Tooltip DPS is rounded (e.g. 1.1), while the API can return the exact
		-- 1.0526316. Taking the larger value corrupts differences between weapons.
		if key ~= "dps" then item.stats[key] = math.max(item.stats[key] or 0, value) end
	end
	if not item.stats.dps then
		if item.classID == 2 and ns.Number(item.minDamage) and ns.Number(item.maxDamage)
			and ns.Number(item.speed) and item.speed > 0 then
			item.stats.dps = (item.minDamage + item.maxDamage) / (2 * item.speed)
		else item.stats.dps = parsed.dps end
	end
	-- Forever combines these chances. A tooltip percentage is authoritative;
	-- API aliases must not score the same bonus again as a rating.
	for _, key in ipairs({ "crit", "hit", "dodge", "parry", "block" }) do
		if parsed[key] then item.stats[key .. "Rating"] = nil end
	end
	if C_Item and C_Item.GetItemUniqueness then
		local ok, category, maximum = pcall(C_Item.GetItemUniqueness, link)
		if ok and ns.Number(category) and category > 0 then item.limit, item.limitMax = category, maximum end
	end
	self.cache[link] = item
	return item
end

function Items:Get(link)
	local ok, item, status = pcall(self.Read, self, link)
	if not ok then self.lastError = tostring(item); return nil, "pending" end
	return item, status
end
