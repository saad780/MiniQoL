# Mini QoL v1.1.0

One settings panel for the whole bundle, a reworked Gearwise upgrade prompt, and
a map that remembers where you left it for the session rather than forever.

## One place for settings

- The game's AddOns list now holds a single **Mini QoL** entry whose only job is
  to open the panel. Gearwise, Peddler, Wayfinder and XP Counter no longer
  register settings categories of their own.
- Every setting they used to keep there moved into the panel: Wayfinder's five
  size/radius sliders, all nineteen service icon categories and its data
  actions; Gearwise's build and stat-priority pickers and live build summary;
  Peddler's marking modifier, coin corner and marked-item list; XP Counter's
  move, test and reset controls for the floating text.
- `/gearwise`, `/peddler`, `/xpcounter`, `/wf` and the world map's
  **Settings…** button all open the panel on the matching page.
- The panel itself was rebuilt on a shared theme: a grouped sidebar with live
  module status, themed sliders, dropdowns and buttons, and sections so a long
  page reads as a few short lists.

## Gearwise

- Equal-value look offers. When a looted item scores exactly what you are
  wearing, a small badge appears at the edge of the screen; hovering it shows
  your character side by side in both versions, with turn-together previews, so
  you can choose on appearance. Accept equips it, decline dismisses it for good.
  Looting the same declined item again stays silent. `/gw styles` reviews them,
  `/gw styles reset` forgets the declined list.
- The upgrade prompt was redesigned to match the panel, with larger item icons,
  quality-coloured names, a score banner and a queue count.
- **Space** equips while the upgrade prompt is open, the way it accepts a quest
  at an NPC. It yields to typing, combat, popups and NPC windows, and can be
  turned off with `/gw space off`.

## Map

- The continuous map remembers its position, zoom and layer for the rest of the
  play session only. Closing and reopening returns you to the same place; a
  reload or relog starts fresh on the map the game opens. The view is no longer
  written to saved variables, and any previously saved views are discarded.

## Fixes

- Peddler's settings no longer show stale values after a change made elsewhere.
- Removed three dead loop increments in Peddler that would break under a newer
  Lua, and guarded XP Counter's popup bridge against an unloaded database.
- Rounded slider values before formatting rather than handing `%d` a float.
- A refused setting write no longer leaves its tick box showing a value the
  setting never took.

Upgrade by replacing the `MiniQoL` addon folder with the folder from
`MiniQoL-1.1.0.zip`, then reload the UI. Existing saved settings are preserved.
For a first installation, move only the standalone `Peddler`, `Gearwise`,
`Wayfinder` and `XPCounter` folders outside `AddOns`; keep all other addons.

Validation: scope, settings, panel, NPC dialogue, native mixin and session-only
map-view checks pass; 60 Lua files compile and all 61 selected source references
resolve. In-game verification remains pending.
