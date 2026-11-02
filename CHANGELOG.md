# Changelog

All notable changes to this project will be documented in this file.

## [1.4.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.4.0] - 2026-10-30

### Changed
- The interface text now follows KOReader's language. Until now every label
  followed the game's Language setting, which only picks the word list;
  that setting now applies to the letters and dictionary alone.
- Redesigned play screen, in line with the other games: a full-width action
  bar and a board that fills the available room. The nine letter slots are
  shown as tiles from the first draw, the six numbers as a row of tiles
  under the timer, and the status line reads "Letters · Drawn: n/9" or
  "Numbers · Target: n" and wraps in landscape instead of being cut off.
- Title-bar menu in the same order as every other game: New game (new),
  "Language: EN" (was "Language / Langue"), Rules.
- The solutions list scrolls when it is longer than the room left for it.
- New README screenshot.

### Fixed
- Text was sized in pixels and then scaled again by the screen DPI, so the
  tiles, the timer and the target came out far too big on high-DPI screens;
  everything is now fitted to its box.
- A new numbers round briefly showed the time left over from the previous
  round instead of the full countdown.

## [1.3.1] - 2026-10-01

### Fixed
- Picks up game-common v1.5.0. Play statistics were recorded under a key no
  tool could match: `ReaderUI`/`FileManager:registerModule()` rewrite a plugin
  instance's `name` to `reader<id>` / `filemanager<id>` right after it is
  built, so this game's sessions were split across two rows and neither
  carried its plugin id. Rows written under the old keys are merged back on
  first read. The same release brings the `stopPlugin()` /
  `deletePluginSettings()` hooks KOReader 2026.07 calls when a plugin is
  deleted from the device (PR #15240).

  No change to this plugin's own code -- it inherits all of it from the
  shared library.

## [1.3.0] - 2026-09-30

### Added
- French dictionary goes from 47,435 to **132,778 words**, now covering 3-9
  letters instead of stopping at 7. The 3-7 letter words are the original CC0
  Scrabble-valid list; the 8- and 9-letter words come from
  `an-array-of-french-words` (MIT), normalized the same way.
- This removes the asymmetry the English dictionary work had inverted rather
  than fixed: only English could reach the longest words. Both languages now
  cover the full nine-tile draw.


## [1.2.0] - 2026-09-30

### Added
- English dictionary goes from 1,837 to **105,145 words** (3-9 letters), from
  the Public-Domain ENABLE word-game list. It is the only one of the two that
  covers the full 9-tile draw, so 8- and 9-letter solutions appear in English
  rounds; the French list is still capped at 7 letters.

### Changed
- `findSolutions` builds its letter-availability map in lowercase, the way the
  dictionary stores words, instead of uppercasing every entry as it scans. With
  a 105k-word dictionary that one allocation per word dominated the round:
  33ms -> 9ms, same solutions.
