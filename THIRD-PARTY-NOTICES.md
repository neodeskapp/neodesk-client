# Third-party notices

Fonts and pictures from other projects that the NeoDesk client ships, with
their licences. The licence texts are next to the files.

| What | Files | Licence |
|---|---|---|
| Material Symbols Outlined (Google), version 2.978, static subsets at weight 400, grade 0, optical size 20; source commit, glyph list and hashes in `MaterialSymbols-VERSION.txt` | `flutter/assets/fonts/NdSymbols.ttf`, `NdSymbolsFilled.ttf` | Apache License 2.0, `flutter/assets/fonts/MaterialSymbols-LICENSE.txt` |
| IBM Plex Sans and IBM Plex Mono (IBM) | `flutter/assets/fonts/IBMPlex*.ttf` | SIL Open Font License 1.1, `flutter/assets/fonts/IBMPlex-OFL.txt` |
| Funnel Display | `flutter/assets/fonts/FunnelDisplay-*.ttf` | SIL Open Font License 1.1, `flutter/assets/fonts/FunnelDisplay-OFL.txt` |
| Twemoji flags (Twitter) | `flutter/assets/flags/*.svg` | CC BY 4.0 |
| Phosphor operating system marks | `flutter/assets/nd-os-*.svg` | MIT |

`flutter/tool/build_symbols.py` rebuilds the Material Symbols subsets from
`flutter/tool/nd_symbols.txt` and rewrites the version file.
