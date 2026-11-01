# Frame generation and 120 Hz on the Duo

Scope: presentation rates above 60 Hz for the games this fork supports, and whether MetalFX
frame interpolation is a route to them. First target: **Scott Pilgrim vs The World: The Game**
(`0100394011C30000`), a 60 fps-capped 2D game on a 120 Hz panel.

Everything below is read from this tree or from the reference project at
`~/dev/GAMING-DEV/macnativegames` (MacNativeGames). Nothing here has run on the Duo: there is no
device in this repo's history yet (`duo/README.md`, "Status"), and no frame-generation code exists
in this tree — `grep -rn mfx dm/` finds nothing outside shader names and an app icon.

## Verdict first

| | Option | Verdict |
|---|---|---|
| (a) | MetalFX frame interpolation | **Not for this title.** Its motion-vector input is a per-pixel field this renderer cannot produce correctly: the reference's only working method is camera reprojection from depth, which is wrong for content that moves independently of the camera — and in a 2D brawler *all* moving content is that. |
| (b) | Duplicate-frame 120 Hz presentation | **Reject.** It shows the same pictures twice: no change in motion, blur or latency, and it doubles present GPU work. The one real benefit of a 120 Hz link (an 8.33 ms grid for late frames) is already there for free with `DM_PRESENT_LINK=2`. |
| (c) | Unlock the game's own frame cap | **Recommended**, staged, behind one measurement. The mechanism already exists for 12 games (`dm/host/hle_fpslock.c`), the 120 Hz link already exists (mode 2), and the fix also repairs the 60 fps case (the Mac run's p99 33.8 ms / 56.9 fps is the signature of two pacers in series). |

The recommendation is conditional on one thing that is **not yet known**: whether the engine's
simulation steps by real time or by frame count. §6 says exactly how to find out before writing any
of it, and what to do if the answer is "frame count".

---

## 1. What exists today

### 1.1 The present path

One `nvnQueuePresentTexture` → one enqueue → **one drawable present**. There is no path anywhere
that shows a game frame twice, and no path that synthesises a picture.

| Piece | Where |
|---|---|
| Enqueue (game thread, returns at once) | `dm/gfx/nvn/nvn_mtl.m:11763` (`present_enqueue`) |
| Present thread / display-link callback takes one frame per tick | `dm/gfx/nvn/nvn_mtl.m:11470` (callback), `:11498-11502` (one frame per tick) |
| Present pass on the Metal 4 queue | `dm/gfx/nvn/nvn_mtl.m:11242-11269` (`present_encode_m4`), commit at `:11399`, drawable at `:11415` |
| Classic-queue present pass (GL/Vulkan layers) | `dm/gfx/nvn/nvn_mtl.m:11144-11171` (`present_encode`) |
| Minimum time on screen | `dm/gfx/nvn/nvn_mtl.m:11427` (`presentAfterMinimumDuration:period`) |
| MetalFX **spatial** upscale in the present (`DM_PRESENT_UPSCALE`) | `dm/gfx/nvn/nvn_mtl.m:11173-11238`; the scaler needs Metal 4 (`:11188`) |

So the present path is already a Metal 4 consumer with a full-screen blit and a MetalFX spatial
scaler — the same queue and resource model a Metal 4 frame interpolator would use. What is missing
is not plumbing, it is pictures.

### 1.2 The rates it can actually reach

The display link has three modes (`dm/gfx/nvn/nvn_mtl.m:116`, default 1 at `:389`):
0 = take the drawable ourselves, 1 = 60 Hz link, 2 = 120 Hz link, 3 = 30 Hz power save.
The range per mode is `link_range` (`dm/gfx/nvn/nvn_mtl.m:11534-11547`): `(60,60,60)`,
`(60,120,120)`, `(30,30,30)`.

Two rules decide the effective rate:

