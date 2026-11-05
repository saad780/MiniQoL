# Mini QoL

Mini QoL includes exactly **Peddler, Gearwise, Wayfinder and XP Counter**, plus the requested lightweight NPC dialogue hotkeys. All other addons remain independent installations.

Open `/mqol` or the minimap gear for compact controls. Maps, gear advice, selling, XP/reputation and NPC hotkeys have their own pages. Other addons' settings and minimap icons are not managed by Mini QoL.

The `MiniQoL` directory is the complete installable addon. The four component sources live under `src/Modules`; the shell lives under `src/MiniQoL`. No other addon code or audio packs are included. Original component authors and licences are retained; the compact panel is inspired by Leatrix Plus and the NPC hotkeys by Dialogue UI.

## Build

Python with `lupa` is required.

```powershell
python tools/build.py --output build/clean
python tests/run.py build/clean/MiniQoL
```

The builder enforces the exact four-component allowlist and rejects unrelated addon folders. Clean builds contain defaults, not personal settings. Existing per-account and per-character settings can be imported locally with `--account` and are never committed to this repository.

The addon retains the four components' native behavior. NPC shortcuts use **1-9 / 0** (including numpad) for choices, and optional **Space** for enabled quest actions. Choices and turning in quests are separate actions. Hotkeys yield to typing, combat, popups, settings and gamepad mode.

Offline scope, loading, settings, dialogue and Lua checks are run before installation. First in-game validation of the combined addon remains pending.

To install manually, exit WoW, copy `MiniQoL` into `Interface/AddOns`, and move only the standalone `Peddler`, `Gearwise`, `Wayfinder` and `XPCounter` folders to a backup. Keep every other addon installed. The optional `tools/Install.ps1` performs that scoped installation with account and addon backups, imports the four components' existing settings, and verifies that unrelated addon folders are unchanged.
