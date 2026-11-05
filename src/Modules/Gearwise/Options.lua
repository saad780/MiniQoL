local _, ns = ...
local Options = {}
ns.Options = Options

function Options:Refresh()
	if self.status and ns.profile then
		local p = ns.profile
		self.status:SetText(p.label .. " " .. p.className .. "  /  " .. p.source .. "  /  "
			.. (p.leveling and "Leveling" or "Standard") .. "  /  Level " .. p.level)
	end
end

function Options:Open()
	if self.category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(self.category:GetID())
	elseif self.panel then self.panel:Show() end
end

function Options:Init()
	local panel = CreateFrame("Frame", "GearwiseOptions", UIParent)
	self.panel = panel
	local function Text(text, x, y, font)
		local label = panel:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
		label:SetPoint("TOPLEFT", x, y)
		label:SetText(text)
		return label
	end
	Text("Gearwise", 20, -20, "GameFontNormalLarge")
	Text("Small arrows. Useful stats. Gear advice for the character you're playing.", 20, -52)
	self.status = Text("", 20, -82)
	self.status:SetTextColor(0.55, 0.77, 0.91)
	local function Dropdown(label, y, key, choices)
		Text(label, 20, y, "GameFontNormal")
		local dropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
		dropdown:SetPoint("TOPLEFT", 20, y - 22)
		dropdown:SetWidth(260)
		dropdown:SetupMenu(function(_, root)
			for _, option in ipairs(choices()) do
				local value, name = option[1], option[2]
				root:CreateRadio(name, function() return ns.db[key] == value end, function() ns:SetOption(key, value) end)
			end
		end)
	end
	Dropdown("Build", -124, "spec", function()
		local _, class = UnitClass("player")
		local options = { { "auto", "Automatic (talents)" } }
		for _, profile in ipairs(ns.Profiles.classes[class] or {}) do options[#options + 1] = { profile.key, profile.label } end
		return options
	end)
	Dropdown("Stat priorities", -196, "mode", function()
		return { { "auto", "Automatic (leveling below 60)" }, { "leveling", "Leveling" }, { "standard", "Standard" } }
	end)
	for index, option in ipairs({ { "bags", "Arrows on bag items" }, { "quests", "Quest reward arrows and best-value coin" },
		{ "unusable", "Shade equipment I cannot wear red" }, { "popups", "Prompt when I obtain an upgrade" },
		{ "tooltips", "Compact item tooltip comparison" } }) do
		local key, label = option[1], option[2]
		local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		check:SetPoint("TOPLEFT", 16, -282 - (index - 1) * 32)
		local text = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		text:SetPoint("LEFT", check, "RIGHT", 4, 0)
		text:SetText(label)
		check:SetScript("OnShow", function(button) button:SetChecked(ns.db[key]) end)
		check:SetScript("OnClick", function(button) ns:SetOption(key, button:GetChecked()) end)
	end
	local note = Text("Leveling gives health and recovery more value. Use a manual build when gearing for a different role.\n\nScores estimate useful item stats; special effects, set bonuses and exact damage rotations need your judgment.\n\n/gw upgrades reviews upgrades already in your bags.", 20, -464)
	note:SetWidth(560)
	note:SetJustifyH("LEFT")
	note:SetTextColor(0.65, 0.69, 0.74)
	panel:SetScript("OnShow", function() self:Refresh() end)
	panel:Hide()
	if Settings and Settings.RegisterCanvasLayoutCategory then
		self.category = Settings.RegisterCanvasLayoutCategory(panel, "Gearwise")
		Settings.RegisterAddOnCategory(self.category)
	end
	self:Refresh()
	SLASH_GEARWISE1, SLASH_GEARWISE2 = "/gearwise", "/gw"
	SlashCmdList.GEARWISE = function(message)
		local command, argument = (message or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
		if command == "spec" then
			local aliases = { cat = "feral", resto = "restoration", ret = "retribution", prot = "protection", enh = "enhancement", ele = "elemental", bm = "beast_mastery" }
			argument = aliases[argument] or argument
			local _, class = UnitClass("player")
			if argument == "auto" or ns.Profiles:Find(class, argument) then
				ns:SetOption("spec", argument)
				ns.Print("Using " .. ns.profile.label .. (argument == "auto" and " (automatic)." or "."))
			else
				local names = { "auto" }
				for _, profile in ipairs(ns.Profiles.classes[class] or {}) do names[#names + 1] = profile.key end
				ns.Print("Builds: " .. table.concat(names, ", "))
			end
		elseif command == "status" then
			self:Refresh()
			ns.Print(self.status:GetText() or "Class data unavailable")
		elseif command == "arrows" and (argument == "on" or argument == "off") then
			ns.db.bags, ns.db.quests = argument == "on", argument == "on"
			ns:Invalidate(false)
		elseif command == "tooltip" and (argument == "on" or argument == "off") then
			ns:SetOption("tooltips", argument == "on")
		elseif (command == "popups" or command == "unusable") and (argument == "on" or argument == "off") then
			ns:SetOption(command, argument == "on")
		elseif command == "upgrades" then
			if ns.db.popups then ns.Upgrades:Review() else ns.Print("Enable upgrade popups with /gw popups on.") end
		elseif command == "debug" then
			local counts = {}
			for button, kind in pairs(ns.Display.buttons) do
				if button:IsVisible() then
					local ok, link = pcall(ns.Display.Link, ns.Display, button, kind)
					local status = ok and link and ns.Compare:Get(link).status or "no item link"
					counts[status] = (counts[status] or 0) + 1
				end
			end
			local rows = {}
			for status, count in pairs(counts) do rows[#rows + 1] = status .. "=" .. count end
			ns.Print("Visible tracked items: " .. (#rows > 0 and table.concat(rows, ", ") or "none"))
			if ns.Items.lastError then ns.Print("Item data: " .. ns.Items.lastError) end
			if ns.Compare.lastError then ns.Print("Comparison: " .. ns.Compare.lastError) end
		else self:Open() end
	end
end
