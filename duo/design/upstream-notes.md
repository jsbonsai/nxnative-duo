# Upstream (seedds/nxnative) — what matters to us

Surveyed 2026-10-30 (all 761 open+closed issues/PRs; Discussions are disabled on that repo). Every item below is a
pointer to work we would otherwise redo, or to a platform fact that changes a plan.

## 1. The aspect question: upstream already decided it (issue #93, OPEN)

> "**Zoom to fill** crops about 18% of the height, which cuts off HUD elements near the top and bottom (hearts, the
> minimap, button prompts). **Stretching** makes everything about 22% wider. Neither is acceptable as a default."
> … "The game itself renders a wider view (3D projection and viewport, render targets, and UI layout where the
> engine anchors HUD elements to the screen edges), and the host presents it without bars."

What this means for us:

* Our **camera-aspect patches are the sanctioned direction** (`duo/design/aspect.md`), not a hack.
* The missing half is **UI classification**: a per-profile list of which draws are UI, so HUD elements anchor to the
  real aspect instead of being stretched. A contributor (ComicBit) has BOTW 1.9.0 + TOTK 1.4.3 working with that
  scheme on an unmerged branch (`ComicBit/nxnative:zelda-native-widescreen`) and warns about an ABI collision with
  the frame-step state page at `+0x40` (we use `+0x40` for the aspect ratio slot — check before merging anything).
* 16:9 ÷ 1.4215 = **1.251**, which is exactly the 1.25x HUD distortion we measure. Our `Stretch` mode is a
  deliberate shortcut; it is what upstream calls unacceptable as a *default*.
* **#631** (open PR): `DM_BAR_FILL` — blurred picture or a still image in the bars. A nicer **Letterbox** than black
  bars, and the upstream answer for a non-16:9 panel. Worth adopting as our Letterbox default.
* **#117** (closed, unmerged): `OUTPUT_W`/`OUTPUT_H` + a profile key `aspect any` — the general "render wider" output
  size mechanism. Not in main; the HUD re-authoring is explicitly a separate per-game job even there.

## 2. A game that dies before the first frame

* **#269** (open PR): `nvnCommandBufferSetConservativeRasterDilate` and `SetSubpixelPrecisionBias` should be
  **quiet no-ops** (Metal has no conservative rasterisation). They were red stubs in a title that set them.
  **We hit exactly this on Burnout Paradise**; the two stubs are now in `dm/gfx/nvn/hle_nvn.c` (2026-10-30).
* **#359**: a crash in static init is usually the **provisional profile's guessed memory layout**
  (`mem_reserve` / `mem_alias` / pool placement), not the renderer. Fix by writing a real profile.
* **#540** carries the maintainers' standing instruction for a provisional profile: it "may not boot; bring it up
  per docs/agents after packing". Bring-up loop: `patch_nso.py` → `make -C dm/host GAME=… dmhost` → `run/boot.sh`,
  then `grep -aF "[RED]" log | sort | uniq -c`.
* **#732**: a silent exit right after `stubs=0` had an SDK/HLE NULL cause — check that before blaming NVN.

## 3. "the shader split found no shaders" (we saw it on AC Ezio)

* **#549** (merged): the pattern for every such report — identify the container, add a reader keyed on format bytes,
  report shaders before → after (Team Sonic Racing: 0 → 4,516).
* **#747** (open draft PR) is **our Ezio answer**: Ubisoft `scimitar` `.forge` payloads are an LZ stream no decoder
  on hand reads, so instead **build once, run with `DM_NVN_SHDUMP=<dir>`** (the host dumps the control section and
  code of every program missing from the map), then feed the dump directory back to the split and add
  `pso_pairs_manual.tsv`. Verified upstream on AC: The Rebel Collection (326 keys from `main` + 514 from dumps).
* Unreadable archives no longer abort the split (PR #282), so our Ezio failure is a coverage miss, not a crash.

## 4. Free Apple ID / signing / re-signing

* **No upstream issue documents the 7-day expiry or the 3-app limit**; plan for them empirically (our quickstart
  already states both).
* **#524 / #478**: keep the RomFS **out of the IPA** (`DM_COPY_ROMFS=NO`, `DM_COPY_SHADERS=NO`) and push it once
  (`push_romfs.sh`), so a 7-day re-sign is a small rebuild rather than re-sending gigabytes. Entitlements live on
  the executable's signature (`build_ipa.sh`), which is what a sideloader reads.
* **#647** (open PR): a script that checks profile **expiry**, bundle id and device UDID before installing — the
  right hook for our re-sign reminder.
* **#724**: a Personal Team cert does **not** grant `dynamic-codesigning`; don't design features that need it.

## 5. Foldables, portrait, external displays (our split-screen work)

* **#557** (open) and **#633** (open): portrait layout with the picture in the top half and the controls in the
  bottom half — the same target as `duo/design/dualscreen.md`. #633 proposes gating the mode on the inner display's
  native aspect (0.7035) and splitting the present at fractions of the canvas height.
* **Platform limit, from #557**: Apple's "Prepare your app for iPhone Duo" says the **inner display does not honour
  an app's supported interface orientations**. Upside-down portrait will not rotate there; do not chase it.
  (#576 records the cover-screen portrait bug.)
* **#683** (open PR): hinge/division-region API (`UIHingeInteraction`) for tabletop poses — our split has no hinge
  gap yet.
* **#705** (open): on iOS 27 an external display only mirrors unless the app calls `registerSceneAccessory`; a
  ~100-line fix is in the issue body. Relevant to the outer screen / a TV.

## 6. Per-game notes that apply to our queue

| Game | Issue | What it says |
|---|---|---|
| Dragon Quest VII | #589 (closed) | Blurry textures were the game's own `r.Streaming.PoolSize=200`; a profile key raises it (1000). **Mac only** — the iPhone path was deliberately left off pending a memory check. |
| Galaxy 2 | #508 (closed), #659 | iOS lighting bug was a Vulkan NaN shader issue, fixed; "1.4.0 confirmed playable"; packing Galaxy 1+2 needs `--title-id`. |
| Wonder | #373/#377 (closed), #758 | The maintainers' known-good baseline build. |
| Luigi's Mansion 3 | #580 (closed), #672 (open) | Set `depth_mode zero` in the profile; one open crash remains (Ghost Gallery). |
| Burnout / AC Ezio / Demon Slayer | — | No issue mentions any of the three. |

## 7. What to do next, ranked

1. Adopt **#747's dump path** for AC Ezio instead of a `.forge` reader (an afternoon vs. a week).
2. Retest **Burnout** with the two NVN no-ops (done in code, untested on device yet).
3. Adopt **`DM_BAR_FILL`** (#631) as the Letterbox default: blurred bars instead of black.
4. Watch **#93's branch** for the UI-classification scheme; reusing it is the shortest path to a non-stretched HUD.
5. Compare our split to **#557/#633** (fractions-of-canvas present split, hinge gating) before writing more layout
   code; take **#705**'s scene-accessory call for the outer screen.
