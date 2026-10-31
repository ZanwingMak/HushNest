# Third-party notices

Application code and the original HushNest icon / synthesized audio use the repository MIT license (Copyright 2026 ZHENYING MAI).

The cross-platform sleep pack is independent of the original iOS resources. Six longer CC0 field recordings are trimmed, filtered, normalized and crossfaded into circular PCM WAVs. Attribution, public full-length preview URLs, source/output SHA256 checksums and signal analysis are in `assets/sleep/FieldRecordings.json`; that manifest is distributed with every target and linked in Web Settings.

| Sound | Recording / author | License |
| --- | --- | --- |
| Rain | [long_easy_rain_08.wav — joedeshon](https://freesound.org/people/joedeshon/sounds/430765/) | CC0 1.0 |
| Ocean | [Gentle Ocean Waves Mix (2018) — esh9419](https://freesound.org/people/esh9419/sounds/417797/), with CC0 sources by subtyrant and indieground | CC0 1.0 |
| Stream | [Water Stream 03 — sammerz_](https://freesound.org/people/sammerz_/sounds/864286/) | CC0 1.0 |
| Forest | [Spring forest (nature) — gadesound / Konrad Lesniak](https://freesound.org/people/gadesound/sounds/653519/) | CC0 1.0 |
| Fireplace | [Fireplace for Six Minutes (Stereo) — petebuchwald](https://freesound.org/people/petebuchwald/sounds/496130/) | CC0 1.0 |
| Night | [Quiet Night Atmosphere – Soft Crickets — Goldenboy76](https://freesound.org/people/Goldenboy76/sounds/857163/) | CC0 1.0 |

[CC0 1.0 Public Domain Dedication](https://creativecommons.org/publicdomain/zero/1.0/). The new full-length brown/pink noise generator and its output use the repository MIT license. The original iOS recordings and their manifest remain unchanged; only original alarm WAVs are reused by cross-platform builds.

The Windows WASAPI audio helper uses NAudio.Wasapi and NAudio.Core 2.2.1, copyright Mark Heath and contributors, MIT: https://github.com/naudio/NAudio/blob/v2.2.1/license.txt .

The desktop host and native Go UI use MyGo 0.7.3 (MIT), https://github.com/egoist/mygo . Its license is preserved in `desktop/licenses/MyGo.LICENSE.txt` and copied into desktop packages. Native desktop windows do not create a WebView. No React frontend, Electron or Chromium engine is distributed in desktop packages. Go dependencies include purego, go-text/typesetting (Unlicense OR BSD-3-Clause), and golang.org/x/image, x/net and x/text; their full license texts are copied into the desktop `licenses/` resource directory.

React, Capacitor, Vite, Tailwind CSS, Phosphor Icons, sharp and the build tooling retain their respective licenses in npm dependencies. NAudio's MIT notice is also included in the Windows helper output by its build script. The macOS audio helper is original HushNest code and uses Apple system frameworks.

User-imported media is private local content and is not covered by the project license. No imported media is bundled or uploaded.
