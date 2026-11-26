local _, ns = ...
-- Mail: a word when mail arrives, and the people you send to listed beside the
-- Send Mail tab.
--
-- Arriving. The game marks unread mail with an icon by the minimap and says
-- nothing. Here it is said, in chat and on screen with a sound: who new mail
-- is from when it arrives, and what is waiting when you log in. The game tells
-- addons only whether there is unread mail and who the last three senders
-- were, so news is a sender who wasn't there before, or mail where there was
-- none; a second letter from someone whose first is still unread can't be
-- told apart from the first. An auction selling is different: the game
-- announces each sale in chat as it happens, and that is marked on screen with
-- a sound of its own.
--
-- Sending. A box beside the Send Mail tab lists your other characters and the
-- people you have mailed in the last month, the ones mailed most first. A
-- click puts a name in the To field. Characters on this game carry a surname
-- and mail is addressed with it ("Ana Smith"), so each of yours is written
-- down in full as it logs in. Syndicator and Questie can also supply names
-- before those characters log in with MiniQoL.
local Mail = {}
ns.Mail = Mail
local T = ns.Theme

local SETTLE = 1            -- seconds: the game tells of pending mail in bursts
local QUIET = 6             -- after arriving in the world or leaving the mailbox, a change is no news
local NAMING = 30           -- mail said to have arrived before the game named its sender
local SALE_ECHO = 15        -- a sale just marked isn't said again as mail from the auction house
local DAY = 86400
local RECENT_DAYS = 30      -- "the recent past"
local KEPT_DAYS = 120       -- after which someone is forgotten altogether
local MAX_ALTS, MAX_PEOPLE = 10, 8
local SUBJECT = "share"    -- what a click on a name writes as the subject
local BOX_W, HEADER_H, HEAD_H, ROW_H, PAD, GAP = 172, 22, 16, 18, 8, 6
local NEWS = { 1, 0.82, 0 } -- the game's own colour for a line of news

local function Readable(value)
    return not (issecretvalue and issecretvalue(value)) and value ~= nil
end

local function Text(value)
    return Readable(value) and type(value) == "string" and value ~= "" and value or nil
end

-- Small letters for the plain alphabet only. A name's other letters are more
-- than one byte each, and lowering those a byte at a time would spoil them.
local function Lower(text)
    return (text:gsub("[A-Z]", string.lower))
end

local Characters = ns.Characters
local Fold, Realm = Characters.Fold, Characters.Realm
Mail.PlayerName = Characters.PlayerName

-- A name as typed into the To field, tidied: "reco  veri " is "Reco Veri".
-- Only a plain small letter at the start of a word is raised; anything else
-- is left as it was typed, since the game accepted it.
local function Tidy(name)
    name = Text(name)
    if not name then return nil end
    name = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    if name == "" then return nil end
    return (name:gsub("[^%s%-]+", function(word)
        local first = word:sub(1, 1)
        return first:match("[a-z]") and first:upper() .. word:sub(2) or word
    end))
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
function Mail:Initialize()
    local db = ns.db
    if type(db.mail) ~= "table" then db.mail = {} end
    self.db = db.mail
    for key, default in pairs({ notify = true, sound = true, contacts = true }) do
        if self.db[key] == nil then self.db[key] = default end
    end
    if type(self.db.sent) ~= "table" then self.db.sent = {} end
    self:AdoptNamelessBook()
    self.known = { has = false, senders = {} }
    -- Quiet from the start: the game may tell of mail before it says the
    -- world is entered, and what is waiting is said in its own time.
    self.quietUntil = GetTime() + QUIET
    self:Prune()
    return self
end

-- While Forever's realms answered no name, mail sent was filed under "". Once
-- the realm has a key (Characters.Realm), that book joins this realm's.
function Mail:AdoptNamelessBook()
    local realm, old = Realm(), self.db.sent[""]
    if realm == "" or type(old) ~= "table" then return end
    local book = type(self.db.sent[realm]) == "table" and self.db.sent[realm] or {}
    for key, entry in pairs(old) do
        local kept = book[key]
        if type(kept) ~= "table" then
            book[key] = entry
        elseif type(entry) == "table" then
            kept.count = (kept.count or 0) + (entry.count or 0)
            if (entry.last or 0) > (kept.last or 0) then kept.last, kept.name = entry.last, entry.name or kept.name end
        end
    end
    self.db.sent[realm], self.db.sent[""] = book, nil
end

