# Tree Regrowth & Saplings (TreeRegrow)

For Factorio 2.0 / Space Age. Works with or without the Space Age expansion;
it does not touch Space Age's agricultural tree-seed system.

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
  science) unlocks crafting saplings from 2 wood (can be disabled). Place a
  sapling like any building: it becomes a real tree that
  matches the dominant species within 16 tiles — or the default green tree in
  a treeless area. Blueprint tree layouts and let construction bots plant them.
- **Sensible limits.** Spreading respects a local density cap (forests creep
  outward instead of solidifying), skips polluted ground by default, and dead
  or dry trees never propagate.

Everything is tunable in *Settings → Mod settings*.

## Install

Drop `TreeRegrow_0.1.1.zip` into `%APPDATA%\Factorio\mods`.

## Quick test

Set "Spread attempts per cycle" to 200 in map settings, stand near a forest
edge on natural ground, and watch new trees appear within a minute or two.

## License

MIT — see [LICENSE](LICENSE).
