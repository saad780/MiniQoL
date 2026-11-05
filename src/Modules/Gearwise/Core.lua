local addonName, ns = ...
Gearwise = ns
ns.name, ns.revision = addonName, 0

function ns.Readable(value)
	if issecretvalue and issecretvalue(value) then return false end
	if canaccessvalue and not canaccessvalue(value) then return false end
	return value ~= nil
end

function ns.Number(value)
	return ns.Readable(value) and type(value) == "number" and value == value
		and value > -math.huge and value < math.huge
end

function ns.Text(value)
	return ns.Readable(value) and type(value) == "string" and value ~= "" and value or nil
end

function ns.Print(text)
	print("|cff8bc5e8Gearwise|r: " .. text)
end

function ns:Invalidate(items)
	self.revision = self.revision + 1
	self.Compare:Clear()
	if items then self.Items:Clear() end
	self.profile = self.Profiles:Detect()
	self.Display:Schedule()
	if self.Upgrades then self.Upgrades:Schedule() end
	if self.Options.Refresh then self.Options:Refresh() end
end

function ns:SetOption(key, value)
	self.db[key] = value
	self:Invalidate(false)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		local name = ...
		if name == addonName then
			GearwiseDB = type(GearwiseDB) == "table" and GearwiseDB or {}
			ns.db = GearwiseDB
			for key, default in pairs({ spec = "auto", mode = "auto", bags = true, quests = true,
				tooltips = true, unusable = true, popups = true }) do
				if ns.db[key] == nil then ns.db[key] = default end
			end
		elseif ns.loggedIn then
			ns.Display:InstallHooks()
		end
	elseif event == "PLAYER_LOGIN" then
		ns.loggedIn = true
		ns.profile = ns.Profiles:Detect()
		ns.Display:Init()
		ns.Upgrades:Init()
		ns.Options:Init()
		for _, name in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
			"PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED",
			"PLAYER_SPECIALIZATION_CHANGED", "SPELLS_CHANGED", "SKILL_LINES_CHANGED", "PLAYER_ENTERING_WORLD",
			"GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT", "QUEST_DETAIL", "QUEST_COMPLETE", "QUEST_ITEM_UPDATE",
			"QUEST_LOG_UPDATE", "PLAYER_REGEN_ENABLED" }) do
			pcall(events.RegisterEvent, events, name)
		end
	elseif ns.loggedIn then
		if event == "QUEST_DETAIL" or event == "QUEST_COMPLETE" or event == "QUEST_LOG_UPDATE" or event == "QUEST_ITEM_UPDATE" then
			ns.Display:Schedule()
		else
			ns:Invalidate(event ~= "BAG_UPDATE_DELAYED" and event ~= "PLAYER_REGEN_ENABLED")
		end
	end
end)
