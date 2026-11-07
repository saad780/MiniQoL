# Mini QoL v1.0.1

Publication and licensing update for the four-component WoW Forever addon.

- License the combined software distribution under GPL-3.0-only and include the
  full GPL, copyright, attribution and component notices in the download.
- Credit Cartas/Peddler, Carbonite, OpenMap, and the Leatrix Plus/Dialogue UI
  design inspirations, alongside saad780's original code.
- Replace Booty Bay/Ratchet dock coordinates with Carbonite's GPL data and omit
  two Feathermoon dock entries whose redistribution permission was unverified.
- Require an explicit account directory for the optional installer and use the
  current Windows profile for backups.
- Ship defaults only. Personal account paths, saved settings, credentials and
  backups are excluded from public source and release artifacts.

Exit WoW, back up your settings, and extract `MiniQoL` into `Interface/AddOns`.
Move only the standalone `Peddler`, `Gearwise`, `Wayfinder` and `XPCounter`
folders outside `AddOns`. Keep all other addons installed.

The release includes an installable ZIP and a complete source ZIP. Component
license notices and game-asset provenance are retained; software licensing does
not relicense Blizzard artwork.

Validation: exact four-component scope, 58 Lua files compiled, source references,
settings, panel navigation and NPC hotkey behavior checked offline. In-game
verification remains pending.
