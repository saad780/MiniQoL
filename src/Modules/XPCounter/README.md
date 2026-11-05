# XP Counter for WoW: Forever

XP Counter writes each XP gain and reputation change to your local chat window. Optional floating text is off by default. When enabled, a kill popup is short, such as `53 XP - 3 more (~2m 10s)`; quest and exploration popups show only the XP amount. Reputation popups are short too, while chat keeps the full standing and perk details. Kill XP includes estimates of how many similar kills remain until the next level and how long leveling may take. Quest and exploration XP never show those estimates.

## Install

Copy the `XPCounter` folder into `World of Warcraft/_classic_beta_/Interface/AddOns/`, then restart WoW or type `/reload`. Enable **XP Counter** in the AddOns list if needed.

## Popup settings

Open **Game Menu → Options → AddOns → XP Counter**, or type `/xpc`.

- **Show on-screen text popups** turns floating text on or off. It starts off, including on the first load after this update. Chat output stays on.
- **Test popup** displays a sample message for five seconds.
- **Move popup** shows a draggable preview and closes Options. Drag it with the left mouse button, then right-click the preview to finish. The position is saved for later sessions.
- **Reset position** returns the popup to its default location.

## Notes

- Area discovery XP is labeled `Discovery: +<amount> XP`. Discovery detection uses the game's message name so changing message IDs do not mislabel it as `Other`.
- This build targets Forever interface 16001 and uses Blizzard's `C_Reputation` API and character XP events.
- The kill estimate assumes each future kill awards the same XP as the one just received. Rested XP, mob level, group size, and buffs can change it.
- The time estimate uses all XP earned over the last five minutes, including quests and exploration, divided by the time observed in that window. It appears after at least 30 seconds of XP history. It resets when the UI reloads, and it may swing after a large XP reward or a long break.
- The Forever API does not supply a complete faction reward catalog. Known capital vendor discounts are listed; for other standings the addon does not claim a specific unlock.
- This beta addon has been checked with a simulated event harness. In-game behavior still needs a live kill, quest turn-in, exploration reward, and reputation standing change.
