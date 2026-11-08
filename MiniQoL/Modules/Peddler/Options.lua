-- Mini QoL packaging adapter; upstream source and credits follow.
MiniQoLRuntime:Execute("Peddler", function(...)
local _, Peddler = ...

-- Peddler registers no settings category of its own. Its options are declared
-- to Mini QoL and drawn on the panel's Selling page, so there is one place to
-- change them instead of two that can disagree.
SLASH_PEDDLER_COMMAND1 = '/peddler'
SlashCmdList['PEDDLER_COMMAND'] = function()
	if MiniQoL and MiniQoL.ShowPage then MiniQoL:ShowPage("selling") end
end

end)