1. **Ticks per frame.** `mtl_link_wait_tick` multiplies the game's present interval by 2 on a
   120 Hz link (`dm/gfx/nvn/nvn_mtl.m:11853-11866`; `mtl_link_rate` at `:11869`). A game that asks
   for interval 1 therefore still waits two 8.33 ms ticks — **16.7 ms, i.e. 60 fps**.
2. **The cap.** `present_itv` (`dm/gfx/nvn/hle_nvn.c:1675`) and `present_period` (`:1691-1700`)
   derive the period from `g_hz`, which is 60 unless `DM_PRESENT_HZ` says otherwise
   (`:1661-1674`), and from a cap that can only be 30 or 60 (`fps_present_cap`,
   `dm/gfx/nvn/hle_nvn.c:1648-1655`; `mtl_fps_target`, `dm/gfx/nvn/nvn_mtl.m:10397-10398`;
   `nvn_game_fps`, `dm/gfx/nvn/hle_nvn.c:1660`; the profile key is validated to `0/30/60` in
   `dm/games/game.py:98-99`).

Consequences, as the code stands:

| Setting | Game frames/s ceiling | Notes |
|---|---|---|
| default (`DM_PRESENT_LINK=1`, profile `present_interval game`) | 60 | one tick per frame |
| `DM_PRESENT_LINK=2` | 60 | 120 Hz link, but 2 ticks per frame (`nvn_mtl.m:11853-11866`); a late frame lands on the next **8.33 ms** tick instead of the next 16.7 ms one — this is the free win |
| `DM_PRESENT_LINK=3` | 30 | power save (`link_sync`, `nvn_mtl.m:11580`) |
| `DM_PRESENT_INTERVAL=display DM_PRESENT_HZ=120 DM_PRESENT_LINK=2` | **120** | `link_wait` takes the `hz > 60` path (`dm/gfx/nvn/hle_nvn.c:1679-1690`) and waits 1 tick per frame; documented as a *cut* — the game's own interval is ignored (`dm/gfx/nvn/hle_nvn.c:1667-1671`) |

The last row is the important one for this ticket: **the host can already present at 120 Hz**; it
is reachable only through three environment switches and only by overriding the game's interval.
Nothing in the profile/cap path can say "120".

Two facts about the device side:
- The iOS layer is a `CAMetalLayer` at native scale (`dm/ios/Sources/front_ios.m:31-45`) and the
  app opts into high refresh with `CADisableMinimumFrameDurationOnPhone` (`dm/ios/Gen/Info.plist:5-6`).
- `mtl_display_hz()` reads `UIScreen.mainScreen.maximumFramesPerSecond` on iOS
  (`dm/gfx/nvn/nvn_mtl.m:11065-11073`), but `front_screen_max_fps()` is a weak stub on iOS
  (`:11531`), so the virtual-tick path in `link_range` never applies there — mode 2 is exactly
  120 Hz, which is what we want.

### 1.3 Scott Pilgrim as the target

