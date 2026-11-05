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

Add("WARRIOR", "arms", "Arms", melee, nil, { meleeDPS = 14 })
Add("WARRIOR", "fury", "Fury", melee, { hit = 25 }, { meleeDPS = 14 })
Add("WARRIOR", "protection", "Protection", tank, nil, { meleeDPS = 9, shield = true })
Add("PALADIN", "holy", "Holy", healer, { spi = 0.6, crit = 22 }, { role = "healer" })
Add("PALADIN", "protection", "Protection", tank, { sp = 1, int = 0.8 }, { meleeDPS = 8, shield = true })
Add("PALADIN", "retribution", "Retribution", melee, { sp = 0.7, int = 0.35 }, { meleeDPS = 14 })
Add("HUNTER", "beast_mastery", "Beast Mastery", melee, { str = 0.3, agi = 2.5, ap = 1, rap = 1, int = 0.35 }, { rangedDPS = 15 })
Add("HUNTER", "marksmanship", "Marksmanship", melee, { str = 0.3, agi = 2.6, ap = 1, rap = 1, int = 0.5 }, { rangedDPS = 16 })
Add("HUNTER", "survival", "Survival", melee, { str = 0.4, agi = 2.7, ap = 1, rap = 1, sta = 1, int = 0.35 }, { rangedDPS = 15 })
Add("ROGUE", "assassination", "Assassination", melee, { str = 1, agi = 2.4, hit = 26 }, { meleeDPS = 15 })
Add("ROGUE", "combat", "Combat", melee, { str = 1, agi = 2.3, hit = 25 }, { meleeDPS = 15 })
Add("ROGUE", "subtlety", "Subtlety", melee, { str = 1, agi = 2.5 }, { meleeDPS = 15 })
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
	local level = math.max(1, UnitLevel("player") or 1)
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
	if profile.leveling and level < 20 and not profile.meleeDPS and not profile.feral then
		-- Early caster/healer characters still use their melee weapons. A plain
		-- mace upgrade must not tie just because the eventual build is a caster.
		profile.meleeDPS = level < 10 and 8 or 2
	end
	profile.weights.health = (profile.weights.sta or 0) / 10
	profile.weights.mana = (profile.weights.int or 0) / 15
	profile.weights.hp5 = profile.leveling and 1 or 0.2
	return profile
end
