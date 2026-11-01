# Dual-screen mode: game on the top half, controls on the bottom half

Status: **implemented and verified on the Duo's inner screen, upright (2026-10-30) — §0.9 rows 1–3 pass;
rows 4–5 (landscape, menu switch off) await a check by hand.** §1–§7 below are the original design notes
(written at `7c60fce`, before any code); where they disagree with §0, §0 is what the code does. Read §0 first.

## 0. As built — read this first (handoff notes)

### 0.1 The target (what "done" looks like)

Reference photo: [`img/split-reference.png`](img/split-reference.png) (supplied by the owner; the look to match).
The phone (the "Duo": an iPhone19,4 foldable) is open, inner screen held **upright like a book turned
sideways**, so the fold runs **horizontally across the middle** of the inner screen.

| Region | What must be there |
|---|---|
| Top half (above the fold) | The game picture, **full width** of the panel, edge to edge. A 16:9 picture in a ~1.41 box leaves thin black bands above and below (letterbox) — that is what the photo shows and is acceptable. |
| Bottom half (below the fold) | The **whole** controller, spread across the panel: ZL / L3 / L top-left, − / + (and the layout button) top-centre, R3 / ZR / R top-right, a large left stick bottom-left with the D-pad to its right, A/B/X/Y bottom-right. Stick ring ≈ 1/5 of the panel width. |
| Nothing | No black band above the picture bigger than the safe inset; **no shrunken window in the middle of the screen**. |

Landscape (the phone turned sideways) keeps the original whole-screen layout: picture full screen, controls overlaid.

### 0.2 Device facts (measured, not assumed)

`xcrun devicectl device info displays --device $DUO_DEVICE`:

| Display | uniqueId | Pixels (bounds) | Scale | Points | Notes |
|---|---|---|---|---|---|
| `LCD` (primary) | `987-654-321` | 1398 × 2034 | 3 | 466 × 678 | **outer** screen; `active: false` while unfolded |
| `LCD-1` | `123-456-789` | 2007 × 2853 (portrait) | 3 | 669 × 951 | **inner** screen; the one that matters; `active: true` while unfolded |

Gotcha: `UIScreen.mainScreen` reports the *outer* screen (466 × 678) even while the app runs on the inner one.
Never size anything from `UIScreen.mainScreen`; use the view's / window's bounds.

### 0.3 The bug that made it "way too small" (diagnosed 2026-10-30)

Symptom (screenshot [`img/split-bug-landscape-shrunk.png`](img/split-bug-landscape-shrunk.png), inner screen, phone upright,
split "On"): the picture **and** the controls sat in a band in the middle of the screen, black above and below.

Proof from numbers:

* The app log said `front end: layout bounds 951x669 ... dual=1` — a **landscape** window (951 wide) while the
  phone was upright (the inner screen in portrait is 669 × 951 points).
* iOS shows a landscape-only app on the upright inner screen by scaling the whole landscape window to the
  screen's width: 2853 × 2007 px → scale 2007/2853 = 0.703 → **2007 × 1412 px**, centred: (2853 − 1412)/2 = **720 px**
  of black on top. Measured on the screenshot: content band starts at y = 722 px. Match.
* So the "split" had happened *inside* a shrunken landscape window: top half of a 1412-px-tall band = a tiny picture,
  bottom half = tiny controls.

Root causes (all fixed):

1. `DmRootVC -supportedInterfaceOrientations` returned **landscape only** unless `DM_DUAL_SCREEN` was already set
   *at the moment iOS asked* — it never was at launch.
2. `main.m` copied the menu's saved choice into `DM_DUAL_SCREEN` on the **host thread, after** the first layout;
   and because an env var overrides, the menu switch could then never turn split off again.
3. Split was a *mode* toggled by hand, independent of how the phone is held.
4. In split, the controls inset the bottom half by the screen's **top** safe-area inset (pushing the top row down for nothing).

### 0.4 The decision (what the code does now)

* **The app supports every orientation, always** (`front_ios.m -supportedInterfaceOrientations` → `UIInterfaceOrientationMaskAll`;
  `project.yml` `UISupportedInterfaceOrientations` lists all four).
* **Split follows the window's shape:** `dm_split_active(size)` = window is portrait (`height > width`) **and**
  `dm_split_enabled()`. Rotate upright → split; rotate to landscape → whole-screen layout. No restart, no toggling.
* `dm_split_enabled()` precedence: `DM_DUAL_SCREEN=0|1|on` from an env file (wins, for tests) → the in-game menu's
  saved choice `NSUserDefaults DmDualScreen` → **default ON**.
* Picture in split: `game.frame = (0, safeTop, width, height/2 − safeTop)`; the present draws the game inside it with
  the menu's **Picture fill** (Letterbox = reference look; Crop fills by cutting the sides; Stretch distorts).
* Controls in split: every geometry function works in `-controlRect` = bottom half; `-safe`/`-corner` **intersect** the
  screen's safe rect with it; unit `u = min(h/430, w/700, 1.3)` (u ≈ 0.955 on the Duo's 669 × 475-pt bottom half).
* Right-stick swipe area only accepts touches **inside** `-controlRect` (a touch on the picture never grabs it).

### 0.5 File map (where each piece lives)

| File | Symbol | Role |
|---|---|---|
| `dm/ios/Sources/DmGamepad.m` | `dm_split_enabled`, `dm_split_active` | the one decision; C functions, also called by `front_ios.m` |
| `dm/ios/Sources/DmGamepad.m` | `-dual`, `-controlRect`, `-safe`, `-corner`, `-u`, `-inRightArea:` | control geometry for split / landscape |
| `dm/ios/Sources/DmGamepad.m` | `dm_dual_set`, `dm_split_enabled`, `dm_gamepad_set_hidden`, `-gearTapped` | in-game settings: the ⚙ button (bottom centre) opens the menu in `InGameMenu.swift`, which drives Picture fill (live) and Split when upright (live) |
| `dm/ios/Sources/front_ios.m` | `-viewDidLayoutSubviews` | picture frame (top half in split); logs the geometry; nudges the pad on split changes |
| `dm/ios/Sources/front_ios.m` | `-supportedInterfaceOrientations` | all orientations |
| `dm/ios/Sources/front_ios.m` | `-startGame` | makes the game view and the pad once the launcher has applied its choices; the saved Picture fill arrives as `DM_PRESENT_FILL` and seeds the present pass |
| `dm/gfx/nvn/nvn_mtl.m` | `dm_present_set_fill`, `dm_present_fill`, `present_viewport` | live fill: 0 letterbox, 1 stretch, 2 crop (`DM_PRESENT_FILL` only seeds it) |
| `dm/host/dm.h` | declarations of the two fill functions | |
| `dm/ios/project.yml` | `UISupportedInterfaceOrientations` | all four orientations |

