# UI plan — implementing the "Shelf" redesign

Derived from `design-handoff/IMPLEMENTATION.md` (the spec) and `design-handoff/COPY.md` (the strings). The order
follows the spec's own §15 build order. The branch is rebased on `duo` (the PS2 CLI, `docs/COPY-STYLE.md` and its
tests are in); PS2-specific work is marked below. Each item names the spec sections it implements, the files it touches, and
whether it is pure styling or needs model/plumbing work.

Two standing rules for every item:

- A sentence that is not in `COPY.md` is not written. Copy is transcribed into `Sources/DuoBuilder/Copy.swift` and
  views read it from there.
- If the data a screen needs does not exist in `bin/duo`, the screen ships without that element (spec §3) and the
  gap is listed in `DESIGN-QUESTIONS.md`. Nothing is synthesised in Swift to fill it.

Risk is about the chance of the item changing behaviour the app already gets right, or of needing a decision the
spec does not make. "CLI gap" means the screen can only render its designed state from a fixture, not from the live
CLI, until the parent adds the command/field.

---

## 1. Design tokens and shared views

- **Spec:** §4 (colour roles, type, spacing, radii, support states), §5 (shared components), §11 (light/dark,
  accessibility, motion).
- **Files:** `Sources/DuoBuilder/DuoTheme.swift` (new, from `design-handoff/DuoTheme.swift`), `DuoBuilderApp.swift`.
- **Type:** styling.
- **Work:** transcribe the tokens exactly; make the reference code compile against the package's macOS 13 target
  (the spec says macOS 14+, the package still says `.macOS(.v13)` — `@Observable` is avoided, `.snappy` is used only
  behind an availability check or replaced by an equivalent curve); add the missing component states the screens
  need (slot placeholder, room bar, details disclosure); fix the reference's small defects rather than redesigning.
- **Risk:** low. The reference is explicitly "not yet compiled"; expect naming and overload fixes, not design
  changes.

## 2. Copy deck transcription

- **Spec:** §0 (`COPY.md`), §6 all screens, §9 (register).
- **Files:** `Sources/DuoBuilder/Copy.swift` (new).
- **Type:** styling (strings only), plus a few pure formatting helpers.
- **Work:** every key in `COPY.md` becomes a constant or a small function taking the placeholders
  (console names are replaced by the owner's later file-format rule; the delta is listed in `DESIGN-QUESTIONS.md`
  §B)
  (`<game>`, `<phone>`, `<n>`, `<date>`, `<size>`, `<v>`). Dates use "Sat, Nov 7"; durations use the existing
  `StageCopy.duration` formats ("52s", "14m 32s"), stage elapsed uses "0m 42s" as drawn in `12`.
- **Risk:** low, but placeholders whose source data does not exist are marked here and in `DESIGN-QUESTIONS.md`
  rather than filled with a guess.

## 3. Window, phases, top bar, status strip, device pill

- **Spec:** §2.1 (720×560, hidden title bar), §2.2 (one root phase machine + transitions), §5 (`TopBar`,
  `DevicePill`, `StatusStrip`), §7.2 (pill menu).
- **Files:** `DuoBuilderApp.swift`, `Views.swift` → `RootView`, `Components.swift` (new), `AppModel.swift`,
  `DeviceStore.swift` (new).
- **Type:** plumbing (phase replaces the current `screen` switch) + styling.
- **Work:** 720×560 window; `Phase` with the six cases; opacity+scale transition, scale dropped under Reduce
  Motion; 52 pt top band on Home/Card/Reading, 44 pt on Working/Failed/Done; device pill with connected-first menu,
  greyed "(not connected)" phones, "On This iPhone…" and "Set Up a New iPhone…"; status strip with the ready line
  or "N things to set up", "Not affiliated with Nintendo", and the Setup link.
- **Risk:** medium. The current model's single `screen` enum drives everything; the refactor must not lose the
  6-second device poll or the "no project folder" error path.

