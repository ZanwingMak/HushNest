# Third-party notices

Application code and the original HushNest icon / synthesized audio use the repository MIT license (Copyright 2026 ZHENYING MAI).

The six field recordings are reused without modifying the source WAV files. Authors, source links, CC0 / public-domain licenses, and checksums are preserved in `../HushNest/Resources/FieldRecordings.json`, copied to every target at build time and linked in Settings.

The Windows WASAPI audio helper uses NAudio.Wasapi and NAudio.Core 2.2.1, copyright Mark Heath and contributors, MIT: https://github.com/naudio/NAudio/blob/v2.2.1/license.txt .

The desktop host uses MyGo 0.7.3 (MIT), https://github.com/egoist/mygo . Its license is preserved in `desktop/licenses/MyGo.LICENSE.txt` and copied into desktop packages. Windows uses the installed WebView2 Runtime; macOS uses WKWebView. No Electron or bundled Chromium engine is distributed.

React, Capacitor, Vite, Tailwind CSS, Phosphor Icons, sharp and the build tooling retain their respective licenses in npm dependencies. NAudio's MIT notice is also included in the Windows helper output by its build script. The macOS audio helper is original HushNest code and uses Apple system frameworks.

User-imported media is private local content and is not covered by the project license. No imported media is bundled or uploaded.
