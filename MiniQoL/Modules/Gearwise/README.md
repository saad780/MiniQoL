# Gearwise for WoW Forever

Gearwise compares equipment for your selected build. Green up arrows and red down arrows appear at the top right of item icons in bags (including Bagnon) and quest rewards. Equipment your character cannot currently wear gets a red shade.

A gold coin at the bottom left marks the quest reward choice worth the most at a vendor, including the reward quantity. It waits for all sale prices to load and ignores guaranteed rewards. The coin stays visible alongside upgrade/downgrade arrows at the top right, including when the same item is both an upgrade and the best sale.

Newly obtained upgrades open a compact, movable comparison window showing the current item, replacement, and expected item stat gains and losses. A two-handed weapon comparison includes both displaced weapons. **Equip upgrade** equips into the displayed slot. **Keep current** saves your choice for that character and stops automatic prompts for that upgrade. Hover either item for its tooltip. Prompts wait until combat ends and recheck your gear before equipping. The game's binding confirmation still applies.

The first login or reload records your existing inventory without prompting for it. Sorting bags or swapping gear does not count as obtaining an item. Use `/gw upgrades` to review upgrades already in your bags, including ones you declined.

Gear you carry before you can wear it is remembered: a sword two levels ahead, mail before level 40, an off-hand weapon before dual wield, a bow before the skill is trained. The prompt opens when the level or the skill arrives, and says the item can be worn now. With several upgrades waiting, the biggest gain is offered first, so equipping it retires the lesser pieces for the same slot; the count on the prompt is a count of upgrades.

Small improvements count too: an otherwise identical 10-armor chest upgrades an 8-armor chest. `/gw upgrades` refreshes item data and reports upgrades found, comparisons still loading, or why there are no upgrades.

Profession and utility tools, including fishing poles, mining picks, skinning knives, blacksmith hammers, spanners and chisels, receive no combat gear arrows, red unusable tint, or equip recommendation. Detection uses item categories rather than localized names.

What each build is advised follows how it fights:

- Warriors and rogues weigh a ranged weapon mostly by the stats on it, and a little by its damage, so a plainly better throwing knife, bow or gun is an upgrade. Hunters weigh a melee weapon the same way.
- Hunters are not offered a throwing weapon for the ranged slot: shots need a bow, gun or crossbow.
- Shield builds (Protection, Enhancement Tank) keep the off hand for a shield. A second weapon or a held item is not weighed against one.
- With two weapons, the harder-hitting one is offered for the main hand; the weapon it pushes out is then offered for the off hand.

Leveling caster/healer builds value melee weapon DPS below level 20. Weapon changes use precise API DPS, or calculate DPS from damage and speed when the API value is missing; rounding is applied only to the final displayed change. For example, Worn Mace to Forsaken Maul shows +0.8 Weapon DPS even though the individual tooltips round to 1.1 and 1.8 DPS.

The values behind the advice can be changed. The Gear advice page lists what one point of each stat is worth to your build, one row per stat the build weighs, so the list differs by class and build. Drag a value to say how much you care about it; it applies to that build on that character only, and the build's own value is shown beside it. Setting a value back, **Reset**, or `/gw values reset` restores the defaults, which are never overwritten. Tooltips say "Your values" while any are changed.

- `/gw` opens settings.
- `/gw spec <build>` or `/gw spec auto` chooses a build.
- `/gw values` opens the stat values; `/gw values reset` puts the current build back on its own.
- `/gw arrows on|off` controls bag and quest arrows.
- `/gw unusable on|off` controls red equipment shading.
- `/gw popups on|off` controls upgrade prompts.
- `/gw tooltip on|off` controls tooltip comparisons.
- `/gw debug` reports visible item comparison states and the latest item-data errors.

Scores use your build's stat weights. Simple weapon procs use the live effect amount and a tooltip or WoWSims Forever trigger rate. An unknown rate can show the frequency needed to beat your equipped weapon. Comparisons include supported set bonuses gained or lost and can preview additional swaps with pieces in your bags or personal bank. Tooltips identify estimates and effects that need manual review.

Copy the addon files and `Media` folder to `World of Warcraft/_classic_beta_/Interface/AddOns/Gearwise/`, then type `/reload` in game. This version targets interface 16001. Automated checks use Lua 5.1 with a simulated game API; final appearance and protected equip behavior require in-game verification.
