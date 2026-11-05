-- Defaults-only migration initializer. No personal settings are embedded.
MiniQoLDB = type(MiniQoLDB) == 'table' and MiniQoLDB or {}
MiniQoLDB.migratedModules = MiniQoLDB.migratedModules or {}
MiniQoLDB.migratedCharacters = MiniQoLDB.migratedCharacters or {}
local accountImports = MiniQoLDB.migratedModules
local characterKey = (UnitName('player') or '') .. '|' .. (GetRealmName() or '')
MiniQoLDB.migratedCharacters[characterKey] = MiniQoLDB.migratedCharacters[characterKey] or {}
local characterImports = MiniQoLDB.migratedCharacters[characterKey]
local function import(values) for key, value in pairs(values) do if _G[key] == nil then _G[key] = value end end end
