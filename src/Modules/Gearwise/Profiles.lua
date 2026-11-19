local _, ns = ...
local Profiles = {}
ns.Profiles = Profiles

-- Deliberately small, independent stat-score heuristics, not simulated DPS/HPS.
-- Percent stats and rating stats have separate weights. Leveling adds recovery
-- and health value; it never turns caster gear into melee gear or vice versa.
local melee = { str = 2, agi = 1.4, ap = 1, sta = 0.7, armor = 0.015,
	crit = 20, hit = 22, critRating = 0.9, hitRating = 1.1, hasteRating = 0.8, expertiseRating = 0.9 }
local caster = { int = 1.8, sta = 0.6, spi = 0.65, sp = 2.6, mp5 = 2, armor = 0.01,
	crit = 18, hit = 24, critRating = 0.8, hitRating = 1.1, hasteRating = 0.9 }
local healer = { int = 1.9, sta = 0.65, spi = 1.5, heal = 1.4, sp = 0.35, mp5 = 4, armor = 0.01,
	crit = 15, critRating = 0.7, hasteRating = 0.8 }
local tank = { str = 1.3, agi = 1.5, ap = 0.5, sta = 2.4, armor = 0.10,
	defense = 2.4, dodge = 22, parry = 20, block = 12, blockValue = 0.8,
	dodgeRating = 1.2, parryRating = 1.1, blockRating = 0.7, crit = 10, hit = 16,
	critRating = 0.5, hitRating = 0.8, expertiseRating = 0.8 }

Profiles.classes = {}
local function Add(class, key, label, base, changes, options)
	local profile = { class = class, key = key, label = label, weights = {} }
	for k, v in pairs(base) do profile.weights[k] = v end
	for k, v in pairs(changes or {}) do profile.weights[k] = v end
	for k, v in pairs(options or {}) do profile[k] = v end
	Profiles.classes[class] = Profiles.classes[class] or {}
	table.insert(Profiles.classes[class], profile)
end

-- A weapon the build does not fight with still gets used: a warrior or a rogue
-- pulls with one throw before a whole fight of swings, and a hunter is caught
-- in melee. What it is worth to them is the stats on it, but its damage has to
-- count for something. At nothing, every plain throwing knife scored zero, so
-- a better one tied with the one in the slot and was never offered.
local spare = 0.25

Add("WARRIOR", "arms", "Arms", melee, nil, { meleeDPS = 14, rangedDPS = spare })
Add("WARRIOR", "fury", "Fury", melee, { hit = 25 }, { meleeDPS = 14, rangedDPS = spare })
Add("WARRIOR", "protection", "Protection", tank, nil, { meleeDPS = 9, rangedDPS = spare, shield = true })
Add("PALADIN", "holy", "Holy", healer, { spi = 0.6, crit = 22 }, { role = "healer" })
Add("PALADIN", "protection", "Protection", tank, { sp = 1, int = 0.8 }, { meleeDPS = 8, shield = true })
Add("PALADIN", "retribution", "Retribution", melee, { sp = 0.7, int = 0.35 }, { meleeDPS = 14 })
-- shoots: the ranged slot has to hold a bow, gun or crossbow (Compare.lua).
Add("HUNTER", "beast_mastery", "Beast Mastery", melee, { str = 0.3, agi = 2.5, ap = 1, rap = 1, int = 0.35 }, { rangedDPS = 15, meleeDPS = spare, shoots = true })
Add("HUNTER", "marksmanship", "Marksmanship", melee, { str = 0.3, agi = 2.6, ap = 1, rap = 1, int = 0.5 }, { rangedDPS = 16, meleeDPS = spare, shoots = true })
Add("HUNTER", "survival", "Survival", melee, { str = 0.4, agi = 2.7, ap = 1, rap = 1, sta = 1, int = 0.35 }, { rangedDPS = 15, meleeDPS = spare, shoots = true })
Add("ROGUE", "assassination", "Assassination", melee, { str = 1, agi = 2.4, hit = 26 }, { meleeDPS = 15, rangedDPS = spare })
Add("ROGUE", "combat", "Combat", melee, { str = 1, agi = 2.3, hit = 25 }, { meleeDPS = 15, rangedDPS = spare })
Add("ROGUE", "subtlety", "Subtlety", melee, { str = 1, agi = 2.5 }, { meleeDPS = 15, rangedDPS = spare })
Add("PRIEST", "discipline", "Discipline", healer, { int = 2.1 }, { role = "healer", wand = true })
Add("PRIEST", "holy", "Holy", healer, { spi = 1.9 }, { role = "healer", wand = true })
Add("PRIEST", "shadow", "Shadow", caster, { sp = 2.9, spi = 0.9 }, { school = "shadow", wand = true })
Add("SHAMAN", "elemental", "Elemental", caster, { crit = 22, spi = 0.35 }, { school = "nature" })
Add("SHAMAN", "enhancement", "Enhancement", melee, { int = 0.5, sp = 0.55 }, { meleeDPS = 14 })
Add("SHAMAN", "restoration", "Restoration", healer, { spi = 0.65, mp5 = 4.5 }, { role = "healer" })
Add("SHAMAN", "tank", "Enhancement Tank", tank, { int = 0.6, sp = 0.4 }, { meleeDPS = 8, shield = true })
Add("MAGE", "arcane", "Arcane", caster, { int = 2.1 }, { school = "arcane", wand = true })
Add("MAGE", "fire", "Fire", caster, { crit = 24 }, { school = "fire", wand = true })
Add("MAGE", "frost", "Frost", caster, { int = 2, spi = 0.8 }, { school = "frost", wand = true })
Add("WARLOCK", "affliction", "Affliction", caster, { sta = 1.1, spi = 0.25, crit = 10 }, { school = "shadow", wand = true })
Add("WARLOCK", "demonology", "Demonology", caster, { sta = 1.3, spi = 0.25 }, { school = "shadow", wand = true })
Add("WARLOCK", "destruction", "Destruction", caster, { sta = 0.9, spi = 0.25, crit = 22 }, { school = "fire", secondarySchool = "shadow", wand = true })
Add("DRUID", "balance", "Balance", caster, { spi = 0.9 }, { school = "nature", secondarySchool = "arcane" })
Add("DRUID", "feral", "Feral (Cat)", melee, { str = 2.4, agi = 2.3, feralAP = 1 }, { feral = true })
Add("DRUID", "restoration", "Restoration", healer, { spi = 2 }, { role = "healer" })
Add("DRUID", "bear", "Feral (Bear)", tank, { armor = 0.22, sta = 2.8, str = 1.5, feralAP = 0.6 }, { feral = true })

