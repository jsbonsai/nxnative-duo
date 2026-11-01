# Full-screen aspect on the Duo without stretching — the method that works

Status (2026-10-30): **proven on Super Mario 3D World (in-game camera) and Tears of the Kingdom.** This is the
method every new game should follow. Read this before patching any game; read `duo/STATUS.md` for per-game state.

## 1. The problem in one paragraph

Switch games render a 16:9 picture (1920×1080). The Duo's screens are ~1.42 (inner landscape 2853×2007 px =
1.4215; inner upright split top half 2007×1426 px = 1.407). Shown full screen, a 16:9 picture is stretched
**1.25× vertically** (1.778 / 1.4215 = 1.2507): characters look tall and thin. Letterbox (bars) and Crop (cut the
sides) are already in the ⚙ menu for every game, but neither is "full screen, full picture, correct shape".

## 2. The three levers (and which one is right)

| Lever | What it changes | Verdict |
|---|---|---|
| **Canvas** (swap-chain / display size, e.g. 1920×1350) | the size of the final picture | **Do not use.** Did not fix the 3D world in 3D World (the camera still used 16:9); **hung LM3 at boot** (86 rows); fragile (dozens of sites per game). The rows are kept commented-out in `duo/research/res.tsv`. |
| **Camera projection aspect** | the shape of the 3D world itself | **Use this.** Keep the 1920×1080 canvas; give the camera the screen's ratio (1.4215); present with **Stretch**. The narrower projection and the 1.25× present stretch cancel exactly. |
| UI layout space | HUD, menus, prompts | Separate, second step (§6). |

Why the camera lever is right: the game's own matrices change, so everything derived from them stays consistent —
frustum culling, shadow lookups, deferred lighting's world-position reconstruction, motion vectors / TAA. A
driver-side alternative (scaling clip-space y in every vertex shader, which our shader build could do in
`dm/gfx/tools/dmsh_build.py vs_depth`) was **rejected**: deferred renderers (LM3 has a G-buffer) rebuild each
pixel's world position from depth + screen UV with the *unscaled* inverse projection, so lights and shadows would
slide.

Framing: same vertical field of view as the original, horizontal field of view narrowed to the Duo's shape —
the same framing as Crop, but rendered at the full 1920 px width instead of a 1535 px slice. (Widening the
vertical FOV instead, "Vert+", would need the FOV patched too; not done.)

## 3. The patch mechanics (code)

`dm/tools/duo_aspect.py`, wired in `dm/tools/patch_nso.py` (block "Duo aspect", runs when `DM_DUO=1`):

