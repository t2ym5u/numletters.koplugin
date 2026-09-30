# Changelog

All notable changes to this project will be documented in this file.

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