-- Drops anyone not mailed in a long while, and what isn't a record at all.
function Mail:Prune()
    local oldest = time() - KEPT_DAYS * DAY
    for realm, book in pairs(self.db.sent) do
        if type(book) ~= "table" then
            self.db.sent[realm] = nil
        else
            for key, entry in pairs(book) do
                if type(entry) ~= "table" or not Text(entry.name) or (entry.last or 0) < oldest then book[key] = nil end
            end
            if next(book) == nil then self.db.sent[realm] = nil end
        end
    end
end

function Mail:Get(key)
    return self.db ~= nil and self.db[key] ~= false
end

function Mail:Set(key, value)
    if not self.db then return end
    self.db[key] = value and true or false
    if key == "contacts" then self:RefreshBox() end
end

---------------------------------------------------------------------------
-- Your characters
---------------------------------------------------------------------------
function Mail:Book()
    return self.db and self.db.sent[Realm()] or {}
end

-- Everyone of yours on this realm but the one you are on: the most mailed
-- first, then the highest level.
function Mail:Alts()
    local book, list = self:Book(), {}
    for _, record in ipairs(Characters:Alts()) do
        local folded = Fold(record.name)
        local entry = book[folded]
        list[#list + 1] = { key = folded, name = record.name, class = record.class, faction = record.faction,
            level = record.level, alt = true, count = type(entry) == "table" and entry.count or 0,
            last = type(entry) == "table" and entry.last or 0 }
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
        return a.name < b.name
    end)
    return list
end

---------------------------------------------------------------------------
-- The people you send to
---------------------------------------------------------------------------
-- A mail to `name` went through.
function Mail:Sent(name)
    name = Tidy(name)
    if not name or not self.db then return false end
    local realm = Realm()
    local book = self.db.sent[realm]
    if type(book) ~= "table" then
        book = {}
        self.db.sent[realm] = book
    end
    local key = Fold(name)
    -- One of your own keeps the name it gave itself.
    for _, alt in ipairs(self:Alts()) do
        if alt.key == key then name = alt.name end
    end
    local entry = type(book[key]) == "table" and book[key] or { count = 0 }
    entry.name, entry.count, entry.last = name, (entry.count or 0) + 1, time()
    book[key] = entry
    self:PaintBox()
    return true
end

-- Whoever else was mailed in the last month: the most mailed first, then the
-- most lately.
function Mail:People(alts)
    local mine, list, now = {}, {}, time()
    local me = Characters.PlayerName()
    if me then mine[Fold(me)] = true end
    for _, alt in ipairs(alts or self:Alts()) do mine[alt.key] = true end
    for key, entry in pairs(self:Book()) do
        if type(entry) == "table" and Text(entry.name) and not mine[key]
            and now - (entry.last or 0) <= RECENT_DAYS * DAY then
            list[#list + 1] = { key = key, name = entry.name, count = entry.count or 1, last = entry.last or 0 }
        end
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        if a.last ~= b.last then return a.last > b.last end
        return a.name < b.name
    end)
    return list
end

function Mail:Forget(key)
    local book = self.db and self.db.sent[Realm()]
    if type(book) ~= "table" or not book[key] then return false end
    book[key] = nil
    self:PaintBox()
    ns:Refresh()
    return true
end

function Mail:ForgetPeople()
    local count = 0
    for _ in pairs(self:Book()) do count = count + 1 end
    if self.db then self.db.sent[Realm()] = nil end
    self:PaintBox()
    ns:Refresh()
    return count
end

