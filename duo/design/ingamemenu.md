# In-game settings menu

A settings overlay drawn over the running game, opened from the virtual gamepad or a
controller's Home button, that changes the settings the host can still act on **without
quitting the app**. Today the only in-game control is the 2D/3D/Tap pill
(`dm/ios/Sources/DmGamepad.m:210-223`, `:374-380`): every other choice lives on the
pre-game screen (`dm/ios/Sources/Launcher.swift:94-165`), which is shown once, before the
guest boots (`front_ios.m:118-119` → `dm_show_launcher` → `startGame`), and cannot be
reached again: `dm_main` runs the guest on the big-stack thread and never returns to the
launcher (`dm/host/main.c:142-144`).

The menu reuses the launcher's settings list, its row views and its persistence, and adds
the one thing the launcher cannot do: a **live** application path for the settings the host
already reads at run time, and an honest **"applies at the next start"** mark for the rest.

---

## 1. Where the settings come from

| Step | Evidence |
|---|---|
| `dm/games/settings.tsv` lists the player-facing rows (variable, kind, default, shown-if, section, label, note, meta) | `dm/games/settings.tsv:1-34` |
| `dm/games/settings.py` filters them per game and platform (`SETTINGS_PLATFORM`, default `ios`; `needs`; `level`) and writes the list | `dm/games/settings.py:60-106` |
| The packer writes that list into the app as `dm/launcher.json` | `scripts/build_ipa_from_nsp.py:2067` |
| `dm_show_launcher` decodes it into `SettingsFile` and presents the screen | `dm/ios/Sources/Launcher.swift:168-188` |
| `LauncherModel` seeds each row from a fixed env value, else a saved choice, else the default | `dm/ios/Sources/LauncherSettings.swift:46-58` |
| Play writes every non-fixed value into the environment and (unless it is the default) into `UserDefaults` | `LauncherSettings.swift:98-105` |
| `DM_LAUNCHER=0` starts at once but still applies the saved choices | `Launcher.swift:172`, `LauncherSettings.swift:108-112` |
| An env file's keys and the launch environment's keys are passed to the model and stay fixed | `dm/ios/Sources/main.m:134-135`, `LauncherSettings.swift:47-51` |

Two consequences for the overlay:

1. **It is data-driven.** Any row the game's `launcher.json` carries — including rows added
   later for the Duo (dual-screen mode, frame generation) — appears with no UI code, as long
   as it is a `settings.tsv` row. The overlay only has to know *which rows can be applied
   live*; that is a table in one new C file (§5).
2. **Persistence already works.** A value written to `launcher.<ENV>` in `UserDefaults` is
   read back by the next launch's `LauncherModel` (`LauncherSettings.swift:56`) whether
   the launcher screen runs (`apply()`) or not (`applySaved()`). So a "next start" change
   needs no new storage.

`fixed` (env file / launch environment) stays locked in the overlay exactly as in the
launcher: those rows are shown disabled with the reason (`LauncherRow.swift:13-17`, `:58`).

---

## 2. What the host reads at startup, and what it can still change

Everything the launcher sets is an environment variable, and the environment is read at
different moments: some switches are consulted on every frame, some are cached in a
`static` on first use, some are consumed while the game is being set up. That — not the
setting's category — is what decides whether it can change live.

### 2.1 The live channel: the frame-step state page

Builds whose profile has `FRAME_STEP` get a read-write page in `main`, after the key page
(`dm/tools/patch_nso.py:1171-1189`). Its layout is documented at `patch_nso.py:1156-1168`:

