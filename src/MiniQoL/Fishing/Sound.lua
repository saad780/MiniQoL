local _, ns = ...
-- Turns the sound up while the line is out so the splash is easy to hear, and
-- puts every setting back afterwards -- including after a crash, because the
-- old values are written to saved variables while boosted.
local Fishing = ns.Fishing

local VOLUME = { "Sound_MasterVolume", "Sound_SFXVolume" }
local FIXED = { Sound_EnableSFX = "1", Sound_MusicVolume = "0", Sound_AmbienceVolume = "0" }
local BACKGROUND = "Sound_EnableSoundWhenGameIsInBG"

function Fishing:SoundBoosted()
    return self.db and self.db.soundBackup ~= nil
end

function Fishing:ApplyVolume()
    if not self:SoundBoosted() then return end
    local volume = tostring(self:Get("volume"))
    for _, cvar in ipairs(VOLUME) do SetCVar(cvar, volume) end
end

function Fishing:BoostSound()
    if self:SoundBoosted() then return end
    local backup = {}
    for _, cvar in ipairs(VOLUME) do backup[cvar] = GetCVar(cvar) end
    for cvar, value in pairs(FIXED) do
        backup[cvar] = GetCVar(cvar)
        SetCVar(cvar, value)
    end
    if self:Get("soundInBackground") then
        backup[BACKGROUND] = GetCVar(BACKGROUND)
        SetCVar(BACKGROUND, "1")
    end
    self.db.soundBackup = backup
    self:ApplyVolume()
    self:Fire("SOUND_CHANGED")
end

function Fishing:RestoreSound()
    local backup = self.db and self.db.soundBackup
    if not backup then return end
    for cvar, value in pairs(backup) do
        if value ~= nil then SetCVar(cvar, value) end
    end
    self.db.soundBackup = nil
    self:Fire("SOUND_CHANGED")
end

function Fishing:SetupSound()
    -- Anything left boosted by a logout or a crash is undone at login.
    self:RestoreSound()
    local boostTimer
    local events = CreateFrame("Frame")
    events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    events:RegisterEvent("PLAYER_LOGOUT")
    events:SetScript("OnEvent", function(_, event, _, _, spellID)
        if event == "PLAYER_LOGOUT" then return end
        if not self:IsFishingSpell(spellID) then return end
        if boostTimer then boostTimer:Cancel(); boostTimer = nil end
        if event == "UNIT_SPELLCAST_CHANNEL_START" then
            -- Wait out the sound of the cast itself before turning it up.
            boostTimer = C_Timer.NewTimer(self.BOOST_DELAY, function()
                boostTimer = nil
                if self:Get("sound") then self:BoostSound() end
            end)
        else
            self:RestoreSound()
        end
    end)
    self:On("SETTING_CHANGED", function(key)
        if key == "volume" then self:ApplyVolume()
        elseif key == "sound" and not self:Get("sound") then self:RestoreSound() end
    end)
end
