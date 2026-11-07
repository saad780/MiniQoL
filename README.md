# Mini QoL

Mini QoL brings **Peddler, Gearwise, Wayfinder and XP Counter** together in one
addon for WoW Forever (interface `16001`), with a compact settings panel and
keyboard shortcuts for the game's NPC dialogue windows.

Open `/mqol` or click the minimap gear. Maps, gear advice, selling, XP/reputation
and NPC shortcuts have their own settings pages. Other addons keep their own
settings and minimap icons.

## Download and install

Download **MiniQoL-1.0.2.zip** from the [latest release](https://github.com/saad780/MiniQoL/releases/latest).

1. Exit WoW and back up your addon settings.
2. Extract the `MiniQoL` folder into your game's `Interface/AddOns` directory.
3. Move only the standalone `Peddler`, `Gearwise`, `Wayfinder` and `XPCounter`
   folders to a backup outside `AddOns`. Keep every other addon installed.
4. Start WoW and enable Mini QoL.

Downloads contain clean defaults. Your existing MiniQoL saved settings are kept.
To import settings from the four standalone addons, the optional Windows
installer creates account/addon backups and checks that unrelated addon folders
are unchanged. Supply your own account directory explicitly:

```powershell
.\tools\Install.ps1 -AccountRoot "C:\Path\To\World of Warcraft\_forever_\WTF\Account\YOUR_ACCOUNT"
```

Use `-AddonRoot` if your game is outside the installer's default location.
Backups go into `addon-backups` under your Windows user profile unless you supply
`-BackupParent`. Run the installer from a source checkout, with Python and `lupa`
installed, while WoW is closed.

NPC shortcuts use **1–9 / 0**, including the numpad, for dialogue and reward
choices, with optional **Space** for quest actions. Selecting a choice and
turning in a quest are separate actions. Shortcuts yield to typing, combat,
popups, settings and gamepad mode.

## Authors and credits

Most of the addon implementation is by **[saad780](https://github.com/saad780)**:
the MiniQoL shell, panel, runtime, NPC shortcuts, integration/build tools,
Gearwise, Wayfinder's original implementation and XP Counter. The bundle also
includes these contributions from other projects:

| Component or contribution | Credit | Terms |
| --- | --- | --- |
| [Gearwise](https://github.com/saad780/Gearwise) | saad780 | MIT; original notice retained |
| [Wayfinder](https://github.com/saad780/Wayfinder) and [XP Counter](https://github.com/saad780/XPCounter) | saad780, with the Wayfinder contributions below | GPLv3 in this distribution |
| [Peddler](https://www.curseforge.com/wow/addons/peddler) | Cartas @ Bloodfang-Classic and upstream contributors; Forever adaptations by saad780 | Upstream public-domain dedication; local adaptations GPLv3 |
| [Carbonite All-in-One](https://github.com/IrcDirk/Carbonite-All-in-One-Retail-Classic) town-service and transport data | Carbonite contributors, maintained by IrcDirk | GPLv3 |
| [OpenMap](https://github.com/openmap-world/openmap) scroll controller and coordinate/layout adaptations | OpenMap contributors | MIT; notice retained |
| Game-derived map masks and client artwork | Blizzard Entertainment; mask tracing/generation by OpenMap contributors | Separate asset rights; see the retained provenance notices |

The panel's layout is inspired by [Leatrix Plus](https://www.curseforge.com/wow/addons/leatrix-plus)
by Leatrix, and the NPC shortcuts by [Dialogue UI](https://www.curseforge.com/wow/addons/dialogueui)
by Peterodox. Their code and artwork are not bundled. See
[THIRD_PARTY.md](THIRD_PARTY.md) for source locations, modifications and full
attribution, including the distinction between software and game artwork.

## License

The **combined Mini QoL software distribution is licensed under GNU GPL version
3 (`GPL-3.0-only`)**, including its Carbonite-derived data. See [LICENSE](LICENSE).
You may use, modify and redistribute it under those terms; it comes without
warranty. Retained MIT notices and Peddler's upstream public-domain dedication
continue to apply to their respective components. The GPL does not grant rights
to Blizzard's game artwork or trademarks. See [COPYRIGHT](COPYRIGHT) and
[THIRD_PARTY.md](THIRD_PARTY.md) for the scope of each notice.

## Build and validation

The `MiniQoL` directory is the installable addon. Original component inputs live
under `src/Modules`, and the shell under `src/MiniQoL`.

```powershell
python -m pip install lupa
python tools/build.py --output build/clean
python tests/run.py build/clean/MiniQoL
```

The builder accepts exactly the four named components and rejects unrelated
addon folders. A normal build contains defaults, not personal settings. The
optional `--account` import creates a private local profile snapshot; keep those
builds, account backups and `WTF` data out of source control and releases.

Offline checks cover scope, Lua compilation, source references, settings, panel
navigation, NPC shortcuts and native map API mixin lookups during player
sampling. In-game validation of the combined addon remains pending.
