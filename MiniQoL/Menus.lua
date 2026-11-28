local _, ns = ...
---------------------------------------------------------------------------
-- Menus
---------------------------------------------------------------------------
-- With the game's Gamepad UI on, a menu an addon opens through the game's menu
-- system joins its controller focus handling and taints it: the game then
-- blocks its own gamepad calls ("Interface action failed") until a reload.
-- ControllerSafeMenu (Vendor/) draws a plain menu of its own in that case,
-- from the same generator; with the Gamepad UI off it is the game's menu.
function ns.ContextMenu(owner, generator)
    local safe = ns.ControllerSafeMenu
    if safe then return safe.CreateContextMenu(owner, generator) end
    if MenuUtil and MenuUtil.CreateContextMenu then return MenuUtil.CreateContextMenu(owner, generator) end
end

-- Whether menus are being drawn by ControllerSafeMenu rather than the game.
function ns.OwnMenus()
    local safe = ns.ControllerSafeMenu
    return safe ~= nil and safe.IsControllerUIOn() == true
end

-- Every choice in a ControllerSafeMenu description, also calling `after`.
local function AfterChoices(element, after)
    for _, child in ipairs(type(element) == "table" and element.children or {}) do
        for _, key in ipairs({ "callback", "setSelected" }) do
            local fn = child[key]
            if type(fn) == "function" then
                child[key] = function(...)
                    local answer = fn(...)
                    after()
                    return answer
                end
            end
        end
        AfterChoices(child, after)
    end
end

-- One of our dropdowns (WowStyle1DropdownTemplate), set up as usual. With the
-- Gamepad UI on, a click opens the safe menu from the same generator instead,
-- and the dropdown's text is brought up to date after each choice.
-- The safe menu opens on mouse up: opened on mouse down, as the game's does,
-- its "a click outside closes it" could shut it again within the same click.
function ns.SetupDropdown(dropdown, generator)
    dropdown:SetupMenu(generator)
    local open = dropdown:GetScript("OnMouseDown")
    dropdown:SetScript("OnMouseDown", function(self, button, ...)
        if ns.OwnMenus() then return end
        if open then return open(self, button, ...) end
    end)
    dropdown:HookScript("OnMouseUp", function(self)
        if not ns.OwnMenus() or (self.IsEnabled and not self:IsEnabled()) then return end
        if self.IsMouseOver and not self:IsMouseOver() then return end
        ns.ContextMenu(self, function(owner, root)
            generator(owner, root)
            AfterChoices(root, function() if self.GenerateMenu then self:GenerateMenu() end end)
        end)
    end)
end
