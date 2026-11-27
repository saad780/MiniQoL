# Brief: a zone quest route for Mini QoL

A handoff for whoever builds item 3 from the Better Zone Map review: a suggested
order for the quests you're on in a zone, drawn on the maps and followed by the
arrow. It covers what Better Zone Map does and how, what Mini QoL already has
to build on, and the traps to avoid.

## Licensing

Better Zone Map (BorkMcGork, v1.3.20) is installed at
`C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\BetterZoneMap`
(the route is `QuestRoute.lua`, about 3,700 lines; its walking data is in
`BetterZoneMap_Paths`). It ships with no license, so it is all-rights-reserved.
Read it to understand the behaviour, but write your own code, choose your own
constants, and never copy its code or its generated data (`PathData.lua`,
`GroundData.lua`, `InteriorData.lua`). The user's credit rule: credit only
material actually copied, never projects used as inspiration.

## What the feature does, from the player's side

- Numbered stops on the map, joined by a line, giving an order for every quest
  you're on in the current zone, starting from where you stand. Every turn-in
  comes after that quest's objectives.
- Three kinds of stop. New quests to pick up are light with a "!", objectives
  are dark, and turn-ins are gold with a "?". Stops within ~35 yd share one
  marker, and two objectives of the same quest share one from further apart
  (~110 yd), with the marker placed between them.
- Hovering a stop shows what to do there (each quest, each objective and its
  progress).
- Plain click: tracks that stop's quest. A stop with several quests tracks the
  next one on each click.
- Ctrl+click: leaves the stop out of the route (kept per character). Clicking
  again brings it back. Skipped stops can optionally stay visible, grayed, with
  an x. `/bzm route reset` brings them all back. Skips are forgotten once the
  quest is handed in or dropped.
- Shift+click: go to this stop next (its ring turns blue). The rest of the route
  is re-planned from it. Shift+click again lets the planner choose.
