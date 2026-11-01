# XIVPetBar

A pet HP / MP / TP bar for Final Fantasy XI ([Windower 4](https://www.windower.net/)) in
[xivbar](https://github.com/Windower/Lua/tree/dev/addons/xivbar)'s style, under xivbar's player bar, with the pet's name above it
and a job line on the right. Shows whenever you have a pet out (main job or subjob).

| Job | Job line |
|---|---|
| SMN | Blood Pact: Rage and Ward recasts |
| BST | Ready charges (x/3) with time to the next charge, Reward recast |
| PUP | Active maneuvers by element (x2, x3), OVERLOAD warning, Repair recast; automaton HP/MP shown as real numbers |
| DRG | Spirit Link and Steady Wing recasts |
| GEO | Luopan HP only (no MP/TP) |

Most pets only report HP% and MP%, so those show as percentages. Avatars have no MP and luopans
have no MP or TP; those segments show "-".

It reads xivbar's `data\settings.xml` (never writes it) and uses xivbar's theme images, so moving
or re-theming xivbar moves and re-themes this bar too. It is a separate addon so Windower updates
to xivbar can't wipe it.

## Install

Requires the official **xivbar** addon (installed from the Windower launcher), whose theme images
this bar uses.

1. Copy the `XIVPetBar` folder into `Windower4\addons\`.
2. Load it: `//lua load XIVPetBar`, or add `lua load XIVPetBar` to `Windower4\scripts\init.txt`
   to load it at every launch. If you use the PetTP addon, unload it so the two don't overlap.

## Commands (`//petbar` or `//xpb`)

- `full` / `compact`: bar size (xivbar's two backgrounds)
- `scale 0.8`: scale the whole bar (0.5 to 2)
- `theme ffxi`: ffxiv, ffxi, ffxiv-legacy, or `auto` (same as xivbar)
- `pos 0 10`: move it from the default spot under xivbar, in pixels (x, y)
- `extras off`: hide the job line
- `test`: show a sample pet to preview the look; run again to stop
- `reset`: back to defaults

Your choices are saved per character in `data\settings.xml` and come back at the next login.
`ReadyChargeSeconds` (default 30) is the BST Ready charge time; lower it if gear or job points shorten it.

## Credits

- Look, layout numbers and theme images from [xivbar](https://github.com/Windower/Lua/tree/dev/addons/xivbar) by SirEdeonX (BSD 3-Clause).
- Pet packet handling modeled on the PetTP addon by SnickySnacks.
- Written by Someonesmall with Claude (Anthropic).

## License

BSD 3-Clause, see [LICENSE](LICENSE). The original xivbar notices are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