local defaults = { WARRIOR = "arms", PALADIN = "retribution", HUNTER = "beast_mastery", ROGUE = "combat",
	PRIEST = "shadow", SHAMAN = "enhancement", MAGE = "frost", WARLOCK = "affliction", DRUID = "feral" }
local specIDs = {
	[71] = "arms", [72] = "fury", [73] = "protection", [65] = "holy", [66] = "protection", [70] = "retribution",
	[253] = "beast_mastery", [254] = "marksmanship", [255] = "survival", [259] = "assassination", [260] = "combat", [261] = "subtlety",
	[256] = "discipline", [257] = "holy", [258] = "shadow", [262] = "elemental", [263] = "enhancement", [264] = "restoration",
	[62] = "arcane", [63] = "fire", [64] = "frost", [265] = "affliction", [266] = "demonology", [267] = "destruction",
	[102] = "balance", [103] = "feral", [104] = "bear", [105] = "restoration",
}

function Profiles:Find(class, key)
	for _, profile in ipairs(self.classes[class] or {}) do if profile.key == key then return profile end end
end

---------------------------------------------------------------------------
-- Values set by hand
---------------------------------------------------------------------------
-- Every number above is a judgement, and a player may judge differently. Any
-- of a build's values can be replaced, per character and per build. The
-- defaults are never written over: a value set back to its default, or
-- cleared, is simply the build's own again.
--   max and step size the control the panel draws; hint is its tooltip.
local PER_POINT = "What one point is worth. "
Profiles.STATS = {
	{ key = "str", label = "Strength", max = 5, step = 0.05, hint = PER_POINT .. "Strength adds attack power for melee builds." },
	{ key = "agi", label = "Agility", max = 5, step = 0.05, hint = PER_POINT .. "Agility adds crit, dodge and armor, and attack power for rogues, hunters and cats." },
	{ key = "sta", label = "Stamina", max = 5, step = 0.05, hint = PER_POINT .. "Stamina is health. Leveling priorities add their own bonus on top of this." },
	{ key = "int", label = "Intellect", max = 5, step = 0.05, hint = PER_POINT .. "Intellect is mana and spell crit." },
	{ key = "spi", label = "Spirit", max = 5, step = 0.05, hint = PER_POINT .. "Spirit is regeneration. Leveling priorities add their own bonus on top of this." },
	{ key = "ap", label = "Attack power", max = 3, step = 0.05, hint = PER_POINT .. "Attack power written on the item itself." },
	{ key = "rap", label = "Ranged attack power", max = 3, step = 0.05, hint = PER_POINT .. "Attack power that only counts for ranged attacks." },
	{ key = "feralAP", label = "Feral attack power", max = 3, step = 0.05, hint = PER_POINT .. "Attack power that only counts in cat and bear form." },
	{ key = "sp", label = "Spell power", max = 6, step = 0.05, hint = PER_POINT .. "Damage added to spells. Damage for the build's own school counts the same." },
	{ key = "heal", label = "Healing", max = 4, step = 0.05, hint = PER_POINT .. "Healing added to spells." },
	{ key = "mp5", label = "Mana per 5 seconds", max = 10, step = 0.1, hint = PER_POINT .. "Mana restored every five seconds." },
	{ key = "crit", label = "Crit chance", max = 50, step = 0.5, hint = "What each 1% chance to crit is worth." },
	{ key = "hit", label = "Hit chance", max = 50, step = 0.5, hint = "What each 1% chance to hit is worth." },
	{ key = "critRating", label = "Crit rating", max = 3, step = 0.05, hint = PER_POINT .. "Rating is the small-number form of crit chance." },
	{ key = "hitRating", label = "Hit rating", max = 3, step = 0.05, hint = PER_POINT .. "Rating is the small-number form of hit chance." },
	{ key = "hasteRating", label = "Haste rating", max = 3, step = 0.05, hint = PER_POINT .. "Haste speeds up attacks and casts." },
	{ key = "expertiseRating", label = "Expertise rating", max = 3, step = 0.05, hint = PER_POINT .. "Expertise stops attacks being dodged and parried." },
	{ key = "armor", label = "Armor", max = 0.5, step = 0.005, hint = PER_POINT .. "Small on purpose: armor comes in tens and hundreds." },
	{ key = "defense", label = "Defense", max = 6, step = 0.1, hint = PER_POINT .. "Defense makes a tank harder to hit and to crit." },
	{ key = "dodge", label = "Dodge chance", max = 50, step = 0.5, hint = "What each 1% chance to dodge is worth." },
	{ key = "parry", label = "Parry chance", max = 50, step = 0.5, hint = "What each 1% chance to parry is worth." },
	{ key = "block", label = "Block chance", max = 50, step = 0.5, hint = "What each 1% chance to block is worth." },
	{ key = "blockValue", label = "Block value", max = 3, step = 0.05, hint = PER_POINT .. "How much damage each block stops." },
	{ key = "dodgeRating", label = "Dodge rating", max = 3, step = 0.05, hint = PER_POINT .. "Rating is the small-number form of dodge chance." },
	{ key = "parryRating", label = "Parry rating", max = 3, step = 0.05, hint = PER_POINT .. "Rating is the small-number form of parry chance." },
	{ key = "blockRating", label = "Block rating", max = 3, step = 0.05, hint = PER_POINT .. "Rating is the small-number form of block chance." },
	{ key = "meleeDPS", label = "Melee weapon damage", max = 30, step = 0.25, hint = "What each point of damage per second on a melee weapon is worth. The off hand counts for half." },
	{ key = "rangedDPS", label = "Ranged weapon damage", max = 30, step = 0.25, hint = "What each point of damage per second on a bow, gun, crossbow or thrown weapon is worth." },
}
local statByKey = {}
for _, stat in ipairs(Profiles.STATS) do statByKey[stat.key] = stat end
-- Weapon damage is kept on the build itself, not among its stat weights.
local DAMAGE = { meleeDPS = true, rangedDPS = true }