Saved choices (per app = per game): the launcher's store, one `launcher.<VAR>` string per row (`SettingsStore`, `dm/ios/Sources/LauncherSettings.swift`). Picture fill is `launcher.DM_PRESENT_FILL` (0 letterbox, 1 stretch, 2 crop), split `launcher.DM_DUAL_SCREEN` (default on), the pad layout `launcher.DM_PAD_LAYOUT` (2D/3D/Tap); the panel's old `DmFillMode` / `DmDualScreen` / `DmPadLayout` / `DmPadHidden` keys were migrated once, in `main.m`.

### 0.6 Logs to read (Documents/log.txt; one line per geometry change)

```
front end: layout bounds 669x951 (portrait) scale 3.00 safe t.. l.. b.. r.. split=1 fill=1   ← front_ios.m
front end: pad bounds 669x951 dual=1 control rect 669x476 at 0,475 u=0.96                ← DmGamepad.m
[nvn-mtl] present fill set at run time: ...                                              ← nvn_mtl.m
front end: split when upright -> on|off (in-game settings)                               ← DmGamepad.m
```

If `layout bounds` says **landscape** while the phone is upright, the app did not rotate: that is the §0.3 bug again.

### 0.7 How to see the device screen from the Mac (no phone interaction needed)

```sh
xcrun devicectl device capture screenshot --device $DUO_DEVICE \
    --display-unique-id 123-456-789 --destination /tmp/inner.png     # inner screen, 2007 x 2853 px
```

Without `--display-unique-id` it captures the **outer** (inactive, black) screen. iPhone Mirroring does not work
for this (it binds to the other iPhone on the account, and cannot pick the inner screen). `idevicescreenshot` fails
(no screenshotr service). The in-app `DM_CTL` `shot` command captures the *game frame only* (no controls) and is
unreliable on some titles; prefer `devicectl`.

### 0.8 Build / install loop used

