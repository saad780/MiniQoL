local _, ns = ...
local Options = {}
ns.Options = Options

-- Gearwise registers no settings category of its own: everything it offers is
-- declared to Mini QoL and drawn on the panel's Gear advice page.
function Options:Refresh()
	if MiniQoL and MiniQoL.Refresh then MiniQoL:Refresh() end
end

function Options:Open()
	if MiniQoL and MiniQoL.ShowPage then MiniQoL:ShowPage("bags") end
end

function Options:Init()
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
			local p = ns.profile
			ns.Print(p and (p.label .. " " .. p.className .. "  /  " .. p.source .. "  /  "
				.. (p.leveling and "Leveling" or "Standard") .. "  /  Level " .. p.level)
				or "Class data unavailable")
		elseif command == "arrows" and (argument == "on" or argument == "off") then
			ns.db.bags, ns.db.quests = argument == "on", argument == "on"
			ns:Invalidate(false)
		elseif command == "tooltip" and (argument == "on" or argument == "off") then
			ns:SetOption("tooltips", argument == "on")
		elseif (command == "popups" or command == "unusable") and (argument == "on" or argument == "off") then
			ns:SetOption(command, argument == "on")
		elseif command == "space" and (argument == "on" or argument == "off") then
			ns:SetOption("spaceToEquip", argument == "on")
			ns.Upgrades:RefreshKeys()
			ns.Print("Space equips the upgrade prompt: " .. (argument == "on" and "on." or "off."))
		elseif command == "styles" then
			if argument == "on" or argument == "off" then
				ns:SetOption("styles", argument == "on")
				ns.Print("Equal-value look offers " .. (argument == "on" and "on." or "off."))
			elseif argument == "reset" then
				local count = ns.Sidegrades:ClearDeclined()
				ns.Print(("Forgot %d declined item%s."):format(count, count == 1 and "" or "s"))
				ns.Sidegrades:Review()
			else
				ns.Sidegrades:Review()
			end
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
