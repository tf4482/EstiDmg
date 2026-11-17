# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/).

## [0.1.2] - 2026-11-17

### Changed

- CurseForge uploads are named after the package, like the GitHub zip.
- The TOC targets WoW Forever only (interface 16001), so uploads no longer carry a Retail game version.

## [0.1.1] - 2026-11-17

### Fixed

- Lua error when the game hides the width of a health bar (secret value); the bar uses the last readable width instead.

### Changed

- Added the CurseForge project ID to the TOC for automatic uploads.

## [0.1.0] - 2026-11-17

### Added

- Health bar overlay marking the expected damage of enemy casts and channels on nameplates, target, and focus frames.
- Damage of the player's own casts on the target.
- Preset bar colors (dark red by default) and opacity in percent (slider in steps of 5, number box, `/estidmg opacity`) in the settings, with an optional free color picker via `Custom...` or `/estidmg color frames|plates`, set separately for unit frames and nameplates.
- Health bar lookup for other unit frame and nameplate addons, tested with Platynator.
- Optional crit extension bar with its own colors, using the player crit damage talents.
- German localization of the settings page and status messages; slash commands stay English, other clients show English.
- Settings page, addon compartment entry, and `/estidmg` command.
