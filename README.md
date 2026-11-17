# EstiDmg

Shows the estimated damage of enemy casts and channels above nameplates and the target and focus frames, like Estimated Heals does for heals.

## Features

- **Estimated damage** - a number like `~12,345` while an enemy casts a damaging spell.
- **Nameplates, target, focus** - each can be switched off separately.
- **Remembered** - settings are saved per account; default is off.
- **Settings page** - all options in the game's settings and the addon compartment menu.

Limits: the number is the first damage value in the spell's description, so it is a rough estimate. Spells without a damage number show nothing. Where the game hides enemy spell IDs, nothing is shown either.

## Install

1. Download `EstiDmg-X.Y.Z.zip` from the releases.
2. Unzip it into the game's `Interface/AddOns/` folder.
3. Restart the game or type `/reload`.

## Usage

```text
/estidmg          show the current state
/estidmg on       turn the estimates on
/estidmg off      turn the estimates off
/estidmg config   open the settings page
/estidmg help     list all commands
```

## Examples

- Turn it on once with `/estidmg on`, then watch the number above a caster's nameplate.
- Only want the target frame: open `/estidmg config` and untick Nameplates.
- Quick switch off in a dungeon: `/edmg off`.

## Develop

Check the code with [Luacheck](https://github.com/lunarmodules/luacheck) before each commit
(CI runs it on every push):

```text
luacheck .
```

Release: push an annotated tag `vX.Y.Z`; GitHub Actions packages the addon with the
BigWigs packager and publishes it.

## License

All rights reserved, see [LICENSE](LICENSE).
