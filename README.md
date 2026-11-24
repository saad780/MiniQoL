# Mini QoL

Mini QoL brings **Peddler, Gearwise, Wayfinder and XP Counter** together in one
addon for WoW Forever (interface `16001`), with a compact settings panel and
keyboard shortcuts for the game's NPC dialogue windows.

Open `/mqol` or click the minimap gear. Maps, gear advice, selling, XP/reputation
and NPC shortcuts have their own settings pages. Every setting for every bundled
module lives there, so the game's AddOns list holds a single **Mini QoL** entry
whose only job is to open the panel. Other addons keep their own settings and
minimap icons.

The continuous map remembers where you panned and zoomed for 45 seconds after
you last moved it, even while the map is closed. It then shows the whole zone
you are in (or your city), the way the game's own map opens. The map layer is
remembered for the play session. **Track my location** follows
your character across map reopens until you click the button again. Dragging
the map pauses tracking until you release it.

Under **Maps & travel → Waypoints → Route style**, choose **Direct** for the
shortest walkable route, **Balanced** (the default) to favor roads with short
detours, or **Roads Always** to follow roads even on longer detours. Mini QoL
includes the router and walking maps for Eastern Kingdoms, Kalimdor, and Zephras
Isle. The arrow points straight at the objective and shows its straight-line
distance. For an objective on another continent, it points at the next local
boarding stop when one is available.

**Show ant trails** (under Waypoints, on by default) draws the walking route
on the continuous world map and minimap. Follow the dots around obstacles
and to any flight master, dock or portal on the way. Outside walking map
coverage, the dots lead straight to the next stop or waypoint. **Ant trails on**
chooses which maps show the dots, and **Ant trail color** sets their color.

Middle-click a destination to get travel instructions for any flight, boat,
zeppelin, tram or portal that gets you there sooner. At the stop, the guide
names the ride or flight to take. After arrival it continues toward your original
pin. Flights use this character's discoveries. A new departure can be learned
on the way. The arrow also calls out an undiscovered flight master you pass on foot.
A ready Hearthstone is suggested whenever the cast and the remaining trip
from your bound inn beat the quickest route from here. Hearthstones, flights and transports each
have a default-on switch under **Maps & travel → Waypoints**.

When you release your spirit, the waypoint arrow points at your corpse. Coming
back to life completes that waypoint, wherever it happens, and the arrow returns
to the waypoint it was on before. **Point the arrow at your corpse** under
Waypoints turns this off.

Middle-click a quest in the quest log, the objective tracker (its title, lines
or quest icon) or Questie's tracker, and the waypoint arrow points at the nearest
place still to do for it, or at where to hand it in once it is complete. The
waypoint follows the quest: it moves as objectives are finished and goes when the
quest is handed in or abandoned. Middle-click the same quest again to stop. With
Questie loaded its quest data picks the spot; otherwise the game's quest markers
do. **Middle-click a quest to follow it** under Waypoints turns this off.

On a Skyborne character, Wayfinder puts each Elemental Convergence on the map
and minimap as you come across it, so you can find your way back to cast
Skysight there and be Charged for the hour. Nothing has to be cast: a
convergence is added, where it actually is, once the game shows its marker on
your minimap. Wayfinder reads that marker itself; if one shows and isn't added,
hold the mouse over it on the minimap. Casting Skysight within reach of one (25
yards) adds it too, marked as approximate until its marker places it. Seeing
one in the distance adds nothing, because that doesn't say where it is.
`/wf convergence` marks one by hand where you stand, Shift-click removes an
icon, and **Elemental Convergences** under Icons turns them off. Other races
are not shown them.

With the Polestar leveling guide installed, **Show Polestar's guide on this
arrow** under Waypoints points the arrow at the guide's objective. The ant trail
leads to any flight master or boat along the way. Turn on Polestar's own
**Let a following addon show the way**
(Guide, Arrow & routes, Other waypoints) and Polestar's arrow steps aside while
this one shows the way. Polestar moves the waypoint on when a goal is done;
removing it yourself lets that goal go in Polestar too, until the guide moves on.

Mini QoL writes down what each of your characters is wearing whenever it
changes. The **Alts** button on the character sheet, at the bottom right of the
character beside the lower trinket slot (left- or right-click), lists
your other characters: pick one and their gear takes the place of yours on the
sheet, with the usual item tooltips, until you pick yourself again or close the
sheet. A character is added the first time it logs in with Mini QoL on. The
**Alt gear** page turns this off or forgets characters you no longer play.

Mini QoL says when mail arrives: who it is from, in chat and on screen with a
sound, and what is waiting when you log in. Each auction that sells is marked on
screen as the game announces it. The game only tells addons the last three
senders of unread mail, so a second letter from someone whose first is still
unread goes unsaid. On the Send Mail tab, a box beside the mailbox lists your
other characters and the people you have mailed in the last month, the ones
mailed most first: click a name to put it in the To field, with "share" as the
subject unless you have typed one, right-click a person to take them off, and
drag the box by its title to move it. Your characters are added as they log in,
or straight away if Syndicator knows them. The **Mail** page turns either part
off.

A slim bar under the player frame's health and power bars times your regen:
one row for health, one for mana, energy or rage, drawn with the player
frame's own bar art inside the game's cast bar frame. A greyed-out row means
nothing is coming back (full, in combat, or dead). After a spell that costs
mana, the mana row drains through the five-second rule; once it empties, regen
is under way and each row fills toward the next tick, flashing as it lands.
The number on a row is what the last tick gave (for rage, what it loses each
tick out of combat). When the game keeps your health or power secret from
addons, the number is the last tick measured or what your regen rate gives;
`/mqol regen` says which. The **Regen ticks** page turns either row or the
numbers off, and sets the look (unit frame art or the classic flat texture;
cast bar frame, thin line or no border; where the number sits, its size and
color) and the size and place (the player frame's width or your own, row
height, the space between rows, the gap below the player frame and a sideways
nudge). **Reset** puts the look and size back.

**Alt Mail** opens from the envelope by the bags, the Mini QoL **Mail** page, or
`/altmail`. Set a recipient for each group, then hover over a stack and press
**Ctrl+Shift+1** or **Ctrl+Shift+2** to mark it. The numbered envelope follows
that stack in stock bags, Bagnon, or Baganator. Enable automatic sending per
group, or use **Send Now** at a mailbox.

Gearwise prompts when you loot an upgrade, and **Space** equips it while that
prompt is open. When a looted item scores exactly what you are wearing, a small
badge waits at the edge of the screen instead: hover it to see your character
side by side in both versions and keep whichever you prefer. Items you turn down
never ask again.

## Download and install

Download **MiniQoL-1.1.0.zip** from the [latest release](https://github.com/saad780/MiniQoL/releases/latest).

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
| [Polestar](https://github.com/fitzforge/polestar) walking router and maps | Polestar contributors, Cillian Berragan, and Leffe | GPLv3; upstream notices retained |
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

For a personal build with **Nearby upgrades** (`/mqol nearby`) and **World search**
(`/mqol find [name]`), pass `--outrider-data "<WoW AddOns directory>"` to the build
command. This imports the installed Outrider data packs with their source notices.
Outrider can stay disabled in game. Keep the resulting data in your local build.

Offline checks cover scope, Lua compilation, source references, settings, panel
navigation, NPC shortcuts, native map API mixin lookups during player sampling
and session-only map views. In-game validation of the combined addon remains
pending.
