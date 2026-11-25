# Tree Regrowth & Saplings (TreeRegrow)

For Factorio 2.1 / Space Age. Works with or without the Space Age expansion;
it does not touch Space Age's agricultural tree-seed system.

Factorio 2.0 players: use version 0.1.1.

## What it does

- **Forests regrow.** Every 5 seconds the mod tests a handful of random map
  locations per surface. Where living trees exist, one may seed a new tree of
  the same species a few tiles away — but only onto natural terrain (tiles the
  world generates: grass, dirt, sand...). Concrete, stone brick, refined
  concrete, hazard concrete and landfill never accept seeds.
- **Decorative single trees.** Because spreading requires natural ground, a
  tree fully ringed by paving stays exactly where it is, forever, alone.
- **Saplings.** Mining a living tree has a 25% chance (configurable) to also
  drop a *tree sapling*. The cheap **Forestry** technology (25 automation
  science) unlocks crafting saplings from 4 wood (can be disabled). Place a
  sapling like any building: it goes in as a *planted sapling* and grows into
  a real tree after a minute (configurable, or instantly), matching the
  dominant species within 16 tiles, or the default green tree in a treeless
  area.
- **Robots plant trees.** Trees themselves can't be ghosts, but planted
  saplings can: put them in blueprints, or use the **Reforest planner**
  (shortcut bar). Drag over an area and it fills the natural ground with
  sapling ghosts in a loose, natural scatter (spacing is a per-player
  setting); alt-drag removes them. Construction robots plant them from the
  saplings in your inventory or logistic network. Since chopping trees drops
  saplings, clearing land for a build gives you what you need to replant it
  somewhere else.
- **Leaves grow back.** Pollution strips leaves off trees, and since Factorio
  2.1.24 the game never gives them back. TreeRegrow does: once a chunk's
  pollution drops below 60 (configurable), its trees regrow their leaves,
  taking 30 minutes (configurable) to go from bare to full.
- **GMO trees.** A technology (200 red + green science, after Forestry) that
  lets trees regrow leaves at any pollution level. Pollution still strips
  them, and trees absorb pollution as they lose leaves, so forests next to
  your factory keep cleaning the air instead of wearing out. Expect a
  smaller pollution cloud and fewer attacks.
- **Sensible limits.** Spreading respects a local density cap (forests creep
  outward instead of solidifying), skips polluted ground by default, and dead
  or dry trees never propagate.

Everything is tunable in *Settings → Mod settings*.

## Install

Drop `TreeRegrow_0.2.0.zip` into `%APPDATA%\Factorio\mods`.

For other mods: `remote.call("treeregrow", "reforest", surface_index, {{x1, y1}, {x2, y2}}, spacing, force_name)`
plans saplings over an area (it returns how many), and `"unplan"` removes them.

## Quick test

Set "Spread attempts per cycle" to 200 in map settings, stand near a forest
edge on natural ground, and watch new trees appear within a minute or two.

## License

MIT — see [LICENSE](LICENSE).
