# Mini QoL authorship and third-party notices

The combined software distribution is GPL-3.0-only. The full GPL version 3 is
included in `LICENSE`. Existing MIT notices and the upstream public-domain
dedication below remain intact. These software licenses do not relicense game
artwork, trademarks, or assets whose rights are separately identified.

## Original Mini QoL work

Copyright (c) 2026 saad780. The MiniQoL shell, runtime, panel, NPC shortcuts,
integration adapters, tests, build/install tools, Gearwise, XP Counter and the
original parts of Wayfinder were developed by saad780. Original work is offered
under GPL-3.0-only for this distribution, except Gearwise, whose existing MIT
license is retained. Contributions below are not claimed as original Mini QoL
work.

The packaging changes made on 2026-11-05 and 2026-11-07 wrap component Lua files
in the MiniQoL runtime, relocate resource paths, consolidate manifests, bridge
component settings, and add a unified panel and NPC shortcuts. Sources under
`src/Modules` are the editable inputs; `MiniQoL/Modules` contains generated
adaptations. Generated Lua adapters are marked in their headers.

## Peddler

- Original author: Cartas @ Bloodfang-Classic, with upstream contributors.
- Upstream: https://www.curseforge.com/wow/addons/peddler
- Upstream license: https://www.curseforge.com/wow/addons/peddler/license
- Upstream dedication, verified 2026-11-07: "This work is dedicated to the public domain."
- Included version: 9.1-forever.3, based on Peddler 9.1; code and `coins.tga`
  are retained from that component.
- Forever adaptations by saad780 update item/container APIs, bag-button hooks,
  item-link handling and compatibility with the Forever client. Those local
  adaptations and MiniQoL integration changes are GPL-3.0-only. The original
  author's public-domain dedication is not replaced or represented as ours.
- Paths: `src/Modules/Peddler` and `MiniQoL/Modules/Peddler`.
- The component's `LICENSE.txt` preserves the dedication and modification notice.

## Gearwise

- Author: saad780.
- Source: https://github.com/saad780/Gearwise
- License: MIT, copyright (c) 2026 saad780.
- Paths: `src/Modules/Gearwise` and `MiniQoL/Modules/Gearwise`.
- Its full `LICENSE.txt` is retained. MiniQoL adds runtime wrapping and resource
  path/integration adapters; the component's MIT grant remains available.

## Wayfinder, XP Counter and Carbonite data

- Wayfinder and XP Counter author: saad780.
- Sources: https://github.com/saad780/Wayfinder and https://github.com/saad780/XPCounter
- Wayfinder includes adapted town-service data in `Data/Seed.lua` and dock
  positions in `Data/Transports.lua` from **Carbonite All-in-One**, credited to
  the Carbonite contributors and maintainer IrcDirk.
- Carbonite source revision: `72b3a19cb88f6fd25ed812d7060f6dcd45ea6aec`.
- Original service data:
  https://github.com/IrcDirk/Carbonite-All-in-One-Retail-Classic/tree/72b3a19cb88f6fd25ed812d7060f6dcd45ea6aec/Carbonite/Data/camelot/Guides
- Original transport data:
  https://github.com/IrcDirk/Carbonite-All-in-One-Retail-Classic/blob/72b3a19cb88f6fd25ed812d7060f6dcd45ea6aec/Carbonite/Data/camelot/ZoneConnections.lua
- License:
  https://github.com/IrcDirk/Carbonite-All-in-One-Retail-Classic/blob/72b3a19cb88f6fd25ed812d7060f6dcd45ea6aec/LICENSE
- MiniQoL/Wayfinder flattens the service records, maps categories and extracts
  transport endpoints; it does not include the Carbonite addon itself.
- GPL version 3 is preserved in `Modules/Wayfinder/LICENSE.txt`. The combined
  distribution uses GPL-3.0-only without assuming an additional grant to use
  future GPL versions for upstream data.
- XP Counter's original code and MiniQoL popup bridge are GPL-3.0-only in this
  distribution; the full license is also included in its module directory.

## OpenMap code and assets

- Authors: OpenMap contributors; copyright (c) 2026 OpenMap contributors.
- Source: https://github.com/openmap-world/openmap
- Project: https://www.curseforge.com/wow/addons/openmap
- Included code is adapted from OpenMap 0.5.0-beta: `Map/WorldMap.lua` in
  Wayfinder's `Vendor/OpenMap/WorldMap.lua`, and coordinate/host-layout routines
  from `Map/Stitch.lua` in Wayfinder's `ContinuousArt.lua`.
- License: MIT. The complete MIT notice is retained in
  `Modules/Wayfinder/Vendor/OpenMap/LICENSE.txt`, alongside the adaptation notes
  in that folder's `README.md`.
- Wayfinder uses its own namespace, rendering, waypoint gesture and zoom limits;
  OpenMap's remaining application modules are not bundled.
- `Modules/Wayfinder/Media/MapMasks/NOTICE.md` identifies the copied masks.
  `MapTerritory` and `MapCityMask` are traced from Blizzard's artwork;
  `MapFeatherRound.tga` is a generated edge mask without game artwork.
- The original asset notice is retained in
  `Modules/Wayfinder/Vendor/OpenMap/UPSTREAM-TEXTURES.md`. Blizzard-derived assets
  remain Blizzard Entertainment's; neither the MIT nor GPL code license grants
  ownership of them. Visible map tiles are loaded from the installed game.
- No artist-drawn OpenMap dungeon maps, gap paintings or baked world-map tiles
  are bundled.

Paths above describe the installable addon. The same notices and module sources
are retained under `src/Modules` in the repository.

## Design inspiration

- **Leatrix Plus**, by Leatrix: https://www.curseforge.com/wow/addons/leatrix-plus
  inspired the compact settings layout.
- **Dialogue UI**, by Peterodox: https://www.curseforge.com/wow/addons/dialogueui
  inspired keyboard access to NPC dialogue.

MiniQoL implements its own panel and shortcuts. No code or artwork from either
project is included. No Leatrix Maps data is included: Booty Bay/Ratchet dock
coordinates use the Carbonite source above; the two unverified Feathermoon dock
entries were omitted during the publication audit on 2026-11-07.

World of Warcraft and its artwork and trademarks belong to Blizzard
Entertainment. Mini QoL is an independent addon and does not claim endorsement
by Blizzard or the other projects credited here.

## Bundled component versions

## Gearwise

Author: saad780

Version: 1.2.0

Manifest: Modules/Gearwise/Gearwise.toc

Licences: LICENSE.txt

## Peddler

Author: Cartas @ Bloodfang-Classic

Version: 9.1-forever.3

Manifest: Modules/Peddler/Peddler.toc

Licences: LICENSE.txt

## Wayfinder

Author: saad780

Version: 1.4.19

Manifest: Modules/Wayfinder/Wayfinder.toc

Licences: LICENSE.txt, Vendor\OpenMap\LICENSE.txt

## XPCounter

Author: saad780

Version: 1.3.1

Manifest: Modules/XPCounter/XPCounter.toc

Licences: LICENSE.txt
