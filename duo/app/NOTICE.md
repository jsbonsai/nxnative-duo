# NOTICE

Duo Builder (`duo/app`) is part of nxnative-duo and is distributed under this repository's MIT licence
(see `../../LICENSE`).

## Ported from NX2Apple

`Sources/DuoBuilder/PipeReader.swift` is ported from NX2Apple's macOS front end
(<https://github.com/LNPANDY/NX2Apple>, `frontend/Sources/NSPortBuilder/`), which is MIT licensed; the file carries
its provenance line. The rest of the app's first version also drew on NX2Apple (key checks, device lists, failure
cards); those files were replaced when the app moved to `bin/duo` as its only backend (2026-10-30).

```
MIT License

Copyright (c) 2026 seedds
Copyright (c) 2026 jhaizhou
Copyright (c) 2026 LNPANDY and NX2Apple contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### The files, and what changed

| File | Ported | Adaptation |
|---|---|---|
| `KeyCheck.swift` | logic verbatim (prod.keys parsing, AES-XTS, NCA header reading, the verdict and its message table) | `KeyCheckLine` uses SF Symbols and system colours instead of `LauncherPalette` and `.manrope`; its English wording lives in `KeyCheckCopy` (DropView.swift) because this app has no localisation table. |
| `AppSignature.swift` | verbatim | the expiry line's wording comes from `DevExpiryCopy` (DoneView.swift). |
| `Devices.swift` | verbatim (`AppleDevice`, `SigningTeam`, `XcodeTeam`, `DeviceTools`) | none. |
| `PipeReader.swift` | verbatim | none. |
| `BuildFailure.swift` | the kind list, the classifier table, `classify`, `classifyInstall`, `gameName(in:)` verbatim | `GameLibrary.onUnmountedVolume` inlined as `BuildFailureClassifier.onUnmountedVolume`; `overrideFlag` and `MetalPin` left out — bin/duo exposes no `--allow-*` pass-through and always builds with `--allow-other-metal`. |
| `BuildFailureView.swift` | the card's structure (what happened, next step, a button that does it) | bound to this app's `BuildModel`, English wording table beside the kinds, "Build anyway" removed with `overrideFlag`. Buttons limited to what the app can do: open Xcode, show the folder, choose prod.keys, try again. |
| `InputStaging.swift` | verbatim | none. |
| `CloudFolder.swift` | verbatim | none. |
| `BundledTools.swift` | verbatim | `nonisolated` modifiers dropped (the enum is not an actor; it is already non-isolated). |
| `DropFiles.swift` | `GameFilesDrop` (the drop-target view, and the `loadDataRepresentation` collection of paths) | the four-slot library model became this app's two inputs: `take(dropped:)` and `BuildInputs`, which also decides when a drop must be staged. Palette colours became system colours. |

### Not taken

* `EmbeddedFonts.swift` (the Manrope font) — the app draws with system fonts, so neither the font files nor
  the Manrope OFL text are needed here.
