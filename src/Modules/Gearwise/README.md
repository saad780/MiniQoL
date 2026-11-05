# Gearwise for WoW Forever

Gearwise compares equipment for your selected build. Green up arrows and red down arrows appear at the top right of item icons in bags (including Bagnon) and quest rewards. Equipment your character cannot currently wear gets a red shade.

A gold coin at the bottom left marks the quest reward choice worth the most at a vendor, including the reward quantity. It waits for all sale prices to load and ignores guaranteed rewards. The coin stays visible alongside upgrade/downgrade arrows at the top right, including when the same item is both an upgrade and the best sale.

Newly obtained upgrades open a compact, movable comparison window showing the current item, replacement, and expected item stat gains and losses. A two-handed weapon comparison includes both displaced weapons. The larger **Equip upgrade** button equips into the displayed slot; **Keep current** dismisses it. Hover either item for its tooltip. Prompts wait until combat ends and recheck your gear before equipping. The game's binding confirmation still applies.

The first login or reload records your existing inventory without prompting for it. Sorting bags or swapping gear does not count as obtaining an item. Use `/gw upgrades` to review upgrades already in your bags.

Small improvements count too: an otherwise identical 10-armor chest upgrades an 8-armor chest. `/gw upgrades` refreshes item data and reports upgrades found, comparisons still loading, or why there are no upgrades.

Profession and utility tools, including fishing poles, mining picks, skinning knives, blacksmith hammers, spanners and chisels, receive no combat gear arrows, red unusable tint, or equip recommendation. Detection uses item categories rather than localized names.

Leveling caster/healer builds value melee weapon DPS below level 20. Weapon changes use precise API DPS, or calculate DPS from damage and speed when the API value is missing; rounding is applied only to the final displayed change. For example, Worn Mace to Forsaken Maul shows +0.8 Weapon DPS even though the individual tooltips round to 1.1 and 1.8 DPS.

- `/gw` opens settings.
- `/gw spec <build>` or `/gw spec auto` chooses a build.
- `/gw arrows on|off` controls bag and quest arrows.
- `/gw unusable on|off` controls red equipment shading.
- `/gw popups on|off` controls upgrade prompts.
- `/gw tooltip on|off` controls tooltip comparisons.
- `/gw debug` reports visible item comparison states and the latest item-data errors.

Scores and changes estimate item stats, not final character-sheet totals, simulated damage, special effects, or set bonuses. Wearable items unsuited to the selected build are not marked as physically unusable.

Copy the addon files and `Media` folder to `World of Warcraft/_classic_beta_/Interface/AddOns/Gearwise/`, then type `/reload` in game. This version targets interface 16001. Automated checks use Lua 5.1 with a simulated game API; final appearance and protected equip behavior require in-game verification.