-- The build's own value for a stat, or nil where the build has no use for it:
-- only what a build weighs can be set, so the list is short and is the
-- build's own.
function Profiles:Default(class, key, stat)
	local base = self:Find(class, key)
	if not base or not statByKey[stat] then return nil end
	if DAMAGE[stat] then return base[stat] end
	return base.weights[stat]
end

local function Saved(key, create)
	local db = ns.db
	if not db or not key then return nil end
	if type(db.custom) ~= "table" then
		if not create then return nil end
		db.custom = {}
	end
	if type(db.custom[key]) ~= "table" then
		if not create then return nil end
		db.custom[key] = {}
	end
	return db.custom[key]
end

-- The value in use and the default it stands in for.
function Profiles:Value(class, key, stat)
	local default = self:Default(class, key, stat)
	if default == nil then return nil end
	local saved = Saved(key)
	local value = saved and saved[stat]
	return ns.Number(value) and value or default, default
end

function Profiles:SetValue(class, key, stat, value)
	local default = self:Default(class, key, stat)
	if default == nil then return false end
	local info = statByKey[stat]
	if ns.Number(value) then
		-- Sliders hand back floats a hair off the step.
		value = math.max(0, math.min(info.max, math.floor(value / info.step + 0.5) * info.step))
		value = tonumber(("%.4f"):format(value))
	end
	if not ns.Number(value) or math.abs(value - default) < info.step / 2 then
		local saved = Saved(key)
		if saved then
			saved[stat] = nil
			if next(saved) == nil then ns.db.custom[key] = nil end
		end
	else
		Saved(key, true)[stat] = value
	end
	return true
