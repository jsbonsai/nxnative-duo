# Duo Builder — "Shelf" redesign: implementation guide

*Response to `DESIGN.md` (v0.1.0, 2026-10-31). Audience: the engineer or coding agent implementing it in the
SwiftUI Mac app. Everything here is meant to be built with system fonts, colours and materials; nothing needs a
custom chrome layer.*

---

## 0. What is in this pack

| Path | What it is |
|---|---|
| `IMPLEMENTATION.md` | This guide. Read it top to bottom once, then use §6 per screen. |
| `COPY.md` | Every user-facing string, grouped by screen, in the register of DESIGN.md §9. |
| `DuoTheme.swift` | Design tokens (colours, type, spacing, radii) and the shared views. Written as reference code and not yet compiled; expect small fixes when adding it to the target (macOS 14+ SwiftUI). |
| `screens/*.png` | @2x renders of every screen (1440×1120 = 720×560 pt). File names match §6. |
| `assets/icon-*.png` | Three app-icon directions at 1024 px, for reference when updating the `AppIcon` view. |

The PNGs are pixel references, not assets to ship. Game banners in them are placeholder gradients with invented
game names; the real app keeps extracting the NACP icon from the user's file.

Live, editable source of every screen: the "Shelf — full set" page of the design canvas this pack came from.

### Screen index

| # | File | Screen | State it represents |
|---|---|---|---|
| 01 | `01-home-first-run.png` | Home | First launch, nothing set up, no phone, empty library |
| 02 | `02-home.png` | Home | Normal: 2 of 3 slots, one expiring, library of 9 |
| 03 | `03-home-drag-over.png` | Home | Files dragged over the window |
| 04 | `04-reading-the-game.png` | Card (loading) | After drop, before the card is known |
| 05 | `05-home-light.png` | Home | Light appearance |
| 06 | `06-card-other-version-duo-pack.png` | Game card | "Another version was tested", Duo pack on, DLC |
| 07 | `07-card-two-game-cartridge-blocked.png` | Game card | Two-game cartridge, "New to nxnative", install blocked with reason |
| 08 | `08-card-ps2.png` | Game card | PS2 `.iso`, phone free-space check |
| 09 | `09-card-tested-light.png` | Game card | "Tested with nxnative", already built, light |
| 10 | `10-setup-sheet.png` | Setup sheet | Mid-setup: 8 done, 1 running, 2 need you |
| 11 | `11-working-early.png` | Working | First stage, ETA unknown, Details open |
| 12 | `12-working-graphics.png` | Working | The long stage (graphics), with timeline |
| 13 | `13-working-ps2-copying.png` | Working | PS2 copy-to-phone stage |
| 14 | `14-failed.png` | Failed | 3-app limit hit, "what you can do" ladder |
| 15 | `15-done-trust-step.png` | Done | First install of an Apple ID on this phone → Trust step |
| 16 | `16-done-renewed-light.png` | Done | Renew finished, no Trust step, light |
| 17 | `17-on-this-iphone-renew-sheet.png` | Sheet | "On this iPhone": slots, days left, Renew, reminders |
| 18 | `18-system-tokens-components.png` | — | Tokens and component states |
| 19 | `19-app-icon-directions.png` | — | App icon A / B / C |

---

## 1. The direction in one paragraph

The app gains a memory. Home becomes a **shelf**: the top row is the phone's three free-Apple-ID slots (with days
left and Renew), and below it is a **library** of every game the user has dropped before, each tagged with whether
it reinstalls in about a minute (graphics already prepared) or still needs the first 10–40 minute build. Dropping a
file anywhere in the window still leads to the same single game card and the same one primary button. Working,
Failed and Done keep their jobs but get more honest structure: a stage timeline, a ladder of fixes, and the slot
row after success. Setup becomes a checklist that shows progress instead of a list of problems.

### How each weakness in DESIGN.md §8 is answered

| §8 item | Answer | Where |
|---|---|---|
| 1. Dead space on the card | "What happens next" strip (3 steps with real durations and slot use) fills the middle | 06, 08 |
| 2. Disabled Install is silent | Disabled primary button always has a red reason line directly beneath it, and the offending chip is red with its own remove (✕) | 07 |
| 3. Setup is a drawer | One ordered checklist; done rows fold to one line, the running row shows progress, rows that need the human are expanded and outlined; footer says closing is safe | 10 |
| 4. Working isn't reassuring | Vertical stage timeline with per-stage elapsed time; the long stage says it is the long one | 11, 12, 13 |
| 5. Done sells nothing | Shows exact expiry date, the updated slot row, an opt-in reminder, and the next step | 15, 16 |
| 6. No memory | Library, "On this iPhone" slots, Renew, reminders | 02, 17 |
| 7. Errors are one sentence | Sentence stays, then a numbered "What you can do" ladder, plus Details | 14 |
| 8. Weak drag affordances | Whole-window drop overlay that lists each file and says which ones will be left out | 03 |
| 9. "Switch" in copy | All entry copy is file-type neutral: "Drop a game", ".nsp · .xci · .iso" | 01, 02, 03 |