See `bin/nx` + manual signing (Xcode's account session is out): build with `CODE_SIGNING_ALLOWED=NO`, copy the
app's provisioning profile into `DmIOS.app/embedded.mobileprovision`, `codesign -f -s "Apple Development: …"
--entitlements <plist with application-identifier/team-identifier/get-task-allow/keychain-access-groups/
increased-memory-limit> --generate-entitlement-der`, `devicectl device install app`. Entitlements must include
`application-identifier` or install fails with CoreDeviceError 3002.

### 0.9 Verification checklist (measured results)

Measured 2026-10-30 on LM3 (plain build, no per-game patches), inner screen upright, screenshot
[`img/split-fixed.png`](img/split-fixed.png) (`devicectl … --display-unique-id 123-456-789`, 2007 × 2853 px, fold at y = 1426 px).

| # | Check | How | Result |
|---|---|---|---|
| 1 | Upright → app window is portrait | log line | **pass**: `layout bounds 669x951 (portrait) scale 3.00 safe t0 l0 b34 r0 split=1`; `pad bounds 669x951 dual=1 control rect 669x476 at 0,475 u=0.96` |
| 2 | Picture spans the full width of the top half | rows where > 50 % of the width is picture | **pass**: x 0–2006, y 0–1424 px (the whole top half, edge to edge, with Picture fill = Crop) |
| 3 | Controls span the bottom half | light-grey control pixels below the fold | **pass**: x 10–1996, y 1444–2738 px; ZL/L3/L top-left, − 3D + top-centre, R3/ZR/R top-right, stick bottom-left, D-pad right of it, diamond bottom-right, ⚙ bottom-centre |
| 4 | Landscape unchanged | rotate; log `(landscape) split=0`; full-screen picture | pending (needs the phone turned by hand) |
| 5 | Menu switch off → upright shows whole-screen layout | ⚙ → Split when upright → Off | pending |

Not ours: a grey circle at the same screen pixel in every screenshot (≈ 1890, 1105 px in the 2007 × 2853 image, on the
picture's right edge) does not move when the app's layout changes. It is a system overlay (iOS AssistiveTouch
button), not a control. Settings → Accessibility → Touch → AssistiveTouch hides it.

Picture fill note: this run used **Crop** (proportions kept, the sides of the 16:9 picture trimmed to fill the
~1.41 top half). The reference photo is **Letterbox** (whole picture, full width, thin black bands above and below).
Both are one tap in ⚙ → Picture fill (the in-game menu), or the launcher's **Screen** section; the choice is saved per game.

### 0.9a On-screen controls: the layout editor, opacity, background, and what "rotates" means

The ⚙ button (`DmGamepad.m -gearTapped`) opens the in-game menu (`InGameMenu.swift`), whose tiles hold, besides the game's own rows:

| Tile | Effect | Saved as |
|---|---|---|
| **Touch controls: On / Off** | hides every control (and stops it taking touches, which then go to the game's touch screen). A physical controller still hides it automatically (`_padOff`, unchanged) | the launcher row `DM_PAD_HIDDEN` (`launcher.DM_PAD_HIDDEN`), applied live by `dm_gamepad_set_hidden` |
| **Move Controls / Done Moving** | edit mode (below); the menu closes so the pad can be touched, and a **Done** pill at the top centre of the screen ends it without reopening the menu | not saved (a session toggle, `dm_gamepad_set_editing`) |
| **Reset Layout** | this orientation class's positions, sizes and picture placement back to the defaults; the other class and the opacity stay | `dm_gamepad_reset_layout` |
| **Controls opacity** (10…100 %, live) | every control's colours scaled (`set_colours`: each colour's own alpha × o, no layer opacity, so no off-screen pass); pressed keeps a floor above idle (18 % against 1.4 % at 10 %) | this orientation class's set, `dm_gamepad_set_opacity` |
| **Background: Choose Photo… / Remove**, **Dimming** (0…80 %, default 30 %) | the player's image behind the picture and the controls (below) | `Documents/background.jpg`, `NSUserDefaults DmBackgroundDim` |

**Edit mode** (`DmGamepad.m` "Edit mode"; nothing reaches the game). Dashed outlines show what moves: white around each
visible control, yellow around the picture.

* One finger on a control drags it; one finger on the game picture drags the picture (vertically and horizontally,
  kept on screen).
* Two fingers pinch. `dm_layout_pinch_target` (`DmPadLayout.m`) decides what from the control under each finger and
  under their midpoint (`-editKeyAt:`, which uses the grab radii, so fingers *around* a small key count) and the
  picture rect: the control under the midpoint; else the one both fingers are on; else the only one a finger is on;
  fingers on two *different* controls = **all controls**; no control: **the picture** when the midpoint (or both
  fingers) is on it, else **all controls** (empty pad space). Controls take precedence over the picture they sit on.
* Sizes: a control's own scale and the all-controls scale are 0.5…2.5; the picture's is 0.5…1 of its home rect (never
  larger, so it never leaves the screen), aspect kept, and a picture pinch also follows the fingers' midpoint.
* A control's own scale works about its centre (every radius, rect, label and grab radius scales: `-faceR`,
  `-stickR:`, `-dpadS`, `-dropR:`, `-clickR:`, `-pillRect:`, `-swapR`). The all-controls scale multiplies the layout
  unit (`-u` = `-u0` × scale), so the whole layout grows from the screen edges and corners and keeps its proportions;
  the ⚙ button stays on `-u0`.
* A gesture is saved the moment its fingers lift; a pinch that loses a finger ignores the rest until all are up.

**Storage** (`DmPadLayout.h`, `DmPadLayoutSet`): one set per **orientation class** — `portrait` (taller than wide: the
split screen, by default) and `landscape` — under `NSUserDefaults DmControlLayout.portrait` / `DmControlLayout.landscape`.
Each is a property list: `offsets {key: [x, y]}` (points), `scales {key: s}`, `scale` (all controls), `picture [dx,
dy, s]`, `opacity`. Keys: `stick`, `dpad`, `face`, `zl`, `zr`, `l`, `r`, `ls`, `rs`, `plus`, `minus`, `swap`
(`keyName()`). Defaults hold property-list types only — an `NSValue` threw on the first save and killed the app once
(fixed 2026-10-30) — so the set never holds anything else, even in memory. `-layoutSubviews` loads the other class's set
when the view turns, so portrait split and landscape each keep their own positions, sizes, picture placement and
opacity, and a change in one never touches the other (before: one `DmPadOffsets` map applied in both). The old
`DmPadOffsets` map becomes landscape's offsets once and is deleted (landscape's own set wins if one exists).
`dm/ios/tests/test_pad_layout.py` runs the model on the Mac: migration, separation of the classes, plist validity,
clamps, malformed values, Reset, the picture clamp and the pinch rule.

**Picture placement** (`front_ios.m`): `void dm_picture_set_placement(float dx, float dy, float scale)` — points from
the picture's home rect, scale 0.5…1 about its centre; live (lays the root view out at once). `CGRect
dm_picture_rect(int placed)` — the home rect (0) or where it is drawn (1), root-view coordinates. The home rect is
the 16:9 picture itself under letterbox fill (front_ios.m sizes the Metal view to it, so its bands are the root
view's background, not black inside the drawable), the box under stretch / crop; a fill change relayouts
(`front_ios_relayout`, settings_live.m). The placement is applied as the game view's centre + scale transform, so the
drawable keeps its size during a pinch; `-viewDidLayoutSubviews` clamps it on screen (`dm_layout_picture_clamp`) and
logs `front end: picture rect …`. The game's touch screen (`-pushGame`) normalises against `dm_picture_rect(1)`
(crop: the 16:9 picture covering it), so touches follow the moved / scaled picture.

**Background image** (`front_ios.m`): the picker is `PHPickerViewController` (out of process, no photo-library
permission). The bytes go to `dm_background_set_image`, which draws the photo upright, scales it so its shorter side is
at most the screen's longer side in pixels (aspect-fill in either orientation without upscaling), writes
`Documents/background.jpg` and shows it live: a `UIImageView` (aspect fill, whole screen) at the bottom of the root view
with a black layer at the dimming over it, under the game view (opaque) and the pad. It shows in the split screen's
control half and in every letterbox / pillarbox band. One image for both orientations. No file = the black
background as before. `dm_background_remove`, `dm_background_present`, `dm_background_set_dim` / `_dim`.

Rotation: the app allows all four orientations (`front_ios.m -supportedInterfaceOrientations` returns
`UIInterfaceOrientationMaskAll`, `project.yml` lists all four). **Upright** = split (picture on top, controls on the
bottom); **landscape** = the whole-screen layout. Each layout change is logged:
`front end: layout bounds WxH (portrait|landscape) … split=0|1`. If a rotation does not change those numbers, iOS is
not rotating the app (check the device's rotation lock) — the app never forces an orientation.

### 0.9b External display (upstream PR #367) and the split screen (merge of 2026-10-31)

Upstream added a TV / monitor scene (`front_ios.m` `DmTVSceneDelegate`, `DmTVVC`, `tv_attach` / `tv_detach`;
`project.yml` `UIWindowSceneSessionRoleExternalDisplayNonInteractive`; on iOS 27 the scene accessory registered in
`DmRootVC -viewDidLoad`). It moves the game's Metal view into the TV's window, fits it 16:9 there (`fit_16_9`), caps the
drawable at 1920 px across, and sets console (docked) mode; disconnecting puts the view back and restores the mode.

How it was combined with this fork's layout:

* **Phone alone** (no TV): unchanged. `-viewDidLayoutSubviews` computes the box exactly as before (split upright /
  `DM_ASPECT=fill` / 16:9, the latter now through upstream's `fit_16_9`, the same arithmetic), then the letterbox home
  rect and the layout editor's placement (`g_pic_off`, `g_pic_scale`). `tv_attach()` at game start returns at once
  without a TV.
* **TV connected**: the phone's layout code places the game view **only while it is a subview of the root view**
  (`self.game.superview == self.view`); on the TV, `DmTVVC` lays it out. `tv_attach` resets the view's transform to
  identity first (the editor's scale is the phone's; a frame set under a non-identity transform is undefined) and
  relayouts the pad. The pad stays on the phone with its own rules: upright + Split when upright = bottom half (top
  half shows the background image or black), landscape = whole screen.
* `dm_picture_rect` returns `CGRectZero` while the picture is on the TV, so the editor draws no picture outline and
  touches are not mapped onto a picture that is not on the phone (the TV is docked mode anyway, where the host reports
  no touch screen).
* `tv_detach` reinserts the game view **above the background image** (`g_bg`, index 0) instead of upstream's index 0,
  which would have hidden the picture behind the background; the next layout restores the split / placement.

Device checks still owed: TV by cable and AirPlay, upright (split) and landscape, connect and disconnect mid-game,
with and without a background image, and with a moved / scaled picture.

### 0.10 Known gaps (not done yet)

* No gap at the fold / no `UIHinge` use (§3 has the API notes): controls sit right at the midline.
* Not tested on the outer screen (466 × 678 pt, portrait): split would apply there too (it is portrait).
* "Keyboard on the bottom half" (owner's original idea) is not built; the bottom half is the controller only.
* The game itself still renders 16:9 (the per-game aspect patches are a separate effort, see `duo/STATUS.md`).

## 1. Decision in one paragraph

Keep the gamepad view full-screen (it is the app's only touch owner, and the game's
touch screen and the 3D right-stick area depend on that). Add a **control region**
to it: all existing geometry functions are computed inside that rectangle instead
of `self.bounds`. In dual mode the region is the bottom half; the game view is the
top half. A 24 pt gap is inserted at the midline while the hinge reports
`UIHingeStatusPartiallyOpen`. The mode falls back to the normal full-screen layout
while the hinge is `Closed` (the scene is then normally on the cover display) or
while a physical controller is connected (the virtual pad is hidden). Portrait is enabled
only in dual mode; the game view keeps the existing `DM_ASPECT` policy, applied
inside the top half. On the Duo build the camera ratio (`DM_DUO_ASPECT`) is updated
from the game view's actual aspect so a rotation or a half-screen picture is not
stretched.

## 2. What the app lays out today

### 2.1 View tree and the game view

`main.m:187-196` creates the window and `DmRootVC`; `front_ios.m:58-71` sets up the
boot hint and the power/audio observers until the game starts.

`front_ios.m:73-90` (`-startGame`) builds the tree once the launcher has applied
its settings:

| Object | Frame | Code |
|---|---|---|
| `DmGameView` (`CAMetalLayer`) | `self.view.bounds`, then re-framed in `viewDidLayoutSubviews` | `front_ios.m:77-79`, class at `front_ios.m:31-46` |
| `self.pad` (`DmGamepad`) | `self.view.bounds`, autoresizing width+height | `front_ios.m:82-84` |
| `self.fps` (`UILabel`, optional) | placed in `viewDidLayoutSubviews` | `front_ios.m:85-86`, `147-162` |
| `front_progress` overlay | root bounds, centred box | `front_ios.m:164-189` |

`DmGameView.layoutSubviews` sets
`drawableSize = bounds.size * nativeScale` (`front_ios.m:41-45`). The layer is
`BGRA8Unorm`, `contentsScale = UIScreen.mainScreen.nativeScale`
(`front_ios.m:34-38`).

`front_ios.m:91-109` (`-viewDidLayoutSubviews`) is the whole game-view layout today:

- `DM_ASPECT=fill` (read once, `front_ios.m:97-98`) → `self.game.frame = b`
  (`:100`), the whole screen.
- otherwise fit 16:9 into `b` and centre it (`:101-104`).
- the FPS label sits in the pad's top row: safe rect + `(130u, 22u - 11)`,
  `u = MIN(b.height / 430, 1.3)` (`:105-108`).

The view controller is landscape-only: `supportedInterfaceOrientations` returns
`UIInterfaceOrientationMaskLandscape` (`front_ios.m:124`), and the generated
Info.plist lists only the two landscape values (`project.yml:38-40`). The
`SceneDelegate` does not implement any orientation callback (`main.m:187-196`).

### 2.2 The pad's layout today

`DmGamepad` is a full-screen transparent `UIView` above the game view. Every
control is a `CAShapeLayer` inside one `_controls` layer (`DmGamepad.m:184-194`);
a press only changes a fill, a stick only moves its knob (`refresh`,
`DmGamepad.m:446-455`), so no per-frame redraw.

Layout constants are in `u` (unit = 1/430 of the screen height, capped at 1.3):
`DmGamepad.m:105-127`.

| Concern | Code | Today |
|---|---|---|
| safe rectangle | `DmGamepad.m:226` | `UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets)` |
| bottom-corner rectangle | `:227` | same, side insets × `K_CORNER_IN = 0.5` |
| unit `u` | `:228` | `MIN(self.bounds.size.height / 430, 1.3)` |
| face diamond centre | `:230-234` | `(corner.maxX - 81u, corner.maxY - 82u)` |
| left stick centre | `:235` | `(corner.minX + 81u, corner.maxY - 82u)` |
| right-stick area | `:238` | `p.x >= bounds.maxX - bounds.width / 3` |
| D-pad centre | `:239` | `(corner.minX + 231u, corner.maxY - 64u)` |
| ZL/ZR, L/R | `:243-245` | from `safe` top corners |
| L3/R3 | `:246` | from `safe` top, `102u` from the side |
| −/+ pills, layout button | `:247-250` | `safe` top centre, ±`52u`, `22u` down |
| layout selection | `:210-223` | `applyLayout` shows/hides the 3D-only keys; `nextLayout` cycles 2D → 3D (→ Tap in handheld) and saves `DmPadLayout` |
| hit tests | `:252-280` | locked keys first, then face/D-pad/stick by distance, then the 3D right third |
| touch ownership | `:335-355` | `_owner` maps touch → control; unclaimed touches go to the game |
| game touch normalization | `:319-330` | fits 16:9 into `self.bounds` again and normalizes on that box |
| shapes on layout | `:416-443` | recomputes paths from the geometry functions |
| physical controller | `:523-527` | `_padOff = any`; `_controls.hidden = any`; `reset` |

The 2D layout uses the top corners (ZL/L, ZR/R, −/+, layout button) and the bottom
corners (left stick, face diamond). The 3D layout adds the D-pad inward of and
below the left stick, L3/R3 in the top row, and an invisible right stick whose area
is the right third of the **screen**. Tap keeps only the layout button; every other
touch goes to the game. These are documented at `DmGamepad.m:1-15`.

### 2.3 The picture and the present

The present pass scales the game's 16:9 canvas into the layer drawable:
`present_viewport` at `dm/gfx/nvn/nvn_mtl.m:11118-11135`. `DM_PRESENT_FILL`
selects stretch / crop / off. The Duo camera stubs read a float at
`dm_fps_state + 0x40` (`dm/host/loader.c:244-255`), written once at load from
`DM_DUO_ASPECT`. That is the ratio the camera projection uses; it must match the
drawable's aspect for the world to be undistorted (`duo/DESIGN.md`,
`duo/README.md`).

## 3. What iOS 27 exposes for folds and orientation

### 3.1 Fold state: `UIHinge` / `UIHingeInteraction` (iOS 27.1)

The SDK has exactly two fold-specific public headers; a case-insensitive grep for
`fold|hinge|posture|crease` over all `UIKit.framework/Headers` matches only these
two files. Reproduced with:

```
SDK=/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.1.sdk
grep -rliE '\b(fold|folded|folding|hinge|posture|crease)\b' \
  "$SDK/System/Library/Frameworks/UIKit.framework/Headers"