| Fact | Evidence |
|---|---|
| 2D sprite renderer, not a 3D scene | The four named programs are `mvppos2_col_tex2.vs` (MVP-transformed positions), `screenpos2_col_tex2.vs` (screen-space quads), `color_tex0.ps` and `color_movie.ps` — a sprite batcher plus a screen-space blitter. The other 30 rows in `dm/games/0100394011C30000/shader_map.tsv` are unnamed hashes inside `main`, so no G-buffer or deferred pass can be ruled out from the names alone (see §7.2) |
| 14 draws per frame, ~20,318 translated instructions per draw | `duo/games/0100394011C30000.md:26` |
| Runs at ~57 fps with p50 16.67 ms, p99 33.82 ms on the Mac | same file, `:23-25` (p50, CPU) and `:35-36` (p99, presents/s) |
| Profile today: `present_interval game`, `fps_target 0`, no present snapshots | `dm/host/gen/0100394011C30000/game_profile.h:20,23,26` |
| The game does resolve `nvnWindowSetPresentInterval` and `nvnWindowBuilderSetPresentInterval` by name | strings at `main+0x1320402` / `main+0x131e4f2` in the extracted NSO (build `8b939dc403aa7e4817de4f646ff72d86`, the profile's build) |
| Any interval change it makes is logged | `dm/gfx/nvn/hle_nvn.c:1295` (`the game sets present interval %d → %d`) |

`p99 33.82 ms` with `p50 16.67` and CPU at 10 % is not a frame that is too slow — most likely two
pacers in series (inference, decided by §6.2): the game's own 60 Hz wait, then the host's vsync wait. The same signature, and the same
fix, is documented for Luigi's Mansion 3 in `dm/host/hle_fpslock.c:14-17` ("p99 18.69 → 16.67 ms,
60.0 fps").

---

## 2. MetalFX frame interpolation: what the SDK requires

iOS 27.1 SDK, `iPhoneOS27.1.sdk/System/Library/Frameworks/MetalFX.framework/Headers/`:

**Availability and device gate.** `MTLFXFrameInterpolatorDescriptor` and
`MTLFXFrameInterpolatorBase` are `API_AVAILABLE(macos(26.0), ios(26.0))`
(`MTLFXFrameInterpolator.h:34,151`), unavailable on visionOS. The headers name **no device list**;
support is a runtime query: `+supportsDevice:` and `+supportsMetal4FX:`
(`MTLFXFrameInterpolator.h:108-117`). A Metal 4 command-buffer interpolator is created with
`newFrameInterpolatorWithDevice:compiler:` (`:99`) and encoded with
`encodeToCommandBuffer:` on `id<MTL4CommandBuffer>` (`MTL4FXFrameInterpolator.h:34`). iOS 27.2 on
the Duo satisfies the availability; whether the GPU supports it must be asked at run time. The
existing present path already hard-gates its MetalFX spatial scaler the same way
(`dm/gfx/nvn/nvn_mtl.m:11188`), so a failed `supportsMetal4FX:` is a graceful fallback, not a crash.

**The five textures** (`MTLFXFrameInterpolatorBase`, `MTLFXFrameInterpolator.h:234-314`):

| Property | Meaning |
|---|---|
| `colorTexture` | this frame, after tone mapping and before UI |
| `prevColorTexture` | the previous frame's `colorTexture`; required unless `requiresPrevColorTexture` is NO (iOS 27) |
| `depthTexture` | depth of this frame |
| `motionTexture` | per-pixel motion, **pointing to where the pixel was in `prevColorTexture`** |
| `uiTexture` | optional; with `uiTextureComposited` NO the interpolator composites it into the output |

Plus `deltaTime`, `nearPlane`, `farPlane`, `fieldOfView` (degrees), `aspectRatio`, `depthReversed`,
`jitterOffsetX/Y`, `motionVectorScaleX/Y`, `shouldResetHistory`, `outputTexture` (private storage),
and — new in iOS 27 — `worldToViewMatrix` / `viewToClipMatrix`, `contentWidth/Height` and content
offsets (`MTLFXFrameInterpolator.h:284-374`).

**Pixel formats.** The header carries no format table: the descriptor's five format properties must
equal the formats of the textures assigned (`MTLFXFrameInterpolator.h:38-49`), and the instance
exposes the minimum `MTLTextureUsage` per slot (`:158-166`). The formats that are known to work are
the ones the reference ships and its probe measured (§3): colour `RGBA16Float` / `RG11B10Float` /
`RGB10A2Unorm`, depth `Depth32Float`, motion `RG16Float`, UI `RGBA16Float`, output `RGBA8Unorm_sRGB`.

**What Apple says about the integration** (WWDC25-211, "Go further with Metal 4 games", 7:17):
frame interpolation "to all Apple platforms"; two rendered frames, motion vectors and depth; UI
either composited, offscreen or re-rendered per frame; and "try to have at minimum 30 frames per
second before interpolation". Pacing is explicit: present the interpolated frame, then after a
present interval show the most recently rendered frame.

---

## 3. What the reference project did

`~/dev/GAMING-DEV/macnativegames`, TotK on iPhone. All references are to
`games/totk/third_party/d2r_gfx/gfx/nvn/`.

### 3.1 Inputs and where they come from

`totk_mfx.m` per game frame (`:1-19` header comment):

- **colour**: the canvas copied *before the first UI draw* (`mfx_scene_target`, `:182`;
  `mfx_snapshot_scene` in the replay, `nvn_mtl.m:4501`, called at `:11401` and `:15766`), two
  buffers ping-ponged so `prevColorTexture` is the previous frame's copy;
- **UI**: colour attachment 7 of the later canvas passes, premultiplied `RGBA16Float`
  (`mfx_ui_target`, `:183`; attachment injection `mfx_pass_setup`, `nvn_mtl.m:4433`, used at `:4696`);
- **depth**: the game's own G-buffer `Depth32Float` (`mfx_note_depth`, `:186`);
- **camera**: 84 floats of the game's 2368-byte camera block at vertex uniform 1
  (`mfx_note_camera`, `:187`; `mfx_take_camera`, `nvn_mtl.m:10634`).

Descriptor: colour = canvas format, output `RGBA8Unorm_sRGB`, depth `Depth32Float`, motion
`RG16Float`, UI `RGBA16Float` (`totk_mfx.m:198-200`). Encode sets `uiTextureComposited = NO`,
`motionVectorScale = 1`, `depthReversed = NO`, `shouldResetHistory = !hist_ok`, and the camera
parameters (`:336-340`).

### 3.2 How it gets motion for a game that provides none

There is no motion texture in the game. The reference **computes** it on the GPU from depth and the
two frames' view-projection matrices: `reproj = prevVP * inverse(VP)` (`inv4`/`mul4`, `:264-279`;
product at `:308-309`), then a compute kernel projects each depth pixel into the previous frame and
writes the difference in pixels (`mfx_mv`, `:222`).