- Optional pickups: available quests whose giver is in this zone (as Questie
  shows them) join the route when the detour is worth it. If all of a new
  quest's objectives are also in this zone, its pickup, objectives and turn-in
  are planned as one chain. Otherwise only the pickup is planned, for when you
  pass the giver anyway. Pickups are limited to the free slots in your quest
  log and to a level window ("up to +N levels", "down to -N", "green quests
  only", "any"). Profession quests for a profession you don't have are skipped.
  `/bzm route why` lists the quests left off and the reason for each.
- An arrow (TomTom's, in their case) points at the next stop. Along the walking
  route it aims at each corner in turn, while the distance and time shown are
  for the whole walk to the stop. Once you reach a stop's creatures, the line
  and the arrow give way to an outline of the area you're in.
- Re-planning: about a second after any quest change, and when you've moved
  ~120 yd from where the route was planned (optional). The order you're already
  following is kept unless a new one is clearly shorter (~5%), so the route
  doesn't reshuffle under you.
- Settings: on/off, include turn-ins, include pickups, avoid enemy towns,
  follow the way on foot, keep to roads, keep out of deep water, point the
  arrow at the next stop, re-plan as I move, outline the area I'm in, dashed or
  solid line, show skipped stops, line opacity, stop marker size, detour worth
  per new quest (100 to 5000 yd), and the pickup level window.

## How Better Zone Map does it

### Data: everything comes from Questie

- **Quests you're on**: Questie's quest log (its `QuestiePlayer`/`QuestieDB`
  quest objects). Each has `Objectives[i]` with `Needed`, `Collected` and
  `spawnList[npcOrObjectId] = { Name, Spawns = { [areaId] = { {x, y, phase}, ... } } }`,
  plus `SpecialObjectives`. Coordinates are 0-100 on the area's map;
  `ZoneDB:GetUiMapIdByAreaId` converts an area to a uiMapID. Spawns of
  (-1, -1) are inside dungeons. Spawns in a phase you can't see are dropped with
  `Phasing.IsSpawnVisible`.
- **Turn-ins**: the quest's `Finisher` (NPC and object ids → `QuestieDB:GetNPC`
  spawns, keeping friendly NPCs only). Spots near the game's own turn-in marker
  are preferred (`C_QuestLog.GetQuestsOnMap` gives that marker once a quest is
  complete).
- **Pickups**: the quests Questie draws as available (its own level and type
  filters apply), with the giver's spawns. A quest's objectives are looked up
  the same way, and the quest is marked "objectives elsewhere" if any objective
  lies outside the zone. A new quest's kill or item count is guessed (~6). This
  is worked out a frame at a time and cached until the set of quests on offer
  changes.
- **Enemy towns**: wherever Questie knows a flight master, innkeeper, banker or
  auctioneer who serves only the other faction. Those NPCs are clustered
  (~150 yd) into towns, each a no-go circle (radius plus ~120 yd margin, capped
  at ~350 yd). Free-for-all arenas are added by hand. A stop inside an enemy
  town stays on the route.
- **Zone level ranges** (a side feature): the 10th to 90th percentile of the
  zone's quest levels, from Questie.

### The planning model

- Each **task** is one stop to visit once, at one of several **candidates**
  `{ x, y, penalty }`. It has an `after` list of tasks that must come first (a
  turn-in after its objectives, a new quest's objectives after its pickup) and
  a stable `key` (`questID:index:areaID`) so skips and the previous order
  survive re-planning.
- **Objective candidates are camps.** Spawns are clustered (~70 yd radius,
  joining the earliest camp within reach, using a spatial grid so thousands of
  spawns stay fast). A camp's weight is its own count plus half the spawns of
  camps within ~180 yd. Camps with less than ~30% of the busiest camp's weight
  are dropped, unless only one more kill is needed. The ~10 nearest good camps
  are kept, and the busiest always is. Each candidate costs a penalty of about
  25 yd per kill still needed beyond the camp's weight, capped at ~250 yd.
  Camps are cached per objective until the quest log changes.
- **Turn-in and pickup candidates** are the ~6 nearest spawns of the NPC.
- The route is **open**: it starts at the player and ends at the last stop.
  Distances are in yards on the zone (map size from the walk grid or the
  game). A leg that crosses an enemy town bends around it, which counts toward
  its length.
- **Too many tasks**: keep the nearest ~26, quests already in your log before
  new ones. Drop any task left without a prerequisite.
- **Optional chains**: each new quest is a chain. A pickup alone is worth
  ~100 yd of detour; a quest's objectives and turn-in are worth the "detour per
  new quest" setting. The chain costing most beyond its worth goes first, until
  every chain left pays for itself and the count fits the free log slots.
- **The search**, about 8 ms in total:
  1. Greedy: always the nearest available task (prerequisites done), at its
     nearest camp counting the penalty.
  2. Best camps for a fixed order, by dynamic programming: the cheapest way to
     reach each candidate of stop k from any candidate of stop k-1.
  3. Local search until nothing helps: move each single task to its best legal
     position and camp; move short runs of 2 or 3 consecutive tasks (so a
     pickup and its objective, or an objective and its turn-in, move together);
     2-opt reversal of stretches with no internal prerequisites.
  4. Perturb and re-improve ("shakes", seeded so the same input gives the same
     route); keep any shorter result.
  5. Compare against the order you were following, both improved from where
     it stands and as it is, and keep yours unless the new one is ~5% shorter.
  6. For routes of 7 or more stops, keep refining in 2 ms slices a frame
     afterwards. Swap in a better route only if it's ~1% shorter.
- **Walking distances are learned**: the planner starts from straight lines.
  As each leg's real walking path comes back, its length is stored by the pair
  of walk-grid cells it joins. For pairs not yet measured, the straight line is
  stretched by the average detour seen so far. The route is re-planned with
  what's been learned (up to 3 rounds per task set). Once every leg is
  measured, the shortest measured route wins.
- **A quick re-plan**: when only progress changed (a kill, not a new or
  finished objective), it just re-picks camps for the same order.

### Walking paths

BZM ships its own walkability grid per zone, generated offline from terrain
and buildings, with deep water and roads in a separate layer. It runs A* over
it a few milliseconds per frame, with water and off-road steps costing extra,
enemy towns avoided, and hand-made tunnel entries for towns like Booty Bay.
**Mini QoL doesn't need any of this.** It bundles Polestar's walking router
(`src/Modules/Wayfinder/Vendor/PolestarWalking`, through `Walking.lua`), with
road styles, hostile-hub costs and zone danger already built in.

### Drawing

- The line is dashed or solid, its width constant on screen. Dashes start from
  the far end so they don't crawl as you move, and points closer together than
  a few pixels are dropped. When zoomed in, only the visible part plus half a
  view around it is drawn.
- Stops sit on a non-panning layer, each placed on a whole pixel so the number
  doesn't wobble inside its circle. The player's arrow is redrawn above a stop
  you're standing on.
- The leg from you to the next stop is drawn a little stronger.

## What Mini QoL already has to build on

All paths are under `src/Modules/Wayfinder/` unless noted.

- **Questie access**: `QuestWaypoints.lua` reads Questie through
  `QuestieLoader._modules` without creating modules (`QuestieModule(name)`),
  waits for `Questie.API.isReady`, and uses `TrackerMapEligibility`,
  `DistanceUtils`, `ZoneDB` and `Phasing`.
- **Camps** (added in this branch): `QuestWaypoints.Camps(spawns)`,
  `QuestWaypoints.CampCost(camp, left, wx, wy)` and
  `QuestWaypoints.Outline(points)`. These are the same camp idea with our own
  constants and code, already used by middle-click quest following. Reuse them
  for objective candidates.
- **World coordinates**: `ns.MapToWorld`, `ns.WorldToMapRect`, `ns.GetMapRect`,
  `ns.GetPlayerWorld` and `ns.Distance` (in `Geometry.lua`). Yards, with x
  north and y west.
- **Walking router**: `Navigation.lua`'s `AskWalk`/`UpdateWalk` show how to call
  `ns.Walking.Nav.Path.Find(cont, from, to, done, options)` (asynchronous jobs,
  options `style`, `profile`, `danger`, `waterWalking`) and how failures are
  handled. `Travel.lua` prices a failed walk at 3× its straight line
  (`FAILED_WALK`) rather than ruling it out. Do the same: the router refuses
  starts it can't verify, because Forever gives no player height.
- **The arrow**: `Navigation:PlaceSourceWaypoint("route", ...)` gives the route
  its own single waypoint on the arrow. It moves along like Polestar's and the
  quest follower's. The arrow already shows the walk left and the time
  (`arrowTime`), and it rests inside a waypoint's `area` (`Navigation.InArea`,
  `Navigation:GetArea`, with the outline drawn by `AntTrails.lua`). Give the
  route waypoint the stop's `area` and you get BZM's "outline the area I'm in"
  for free.
- **Drawing surfaces**: `AntTrails.lua` already draws dots on the continuous
  world map, the minimap and the zone map (Shift+M), with the projection math
  for each. The route line can be another set of dots (static or slowly
  marching, in its own color) on the same surfaces. Numbered stop markers can
  be Wayfinder pins through `MapPins.lua`'s providers, which exist on both the
  world map and the zone map and handle the combat passthrough problem.
- **Background work**: `Background.lua` (`ns.Background:Queue(key, fn)`) runs
  cooperative jobs under one shared frame budget. Run planning and refinement
  there, not in your own OnUpdate.
- **Error flood guard**: wrap per-frame code in `ns.Guarded(fn, label)`.
- **Settings**: defaults in `ns.defaults` (`Core.lua`), and UI in
  `src/MiniQoL/Integrations.lua` (`wayfinder(...)`, `wayfinderSlider(...)`,
  `feature{ kind = "select" }`) on the "maps" page.
- **Menus**: use `ns.ContextMenu` (controller-safe) for any right-click menu.
- **Tests**: lupa (Lua 5.1) harness in `tests/`, wired in `tests/run.py`. The
  planner should be plain functions with no WoW API so it's easy to test (BZM
  exposes `ns.RoutePlanner` for the same reason). Build with
  `python tools/build.py --output build/<fresh dir>` (it refuses to overwrite
  an existing folder), then run `python tests/run.py build/<dir>/MiniQoL`.