| Kind | Registry | What it does |
|---|---|---|
| 16:9 constant | `duo/research/games.tsv` column 3 | the rodata float `0x3FE38E39` (1.7778) becomes the screen ratio. Every reader of that constant changes. |
| Aspect site, **constant stub** (new 2026-10-30) | `duo/research/games.tsv` column 2 | an `fdiv s<d>,…` or `ldr s<d>,[…]` that produces the camera aspect is replaced by `b stub`; stub = `ldr s<d>, <literal>` · `b site+4` · `.float ratio`. Works in **any** build. `install_sites_const`. |
| Aspect site, runtime stub | `duo/research/games.tsv` column 2 | same, but reads the ratio from the frame-step state page (+0x40) at run time; only builds with `FRAME_STEP` (TotK). `install_sites`. |
| Word rewrite | `duo/research/res.tsv` | any single 32-bit word, old value and a neighbour asserted (used for 3D World's camera getter). `install_res`. |

The ratio is `DM_DUO_ASPECT` at build time (default `2853:2007`). Tests: `dm/tools/tests/test_duo_aspect.py`
(`ConstStub` decodes the stub with capstone).

## 4. Finding a game's aspect sites (the per-game work)

1. `duo/tools/find_aspect.py <extracted main>` lists candidate `fdiv` / `ldr s` sites near the sead projection's
   fields (`str s,[x,#0xb0]` = aspect, `#0xac` = tangent) and every 16:9 rodata constant.
2. The decisive trace (3D World): the projection builder (`0x87b200`, a sead `PerspectiveProjection`-like call
   taking fovy, aspect, near, far) and the **setter** that stores aspect at `+0xb0` (`0x738620`); its callers load
   aspect from a camera object field (`+0x124`/`+0x128`); the writers of that field are `fdiv rect.w / rect.h`
   (`0x901640`, `0x90165c`). Those two fdivs are the sites. Capstone needs `md.skipdata = True` or it stops at
   the first data word in `.text` (that silently produced "0 xrefs" for a while).
3. A game can have several cameras: 3D World's title camera reads the 16:9 constant through a getter
   (`0x7386c0`, patched in `res.tsv` to load the patched constant); the in-game camera uses the fdivs. Test the
   title **and** a level.
4. Ghidra via REA chokes on a whole 21 MB main (auto-analysis never finishes inside the 30 s MCP timeout); a
   3 MB slice wrapped as an ELF at the original addresses analyses in ~22 s.

## 5. Verifying (no eyeballing)

The device screenshot of the patched game in **Stretch** must match the **unpatched** 1080 frame of the same scene
**cropped** to the screen's ratio and scaled, not the unpatched frame stretched. Score with normalized
cross-correlation over static scenery (exclude HUD, controls, the player), searching a small shift.

3D World, level 1-1 spawn, 2026-10-30 (`/tmp/win.png` vs `/tmp/bl2.png`, kept as `duo/design/img/aspect-3dw-*.png`):

| Hypothesis | Best NCC | Shift |
|---|---|---|
| correct shape (crop-equivalent) | **0.656** | dx 0, dy 0 |
| still stretched | 0.189 | dx −160 (search edge: no real alignment) |

Owner on the device: "Mario is the right size, he is not stretched."

Capture: `duo/tools/dev.py shot out.png` (active display); drive the game: `duo/tools/dev.py run <bundle> <script>`
(`launch`, `key A`, `wait 6`, `shot …`). Builds need `DM_CTL=Documents/ctl.txt` in the env file (`duo/test.env`).

## 6. The HUD (3D World): tested, not solved (timeboxed 2026-10-30)

With the camera fixed and the game back on its 1920x1080 canvas, the HUD is still 1.25x tall. Two candidates were
built and measured; **neither changed it**, so both are `#off` in `duo/research/res.tsv`:

| Tried | Result |
|---|---|
| the 4 `nn::ui2d` UI-resolution table rows (`0x13e7c4c`, `0x13e7d48`, `0x13e7d9c`, `0x13e7df0`, height 1080 -> 1350) | HUD identical (`duo/tools/hudcheck.py`: top-left 0.305/0.584, top-right 0.459/0.678, same before and after) |
| `GetScreenHeight()` docked 1080 -> 1350 and the two handheld 720 -> 900 getters (`0x8a86a0`, `0x8a86c0`, `0x8a86e0`; 63/54 callers) | HUD identical |

What was learned, so the next attempt starts further ahead:

* `duo/tools/hudcheck.py <device.png> <baseline-1080.png>` scores each corner as "true shape" vs "stretched": it
  renders the baseline corner crop both ways (uniform W/1920 vs W/1920 x H/1080) and picks the better match.
  Right now: top-left stretched, top-right stretched (the bottom corners are covered by the controls).
* `DM_CTL` `passdump` shows only ~38 draws per frame, and the frame ends with a **blit** of the scene into the
  swap-chain texture (`sc=0,0,1920,1080 tgt=1920x1080`). 3D World records its scene and UI into **pre-built NVN
  command lists**, so the HUD's own draws (and their projection constant buffers) are not in the dump. Finding
  them needs tracing into the command-list replay, not more grep.
* The HUD's projection scale is computed at run time: `2/1920` (0x3A888889) and `2/1080` are not in the image.
* `duo/games/010028600EBDA000-ui.md` still stands as the map of the `nn::ui2d` layout path
  (`[context+0x50]` -> ortho -> `DrawInfo`); its §7 names the unproven link (the writer of `[context+0x50]`).

## 6a. Installing a test build without a new provisioning profile (free Apple ID)

A new bundle id (`org.example.duo.<game>`) needs the Xcode account, which is unavailable (`No Accounts`), and
the free team allows three apps on the device at a time. To verify a camera patch for a game that has no profile:

1. Prepare and build it normally with its own bundle id (`nx build … --prepare-xcode --bundle-id org.example.duo.<game>`,
   then `xcodebuild … CODE_SIGNING_ALLOWED=NO`).
2. Retarget the built app to a bundle id that already has a profile and a free device slot:
   `plutil -replace CFBundleIdentifier -string org.example.duo.lm3 "$APP/Info.plist"` (any of lm3 / totk / 3dw / scott).
3. Sign it with that profile and its entitlements (see §6a's recipe in `duo/design/dualscreen.md` §0.8 —
   `application-identifier`, `team-identifier`, `get-task-allow`, `keychain-access-groups`, `increased-memory-limit`),
   `devicectl device install app`, then drive it with `duo/tools/dev.py`.
   The bundle id only changes the app's UserDefaults domain (its in-game menu settings), not the game.

Available profiles on this Mac: `security cms -D -i ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision | plutil -extract Name raw -`.

## 7. Per-game state

| Game | Build | Camera | HUD | Notes |
|---|---|---|---|---|
| Super Mario 3D World | `891687f0…` | **correct, verified on device** (fdivs `0x901640`/`0x90165c`, the 16:9 constant, the title camera getter) | stretched | canvas, UI-table and screen-height rows all `#off`; this is the reference build |
| Tears of the Kingdom | `277178b7…` | correct (4 runtime stubs) | stretched | |
| Luigi's Mansion 3 | `79e5950f…` | search started 2026-10-30 | — | canvas rows and the 16:9 constant both hang it: keep LM3 plain until a camera site is found |
| Super Mario Bros. Wonder | `cd6e42ae…` | **correct on device** (one site, `0x10f47c`; canvas rows `#off`) | stretched | the world fills the screen with natural proportions; the HUD's Toad head measures 200x240 px (1.2x tall) like 3D World's |
| Demon Slayer | `14c878ec…` | **no site found** (UE4; the rect->aspect fdivs are unreachable or render-pass inputs) | — | see `duo/games/0100309016E7A000-camera.md` |
| DQ VII Reimagined | `ab060209…` (1.1.0), `f7ec03e4…` (1.2.0) | **unverified**, opt-in. Sites `0x1038130` (W/H, UE4's default MaintainXFOV branch) and `~0x10384bc` (H/W). With only `~0x10384bc` the Duo picture measured stretched (title screen NCC 0.93 vs 0.64): that branch never ran. With both, the title-screen test is inconclusive (0.931 vs 0.907 on 406 px): the title background may be 2D | — | needs a measured in-game 3D scene (same save on the Duo and a 16:9 reference phone). Owner played 1.2.0 on the Duo: 60 fps, "10/10" — a performance verdict, not a proportions one |
| AC Ezio Collection | `824b38a2…` | patch applies; **cannot pack yet**: the shader split finds no shaders in main or the RomFS, profile provisional | — | needed the new pair site kind |
| Burnout Paradise | `74570fa2…` | patch applies; **does not boot yet** — provisional profile; frame 1, then two unknown `nvnDeviceGetInteger` items (0x60/0x61) and no further frames | — | the two unimplemented NVN raster calls are now quiet no-ops (`ConservativeRasterDilate`, `SubpixelPrecisionBias`, matching upstream #269) and that error is gone, but the game still stalls: it needs bring-up (docs/agents/03-bringup.md), not an aspect fix |
| Super Mario Galaxy 2 | `a071148f…` | **correct on device** (`0x2fe2e0`, `0x2fe5f8`; `0x2fe4a0` removed) | — | the first run read as squashed (the file-select mushroom): `0x2fe4a0` is the matrix element `cot/aspect`, so patching it applied the ratio twice. After removing it the mushrooms and title logo are round |
| Scott Pilgrim, Sea of Stars, TMNT, Star Ocean 2R, FF Tactics | — | mostly 2D: the camera lever may not exist | — | Letterbox in the in-game menu is the honest default |

## 8. Measurement traps (learned 2026-10-30)

1. **The player's saved fill choice.** A Duo build defaults to Stretch, but a choice the player made in the menu (Letterbox,
   Crop) is saved and wins. A letterboxed 16:9 picture on the Duo fills exactly the middle 80% of the height, which is
   also what a correct MaintainXFOV patch produces — so "the 16:9 picture sits in the middle 80%" proves nothing. Always
   crop the frame to the picture rows that are lit across the whole width first, and compare INSIDE the picture.
2. **2D backgrounds.** Title screens and menus are often a flat image or movie, not the 3D camera: they look the same with
   or without the patch. Measure an in-game 3D scene (same save on both phones: copy `Documents/save` between the app
   containers with `devicectl device copy from/to`).
3. **Which branch runs.** UE4 builds the projection in one of two branches (`AspectRatioAxisConstraint`). Patch both:
   they are exclusive, so the ratio is never applied twice, unlike a matrix element (Galaxy 2's mistake).
4. **Patched ≠ working.** `main.cuts.tsv` showing the `duo aspect` line only proves the instruction was replaced.