Two hard-won corrections, both in that kernel and its comment (`:11-19`, `:217-221`):

1. **Objects that move independently of the camera get the background's motion and shake.** Camera
   reprojection alone put Link off his place "in every interpolated frame, by the camera's step
   between two game frames… 25-30 times a second".
2. **Zero motion everywhere is worse.** "MetalFX relies on the motion it is given" — a
   zero-motion field "shook the whole picture".

The fix is a depth-discontinuity test: a pixel whose depth does not match what the previous frame's
depth says a still point would have is given no motion (`dyn`, `:233-244`). So even in a 3D game
whose camera is the dominant motion, the parts that move on their own are *dropped from
interpolation*, not interpolated correctly.

### 3.3 Presentation and pacing

- One interpolated picture per game frame, shown one refresh before the game frame: the present
  queue item carries an `interp` slot (`nvn_mtl.m:13831`), the callback shows the interpolated
  texture on one tick and the game frame on the next, at the refresh nearest half a game frame
  later (`:13881-13888`); `src = interp >= 0 ? mfx_output(interp) : tex_mtl(t)` at `:13501`.
- The encode is its own command buffer, GPU-ordered after the frame, with three slots and explicit
  Metal 4 resource lifetime (`mfx_present_frame_body`, `nvn_mtl.m:14025-14060`).
- Pacing: the game is held to every second display tick in the half-rate mode —
  `present_ticks` returns 2 (`hle_nvn.c:2743-2753`), `present_period` divides by the real display
  rate (`:2754-2760`).
- Interpolators are cached (4 configurations, `totk_mfx.m:94-104`) because rebuilding them grows
  device allocations.

### 3.4 What it measured

`docs/botw-v1.9.0-port.md:172-179`, BotW 1.9.0 on a Mac with a 120 Hz display:

| Mode | Game fps | Shown per second | MetalFX GPU p50 / p95 |
|---|---|---|---|
| off | 68.9 | ~67 | – |
| 30+30 | 29.9 | ~60 | 0.06 / 0.42 ms |
| half the refresh rate | 58.4 | ~115 | 0.4 / 7.6 ms |
| uncapped | 61.1 | ~115 | 0.4 / 7.6 ms |