## 4. Models and stores

- **Spec:** §2.3 (stores), §9 (persistence), §3 (CLI contract), §10 (expiry arithmetic).
- **Files:** `Models.swift`, `LibraryStore.swift` (new), `InstallsStore.swift` (new), `SettingsStore.swift` (new),
  `AppModel.swift`, `Pipeline.swift`, `Failure.swift` (new), `CacheProbe.swift` (new).
- **Type:** plumbing / model.
- **Work:**
  - `LibraryEntry` exactly as §9, saved to `~/Library/Application Support/Duo Builder/library.json`; security-scoped
    bookmarks for files (falls back to a stale bookmark + "Locate…" when the file moved); banner PNG cached at
    256 px; `cacheKey` set from the prepared-build path convention (spec §3 allows "a path convention").
  - `InstallsStore` decodes a per-device installs document (bundle id, title, install date, profile expiry, free
    bytes, weekly app IDs left) from the contract the spec asks the CLI for. Live, `bin/duo` has no such command,
    so the store is `.unavailable` and views omit slots/installs (marked CLI gap).
  - `SettingsStore`: reminder, auto-renew, selected device, saved as `settings.json`.
- **Risk:** high. Bookmark APIs and the Application Support location are the app's first persistence; a bug here
  means the shelf cannot reopen a game. The CLI-gap fields are typed now so the parent can fill them without a UI
  rewrite.

## 5. Home: first run, shelf, library, add tile

- **Spec:** §6.01, §6.02, §5 (`SlotCard`, `LibraryTile`, `AddGameTile`).
- **Files:** `Views.swift` → `HomeView`, `Components.swift`, `LibraryStore.swift`, `AppModel.swift`.
- **Type:** styling + plumbing.
- **Work:** "On this iPhone" header and three `SlotCard`s (install order; expiring by colour, never position; free
  slot last, itself a drop target) or, first run, three dashed "Slot 1/2/3" placeholders and the 230 pt dashed drop
  area + welcome column; Library header count; 5-column `LazyVGrid`, 16 pt column gap, 18 pt row gap; `AddGameTile`
  first; tile status line (`Ready · about 1 min` / `Not built yet` / `On <phone>` / `New to nxnative` /
  `May not start`) and PS2 tag; most-recently-used sort, games on the selected phone after the others; status strip
  pinned.
- **Risk:** medium-high. The slots and phone-specific ordering depend on installs data that only fixtures have
  today (CLI gap). First run is fully live.

## 6. Drag and drop: whole-window overlay

- **Spec:** §6.03, §8, §5 (`DropOverlay`).
- **Files:** `Components.swift` (`DropOverlay`), `RootView`, `AppModel`.
- **Type:** plumbing.
- **Work:** SwiftUI's `onDrop(of: [.fileURL], isTargeted:)` accepts the drop; while the target is hot, the drag
  pasteboard (`NSPasteboard(name: .drag)`) is polled for the file URLs, because `onDrop` reports only *that*
  something is over the window and §6.03 names the files during hover. Overlay inset 16 pt under the top band,
  accent dashed 2 pt border, radius 22, 12% fill, content dimmed to 25%; centred 380 pt panel with per-file rows
  classified by extension only; "These aren't game files" + orange border when nothing is supported; while Working
  the overlay is orange and says "Wait for <game> to finish"; the free slot highlights while targeted.
- **Risk:** medium. The poll only runs while SwiftUI reports a targeted drop, and a preview model skips it so the
  renderer's hover state survives.

## 7. Reading the game

- **Spec:** §6.04.
- **Files:** `Views.swift` → `ReadingView`, `AppModel.swift`, `AppModel+Read.swift` if needed.
- **Type:** styling + small plumbing (phase, 400 ms skip).
- **Work:** card-shaped skeleton, 176 pt placeholder + spinner, "Reading the game…", monospaced file name, grey
  placeholder chips/panels, footer sentence + Cancel; skip to the card when reading finishes in under ~400 ms.
