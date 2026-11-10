# Factory Radar

A Factorio mod: one window that shows what happens in your factory and in your team. Planets and their science, space platforms with routes and cargo, power grids, research, quality, combat, an item search over planets, platforms and players, power grids with warnings and a journal, and for co-op: who is where, shift summaries, MVP vote, titles and achievements.

Works in a solo game and with friends. Factorio 2.0 and 2.1, with or without Space Age and Quality. Languages: English and Russian.

Mod portal page: https://mods.factorio.com/mod/factory-radar

## Versions

| Mod version | Factorio |
| --- | --- |
| 1.0.x | 2.0 (2.0.36 or newer) |
| 1.1.x | 2.1 (2.1.7 or newer) |

Both come from the same source. A release of a mod on the portal has one game version, so the build script writes the right `info.json` and changelog for each. Space Exploration is an optional dependency on 2.1: when SE is active (without Space Age), the same mod shows SE planets, moons, orbits and asteroid zones. No separate SE mod is needed.

## Layout

```
src/factory-radar/    the mod itself (info.json, control.lua, data*.lua, scripts/, locale/, graphics/)
  scripts/compat_se.lua  optional Space Exploration adapter (activates only when SE is installed)
tests/                GUI test that runs the mod against a mock of the game API, and an rcon helper
tools/                build.py (makes the zips), check.py (locale keys, changelog format)
portal/               text of the mod portal page
```

## Build and test

```
python tools/build.py              # dist/for-2.0/factory-radar_1.0.x.zip
python tools/build.py --game 2.1   # dist/for-2.1/factory-radar_1.1.x.zip
python tools/check.py              # ru/en keys match, changelog format
pip install lupa
python tests/run_tr.py ru          # GUI test without the game (also: en, STRESS=1, STRICT=1, SE=1)
```

The tests do not replace a run in the game. The mock only checks that every tab builds and that no text keys are missing.

## Notes for contributors

- All player texts exist in `ru` and `en` with the same keys (`tools/check.py` checks this).
- Saved data lives in `storage.tr`, accessed only through `C.D()` in `scripts/core.lua`.
- Nothing local may influence game state: this is a multiplayer mod.
- Code comments are in Russian.

## License

MIT, see the LICENSE file.
