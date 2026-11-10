# Licenses

SewLens drafts patterns with [FreeSewing](https://freesewing.eu/) 4.x. `@freesewing/core` and the design, plugin, i18n, and config packages used here are MIT licensed. Copyright Joost De Cock and the FreeSewing contributors.

The pattern service also uses:

| Package | License |
|---|---|
| pdf-lib | MIT |
| @pdf-lib/fontkit | MIT |
| firebase-functions | Apache-2.0 |
| firebase-admin | Apache-2.0 |

Fonts embedded in the PDF:

| Font | License |
|---|---|
| Noto Sans | SIL Open Font License 1.1 |
| Kosugi Maru | SIL Open Font License 1.1 |

Fonts in the app (`assets/fonts`, license text in `assets/fonts/OFL.txt`):

| Font | License |
|---|---|
| Noto Sans | SIL Open Font License 1.1 |
| Noto Sans JP, subset to kana, JIS level 1 kanji and the app's strings (`functions/scripts/subset-jp-font.mjs`) | SIL Open Font License 1.1 |

Build tools: `subset-font` (BSD-3-Clause) makes the Japanese subset.
