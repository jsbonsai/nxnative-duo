# In-game settings menu, v2 — one settings model behind two screens

Status: **v1 built, 2026-10-30 — see §7 for what shipped, the corrections the code forced, and the gaps that
remain (G1 partly, G9–G14).** §2–§4 are the design as written. This note supersedes
[`ingamemenu.md`](ingamemenu.md) where the two disagree: the overlay's shape, the input
suspension rules and most of its risk list still hold; its settings model, its second menu
button and its live/next-start classification do not. Every claim about the running code
below carries a `file:line`.

Read §0 first: the ⚙ panel shipped after v1 was written, and that changes the design.

---

## 0. What is built today, and the four things v1 got wrong

Built, read from the code:

| Piece | Where |
|---|---|
| The ⚙ panel: **Picture fill** (Stretch / Crop / Letterbox), **Split when upright** (Off / On), **On-screen controls** (Show / Hide), **Move / Play**, **Reset control positions**, **Close** | `dm/ios/Sources/DmGamepad.m:561-640`; opened by the ⚙ button at `:550-554` (bottom centre), toggled at `:570-571` |
| Picture fill is a live present-pass mode, not an env value | `dm_present_set_fill` at `dm/gfx/nvn/nvn_mtl.m:11122`, read per present at `:11132-11133`; `DM_PRESENT_FILL` only seeds it (`:11124-11128`) |
| Split follows the window's shape and is read on every layout | `dm_split_enabled` / `dm_split_active` at `DmGamepad.m:249-255`, consumed at `front_ios.m:106` |
| The pre-game launcher, drawn from the bundle's `dm/launcher.json` | `dm_show_launcher` at `dm/ios/Sources/Launcher.swift:168-189`; rows at `LauncherRow.swift:9-60`; model + persistence at `LauncherSettings.swift:37-112` |
| The settings list per game: 18 rows in the catalogue, 17 on iOS (`DM_FULLSCREEN` is `platform:mac`) | `dm/games/settings.tsv:17-34`; filtering at `dm/games/settings.py:71-79` |
| Saved choices: one string per row under `launcher.<VAR>` | written at `LauncherSettings.swift:102`, read at `:56`; the Mac launcher reads the same keys (`dm/mac/launcher.c:126-130`, `dm/mac/Launcher.swift:1-6`) |

Not built: there is no `InGameMenu.swift`, no `dm_setting_live`, no `dm_gamepad_set_layout`
and no `dm_gamepad_suspend`. The only exported pad entry points are `dm_gamepad_view`,
`dm_gamepad_active` and `dm_gamepad_reset` (`DmGamepad.m:759-763`). The bridging header
exposes nothing but `CloudSaves.h` (`dm/ios/Sources/DmIOS-Bridging-Header.h:3`).

Four corrections to v1:

1. **One button, not two.** v1 adds a `≡` pill next to the layout pill (`ingamemenu.md`
   §3.2) without noticing the ⚙ button that already exists. v2 grows the ⚙ panel into the
   menu; the controller's Home button is the second opener (its system gesture is already
   disabled and the app gives it no function, `DmGamepad.m:707-708`).
2. **One persistence, not two.** v1 adds `LauncherModel.store()` for the launcher's rows but
   leaves the panel's five choices in `DmFillMode` / `DmDualScreen` / `DmPadHidden` /
   `DmPadLayout` (`DmGamepad.m:129-131`, `:559-560`). A choice made in the panel therefore
   never appears in the launcher. v2 puts every player-visible choice in the same store.
3. **A live/next-start *query*, not just a write.** v1's `dm_setting_live(env, value)`
   answers only after a change. The menu must draw the badge *before* the player touches the
   row, so the bridge needs a side-effect-free state query.
4. **Fill and split cannot simply become launcher rows.** `dm_split_enabled` gives
   `DM_DUAL_SCREEN` precedence over the saved choice (`DmGamepad.m:250-251`), so a launcher
   row that sets that variable would freeze the menu switch — the exact failure recorded in
   `duo/design/dualscreen.md` §0.3 root cause 2. The runtime state must come first (§4 G2).

---

## 1. Inventory

"Live" means: the running game shows the new value without the app restarting. "Next start"
means the value is consumed once and only a relaunch reads it again. Each cell names the
read that decides it. A setting the app does not ship (capability missing, or `shown` false)
is not in the app's `launcher.json` at all (`settings.py:71-79`).

