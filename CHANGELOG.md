# Changelog

All notable changes to this project will be documented in this file.

## [1.6.2] - 2026-11-04

### Fixed
- A game no longer crashes when an outdated plugin is installed alongside:
  shared modules left behind by an older plugin are replaced by this
  plugin's own copy instead of being used as they are.

## [1.6.1] - 2026-11-04

### Changed
- Uses less memory: the game loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unplayed.
- Uses less memory: the word lists load when the game opens, only for the
  language played, and are freed when it closes.

## [1.6.0] - 2026-11-04

### Changed
- Finding every word for the drawn letters is about 8 times faster: up to
  0.1 s on a desktop (over 2 s on a reader) before, about 0.01 s now. Same
  words listed.
- The numbers solver (best answer and its steps) is about a third faster
  (worst seen ~15 ms -> ~11 ms on a desktop). Same answers.

## [1.5.1] - 2026-11-03

### Changed
- Picks up game-common 1.11.0: the shared on-screen keyboard (where used)
  gives every key the same letter size, and the no-repeat history helper.

## [1.5.0] - 2026-11-02

### Added
- Multiplayer mode, listed as "Numbers and Letters · multiplayer" under
  Tools → Games → Party & quiz (or Mode: Multiplayer in the menu). The
  reader lies in the middle of the table and runs a match of letters and
  numbers rounds in turn (Rounds: 4–10) with a clock (Time: 30, 45 or 60 s;
  the numbers round gets 15 s more). When the time is up, each player's word
  or number is typed in, then checked: the longest valid word(s) score their
  length; in the numbers round only the closest answer(s) score (exact 10,
  within 5 → 7, within 10 → 5), and a number the draw cannot make scores
  nothing. Each round then shows the best possible words or a solution, and
  the scores; a final scoreboard names the winner. Player names are
  remembered, and a match in progress is saved and restored.
- Separate rules for the multiplayer mode, reachable from the solo rules.

### Changed
- The countdown now refreshes only its own digits each second, not the
  whole screen.
- Family-friendly words: the best words revealed after a letters round
  leave out vulgar, sexual, scatological, slur and drug-related words
  (`blocklist.lua`). A player's own word is still checked against the whole
  dictionary.

### Fixed
- The English word list is now always numletters' own. It was loaded by a
  module name shared with the other word games, so with one of them
  installed the letters round could check words against that game's
  (different) English list.

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