- **Risk:** low-medium. `duo info` emits no progress stream, so the designed real bar/count is omitted (CLI gap);
  the skeleton must not imply progress it does not have.

## 8. Game card, all four variants

- **Spec:** §6.06 (other version + Duo pack), §6.07 (cartridge/new/blocked), §6.08 (PS2), §6.09 (tested/cached),
  §4.4, §5 (`SupportBadge`, `FileChip`, `PictureRow`, `NextStepsStrip`, `PrimaryActionButton`).
- **Files:** `Views.swift` → `CardView`, `Components.swift`, `Models.swift`, `AppModel.swift`, `CacheProbe.swift`.
- **Type:** styling + plumbing (support mapping, reasons, cache probe, PS2 branch).
- **Work:** back pill + device pill; 176 pt banner (radius 26, shadow); title/meta; support badge; file chips
  (ok/add/problem); cartridge picker; picture row with Duo toggle or static original-shape panel; "What happens
  next" strip with real durations and slot use; cached-build info row; primary button + red reason line; card
  footer. `.iso (ps2)` branch: `.iso` banner tag, "Disc image · size", the BIOS chip from the user's Setup choice
  (and the title's `bios: required` state), the room panel stating the requirement without a phone free-space
  number, and the PS2 copy step.
- **Risk:** high. Support-state mapping must not merge the four states; file-set problems arrive as one CLI
  sentence, not per-file roles, so the red chip's ✕ (remove one file) and the "belongs to <other game>" reason are
  not representable (CLI gap; the existing sentence is shown as the reason). "About 2 minutes" for the build step is
  only shown from measured data (none today), per §5. The cached-build state is detected by the build path
  convention the pipeline uses. PS2 has no phone-free-space number and no cache; `ps2.bios` is the title's
  requirement, not proof a dump is present.

## 9. Working: stage timeline

- **Spec:** §6.11, §6.12, §6.13, §5 (`StageTimeline`, `DetailsDisclosure`), §3 (`plan`, `eta_seconds`, `copy`).
- **Files:** `ProgressEvent.swift`, `StageTracker.swift` (new, pure), `BuildRunner.swift` (new), `Views.swift` →
  `WorkingView`, `Components.swift`.
- **Type:** plumbing.
- **Work:** header (64 pt banner, 17 pt game name, meta "picture · to phone · elapsed so far", overall %);
  vertical timeline with done (green ✓ + elapsed), active (accent ring + headline + bar + count line + ETA when the
  pipeline sends one, "time left: not known yet" otherwise), pending; the graphics row carries the long-one hint;
  only the active stage is expanded; stage names mapped by the §6.11 table (unmapped pipeline stages keep their own
  name, as today); Details disclosure with the monospaced log; footer sentence + Cancel; the PS2 copy panel and two
  info cells when a `copy` stage arrives. The nine `.iso (ps2)` stages use the names in `duo/ps2.md`
  (`reading-disc`, `reading-executable`, `translating`, `exploring`, `compiling-vu`/`vu-aot`, `building`/`linking`,
  `verifying`) and the wrapper's six outer steps.
- **Risk:** high. There is no `plan` event, so future rows cannot be drawn honestly: the timeline shows stages
  already reached (spec §3's explicit fallback). Elapsed times are measured in Swift from event timestamps,
  allowed by §3. Stage mapping has to cover the pipeline's real inner names (`shader split`, `iOS shaders`,
  `GLSLC capture`, …) without merging two rows into one.

## 10. Failed

- **Spec:** §6.14, §5, §3 (`code`), `FailureLadder` table.
- **Files:** `Failure.swift` (new), `Views.swift` → `FailedView`, `AppModel.swift`.
- **Type:** plumbing + styling.
- **Work:** same header as Working without %; red panel with octagon glyph, "Install stopped" and the failure
  sentence; "WHAT YOU CAN DO" ladder chosen by `code` from one table (`slots_full`, `app_id_limit`, `device_gone`,
  `device_locked`, `trust_needed`, `disk_full_mac`, `disk_full_phone`, `signing_failed`, `unknown`); the paid-account
  tip only for limit codes; installed-game chips with days left for `slots_full`; footer Details / Back to Shelf /
  Try Again.
- **Risk:** high. `bin/duo` emits no failure codes; the live app can only use the `unknown` ladder plus the CLI
  sentence (CLI gap). The ladder table is written now so the CLI change is the only missing piece. "How to switch"
  has no destination (help content does not exist; see questions).

## 11. Done

- **Spec:** §6.15, §6.16, §10, §7.4.
- **Files:** `Views.swift` → `DoneView`, `Components.swift`, `InstallsStore.swift`, `SettingsStore.swift`,
  `Reminders.swift` (new).
- **Type:** plumbing + styling.
- **Work:** 112 pt banner with green check badge; "<game> is on <phone>" or "<game> is renewed"; real expiry line
  and duration; Trust panel on the first install of this Apple ID on this phone, otherwise the "Open it…" line;
  slot row for that phone with the new/renewed one outlined green; reminder checkbox (persisted; permission asked
  when first ticked); Back to Shelf.
- **Risk:** high. Expiry dates and slot contents need installs data (CLI gap), so live the screen shows the
  headline, duration, Trust step and open line without the slot row. The two reference renders disagree about the
  renewed variant's slot row and checkbox (questions).

## 12. Setup sheet: one ordered checklist

- **Spec:** §6.10, §5 (`SetupStepRow`), §8.3, §7.1 (⌘,).
- **Files:** `Views.swift` → `SetupSheet`, `SetupStore.swift` (new), `Components.swift`, `AppModel.swift`.
- **Type:** styling + plumbing.
- **Work:** 560×520 sheet; header/title/subtitle; one 4 pt segment per step in list order; one `ScrollView` list in
  the fixed order (Xcode → … → Free space), done rows folded to 30 pt with the value right, running row expanded
  with the accent panel, needs-you rows expanded with orange outline and action; "Files from your own console ·
  at least one" group with per-file Choose…; auto-scroll to the first not-done row with the floating "N done above"
  capsule; failed Fix → "Try Again" + "Show what happened"; footer sentence + Check Again + Done.
- **Risk:** high. The doctor has no progress percentage for a running fix (streamed lines only) and no BIOS item
  (the app's own Setup choice stands in). `ps2-tools` and `ps2-space` appear only where the `.iso (ps2)` pipeline is
  installed. Done values come from doctor details; where a detail is a path or a sentence the row shows the part the
  design asks for (e.g. "signed in") and the full detail on expansion. The metal item exists only when Xcode's
  compiler differs from the tested one, so the list can legitimately be 10 or 13 rows; segments follow the list.

## 13. On this iPhone / renew sheet

- **Spec:** §6.17, §10, §7.1/§7.2 entry points.
- **Files:** `Views.swift` → `RenewSheet`, `InstallsStore.swift`, `SettingsStore.swift`, `Components.swift`.
- **Type:** plumbing + styling.
- **Work:** 560×490 sheet; per-phone segmented control; subtitle; rows with 44 pt art, name, days till expiry,
  4 pt bar, bordered Renew; expiring rows tinted; reminder + auto-renew checkboxes; weekly line only if the count
  is trustworthy; footer connection status, Close, Renew All (estimate only after a renew has been measured).
- **Risk:** high. Needs `duo device apps` and `duo renew` (CLI gap); the sheet and its menu are gated on installs
  data being available, so it renders from fixtures until the CLI exists.

## 14. Menus, commands, context menus, notifications

- **Spec:** §7.1–§7.4.
- **Files:** `DuoBuilderApp.swift` (commands), `Components.swift` (context menus), `Reminders.swift`,
  `SettingsStore.swift`.
- **Type:** plumbing.
- **Work:** File/Phone/Window/Help commands from the table with their shortcuts and enablement; device pill menu;
  library-tile and slot-card context menus; Esc/⌘. cancels Reading/Working with the 10-minute confirmation;
  expiry reminder and build-finished notifications (permission on first tick only).
- **Risk:** medium. Two Help items have no content in the repo (no help page, no limits page); they are listed as
  a question instead of inventing copy. Notification scheduling depends on expiry dates (CLI gap).

## 15. Snapshot fixtures and renderer

- **Spec:** §12, §0 screen index, §15 acceptance.
- **Files:** `Snapshot.swift`, `fixtures/` (new), `package.sh` (UTType declarations).
- **Type:** plumbing (test/rendering support).
- **Work:** one `--fixtures <dir>` flag loading `doctor*.json`, `library.json`, `installs*.json`, `info-*.json`,
  `run-*.json`, `failure-*.json` and `done-*.json` (the old `--info`/`--doctor` still work); render every state in
  both appearances at 720×560 with this pack's screen numbers and an appearance suffix
  (`02-home-dark.png`, `02-home-light.png`, …); before/after renders kept under `snapshots/`.
- **Risk:** medium. The fixtures are test inputs, not shipped data; they must decode into the same store types the
  live app uses, or the renders would prove nothing.

## 16. App icon

- **Spec:** §13.
- **Files:** `Snapshot.swift` → `AppIcon`, `package.sh`.
- **Type:** styling.
- **Work:** none until the owner picks A, B or C; the current abstract icon stays. The chosen direction is drawn
  in code and regenerated at packaging time.
- **Risk:** low, purely a decision.

## 17. Verification

- **Spec:** §15 acceptance checklist, §11 contrast/VoiceOver/keyboard.
- **Files:** all, `Tests/DuoBuilderTests/`.
- **Type:** verification.
- **Work:** `swift build`, `swift test`; render every fixture state twice (before/after); check one filled accent
  button per screen, four distinct support states, banned words, no progress/ETA the pipeline did not send, Cancel
  visible on Reading/Working/Copying, reasons under disabled buttons, Setup one ordered list, both appearances.
- **Risk:** low.

---

## What the current CLI cannot express (parent decisions)

These are the §3 rows with no live source today. Each screen ships without the element, from the spec's own rule,
and renders its designed state only from a fixture.

| §3 need | Screens | Status in `bin/duo` | Question |
|---|---|---|---|
| `plan` event (stage list up front) | 11–13 | absent | Q1 in `DESIGN-QUESTIONS.md` |
| `copy` stage (bytes/rate) | 13 | present for `.iso (ps2)` (`duo ps2 build`, outer step 5) | — |
| `device apps --json` (bundle id, title, install date, expiry) | 02, 14, 15, 16, 17 | absent | Q2 |
| `renew <bundle-id>` | 02, 16, 17 | absent | Q2 |
| `cache list --json` or a path convention | 02, 09 | no command; path convention used | Q3 |
| per-file role/mismatch reason | 07 | one `problems` sentence only | Q4 |
| phone free space | 08, 13 | cannot be measured through devicectl; the card shows `ps2.size_bytes` + 512 MB headroom | Q5 |
| weekly new-app-ID count | 17 | absent | Q2 |
| stable failure `code` | 14 | absent (sentences only) | Q6 |
| `.iso (ps2)` card/build, BIOS, doctor rows | 08, 13, setup group | present (`duo ps2 info/build`, `ps2-tools`, `ps2-space`, `--bios`) | Q5 |
| measured build/renew durations | 06, 09, 17 | absent | Q7 |
| help content ("How to switch", Help menu) | 14, menu bar | absent | Q8 |