Two things to carry over: the cost is not free at p95 (7.6 ms is nearly a whole 120 Hz refresh),
and the reference only ever ran it on 30 fps and ~60 fps sources (30+30 doubles 30 to 60; the
half-rate row doubles ~58 to ~115) — consistent with Apple's "at minimum 30 frames per second
before interpolation".

The synthetic probe (`games/totk/tests/metalfx_interp/probe.m`) established the conventions the
kernel relies on: motion in pixels of the motion texture pointing at the previous position
(`:39-45`, checks `:242-250`), UI given apart and premultiplied — the "composited" mode "gives a
black frame on this system" (`:252`), 8-bit colour works (`:251`), Metal 4 encoder gives the same
result (`:258`), and the game's set-up (16F scene + premultiplied 16F UI → RGBA8 sRGB out) passes
(`:259`).

---

## 4. Option (a): true interpolation for Scott Pilgrim

**What it needs that this game does not have.**

1. *A scene/UI split.* Solvable: the frame is 14 draws, so "everything after the Nth draw is UI" is
   a handful of draws to identify; the replay could copy the swapchain before the first UI draw
   exactly as the reference does. Low risk.
2. *Depth.* A 2D sprite renderer drawn in painter's order has no G-buffer; the profile records no
   PSO data at all (`dm/games/0100394011C30000/pso_manifest.tsv` is the empty provisional seed), so
   whether a depth attachment exists is **unverified**. If it does, it holds sprite-vs-sprite
   ordering, not world distance — not what MetalFX wants.
3. *Motion vectors.* This is the blocker. The reference's method needs a view-projection matrix and
   a depth that means "distance". A 2D game has an orthographic MVP per draw
   (`mvppos2_col_tex2.vs`), and the moving content — the player, enemies, effects — moves
   *relative to the scrolling background*, which is exactly the case the reference had to special-case
   away (`totk_mfx.m:11-19`).

**A method that could work, and why it is not the first thing to build.** With 14 draws per frame,
the replay could capture each draw's MVP and reproject its own vertices from the previous frame's
MVP — per-draw motion instead of per-camera motion. That is correct for independently moving
sprites, which is the whole game. But it means: capturing per-draw constants and vertex data in the
replay, matching draws across frames to know which MVP is "the same sprite as last frame", a
synthetic depth (draw order), and an answer for sprite animation frame swaps (which have no motion
at all and are exactly what MetalFX will smear). That is a project, with unproven quality, on a
renderer with no depth buffer. It is the right *second* thing.

**Cost.** Extrapolating the reference's numbers to the Duo: the interpolation input would be the
1920×1080 canvas, output the present rect (2853×1605 in full screen), i.e. the same order as the
TotK measurements — ~0.4 ms p50 but up to ~7.6 ms p95 of GPU time per generated frame, on top of
the present blit. On a phone that p95 is a dropped frame.

## 5. Option (b): duplicate-frame 120 Hz presentation

Mechanically this is easy — the present path already has the shape for it (the reference's
`interp` slot shows a second texture on a second tick, `nvn_mtl.m:13831-13888`); for duplicates the
second texture is simply the same one.

It does not help:

- **Motion**: the screen shows the same picture twice. Perceived smoothness, motion blur (each
  picture still stays 16.7 ms on an OLED) and latency are unchanged.
- **Jitter**: the only thing a 120 Hz grid buys a 60 fps source is that a late frame lands on the
  next 8.33 ms tick. `DM_PRESENT_LINK=2` already does exactly that (`nvn_mtl.m:116`,
  `:11853-11866`), with no second blit.
- **Cost**: one extra full-screen present per frame. The present rect in full screen on the Duo is
  2853×1605 ≈ 4.58 M px (`present_viewport`, `nvn_mtl.m:11118-11133`, keeps 16:9 inside the
  drawable); at RGBA8 that is ~18 MB written per present, so a 120 Hz duplicate stream writes
  ~2.2 GB/s instead of ~1.1 GB/s — before the reads. (Arithmetic from the pixel counts, not a
  measurement.)