| Offset | Contents | Written by |
|---|---|---|
| `+0x00` | float target fps (0 = the game's own interval logic) | loader, `dm_fps_state_apply` |
| `+0x04` | movie flag | host, each present (`dm/gfx/nvn/hle_nvn.c:1813`) |
| `+0x10` | float render scale | loader |
| `+0x20` | u32 step in vsyncs | host (`hle_nvn.c:1770`) |
| `+0x24` | u32 a step the game fixes itself | the game's stub |
| `+0x40` | float drawable aspect ratio (Duo) | loader, `duo_aspect.py` |

The loader writes it once, immediately before the guest starts
(`dm/host/loader.c:234-258`, called from `dm/host/main.c:142`). Nothing in the page is
cached on the host side:

- `fps_step_cap()` re-reads `+0x00` on every present (`hle_nvn.c:1635-1643`) and the
  thermal cap already flips that value mid-run (`hle_nvn.c:1613-1634`), so a changed cap is
  a supported transition — `present_itv` (`:1675`), `nvn_game_fps` (`:1660`) and the
  display-link mode all follow it on the next present, and the change is logged
  (`hle_nvn.c:1815-1816`: `[nvn] frame step cap 60 → 30 fps at present N`).
- The game's own stubs read `+0x00`/`+0x10`/`+0x40` on every execution. The render-scale
  stub, for instance, loads `[state + 0x10]` each time the view-sizing function runs
  (`dm/games/0100F2C0115B6000/patches.py:107-123`), and the Duo aspect stub loads
  `[state + 0x40]` at each patched site (`dm/tools/duo_aspect.py:44-56`).

So **frame rate, render scale and the aspect ratio are writable at run time**, and the
value is seen by both the host's pacing and the game's own code on the next frame.

Two caveats that the overlay must respect:

- The page only exists on builds with `FRAME_STEP` (`dm/host/hle.h:63`: "NULL when the
  build has none"). `dm_fps_state == NULL` means "not live on this game".
- Builds that are capped by an *engine-native* limiter instead (`dm/host/hle_fpslock.c`,
  `k_locks` / Frostbite / NieR rows) read `DM_FPS_TARGET` **once**, at the first present
  (`hle_fpslock.c:211-231`). There the target is applied by writing the game's own fields
  every present (`:245-265`), so a live target is one static away (§5, Tier 2).

### 2.2 Settings read once, at start

| Where it is read | Consequence |
|---|---|
| `dm_opmode()` takes `DM_OPMODE` once into an atomic (`dm/host/hle_oe.c:8-14`) | the mode is runtime state; `dm_set_opmode` exists and pushes notification 30 (`hle_oe.c:51-56`), but `GetDefaultDisplayResolution` returns the mode's size (`:150-153`) and `GetDefaultDisplayResolutionChangeEvent` is "bound, never signaled" (`:154-155`), so a game that sized its render targets at boot cannot be relied on to resize |
| `GetDesiredLanguage` reads `DM_LANG` per call (`hle_oe.c:245-251`) | the host would answer a new language, but the game has already built its fonts and string tables at boot |
| `fx_mode()` caches `DM_PRESENT_UPSCALE` in `g_fx_mode` (`dm/gfx/nvn/nvn_mtl.m:11181-11193`) | one static; live-able with a setter |
| `present_viewport` caches `DM_PRESENT_FILL` in `static int fill` (`nvn_mtl.m:11121-11131`) | one static |
| `mtl_snap_on()` caches `DM_PRESENT_SNAP` and sizes the ring (`nvn_mtl.m:11683-11694`) | the ring's textures, events and command buffers are live GPU state (`nvn_mtl.m:11670-11682`); not a run-time toggle |
| `pso4_on()` (`nvn_mtl.m:5583-5600`), the prebuild (`:6318`, `:6612`), the encode thread (`dm/gfx/nvn/nvn_rec.h:81`) | pipeline/archive/thread construction at first use |
| `fstep_hold()` caches `DM_FPS_HOLD` (`hle_nvn.c:1732-1738`) | one static |
| `dm_haptics_apple_init` reads `DM_RUMBLE`, `DM_RUMBLE_GAIN`, `DM_RUMBLE_MIN` once (`dm/host/haptics_apple.m:394-405`) into `gain` (`:44`) and `rumble_min` (`:71`) | `dm_haptics_init` may be called again (it clears every motor, `dm/host/hle_haptics.c:23-29`) |
| `DM_TOUCH_HAPTICS` at gamepad init (`DmGamepad.m:172-176`) | the generator is per view |
| `DM_SHOW_FPS` at gamepad start (`front_ios.m:147-166`) | the label is created (or not) in `startGame` (`:85-86`) |
| `DM_METAL_HUD` as a layer property (`front_ios.m:80`) | a property, settable at any time |
| `DM_ASPECT` in `viewDidLayoutSubviews` (`front_ios.m:98`) | one static |

### 2.3 Inventory

The iOS list is `settings.tsv` minus the `platform:mac` row (`DM_FULLSCREEN`), i.e. 17 rows
(`dm/games/settings.tsv:17-34`). "Live" below means: a change is visible without restarting
the app.

| Setting (`env`) | Row | Class | Live path |
|---|---|---|---|
| `DM_FPS_TARGET` | `settings.tsv:17` | **live** on builds with a state page; next start otherwise | write state `+0x00` (`loader.c:234-238`); read per present (`hle_nvn.c:1635`) |
| `DM_RENDER_SCALE` | `settings.tsv:19` | **live** | write state `+0x10` (`loader.c:241-243`); the stub loads it per call (`patches.py:107-123`) |
| `DM_FPS_HOLD` | `settings.tsv:33` | **live** with a setter | `hle_nvn.c:1732-1738` caches it |
| `DM_PRESENT_UPSCALE` | `settings.tsv:21` | **live** with a setter | `nvn_mtl.m:11181-11193` caches it; the scaler is rebuilt on demand in `fx_encode` (`nvn_mtl.m:11199-11230`) |
| `DM_RUMBLE` | `settings.tsv:26` | **live** with a setter | `haptics_apple.m:404` → `dm_haptics_init` |
| `DM_RUMBLE_GAIN` | `settings.tsv:27` | **live** with a setter | `haptics_apple.m:44`, `:400` |
| `DM_RUMBLE_MIN` | `settings.tsv:28` | **live** with a setter | `haptics_apple.m:71`, `:401` |
| `DM_TOUCH_HAPTICS` | `settings.tsv:25` | **live** with a setter | `DmGamepad.m:172-176` |
| `DM_SHOW_FPS` | `settings.tsv:24` | **live** with a setter | `front_ios.m:147-166` |
| `DM_METAL_HUD` | `settings.tsv:34` | **live** with a setter | `front_ios.m:80` |
| `DM_OPMODE` | `settings.tsv:20` | **next start** | see §2.2: the host can change it (`hle_oe.c:51-56`) but the game cannot reliably follow |
| `DM_LANG` | `settings.tsv:22` | **next start** | the game builds its text at boot |
| `DM_DYNAMIC_RESOLUTION` | `settings.tsv:18` | **next start** (one static; settable if wanted) | `hle_fpslock.c:96-125` |
| `DM_PRESENT_SNAP` | `settings.tsv:29` | **next start** | ring state, `nvn_mtl.m:11683-11694` |
| `DM_PSO_MTL4` | `settings.tsv:30` | **next start** | `nvn_mtl.m:5583-5600` |
| `DM_PSO_PREBUILD` | `settings.tsv:31` | **next start** | `nvn_mtl.m:6318`, `:6612` |
| `DM_NVN_ENC_THREAD` | `settings.tsv:32` | **next start** | `nvn_rec.h:81` |
| `DM_ASPECT` / `DM_PRESENT_FILL` / `DM_DUO_ASPECT` | not a row (baked by `duo/duo.env`) | **next start** today; the camera ratio is live by design | `front_ios.m:98` and `nvn_mtl.m:11121` cache the first two; the ratio itself is the state page's `+0x40` (`loader.c:247-254`, `duo_aspect.py:18`) |
| pad layout (2D/3D/Tap) | not an env row | **live** | `DmGamepad.m:129`, `:217-223` |

---

## 3. The overlay

### 3.1 Shape and place in the view hierarchy

`DmRootVC` builds three views, in order: the game view (`CAMetalLayer`,
`front_ios.m:28-46`, added at `:77`), the full-screen gamepad (`:82-84`), the fps label
(`:85-86`). The overlay is a fourth, topmost layer, presented as a view controller with
`UIModalPresentationStyle.overFullScreen` over the same window.

```
UIWindow
└─ DmRootVC.view
   ├─ DmGameView            (CAMetalLayer, 16:9 or fill — front_ios.m:94-104)
   ├─ DmGamepad (self.pad)  (full screen, all game touches and buttons)
   ├─ UILabel  (fps)        (hidden unless DM_SHOW_FPS — front_ios.m:147)
   └─ presented InGameMenuController   ← new, overFullScreen, clear background
        ├─ scrim  (black 0.35, tap = close)
        └─ panel  (420 pt wide, pinned to the trailing safe edge, dark, rounded)
```

A full-screen transparent container with a light scrim (not an opaque sheet) is deliberate:
the game keeps running and presenting underneath, so the player can *see* what a frame-rate
or render-scale change does. The panel takes about 45 % of the landscape width, leaving the
picture visible.

Auto Layout and `view.safeAreaInsets` only — no fixed frames, so it is correct in either
landscape orientation and in whatever fold state the app is in. The controller forwards the
presenter's `supportedInterfaceOrientations` (landscape, `front_ios.m:124`),
`prefersStatusBarHidden`, `prefersHomeIndicatorAutoHidden` and
`preferredScreenEdgesDeferringSystemGestures` (`front_ios.m:121-124`).

### 3.2 Opening it

Two triggers, both deliberate:

1. **A menu pill on the gamepad**, next to the layout pill. New constants in the top row:
   `K_MENU_X = 100` (from the screen's midline), `K_MENU_Y = K_PILL_Y` (22), `K_MENU_R = 15`
   (the layout pill's radius). It sits just outside `+`, which spans 27…77 in `u` units
   (`K_PILL_DX = 52`, `K_PILL_W = 50` — `DmGamepad.m:115`), so the circle covers 85…115:
   an 8 u gap and no overlap with `−`/`+` or the layout pill at the centre
   (`K_SWAP_R = 15`, `:116`).
   Its layer is added to `self.layer`, **not** to `_controls`, so it survives the
   "a controller is connected" hide (`_controls.hidden = any`, `:527`) — otherwise a player
   with a controller would have no touch route to the menu at all.
   Label `≡` in the system UI font, like the other labels (`DmGamepad.m:408-414`).
2. **A controller's Home button.** Home and Capture already have their system gestures
   disabled and "the app gives them no function" (`DmGamepad.m:479-480`), so Home is free:
   its `valueChangedHandler` opens the menu. Menu/Options keep their game meaning
   (`buttonMenu → B_PLUS`, `:473`).

Opening is a single entry point, `front_ios_menu_toggle()` (`front_ios.m`, new), which
dispatches to the main queue and toggles. It undoes itself when the app carries no settings
list: `dm_ingame_menu_present` returns `false` (as `dm_show_launcher` does,
`Launcher.swift:170-171`), and the pad is re-enabled at once — the menu can never leave the
game without input.

### 3.3 What it shows

Sections, top to bottom:

- **Now** — the live rows, in list order, drawn with `SettingRow` exactly as the launcher
  draws them (`LauncherRow.swift:9-60`): choices as menus, ranges as sliders with the
  percentage/pixel label (`LauncherSettings.swift:80-86`), toggles as switches.
- **Controls** — pad layout: a three-way picker (2D / 3D / Tap, Tap only in handheld mode —
  `DmGamepad.m:197`) that calls `dm_gamepad_set_layout`. This replaces the tap-to-cycle pill
  as the discoverable place for the choice while keeping the pill itself.
- **Next start** — the rows that need a relaunch, same widgets, each with the note
  "Applies at the next start of the game".
- **Footer** — live status: frames per second (`mtl_present_count()`, declared at
  `front_ios.m:146`, defined at `nvn_mtl.m:10743`), thermal state (`dm_thermal_now()`, `front_ios.m:131`) and the
  frame-step cap when it differs from the chosen target (the thermal cap holds 30 fps at
  `thermalState >= 2`, `hle_nvn.c:1613-1634` — a player who chose 60 must be told why the
  game runs at 30); then **Reset to tested defaults** and **Done**.

Rows whose setting is fixed by an env file or the launch environment are drawn disabled with
their reason (`LauncherRow.swift:13-17`), as in the launcher.

### 3.4 Applying a change

`LauncherModel` gains one method (`LauncherSettings.swift`) that is pure Foundation, so the
Mac target that compiles the same file (`dm/ios/tests/test_launcher_storage.py:30`) is
unaffected:

```swift
// Store one choice exactly as apply() does: only a value that differs from the game's
// default is kept, and nothing is written for a fixed row or under DM_SAVED_CHOICES=0.
func store(_ s: Setting, _ v: String)
```

and the iOS-only extension in `InGameMenu.swift` decides *how* it takes effect:

```swift
func commit(_ s: Setting, _ v: String) -> Bool {   // true = applied now
    guard !fixed.contains(s.env) else { return false }
    store(s, v)
    let live = dm_setting_live(s.env, v) != 0
    if live { pending.remove(s.env) } else { pending.insert(s.env) }
    return live
}
```

- **No `setenv` on the live path.** POSIX does not require `setenv`/`putenv` to be
  thread-safe, and the host calls `getenv` from the present thread, the audio thread and the
  game thread (`hle_nvn.c:1649`, `hle_oe.c:245`, `front_ios.m:148`). The environment stays
  the *launch-time* record written by the launcher; a run-time change goes through explicit
  setters and the state page, and persistence goes through `UserDefaults`, which the next
  launch's `LauncherModel` reads (`LauncherSettings.swift:56`).
- `dm_setting_live(env, value)` returns **1 only when the change was really applied**; a
  setting with no live path — or a build without a state page (`dm_fps_state == NULL`,
  `hle.h:63`) — returns 0, and the row is marked pending. The UI therefore never claims a
  change it did not make.
- A **session-scoped model** (a `static` in `InGameMenu.swift`) is created on the first
  open and reused, so values survive closing and reopening, and survive
  `DM_SAVED_CHOICES=0`, where nothing is stored (`LauncherSettings.swift:52`, `:102`).
- **Reset** runs `commit` on every non-fixed row with the game's default, so live rows
  return to their tested values immediately and the rest are marked pending.

### 3.5 Closing

Done, the scrim, or a downward swipe on the panel. Closing calls the `closed` C callback
given to `dm_ingame_menu_present` (the shape `dm_show_launcher` already uses,
`Launcher.swift:168-188`), which re-enables the gamepad and resumes input (§4). The menu
also closes itself when the app goes to the background (focus event 1,
`front_ios.m:291`), so it is never stale on return.

---

## 4. Input routing

Touches reach the game **only** through the gamepad view:

- game touch screen → `dm_touch_set`, pushed from `pushGame` (`DmGamepad.m:319-333`) and
  documented in `dm/host/front.h:39-40`;
- buttons and sticks → `dm_input_set` (`DmGamepad.m:32-37`) and `dm_pad_set_player`
  (`:466-480`).

Nothing else in the iOS front end calls `dm_touch_set`; so "the game must not receive the
touches meant for the UI" reduces to "the pad must receive nothing, and must have released
what it holds".

On open, in this order:

1. `dm_gamepad_suspend(1)` → `[g_view reset]` (`DmGamepad.m:384`): every touch owner,
   diamond mapping, stick and game finger slot is cleared and an **empty** touch set is
   pushed, so a finger held at that instant does not stay pressed in the game.
2. The same call sets a file-scope `_Atomic int` that `read_pad` (`:466`) checks: while it
   is set, every controller reports zeros (`dm_pad_set_player(p, 0, 0, 0, 0, 0)`) instead of
   its live state — otherwise moving a controller's stick behind the menu would drive the
   game.
3. `self.pad.userInteractionEnabled = NO` — UIKit stops delivering touches to the pad
   entirely, so neither the controls nor the "forward to the game" path (`:338`, `:342`, `:352`)
   can run.
4. The overlay is presented on top; its scrim is the only hit target outside the panel.

On close the three steps reverse, and each controller is read once (`read_pad`) so a button
that is still held registers again instead of waiting for its next edge.

The menu pill is the one control tested **before** the `_padOff` branch (`:338`), because
with a controller connected the whole touch layer forwards to the game. The cost is one
30 pt target at the top centre-right that no longer reaches the game's touch screen in that
state; it is in the strip the fps label already occupies on the left (`front_ios.m:105-107`)
and where no game control sits.

---

## 5. Change set

### Tier 1 — the menu, the two state-page settings, the pad layout

| File | Change |
|---|---|
| `dm/ios/Sources/InGameMenu.swift` **(new, iOS only)** | `extension LauncherModel { func commit(...) }`; `InGameMenuView` (SwiftUI: scrim + panel + sections + footer); `InGameMenuController` (`.overFullScreen`, forwards orientation/status-bar preferences); `@_cdecl("dm_ingame_menu_present")` mirroring `dm_show_launcher` (`Launcher.swift:168-188`), returning `false` when the app has no `dm/launcher.json`; the session-scoped model |
| `dm/ios/Sources/LauncherSettings.swift` | `@Published var pending: Set<String>` and `func store(_:_:)` (the `apply()` write rule of `:98-105`, factored out; `apply()` keeps working unchanged) |
| `dm/ios/Sources/LauncherRow.swift` | `note` (`:14-17`) appends "Applies at the next start" while `m.pending.contains(s.env)` |
| `dm/ios/Sources/settings_live.m` **(new, iOS only)** | `int dm_setting_live(const char *env, const char *value)`: parse, dispatch, return 1 only if applied. Tier 1 handles `DM_FPS_TARGET` → `dm_fps_state_set_fps(atoi(v))`, `DM_RENDER_SCALE` → `dm_fps_state_set_scale(strtof(v))`; returns 0 when `dm_fps_state == NULL` |
| `dm/host/loader.c`, `dm/host/hle.h` | split `dm_fps_state_apply()` (`:234-258`) into `dm_fps_state_set_fps(int)`, `dm_fps_state_set_scale(float)`, `dm_fps_state_set_aspect(float)` — each a 32-bit `__atomic_store_n` at the page offset — and let `dm_fps_state_apply()` read the environment and call them, so boot behaviour is bit-identical |
| `dm/ios/Sources/front_ios.m` | declare `bool dm_ingame_menu_present(void *, void (*)(void))`; `DmRootVC` gains `menuOpen`, `-inGameMenuToggle` (suspend + disable the pad, present, remember `self.pad`) and the `closed` callback; `void front_ios_menu_toggle(void)` |
| `dm/ios/Sources/DmGamepad.m` | `C_MENU` + `_menu`/`_menuLabel` layers in `self.layer`; `K_MENU_X`/`K_MENU_R`; `-inMenu:`; claim in `touchesBegan` before `_padOff`; fire in `endTouches` when released inside (the `C_SWAP` shape, `:374-380`); `void dm_gamepad_suspend(int)`; the `_Atomic` check in `read_pad`; `void dm_gamepad_set_layout(int)` (the body of `nextLayout` `:217-223` with the layout given, including the Tap-in-handheld clamp of `:197`); Home button handler in `pad_keep_system_buttons` (`:480`) |
| `dm/ios/Sources/DmIOS-Bridging-Header.h` | declare `dm_setting_live`, `mtl_present_count`, `dm_thermal_now`, `dm_opmode`, `dm_gamepad_set_layout` |

New `.m`/`.swift` files under `dm/ios/Sources/` need no project edit: `project.yml:14-16`
takes the whole folder, and `dm/ios/tools/compile_check.py:30` globs `*.m`.

### Tier 2 — one small setter per extra live row

Each is independent and can ship on its own; the overlay picks it up by adding one line to
`dm_setting_live`'s table.

| Setting | Setter | Where |
|---|---|---|
| `DM_FPS_HOLD` | `dm_nvn_fps_hold_set(int)` — lift the `static h` out of `fstep_hold` into a file-scope `_Atomic int` | `hle_nvn.c:1732-1738` |
| `DM_PRESENT_UPSCALE` | `mtl_fx_present_set(int)` — set `g_fx_mode` atomically; the next `fx_encode` builds or drops the scaler | `nvn_mtl.m:11181-11193`, `:11199` |
| `DM_RUMBLE`, `DM_RUMBLE_GAIN`, `DM_RUMBLE_MIN` | `dm_haptics_apple_set(int on, float gain, float min)` — the three env reads of `dm_haptics_apple_init` move into a helper the setter also calls; gain/min are stored on the rumble queue; `dm_haptics_init` is safe to call again | `haptics_apple.m:394-405`, `hle_haptics.c:23-29` |
| `DM_TOUCH_HAPTICS` | `dm_gamepad_touch_haptics(int)` — allocate/release `_touchFeedback` on the main queue | `DmGamepad.m:172-176` |
| `DM_SHOW_FPS` | `front_ios_fps_set(int)` — create the label lazily, keep the 1 Hz timer, hide/show; `-viewDidLayoutSubviews` reads the file-scope label | `front_ios.m:147-166`, `:105-107` |
| `DM_METAL_HUD` | `front_ios_hud_set(int)` — `g_layer.developerHUDProperties = on ? @{@"mode": @"default"} : nil` | `front_ios.m:80` |
| `DM_FPS_TARGET` on engine-locked builds | `dm_fps_lock_set_target(int)` — the tick rewrites the game's fields every present they differ, so a new target lands on the next present | `hle_fpslock.c:211-231`, `:251-265` |
| `DM_DYNAMIC_RESOLUTION` | `dm_fps_lock_set_dynamic(int)` — the `dynamic` flag is a static inside the tick | `hle_fpslock.c:96-125` |
| `DM_ASPECT` / `DM_PRESENT_FILL` | make `front_ios.m:98` and `nvn_mtl.m:11121` re-readable (a setter clearing the cached `fill`), then `dm_fps_state_set_aspect` from Tier 1 makes the Duo ratio live end to end | `front_ios.m:94-104`, `nvn_mtl.m:11121-11134`, `duo_aspect.py:18` |

### Not part of this

- **A way back to the launcher.** The guest runs on `front_run` (`main.c:143`) and never
  returns; changing a "next start" row means quitting and reopening the app. The overlay
  says so instead of offering a restart it cannot perform.
- **The dual-screen mode** being designed in parallel. Its switch, once it is a
  `settings.tsv` row, appears in the overlay with no UI change; only its live/next-start
  classification and the panel's anchor (one constant in `InGameMenuController`) need a
  decision.

---

## 6. Risks

1. **Render scale is a view resize.** The stub multiplies both extents of each 3D view
   (`patches.py:107-123`) and, for any factor other than 1.0, replaces the game's dynamic
   multiplier with 1 — so the picture changes size on the next frame and the game
   reallocates its attachments: expect a hitch and a transient memory peak, and note that
   dynamic resolution is off while the scale is not 1.0 (that is the launcher's behaviour
   too, `settings.tsv:18-19`).
2. **Frame-rate changes reconfigure pacing.** `fps_step_cap` feeds `present_itv`
   (`hle_nvn.c:1675`), `nvn_game_fps` (`:1660`) and the display-link mode; a change costs a
   frame or two of jitter, and the thermal cap (`:1613-1634`) can still hold 30 regardless
   of the choice — which is why the footer shows it.
3. **Writes to guest memory.** Only 32-bit aligned stores to the state page; the game's
   plain `ldr` sees either the old or the new value, never a mix. The 64-bit fields
   (`+0x18`, `+0x30`) are never written by the setters.
4. **First SwiftUI render over a running game.** ~30-60 ms on the main thread; the guest
   thread is not blocked (unlike `front_text_input`, `front_ios.m:194-217`, which parks its
   caller), so the game keeps rendering but may drop a frame as the menu appears.
5. **Fixed rows.** `fixed` (env file / launch environment) must stay locked in the overlay
   (`LauncherSettings.swift:47-51`, `LauncherRow.swift:13`), or an in-game change would
   silently beat a value the player wrote in `Documents/env.txt` and the launcher refuses to
   touch.
6. **`DM_SAVED_CHOICES=0`** stores nothing (`LauncherSettings.swift:52`, `:102`); the
   session model keeps the value visible for this run, and it is gone at the next start —
   which is exactly what that switch asks for.
7. **Games without a frame-step page** get no live frame-rate row; the table returns 0 and
   the row moves to "Next start" instead of pretending.
8. **The menu pill changes one touch region** while a controller is connected (§4): a
   30 pt circle at the top centre-right no longer reaches the game's touch screen.
9. **Home now has a function.** It had none (`DmGamepad.m:479-480`) and its system gesture is
   already disabled, so nothing is taken from iOS; but a player used to "Home does nothing"
   will now open the menu.
10. **Overlay over the present loop.** The scrim is a plain `UIView` at 0.35 alpha, so
    compositing costs one extra layer; no Metal pass is added and the game's own present
    path is untouched.

---

## 7. How it is checked

- `dm/ios/tests/launcher_storage_check.swift` (built by `dm/ios/tests/test_launcher_storage.py:30`):
  add cases for `store()` — a default value removes the key, a changed one writes it, a
  fixed row writes nothing, `DM_SAVED_CHOICES=0` writes nothing — and for `pending`.
- `dm/host/tests/t_resolution.c` and `t_fpslock.c` already drive `DM_FPS_TARGET` /
  `DM_RENDER_SCALE` through the state page (`t_resolution.c:14`, `t_fpslock.c:46`); add a
  case that calls `dm_fps_state_set_fps` after the first present and asserts the cap moved.
- `dm/ios/tools/compile_check.py` (globs `dm/ios/Sources/*.m`) covers the new ObjC file.
- On the device, with the log (`Documents/log.txt`): open the menu in a `FRAME_STEP` game,
  switch 60 → 30, and look for `[nvn] frame step cap 60 → 30 fps at present N`
  (`hle_nvn.c:1815-1816`) plus the fps counter settling at 30; move the render scale and
  watch the picture resize on the next frame (the same `3D views rendered at 0.75 of the
  game's size` line the loader logs at start, `loader.c:242`, should come from the live
  setter too).
