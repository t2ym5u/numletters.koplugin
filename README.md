# numletters.koplugin

A **Chiffres et Lettres** display plugin for [KOReader](https://github.com/koreader/koreader) — the classic French TV word-and-numbers game for table play.

## Screenshot

![Screenshot](images/numletters.png)

## Concept

Two round types alternate around the table:

**Letters round** — Draw 9 letters one by one (Vowel or Consonant). When all 9 are drawn the countdown starts. Every player finds the longest word they can make using each drawn letter at most once. Tap *Solutions* to reveal all valid words, grouped by length.

**Numbers round** — 6 random numbers (1–100) are drawn and a 3-digit target is shown. Players use +, −, ×, ÷ to combine the numbers and reach (or get closest to) the target. Everyone writes their calculation on paper and compares.

No typing during play — pen and paper only.

## Rules

**Letters round:** Draw 9 letters (Vowel / Consonant). Find the longest word using each letter at most once. Longest word wins; tap **Solutions** to reveal all valid words.

**Numbers round:** 6 numbers drawn (1–100) + a 3-digit target. Combine them with +, −, ×, ÷ to reach (or get closest to) the target. Exact match scores 10 pts; within 1–5 scores 7; within 6–10 scores 5.

## Features

- **Letters mode** — 9-letter draw with Vowel / Consonant buttons, 45-second countdown
- **Numbers mode** — 6 numbers + 3-digit target, 45-second countdown
- **Solutions reveal** — all valid dictionary words grouped and sorted by length (letters mode)
- **Two dictionaries** — EN (105,145 words) and FR (132,778 words), both 3-9 letters, so either language can produce the full nine-tile solutions; shared with `boggle.koplugin`
- **E-ink friendly** — tile display is static during play; only the timer digit refreshes in fast/A2 mode

## Controls

### Letters round

| Button | Action |
|--------|--------|
| **Voyelle / Vowel** | Draw a vowel tile |
| **Consonne / Consonant** | Draw a consonant tile |
| **Solutions** | Stop timer and reveal all valid words |
| **Nouvelle manche / New round** | Clear the board and start over |

### Numbers round

| Button | Action |
|--------|--------|
| **Nouveaux chiffres / New numbers** | Draw 6 numbers + new target |
| **Solutions** | Stop timer (no solver — compare on paper) |

### Common

| Button | Action |
|--------|--------|
| **Lettres / Chiffres** | Switch between Letters and Numbers mode |
| **Menu** | New game, Language (word list), Rules |
| **Rules** | Show rules reminder |
| **Close** | Exit |

## Scoring (standard Chiffres et Lettres)

**Letters:** longest valid word wins. Equal length = tie.

**Numbers:** exact target = 10 pts; within 5 = 7 pts; within 10 = 5 pts; furthest away = 0.

Adjust scoring to your house rules — in solo the plugin tracks no scores; players use paper.

## Multiplayer

Pick **Numbers and Letters · multiplayer** under Tools → Games → Party & quiz
(or *Mode: Multiplayer* in the menu). Lay the reader in the middle of the
table: it draws, runs the clock, checks the answers and keeps the scores.

- **Settings:** Players (2–8) and Player names (remembered), Rounds (4, 6, 8
  or 10), Time (30, 45 or 60 s, default 30 as on the show; the numbers round
  gets 15 s more), Language (dictionary).
- **A match** alternates letters and numbers rounds. Everyone writes on
  paper; when the time is up, tap each player's name to type their word or
  the number they reached (empty is fine), then **Check answers**.
- **Letters:** a word counts if it is in the dictionary and uses only the
  drawn letters. The longest valid word(s) score their length; ties all
  score.
- **Numbers:** players say their calculation aloud. Only the closest
  answer(s) score — exact 10, within 5 → 7, within 10 → 5, further 0 (the
  TV rule); ties all score. A number the drawn numbers cannot make at all
  (checked by the built-in solver) scores 0.
- After each round the screen lists everyone's result, the best possible
  words or a solution (step by step), and the standings. After the last
  round a final scoreboard names the winner; **New game** starts again.
- A match in progress is saved when you close the game and restored next
  time. Solo play is unchanged.

## Installation

### Via KOReader Plugin Manager

```
numletters.koplugin/ → KOReader plugins/ folder
game-common/          → alongside plugins/ (shared library)
```

> **Note:** the zip already bundles `board.lua`, `words_en.lua` and `words_fr.lua`
> from `boggle.koplugin`, so you do **not** need to install Boggle separately.

### Manual

1. Download `numletters.zip` from [Releases](../../releases).
2. Extract to your KOReader `plugins/` directory.
3. Restart KOReader — **Chiffres et Lettres** appears in the Tools menu.

## Development

`numletters.koplugin/` lives inside the
[koreader-plugins](https://github.com/t2ym5u/koreader-plugins) monorepo.
`board.lua`, `words_en.lua` and `words_fr.lua` are symlinks to `boggle.koplugin/`
in the dev tree; they are copied as real files into the distribution zip.

## License

GPL-3.0
