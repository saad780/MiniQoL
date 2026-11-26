local _, ns = ...
local Characters = {}
ns.Characters = Characters

local function Readable(value)
    return not (issecretvalue and issecretvalue(value)) and value ~= nil
end

local function Text(value)
    return Readable(value) and type(value) == "string" and value ~= "" and value or nil
end

local function Number(value)
    return Readable(value) and type(value) == "number" and value or nil
end

function Characters.Fold(name)
    return (name:gsub("[A-Z]", string.lower):gsub("%s+", " "))
end

local function GuidRealmID(guid)
    return guid and guid:match("^Player%-(%d+)%-%x+$")
end

-- The realm's name. Forever's realms have none: GetRealmName answers "" and
-- GetRealmID 0. There the server in the player's GUID stands in for it, as
-- ForeverCore keys characters, so this character still has a key and a home.
-- A realm with an ID but no name yet is still loading: "" until it has one.
function Characters.Realm()
    local name = Text(GetRealmName and GetRealmName())
    if name then return name end
    if not (GetRealmID and GetRealmID() == 0) then return "" end
    return GuidRealmID(Text(UnitGUID and UnitGUID("player"))) or ""
end

-- Whether a realm is a server from the GUID rather than a realm's name.
function Characters.IsServer(realm)
    return type(realm) == "string" and realm:find("^%d+$") ~= nil
end