| Setting | What it changes | Live / next start — evidence | Today | Risk |
|---|---|---|---|---|
| **Frame rate** `DM_FPS_TARGET` (30 / 60 / 0) | The cap the host paces the game to; with the frame-step stubs it also decides the game's own time step | **Live** on builds with a frame-step page: the loader writes the page once (`dm/host/loader.c:234-238`, called from `dm/host/main.c:142`) and `fps_step_cap()` re-reads `+0x00` on every present (`dm/gfx/nvn/hle_nvn.c:1635-1643`); the change is logged at `:1815`. **Next start** without a page: `g_present_cap` is a one-shot static (`hle_nvn.c:1648-1653`). **Next start** on engine-limited builds: read once at the first tick (`dm/host/hle_fpslock.c:211-226`) | launcher | Live: safe; a frame or two of jitter. Next start: needs a relaunch. A movie or a serious thermal state still holds 30 regardless (`hle_nvn.c:1621-1641`) — the menu must say so |
| **Render scale** `DM_RENDER_SCALE` (0.5–1.0) | Size of the game's 3D views; also turns its dynamic resolution off | **Live** where the stub exists: the loader writes `+0x10` (`loader.c:241-243`) and the stub loads `[state+0x10]` on every execution of the view-sizing function (`dm/games/0100F2C0115B6000/patches.py:107-126`, site `main+0xd5cc0`) | launcher | Live: the game reallocates its attachments (hitch, transient memory peak). Cannot break the game |
| **Dynamic resolution** `DM_DYNAMIC_RESOLUTION` | Lets the game's own scaler work between 70 and 100 % (NieR-style builds only) | **Next start**: `static int state, dynamic` initialised once (`hle_fpslock.c:98-108`), then written into guest memory every present (`:127-137`) | launcher | Next start: safe. Live would write guest memory the game also writes — do not |
| **Console mode** `DM_OPMODE` (Docked / Handheld) | The operation mode the game sees; decides its canvas size and perf profile | **Next start**: cached in an atomic on first call (`dm/host/hle_oe.c:9-13`). The host *can* push a change (`dm_set_opmode`, `:51-56`, notification 30), but `GetDefaultDisplayResolution` answers the mode's size (`:151-163`) and its change event is "bound, never signaled" (`:164-165`), so a game that sized its targets at boot will not resize | launcher | **Can break a game** (fixed render targets, wrong perf profile). Keep next start |
| **Upscaling** `DM_PRESENT_UPSCALE` (Standard / MetalFX) | MetalFX spatial scaler in the present pass instead of a bilinear blit | **Next start today**: `g_fx_mode` is a one-shot static (`nvn_mtl.m:11187-11196`). The mode *is* read per present (`:11207`) and the scaler is rebuilt when its key changes (`:11208-11210`), so a setter is a one-line change (§4 G1) | launcher | Live-able: safe, one present of scaling hitch, a little more GPU time and heat |
| **Game language** `DM_LANG` | The language code `GetDesiredLanguage` / `GetRegionCode` answer | **Next start**: the host answers per call (`hle_oe.c:255-259`, `:265-269`) but there is no event to tell the game, and games build fonts and string tables at boot | launcher | **Can break a game** (mixed strings, missing font). Next start only |
| **Display mode** `DM_FULLSCREEN` | Mac window vs fullscreen | **Next start**: not in the iOS list at all (`settings.tsv:23`, `platform:mac`) | launcher (Mac) | Not an iPhone setting |
| **Frame-rate counter** `DM_SHOW_FPS` | The fps label at the top left | **Next start today**: the label is made once in `startGame` (`front_ios.m:87`) and the env is read there (`:168-170`); the 1 Hz timer is captured in the block (`:175-180`) | launcher | Live-able (G1): safe |
| **Touch feedback** `DM_TOUCH_HAPTICS` | The light tap when a touch control is pressed | **Next start**: read in the pad's init (`DmGamepad.m:186-189`), used at `:355-356` and `:421` | launcher | Live-able (G1): safe |
| **Game rumble** `DM_RUMBLE` | Controller / phone vibration on or off | **Next start**: one-shot init in `dm_haptics_apple_init` (`dm/host/haptics_apple.m:394-404`, `dm_haptics_init(apply, on)` at `:404`). `dm_haptics_init` clears every motor under a lock (`dm/host/hle_haptics.c:26-32`), so re-calling it is safe — a setter is S (§4 G7) | launcher | Live-able: safe (motors are re-cleared) |
| **Rumble strength** `DM_RUMBLE_GAIN` (0–300 %) | Scales the amplitude | **Next start**: `gain` static (`haptics_apple.m:44`), env read once (`:399-400`), applied per report (`:256-257`, `:313`) | launcher (`needs=DM_RUMBLE=1`) | Live-able (G1): safe |
| **Rumble cutoff** `DM_RUMBLE_MIN` (0–90 %) | Levels below it stay silent, the rest is stretched | **Next start**: `rumble_min` static (`haptics_apple.m:71`), read once (`:401-402`), used in `controller_level` (`:72-75`) | launcher | Live-able (G1): safe |
| **Frame buffering** `DM_PRESENT_SNAP` | The present copies each frame into a ring of host textures | **Next start**: `mtl_snap_on` caches its answer (`nvn_mtl.m:11689-11696`) and the ring's textures, allocators and buffers are live GPU state created on first use (`:11684-11696`, `:11786-11794`) | launcher | **Can break a game** if torn down mid-run. Next start |
| **Metal 4 pipelines** `DM_PSO_MTL4` | Builds pipelines from an archive + bases instead of per layout | **Next start**: `pso4_on` static (`nvn_mtl.m:5583-5596`); the compiler and archive are opened once (`:5782-5786`) | launcher | Needs a relaunch (archive, `MTL4Compiler`, memory). Next start |
| **Pipeline prebuild** `DM_PSO_PREBUILD` | Builds a stand-in base per shader pair, once per chain version | **Next start**: read in the background path (`nvn_mtl.m:6328`) and the prepare path (`:6612`); the work is per chain version (`:6145-6149`) | launcher | First start waits minutes. Next start only |
| **Encode thread** `DM_NVN_ENC_THREAD` | Metal encoding on a worker thread with stand-ins | **Next start**: chosen once in `nvn_rec_on` (`dm/gfx/nvn/nvn_rec.h:81-88`) and the whole recording path differs after it | launcher | **Can break a game** (encoding path). Next start |
| **Hold frames when late** `DM_FPS_HOLD` | Whether a late frame may raise the hold above the cap | **Next start today**: `fstep_hold` caches `h` (`hle_nvn.c:1732-1739`), but it is consulted per present (`:1749`), so a setter is S | launcher | Live-able (G1): safe |
| **Performance HUD** `DM_METAL_HUD` | Apple's Metal HUD layer over the game | **Live-able already**: it is a layer property set at `front_ios.m:83` (`developerHUDProperties`) | launcher + env | Safe |
| **Picture fill** `DmFillMode` / `DM_PRESENT_FILL` | Letterbox / Stretch / Crop in the present viewport | **Live**: `dm_present_set_fill` (`nvn_mtl.m:11122`), read every present (`:11132-11133`); the panel calls it (`DmGamepad.m:641-646`); the saved key is applied before the first frame (`front_ios.m:75-76`) | **menu** (env seeds it) | Safe |
| **Split when upright** `DmDualScreen` / `DM_DUAL_SCREEN` | Picture on the top half, controls on the bottom half | **Live**: the panel writes the key and relayouts (`DmGamepad.m:665-671`); `dm_split_active` is read on every layout (`:255`, `front_ios.m:106`) | **menu** (env overrides, `:250-251`) | Safe; the env precedence is the bug to fix before a launcher row (G2) |
| **On-screen controls** `DmPadHidden` | Hides every control; the touches then go to the game | **Live**: `DmGamepad.m:647-653` hides `_controls` (`:651`); a connected controller still hides it on its own (`:755`) | **menu** | Safe |
| **Pad layout** `DmPadLayout` (2D / 3D / Tap) | Which on-screen layout is drawn | **Live**: read at init (`DmGamepad.m:212-215`, Tap clamped to handheld at `:214`), stored by `nextLayout` (`:236-239`) | pill (and v1's menu row) | Safe |
| **Control positions** `DmPadOffsets` | Per-control drag offsets | **Live**: edit mode at `DmGamepad.m:654-658`, drags applied live, saved on lift (`:410-411`), reset at `:659-663` | **menu** | Safe. Offsets are not per orientation (`dualscreen.md` §0.9a). *Superseded by the layout editor: per-orientation-class sets `DmControlLayout.portrait` / `.landscape` (dualscreen.md §0.9a)* |
| **Aspect** `DM_ASPECT` | The Metal view is the whole screen instead of a centred 16:9 box | **Next start**: `static int fill` read once in `viewDidLayoutSubviews` (`front_ios.m:100-101`) | env only | **Can break a game** (picture geometry). Keep env/build-time |
| **Duo camera ratio** `DM_DUO_ASPECT` | The ratio the camera stubs substitute for 16:9 | **Next start**: written once into the page (`loader.c:247-254`); builds without a page get a constant baked into the stub (`dm/tools/patch_nso.py:1189-1195`) | env only (baked by `duo/duo.env`) | **Can break a game** (distorted world). Never a player row |
| **Thermal cap** `DM_THERMAL_CAP` | Whether a hot device is held at 30 fps | **Next start**: one-shot `on` static (`hle_nvn.c:1614-1621`); the state itself is sampled per second | env only (diagnostic) | Exposing "off" is an overheating promise. Keep env-only |
| **Motion** `DM_MOTION` / `DM_PHONE_MOTION` | Live motion sensors (controllers and the phone's gyro) | **Next start**: read once when the pad is made (`DmGamepad.m:88-91`, called at `:223`) | env only | Safe but needs a gesture to restart Core Motion. Later |
| **Shake threshold** `DM_SHAKE_G` | Acceleration above gravity that counts as a shake | **Next start**: read once in `motion_start` (`DmGamepad.m:53`) | env only | Safe; niche |
| **Controller merge** `DM_PAD_MERGE` | Every controller is player 1 instead of one player each | **Next start**: read once in `pads_start` (`DmGamepad.m:711-713`, called at `:220`) | env only | Changing player assignment mid-session would strand held inputs. Keep env |
| **Cloud saves folder** `DM_SAVE_SYNC` | The iCloud Drive folder the save is synced through | **Next start**: read at mount (`dm/host/save_sync.c:326-343`, `:474`), and the mount runs once (`:510-513`); the folder is put into the env before the first frame (`front_ios.m:78`, `CloudSaves.m:67-77`) | launcher (Cloud saves section, `Launcher.swift:20-58`) | Switching mid-run could overwrite a save. Next start |
| **Present pacing** `DM_PRESENT_LINK` / `_HZ` / `_INTERVAL` / `_LATENCY` / `_FIFO` | Display-link rate, frame latency, uncapped mode | **Next start**: link rate and latency at device init (`nvn_mtl.m:388-391`), rate/mode in `present_cfg` (`hle_nvn.c:1661-1673`), FIFO one-shot (`nvn_mtl.m:11507`) | env only | Uncapped changes game logic (`hle_nvn.c:1595-1596`). Not a player row |
| **Audio output / latency** `DM_AUDIO`, iOS I/O buffer | Silent sink vs Core Audio, callback size | **Next start**: `DM_AUDIO` read per open (`dm/host/hle_audio.c:260`); the iPhone's 5 ms buffer is set once at session setup (`front_ios.m:262-269`); the only size knob is the Mac diagnostic `DM_DBG_AU_FRAMES` (`hle_audio.c:173-174`) | no player row exists | n/a — a gap (G11) |

Three rules apply to every row above:

- **`fixed` wins.** A row whose variable an env file or the launch environment set is drawn
  disabled with the reason (`LauncherSettings.swift:49-51`, `LauncherRow.swift:13-17`). In a
  player build `main.m` refuses launcher keys from `env.txt` outright (`main.m`, the
  `DM_PLAYER_BUILD` block) and refuses diagnostic ones (`player_env.h:6-15`), so a player
  cannot lock themselves out of a row by writing a file.
- **Defaults are the game's tested ones.** A row's default comes from the profile
  (`game.py:91-180`) through `settings.py:81-120`; leaving a row at its default stores
  nothing (`LauncherSettings.swift:102`).
- **`DM_SAVED_CHOICES=0`** starts from the defaults and writes nothing (`:52`, `:102`); the
  in-game menu must honour it and keep the value for this session only.

---

## 2. The proposed menu

### 2.1 Shape and entry

The overlay of `ingamemenu.md` §3.1 stays: a transparent full-screen container with a light
scrim (tap to close) and a dark panel pinned to the trailing safe edge, over the running
game, so the player sees a frame-rate or render-scale change happen. It forwards the root
controller's orientation, status-bar and home-indicator preferences (`front_ios.m:140-145`).

One entry point, two triggers:

- **⚙** — the button that exists today (`DmGamepad.m:550-554`). It opens the menu instead of
  the small panel; the panel's five rows become rows of the menu.
- **Controller Home** — its system gesture is already disabled and the app gives it no
  function (`DmGamepad.m:707-708`), so nothing is taken from iOS.

Opening uses the suspension v1 specifies: `dm_gamepad_suspend(1)` → `[g_view reset]`
(clears every touch, `DmGamepad.m:485`), controller reads forced to zero, pad
`userInteractionEnabled = NO`. That is the only safe way to keep a held finger or stick from
driving the game behind the menu.

### 2.2 Rows, in priority order

Sections top to bottom; a section with no available row is not drawn. "Ship" says whether
the row is in the first public build.

| # | Row | Section | Control | Default (evidence) | Applies | Ship |
|---|---|---|---|---|---|---|
| 1 | **Frame rate** | This game | 30 / 60 (row only when the game offers it) | the profile's `fps_target` (`dm/games/01007EF00011E000/game.tsv`, `fps_target 60`) | live on frame-step builds, else **"next start"** badge | **v1** |
| 2 | **Render scale** | This game | slider 50–100 %, with the pixel size the launcher shows (`LauncherSettings.swift:88-96`) | `1.0` (`settings.tsv:19`) | live | **v1** |
| 3 | **Game rumble** | Controls | toggle | on (`settings.tsv:26`) | live (new setter, G7) | **v1** |
| 4 | **Picture fill** | Screen | Letterbox / Stretch / Crop | Letterbox (`DmFillMode` absent → 0, `DmGamepad.m:591-592`) | live | **v1** |
| 5 | **Split when upright** | Screen | toggle | on (`DmGamepad.m:252-253`) | live | **v1** |
| 6 | **Pad layout** | Controls | 2D / 3D / Tap (Tap only in handheld, `DmGamepad.m:214`) | the profile's `pad_layout` (`game.py:176`) | live | **v1** |
| 7 | **On-screen controls** | Controls | Show / Hide | Show (`DmGamepad.m:211`) | live | **v1** |
| 8 | **Control positions** | Controls | **Move** / **Play** + **Reset positions** | — (Move is a session toggle, `dualscreen.md` §0.9a) | live | **v1** |
| — | **Footer**: fps (`mtl_present_count`, `nvn_mtl.m:10743`), thermal state (`dm_thermal_now`, `front_ios.m:152`), the effective cap when it differs from the choice, **Reset to tested defaults**, **Done** | — | — | — | — | **v1** |

That is 8 setting rows plus a footer: one pass of work, and every row is live on the builds
that show it.

Later, in this order (each is its own small change, §4):

| Row | Why later |
|---|---|
| Touch feedback | needs a setter that allocates/frees the generator (G1) |
| Rumble strength / cutoff | needs the rumble setter plus two stored floats (G1) |
| Hold frames when late (`DM_FPS_HOLD`) | needs a file-scope atomic instead of the static (G1) |
| Upscaling (MetalFX) | needs a mode setter; the scaler rebuilds itself (G1) |
| Frame-rate counter, Performance HUD | cheap live setters, low player value (G1) |
| Frame buffering, Metal 4 pipelines, Pipeline prebuild, Encode thread | next start only; an "Advanced" section with the badge |
| Console mode, Game language, Dynamic resolution | next start only; the badge is the whole feature |
| Cloud saves folder | next start; needs the picker inside the menu (G10) |
| Controller mapping | does not exist at all (G12) |
| Audio latency | does not exist as a player choice (G11) |
| Save management (start over / export) | does not exist; highest risk (G13) |
| Per-profile presets | does not exist (G14) |

### 2.3 Row behaviour

- **The badge is computed, not guessed.** A row is drawn with "Applies at the next start"
  when `dm_setting_live_state(env)` returns 0 — i.e. on a build without a frame-step page,
  or for any row the live table does not know. The state is queried when the menu opens, so
  the player sees the truth before touching anything.
- **After a change** the row briefly states what happened: "Applied" (live) or "Saved — takes
  effect at the next start" (next start). The menu never claims a change it did not make.
- **Fixed rows** stay disabled with the launcher's wording (`LauncherRow.swift:13-17`).
- **`needs`** hides a sub-setting exactly as the launcher does (`LauncherSettings.swift:63-71`).
- **Reset to tested defaults** resets every row of *this game's* list to its default and runs
  the live path for each live row, so the picture returns to the tested look immediately.
  Like Play, it forgets the stored choices (the launcher's own rule, `:91-94` and `:102`).
- **No restart is offered.** The app cannot restart itself and the guest cannot be torn down
  and re-entered (§5), so a next-start row says so and stops there.

---

## 3. The shared model

### 3.1 Today: two stores, one screen each

| Store | Keys | Who reads it |
|---|---|---|
| Launcher rows | `launcher.<VAR>` strings in `UserDefaults` (`LauncherSettings.swift:56`, `:102`); the Mac app reads the same keys through `CFPreferences` (`dm/mac/launcher.c:126-130`) | `LauncherModel.init`, `apply`, `applySaved`; the Mac launcher |
| Panel choices | `DmFillMode`, `DmDualScreen`, `DmPadHidden`, `DmPadOffsets`, `DmPadLayout` (`DmGamepad.m:129-131`, `:559-560`) | `DmGamepad` only |

The two sets never meet: the launcher cannot set fill / split / controls, and the panel
cannot set a single launcher row.

### 3.2 The type to add: `SettingsStore`

In **`dm/ios/Sources/LauncherSettings.swift`** (Foundation only — the Mac target compiles
this file, `dm/mac/Launcher.swift:1-6`, and `dm/ios/tests/test_launcher_storage.py:30`
builds it):

```swift
/// One game's settings: what the rows are, what is fixed, and the one place a choice is
/// read and written. Shared by the launcher and the in-game menu, so both see the same value
/// and write the same key.
final class SettingsStore {
    let settings: [Setting]
    let fixed: Set<String>        // env file / launch environment: shown, never changed
    let fromLaunch: Set<String>
    let ignoreSaved: Bool         // DM_SAVED_CHOICES=0: defaults, and write nothing
    private let defaults: UserDefaults
    init(_ settings: [Setting], defaults: UserDefaults = .standard)

    /// The value in force now: the environment (what the launcher applied this run, or an
    /// env file) first, then the saved choice, then the game's default.
    func current(_ s: Setting) -> String
    /// Store one choice exactly as Play does: a default removes the key, a change writes
    /// `launcher.<env>`, a fixed row and DM_SAVED_CHOICES=0 write nothing. Returns false
    /// when nothing was written.
    @discardableResult func store(_ s: Setting, _ v: String) -> Bool
    /// The default value, without writing (the menu's Reset shows it; the live path applies it).
    func defaultValue(_ s: Setting) -> String
    var changed: Bool
}
```

`LauncherModel` keeps its published `values` and delegates: `init` fills `values` from
`store.current` for non-fixed rows and from the environment for fixed ones (today's
`LauncherSettings.swift:54-58`); `apply()` calls `store.store` then `setenv`, which is
exactly today's rule at `:101-103`; `applySaved()` and `reset()` are unchanged. The Mac
window therefore keeps working with no code change, and `launcher_storage_check.swift`
keeps passing (its cases are the store's contract).

### 3.3 The menu's model: `InGameMenuModel`

In **`dm/ios/Sources/InGameMenu.swift`** (new, iOS only: it needs UIKit, SwiftUI and C):

```swift
final class InGameMenuModel: ObservableObject {
    let store: SettingsStore          // made once, on first open
    @Published var values: [String: String]
    @Published var pending: Set<String>   // rows whose value waits for the next start

    enum Applied { case live, nextStart, refused }

    func commit(_ s: Setting, _ v: String) -> Applied {
        guard !store.fixed.contains(s.env) else { return .refused }
        let stored = store.store(s, v)                 // persistence first, as Play does
        if dm_setting_live(s.env, v) != 0 {            // a NULL value only asks
            pending.remove(s.env); return .live
        }
        if stored { pending.insert(s.env) }
        return .nextStart
    }
    func resetAll()                                    // default value → commit() for each row
    func liveState(_ s: Setting) -> Bool               // dm_setting_live_state(s.env) != 0
}
```

The model is created lazily from the bundle's `dm/launcher.json` — the same file
`dm_show_launcher` decodes (`Launcher.swift:169-170`) — and kept in a `static` so values
survive closing and reopening, including under `DM_SAVED_CHOICES=0`.

### 3.4 The live bridge: `dm_setting_live` and the state page

New **`dm/ios/Sources/settings_live.m`** (iOS only; `project.yml` takes the whole folder and
`dm/ios/tools/compile_check.py` globs `*.m`, so no project edit):

```c
// 1 = the change is in effect now; 0 = it needs the next start (or is unknown here).
// A NULL value only asks: no side effect.
int dm_setting_live(const char *env, const char *value);
int dm_setting_live_state(const char *env);
```

The table for v1:

| `env` | Live path |
|---|---|
| `DM_FPS_TARGET` | `dm_fps_state_set_fps(atoi(v))`; 0 when `dm_fps_state == NULL` (`hle.h:63`) |
| `DM_RENDER_SCALE` | `dm_fps_state_set_scale(strtof(v))` |
| `DM_RUMBLE` | `dm_haptics_apple_set(...)` (G7), which re-runs `dm_haptics_init` (`haptics_apple.m:404`) |
| `DM_PRESENT_FILL` | `dm_present_set_fill(atoi(v))` (`nvn_mtl.m:11122`) |
| `DM_DUAL_SCREEN` | `dm_dual_set(atoi(v))` (G2) |
| `DM_PAD_LAYOUT` | `dm_gamepad_set_layout(atoi(v))` (G4) |
| `DM_PAD_HIDDEN` | `dm_gamepad_set_hidden(atoi(v))` (G4) |

In **`dm/host/loader.c`** + **`dm/host/hle.h`**, split the one-shot `dm_fps_state_apply`
(`loader.c:234-258`) into three stores:

```c
void dm_fps_state_set_fps(int fps);      // 32-bit store at +0x00
void dm_fps_state_set_scale(float s);    // +0x10
void dm_fps_state_set_aspect(float r);   // +0x40
```

`dm_fps_state_apply()` keeps reading the environment and calls them, so boot behaviour is
bit-identical. Only 32-bit aligned stores ever touch the page; the 64-bit fields are not
written by the setters.

**No `setenv` on the live path.** POSIX does not promise a thread-safe `setenv`, and the host
calls `getenv` from the present thread, the audio thread and the guest thread
(`hle_nvn.c:1649`, `hle_audio.c:260` via `real_audio`, `hle_oe.c:256`). The environment stays
the launch-time record written by `apply()`; a run-time change goes through an explicit setter
and the state page, and persistence goes through `UserDefaults`.

### 3.5 Persistence: one key format for every player choice

Every scalar player choice becomes a `launcher.<VAR>` string. The four panel choices get
catalogue rows (`dm/games/settings.tsv`) so they exist in `dm/launcher.json`, in the
launcher's UI and in the menu with no extra code:

| Row | Line to add | Live path |
|---|---|---|
| `DM_PRESENT_FILL` | `choice 0=Letterbox,1=Stretch,2=Crop`, default `0`, `always` | `dm_present_set_fill` |
| `DM_DUAL_SCREEN` | `toggle -`, default `1`, `always` | `dm_dual_set` |
| `DM_PAD_LAYOUT` | `choice 0=2D,1=3D,2=Tap`, default `DM_GAME_PAD_LAYOUT` (`game.py:176`) | `dm_gamepad_set_layout` |
| `DM_PAD_HIDDEN` | `toggle -`, default `0`, `always` | `dm_gamepad_set_hidden` |

- **Migration, once, in `main.m`'s boot (before the launcher reads anything):** if
  `launcher.DM_PRESENT_FILL` is absent and `DmFillMode` exists, copy it; same for
  `DmDualScreen` → `launcher.DM_DUAL_SCREEN`, `DmPadLayout` → `launcher.DM_PAD_LAYOUT`,
  `DmPadHidden` → `launcher.DM_PAD_HIDDEN`. Then delete the old keys; nothing reads them
  afterwards.
- **`DmPadOffsets` stays as it is.** It is a `key → [x, y]` map, not a scalar row
  (`DmGamepad.m:400-411`); it has no env equivalent and no place in a `choice/range/toggle`
  model. It keeps its own key and its own Reset button.

### 3.6 How the two screens then agree

| Direction | Mechanism |
|---|---|
| Launcher → menu | The menu is created after Play; `SettingsStore.current` prefers `getenv`, which `apply()` just set, so a choice the launcher made this run is what the menu shows — even when it equals the default and was therefore not stored. |
| Menu → launcher | `store()` writes `launcher.<VAR>`, which `LauncherModel.init` reads at the next launch (`LauncherSettings.swift:56`) and the Mac launcher reads through `CFPreferences` (`dm/mac/launcher.c:126`). |
| Either → reset | One `changed` / `defaultValue` definition, so "Reset to tested defaults" means the same thing on both screens. |
| Fixed rows | One `fixed` set, built from `DM_ENV_FILE_KEYS` / `DM_ENV_LAUNCH_KEYS` (`LauncherSettings.swift:50-51`), so a locked row is locked in both places. |

### 3.7 File-by-file

| File | Change |
|---|---|
| `dm/ios/Sources/LauncherSettings.swift` | add `SettingsStore`; `LauncherModel` delegates to it (`init`, `apply`, `reset`, `changed`) |
| `dm/ios/Sources/InGameMenu.swift` **(new, iOS)** | `InGameMenuModel`, the SwiftUI view/controller, `@_cdecl("dm_ingame_menu_present")` returning false when the app has no `dm/launcher.json` |
| `dm/ios/Sources/settings_live.m` **(new, iOS)** | the two functions and the table |
| `dm/host/loader.c`, `dm/host/hle.h` | the three state-page setters; `dm_fps_state_apply` calls them |
| `dm/ios/Sources/DmGamepad.m` | `dm_gamepad_set_layout`, `dm_gamepad_set_hidden`, `dm_gamepad_suspend`; the ⚙ opens the menu; Home opens it; the four panel values come from the store instead of `NSUserDefaults` |
| `dm/ios/Sources/front_ios.m` | present/close the overlay, suspend and resume the pad, declare the new C functions |
| `dm/ios/Sources/main.m` | the one-time key migration |
| `dm/ios/Sources/DmIOS-Bridging-Header.h` | declare `dm_present_set_fill`, `dm_setting_live`, `dm_setting_live_state`, `mtl_present_count`, `dm_thermal_now`, `dm_gamepad_set_layout`, `dm_gamepad_set_hidden` |
| `dm/games/settings.tsv` | the four rows of §3.5 |
| `dm/host/haptics_apple.m`, `.h` | `dm_haptics_apple_set(int on, float gain, float min)` (G7) |
| `docs/settings.md`, `docs/frontends.md`, `docs/launcher.schema.json` | the four new rows and "a choice can be changed in game" |

---

## 4. Gaps to close in the baseline app

Ordered so that each step is usable on its own. S ≈ a day, M ≈ a few days, L ≈ a week or
more. "Risk" is the chance of breaking a shipped game.

| # | Gap | Size | Risk | Unblocks |
|---|---|---|---|---|
| **G1** | The live table plus setters for the six cached statics: `DM_FPS_HOLD` (`hle_nvn.c:1732-1739`), `DM_PRESENT_UPSCALE` (`nvn_mtl.m:11187-11196`), rumble gain/cutoff (`haptics_apple.m:44`, `:71`), touch feedback (`DmGamepad.m:186-189`), fps label (`front_ios.m:168-180`), HUD (`front_ios.m:83`). One `_Atomic` per value; every read stays where it is | M | Low, except upscaling (scaler rebuild = one hitch) | rows 1–3 and every later live row |
| **G2** | Split becomes runtime state: `static _Atomic int` seeded once from `DM_DUAL_SCREEN` at first use, `dm_dual_set(int)` to change it; `dm_split_enabled()` stops consulting `getenv` per call (`DmGamepad.m:249-254`) | S | Low; `dualscreen.md` §0.9's env test still passes because the env seeds the state | a launcher row for split; the menu switch keeps working when the env is set |
| **G3** | One persistence for fill: `DM_PRESENT_FILL` row, `launcher.DM_PRESENT_FILL`, `DmFillMode` migrated and removed (`front_ios.m:75-76` reads the store) | S | Low | the launcher can set fill; one source of truth |
| **G4** | `dm_gamepad_set_layout(int)` (the body of `nextLayout`, `DmGamepad.m:236-239`), `dm_gamepad_set_hidden(int)`, `dm_gamepad_suspend(int)`, and the Home handler | S | Low | rows 6–8 in the menu without the pill |
| **G5** | The overlay: `InGameMenuController`, the scrim/panel, the badge, the footer; rebuild the panel when the row set changes (today it is built once and only toggled, `DmGamepad.m:570-571`, at a fixed 300×286 u, `:554`) | M | Low (one extra composited layer) | the menu itself |
| **G6** | Capability answers to the UI: `dm_setting_live_state` for every row, plus a reachable flag for "this build has a frame-step page" (`dm_fps_state != NULL`, `hle.h:63`) | S | Low | honest badges instead of optimistic ones |
| **G7** | `dm_haptics_apple_set(int on, float gain, float min)`: move the three env reads of `dm_haptics_apple_init` (`:394-405`) into a helper the setter also calls; gain/min are plain floats on the rumble queue; `dm_haptics_init` is already safe to re-call (`hle_haptics.c:26-32`) | S | Low | the v1 rumble row and the later strength/cutoff rows |
| **G8** | Launcher rows for the screen/controls section, after G2/G3: `DM_PRESENT_FILL`, `DM_DUAL_SCREEN`, `DM_PAD_LAYOUT`, `DM_PAD_HIDDEN` | S | Low | a player who never opens the menu can set the Duo layout before starting |
| **G9** | A way out of a "next start": quit-to-launcher or a clean guest restart. `dm_main` runs the guest and never returns (`main.c:142-144`), so this means tearing down the host | L | High (save flush, GPU teardown, audio session) | next-start rows become actionable; also the only honest "restart" button |
| **G10** | Cloud saves from the menu: call `dm_cloud_saves_env()` and remount, or mark it next start and offer the picker. Today `DM_SAVE_SYNC` is read at the first mount only (`save_sync.c:474`, `:510-513`) | M | Medium (a mis-timed remount can overwrite a save) | the one save-related choice a player misses mid-game |
| **G11** | An audio latency row. The iPhone fixes 5 ms (`front_ios.m:262-269`); the only size knob is the Mac diagnostic `DM_DBG_AU_FRAMES` (`hle_audio.c:173-174`), and the docs record crackling at larger sizes | M | Medium (crackling, dropouts) | a real player complaint (Bluetooth audio latency) |
| **G12** | Controller remapping. Physical pads map by position, Nintendo pads by label (`DmGamepad.m:694-706`); there is no per-player remap and no UI | L | Medium | accessibility, and non-standard pads |
| **G13** | Save management: delete a save, start over, export. Nothing exists beyond Cloud saves and the test switches `DM_TEST_KILL_AT` / `DM_TEST_FS_FAIL*` | M | High (irreversible) | a common request; ship behind a confirmation, not in v1 |
| **G14** | Per-profile presets (e.g. "60 fps docked", "battery"): a named bundle of row values. Nothing exists; the store holds one value per row | L | Low | a one-tap quality choice without hiding which values changed |

---

## 5. Explicitly rejected

1. **`setenv` at run time.** Not thread-safe by POSIX, and the host reads the environment
   from the present, audio and guest threads (`hle_nvn.c:1649`, `hle_oe.c:256`,
   `hle_audio.c:260`). Live changes go through setters and the state page.
2. **Restarting the app from the menu.** iOS has no supported self-restart, and killing the
   process loses the unsaved session; the save flush lives on the exit path
   (`save_sync.h:1-4`). A row that needs a relaunch says so instead.
3. **Going back to the launcher in game.** `front_run(guest_main)` never returns
   (`main.c:142-144`); re-entering means a full teardown of the guest, GPU and audio. That
   is G9, not a menu feature.
4. **Live console mode (`DM_OPMODE`).** The host can push notification 30 (`hle_oe.c:51-56`),
   but the resolution change event is never signaled (`:164-165`), so a game that sized its
   render targets at boot keeps them — the picture breaks. Next start.
5. **Live game language (`DM_LANG`).** No notification path, and fonts/string tables are
   built at boot (`hle_oe.c:255-259`). Next start.
6. **Live pipeline, thread and ring switches** (`DM_PSO_MTL4`, `DM_PSO_PREBUILD`,
   `DM_NVN_ENC_THREAD`, `DM_PRESENT_SNAP`). Each constructs a compiler/archive, a worker
   thread or a texture ring at first use (`nvn_mtl.m:5782-5786`, `:6145`, `nvn_rec.h:81-88`,
   `:11786-11794`); toggling means tearing that down mid-frame. Next start, with the badge.
7. **Live frame buffering (`DM_PRESENT_SNAP`).** Same reason, and the latency it adds is the
   point of the setting; a mid-run switch changes both memory and feel at once.
8. **A frame-generation / interpolation row.** Nothing in the host interpolates frames, and
   a generated frame would misrepresent the game's own timing (which the frame step and the
   fps counter both report). Out of scope until there is a design.
9. **A "quality preset" slider (Low / Medium / High).** It hides *which* switch moved, so a
   bug report stops being reproducible, and the tested defaults (`game.tsv`) are chosen per
   game precisely because a bundle that is right for one game is wrong for another.
10. **Exposing diagnostics as player rows** (`DM_NVN_*`, `DM_TEST_*`, `DM_THERMAL_CAP=0`,
    present pacing). They change rendering semantics or remove safety nets (the thermal cap
    at `hle_nvn.c:1621-1634`); a player build already refuses them from `env.txt`
    (`player_env.h:6-15`). They stay in `Documents/env.txt` for support.
11. **An uncapped frame rate / `DM_PRESENT_HZ` row.** The host's own comment records that the
    game's UI logic counts frames (`hle_nvn.c:1595-1596`); uncapped is a profiling mode.
12. **Per-orientation control offsets.** Tempting (`dualscreen.md` §0.9a: a landscape drag
    carries into split), but it doubles the key format (`DmPadOffsets` per orientation) for a
    problem Reset already solves. Deferred, not rejected forever. *Done since: the layout editor keeps one set per
    orientation class (dualscreen.md §0.9a).*

---

## 6. Decisions needed

| # | Question | Recommendation |
|---|---|---|
| 1 | Does the existing **⚙** button become the menu, or does v1's `≡` pill stay as a second opener? | **⚙ becomes the menu**; no second pill. One button, one behaviour, and the pill would take a touch region from the game. |
| 2 | Is **Game rumble** in the first public menu (it costs one new haptics setter, G7)? | **Yes.** It is the change players reach for mid-session, and the setter is S with a low-risk re-init path. |
| 3 | Do **Picture fill / Split when upright / Pad layout / Show-hide controls** become `settings.tsv` rows (visible in the launcher too)? | **Yes**, rows — otherwise the shared model is cosmetic. It needs G2/G3 first, plus `docs/settings.md`, `docs/frontends.md` and `docs/launcher.schema.json` in the same change. |
| 4 | What does **Reset to tested defaults** in the menu do to *stored* choices? | **Same as Play**: reset the values and forget the stored choices, so the build's tested defaults come back. Keeping them would make a reset that does not survive the session look broken. |
| 5 | May the controller's **Home** button open the menu? | **Yes.** Its system gesture is already disabled and the app gives it no function (`DmGamepad.m:707-708`); nothing is taken from iOS. |

---

## 7. As built — 2026-10-30 (v1)

> **Superseded in part, 2026-10-30 (v2): the menu is catalogue-driven.** The 8-row hand-written list described below is gone;
> the menu now draws every row of the app's `dm/launcher.json` — the same rows, sections and order as the launch screen —
> through `SettingsGrouping` (`dm/ios/Sources/LauncherSettings.swift`), with a search field, a per-section Reset, a badge and
> a description on every row, and two more live rows (`DM_TOUCH_HAPTICS`, `DM_METAL_HUD`). The design, the per-setting
> live/next-start evidence, the duplicate audit and the catalogue additions are in **[`settings-ui.md`](settings-ui.md)**
> (§1 inventory, §3 the two screens, §4 duplicates, §5 live changes). The overlay's shape, the store rules and the
> live/next-start honesty described in this section still hold; only the row model and the live table grew.

Built and checked without Xcode or a device: `dm/ios/tools/compile_check.py` (ObjC **and**, new, the Swift files
typechecked together against the iPhone SDK), `dm/ios/tests/test_launcher_storage.py` (compiles and runs the real
`LauncherSettings.swift` + `LauncherRow.swift` + the Mac window on macOS), `dm/tools/tests/test_launcher_settings.py`,
`dm/tools/tests/test_settings.py`, `dm/tools/env_switches.py --check`, and the host tests `t_fpslock`,
`t_resolution`, `t_haptics`, `t_haptics_apple`, `t_symbols`, `t_oe`. **Nothing was run on a phone**: the overlay's
look, the Home button and the live rows are compiled, not observed.

### 7.1 What shipped

| Piece | Where |
|---|---|
| `SettingsStore`: `current` / `applied` / `store` / `defaultValue` / `static rangeLabel`; `LauncherModel` keeps its `values`, delegates `init` and `apply()` (one `store.store` call per row) and `rangeLabel` | `dm/ios/Sources/LauncherSettings.swift:37-91`, `:93-165` |
| **v1, replaced in v2** — `InGameMenuModel` now draws *every* row of `dm/launcher.json` through `SettingsGrouping`, with a search field and a per-section Reset ([`settings-ui.md`](settings-ui.md) §3). `commit` (persist → live → "Applied" / "Saved · takes effect at the next start"), `resetAll`, Control positions state remain | `dm/ios/Sources/InGameMenu.swift:28-116` |
| The overlay: scrim (tap closes) + dark panel on the trailing edge, `Choice` / `Range` / `Toggle` rows with the badge, footer (fps sampled from `mtl_present_count`, thermal state, the 30 fps thermal hold, Reset, Done), ✕-free — the panel never hides the game | `dm/ios/Sources/InGameMenu.swift:119-284` |
| `dm_ingame_menu_present` (present / close), `dm_setting_commit` (the layout pill's one path into the same store), `MenuHost` (root controller's orientation / status bar / home indicator / edge gestures; `dm_gamepad_suspend(1)` on appear, `(0)` on disappear) | `dm/ios/Sources/InGameMenu.swift:287-341` |
| `dm_setting_live(env, value)` and `dm_setting_live_state(env)` = `dm_setting_live(env, NULL)`; the v1 table was `DM_FPS_TARGET`, `DM_RENDER_SCALE`, `DM_RUMBLE`, `DM_PRESENT_FILL`, `DM_DUAL_SCREEN`, `DM_PAD_LAYOUT`, `DM_PAD_HIDDEN`; v2 adds `DM_TOUCH_HAPTICS` and `DM_METAL_HUD` ([`settings-ui.md`](settings-ui.md) §5); everything else answers 0 (next start). No `setenv` anywhere on this path | `dm/ios/Sources/settings_live.m:37-81` |
| The state page split into `dm_fps_state_set_fps` (+0x00), `dm_fps_state_set_scale` (+0x10), `dm_fps_state_set_aspect` (+0x40); `dm_fps_state_apply` reads the environment and calls the three, so boot bytes are unchanged | `dm/host/loader.c:232-273`, `dm/host/hle.h:63-68` |
| `dm_haptics_apple_set(on, gain, min)` (NaN keeps gain / min; the values are written on the rumble queue; `dm_haptics_init` re-run, which clears every motor) and `dm_haptics_apple_ready()`; the env reads moved into `env_values`, which init also calls | `dm/host/haptics_apple.m:76-83`, `:394-447`, `dm/host/haptics_apple.h:8-12` |
| Split is runtime state: `static _Atomic int g_dual`, seeded once from `DM_DUAL_SCREEN` in `dm_split_enabled`, changed by `dm_dual_set` (relayouts). The env no longer overrides the saved choice on every call (G2) | `dm/ios/Sources/DmGamepad.m:262-286` |
| Pad switches: `dm_gamepad_ready`, `_set_layout` (through `-switchToLayout:`), `_set_hidden`, `_set_editing`, `_reset_offsets`, `_editing`, `_suspend` (releases every touch, `userInteractionEnabled = NO`, controller reads forced to zero by `g_suspended` in `read_pad`) | `dm/ios/Sources/DmGamepad.m:637-750` |
| ⚙ opens the menu (the panel, its segments and its four saved keys are **deleted**); Home opens / closes it (`GCInputButtonHome.pressedChangedHandler`) | `dm/ios/Sources/DmGamepad.m:584-594`, `:651-657` |
| The pad reads its layout and hidden state from `DM_PAD_LAYOUT` / `DM_PAD_HIDDEN`, which Play set; the layout pill stores through `dm_setting_commit` instead of writing `DmPadLayout` itself | `dm/ios/Sources/DmGamepad.m:215-222`, `:248-255` |
| One-time migration `DmFillMode` → `launcher.DM_PRESENT_FILL`, `DmDualScreen` → `launcher.DM_DUAL_SCREEN`, `DmPadLayout` → `launcher.DM_PAD_LAYOUT`, `DmPadHidden` → `launcher.DM_PAD_HIDDEN`; the old key is deleted, so it runs once | `dm/ios/Sources/main.m:93-114`, called at `:130` |
| `front_ios.m` no longer reads `DmFillMode`; the saved fill arrives as `DM_PRESENT_FILL` and seeds the present pass | `dm/ios/Sources/front_ios.m:73-75`, `dm/gfx/nvn/nvn_mtl.m:11122-11129` |
| The four catalogue rows, with a new `Screen` section (schema 1 allows a new section; `settings.py`'s `SECTIONS` grew): `DM_PRESENT_FILL` (choice 0/1/2, default 0, both platforms), `DM_DUAL_SCREEN` (toggle, default 1, iOS), `DM_PAD_LAYOUT` (choice 0/1/2, default `DM_GAME_PAD_LAYOUT`, iOS), `DM_PAD_HIDDEN` (toggle, default 0, iOS) — so the launcher shows them too (G8) | `dm/games/settings.tsv:25-34`, `dm/games/settings.py:13` |
| The Swift bridge | `dm/ios/Sources/DmIOS-Bridging-Header.h` |
| The compile check now typechecks the Swift files | `dm/ios/tools/compile_check.py:42-50` |

The launcher's behaviour is unchanged: same `launcher.<VAR>` keys, same "a default stores nothing", same Reset rule,
same log lines. `launcher_storage_check.swift` gained store-level cases (`current` vs `applied`, write, default
removes, the shared range label) and still passes.

### 7.2 Corrections to this note, found while reading the code

1. **§3.2's one `current` accessor cannot serve both screens.** The launcher's `init` must *not* prefer a value
   that something put in the environment for a non-fixed row — `launcher_storage_check.swift` pins that ("a saved
   value that is not a string is ignored", "a saved choice goes into the environment and stays saved"). So the store
   has two reads: `current` (the launcher's rule: fixed → env, else saved → default) and `applied` (the value in force
   this run: the environment Play wrote first). The menu uses `applied`.
2. **No `SettingsStore.changed`.** The launcher's `changed` is about the *screen's* unsaved values, so it cannot
   delegate to a store that has never seen them; the menu computes its own from `values`. A store-level `changed`
   would have been dead code.
3. **`dm_haptics_init` is called with `!e || atoi(e) != 0`, not with a variable named `on`** (§1 cites `:404`).
   `dm_haptics_apple_set` passes `on != 0`, which is the same rule for the value the menu sends.
4. **The overlay is presented from `InGameMenu.swift`, not from `front_ios.m`** (§3.7). `front_ios.m` only lost its
   `DmFillMode` read; the menu finds the key window itself.
5. **`DM_DUAL_SCREEN`'s catalogue default is 1, not 0.** `dualscreen.md` §4.1 proposed 0; the code has defaulted to
   on since the panel shipped (`dm_split_enabled`), and a row whose default flipped would change every player's
   picture on update. The row is 1 and `dm_split_enabled` keeps 1 as its own default.
6. **The footer's "effective cap" is the thermal rule only.** `fps_step_cap()`/`thermal_capped()` are file-static in
   `dm/gfx` and this change was not allowed to add a getter there, so the footer states the 30 fps hold when
   `dm_thermal_now() >= 2` (exactly `thermal_capped`'s threshold) and does not claim to know the movie case.
7. **The menu's Control positions row needed two more exports than G4 lists** — `dm_gamepad_set_editing`,
   `dm_gamepad_reset_offsets` — plus `dm_gamepad_editing` so the Move / Play switch is the pad's own state and not a
   memory that goes stale when the menu is closed. `dm_gamepad_ready` and `dm_haptics_apple_ready` exist so a
   badge is never optimistic.

### 7.3 Gaps: what is still open

| # | State |
|---|---|
| **G1** | **Partly open.** Shipped: the rumble setter. Still open: `DM_FPS_HOLD`, `DM_PRESENT_UPSCALE`, rumble strength / cutoff rows, touch feedback, the frame-rate counter and the Performance HUD as live setters |
| **G2** | **Closed** (`DmGamepad.m:262-286`) |
| **G3** | **Closed** (`settings.tsv:27`, `main.m:93-114`, `front_ios.m:73`) |
| **G4** | **Closed**, plus the edit / reset / ready exports above (`DmGamepad.m:709-750`) |
| **G5** | **Closed** (`InGameMenu.swift:119-284`) |
| **G6** | **Closed** (`settings_live.m:81`) |
| **G7** | **Closed** (`haptics_apple.m:436-447`) |
| **G8** | **Closed** (`settings.tsv:25-34`, `settings.py:13`) |
| **G9** | **Open.** A next-start row still says so and stops; there is no quit-to-launcher and no clean guest restart |
| **G10** | **Open.** Cloud saves are still chosen in the launcher only |
| **G11** | **Open.** No audio latency row |
| **G12** | **Open.** No controller remapping |
| **G13** | **Open.** No save management |
| **G14** | **Open.** No per-profile presets |

Smaller, discovered while building:

- **The menu has no restart of its own**, so a row that needs the next start is only a label (G9).
- **`SettingsStore` needs `dm/launcher.json`.** An app built without it (no settings list at all) has no menu — the ⚙
  does nothing — and the layout pill falls back to switching without storing. That is the same precondition
  `dm_show_launcher` has.
- **The Control positions offsets stay one map** (`DmPadOffsets`), not per orientation: a drag made in landscape
  carries into split (dualscreen.md §0.9a), unchanged by this work.
- **The scrim is 30 % black**, so the frame-rate and render-scale changes are visible but dimmed; a "compare" mode
  (split before/after) is not built.