**Verdict: reject.** State it plainly in the UI: a 120 Hz mode that only repeats frames is a lie.

## 6. Option (c): unlock the game's own cap — recommended

### 6.1 Why this one

- The mechanism is already in the tree and proven on 12 builds: `dm/host/hle_fpslock.c:19-80`
  (`k_locks`) writes an engine's own frame-limit field at a fixed address, per build ID, whenever
  the game sets it back. `fps_target` selects 30 or 60 (`dm/games/game.py:98`), `DM_FPS_TARGET`
  overrides, and `hle_nvn.c` calls `dm_fps_lock_tick` on every present.
- It fixes the 60 fps case too. The Mac run's 56.9 fps with p99 33.8 ms looks like the two-pacers
  signature (inference, §6.2); removing the game's limiter and letting the host pace is precisely what
  `hle_fpslock.c:14-17` describes for Luigi's Mansion 3.
- 120 Hz presentation is already implemented behind switches (§1.2); only the profile/cap path is
  missing a 120 case.
- It is the only option whose worst case is "no change", and whose measurement is a single run.

### 6.2 The measurement that decides it — do this first, no code

Run the game twice on the Mac host (or the device) and read the log:

1. **Baseline**: default. Record `[nvn] present tick …`, the `[nvn] the game sets present interval`
   lines (`hle_nvn.c:1295`), and the frame summary (`frame time p50/p95/p99`, presents/s).
2. **Offer 120 and see what the game does**:
   `DM_PRESENT_INTERVAL=display DM_PRESENT_HZ=120 DM_PRESENT_LINK=2`.

Interpretation:

| Observation | Meaning | What to do |
|---|---|---|
| presents stay ~60 while the host offers 120 ticks | the game's own limiter is the cap | §6.3, then §6.4 |
| presents rise to ~110-120 **and the game plays faster** (walk speed, animation, timer) | the engine steps per frame | the cap is the simulation rate: **stop**. Record it, and (a) becomes the only route to smoother motion |
| presents rise to ~120 and the game plays at the right speed | the engine steps by real time | §6.3 + §6.4 is the whole job |
| presents rise but frames are late/dropped | GPU/CPU bound at 120 | keep 60 and ship `DM_PRESENT_LINK=2` |

A third run with `DM_PRESENT_HZ=0 DM_PRESENT_LINK=0` measures the raw frame cost with no pacing at
all (both switches are needed: with the link on, the acquire still waits for ticks,
`hle_nvn.c:1341`). `DM_PRESENT_HZ=0` is a profiling switch only — its own warning says so
(`hle_nvn.c:1665-1666`).

### 6.3 Change set, part 1 — teach the host a 120 cap

Needed for a *profile-level* 120 that does not depend on the `present_interval display` cut.

| File | Change |
|---|---|
| `dm/games/game.py:98-99` | accept `fps_target 120` |
| `dm/gfx/nvn/hle_nvn.c:1648-1655` | `fps_present_cap`: accept 120 (currently `t==30||t==60`) |
| `dm/gfx/nvn/hle_nvn.c:1675` | `present_itv`: `60 / c` yields 0 for 120 — clamp to 1 |
| `dm/gfx/nvn/hle_nvn.c:1661-1674` | `present_cfg`: when the cap is 120 and no `DM_PRESENT_HZ` is set, pace at 120 (`g_hz`) so `present_period` (`:1691-1700`) computes 8.33 ms |
| `dm/gfx/nvn/nvn_mtl.m:10397-10398` | `mtl_fps_target`: return 120 when the game's target is 120 |
| `dm/gfx/nvn/nvn_mtl.m:11569-11602` | `link_sync`: a 120 target selects link mode 2 (today only the 30 case picks mode 3, `:11580`) |
| `dm/gfx/nvn/nvn_mtl.m:11853-11866` | `mtl_link_wait_tick`: the `× 2` on a 120 Hz link must become `× 1` when the target is 120 (this is the line that caps the default path at 60 today) |
| `dm/gfx/tests/t_nvn.c:66-70`, `t_pace.c` | the pacing cases: add 120 (period 8,333,333 ns, one link tick) |