function Characters.PlayerName()
    local name, surname = UnitName("player")
    name, surname = Text(name), Text(surname)
    if not name or name == UNKNOWNOBJECT then return end
    if not surname or (RegionalUniqueNamesEnabled and not RegionalUniqueNamesEnabled()) then return name end
    local constants = Constants and Constants.CharacterNameSeparatorConsts
    local tail = (Text(constants and constants.CHARACTERNAME_SURNAME_SEPARATOR) or " ") .. surname
    return name:sub(-#tail) == tail and name or name .. tail
end

-- Forever shares its name pool between physical realms running the same
-- regional ruleset. Other clients use the ordinary realm name.
local function RegionalScope()
    if not (RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() and C_GameRules and Enum and Enum.GameRule) then return end
    local region = GetCurrentRegion and Number(GetCurrentRegion())
    if not region then return end
    local active, rule = C_GameRules.IsGameRuleActive, Enum.GameRule
    if not (active and rule.PvPRuleset and rule.RPRuleset and rule.HardcoreRuleset) then return end
    return ("region%d/%s%s%s"):format(region, active(rule.PvPRuleset) and "PvP" or "PvE",
        active(rule.RPRuleset) and "/RP" or "", active(rule.HardcoreRuleset) and "/HC" or "")
end

local function Key(name, realm)
    if Text(name) and Text(realm) then
        return Characters.Fold(name) .. "@" .. ((Characters.scopes and Characters.scopes[realm]) or realm)
    end
end

function Characters.PlayerKey()
    return Key(Characters.PlayerName(), Characters.Realm())
end

local function Ensure(name, realm)
    local key = Key(name, realm)
    if not key then return end
    local record = Characters.records[key]
    if type(record) ~= "table" then
        record = { name = name, realm = realm }
        Characters.records[key] = record
    end
    return record
end

local function Merge(record, old)
    local newer = (old.seen or old.saved or 0) >= (record.seen or record.saved or 0)
    for _, field in ipairs({ "class", "className", "race", "faction", "level", "guid", "seen" }) do
        if old[field] ~= nil and (record[field] == nil or newer) then record[field] = old[field] end
    end
    if old.address then record.address = true end
    if type(old.items) == "table" then
        local worn = next(old.items) ~= nil
        local kept = record.items and next(record.items) ~= nil
        if not record.items or (worn and not kept) or (worn == kept and (old.saved or 0) > (record.saved or 0)) then
            record.items, record.itemLevel, record.saved = old.items, old.itemLevel, old.saved
        end
    end
    if old.bagsSeen and (not record.bagsSeen or old.bagsSeen > record.bagsSeen) then
        record.bags, record.bagsSeen = old.bags, old.bagsSeen
    end
    if old.bankSeen and (not record.bankSeen or old.bankSeen > record.bankSeen) then
        record.bank, record.bankLinks, record.bankSeen = old.bank, old.bankLinks, old.bankSeen
    end
    if old.location and (not record.location or old.location.saved > record.location.saved) then record.location = old.location end
end

-- The original gear snapshots can contain a given name only. Keep their gear
-- accessible, but only a confirmed full name is safe to offer as a recipient.
function Characters:Initialize()
    local db = ns.db
    if type(db.characters) ~= "table" then db.characters = {} end
    self.records, self.current = db.characters, nil
    if type(db.characterScopes) ~= "table" then db.characterScopes = {} end
    self.scopes = db.characterScopes
    local realm, scope = self.Realm(), RegionalScope()
    if realm ~= "" and scope and self.scopes[realm] ~= scope then
        self.scopes[realm] = scope
        -- Old snapshots from realms we had yet to visit still use realm keys.
        local moves = {}
        for key, record in pairs(self.records) do
            if type(record) == "table" and record.realm == realm and Text(record.name)
                and key == self.Fold(record.name) .. "@" .. realm then moves[#moves + 1] = key end
        end
        for _, key in ipairs(moves) do
            local old = self.records[key]
            local target = Ensure(old.name, realm)
            Merge(target, old)
            self.records[key] = nil
        end
    end
    local mail = type(db.mail) == "table" and db.mail.characters
    if type(mail) == "table" then
        for _, old in pairs(mail) do
            local record = type(old) == "table" and Ensure(old.name, old.realm)
            if record then
                record.address = true
                Merge(record, old)
            end
        end
        db.mail.characters = nil
    end
    local gear = type(db.altGear) == "table" and db.altGear.characters
    if type(gear) == "table" then
        local singleNames = RegionalUniqueNamesEnabled and not RegionalUniqueNamesEnabled()
        for _, old in pairs(gear) do
            local record = type(old) == "table" and Ensure(old.name, old.realm)
            if record and type(old.items) == "table" then
                if singleNames or old.name:find(" ", 1, true) then record.address = true end
                Merge(record, old)
            end
        end
        db.altGear.characters = nil
    end
end

-- Before Forever's realms lost their names, this character was filed under its
-- first name and the realm's name ("firouzi@CAMWOW US1 Realm 4 PvP"). Fold that
-- record into this one when it is the only such record with this first name,
-- has no other character's GUID, and no other known character shares the first
-- name: otherwise whose it is cannot be told.
function Characters:Adopt(record, guid)
    local first = Text((UnitName("player")))
    if not first then return end
    local folded, own, found = self.Fold(first), Text(record.name) and self.Fold(record.name), nil
    for key, other in pairs(self.records) do
        local name = other ~= record and type(other) == "table" and Text(other.name)
        if name then
            local otherFolded = self.Fold(name)
            if otherFolded == folded and Text(other.realm) and not self.IsServer(other.realm)
                and not (guid and other.guid and other.guid ~= guid) then
                if found then return end
                found = key
            elseif otherFolded ~= own and otherFolded:match("^%S+") == folded then
                return
            end
        end
    end
    if not found then return end
    Merge(record, self.records[found])
    self.records[found] = nil
end

function Characters:Observe(level)
    local name, realm = self.PlayerName(), self.Realm()
    local record = Ensure(name, realm)
    if not record then return end
    local guid = Text(UnitGUID and UnitGUID("player"))
    if guid and record.guid and guid ~= record.guid then
        -- The name was reused by a newly created character.
        record = {}
        self.records[Key(name, realm)] = record
    end
    if self.IsServer(realm) then self:Adopt(record, guid) end
    self.current = record
    local className, class = UnitClass("player")
    record.name, record.realm, record.address, record.seen = name, realm, true, time()
    record.guid = guid or record.guid
    record.className, record.class = Text(className) or record.className, Text(class) or record.class
    record.race = Text(UnitRace and UnitRace("player")) or record.race
    record.faction = Text(UnitFactionGroup and UnitFactionGroup("player")) or record.faction
    local currentLevel = Number(level) or Number(UnitLevel and UnitLevel("player"))
    if currentLevel and currentLevel > 0 then record.level = currentLevel end
    return record
end

local function ImportName(name, realm, class, faction)
    local record = Ensure(name, realm)
    if record then
        record.address = true
        record.class = record.class or Text(class)
        record.faction = record.faction or Text(faction)
    end
end

local function ImportSyndicator(api, realm)
    local mine = api.GetByCharacterFullName(api.GetCurrentCharacter())
    local home = mine and mine.details and Text(mine.details.realmNormalized)
    if not home then return end
    for _, key in ipairs(api.GetAllCharacters()) do
        local entry = api.GetByCharacterFullName(key)
        local details = type(entry) == "table" and entry.details
        if type(details) == "table" and details.realmNormalized == home then
            ImportName(details.character, realm, details.className, details.faction)
        end
    end
    return true
end

function Characters:Discover()
    local realm = self.Realm()
    if not self.records or realm == "" then return end
    local api = Syndicator and Syndicator.API
    if api and self.syndicatorRealm ~= realm then
        local ok, ready = pcall(ImportSyndicator, api, realm)
        if ok and ready then self.syndicatorRealm = realm end
    end
    local chars = type(QuestieConfig) == "table" and QuestieConfig.char
    if type(chars) ~= "table" or self.questieRealm == realm or not next(chars) then return end
    local guid = Text(UnitGUID and UnitGUID("player"))
    local realmID = GuidRealmID(guid)
    for key, entry in pairs(chars) do
        if Text(key) and type(entry) == "table" then
            local other = Text(entry.guid)
            if not other or other ~= guid then
                local name, home = key:match("^(.+) %- (.+)$")
                if home == realm then
                    ImportName(name, realm, entry.townsfolkClass)
                elseif not home and realmID and GuidRealmID(other) == realmID then
                    ImportName(key, realm, entry.townsfolkClass)
                end
            end
        end
    end
    -- A late player GUID can identify more of Forever's unqualified names.
    if realmID then self.questieRealm = realm end
end

function Characters:Alts()
    self:Discover()
    local own, realm, alts = self.PlayerKey(), self.Realm(), {}
    for key, record in pairs(self.records or {}) do
        if key ~= own and type(record) == "table" and record.address and key == Key(record.name, realm) then
            alts[#alts + 1] = record
        end
    end
    return alts
end

function Characters:SaveLocation(record)
    if not record then return end
    local zone = Text(GetRealZoneText and GetRealZoneText())
    local map = C_Map and C_Map.GetBestMapForUnit and Number(C_Map.GetBestMapForUnit("player"))
    if not map and not zone then return end
    local previous = record.location
    local place = { mapID = map, zone = zone, subzone = Text(GetSubZoneText and GetSubZoneText()), saved = time() }
    local point = map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
    if Readable(point) and point.GetXY then
        local x, y = point:GetXY()
        if Number(x) and Number(y) and x >= 0 and y >= 0 and x <= 1 and y <= 1 and (x ~= 0 or y ~= 0) then
            place.x, place.y = x, y
        end
    end
    if previous and not place.x and (not zone or zone == previous.zone) and (not map or map == previous.mapID) then
        place.x, place.y, place.mapID = previous.x, previous.y, map or previous.mapID
        place.zone = place.zone or previous.zone
    end
    record.location = place
end

local function LastBag()
    return NUM_TOTAL_EQUIPPED_BAG_SLOTS or (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or NUM_BAG_SLOTS or 4
end

-- Commit one bag only after its occupied slots agree with the game's count.
-- A temporarily unreadable bag keeps its last complete snapshot.
local function ReadBag(bag, links)
    local api = C_Container
    local size = Number(api.GetContainerNumSlots(bag))
    if not size then return end
    if size == 0 then
        if bag == 0 or links then return end
        local slot = api.ContainerIDToInventoryID and api.ContainerIDToInventoryID(bag)
        if slot and GetInventoryItemID and GetInventoryItemID("player", slot) then return end
        return {}
    end
    local counts, used = {}, 0
    for slot = 1, size do
        local item = api.GetContainerItemInfo(bag, slot)
        if issecretvalue and issecretvalue(item) then return end
        if item then
            local id, count = Number(item.itemID), Number(item.stackCount)
            if not id or id <= 0 or not count or count <= 0 then return end
            counts[id], used = (counts[id] or 0) + count, used + 1
            if links then links[id] = Text(item.hyperlink) or links[id] or true end
        end
    end
    if api.GetContainerNumFreeSlots and Number(api.GetContainerNumFreeSlots(bag)) ~= size - used then return end
    return counts
end

function Characters:SaveBags(record, all, attempt)
    local api = C_Container
    if not record or not (api and api.GetContainerNumSlots and api.GetContainerItemInfo) then return end
    if all then for bag = 0, LastBag() do self.dirtyBags[bag] = true end end
    if not next(self.dirtyBags) then return end
    local changes = {}
    if (Number(api.GetContainerNumSlots(0)) or 0) > 0 then
        for bag in pairs(self.dirtyBags) do
            changes[bag] = ReadBag(bag)
            if not changes[bag] then changes = nil; break end
        end
    else
        changes = nil
    end
    if changes then
        record.bags = record.bags or {}
        for bag, counts in pairs(changes) do record.bags[bag] = counts end
        self.dirtyBags = {}
        record.bagsSeen = time()
    elseif not self.bagRetry and (attempt or 0) < 3 then
        self.bagRetry = true
        C_Timer.After(0.25, function()
            self.bagRetry = false
            if self:Current() == record then self:SaveBags(record, false, (attempt or 0) + 1) end
        end)
    end
end

function Characters:Current()
    return self.current
end

-- A bank visit replaces the last snapshot only once every purchased
-- personal tab is readable. Account bank tabs belong to a different owner.
function Characters:SaveBank()
    local record = self:Current()
    if not self.bankOpen or not record or not (C_Bank and C_Bank.FetchPurchasedBankTabData
        and Enum and Enum.BankType and Enum.BagIndex and C_Container and C_Container.GetContainerNumSlots
        and C_Container.GetContainerItemInfo) then return end
    local kind = Enum.BankType.Character
    if not kind or (C_Bank.FetchBankLockedReason and C_Bank.FetchBankLockedReason(kind) ~= nil) then return end
    local tabs = C_Bank.FetchPurchasedBankTabData(kind)
    if type(tabs) ~= "table" or #tabs == 0 then return end
    local counts, links = {}, {}
    for index = 1, #tabs do
        local bag = Enum.BagIndex["CharacterBankTab_" .. index]
        local items = bag and ReadBag(bag, links)
        if not items then return end
        for id, count in pairs(items) do counts[id] = (counts[id] or 0) + count end
    end
    record.bank, record.bankLinks, record.bankSeen = counts, links, time()
    return true
end

function Characters:QueueBank()
    if not self.bankOpen or self.bankPending then return end
    self.bankPending = true
    local visit = self.bankVisit
    local function scan(retries)
        if not self.bankOpen or self.bankVisit ~= visit then return end
        if self:SaveBank() or retries == 0 then
            self.bankPending = false
        else
            C_Timer.After(0.25, function() scan(retries - 1) end)
        end
    end
    C_Timer.After(0, function() scan(3) end)
end

function Characters:Start()
    self:Initialize()
    self.dirtyBags = {}
    self:Observe()
    self:Discover()
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "PLAYER_LEVEL_UP", "BAG_UPDATE",
        "BAG_UPDATE_DELAYED", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
        "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "BANK_TABS_CHANGED", "PLAYERBANKSLOTS_CHANGED" }) do
        frame:RegisterEvent(event)
    end
    frame:SetScript("OnEvent", function(_, event, arg)
        if event == "ADDON_LOADED" then
            if arg == "Syndicator" or arg == "Questie" then C_Timer.After(0, function() self:Discover() end) end
        elseif event == "BANKFRAME_OPENED" then
            if self.bankOpen then return end
            self.bankOpen, self.bankVisit = true, (self.bankVisit or 0) + 1
            self:QueueBank()
        elseif event == "BANKFRAME_CLOSED" then
            self.bankOpen, self.bankPending = false, false
        elseif event == "BANK_TABS_CHANGED" or event == "PLAYERBANKSLOTS_CHANGED" then
            self:QueueBank()
        elseif event == "BAG_UPDATE" then
            if Number(arg) and arg >= 0 and arg <= LastBag() then self.dirtyBags[arg] = true end
            local bags = Enum and Enum.BagIndex
            if self.bankOpen and bags and bags.CharacterBankTab_1 and Number(arg)
                and arg >= bags.CharacterBankTab_1 and arg <= (bags.CharacterBankTab_9 or bags.CharacterBankTab_1) then
                self:QueueBank()
            end
        elseif event == "PLAYER_LEVEL_UP" then
            self:Observe(arg)
        elseif event == "PLAYER_ENTERING_WORLD" then
            local record = self:Observe()
            self:Discover()
            self:SaveLocation(record)
            self:SaveBags(record, true)
        else
            local record = self:Current()
            if event ~= "BAG_UPDATE_DELAYED" then self:SaveLocation(record) end
            if event == "BAG_UPDATE_DELAYED" or event == "PLAYER_LOGOUT" then self:SaveBags(record) end
        end
    end)
    self.events = frame
end
