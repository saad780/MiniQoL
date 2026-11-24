-- Mail: a word when mail arrives (who it is from, what is waiting at login,
-- each auction that sells), and a box beside the Send Mail tab listing your
-- other characters and the people you have mailed lately, a click putting a
-- name in the To field.
local root = ...
local function noop() end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local methods = {}
local function NewFrame(kind, parent, template)
    local frame = { kind = kind, parent = parent, template = template, scripts = {}, points = {}, children = {},
        events = {}, shown = true }
    return setmetatable(frame, { __index = function(_, key)
        if methods[key] then return methods[key] end
        if type(key) == "string" and key:find("^%u") then return noop end
    end })
end
function methods:SetScript(name, fn) self.scripts[name] = fn end
function methods:GetScript(name) return self.scripts[name] end
function methods:HookScript(name, fn)
    local before = self.scripts[name]
    self.scripts[name] = function(...) if before then before(...) end; return fn(...) end
end
function methods:SetShown(value)
    value = value and true or false
    if value == self.shown then return end
    self.shown = value
    local script = self.scripts[value and "OnShow" or "OnHide"]
    if script then script(self) end
end
function methods:Show() self:SetShown(true) end
function methods:Hide() self:SetShown(false) end
function methods:IsShown() return self.shown end
function methods:SetPoint(...) self.points[#self.points + 1] = { ... } end
function methods:ClearAllPoints() self.points = {} end
function methods:GetPoint(index)
    local point = self.points[index or 1]
    if point then return point[1], point[2], point[3], point[4], point[5] end
end
function methods:GetChildren() return unpack(self.children) end
function methods:IsForbidden() return false end
function methods:SetWidth(width) self.width = width end
function methods:SetHeight(height) self.height = height end
function methods:GetHeight() return self.height end
function methods:SetText(text) self.text = text end
function methods:GetText() return self.text end
function methods:SetTextColor(r, g, b) self.color = { r, g, b } end
function methods:SetFocus() self.focused = true end
function methods:HighlightText() self.highlighted = true end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:CreateTexture() return NewFrame("Texture", self) end
function methods:CreateFontString() return NewFrame("FontString", self) end
-- Where a frame is on screen, when the test has said: { left, bottom, right, top }.
function methods:GetLeft() return self.rect and self.rect[1] end
function methods:GetBottom() return self.rect and self.rect[2] end
function methods:GetRight() return self.rect and self.rect[3] end
function methods:GetTop() return self.rect and self.rect[4] end
local function RequiresBackdrop(self, method)
    assert(self.template and self.template:find("BackdropTemplate"),
        "a " .. tostring(self.kind) .. " needs BackdropTemplate to call " .. method)
end
function methods:SetBackdrop() RequiresBackdrop(self, "SetBackdrop") end
function methods:SetBackdropColor() RequiresBackdrop(self, "SetBackdropColor") end
function methods:SetBackdropBorderColor() RequiresBackdrop(self, "SetBackdropBorderColor") end
function CreateFrame(kind, name, parent, template)
    local frame = NewFrame(kind, parent, template)
    if parent then parent.children[#parent.children + 1] = frame end
    if name then _G[name] = frame; frame.GetName = function() return name end end
    if template == "BasicFrameTemplateWithInset" then frame.TitleText = frame:CreateFontString() end
    if template == "UICheckButtonTemplate" then frame.Text = frame:CreateFontString() end
    return frame
end

---------------------------------------------------------------------------
-- The game
---------------------------------------------------------------------------
local CLOCK, clock = 1700000000, 500
function time() return CLOCK end
function GetTime() return clock end
local timers = {}
C_Timer = { After = function(delay, fn) timers[#timers + 1] = { at = clock + delay, fn = fn } end }
local function advance(seconds)
    local target = clock + seconds
    while true do
        local nextIndex
        for index, timer in ipairs(timers) do
            if timer.at <= target and (not nextIndex or timer.at < timers[nextIndex].at) then nextIndex = index end
        end
        if not nextIndex then break end
        local timer = table.remove(timers, nextIndex)
        CLOCK, clock = CLOCK + math.max(0, timer.at - clock), math.max(clock, timer.at)
        timer.fn()
    end
    CLOCK, clock = CLOCK + (target - clock), target
end

function issecretvalue(value) return value == "SECRET" end
UNKNOWNOBJECT = "Unknown"
Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
RAID_CLASS_COLORS = { WARLOCK = { r = 0.53, g = 0.53, b = 0.93 }, ROGUE = { r = 1, g = 0.96, b = 0.41 } }
YES, NO, StaticPopupDialogs = "Yes", "No", {}
local popup
function StaticPopup_Show(name) popup = name end

local player -- whoever is logged in: this game gives a name and a surname
function UnitName() return player.name, player.surname end
function GetRealmName() return player.realm end
function UnitClass() return player.className, player.class end
function UnitFactionGroup() return player.faction, player.faction end
function UnitLevel() return player.level end

-- Unread mail, as the game tells addons of it.
local unread, senders = false, {}
local looks = 0
function HasNewMail() looks = looks + 1; return unread end
function GetLatestThreeSenders() return senders[1], senders[2], senders[3] end

local sounds, mute = {}, {}
SOUNDKIT = { UI_BNET_TOAST = 18019, TELL_MESSAGE = 3081, LOOT_WINDOW_COIN_SOUND = 120 }
function PlaySound(kit, channel)
    if mute[kit] then return false end
    sounds[#sounds + 1] = { kit = kit, channel = channel }
    return true
end
local screen = {}
UIErrorsFrame = { AddMessage = function(_, text, r, g, b) screen[#screen + 1] = { text = text, r = r, g = g, b = b } end }

GameTooltip = { lines = {} }
function GameTooltip:SetOwner(owner) self.owner, self.lines, self.title = owner, {}, nil end
function GameTooltip:SetText(text) self.title = text end
function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
GameTooltip.Show, GameTooltip.Hide = noop, noop

function hooksecurefunc(name, hook)
    local original = _G[name]
    assert(type(original) == "function", name .. " is there to be hooked")
    _G[name] = function(...)
        original(...)
        hook(...)
    end
end

-- The mailbox window. The game may not have built it when Mini QoL starts.
UIParent = NewFrame("Frame")
local function BuildMailbox()
    MailFrame = CreateFrame("Frame", nil, UIParent)
    MailFrame.rect = { 16, 200, 354, 700 }
    SendMailFrame = CreateFrame("Frame", nil, MailFrame)
    SendMailNameEditBox = CreateFrame("EditBox", nil, SendMailFrame)
    SendMailSubjectEditBox = CreateFrame("EditBox", nil, SendMailFrame)
end

---------------------------------------------------------------------------
-- Mini QoL, logged in as one character after another
---------------------------------------------------------------------------
MiniQoLDB = {}
local printed, features, refreshes = {}, {}, 0
local sent -- what the game was last asked to send
local function Session(character)
    player = character
    SendMail = function(recipient, subject, body) sent = { recipient, subject, body } end
    features = {}
    local ns = { db = MiniQoLDB }
    function ns:Print(message) printed[#printed + 1] = message end
    function ns:RegisterFeature(spec) features[spec.id] = spec end
    function ns:Refresh() refreshes = refreshes + 1 end
    assert(loadfile(root .. "/Theme.lua"))("MiniQoL", ns)
    assert(loadfile(root .. "/Mail.lua"))("MiniQoL", ns)
    ns.Mail:Start()
    return ns.Mail
end
local function fire(M, event, ...)
    assert(M.events.events[event], "listens for " .. event)
    M.events.scripts.OnEvent(M.events, event, ...)
end
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function quiet(label)
    equal(#printed, 0, label .. " (chat)")
    equal(#screen, 0, label .. " (screen)")
    equal(#sounds, 0, label .. " (sound)")
end
local function clear() printed, screen, sounds = {}, {}, {} end
local function names(list)
    local out = {}
    for index, entry in ipairs(list) do out[index] = entry.name end
    return table.concat(out, ", ")
end
local function click(row, which) row.scripts.OnClick(row, which or "LeftButton") end
local function rowTexts(M)
    local out = {}
    for _, row in ipairs(M.box.rows) do
        if row:IsShown() then out[#out + 1] = row.name.text end
    end
    return table.concat(out, ", ")
end

local firouzi = { name = "Firouzi", surname = "Asman", realm = "Realm Four", class = "ROGUE", className = "Rogue",
    faction = "Horde", level = 20 }
local azonei = { name = "Azonei", surname = "Murtaba", realm = "Realm Four", class = "WARLOCK", className = "Warlock",
    faction = "Horde", level = 31 }
local reco = { name = "Reco Veri", realm = "Realm Four", class = "WARLOCK", className = "Warlock", faction = "Horde",
    level = 12 }
local chaku = { name = "Chaku Inya", surname = "Inya", realm = "Realm Six", class = "ROGUE", className = "Rogue",
    faction = "Horde", level = 8 }

---------------------------------------------------------------------------
-- 1. Logging in writes the character down under its full name
---------------------------------------------------------------------------
local M = Session(firouzi)
fire(M, "PLAYER_ENTERING_WORLD", true, false)
local db = MiniQoLDB.mail
equal(db.notify, true, "saying when mail arrives is on to start with")
equal(db.sound, true, "with its sound")
equal(db.contacts, true, "and the box beside the Send Mail tab")
local me = db.characters["firouzi asman@Realm Four"]
assert(me, "the character is written down")
equal(me.name, "Firouzi Asman", "with its surname, as mail is addressed")
equal(me.realm, "Realm Four", "its realm")
equal(me.class, "ROGUE", "its class")
equal(me.faction, "Horde", "its faction")
equal(me.level, 20, "and its level")
player.level = 21
fire(M, "PLAYER_LEVEL_UP", 21)
equal(db.characters["firouzi asman@Realm Four"].level, 21, "kept up as it levels")
advance(10)
quiet("logging in with no mail says nothing")

---------------------------------------------------------------------------
-- 2. Mail arriving
---------------------------------------------------------------------------
unread, senders = true, { "Reco Veri" }
fire(M, "UPDATE_PENDING_MAIL")
quiet("not until the game has finished telling of it")
advance(2)
equal(printed[1], "New mail from Reco Veri.", "new mail is said in chat, with who it is from")
equal(#printed, 1, "once")
equal(screen[1].text, "New mail from Reco Veri.", "and on screen")
equal(screen[1].g, 0.82, "in the game's colour for news")
equal(#sounds, 1, "with one sound")
equal(sounds[1].kit, 18019, "a chime")
equal(sounds[1].channel, "Master", "heard with sound effects off")

clear()
fire(M, "UPDATE_PENDING_MAIL")
advance(2)
quiet("the same unread mail again is no news")

-- Another sender while the first is still unread; the game tells of it in a burst.
senders = { "Horde Auction House", "Reco Veri" }
local looked = looks
fire(M, "UPDATE_PENDING_MAIL")
fire(M, "UPDATE_PENDING_MAIL")
fire(M, "UPDATE_PENDING_MAIL")
advance(2)
equal(#printed, 1, "a burst is one piece of news")
equal(looks - looked, 1, "looked at once")
equal(printed[1], "New mail from the auction house.", "the auction house is called that, and only the new sender named")

clear()
senders = { "Azonei Murtaba", "Chaku Inya", "Horde Auction House" }
fire(M, "UPDATE_PENDING_MAIL")
advance(2)
equal(printed[1], "New mail from Azonei Murtaba and Chaku Inya.", "several new senders at once, the old one left out")

-- At the mailbox the mail is in front of you, and afterwards the game catches up.
clear()
fire(M, "MAIL_SHOW")
senders = { "Someone Else", "Azonei Murtaba", "Chaku Inya" }
fire(M, "UPDATE_PENDING_MAIL")
advance(2)
quiet("nothing is said at the mailbox")
unread, senders = false, {}
fire(M, "MAIL_CLOSED")
fire(M, "UPDATE_PENDING_MAIL")
advance(2)
quiet("nor on closing it with everything read")
unread, senders = true, { "Late Riser" }
fire(M, "UPDATE_PENDING_MAIL")
advance(2)
quiet("nor in the moment after closing it, while the game catches up")
advance(10)
senders = { "Reco Veri", "Late Riser" }
fire(M, "UPDATE_PENDING_MAIL")
advance(2)
equal(printed[1], "New mail from Reco Veri.", "after that, new mail is news again")

-- Mail where there was none, before the game says who from.
clear()
unread, senders = false, {}
fire(M, "UPDATE_PENDING_MAIL")
advance(2)
unread = true
fire(M, "UPDATE_PENDING_MAIL")
advance(2)
equal(printed[1], "You have new mail.", "mail the game hasn't named a sender for is still said")
senders = { "Slow Name" }
fire(M, "UPDATE_PENDING_MAIL")
advance(2)
equal(#printed, 1, "and its sender turning up a moment later is not a second piece of news")
advance(60)
senders = { "Slow Name", "Another One" }
fire(M, "UPDATE_PENDING_MAIL")
advance(2)
equal(printed[2], "New mail from Another One.", "someone new after that is")

-- The auction house under the game's own name for it.
clear()
BUTTON_LAG_AUCTIONHOUSE = "H\195\180tel des ventes"
senders = { "H\195\180tel des ventes de la Horde", "Slow Name", "Another One" }
fire(M, "UPDATE_PENDING_MAIL")
advance(2)
equal(printed[1], "New mail from the auction house.", "known in the game's language too")
BUTTON_LAG_AUCTIONHOUSE = nil

-- Unreadable names are left out; the settings are obeyed.
clear()
senders = { "SECRET", "Slow Name", "Another One" }
fire(M, "UPDATE_PENDING_MAIL")
advance(2)
quiet("a sender the game won't show is not named")
M:Set("sound", false)
senders = { "Quiet One", "Slow Name", "Another One" }
fire(M, "UPDATE_PENDING_MAIL")
advance(2)
equal(printed[1], "New mail from Quiet One.", "with the sound off it is still said")
equal(#sounds, 0, "silently")
M:Set("sound", true)
clear()
M:Set("notify", false)
senders = { "Unheard", "Quiet One", "Slow Name" }
fire(M, "UPDATE_PENDING_MAIL")
advance(2)
quiet("turned off, nothing is said")
M:Set("notify", true)
fire(M, "UPDATE_PENDING_MAIL")
advance(2)
quiet("and turning it back on doesn't bring up what arrived meanwhile")

-- A game without the chime: the whisper sound instead.
mute[18019] = true
senders = { "Bell Ringer", "Unheard", "Quiet One" }
fire(M, "UPDATE_PENDING_MAIL")
advance(2)
equal(sounds[1] and sounds[1].kit, 3081, "another sound where the chime won't play")
mute[18019] = nil

---------------------------------------------------------------------------
-- 3. An auction selling
---------------------------------------------------------------------------
clear()
unread, senders = false, {}
fire(M, "UPDATE_PENDING_MAIL")
advance(2)
fire(M, "CHAT_MSG_SYSTEM", "You have learned a new spell: Sprint.")
fire(M, "CHAT_MSG_SYSTEM", "SECRET")
fire(M, "CHAT_MSG_SYSTEM", nil)
quiet("other lines from the game, or none, are nothing")
fire(M, "CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Linen Cloth.")
equal(screen[1].text, "Auction sold: Linen Cloth.", "a sale is marked on screen with what sold")
equal(#printed, 0, "not in chat, where the game has just said it")
equal(sounds[1].kit, 120, "with the clink of coin")
-- The auction house's letter about it arrives a moment later.
clear()
unread, senders = true, { "Horde Auction House" }
fire(M, "UPDATE_PENDING_MAIL")
advance(2)
quiet("the letter for a sale just marked is not said again")
-- A letter from the auction house with no sale behind it is news.
unread, senders = false, {}
fire(M, "UPDATE_PENDING_MAIL")
advance(60)
unread, senders = true, { "Horde Auction House" }
fire(M, "UPDATE_PENDING_MAIL")
advance(2)
equal(printed[1], "New mail from the auction house.", "auction house mail with no sale just marked is said")
clear()
M:Set("notify", false)
fire(M, "CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Copper Bar.")
quiet("turned off, a sale is not marked")
M:Set("notify", true)

---------------------------------------------------------------------------
-- 4. Logging in, reloading and travelling with mail waiting
---------------------------------------------------------------------------
clear()
unread, senders = true, { "Azonei Murtaba", "Horde Auction House" }
M = Session(firouzi)
fire(M, "PLAYER_ENTERING_WORLD", true, false)
fire(M, "UPDATE_PENDING_MAIL")
advance(3)
quiet("nothing in the first moments of logging in")
advance(5)
equal(printed[1], "You have unread mail from Azonei Murtaba and the auction house.", "then what is waiting is said")
equal(#printed, 1, "once")
equal(#sounds, 1, "with its sound")
fire(M, "UPDATE_PENDING_MAIL")
advance(2)
equal(#printed, 1, "and not again as new mail")

-- A reload is not a login. The game may tell of the mail before it says the
-- world is entered.
clear()
M = Session(firouzi)
fire(M, "UPDATE_PENDING_MAIL")
advance(2)
quiet("mail told of before the world is entered is not news")
fire(M, "PLAYER_ENTERING_WORLD", false, true)
fire(M, "UPDATE_PENDING_MAIL")
advance(10)
quiet("a reload with mail waiting says nothing")
senders = { "Reco Veri", "Azonei Murtaba", "Horde Auction House" }
fire(M, "UPDATE_PENDING_MAIL")
advance(2)
equal(printed[1], "New mail from Reco Veri.", "though mail arriving afterwards is said")
-- Nor is walking into a city.
clear()
fire(M, "PLAYER_ENTERING_WORLD", false, false)
senders = { "City Crier", "Reco Veri", "Azonei Murtaba" }
fire(M, "UPDATE_PENDING_MAIL")
advance(3)
quiet("arriving somewhere, the game is only catching up")

-- Logging in with mail the game names nobody for.
clear()
unread, senders = true, {}
M = Session(firouzi)
fire(M, "PLAYER_ENTERING_WORLD", true, false)
advance(8)
equal(printed[1], "You have unread mail.", "waiting mail with no sender named is still said")
senders = { "Named Later" }
fire(M, "UPDATE_PENDING_MAIL")
advance(2)
equal(#printed, 1, "and the name turning up is not more news")

-- The game's line for a sale in another language, with a numbered place for the item.
clear()
ERR_AUCTION_SOLD_S = "Un acheteur a \195\169t\195\169 trouv\195\169 pour votre vente : %1$s."
M = Session(firouzi)
fire(M, "CHAT_MSG_SYSTEM", "Un acheteur a \195\169t\195\169 trouv\195\169 pour votre vente : \195\137toffe de lin.")
equal(screen[1] and screen[1].text, "Auction sold: \195\137toffe de lin.", "a sale is known by the game's own wording")
fire(M, "CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Linen Cloth.")
equal(#screen, 1, "and not by English where the game doesn't speak it")
ERR_AUCTION_SOLD_S = nil
unread, senders = false, {}

---------------------------------------------------------------------------
-- 5. The other characters: each as it logs in, and the ones Syndicator knows
---------------------------------------------------------------------------
clear()
M = Session(azonei)
fire(M, "PLAYER_ENTERING_WORLD", true, false)
equal(names(M:Alts()), "Firouzi Asman", "one of yours that has logged in is listed for the others")
M = Session(reco)
fire(M, "PLAYER_ENTERING_WORLD", true, false)
equal(MiniQoLDB.mail.characters["reco veri@Realm Four"].name, "Reco Veri", "a name the game gives whole is kept whole")
equal(names(M:Alts()), "Azonei Murtaba, Firouzi Asman", "the highest level first")
M = Session(chaku)
fire(M, "PLAYER_ENTERING_WORLD", true, false)
equal(MiniQoLDB.mail.characters["chaku inya@Realm Six"].name, "Chaku Inya", "a surname given twice over is written once")
equal(names(M:Alts()), "", "a character on another realm is not offered to this one")

-- Syndicator has written some down already, by ruleset rather than realm.
M = Session(firouzi)
fire(M, "PLAYER_ENTERING_WORLD", true, false)
local characters = {
    ["Firouzi Asman-PvP"] = { details = { character = "Firouzi Asman", realmNormalized = "PvP", className = "ROGUE", faction = "Horde" } },
    ["Azonei Murtaba-PvP"] = { details = { character = "Azonei Murtaba", realmNormalized = "PvP", className = "WARLOCK", faction = "Horde" } },
    ["Chaku Inya-PvP"] = { details = { character = "Chaku Inya", realmNormalized = "PvP", className = "ROGUE", faction = "Horde" } },
    ["Elsewhere Ella-PvE"] = { details = { character = "Elsewhere Ella", realmNormalized = "PvE", className = "ROGUE", faction = "Horde" } },
    ["Broken-PvP"] = { details = { realmNormalized = "PvP" } },
}
Syndicator = { API = {
    GetAllCharacters = function()
        local keys = {}
        for key in pairs(characters) do keys[#keys + 1] = key end
        table.sort(keys)
        return keys
    end,
    GetByCharacterFullName = function(key) return characters[key] end,
    GetCurrentCharacter = function() return "Firouzi Asman-PvP" end,
} }
equal(names(M:Alts()), "Azonei Murtaba, Reco Veri, Chaku Inya",
    "the ones Syndicator knows on this ruleset are added, without their logging in; none twice; not yourself")
equal(M:Alts()[1].level, 31, "what the character wrote down itself is kept")
equal(M:Alts()[3].class, "ROGUE", "and Syndicator's are given their class")
Syndicator.API.GetCurrentCharacter = function() error("not ready") end
equal(names(M:Alts()), "Azonei Murtaba, Reco Veri", "a Syndicator that can't answer costs nothing but its names")
Syndicator = nil

---------------------------------------------------------------------------
-- 6. Sending: who mail goes to is remembered once the game says it went
---------------------------------------------------------------------------
SendMail("  bob  builder ", "Hello", "Body")
equal(sent[1], "  bob  builder ", "the game sends as before")
equal(next(MiniQoLDB.mail.sent), nil, "nothing is remembered until the mail has gone")
fire(M, "MAIL_SEND_SUCCESS")
local bob = MiniQoLDB.mail.sent["Realm Four"]["bob builder"]
assert(bob, "a mail that went is remembered, on its realm")
equal(bob.name, "Bob Builder", "the name tidied")
equal(bob.count, 1, "counted")
equal(bob.last, CLOCK, "and dated")
fire(M, "MAIL_SEND_SUCCESS")
equal(bob.count, 1, "the game saying so twice is one mail")
SendMail("Nobody Here", "Hello", "Body")
fire(M, "MAIL_FAILED")
fire(M, "MAIL_SEND_SUCCESS")
equal(MiniQoLDB.mail.sent["Realm Four"]["nobody here"], nil, "a mail that failed is not remembered")
SendMail("Left Behind", "Hello", "Body")
fire(M, "MAIL_CLOSED")
fire(M, "MAIL_SEND_SUCCESS")
equal(MiniQoLDB.mail.sent["Realm Four"]["left behind"], nil, "nor one left unsent on closing the mailbox")
SendMail("SECRET", "Hello", "Body")
fire(M, "MAIL_SEND_SUCCESS")
SendMail("   ", "Hello", "Body")
fire(M, "MAIL_SEND_SUCCESS")
local count = 0
for _ in pairs(MiniQoLDB.mail.sent["Realm Four"]) do count = count + 1 end
equal(count, 1, "nor a name that can't be read, or isn't one")

advance(3 * 86400)
for _ = 1, 3 do
    SendMail("Carla Cook", "Pie", "")
    fire(M, "MAIL_SEND_SUCCESS")
end
SendMail("Aaron Able", "Hi", "")
fire(M, "MAIL_SEND_SUCCESS")
advance(60)
SendMail("\195\169owyn of rohan", "Hi", "")
fire(M, "MAIL_SEND_SUCCESS")
SendMail("bob builder", "Again", "")
fire(M, "MAIL_SEND_SUCCESS")
SendMail("reco veri", "Bags", "")
fire(M, "MAIL_SEND_SUCCESS")
equal(MiniQoLDB.mail.sent["Realm Four"]["\195\169owyn of rohan"].name, "\195\169owyn Of Rohan",
    "a name is tidied only where that is safe")
equal(names(M:People()), "Carla Cook, Bob Builder, \195\169owyn Of Rohan, Aaron Able",
    "the people mailed lately, the most mailed first, then the most lately; your own characters not among them")
-- One of yours whose name isn't spelled the way a typed one is tidied.
MiniQoLDB.mail.characters["ana deluca@Realm Four"] = { name = "Ana DeLuca", realm = "Realm Four", class = "ROGUE", level = 5 }
SendMail("ana deluca", "Hi", "")
fire(M, "MAIL_SEND_SUCCESS")
equal(MiniQoLDB.mail.sent["Realm Four"]["ana deluca"].name, "Ana DeLuca", "one of yours keeps its own spelling")
MiniQoLDB.mail.characters["ana deluca@Realm Four"], MiniQoLDB.mail.sent["Realm Four"]["ana deluca"] = nil, nil
equal(names(M:Alts()), "Reco Veri, Azonei Murtaba", "one of yours you mail comes first among yours")
equal(MiniQoLDB.mail.sent["Realm Four"]["reco veri"].name, "Reco Veri", "under the name it gave itself")
equal(M:People()[2].count, 2, "with how often")

-- The recent past: a month. Longer ago is off the list, and much longer forgotten.
advance(29 * 86400)
SendMail("Carla Cook", "More pie", "")
fire(M, "MAIL_SEND_SUCCESS")
advance(2 * 86400)
equal(names(M:People()), "Carla Cook", "someone not mailed for a month is off the list")
assert(MiniQoLDB.mail.sent["Realm Four"]["bob builder"], "though not yet forgotten")
SendMail("Bob Builder", "Back", "")
fire(M, "MAIL_SEND_SUCCESS")
equal(names(M:People()), "Carla Cook, Bob Builder", "and is back on it when mailed again")
equal(M:People()[2].count, 3, "with the count carried on")
advance(121 * 86400)
M = Session(firouzi)
equal(MiniQoLDB.mail.sent["Realm Four"], nil, "after four months unmailed, everyone is forgotten")

-- Another realm's people are its own.
SendMail("Carla Cook", "Pie", "")
fire(M, "MAIL_SEND_SUCCESS")
SendMail("Dan Dyer", "Dye", "")
fire(M, "MAIL_SEND_SUCCESS")
M = Session(chaku)
equal(names(M:People()), "", "people mailed on one realm are not offered on another")
M = Session(firouzi)
equal(names(M:People()), "Carla Cook, Dan Dyer", "and are still there on their own")

-- A game with no SendMail of its own to watch: the Send button's function is.
M = Session(firouzi)
SendMail = nil
SendMailFrame_SendMail = function() end
BuildMailbox()
local N = Session(firouzi)
SendMail = nil
N.sendingHooked = nil
assert(N:HookSending(), "the Send button's own function is watched instead")
SendMailNameEditBox:SetText("erin eel")
SendMailFrame_SendMail()
fire(N, "MAIL_SEND_SUCCESS")
equal(MiniQoLDB.mail.sent["Realm Four"]["erin eel"].name, "Erin Eel", "and the To field read for who it went to")
N:Forget("erin eel")
SendMailFrame_SendMail = nil
N.sendingHooked = nil
assert(not N:HookSending(), "with neither, nothing is watched and nothing breaks")
MailFrame, SendMailFrame, SendMailNameEditBox, SendMailSubjectEditBox = nil, nil, nil, nil
UIParent.children = {}

---------------------------------------------------------------------------
-- 7. The box beside the Send Mail tab
---------------------------------------------------------------------------
M = Session(firouzi)
fire(M, "PLAYER_ENTERING_WORLD", false, true)
fire(M, "MAIL_SHOW")
equal(M.box, nil, "no mailbox window yet, no box, and no error")
BuildMailbox()
fire(M, "MAIL_SHOW")
local box = M.box
assert(box, "the box is made when the mailbox opens")
equal(box.parent, SendMailFrame, "as part of the Send Mail page, so it comes and goes with that tab")
equal(box:IsShown(), true, "shown")
equal(rowTexts(M), "Azonei Murtaba, Reco Veri, Carla Cook, Dan Dyer", "your characters, then the people you have mailed")
equal(box.heads[1]:IsShown() and box.heads[2]:IsShown(), true, "each under its heading")
equal(box.rows[1].name.color[3], 0.93, "your own in their class colours")
equal(box.rows[3].name.color[1], 0.87, "the others plainly")
equal(box.empty:IsShown(), false, "with no word about nobody")
equal(box.points[1][2], MailFrame, "it sits beside the mailbox")
equal(box.points[1][3], "TOPRIGHT", "at its top right")

-- A click addresses the mail.
click(box.rows[3])
equal(SendMailNameEditBox.text, "Carla Cook", "a click puts the name in the To field")
equal(SendMailSubjectEditBox.focused, true, "and moves on to the subject")
equal(SendMailSubjectEditBox.text, "share", "with \"share\" as the subject")
equal(SendMailSubjectEditBox.highlighted, true, "selected, so typing replaces it")
click(box.rows[1])
equal(SendMailNameEditBox.text, "Azonei Murtaba", "one of yours the same")
equal(SendMailSubjectEditBox.text, "share", "subject and all")

-- The subject is only written over when it is not yours. The game says which
-- changes to the field were typed.
local function subject(text, typed)
    SendMailSubjectEditBox:SetText(text)
    SendMailSubjectEditBox.scripts.OnTextChanged(SendMailSubjectEditBox, typed)
end
subject("Linen Cloth", false)
click(box.rows[3])
equal(SendMailSubjectEditBox.text, "share", "the name of an attached item, which the game wrote, gives way")
subject("for your tailoring", true)
SendMailSubjectEditBox.highlighted = nil
click(box.rows[1])
equal(SendMailNameEditBox.text, "Azonei Murtaba", "after typing a subject, a click still addresses the mail")
equal(SendMailSubjectEditBox.text, "for your tailoring", "and leaves the subject you typed")
equal(SendMailSubjectEditBox.highlighted, nil, "unselected")
subject("for your tailoring", false)
click(box.rows[1])
equal(SendMailSubjectEditBox.text, "for your tailoring", "which stays yours however the field is redrawn")
subject("", true)
click(box.rows[3])
equal(SendMailSubjectEditBox.text, "share", "rubbed out, it is written again")
subject("gold for the mount", true)
subject("", false)
subject("Copper Ore", false)
click(box.rows[3])
equal(SendMailSubjectEditBox.text, "share", "and a mail sent clears the field for the next one")
local firstSubject = SendMailSubjectEditBox
subject("typed in the old field", true)
SendMailSubjectEditBox = CreateFrame("EditBox", nil, SendMailFrame)
click(box.rows[3])
equal(SendMailSubjectEditBox.text, "share", "a subject field built afresh is written to")
subject("typed here", true)
click(box.rows[3])
equal(SendMailSubjectEditBox.text, "typed here", "and watched in its turn")
SendMailSubjectEditBox = CreateFrame("EditBox", nil, SendMailFrame)
fire(M, "MAIL_SHOW")
subject("typed first", true)
click(box.rows[3])
equal(SendMailSubjectEditBox.text, "typed first", "a subject typed before any name is clicked is kept as well")
SendMailSubjectEditBox = nil
click(box.rows[3])
equal(SendMailNameEditBox.text, "Carla Cook", "with no subject field at all a click still addresses the mail")
SendMailSubjectEditBox = firstSubject
subject("", false)
box.rows[3].scripts.OnEnter(box.rows[3])
equal(GameTooltip.title, "Carla Cook", "pointing at a name says who")
assert(GameTooltip.lines[1]:find("Mailed 1 time", 1, true), "how often they were mailed: " .. GameTooltip.lines[1])
assert(GameTooltip.lines[1]:find("Right-click", 1, true), "and how to take them off")
box.rows[1].scripts.OnEnter(box.rows[1])
assert(GameTooltip.lines[1]:find("Level 31, one of yours", 1, true), "one of yours says so: " .. GameTooltip.lines[1])
assert(not GameTooltip.lines[1]:find("Right-click", 1, true), "and can't be taken off")

-- Sending to someone new adds them while the box is open; a right-click removes.
SendMail("Fay Fisher", "Fish", "")
fire(M, "MAIL_SEND_SUCCESS")
equal(rowTexts(M), "Azonei Murtaba, Reco Veri, Carla Cook, Dan Dyer, Fay Fisher", "someone just mailed is listed at once")
click(box.rows[4], "RightButton")
equal(rowTexts(M), "Azonei Murtaba, Reco Veri, Carla Cook, Fay Fisher", "a right-click takes a person off the list")
equal(MiniQoLDB.mail.sent["Realm Four"]["dan dyer"], nil, "for good")
SendMail("Azonei Murtaba", "Gold", "")
fire(M, "MAIL_SEND_SUCCESS")
SendMailNameEditBox:SetText("")
click(box.rows[1], "RightButton")
equal(rowTexts(M), "Azonei Murtaba, Reco Veri, Carla Cook, Fay Fisher", "one of yours stays")
equal(MiniQoLDB.mail.sent["Realm Four"]["azonei murtaba"].count, 1, "with how often it was mailed")
equal(SendMailNameEditBox.text, "", "and a right-click addresses nothing")

-- No more rows than fit.
for index = 1, 12 do
    SendMail("Extra Person" .. string.char(64 + index), "Hi", "")
    fire(M, "MAIL_SEND_SUCCESS")
end
equal(box.count, 2 + 8, "the list stops at eight people")
for index = 1, 12 do M:Forget("extra person" .. string.char(96 + index)) end
equal(box.count, 4, "and shrinks again as they go")

-- Turned off and on.
features["mail.contacts"].set(false)
equal(box:IsShown(), false, "turned off, the box is hidden")
features["mail.contacts"].set(true)
equal(box:IsShown(), true, "and back")

-- Where it sits: beside the mailbox, under another addon's panel if one is there.
local other = CreateFrame("Frame", nil, UIParent)
other:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 8, -2)
other.rect = { 362, 420, 660, 698 }
local inside = CreateFrame("Frame", nil, UIParent)
inside:SetPoint("TOPLEFT", MailFrame, "TOPLEFT", 10, -10)
inside.rect = { 26, 100, 300, 690 }
local hidden = CreateFrame("Frame", nil, UIParent)
hidden:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 8, -2)
hidden.rect = { 362, 50, 660, 698 }
hidden:Hide()
box.scripts.OnShow(box)
equal(box.points[1][2], other, "with another addon's panel on that edge, the box goes under it")
equal(box.points[1][3], "BOTTOMLEFT", "at its foot")
other:Hide()
advance(1)
equal(box.points[1][2], MailFrame, "and back beside the mailbox once that panel has gone")
other:Show()

-- Dragged: it stays where it was put, measured from the mailbox.
box.rect = { 400, 300, 572, 650 }
box.scripts.OnDragStop(box)
equal(MiniQoLDB.mail.place.x, 400 - 354, "where it was dragged to is kept, across from the mailbox's right edge")
equal(MiniQoLDB.mail.place.y, 650 - 700, "and down from its top")
equal(box.points[1][2], MailFrame, "and it is pinned to the mailbox there")
equal(box.points[1][4], 46, "at that distance")
box.scripts.OnShow(box)
equal(box.points[1][2], MailFrame, "another addon's panel no longer moves it")
equal(features["mail.place"].available(), true, "the settings offer to put it back")
features["mail.place"].run()
equal(MiniQoLDB.mail.place, nil, "which forgets the place")
equal(box.points[1][2], other, "and puts it back where it started")
equal(features["mail.place"].available(), false, "the offer gone")

---------------------------------------------------------------------------
-- 8. The settings page
---------------------------------------------------------------------------
for _, id in ipairs({ "mail.notify", "mail.sound", "mail.contacts", "mail.known", "mail.forget", "mail.place" }) do
    assert(features[id], id .. " is on the settings page")
    equal(features[id].page, "mail", id .. " on the Mail page")
end
equal(features["mail.notify"].get(), true, "the page reads the settings")
features["mail.notify"].set(false)
equal(MiniQoLDB.mail.notify, false, "and writes them")
equal(features["mail.sound"].available(), false, "the sound has nothing to go with while that is off")
features["mail.notify"].set(true)
equal(features["mail.sound"].available(), true, "and does again")
assert(features["mail.known"].get():find("2 of your other characters and 2 other people", 1, true),
    "who is listed is counted: " .. features["mail.known"].get())
equal(features["mail.forget"].available(), true, "the people mailed can be forgotten")
features["mail.forget"].run()
equal(popup, "MINIQOL_MAIL_FORGET", "after asking")
clear()
MiniQoLDB.mail.sent["Realm Six"] = { ["far away"] = { name = "Far Away", count = 1, last = CLOCK } }
StaticPopupDialogs.MINIQOL_MAIL_FORGET.OnAccept()
equal(MiniQoLDB.mail.sent["Realm Four"], nil, "all of them, on this realm")
assert(MiniQoLDB.mail.sent["Realm Six"], "and nobody on another")
assert(printed[1]:find("Forgot 3 names", 1, true), "saying how many: " .. tostring(printed[1]))
equal(rowTexts(M), "Azonei Murtaba, Reco Veri", "your own characters stay listed")
equal(features["mail.forget"].available(), false, "with nobody left to forget")

-- Nobody at all: the box says how names get there.
MiniQoLDB.mail.characters = {}
M:RememberMe()
M:PaintBox()
equal(rowTexts(M), "", "with nobody to list")
equal(box.empty:IsShown(), true, "the box says how names come to be there")
assert(features["mail.known"].get():find("Nobody is listed yet", 1, true), "and so does the settings page")

print("Mail: new mail and waiting mail said once with who from, sales marked, quiet at the mailbox; alts by full name, people mailed lately, a click to address")

-- Alt Mail's picker and free-text field edit the same group recipient.
tinsert, UISpecialFrames, SlashCmdList = table.insert, {}, {}
strtrim = function(text) return text:match("^%s*(.-)%s*$") end
strlower = string.lower
ItemLocation = { CreateEmpty = function() return {} end }
function methods:SetDefaultText(value) self.defaultText = value end
function methods:SetupMenu(generate) self.generate = generate end
function methods:SetEnabled(value) self.enabled = value end
function methods:IsEnabled() return self.enabled end
function methods:SetText(value)
    self.text = value
    if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
end

local ns = { Mail = M, RegisterFeature = noop }
assert(loadfile(root .. "/AltMail/Categories.lua"))("MiniQoL", ns)
local altMail = ns.AltMail
altMail.GetMarkedItems = function() return {} end
altMail.GetMarkShortcut, altMail.IsSending, altMail.IsMailboxOpen = noop, noop, noop
assert(loadfile(root .. "/AltMail/Panel.lua"))("MiniQoL", ns)
altMail.TogglePanel()
local picker, input, labelInput, saveButton, unlinkButton
for _, widget in ipairs(MiniQoLAltMailPanel.children) do
    if widget.defaultText == "Choose alt" then picker = widget end
    if widget.kind == "EditBox" then
        if widget.scripts.OnEnterPressed then input = widget else labelInput = widget end
    end
    if widget.text == "Save" then saveButton = widget end
    if widget.text == "Unlink" then unlinkButton = widget end
end
local function openPicker()
    local menu = { names = {}, actions = {} }
    function menu:CreateTitle(text) self.title = text end
    function menu:CreateButton(name, selectAlt)
        self.names[#self.names + 1] = name
        self.actions[name] = selectAlt
    end
    function menu:SetScrollMode(height) self.scroll = height end
    picker.generate(picker, menu)
    return menu
end
equal(openPicker().title, "No known alts yet", "empty roster")
equal(labelInput:GetText(), "", "the label starts blank")
input:SetText("Custom Name")
assert(saveButton:IsEnabled(), "only a recipient is required")
click(saveButton)
local group = altMail.GetGroup(1)
equal(altMail.GetRoute(nil, group).recipient, "Custom Name", "custom names work with an empty roster")
equal(group.name, "Custom Name", "the recipient is the default display name")
assert(labelInput:GetText() == "" and not saveButton:IsEnabled(), "the default display name stays out of the label field")

local others = { "Ada Mail", "Bea Mail" }
for i = 1, 12 do others[#others + 1] = "Alt " .. i end
for _, name in ipairs(others) do
    db.characters[name] = { name = name, realm = player.realm }
end
local menu = openPicker()
equal(#menu.names, #others, "all alts are available, including beyond the mailbox sidebar limit")
assert(menu.scroll and not menu.actions[M.me], "long rosters scroll and exclude the sender")
menu.actions["Ada Mail"]()
equal(input:GetText(), "Ada Mail", "picking an alt fills the full name")
equal(altMail.GetRoute(nil, group).recipient, "Custom Name", "picking waits for Save")
assert(saveButton:IsEnabled())
click(saveButton)
equal(altMail.GetRoute(nil, group).recipient, "Ada Mail", "saves the selected alt")
equal(altMail.GetGroup(1).name, "Ada Mail", "the display name follows recipient changes")
labelInput:SetText("Blacksmith")
assert(saveButton:IsEnabled(), "a label-only edit can be saved")
click(saveButton)
input:SetText("Another Name")
click(saveButton)
equal(altMail.GetRoute(nil, group).recipient, "Another Name", "a custom name can replace a picked alt")
equal(altMail.GetGroup(1).name, "Blacksmith", "an explicit label survives a recipient change")
labelInput:SetText("   ")
assert(saveButton:IsEnabled(), "clearing the label can be saved")
click(saveButton)
equal(altMail.GetGroup(1).name, "Another Name", "clearing the label restores the current recipient")
click(unlinkButton)
equal(altMail.GetGroup(1).name, "Mail Group 1", "an unlinked, unlabeled group returns to its numbered name")
assert(not saveButton:IsEnabled(), "a recipient is still required")
print("Alt Mail recipient picker: empty and long rosters, full names, custom entries and explicit saving passed")