## Traps to avoid

- **Tracking from addon code is taint.** BZM's "click a stop to track its
  quest" calls the game's tracking functions. Their notes say that changes to
  tracking made from addon code count as the addon's: the quest tracker later
  fails on auras after a level-up, and a hidden world map carries the taint
  into the next click on it in combat. With the Gamepad UI on, the world map
  and the super-tracking frame break outright. Prefer pointing Mini QoL's own
  arrow at the stop. If you must track, never do it in combat, and test with
  the Gamepad UI on.
- **Don't read the game's shared quest caches** (`GetQuestsOnMapCached`,
  `QuestCache`, `MapUtil` caches) from addon code. Call `C_QuestLog` directly.
  See the zone-map provider in `MapPins.lua`.
- **Never write Blizzard map state in combat.** See the
  `waitingView`/`afterCombat`/`CombatOver` handling in
  `Vendor/OpenMap/WorldMap.lua`.
- **Performance**: BZM's `/bzm perf` exists because routes with thousands of
  dashes made the game stutter. Cap what you draw, cull to the view, and spread
  planning over frames.
- **Secret values (12.x)**: guard anything read from units or the quest log
  with `ns.Readable`.
- **Forever specifics**: realms have no name (see the character-key notes),
  UnitPosition gives no usable height, and Questie on Forever loads its data a
  few seconds after login. Wait for `Questie.API.isReady` and retry.

## Suggested shape

- `QuestRoute.lua`: a pure planner (tasks → order and camps). Unit-tested.
- `QuestRouteData.lua`: tasks from Questie and the quest log, plus cached
  pickups. Spread over frames.
- `QuestRouteView.lua`: stop pins on both maps, the line on AntTrails-style
  surfaces, the clicks (follow, skip, next), and the arrow waypoint with the
  stop's area.
- Settings on the Maps & travel page, and `/mqol route` (`why`, `reset`).