### Product rules (DESIGN.md §3) — how the design keeps each

- **One primary action per screen.** Every screen has exactly one filled accent button (Home: the Add Game tile is
  the only accent element; the expiring slot's Renew is a bordered secondary). Don't add a second filled button.
- **No false certainty.** Four separate support states with four colours and four icons (§4.4). Never merged.
- **Plain language.** "Preparing the game's graphics", never "shaders". See `COPY.md`.
- **Never fake progress.** Timeline rows show only stages the pipeline reported; ETA shows only when the pipeline
  gives one ("time left: not known yet" otherwise). No indeterminate shimmer pretending to be a bar.
- **Cancel always available** on Reading, Working and Copying.
- **Files stay the user's.** Said once on the card footer and on Reading; never uploaded.

---

## 2. App structure

### 2.1 Window

```swift
WindowGroup {
    RootView()
        .frame(width: 720, height: 560)          // was 680×500; brief allows up to ~720×560
}
.windowStyle(.hiddenTitleBar)
.windowResizability(.contentSize)
.defaultSize(width: 720, height: 560)
.commands { DuoCommands() }                       // §7
```

- Traffic lights stay where macOS draws them; leave a 52 pt top band (44 pt on Working/Failed/Done, which have no
  top-bar controls). Top-bar controls are vertically centred in that band, right-aligned.
- The whole window is the drop target on every phase where dropping makes sense (Home, Card). See §8.

### 2.2 Phases (one root state machine)

```swift
enum Phase: Equatable {
    case home                               // 01, 02, 05
    case reading(ReadingProgress)           // 04
    case card(GameCard)                     // 06–09
    case working(BuildRun)                  // 11–13
    case failed(BuildRun, Failure)          // 14
    case done(BuildRun, DoneInfo)           // 15, 16
}

enum ActiveSheet: Identifiable {
    case setup                              // 10
    case onThisPhone(deviceID: String)      // 17
}
```

`RootView` switches on `phase` with a `.transition(.opacity.combined(with: .scale(0.98)))` and
`.animation(.snappy, value: phaseKind)`; respect `accessibilityReduceMotion` by dropping the scale.

Drag-over (03) is **not** a phase: it is an overlay driven by `isDropTargeted` on Home and Card.

### 2.3 Stores (ObservableObject / @Observable)

| Store | Owns | Source of truth |
|---|---|---|
| `SetupStore` | Doctor items, their status, running fixes | `bin/duo doctor --json` (today's `duo-doctor.json`) |
| `DeviceStore` | Connected and known phones, selected phone | Existing 6 s poll |
| `InstallsStore` | What is on each phone, install date, expiry | **New**, see §3 |
| `LibraryStore` | Every game ever read, its files, its cached build | **New**, local JSON (§9) |
| `BuildRunner` | One running pipeline, its stages, log, cancel | `bin/duo build --json` stream |

All stores live in an `AppModel` injected with `.environment(...)`. Views never call the CLI directly.

---

## 3. CLI contract: what the UI needs

DESIGN.md §4 says every state must come from data the CLI emits. The redesign needs a few things the brief does
not list as existing. **Verify each against `bin/duo` before building the UI that depends on it**; where it is
missing, add it to the CLI rather than inventing it in Swift.

| UI need | Screens | Needed from CLI | Notes |
|---|---|---|---|
| Stage list known up front | 11–13 | A `plan` event at start listing the stages this run will go through | Lets the timeline draw future rows honestly. Without it, only draw stages already reached. |
| Per-stage elapsed time | 12, 13 | `stage_start` / `stage_end` timestamps | Swift can time these itself if the CLI only sends stage names. |
| ETA | 11–13 | `eta_seconds` when known, absent when not | Show "time left: not known yet" when absent. Never compute one in Swift from percent alone. |
| Overall % | 11–13 | Already exists | Keep. |
| Copy-to-phone progress (PS2) | 13 | `copy` stage with bytes done/total and rate | New stage, mapped to "Copying the game to the phone…". |
| What is installed on a phone | 02, 14, 15, 16, 17 | `bin/duo device apps --json`: bundle id, title, install date, profile expiry date | Prefer the profile's real expiry over "install date + 7". |
| Renew without rebuilding | 02, 16, 17 | `bin/duo renew <bundle-id> --device <id>` | Re-sign and reinstall the cached `.ipa`. |
| Cached build present? | 02, 09 | `bin/duo cache list --json` or a path convention | Drives "Ready · about 1 min". |
| File set problems | 07 | In `info` JSON: per-file role, title id, and a `mismatch` reason | e.g. update belongs to another title id → name that title if it is in the library. |
| Two-game cartridge | 07 | Already exists (picker) | Keep. |
| Phone free space | 08, 13 | `device info --json`: free bytes | PS2 only. |
| Weekly new-app-ID budget | 17 | Optional; count locally if the CLI can't report it | Show only if trustworthy. |
| Failure codes | 14 | Stable `code` per failure (`slots_full`, `device_locked`, `device_gone`, `disk_full`, …) | The ladder in §6.14 is chosen by code, never by parsing text. |

If any of these can't be provided, ship the screen without that element rather than faking it (e.g. no ETA, no
weekly budget line).

---

## 4. Design tokens

`DuoTheme.swift` in this pack implements everything below. Summary:

### 4.1 Colour roles

All semantic, appearance-aware; only the accent comes from the user's system setting.

| Role | Dark | Light | SwiftUI |
|---|---|---|---|
| Window | `#1E1E1E` | `#F6F6F8` | `Color(nsColor: .windowBackgroundColor)` |
| Panel fill | white 5% | white + hairline | `Color.primary.opacity(0.05)` dark / `.background` + `.overlay(stroke)` light |
| Status strip | `#262628` | `#EDEDF0` | `.bar` material |
| Text | `#F5F5F7` | `#1D1D1F` | `.primary` |
| Secondary text | label 60% | `#6E6E73` | `.secondary` |
| Accent | system | system | `.accentColor` / `.tint` |
| Tested · ready | `#30D158` | `#248A3D` | `.green` |
| Likely works | `#FFD60A` | `#8A6D00` | `.yellow` (dark) / custom dark-yellow in light for contrast |
| New · expiring | `#FF9F0A` | `#A33000` | `.orange` (text in light uses the darker value) |
| Being brought up | `#DA8FFF` | `#8944AB` | `.purple` |
| Stopped · error | `#FF453A` | `#D70015` | `.red` |

Rule: state colour is never the only signal. Each state colour appears with its own SF Symbol and words.

### 4.2 Type

| Token | Size / weight | Design | Used for |
|---|---|---|---|
| `title` | 28 bold | `.rounded` | Game name on the card |
| `headline` | 24 bold | `.rounded` | Done headline, first-run welcome |
| `stage` | 17 semibold | `.rounded` | Active stage headline, game name on Working |
| `section` | 15 semibold | default | "On this iPhone", "Library" |
| `body` | 13 regular | default | Most text |
| `caption` | 12 regular | default | Meta lines, counts |
| `label` | 11 semibold, +0.6 tracking, uppercase | default | "WHAT HAPPENS NEXT", "WHAT YOU CAN DO" |
| `log` | 11 | `.monospaced` | Details log |

Any number that changes over time uses `.monospacedDigit()`.

### 4.3 Spacing and radii

- Spacing scale: 4, 8, 12, 16, 22, 28 (page padding), 32 (card/working page padding).
- Radii (all `RoundedRectangle(cornerRadius:style: .continuous)`): control 8, primary button 12, panel 14,
  library tile 18, card banner 26, slot art 13.

### 4.4 Support state (never merge these)

```swift
enum SupportState {
    case tested                          // "Tested with nxnative"             checkmark.seal.fill   green
    case otherVersionTested(String)      // "Another version was tested (tested: 1.0.0) — likely works"
                                         //                                     exclamationmark.circle yellow
    case bringUp                         // "Still being brought up — may not start"  clock   purple
    case new                             // "New to nxnative — it may not start"  exclamationmark.triangle orange
}
```

Rendered by `SupportBadge` (in `DuoTheme.swift`): icon + sentence in a 10 pt-radius capsule tinted at 10–14%.

---

## 5. Shared components

Build these once; every screen is composed from them. Sketches are in `DuoTheme.swift`.

| Component | Looks like | Notes |
|---|---|---|
| `TopBar` | Right-aligned: device pill, Setup gear (Home); back pill "‹ Library" (Card/Reading) | 52 pt tall, no title text |
| `DevicePill` | Green dot + phone name + chevron; `Menu` | Disconnected phones listed greyed "(not connected)". "No iPhone yet" grey dot when none. |
| `StatusStrip` | Dot + "This Mac is ready · 41 GB free" or orange "N things to set up", right "Setup" link | Home only. 40 pt, `.bar` material, top hairline. |
| `SlotCard` | 84 pt tall: 56 pt art, name, days-left line, 4 pt bar | 3 states: healthy (green bar), expiring ≤ 2 days (orange tint + border + bordered Renew), free (dashed border, + glyph, is a drop target) |
| `LibraryTile` | Square art (18 radius), name, one status line | Status: "Ready · about 1 min" green / "Not built yet" / "New to nxnative" / "On iPhone Duo". PS2 tag top-left. Context menu §7.3. |
| `AddGameTile` | Same size as a tile, dashed accent border, accent tint 8%, + and "Add Game…" | First item in the library grid. Opens the file picker. |
| `SupportBadge` | §4.4 | |
| `FileChip` | 28 pt capsule: ✓ + "Game 1.0.0" | Variants: ok; add (dashed "+ Add update", is a button); problem (red tint/border, text names the problem, trailing ✕ button that removes the file) |
| `PictureRow` | Panel: screen glyph, title, one sentence, trailing switch or "Add a Pack…" | The only build-time choice. Toggle only when a pack exists for this phone + game. |
| `NextStepsStrip` | Label + 3 bordered cells, each title + duration | Durations must be real: "10–40 minutes, first time only", "About 2 minutes" only if measured. |
| `PrimaryActionButton` | Full width, 44 pt, radius 12, accent | `reason: String?` — when non-nil the button is disabled **and** the reason renders under it in red with an info icon. |
| `StageTimeline` | Vertical list: done (green filled circle ✓ + time), active (accent ring + headline + bar + count line), pending (hollow circle, secondary text) | Connector line green between done rows, grey otherwise. |
| `SetupStepRow` | done (30 pt one-liner), running (expanded, progress), needsYou (expanded, orange outline, action button), group (needsYou with sub-rows) | See §6.10. |
| `DetailsDisclosure` | "› Details" text button → monospaced selectable log, 104–160 pt, auto-scrolls | `TextEditor` read-only or `ScrollView` + `Text(...).textSelection(.enabled)`. |
| `DropOverlay` | Accent dashed rounded rect over the whole window + centred file list panel | §8. |

---

## 6. Screens

Each section: what the screen is for, layout from top to bottom, its data, and behaviour. Pixel reference is the PNG
of the same number. Dark is the default reference; light uses the same layout with the light column of §4.1.

### 6.01 Home — first run (`01`)

Shown when the library is empty and there are no installs. Same skeleton as normal Home so the user learns it.

- Top bar: device pill reads "No iPhone yet" with a grey dot.
- "On this iPhone" with three dashed "Slot 1/2/3" placeholders and the line "A free Apple ID gives you 3 slots, 7
  days at a time".
- Below: a 230 pt square dashed drop area (accent) on the left; on the right the welcome:
  "Your game, on your phone." (headline), one sentence, a 3-step list (1 orange badge while Setup is incomplete),
  and the **Set Up This Mac** primary button (opens the Setup sheet).
- Once Setup is complete, step 1 shows a green check and the primary button disappears; the drop area becomes the
  primary affordance.
- Status strip: "N things to set up" in orange, plus "Not affiliated with Nintendo".

### 6.02 Home (`02`, light `05`)

- Top bar: `DevicePill` ("iPhone Duo ▾"), Setup gear.
- **On this iPhone** section: header right text "2 of 3 apps · free Apple ID". Three `SlotCard`s in a 3-column grid
  (12 pt gap), in install order so cards never jump around; the expiring one is distinguished by colour, not
  position. The free slot is always last and is itself a drop target.
- **Library** section: header right text "9 games · 4 reinstall in about a minute". 5-column `LazyVGrid`, 16 pt
  column gap, 18 pt row gap. First cell is `AddGameTile`. The grid scrolls; the status strip stays pinned.
- Sort: most recently used first. Games currently on the selected phone appear in the library too ("On iPhone
  Duo") but after the others.
- Status strip as §5.
- Clicking a tile opens its card (§6.06) without re-reading the file if the file is still at its saved path; if
  the file moved, show the card with a "Locate…" chip instead of the file chips.

### 6.03 Drag over (`03`)

- Covers the full content area (inset 16 pt, below the top band): accent dashed border 2 pt, radius 22, accent fill
  12%. Underlying Home dims to 25% opacity.
- Centred panel (380 pt wide, `#2A2A2D`, radius 18): accent tile with a download glyph, "Drop to add N files",
  "Duo Builder reads them when you let go", then one row per dragged file: monospaced file name and a right label.
- File classification during hover uses **extension only** (no reading): `.xci` "game", `.nsp` "game or update",
  `.iso` "game" (PS2), anything else orange "not a game file, left out".
- If every file is unsupported: the panel title becomes "These aren't game files" and the border turns orange;
  dropping does nothing.

### 6.04 Reading the game (`04`, `11`'s first stage)

- Card-shaped skeleton: 176 pt square placeholder with a spinner, headline "Reading the game…", the file name in
  monospace, a real bar with "1.9 of ~5.0 GB · 38%", and grey placeholder chips/panels where the card will be.
- Footer: "Finding the name, version and whether this build is known to work. Nothing leaves this Mac." + Cancel.
- If reading takes under ~400 ms, skip this screen (go straight to the card) to avoid a flash.

### 6.06 Game card — other version tested, Duo pack (`06`)

Top to bottom inside 32 pt side padding:

1. Back pill "‹ Library" (top bar left after traffic lights) and `DevicePill` (right).
2. Header row: 176 pt banner (radius 26, shadow 0/12/30 black 45%) + column: title (28 bold rounded), meta
   "Publisher · Version x · size", `SupportBadge`, `FileChip`s.
3. `PictureRow` with the Duo toggle: "Duo full screen (experimental)" + the pack's own sentence. Off state:
   "Original shape" with the letterbox/crop/stretch sentence.
4. `NextStepsStrip`: "1 · Prepare the graphics — 10–40 minutes, first time only", "2 · Build the app — About 2
   minutes", "3 · Install on iPhone Duo — Uses your last free slot (3 of 3)". Step 1 becomes "Already prepared"
   when the cache exists.
5. Spacer, then `PrimaryActionButton` "Install on iPhone Duo" and the footnote "Your files stay on this Mac.
   Cancel stops everything at any point."

Button label: "Install on <phone name>". When Setup is incomplete: "Set Up and Install" (opens Setup first, then
continues automatically when Setup becomes ready).

### 6.07 Game card — cartridge, new, blocked (`07`)

Shows three things at once; each can also appear alone.

- `SupportBadge(.new)`.
- `FileChip` problem variant: "Update 1.3.0 is for another game ✕". The ✕ removes that file from the set.
- Cartridge row (panel): "This cartridge holds 2 games:" + native `Picker` (menu style).
- `PictureRow` static: "Original shape · No Duo full-screen pack for this game yet…" with a bordered
  **Add a Pack…** button (opens a JSON file picker; DESIGN.md §10.5).
- Disabled `PrimaryActionButton` with reason: "Remove the update for another game to continue. It belongs to
  Night Courier." (Name the other title only if it is in the library; otherwise "It belongs to a different game.")

### 6.08 Game card — PS2 (`08`)

- Banner gets a "PS2" tag. Meta: "Disc image · 4.2 GB".
- `SupportBadge(.bringUp)`.
- Chips: "Disc image", "Your BIOS · from Setup" (if the BIOS is missing: problem chip "Needs your PS2 BIOS ·
  Add…", and the primary button is disabled with that reason).
- Two panels side by side: "Room on <phone>" with a stacked bar (used / this game / free) and "Needs 4.4 GB ·
  61 GB free"; "Original shape" picture panel.
- `NextStepsStrip`: Build the app → Install on <phone> (slot use) → "Copy the game over · 4.2 GB by cable · keep
  it plugged in".
- If free space is short: the room bar turns red, and the button is disabled with "iPhone 16 Pro needs 4.4 GB
  free. It has 2.1 GB."

### 6.09 Game card — tested, cached (`09`, light)

- `SupportBadge(.tested)`.
- An info row with a bolt glyph: "Already built on this Mac. Installing takes **about a minute**." plus slot use
  on the right. This replaces the `NextStepsStrip` when a cached build exists.

### 6.10 Setup sheet (`10`)

`.sheet` of 560×520 attached to the window.

- Header: "Set up this Mac" (20 bold rounded) + right "8 of 11 ready"; subtitle summarising what the app is doing
  and how many steps need the human ("Duo Builder is doing 1 step now. 2 steps need you." / "Duo Builder can do all
  of it for you." / "This Mac is ready").
- Segmented progress: one 4 pt segment per required step, **in list order**, coloured green (done), accent
  (running), orange (needs you), grey (not checked yet).
- **One list, in a fixed order**, inside a `ScrollView`:
  - Done → `SetupStepRow.done`: 30 pt, green check, name, value on the right ("27.2", "signed in"). Clicking it
    expands to show details (path, version) — collapsed by default.
  - Running → expanded, accent-tinted panel, progress bar with %, "Duo Builder is doing this one. Nothing to
    click."
  - Needs you → expanded, orange outline, explanation, action button (`Fix`, `Fix…`, `App Store`, `Open Xcode`,
    `Choose…`).
  - Group "Files from your own console · at least one": two sub-rows — **Switch keys** (prod.keys, for .nsp/.xci)
    and **PS2 BIOS** (for .iso) — each with its own Choose…. The group is satisfied when either is present; the
    other then shows as optional. Each game card checks only the file its platform needs.
- On open, scroll so the first not-done row is at the top (`ScrollViewReader.scrollTo(firstPendingID,
  anchor: .top)`), and show a floating "⌃ N done above" capsule that scrolls back to the top.
- When a Fix fails: the row stays expanded, the action becomes "Try Again", and a "Show what happened" disclosure
  appears with the command output (this is the "what if Fix fails" from §8.3).
- Footer: "You can close this. The install keeps going, and Duo Builder checks again next time." + Check Again +
  Done. Running fixes must survive closing the sheet.
- Order (matches today's doctor): Xcode, Xcode first-time setup, Xcode's graphics compiler, iOS SDK, build
  tools, .NET 10 SDK, Python environment, Apple ID in Xcode, iPhone, Files from your own console, Free space.

### 6.11–6.13 Working (`11`, `12`, `13`)

- Header row: 64 pt banner, game name (17 semibold), meta "Duo full screen · to iPhone Duo · 4m 12s so far";
  right: overall % (26 bold rounded) over "overall".
- `StageTimeline` (DESIGN.md §6 headlines). Only the active stage is expanded. Map:

  | Pipeline stage | Timeline row |
  |---|---|
  | extract / decompress / build id lookup / survey | Read the game |
  | rewrite | Rebuild the game's executable |
  | shader / glsl / vulkan | Preparing the game's graphics — with "This is the long one, 10–40 minutes, and only the first time." |
  | prepare xcode, app build | Build the app for the phone |
  | ipa pack | Pack the app |
  | heap check / address regions | Checking the game's memory layout (fold into "Read the game" if it is fast) |
  | install | Install on <phone> |
  | copy (new, PS2) | Copying the game to the phone… |

- Before the long stage starts, its pending row already carries an orange "· the long one, 10–40 min" hint (11).
- PS2 copy (13): an orange panel "Keep iPhone 16 Pro plugged in and unlocked until this finishes." with the
  auto-lock path ("Settings › Display & Brightness › Auto-Lock › Never. Set it back when you're done."), plus two
  info cells: room left after this, slots after this.
- Footer: Details disclosure, one honest sentence, **Cancel** (bordered). Cancel sends SIGINT to the CLI, waits
  for it to clean up, then returns to the card. For the PS2 copy stage the sentence is "Cancel removes the
  half-copied game from the phone." — only if the CLI actually does that.
- Optional: mirror progress in the Dock tile (`NSApp.dockTile` with a progress bar) and post a notification on
  completion if the window isn't key.

### 6.14 Failed (`14`)

- Same header as Working (no %).
- Red panel: octagon-x glyph, "Install stopped", one sentence from the failure `code`.
- "WHAT YOU CAN DO" ladder: numbered rows; the first is the recommended fix (accent number badge), the rest are
  bordered. For `slots_full`: 1 Make room (chips of the three installed games with days left; "ends tomorrow" in
  orange), 2 Use another phone (Choose Phone), 3 Keep it for later.
- Under the ladder, quiet tip: "A paid Apple Developer account ($99 a year) removes the 3-app limit, and apps open
  for a year instead of 7 days." + "How to switch" link (opens a help page). Show this tip only for limit-related
  codes (`slots_full`, expiry, weekly-app-ID limit).
- Footer: Details, **Back to Shelf** (bordered), **Try Again** (primary).
- Ladder content per failure code lives in one table in code (e.g. `FailureLadder.swift`) so copy can be reviewed
  in one place. Seed codes: `slots_full`, `app_id_limit`, `device_gone`, `device_locked`, `trust_needed`,
  `disk_full_mac`, `disk_full_phone`, `signing_failed`, `unknown` (ladder: Try Again, Show Details, Copy Details for
  a bug report).

### 6.15 / 6.16 Done (`15`, `16`)

- Centred: 112–120 pt banner with a green check badge, headline "<Game> is on <phone>" or "<Game> is renewed",
  one line with the real expiry date and duration ("It opens until Sat, Nov 7. Took 52s." / "Took 14m 32s.
  Next time: about a minute.").
- Trust step panel (orange, lock glyph) only when this is the first install with this Apple ID on this phone:
  "One last step on the iPhone, this first time only — Settings › General › VPN & Device Management › your Apple ID
  › Trust. Then open the game." Otherwise the "Open it from the Home Screen. The ⚙ button…" line.
- Slot row for that phone (3 compact cards with "Until <date>"), the new or renewed one outlined green.
- Checkbox "Remind me the day before a game stops opening" (persists; drives §10).
- Primary: **Back to Shelf**.

### 6.17 On this iPhone — renew sheet (`17`)

`.sheet` 560×490, opened from the device pill menu ("On This iPhone…"), from any SlotCard, or from the reminder
notification.

- Header with a segmented control per known phone.
- Subtitle: "3 of 3 slots used. Renewing reuses the app already built, so the phone keeps your saves." —
  **verify that renewing with the same bundle id keeps app data before shipping this sentence**.
- One row per installed app: 44 pt art, name, days-left text, 4 pt bar, bordered Renew. Expiring rows get the
  orange tint.
- Two checkboxes: reminder (same setting as Done), and "Renew by itself when this iPhone is plugged in · when 2
  days or fewer are left" (opt-in, off by default).
- Small line about the weekly new-app limit; show only if the number is trustworthy (§3).
- Footer: connection status, Close, primary **Renew All · about N min** (N = number of apps × measured renew time;
  hide the estimate until one has been measured).

---

## 7. Menus, commands and context menus

### 7.1 Menu bar (`DuoCommands`)

| Menu | Item | Shortcut | Enabled when |
|---|---|---|---|
| File | Add Game… | ⌘O | Not working |
| File | Install on <phone> | ⌘↩ | Card showing and installable |
| File | Show in Finder | ⌘⇧R | Card showing |
| File | Remove from Library | ⌘⌫ | Library tile focused or card showing |
| Phone | (list of phones, checkmark on selected) | ⌘1…⌘9 | Always |
| Phone | On This iPhone… | ⌘I | A phone is known |
| Phone | Renew All | ⌥⌘R | A phone is connected and has installs |
| Window | Setup… | ⌘, | Always (Setup doubles as the Settings window) |
| Help | Duo Builder Help, About free Apple ID limits | — | Always |

Esc / ⌘. cancels Reading and Working (with confirmation only if past the 10-minute mark of a first build:
"Stop preparing the graphics? You'll start from the beginning next time.").

### 7.2 Device pill menu

Phones (connected first, disconnected greyed with "(not connected)"), a divider, "On This iPhone…", "Set Up a New
iPhone…" (opens Setup scrolled to the iPhone row).

### 7.3 Context menus

- Library tile: Install on <phone>, Open Card, Show in Finder, Remove from Library, Delete Prepared Graphics
  (frees the cache; tile goes back to "Not built yet").
- Slot card: Renew, Show in Library, Remove from This List (only if the app is already gone from the phone).

### 7.4 Notifications (UserNotifications)

- Expiry reminder: day before, 10:00 local: "Harbor Lights stops opening tomorrow. Plug in iPhone Duo and renew —
  it takes about a minute." Action button "Renew" opens the sheet (§6.17).
- Build finished while the app isn't frontmost: "Lantern Isles is on iPhone Duo."
- Ask for notification permission the first time the reminder checkbox is ticked, not at launch.

---

## 8. Drag and drop

- Declare `UTType`s in Info.plist (`UTImportedTypeDeclarations`) for `.nsp`, `.xci` and `.iso` (the last may
  already exist as `public.iso-image`), so `onDrop(of:)` and `fileImporter` accept them.
- Attach `.onDrop(of: [.fileURL], isTargeted: $isDropTargeted)` to the root content on Home and Card; render
  `DropOverlay` while targeted. Over a free `SlotCard`, also highlight that card.
- On hover, classify by extension only (§6.03). On drop, hand URLs to the reader; never block the main thread.
- Multiple files: one game + its update/DLC go to one card. Files for two different games → read the first,
  queue the rest, and show a small "2 more games added to your library" toast.
- Dropping while Working: refuse (overlay in orange: "Wait for Lantern Isles to finish").

---

## 9. Persistence

`~/Library/Application Support/Duo Builder/`

```
library.json          // [LibraryEntry]
cache/<titleId>-<version>-<variant>/   // prepared graphics + last .ipa (owned by the CLI if it already caches)
settings.json         // reminder on/off, auto-renew on/off, selected device
```

```swift
struct LibraryEntry: Codable, Identifiable {
    var id: String                // titleId (+ cartridge index)
    var title: String
    var publisher: String?
    var platform: Platform        // .switch, .ps2
    var files: [FileRef]          // bookmark data (security-scoped), role, version
    var bannerPNG: Data?          // extracted NACP icon, cached so the shelf draws without re-reading
    var support: SupportStateDTO
    var lastUsed: Date
    var cacheKey: String?         // non-nil = "Ready · about 1 min"
}
```

- Store **security-scoped bookmarks**, not paths, so files can be re-opened after a relaunch and if moved within a
  volume.
- Banner images are cached at 256 px; the library must render without touching the game files.
- Size the cache honestly: show "Prepared graphics use 6.4 GB" in Setup's Free space row details, with "Remove
  Old Builds…".

---

## 10. Expiry, reminders, renew

- Days left = `profileExpiry - now`, rounded down, from the CLI (§3). Show "Expires tomorrow" / "Stops opening
  tomorrow" at < 48 h, "Expired — renew to open it again" when past.
- Slot bar fill = days left / 7.
- Reminder: schedule a local notification per app at expiry − 1 day, re-scheduled whenever installs change.
- Auto-renew (opt-in): when a known phone connects and any app has ≤ 2 days left, run `renew` in the background,
  show progress in the slot card, and post a notification on completion. Never auto-renew without the setting.

---

## 11. Light/dark, accessibility, motion

- Build everything from semantic colours and materials; no hex in views except through `DuoTheme`.
- Contrast: all text ≥ 4.5:1 in both appearances. Light-mode state text uses the darker values in §4.1.
- VoiceOver: banners are decorative (`.accessibilityHidden(true)`) except where they are the only label. Slot cards
  read "Harbor Lights, on iPhone Duo, stops opening tomorrow, Renew button". Timeline reads each stage with
  status. The disabled primary button's reason is its `accessibilityHint`.
- Keyboard: library grid is focusable (`.focusable()` + arrow keys), Return opens a card, ⌘↩ installs.
- Reduce Motion: no scale transitions, no animated progress easing.

---

## 12. Snapshot renderer

Extend `DuoBuilder --snapshot <dir> --info <duo-info.json> --doctor <duo-doctor.json>` with fixtures so every
state in §0's index renders headless in both appearances:

```
--library fixtures/library.json
--installs fixtures/installs.json
--run fixtures/run-graphics.json | run-early.json | run-ps2-copy.json
--failure fixtures/failure-slots-full.json
```

Output names should match this pack's (`02-home-dark.png`, `02-home-light.png`, …) so the PNGs here can be
diffed against real renders.

---

## 13. App icon

Three abstract directions in `assets/` (no game art, no Nintendo marks):

- **A · Refined current** — today's red → orange squircle, a dark open-Duo panel with a hinge line and a larger
  white controller. Smallest change to `AppIcon`.
- **B · Shelf** — indigo squircle, three tiles on a shelf line; the middle tile plays. Matches the new home.
- **C · Fold** — teal → blue, an open two-panel phone outline with a play mark across the hinge.

Whichever is chosen is still drawn in code by the `AppIcon` view and regenerated into `AppIcon.icns` at build.

---

## 14. Things to verify before shipping copy

These lines are in the designs but depend on facts the design couldn't check:

1. Renewing with the same bundle id keeps the game's saves on the phone (§6.17 subtitle).
2. Renewing does not use one of the 10 new app IDs per week (§6.17 footnote).
3. Locking the phone pauses (vs. fails) the PS2 copy (§6.13 wording; if it fails, add a `device_locked` ladder).
4. Cancel during copy removes the half-copied game (§6.13 footnote).
5. The CLI can name the game an orphan update belongs to (§6.07).
6. A paid Apple Developer account removes the 3-app limit and gives 1-year profiles at $99/year (§6.14 tip).

---

## 15. Build order (suggested)

1. `DuoTheme.swift`, shared components, `SupportBadge`, `PrimaryActionButton(reason:)` — and port the existing
   five screens onto them with no behaviour change.
2. Window to 720×560, `TopBar`, `StatusStrip`, `DevicePill` menu.
3. Working: `StageTimeline` from the existing stage stream (+ CLI `plan` event if added).
4. Setup sheet as the ordered checklist, including the keys/BIOS group.
5. Failed ladder by failure code.
6. `LibraryStore` + bookmarks + banner cache → Home shelf and library grid → tile → card.
7. CLI: device apps / renew / cache list → `InstallsStore` → slot cards, Done slot row, renew sheet, reminders.
8. PS2: `.iso` type, card variant, copy stage.
9. Drag overlay polish, context menus, notifications, Dock progress.
10. Snapshot fixtures for every state; diff against `screens/`.

### Acceptance checklist

- [ ] Every screen has at most one filled accent button.
- [ ] The four support states render differently and are never merged.
- [ ] No string contains "provisioning", "entitlement", "NSP", "shader" (the file extension label ".nsp" is
      allowed only in the file-type hint).
- [ ] No progress or ETA appears that the pipeline didn't send.
- [ ] Cancel is visible on Reading, Working and Copying, and stops the CLI process.
- [ ] Disabled Install always shows its reason.
- [ ] Setup lists every step in one order; done steps are folded, not hidden in a separate block.
- [ ] Both appearances match the PNGs; text contrast ≥ 4.5:1.
- [ ] Library and slots render without reading any game file.