function Mail:Summary()
    local alts = self:Alts()
    local people = self:People(alts)
    if #alts == 0 and #people == 0 then
        return "Nobody is listed yet. Your other characters are added as they log in, and people as you send them mail."
    end
    return ("%d of your other characters and %d other %s you have mailed in the last %d days are listed.")
        :format(#alts, #people, #people == 1 and "person" or "people", RECENT_DAYS)
end

-- The game's own sending is watched for who a mail goes to; the name is kept
-- once the game says the mail went.
function Mail:HookSending()
    if self.sendingHooked then return true end
    if type(SendMail) == "function" then
        hooksecurefunc("SendMail", function(recipient) self.pending = Text(recipient) end)
    elseif type(SendMailFrame_SendMail) == "function" then
        hooksecurefunc("SendMailFrame_SendMail", function()
            self.pending = SendMailNameEditBox and Text(SendMailNameEditBox:GetText()) or nil
        end)
    else
        return false
    end
    self.sendingHooked = true
    return true
end

---------------------------------------------------------------------------
-- The box beside the Send Mail tab
---------------------------------------------------------------------------
local function ClassColor(class)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then return color.r, color.g, color.b end
    return T.Color(T.TEXT)
end

local function Ago(stamp)
    local days = math.floor((time() - stamp) / DAY)
    if days <= 0 then return "today" end
    return days == 1 and "yesterday" or days .. " days ago"
end

local function RowTitle(row)
    return row.entry and row.entry.name
end

local function RowBody(row)
    local entry = row.entry
    if not entry then return nil end
    local lines = {}
    if entry.alt and entry.level then lines[#lines + 1] = "Level " .. entry.level .. ", one of yours." end
    if entry.alt and not entry.level then lines[#lines + 1] = "One of yours." end
    if (entry.count or 0) > 0 then
        lines[#lines + 1] = ("Mailed %d %s, last %s."):format(entry.count, entry.count == 1 and "time" or "times",
            Ago(entry.last))
    end
    lines[#lines + 1] = entry.alt and "Click to address this mail to them."
        or "Click to address this mail to them. Right-click to take them off this list."
    return table.concat(lines, "\n")
end

-- A subject you typed is yours, and a click on a name leaves it alone. One the
-- game wrote (the name of an attached item) or an earlier click wrote is not.
function Mail:WatchSubject()
    local subject = SendMailSubjectEditBox
    if not (subject and subject.HookScript) or self.subjectWatched == subject then return end
    self.subjectWatched = subject
    self.subjectTyped = nil
    subject:HookScript("OnTextChanged", function(box, userInput)
        if (box:GetText() or "") == "" then
            self.subjectTyped = nil
        elseif userInput then
            self.subjectTyped = true
        end
    end)
end

-- Puts the name in the To field and "share" in the subject, selected so that
-- typing replaces it, and leaves the cursor there.
function Mail:Pick(entry, button)
    if not entry then return false end
    if button == "RightButton" then
        return not entry.alt and self:Forget(entry.key)
    end
    if not SendMailNameEditBox then return false end
    SendMailNameEditBox:SetText(entry.name)
    local subject = SendMailSubjectEditBox
    if subject then
        self:WatchSubject()
        if subject.SetFocus then subject:SetFocus() end
        if not self.subjectTyped then
            subject:SetText(SUBJECT)
            if subject.HighlightText then subject:HighlightText() end
        end
    end
    return true
end

local function CreateRow(box)
    local row = CreateFrame("Button", nil, box)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(T.Color(T.BG_HOVER))
    row.hover:Hide()
    row.name = T:Text(row, "", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", PAD, 0)
    row.name:SetPoint("RIGHT", -PAD, 0)
    row.name:SetJustifyV("MIDDLE")
    row.name:SetWordWrap(false)
    row:SetScript("OnEnter", function(self) self.hover:Show() end)
    row:SetScript("OnLeave", function(self) self.hover:Hide() end)
    row:SetScript("OnClick", function(self, button) Mail:Pick(self.entry, button) end)
    T:Tip(row, RowTitle, RowBody)
    return row
end

-- Other addons hang panels of their own on the mailbox's right edge. The
-- lowest of those showing, for the box to sit beneath.
function Mail:Neighbour()
    local lowest, lowestBottom
    -- How far down the screen a frame hung on that edge reaches; nil for any other.
    local function hangsThere(frame)
        if frame == self.box or (frame.IsForbidden and frame:IsForbidden()) or not frame:IsShown() then return nil end
        local point, relativeTo, relativePoint = frame:GetPoint(1)
        if relativeTo == MailFrame and point == "TOPLEFT" and relativePoint == "TOPRIGHT" then
            return frame:GetBottom()
        end
    end
    local function look(...)
        for _, frame in ipairs({ ... }) do
            -- Some frames may not be asked about at all; they are passed over.
            local ok, bottom = pcall(hangsThere, frame)
            if ok and type(bottom) == "number" and (not lowestBottom or bottom < lowestBottom) then
                lowest, lowestBottom = frame, bottom
            end
        end
    end
    if UIParent and UIParent.GetChildren then look(UIParent:GetChildren()) end
    if MailFrame.GetChildren then look(MailFrame:GetChildren()) end
    return lowest
end

-- Where the player dragged it, kept as how far that is from the mailbox's top
-- right corner; else beside the mailbox, under anything already there.
function Mail:PlaceBox()
    local box = self.box
    if not box then return end
    box:ClearAllPoints()
    local place = self.db.place
    if type(place) == "table" and type(place.x) == "number" and type(place.y) == "number" then
        box:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", place.x, place.y)
        return
    end
    local neighbour = self:Neighbour()
    if neighbour then
        box:SetPoint("TOPLEFT", neighbour, "BOTTOMLEFT", 0, -GAP)
    else
        box:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", GAP, -2)
    end
end

function Mail:SavePlace()
    local box = self.box
    local left, top, right, mailTop = box:GetLeft(), box:GetTop(), MailFrame:GetRight(), MailFrame:GetTop()
    if not (left and top and right and mailTop) then return end
    self.db.place = { x = left - right, y = top - mailTop }
    if box.SetUserPlaced then box:SetUserPlaced(false) end
    self:PlaceBox()
    ns:Refresh()
end

function Mail:ResetPlace()
    self.db.place = nil
    self:PlaceBox()
end

function Mail:CreateBox()
    if self.box then return self.box end
    if not (MailFrame and SendMailFrame and SendMailNameEditBox) then return nil end
    -- A child of the Send Mail page, so it comes and goes with that tab.
    local box = CreateFrame("Frame", "MiniQoLMailSendTo", SendMailFrame, "BackdropTemplate")
    T:Window(box, HEADER_H)
    box:SetWidth(BOX_W)
    box:SetClampedToScreen(true)
    box:EnableMouse(true)
    box:SetMovable(true)
    box:RegisterForDrag("LeftButton")
    box:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
    box:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        self:SavePlace()
    end)
    box.title = T:Text(box, "Send to", "GameFontNormalSmall", nil, T.GOLD)
    box.title:SetPoint("TOPLEFT", PAD, -6)
    box.heads = {
        T:Text(box, "Your characters", "GameFontDisableSmall", BOX_W - 2 * PAD, T.MUTED),
        T:Text(box, "Others you have mailed", "GameFontDisableSmall", BOX_W - 2 * PAD, T.MUTED),
    }
    box.empty = T:Text(box, "Nobody yet. Your other characters are listed as they log in, and people as you send them mail.",
        "GameFontDisableSmall", BOX_W - 2 * PAD, T.MUTED)
    box.empty:SetPoint("TOPLEFT", PAD, -(HEADER_H + GAP))
    box.rows = {}
    box:SetScript("OnShow", function()
        self:PaintBox()
        self:PlaceBox()
        -- A neighbour may only now be on its way up.
        C_Timer.After(0.5, function() if box:IsShown() then self:PlaceBox() end end)
    end)
    self.box = box
    self:RefreshBox()
    return box
end

-- Shown or not by the setting; with the tab, by being the tab's child.
function Mail:RefreshBox()
    local box = self.box or self:CreateBox()
    if not box then return end
    box:SetShown(self:Get("contacts"))
    if box:IsShown() then
        self:PaintBox()
        self:PlaceBox()
    end
end

function Mail:PaintBox()
    local box = self.box
    if not box then return end
    local alts = self:Alts()
    local groups = { alts, self:People(alts) }
    local limits = { MAX_ALTS, MAX_PEOPLE }
    local y, used = -(HEADER_H + GAP), 0
    for index, list in ipairs(groups) do
        local head = box.heads[index]
        head:SetShown(#list > 0)
        if #list > 0 then
            head:ClearAllPoints()
            head:SetPoint("TOPLEFT", PAD, y)
            y = y - HEAD_H
            for position = 1, math.min(#list, limits[index]) do
                used = used + 1
                local row = box.rows[used]
                if not row then
                    row = CreateRow(box)
                    box.rows[used] = row
                end
                local entry = list[position]
                row.entry = entry
                row.name:SetText(entry.name)
                if entry.alt then
                    row.name:SetTextColor(ClassColor(entry.class))
                else
                    row.name:SetTextColor(T.Color(T.TEXT))
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 1, y)
                row:SetPoint("TOPRIGHT", -1, y)
                row:Show()
                y = y - ROW_H
            end
            y = y - GAP
        end
    end
    for index = used + 1, #box.rows do
        box.rows[index].entry = nil
        box.rows[index]:Hide()
    end
    box.empty:SetShown(used == 0)
    box:SetHeight(used == 0 and HEADER_H + 2 * GAP + 44 or -y)
    box.count = used
end

---------------------------------------------------------------------------
-- Mail arriving
---------------------------------------------------------------------------
local function HasMail()
    return type(HasNewMail) == "function" and HasNewMail() == true
end

-- Who the unread mail is from, as far as the game says: the last three.
local function Senders()
    local list = {}
    if type(GetLatestThreeSenders) ~= "function" then return list end
    local first, second, third = GetLatestThreeSenders()
    for _, name in ipairs({ first or false, second or false, third or false }) do
        if Text(name) then list[#list + 1] = name end
    end
    return list
end

local function IsAuctionHouse(name)
    local lower = Lower(name)
    if lower:find("auction house", 1, true) then return true end
    local own = Text(BUTTON_LAG_AUCTIONHOUSE) -- its name in the game's language
    return own ~= nil and lower:find(Lower(own), 1, true) ~= nil
end

-- "Reco Veri", "Reco Veri and the auction house", "A, B and C".
local function From(senders)
    local names, auction = {}, false
    for _, name in ipairs(senders) do
        if IsAuctionHouse(name) then auction = true else names[#names + 1] = name end
    end
    if auction then names[#names + 1] = "the auction house" end
    if #names == 0 then return nil end
    if #names == 1 then return names[1] end
    return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

local function Sound(name, id, fallback)
    local played = PlaySound(SOUNDKIT and SOUNDKIT[name] or id, "Master")
    if not played and fallback then PlaySound(fallback, "Master") end
end

-- On screen, with a sound, and in chat unless the game has said it there.
function Mail:Tell(text, sale)
    if not sale then ns:Print(text) end
    if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(text, NEWS[1], NEWS[2], NEWS[3]) end
    if self:Get("sound") then
        if sale then
            Sound("LOOT_WINDOW_COIN_SOUND", 120)
        else
            Sound("UI_BNET_TOAST", 18019, SOUNDKIT and SOUNDKIT.TELL_MESSAGE or 3081)
        end
    end
end

-- Looks at what mail is waiting and says what is new about it. `greeting`:
-- the first look after logging in, when whatever is waiting is said.
function Mail:Check(greeting)
    local has, senders, now = HasMail(), Senders(), GetTime()
    local before = self.known
    local known = { has = has, senders = {}, unnamed = has and before.unnamed or nil }
    local fresh = {}
    for _, name in ipairs(senders) do
        known.senders[name] = true
        if not before.senders[name] then fresh[#fresh + 1] = name end
    end
    self.known = known
    if not has or not self:Get("notify") then return false end
    if greeting then
        local from = From(senders)
        if not from then known.unnamed = now end
        self:Tell(from and ("You have unread mail from %s."):format(from) or "You have unread mail.")
        return true
    end
    -- At the mailbox the mail is in front of you; just after it, or after
    -- arriving somewhere, the game is only catching up.
    if self.atMailbox or now < self.quietUntil then return false end
    if #fresh == 0 then
        if before.has or #senders > 0 then return false end
        -- Mail where there was none, before the game says who from.
        known.unnamed = now
        self:Tell("You have new mail.")
        return true
    end
    -- The names for mail already said to have arrived.
    if before.unnamed and now - before.unnamed < NAMING then
        known.unnamed = nil
        return false
    end
    known.unnamed = nil
    local auctionOnly = true
    for _, name in ipairs(fresh) do
        if not IsAuctionHouse(name) then auctionOnly = false end
    end
    if auctionOnly and self.saleAt and now - self.saleAt < SALE_ECHO then return false end
    self:Tell(("New mail from %s."):format(From(fresh)))
    return true
end

function Mail:CheckSoon()
    if self.checking then return end
    self.checking = true
    C_Timer.After(SETTLE, function()
        self.checking = false
        self:Check()
    end)
end

-- The game's line for a sale, as a pattern that picks out what sold.
local function SalePattern()
    local line = Text(ERR_AUCTION_SOLD_S) or "A buyer has been found for your auction of %s."
    line = line:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    line = line:gsub("%%%%1%%%$s", "(.+)"):gsub("%%%%s", "(.+)")
    return "^" .. line .. "$"
end

function Mail:OnSystemMessage(text)
    text = Text(text)
    if not text then return false end
    self.salePattern = self.salePattern or SalePattern()
    local item = text:match(self.salePattern)
    if not item then return false end
    self.saleAt = GetTime()
    if self:Get("notify") then self:Tell(("Auction sold: %s."):format(item), true) end
    return true
end

---------------------------------------------------------------------------
-- The settings page, and wiring
---------------------------------------------------------------------------
function Mail:RegisterPage()
    local function ready() return self.db ~= nil end
    ns:RegisterFeature({ id = "mail.notify", page = "mail", group = "Arriving mail", kind = "check",
        label = "Say when mail arrives", available = ready,
        get = function() return self:Get("notify") end,
        set = function(value) self:Set("notify", value) end,
        tooltip = "Says in chat and on screen who new mail is from: when it arrives, and when you log in with mail waiting. Each auction that sells is marked on screen too, as the game announces it. The game only tells addons the last three senders of unread mail, so a second letter from someone whose first you haven't read yet goes unsaid." })
    ns:RegisterFeature({ id = "mail.sound", page = "mail", group = "Arriving mail", kind = "check",
        label = "With a sound",
        available = function() return ready() and self:Get("notify") end,
        unavailable = "Turn on Say when mail arrives first.",
        get = function() return self:Get("sound") end,
        set = function(value) self:Set("sound", value) end,
        tooltip = "A chime for mail and the clink of coin for an auction sold. Played on the master channel, so it is heard with sound effects turned off." })
    ns:RegisterFeature({ id = "mail.contacts", page = "mail", group = "Sending mail", kind = "check",
        label = "List who you send to beside the Send Mail tab", available = ready,
        get = function() return self:Get("contacts") end,
        set = function(value) self:Set("contacts", value) end,
        tooltip = "A box beside the mailbox while the Send Mail tab is open: your other characters, then the people you have mailed in the last month, the ones mailed most first. Click a name to put it in the To field, with \"share\" as the subject unless you have typed one; right-click a person to take them off the list. Drag the box by its title to move it." })
    ns:RegisterFeature({ id = "mail.known", page = "mail", group = "Sending mail", kind = "info",
        label = "Nobody is listed yet.", available = ready,
        get = function() return self:Summary() end })
    ns:RegisterFeature({ id = "mail.forget", page = "mail", group = "Sending mail", kind = "action",
        label = "People you have mailed", button = "Forget...",
        available = function() return ready() and next(self:Book()) ~= nil end,
        unavailable = "Nobody you have mailed is remembered on this realm.",
        run = function() StaticPopup_Show("MINIQOL_MAIL_FORGET") end,
        tooltip = "Forgets everyone you have sent mail to on this realm. Your own characters stay listed. To take one person off, right-click their name in the box." })
    ns:RegisterFeature({ id = "mail.place", page = "mail", group = "Sending mail", kind = "action",
        label = "Where the box sits", button = "Reset",
        available = function() return ready() and self.db.place ~= nil end,
        unavailable = "It is where it started, beside the mailbox. Drag it by its title to move it.",
        run = function() self:ResetPlace() end,
        tooltip = "Puts the box back beside the mailbox, under any other addon's panel there." })
end

function Mail:OnEvent(event, ...)
    if event == "UPDATE_PENDING_MAIL" then
        self:CheckSoon()
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin = ...
        self.quietUntil = GetTime() + QUIET
        if isInitialLogin then
            C_Timer.After(QUIET, function() self:Check(true) end)
        else
            self:CheckSoon()
        end
    elseif event == "MAIL_SHOW" then
        self.atMailbox = true
        self:HookSending()
        self:WatchSubject()
        self:RefreshBox()
    elseif event == "MAIL_CLOSED" then
        self.atMailbox = false
        self.pending = nil
        self.quietUntil = GetTime() + QUIET
        self:CheckSoon()
    elseif event == "MAIL_SEND_SUCCESS" then
        local name = self.pending
        self.pending = nil
        if name then self:Sent(name) end
    elseif event == "MAIL_FAILED" then
        self.pending = nil
    elseif event == "CHAT_MSG_SYSTEM" then
        self:OnSystemMessage((...))
    end
end

-- Called once the saved variables and the panel exist.
function Mail:Start()
    self:Initialize()
    self:RegisterPage()
    self:HookSending()
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_PENDING_MAIL", "MAIL_SHOW", "MAIL_CLOSED",
        "MAIL_SEND_SUCCESS", "MAIL_FAILED", "CHAT_MSG_SYSTEM" }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event, ...) self:OnEvent(event, ...) end)
    self.events = events
end

StaticPopupDialogs.MINIQOL_MAIL_FORGET = {
    text = "Mini QoL: forget everyone you have sent mail to on this realm?",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        local count = ns.Mail:ForgetPeople()
        ns:Print(("Forgot %d %s."):format(count, count == 1 and "name" or "names"))
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
