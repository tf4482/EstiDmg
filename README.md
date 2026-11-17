# EstiDmg

Marks the estimated damage of casts on enemy health bars, like Estimated Heals does for incoming heals.

## Features

- **Damage bar** - a red part of the health bar shows the expected health loss while an enemy casts a damaging spell.
- **Own casts** - your own cast shows its damage on your target.
- **Nameplates, target, focus** - each can be switched off separately, as can own casts.
- **Bar color and opacity** - pick a preset or any color with the color picker, separately for unit frames and nameplates (dark red by default), and set how solid the bar is.
- **Other UI addons** - tested with Platynator; it may work with other unit frame and nameplate addons.
- **Remembered** - settings are saved per account; default is on.
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
/estidmg color frames   pick a free color for unit frames
/estidmg color plates   pick a free color for nameplates
/estidmg config   open the settings page
/estidmg help     list all commands
```

## Examples

- Just play: it is on by default, so watch the bar on a caster's nameplate.
- Only want the target frame: open `/estidmg config` and untick Nameplates.
- See what your big spell will do: target an enemy and start casting, the bar shows the expected loss.
- Quick switch off in a dungeon: `/esd off` (`/edmg` works too).

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