end

-- How many of a build's values differ from its own.
function Profiles:Changed(class, key)
	local count = 0
	for stat, value in pairs(Saved(key) or {}) do
		if ns.Number(value) and self:Default(class, key, stat) ~= nil then count = count + 1 end
	end
	return count
end

function Profiles:Reset(key)
	if ns.db and type(ns.db.custom) == "table" then ns.db.custom[key] = nil end
end

local function TalentPoints(tab)
	-- Classic-style talents expose the purchased rank as the fifth result.
	-- Sum ranks rather than guessing which numeric tab field contains points.
	if GetNumTalents and GetTalentInfo then
		local ok, count = pcall(GetNumTalents, tab)
		if ok and ns.Number(count) and count > 0 then
			local total = 0
			for index = 1, count do
				local success, _, _, _, _, rank = pcall(GetTalentInfo, tab, index)
				if success and ns.Number(rank) and rank >= 0 and rank <= 10 then total = total + rank end
			end
			return total
		end
	end
	if GetTalentTabInfo then
		local ok, first, _, third, _, fifth = pcall(GetTalentTabInfo, tab)
		local points = type(first) == "string" and third or fifth
		if ok and ns.Number(points) and points >= 0 and points <= 100 then return points end
	end
	return 0
end

function Profiles:Detect()
	local className, class = UnitClass("player")
	local options = self.classes[class]
	if not options then return nil end
	-- On the level-up event the game can still report the old level; the level
	-- the event announced is kept in ns.level (Core.lua).
	local level = math.max(1, UnitLevel("player") or 1, ns.level or 1)
	local key, source = ns.db and ns.db.spec or "auto", "Manual"
	if key == "auto" or not self:Find(class, key) then
		key, source = nil, "Auto"
		local best, count = 0, 0
		for tab = 1, 3 do
			local points = TalentPoints(tab)
			if points > count then best, count = tab, points end
		end
		if best > 0 then key = options[best].key end
		if not key then
			local getSpec = GetSpecialization or (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
			local getInfo = GetSpecializationInfo or (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo)
			if getSpec and getInfo then
				local ok, index = pcall(getSpec)
				if ok and ns.Number(index) then
					local success, id = pcall(getInfo, index)
					if success then key = specIDs[id] end
				end
			end
		end
		if not self:Find(class, key) then key, source = defaults[class], "No talents yet" end
	end
	local base = self:Find(class, key)
	local profile = {}
	for k, v in pairs(base) do if k ~= "weights" then profile[k] = v end end
	profile.weights = {}
	for k, v in pairs(base.weights) do profile.weights[k] = v end
	-- Values set by hand stand in for the build's own.
	for stat, value in pairs(Saved(key) or {}) do
		if ns.Number(value) and self:Default(class, key, stat) ~= nil then
			if DAMAGE[stat] then profile[stat] = value else profile.weights[stat] = value end
			profile.custom = true
		end
	end
	profile.level, profile.className, profile.source = level, className, source
	profile.leveling = ns.db and (ns.db.mode == "leveling" or (ns.db.mode == "auto" and level < 60))
	if profile.leveling then
		profile.weights.sta = (profile.weights.sta or 0) * 1.35
		profile.weights.spi = (profile.weights.spi or 0.15) * (level < 40 and 1.5 or 1.15)
	end
	if class == "DRUID" and level < 10 and (key == "feral" or key == "bear") then
		profile.meleeDPS = 10 -- Before Bear Form, the weapon is used directly.
		profile.weights.int = 0.6
	end
	if profile.leveling and level < 20 and not profile.feral then
		-- Early caster/healer characters still use their melee weapons. A plain
		-- mace upgrade must not tie just because the eventual build is a caster.
		local early = level < 10 and 8 or 2
		if (profile.meleeDPS or 0) < early then profile.meleeDPS = early end
	end
	profile.weights.health = (profile.weights.sta or 0) / 10
	profile.weights.mana = (profile.weights.int or 0) / 15
	profile.weights.hp5 = profile.leveling and 1 or 0.2
	return profile
end