# → UIHinge.h
# → UIHingeInteraction.h
```

`iPhoneOS27.1.sdk/.../UIKit.framework/Headers/UIHinge.h`:

- `:15-29` `UIHingeStatus`: `Unknown = 0`, `Closed = 1`, `PartiallyOpen = 2`,
  `FullyOpen = 3`; `API_AVAILABLE(ios(27.1), tvos(27.1), visionos(27.1))`.
- `:55-70` `UIHinge`: `status` (`:62`) and `angle` in radians (`:68`). The header
  says the angle's update rate and precision are system policy and that `status`
  should be preferred when only closed/partially/fully open is needed (`:64-67`).

`.../UIHingeInteraction.h`:

- `:21-24` `UIHingeInteractionUpdate.hinge`, nullable.
- `:26-29` the interaction is added to a view; the handler is called with the
  initial state and on changes, and with `hinge == nil` when the view leaves a
  hierarchy that provides hinge updates.
- `:51-69` `UIHingeInteraction`, `initWithUpdateHandler:` (`:63`), `enabled`
  (`:69`), same iOS 27.1 availability.

That is all: **no hinge position, no crease rectangle, no fold axis, no
posture name, and no display/visible-area geometry.** The interaction only says
whether the device is closed, partly open or flat, and the dihedral angle.

### 3.2 Orientation and scene geometry

- `UIWindowScene.effectiveGeometry` (`UIWindowScene.h:34`, iOS 16+), of type
  `UIWindowSceneGeometry`.
- `UIWindowSceneGeometry.interfaceOrientation` (`UIWindowSceneGeometry.h:42`),
  `isInterfaceOrientationLocked` (`:45`, iOS 26),
  `isInteractivelyResizing` (`:57`, iOS 26), `coordinateSpace` (`:39`).
  **There is no `bounds`/`frame` here**; the scene's rectangle comes from the
  window/view.
- `UIWindowSceneDelegate windowScene:didUpdateEffectiveGeometry:` (iOS 26,
  `UIWindowScene.h:92-95`), which replaces the deprecated
  `didUpdateCoordinateSpace:interfaceOrientation:traitCollection:` (`:90`).
  The docs say it is always called when a scene moves between screens.
- `UIWindowSceneDelegate supportedInterfaceOrientationsForWindowScene:` (iOS 27,
  `UIWindowScene.h:97-100`) can replace the Info.plist mask per scene. The app
  does not need it; the existing view-controller mask (`front_ios.m:124`) is
  enough for iOS 26 and 27.
- `UIWindowSceneGeometryPreferencesIOS.interfaceOrientations` (iOS 16,
  `UIWindowSceneGeometryPreferencesIOS.h:19-23`) is available if the app ever
  wants to request an orientation; this design does not force one.

The app already reads the orientation on every pad layout:
`DmGamepad.m:417-418` stores
`ws.effectiveGeometry.interfaceOrientation` for the pre-iOS-27 motion fallback.

### 3.3 The device's own numbers

The Xcode 27.1 simulator type
`/Library/Developer/CoreSimulator/Profiles/DeviceTypes/iPhone Duo.simdevicetype`
identifies `modelIdentifier = iPhone19,4` and `minRuntimeVersion = 27.1`.
Its `capabilities.plist` reports:

| Display | Pixels | Scale | Points | Native orientation | Refresh |
|---|---|---|---|---|---|
| inner (screenID 3, "LCD-1") | 2007 × 2853 | 3 | **669 × 951** | 270 | 60 Hz |
| cover (screenID 1, "LCD") | 1398 × 2034 | 3 | 466 × 678 | 0 | 60 Hz |

So the inner panel is 669 × 951 pt in portrait (951 × 669 pt in landscape), and
1 pt = 3 px. The inner display's corner radius is 55 px ≈ 18.3 pt. The profile has
no fold/hinge capability; the hinge API is a UIKit runtime feature, not a
simulator profile flag.

The deployment target is iOS 26.0 (`project.yml:5-6`), while the hinge API is
iOS 27.1. The app must use `if (@available(iOS 27.1, *))`; on iOS 26 the hinge
state is unavailable and the bounds-change fallback (the same layout path) is the
only behaviour. The Duo runs iOS 27.2, so the API is present there.

## 4. The mode

### 4.1 Selection

- Primary: a launcher row in `dm/games/settings.tsv`, section **Controls**,
  `platform:ios`, default `0`:

  ```
  DM_DUAL_SCREEN	toggle	-	0	platform:ios	Controls	Dual-screen controls	Game picture on the top half, touch controls on the bottom; flat or partly folded, portrait or landscape.
  ```

  `LauncherModel.apply()` (`dm/ios/Sources/LauncherSettings.swift:98-105`) sets
  the environment before `startGame`; the choice is saved in `UserDefaults` like
  every other launcher row.
- Secondary: `DM_DUAL_SCREEN=1` in `Documents/env.txt` or the launch
  environment. The launcher then shows the row fixed, as it does for every env
  file switch.
- Read once in `startGame` (`front_ios.m:73`) into `g_dual`; no in-game toggle.
  `DM_LAUNCHER=0` still applies saved choices (`LauncherSettings.swift:108-113`).
- The mode does not force `DM_OPMODE`; the virtual pad exists in both operation
  modes. Tap remains offered only in handheld mode (`DmGamepad.m:196-198`).

### 4.2 Split math

All in the current interface orientation, in points:

```
h = view.bounds.height
w = view.bounds.width
gap = (dual && hinge == UIHingeStatusPartiallyOpen) ? 24 : 0
half = (h - gap) / 2
pictureArea = (0, 0, w, half)
controlRegion = (0, half + gap, w, h - half - gap)
```

The split is horizontal in the **interface** coordinate space, not in the
physical hinge frame: the API exposes no crease axis or position. In a portrait
flex posture that is the crease; in landscape it is still a top/bottom split even
if the physical crease is vertical. The split uses the full view bounds, not the
safe area, so the two halves are equal physical halves; the safe area only insets
the controls inside the strip.

`dual` is false, and the whole layout is exactly today's, when:

- `g_dual` is 0, or
- the hinge reports `UIHingeStatusClosed` (the scene is then normally on the cover display,
  466 × 678 pt), or
- a physical controller is connected (`dm_gamepad_hidden()`), because the virtual
  pad is hidden and the bottom half would be black.

#### Numbers for 2007 × 2853 px (669 × 951 pt at 3×)

| | Portrait | Landscape |
|---|---|---|
| screen | 669 × 951 pt (2007 × 2853 px) | 951 × 669 pt (2853 × 2007 px) |
| half, no gap | 669 × 475.5 pt (2007 × 1426.5 px) | 951 × 334.5 pt (2853 × 1003.5 px) |
| half, 24 pt gap | 669 × 463.5 pt (2007 × 1390.5 px) | 951 × 322.5 pt (2853 × 967.5 px) |
| picture area aspect, no gap | 1.407 | 2.843 |
| picture area aspect, gap | 1.443 | 2.949 |
| pad unit `u`, no gap | 1.106 | 0.778 |
| pad unit `u`, gap | 1.078 | 0.750 |

The 24 pt gap is a fixed comfort margin at the bend (`K_DUAL_GAP`), not a measured
crease width. With the odd 2853 px panel height the mathematical half is
1426.5 px; `CAMetalLayer.drawableSize` rounds it to a whole pixel, a < 0.04 %
aspect difference.

#### Picture inside the area (existing `DM_ASPECT` policy)

| | `DM_ASPECT=fill` | unset (fit 16:9) |
|---|---|---|
| portrait, no gap | 669 × 475.5 pt, 1.407 | 669 × 376.3 pt (2007 × 1129 px), bars 49.6 pt / 148.8 px top+bottom |
| portrait, gap | 669 × 463.5 pt, 1.443 | 669 × 376.3 pt, bars 43.6 pt / 130.8 px |
| landscape, no gap | 951 × 334.5 pt, 2.843 | 594.7 × 334.5 pt (1784 × 1003.5 px), bars 178.2 pt / 534.5 px left+right |
| landscape, gap | 951 × 322.5 pt, 2.949 | 573.3 × 322.5 pt (1720 × 967.5 px), bars 188.8 pt / 566.5 px |

The HUD stretch from the 16:9 canvas is `area_aspect / 1.7778`: 0.79 in portrait
fill, 1.60 in landscape fill, 1.0 in fit. Portrait is the recommended dual
posture: its half is 1.407, close to the panel's 1.4215, and it gives the largest
16:9 picture (669 × 376 pt, vs 595 × 335 pt in landscape fit).

### 4.3 The pad inside the strip

The existing constants already describe a console: shoulders and −/+ at the top,
stick and diamond at the bottom. In a half-screen strip the top row lands on the
crease and the bottom row on the device's bottom edge. No new control constants
are needed; only the rectangle the functions measure from changes.

The functions `safe`, `corner`, `u`, `inRightArea` and the geometry helpers use
`region` instead of `self.bounds`:

```
region = controlRegion (converted into the pad's coordinates)
safe   = CGRectIntersection(UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets), region)
corner = CGRectIntersection(UIEdgeInsetsInsetRect(self.bounds, side insets × 0.5), region)
u      = MIN(region.size.height / 430.0, 1.3)
right-stick area = p inside region && p.x >= region.maxX - region.width / 3
```

`CGRectIntersection` keeps the insets that matter to the half: in portrait the
bottom home-indicator inset, in landscape the side insets and the bottom inset;
the top inset of the screen is above the strip and drops out. The top-row controls
use `safe`; the bottom-corner controls use `corner`, which is the same rectangle
with the side insets halved (`K_CORNER_IN`). The numbers below are offsets inside
those rectangles, because the Duo's actual safe-area insets are runtime values;
"from left/right" for a bottom control means from `corner`'s edge.

| Control | Formula (offsets in `safe` / `corner`) | Portrait, `u=1.106` (no gap) | Landscape, `u=0.778` (no gap) |
|---|---|---|---|
| ZL / ZR centre | `(44u, 40u)` from a top corner, radius `26u` | 48.7 from left/right, 44.2 from top / r 28.8 | 34.2, 31.1 / r 20.2 |
| L / R centre | `(44u, 108u)`, radius `24u` | 48.7, 119.4 / r 26.5 | 34.2, 84.0 / r 18.7 |
| − / + centre | `(midX ∓ 52u, 22u)`, size `50u × 28u` | ∓57.5 from midX, 24.3 from top / 55.3 × 31.0 | ∓40.5, 17.1 / 38.9 × 21.8 |
| layout button | `(midX, 22u)`, radius `15u` | 24.3 from top / r 16.6 | 17.1 / r 11.7 |
| left stick | `(81u, maxY - 82u)`, ring `77u`, knob `30u` | 89.6 from left, 90.7 above bottom / r 85.2 | 63.0, 63.8 / r 59.9 |
| face diamond | `(maxX - 81u, maxY - 82u)`, gap `50u`, key `27u` | 89.6 from right, 90.7 above bottom / gap 55.3, r 29.9 | 63.0, 63.8 / gap 38.9, r 21.0 |
| D-pad (3D) | `(231u, maxY - 64u)`, radius `48u` | 255.4 from left, 70.8 above bottom / r 53.1 | 179.7, 49.8 / r 37.3 |
| L3 / R3 (3D) | `(102u, 40u)`, radius `17u` | 112.8 from left/right, 44.2 from top / r 18.8 | 79.4, 31.1 / r 13.2 |
| right-stick third (3D) | `x >= region.maxX - region.width / 3` | x ≥ 446 from the left | x ≥ 634 |
| grab radii | stick `1.4 × 77u`, D-pad `1.3 × 48u`, face `1.25 × 27u` | 119.2 / 69.0 / 37.3 | 83.9 / 48.5 / 26.3 |

The controls shrink automatically with `u` (0.78 landscape, 1.11 portrait, against
1.3 in the current full-screen Duo layout), which is what makes the whole pad fit
a 334–475 pt strip without new constants. The strip's top row sits at the crease:
the ZL/ZR teardrop tip is about `2.3u` (1.8–2.5 pt) below the strip's top, and the
pills occupy `8u…36u` (6–40 pt) from it. The 24 pt gap keeps the picture and the
controls off the bend.

Layout mapping by mode:

- **2D**: unchanged semantics — ZL/L at the top-left, ZR/R at the top-right,
  −/+ and the layout button at the top centre, left stick bottom-left, diamond
  bottom-right.
- **3D**: adds the D-pad inward of/below the left stick, L3/R3 in the top row, and
  the invisible right stick in the right third **of the strip**, not of the screen.
- **Tap**: only the layout button in the strip; picture touches go to the game,
  strip touches that miss the button do nothing.

### 4.4 Touch routing

The pad stays full-screen, so it remains the only touch owner and the game view
never has to handle touches. Two rectangles gate every touch-down:

- `region`: control hit-testing is allowed only here. A touch outside it can never
  claim a shoulder, the layout button or the 3D right stick, even though their
  grab radii would otherwise reach into the picture.
- `gameRect`: the game picture rectangle that `front_ios.m` just laid out (the
  full game view frame, fill or 16:9). Only touches that begin inside it become
  game touches; `pushGame` normalizes on it instead of recomputing a 16:9 box from
  the pad's bounds.

```
- (void)touchesBegan:... {
    for (UITouch *t in ts) {
        CGPoint p = [t locationInView:self];
        if (_padOff) {                       // controller connected: no virtual pad
            if (!_dual || CGRectContainsPoint(_gameRect, p)) game |= [self gameBegin:t];
            continue;
        }
        if (_dual && !CGRectContainsPoint([self region], p)) {   // the picture half
            if (CGRectContainsPoint(_gameRect, p)) game |= [self gameBegin:t];
            continue;                        // letterbox bars inside the half do nothing
        }
        ... existing hit tests ...
        if (_tap) { if (!_dual) game |= [self gameBegin:t]; continue; }
        ... face / D-pad / stick / right stick ...
        else if (!_dual) game |= [self gameBegin:t];   // dual: a strip touch that misses does nothing
    }
}
```

In non-dual mode `region` is `self.bounds`, so the first gate never triggers and
the `!_dual` branches keep today's behaviour exactly. `pushGame` also fixes a
latent mismatch under `DM_ASPECT=fill`: today it normalizes on a 16:9 box while
the game view fills the whole screen; passing the real game frame makes the
mapping match the stretched present.

A held touch does not survive a re-layout: when the region or game rect changes
(rotation, fold status, controller), the pad calls its existing `reset`
(`DmGamepad.m:384`), which releases every key and stick and pushes an empty game
touch set. That is safer than a key stuck across a rotation.

### 4.5 Rotation, fold and controller

- **Rotation**: `viewDidLayoutSubviews` runs, recomputes `pictureArea` and
  `controlRegion`, re-frames the game view, calls `dm_gamepad_region`, and updates
  the camera ratio. The pad resets held touches; the drawable and the present
  reallocate once. No animation is used for the frame change.
- **Fold status change**: the `UIHingeInteraction` handler stores
  `closed` / `partial` and calls `[self.view setNeedsLayout]` **only when the
  status changes** (the angle can update frequently and is logged, not used for
  layout). `PartiallyOpen` adds the 24 pt gap; `FullyOpen` removes it; `Closed`
  turns dual off and the normal full-screen layout returns. If the system also
  resizes the scene in a fold posture (not documented in the headers), the bounds
  change drives the same path; the design does not assume it.
- **Controller connect/disconnect**: `padsChanged` (`DmGamepad.m:523-527`) sets
  `_padOff` on the main queue and now also calls `[self.superview setNeedsLayout]`.
  The root asks `dm_gamepad_hidden()`; while hidden, dual is off and the picture
  takes the whole screen. On disconnect the split returns. This avoids a black
  bottom half while a controller is in use.
- **Cover display**: when the hinge is `Closed`, the scene can be on the
  466 × 678 pt cover display; dual is off there. Opening the device reports
  `PartiallyOpen`/`FullyOpen` and the split returns. If the hinge is unavailable
  (`nil`, iOS 26, simulator), the mode stays on and the split uses the scene
  bounds.

### 4.6 Aspect and the Duo camera

`DM_ASPECT` keeps its meaning, applied to `pictureArea` instead of the whole
screen:

```
CGRect frame = pictureArea;
if (!fill) { fit 16:9 into pictureArea; centre it; }
self.game.frame = frame;
```

`DM_PRESENT_FILL` then works exactly as today on the drawable (the game view).

The Duo camera stubs need the drawable's aspect, not a fixed full-screen value.
With `DM_ASPECT=fill` and the current `DM_DUO_ASPECT=2853:2007` the projection
would stay 1.4215 while the drawable is 1.407 (portrait, harmless) or 2.843
(landscape, the world stretched ~2×). Add a front-end hook:

- `front_ios.m` caches `g_game_aspect = frame.width / frame.height` on every
  layout (atomic; the host thread reads it).
- `front.h`: `float front_game_aspect(void);` (0 = unknown); a weak default in
  `loader.c` returns 0 for Mac/tests.
- `loader.c` `dm_fps_state_apply` (`:234-255`): when `DM_DUO_ASPECT` is set, use
  `front_game_aspect()` if it is in 0.5…8, else the env value; log which.
- `hle.h`: `void dm_duo_aspect_update(float ratio);`; `loader.c` writes the float
  at `dm_fps_state + 0x40` when the page exists.
- `front_ios.m` calls `dm_duo_aspect_update(g_game_aspect)` at the end of
  `viewDidLayoutSubviews` when `DM_DUO_ASPECT` is set. The loader's startup write
  happens after the first layout (the game view exists before `front_ios_boot`),
  so the first frame is already correct; later rotations update the same slot.

`dm_fps_state + 0x40` is a 4-byte aligned float written on the main thread and
read by the camera stubs per frame; a 32-bit store is atomic on arm64, so the
worst case is one frame at the old ratio.

## 5. Change set

Core mode (smallest set; the game view and pad remain the same objects):

| File | Function / place | Change |
|---|---|---|
| `dm/ios/project.yml` | `UISupportedInterfaceOrientations` (`:38-40`) | add `UIInterfaceOrientationPortrait`; the view controller still restricts normal mode to landscape |
| `dm/ios/Sources/front_ios.m` | statics near `:26` | `g_dual`, `g_hinge_closed`, `g_hinge_partial`, `g_game_aspect`, `K_DUAL_GAP` |
| | `-startGame` (`:73-90`) | read `DM_DUAL_SCREEN`; add the `UIHingeInteraction` under `@available(iOS 27.1, *)` (capture `self` weakly: the view retains the interaction and the interaction retains the handler); `[self setNeedsUpdateOfSupportedInterfaceOrientations]` |
| | `-viewDidLayoutSubviews` (`:91-109`) | compute `pictureArea`/`controlRegion`; apply `DM_ASPECT` inside the area; call `dm_gamepad_region`; place the FPS label in the strip in dual mode; update `g_game_aspect` and `dm_duo_aspect_update` |
| | `-supportedInterfaceOrientations` (`:124`) | landscape, or portrait+landscape when `g_dual` |
| | new `front_game_aspect` | return the cached atomic aspect |
| `dm/ios/Sources/DmGamepad.m` | ivars (`:137-153`) | `_region`, `_gameRect`, `_dual` |
| | `-initWithFrame:` (`:169-209`) | default `_region = bounds`, `_gameRect =` the 16:9 box of `bounds` |
| | new `-setControlRegion:gameRect:dual:` + `-region` + `-padHidden` | convert from the superview, reset held touches when the layout changes, `setNeedsLayout` (the root may `layoutIfNeeded` once after the first layout so the first frame is already in the strip) |
| | `safe` / `corner` / `u` / `inRightArea` (`:226-238`) | measure inside `region` (intersect with the safe area) |
| | `-pushGame` (`:319-330`) | normalize on `_gameRect`; update the comment |
| | `-touchesBegan:` (`:335-355`) | the `_dual` region gate and game-rect gate above |
| | `-padsChanged:` (`:523-527`) | `[self.superview setNeedsLayout]` after `_padOff` |
| | new C entry points next to `:531-538` | `void dm_gamepad_region(UIView *, CGRect region, CGRect game, BOOL dual);` and `BOOL dm_gamepad_hidden(void);` |
| `dm/games/settings.tsv` | Controls section | the `DM_DUAL_SCREEN` toggle row (4.1) |

Duo-aspect correctness (separable; required when `DM_DUO_ASPECT` is set, which is
the Duo build):

| File | Function / place | Change |
|---|---|---|
| `dm/host/front.h` | after `front_screen_max_fps` | `float front_game_aspect(void);` |
| `dm/host/loader.c` | near `:226` | include `front.h` (or declare the hook); weak `front_game_aspect` returning 0; `dm_duo_aspect_update` |
| | `dm_fps_state_apply` (`:234-255`) | prefer the front end's aspect over the env value, log the source |
| `dm/host/hle.h` | near `dm_fps_state` (`:63`) | declare `dm_duo_aspect_update` |
| `dm/ios/Sources/front_ios.m` | `-viewDidLayoutSubviews` | the atomic cache and the update call |

Documentation (when the mode ships):

| File | Change |
|---|---|
| `docs/env_switches.tsv` | `DM_DUAL_SCREEN` row (player, iOS) and a note on `DM_DUO_ASPECT` following the game view's aspect |
| `docs/settings.md` | the Controls table row for `DM_DUAL_SCREEN` (`1`, `0`) |
| `duo/README.md` | status row for the mode; keep `duo.env` without `DM_DUAL_SCREEN` so the launcher can turn it off |

No change is needed to `Launcher.swift`, `LauncherRow.swift`,
`LauncherSettings.swift` (a toggle row is already supported), `main.m` (the scene
delegate needs no orientation callback), `front_mac.m` (the weak aspect hook
returns 0 and the Mac keeps its env value), or the present pass.

## 6. Risks

### Touch hit-testing

- The pad is the only touch owner and stays full-screen. The region gate must run
  **before** every hit test; otherwise the shoulder teardrops (`1.35 × r`) and the
  3D right-third rule reach into the picture. The design gates at the top of
  `touchesBegan`, not inside each hit test.
- The 3D right stick must be the right third of the **strip**, not the screen. If
  `inRightArea` keeps using `self.bounds`, a touch on the picture's right third
  grabs the camera and the game's pointer never sees it.
- `pushGame` must use the real game frame. The old local 16:9 fit is wrong under
  `DM_ASPECT=fill` even without dual mode; dual mode makes the error visible
  because the picture and the pad no longer share a rectangle.
- A touch held across a rotation/fold change must be released. The region setter
  calls `reset`; without it the stick's `_stickNow` is in the old coordinate space
  and the knob jumps.
- Tap layout: picture touches go to the game, strip touches other than the layout
  button do nothing. Verify the layout button still toggles after the region gate.
- The layout button sits at the crease. It is small (r 16.6 pt portrait / 11.7 pt
  landscape) and only counts when released on itself (`DmGamepad.m:374`), so a
  fold adjustment is unlikely to cycle the layout accidentally, but test it.
- `_padOff` is applied on the main queue. The root must re-layout after that block
  runs (`[self.superview setNeedsLayout]`); otherwise the picture stays split
  until the next rotation.

### Game view aspect

- `DM_ASPECT=fill` in landscape gives a 2.843:1 picture. Without the camera-ratio
  update the world is stretched ~2×; with it the projection is correct but the HUD
  is stretched 1.60× (the existing `duo/DESIGN.md` UI-pass issue). Recommend
  portrait for dual mode, or the default 16:9 fit in landscape.
- The fixed `DM_DUO_ASPECT=2853:2007` is a full-screen value. The new hook makes
  the camera follow the game view's actual aspect; if the hook is not implemented,
  dual mode must leave `DM_ASPECT` unset (fit) and `DM_DUO_ASPECT` must match the
  half, which cannot cover both orientations at once.
- `DM_PRESENT_FILL=stretch` is required with fill; with fit, the 16:9 canvas and
  the 16:9 drawable are 1:1, so `off` and `stretch` are equivalent.
- The half-height is 1426.5 px at 3×. The layer rounds the drawable to a whole
  pixel; the aspect difference is < 0.04 %. Do not chase it.
- The game's canvas is unchanged. In portrait the picture is 2007 px across, so a
  1920-px canvas is nearly native (1.05×), sharper than the full-screen 2853-px
  drawable (1.49×); in landscape fill it is the same 1.49× as full-screen. Dual
  mode never makes the picture softer than the full-screen Duo layout.

### Performance

- The drawable halves: 2853 × 2007 = 5.73 Mpx full-screen landscape, versus
  2.86 Mpx in either dual fill orientation (50 %), 2.27 Mpx portrait fit (40 %) and
  1.79 Mpx landscape fit (31 %). The present and any MetalFX spatial scaling write
  fewer pixels; the game's own render targets are untouched.
- The pad still composites one full-screen transparent `UIView` over the screen,
  as today; its `CAShapeLayer`s only cover the strip and are not redrawn per frame.
  No extra pass is added.
- Resizing the drawable on rotation/fold reallocates the drawable and possibly the
  MetalFX scaler once. Do not animate the game view's frame; set it in layout.
- The hinge handler is event-driven; only status changes trigger layout. Do not
  lay out on every angle update (the header explicitly says the rate is system
  policy).
- The inner display runs at 60 Hz (simulator capability), so the game's 60 fps
  target is unchanged; dual mode does not add a frame of latency.

### API and fallbacks

- `UIHinge`/`UIHingeInteraction` are iOS 27.1+. The deployment target is 26.0;
  guard with `@available(iOS 27.1, *)` and keep the bounds-change path. On iOS 26,
  or when the runtime has no hinge data (a non-foldable, or a simulator profile
  without fold capability), `hinge` is nil: dual stays on, gap 0.
- The hinge API gives no crease axis/position. The split is horizontal in the
  interface orientation; in landscape a physical vertical crease is not aligned
  with the gap. That is a stated limitation, not something the current API can
  fix.
- If the system resizes the scene in a flex posture (not documented), the bounds
  change and the layout adapts; if it letterboxes the app into one half, the split
  would be applied inside that half. The design uses the scene bounds as the only
  reliable rectangle.
- Enabling portrait in the Info.plist also lets the SwiftUI launcher rotate. Its
  1/3 + 2/3 `HStack` (`Launcher.swift:101-143`) still lays out in 669 × 951, but
  it is a new posture; if it looks wrong, subclass the hosting controller to keep
  the launcher landscape. This is a polish item, not a blocker.
- The cover display is 466 × 678 pt; the mode deliberately turns off there. If the
  hinge status is unavailable on the cover display, dual stays on and splits the
  cover screen; still functional, just small.

## 7. What to verify on the device

1. Build with Xcode 27.1 / SDK 27.1, deployment target 26.0, on iPhone19,4
   (iOS 27.2). Start with the launcher row on; confirm the split in portrait and
   landscape and that normal mode still starts landscape.
2. Rotate while a stick and a key are held: both release, the knob returns, the
   picture re-frames, the present has no stale bars.
3. Touch the picture's right third in 3D: it must not grab the right stick. Touch
   the strip between controls: nothing. Touch the picture in handheld mode: the
   game's pointer follows (Tap, 2D and 3D).
4. Fold partly: the status log shows `partially open`, the 24 pt gap appears, and
   the picture and controls stay on their halves. Fold closed: the app returns to
   the full-screen layout on the cover display. Open: the split returns.
5. Connect a controller: the picture expands to the full screen and the strip
   disappears; disconnect: the split returns. Reconnect during a held touch: it is
   released.
6. With the Duo build (`DM_ASPECT=fill`, `DM_DUO_ASPECT` set), check a known
   circle in-game: it stays circular in portrait and landscape. The log line from
   `dm_fps_state_apply` should name the game view as the ratio source.
7. Watch the FPS counter: it sits in the strip's top row, not over the picture;
   the frame rate holds and the pad does no per-frame work (no shape redraws in
   Instruments).
