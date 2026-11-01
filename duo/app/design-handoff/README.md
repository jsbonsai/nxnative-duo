# Design handoff — "Shelf" redesign (2026-10-31)

Unzipped from `duo-builder-shelf-handoff.zip`. This folder is the designer's pack, kept verbatim as the
reference for the implementation. Nothing here is compiled or shipped as an asset.

| Path | What it is | Where it goes in the app |
|---|---|---|
| `IMPLEMENTATION.md` | The implementation guide (screens, tokens, CLI needs, build order). | Reference only. The numbered work list derived from it is `../UI-PLAN.md`. |
| `COPY.md` | Every user-facing string, grouped by screen. | Transcribed verbatim into `Sources/DuoBuilder/Copy.swift`. That file is the only place view code reads a sentence from. |
| `DuoTheme.swift` | Reference code for the design tokens and shared views (§4–§5). | Adapted into `Sources/DuoBuilder/DuoTheme.swift` (made to compile against the package's macOS 13 deployment target and the app's existing names). |
| `screens/*.png` | @2x pixel references of every screen (720×560 pt). | Reference only. `../snapshots/` holds renders from the real app, named the same way so they can be diffed. |
| `assets/icon-A-refined-current.png` | App-icon direction A (refined current). | Reference only, and currently unused: §13 leaves the choice of A/B/C to the owner. The app icon is drawn in code by the `AppIcon` view in `Sources/DuoBuilder/Snapshot.swift` and regenerated to `AppIcon.icns` by `package.sh`. |
| `assets/icon-B-shelf.png` | App-icon direction B (shelf). | Same. |
| `assets/icon-C-fold.png` | App-icon direction C (fold). | Same. |

Rules for using this folder:

- The PNGs are pixel references, not assets to ship. Game banners in them are placeholder gradients with invented
  names; the real app keeps extracting the NACP icon from the user's own file.
- No colour token, spacing value, radius or string in the app may come from anywhere else. `DuoTheme.swift` and
  `Copy.swift` are the transcriptions; anything the pack does not state is a question in `../DESIGN-QUESTIONS.md`,
  not a decision made here.
- The live, editable source of the screens is the designer's canvas, not part of this pack.