Note the ordering: nothing here changes behaviour for the other games, because all of it is keyed
on the profile's `fps_target`.

### 6.4 Change set, part 2 — the game's own limiter

1. **Find it.** This title has no row in `k_locks` (`dm/host/hle_fpslock.c:19-80`) and no
   FPSLocker-derived address in the repo. The engine is Ubisoft's own (the binary carries
   `ubilibraries2`/Ubiservices paths and `storm::internal` symbols); the game resolves NVN entry
   points by name (`main+0x1320402` = `nvnWindowSetPresentInterval`), so the interval path is a
   resolved function pointer, not an import — start from the caller of that pointer, and from the
   frame loop's sleep/spin. The build ID is `8b939dc403aa7e4817de4f646ff72d86`
   (`dm/games/0100394011C30000/game.tsv:17`), and `k_locks` rows run only on the exact build they were
   found in, which is the guard this repo requires.
2. **Add the row** to `k_locks` with the right `kind` (`FPS_F32`, `MS_F32`, `VSYNCS_I32`,
   `TICKS_U32`, … — `hle_fpslock.c:12-16`), and set `fps_target` in
   `dm/games/0100394011C30000/game.tsv`.
3. **If the limiter is a spin rather than a field**, it is a rewriter cut instead (the Criterion
   game's spin at `main+0x483588` is cut in `patches.py`, `hle_fpslock.c:64-67`) — same
   infrastructure, `dm/tools/patch_nso.py`.
4. **Verify** with the §6.2 runs: the present rate must reach the target with the game's speed
   unchanged, and the interval log must stop showing the game raising it back.

### 6.5 What ships even if the cap cannot be raised

`DM_PRESENT_LINK=2` in the Duo build's `duo/duo.env`: a 60 fps game presented on an 8.33 ms grid
instead of a 16.7 ms one, at zero cost in pictures. That is the honest ceiling for this title
without (a), and it should be the default in the Duo build regardless of how §6.2 comes out.

### 6.6 Interaction with the dual-screen mode

The dual-screen mode puts the game in the top half of the panel. Taking that as half of the 2007 px
height, the game view is roughly 2853×1003 in landscape, so the 16:9 picture is ~1783×1003 ≈ 1.79 M px — about 39 % of the
4.58 M px full-screen present rect (arithmetic from `present_viewport`, `nvn_mtl.m:11118-11133`).
Present bandwidth and GPU cost therefore drop by more than half in exactly the mode the Duo exists
for, which is where a 120 fps target is most likely to hold. The simulation cost does not drop, so
§6.2 must be measured in the same layout the mode will run in.

---

## 7. Open questions, stated as such

1. **Does the engine step by real time?** Decides everything in §6. §6.2 answers it.
2. **Does the game create a depth attachment at all?** No recorded PSO data for this build
   (`dm/games/0100394011C30000/pso_manifest.tsv` is the empty provisional seed). Only matters for
   (a).
3. **What does the game pass to `nvnWindowSetPresentInterval`?** The host logs it; the log has not
   been read for this title.
4. **Can the Duo hold 120 fps for this game at all?** No device run exists
   (`duo/README.md`, "Status"); the Mac's 56.9 fps says nothing about the Duo's SoC under thermal
   load — and the repo's own thermal cap holds 30 fps when `thermalState >= 2`
   (`hle_nvn.c:1614-1643`), which would make a 120 target moot on a hot device.
5. **MetalFX support on the Duo's GPU** is a runtime query (`supportsMetal4FX:`); irrelevant to the
   recommendation, decisive if (a) is ever attempted.
