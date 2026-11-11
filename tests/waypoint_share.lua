-- Sharing a waypoint must put the token somewhere the player can reach it.
-- The chat helpers moved namespace, their return values do not reliably report
-- success, and recent clients refuse chat messaging while locked down, so every
-- route is exercised here including the copyable fallback.
local root = ...

local function noop() end

-- A stand-in chat edit box: only text that actually lands in it counts.
local box = { text = "", shown = false }
function box:IsShown() return self.shown end
function box:GetText() return self.text end
function box:SetText(value) self.text = value end

local popup
StaticPopupDialogs = {}
function StaticPopup_Show(which, _, _, data) popup = { which = which, data = data } end
CLOSE = "Close"

local printed = {}
local ns = { db = { waypoints = {} } }
function ns:NewModule(name) self[name] = { name = name } return self[name] end
function ns.Print(message) printed[#printed + 1] = message end
function ns.Readable() return true end
MiniQoLRuntime = { Execute = function(_, _, fn) return fn("Wayfinder", ns) end }
assert(loadfile(root .. "/Modules/Wayfinder/Navigation.lua"))()
local Navigation = ns.Navigation

local TOKEN = "[Wayfinder:1429:5000:5000:Goldshire]"

local function reset()
    box.text, box.shown, popup, printed = "", false, nil, {}
    ChatFrameUtil, ChatEdit_InsertLink, ChatFrame_OpenChat = nil, nil, nil
    ChatEdit_GetActiveWindow, C_ChatInfo = function() return box end, nil
end

local function equal(actual, expected, label)
    assert(actual == expected, (label or "value") .. ": " .. tostring(actual))
end

-- 1. The current client's namespace, inserting into an open draft.
reset()
ChatFrameUtil = {
    GetActiveWindow = function() return box end,
    InsertLink = function(text) box.shown = true; box.text = box.text .. text; return true end,
    OpenChat = function(text) box.shown = true; box.text = text end,
}
equal(Navigation:ShareText(TOKEN), true, "namespaced insert")
equal(box.text, TOKEN, "token reached the draft")
equal(popup, nil, "no fallback needed")

-- 2. Older clients, where the helpers are still globals.
reset()
ChatEdit_InsertLink = function(text) box.shown = true; box.text = text; return true end
equal(Navigation:ShareText(TOKEN), true, "legacy global insert")
equal(box.text, TOKEN, "token reached the draft")
equal(popup, nil, "no fallback needed")

-- 3. The silent failure this test exists for: the insert reports success but
--    nothing lands, so opening a fresh chat line has to rescue it.
reset()
ChatEdit_InsertLink = function() return true end
ChatFrame_OpenChat = function(text) box.shown = true; box.text = text end
equal(Navigation:ShareText(TOKEN), true, "falls through a lying insert")
equal(box.text, TOKEN, "opening chat carried the token")
equal(popup, nil, "no fallback needed")

-- 4. Chat messaging lockdown: do not touch chat, hand over a copyable box.
reset()
C_ChatInfo = { InChatMessagingLockdown = function() return true end }
ChatEdit_InsertLink = function() error("chat must not be touched during lockdown") end
ChatFrame_OpenChat = function() error("chat must not be touched during lockdown") end
equal(Navigation:ShareText(TOKEN), false, "lockdown refuses chat")
assert(popup and popup.which == "WAYFINDER_SHARE", "copyable fallback shown")
equal(popup.data, TOKEN, "fallback offers the whole token")
assert(#printed == 1 and printed[1]:find("copy it"), "the player is told why")

-- 5. Neither insert nor open does anything useful.
reset()
ChatEdit_InsertLink = function() return false end
ChatFrame_OpenChat = noop
equal(Navigation:ShareText(TOKEN), false, "no working chat route")
assert(popup and popup.data == TOKEN, "fallback still offers the token")

-- 6. No chat API at all: still recoverable, still no error.
reset()
equal(Navigation:ShareText(TOKEN), false, "missing chat API")
assert(popup and popup.data == TOKEN, "fallback offers the token")

-- 7. The fallback's edit box keeps the token intact when typed in.
local dialog = StaticPopupDialogs.WAYFINDER_SHARE
assert(dialog and dialog.hasEditBox, "the fallback has a copyable box")
local edit = { text = "", parent = { Hide = noop } }
function edit:SetText(value) self.text = value end
function edit:GetText() return self.text end
function edit:HighlightText() self.highlighted = true end
function edit:SetFocus() self.focused = true end
function edit:GetParent() return self.parent end
dialog.OnShow({ editBox = edit }, TOKEN)
equal(edit.text, TOKEN, "box opens holding the token")
assert(edit.highlighted and edit.focused, "ready to copy immediately")
edit:SetText("mangled")
dialog.EditBoxOnTextChanged(edit, TOKEN)
equal(edit.text, TOKEN, "editing cannot corrupt the token")

-- 8. Shift-clicking the game's own map pin. Its handler copies a /way command
--    to the clipboard, which is refused once the map is tainted, so the link is
--    shared here and the game's handler is stopped before it gets there.
reset()
ChatFrameUtil = {
    GetActiveWindow = function() return box end,
    InsertLink = function(text) box.shown = true; box.text = box.text .. text; return true end,
}
MapCanvasMixin = { MouseAction = { Up = 1, Down = 2, Click = 3 } }
local handler, priority
WorldMapFrame = { ScrollContainer = { HookScript = noop },
    AddGlobalPinMouseActionHandler = function(_, fn, level) handler, priority = fn, level end }
Navigation.CreateLocateButton = noop
Navigation:HookWorldMap()
assert(handler and priority > 1000, "the handler goes in ahead of the seamless map's")
local PIN_LINK = "|cffffff00|Hworldmap:1429:5000:5000|h[Map Pin Location]|h|r"
C_Map = { GetUserWaypointHyperlink = function() return PIN_LINK end }
local focus, shift, played = { { pinTemplate = "WaypointLocationPinTemplate" } }, true, false
function GetMouseFoci() return focus end
function IsModifiedClick(kind) return kind == "CHATLINK" and shift end
SOUNDKIT = { UI_MAP_WAYPOINT_CHAT_SHARE = 1 }
function PlaySound() played = true end
equal(handler(WorldMapFrame, MapCanvasMixin.MouseAction.Up, "LeftButton"), false, "the release still reaches the pin")
equal(handler(WorldMapFrame, MapCanvasMixin.MouseAction.Click, "LeftButton"), true, "the shift-click is taken over")
equal(box.text, PIN_LINK, "and its link reaches chat")
assert(played, "with the game's sound")
shift = false
equal(handler(WorldMapFrame, MapCanvasMixin.MouseAction.Click, "LeftButton"), false, "a plain click still tracks the pin")
shift, focus = true, { { pinTemplate = "QuestPinTemplate" } }
equal(handler(WorldMapFrame, MapCanvasMixin.MouseAction.Click, "LeftButton"), false, "other pins keep their own shift-click")

print("Waypoint sharing across chat namespaces, lockdown, the copyable fallback and the game's map pin passed")
