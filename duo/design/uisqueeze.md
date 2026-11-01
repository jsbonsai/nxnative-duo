# HUD squeeze: undoing the present's stretch for UI draws

Status: design, not implemented. No source outside this file is changed.
Owner: the per-draw viewport transform in `dm/gfx/nvn/nvn_mtl.m`.
Reference: MacNativeGames `uw_ui_squeeze` (MIT; mechanism reimplemented, not copied — same
attribution rule as `duo/DESIGN.md`).

## 1. What the Duo does to the HUD

`duo/duo.env` sets `DM_PRESENT_FILL=stretch` and `DM_DUO_ASPECT=2853:2007`; the game's
canvas is 1920×1080 (the `WindowInitialize swap chain ... first 1920x1080` line). The present
therefore draws the canvas into the whole drawable:

| | canvas | drawable | scale |
|---|---|---|---|
| across | 1920 | 2853 | 1.4859 |
| down | 1080 | 2007 | 1.8583 |
| | | **anisotropy** | **1.2505** |

Anything the game draws in canvas coordinates — HUD, menus, text, markers, and in a 2D game
the sprites too — is drawn **1.25× too tall** (equivalently 0.8× too wide). The world is
correct only because the camera patch puts the drawable's aspect (1.4215) into the
projection, which pre-compensates exactly (`duo/DESIGN.md`, "The mechanism").

Note the direction, because the sign decides the code: `duo/games/0100F2C0115B6000.md:19`
says "stretched horizontally ~1.25x (1.778 / 1.4215)". The anisotropy is the same number,
but on a panel *narrower* than 16:9 the present stretches the canvas **vertically**, so the
HUD must be flattened vertically, not narrowed horizontally. The reference's formula
(`totk_ui_squeeze.h:9-13`) with a = 1.4215 gives `ux = 1`, `uy = 1.25`. A patch that narrowed
the HUD would double the error.

## 2. The reference mechanism, exactly

All paths are in `macnativegames/games/totk/third_party/d2r_gfx/gfx/nvn/`.

### How a UI draw is identified

Four conditions, all on the draw that is about to be encoded:

1. **The UI phase has begun this frame.** `g_uw_ui` is set by the first draw into the canvas
   whose vertex shader is one of the game's UI shaders:
   `nvn_mtl.m:11402` — `if (!g_uw_ui && uw_on_canvas() && pr && pr->sh[0] && UW_UI_BEGINS(pr)) g_uw_ui = 1;`
   with `UW_UI_BEGINS(pr)` = `mfx_ui_vs(pr->sh[0]->key)` (`nvn_obj.h:243`).
2. **The draw's vertex shader is a UI shader.** `uw_ui_squeeze` calls
   `UW_NOT_UI_DRAW(vs, dw, di)` (`nvn_mtl.m:4491`), which for TOTK is
   `!uw_ui_vs(vs) || count != 6` (`nvn_obj.h:244`). `uw_ui_vs` (`nvn_mtl.m:4479`) is
   `mfx_ui_vs` (`nvn_mtl.m:4452`, nine 8-hex keys) plus four more keys — a hard-coded
   per-game list of vertex-shader keys, prefix-matched on the first 8 characters.
   The vertex count is a second gate: TOTK's UI is 6-index quads.
3. **The draw goes into the canvas.** `uw_on_canvas()` (`nvn_mtl.m:4477`) compares the draw's
   colour attachment 0 serial with `g_mfx.canvas`, a texture learned by `canvas_learn`
   (`nvn_mtl.m:4430`: the swapchain's dimensions, a float format, no depth attachment), and
   `uw_note_present` (`nvn_mtl.m:4472`) records the swapchain serials and size at the present.
4. **The picture is not 16:9.** `totk_ui_squeeze.h:9-13`:
   ```c
   double f = a > 0 ? a / (16.0 / 9.0) : 1;
   *ux = f > 1.001 ? f : 1;      // wider than 16:9: narrow the UI
   *uy = f < 0.999 ? 1 / f : 1;  // taller than 16:9: flatten the UI
   ```
   `a` is the game's runtime aspect (`runtime_aspect_now`, `nvn_mtl.m:4471`), i.e. the ratio
   the picture is *shown* at. A dead band of 0.1 % keeps 16:9 bit-identical.
   `TOTK_UI_SQUEEZE=0` turns it off (`nvn_mtl.m:4490`).

### What transform it applies

No matrix and no shader is touched: only the draw's viewport and scissor, about the canvas
centre (`cx = tw/2`, `cy = th/2`):

```c
// nvn_mtl.m:11462-11465
uw_ui_squeeze(pr && pr->sh[0] ? pr->sh[0]->key : NULL, dw, di, tw, th, &ux, &uy);
double vx = S.has_vp ? S.vp[0][0] : 0, vw = S.has_vp ? S.vp[0][2] : tw, ...;
if (ux != 1) { vx = cx + (vx - cx) / ux; vw /= ux; }
if (uy != 1) { vy = cy + (vy - cy) / uy; vh /= uy; }
// nvn_mtl.m:11512-11514 — the scissor's edges, rounded, then clamped to the target
if (ux != 1) { sx0 = lround(cx + (sx0 - cx) / ux); sx1 = lround(cx + (sx1 - cx) / ux); }
if (uy != 1) { y0 = lround(cy + (R.sc.y - cy) / uy); y1 = lround(cy + ((long)R.sc.y + R.sc.h - cy) / uy); if (y0 < 0) y0 = 0; }
if (x1 <= x0 || y1 <= y0) { g_draw_skip[10]++; return; }   // squeezed away: the draw is dropped
```

The UI's clip space is mapped into the middle `1/ux` (or `1/uy`) of the canvas; the present
stretches that back. On a 21:9 window the HUD keeps its shape in the middle 16:9; on a panel
taller than 16:9 it is flattened and the world shows above and below it.

### The variant for a game whose UI shaders cannot be named

Breath of the Wild (`nvn_obj.h:210-212`): `UW_UI_BEGINS(pr)` is the constant 1 and a UI draw
is *any* 6-index quad that is not the scene's own picture (`botw_uw_scene_picture`). Its UI
shaders are the scene's, so the key list cannot separate them; the draw shape and the frame
order do. This is the fallback for a 2D game whose HUD and sprites share a vertex shader —
see risk 1.

## 3. nxnative today

### The draw encode (`dm/gfx/nvn/nvn_mtl.m`)

- `draw_(dw, di)` — `:9389`. `__unsafe_unretained NvProg *pr = ...` at `:9403`; the vertex key
  is `pr->sh[0]->key` (8 hex characters, the same key `shader_map.tsv` column 4 names).
- Viewport, `:9524-9532`:
  ```c
  NSUInteger tw = g_pass.tw, th = g_pass.th;                    // :9524, from pass_dims (:3525)
  { MTLViewport v = S.has_vp ? (MTLViewport){S.vp[0][0], ...} : (MTLViewport){0, 0, tw, th, 0, 1};
    if (g_origin_ll) { v.originY += v.height; v.height = -v.height; }   // :9527 lower-left origin
    ... NEGATIVE_Y swizzle, :9529-9531 ...
    if (!(g_ed.ok & ED_VP) || memcmp(&g_ed.vp, &v, sizeof v)) { enc_r_viewport(en, v); ... } }   // :9532
  ```
- Scissor, `:9533-9540`: from `R.sc` clamped to `tw`/`th`, then sent through the same
  `g_ed` dedupe (`:2837`). No squeeze anywhere.
- The replayer includes this file and goes through the same `draw()`
  (`docs/development.md:340`), so a change here is testable offline.

### The present

- `present_viewport(cw, ch, dw, dh)` — `:11118-11133`. `DM_PRESENT_FILL` is read once
  (`:11122-11127`); `stretch` returns `{0,0,dw,dh}` (`:11128`); `crop` and unset scale the
  picture uniformly and centre it (`:11129-11131`), with a "whole canvas" exception when the
  ratios differ by under 1 % (`:11132`).
- `present_crop_rect(src, crop, r)` — `:11135` gives the valid source rectangle; the canvas
  size is `r[2]×r[3]`, not necessarily the texture's.
- `present_encode` (`:11144`, Metal 3) and `present_encode_m4` (`:11242`, Metal 4, the live
  path) both call `present_viewport`; `present_encode_m4` also uses `vp` as MetalFX's output
  size (`:11249`, `:11266`).
- `present_now` — `:11313`; the drawable is taken at `:11374`; the present is encoded at
  `:11387`. This is the one place where the drawable size and the canvas crop are both known.
- `present_enqueue` — `:11763` records the swapchain serial in `g_xv_present` at `:11766`
  (`xv_present`, `:3147`). The swapchain textures are also registered at window setup
  (`hle_nvn.c:1289`, `mtl_xv_window_tex` `:3151`), so the canvas serials are known **before
  the first frame**.

### Profile plumbing

`nvn_mtl.m:34` includes `game_profile.h`, generated by `dm/games/game.py` `header()`
(`game.py:91-188`) from `dm/games/<id>/game.tsv`. The shader map is loaded by `shmap_load`
(`nvn_mtl.m:3617`) into `g_shmap` (key → `vertex`/`pixel`), from `DM_NVN_SHMAP` or the
profile's `shader_map.tsv` (`:3620`).

## 4. The change set

One host file (`nvn_mtl.m`), plus one profile key and its generator line. No matrix stub, no
shader rebuild, no rewriter change.

| Where | What |
|---|---|
| `dm/gfx/nvn/nvn_mtl.m` after `xv_present` (`:3151`) | state: `g_ui_k` (float bits of the present's anisotropy), `g_ui_cw/g_ui_ch`, `g_ui_draw`, `g_ui_vs[]`, `g_ui_off` |
| after `shmap_load` (`:3617-3660`) | `ui_vs_load()`, `ui_is_ui(vs)`, `ui_squeeze(tw, th, &ux, &uy)` |
| `first_draw_covers` (`:7401`) | `if (g_ui_draw) return g_fd_why = 12, 0;` — the coverage proof assumes the viewport is the target's |
| `uv_proof` (`:8549`) | `if (g_ui_draw) return 0;` — the 1:1 texel proof assumes a full-target viewport (`:8556`) |
| `draw_` (`:9403`, before `rp_begin_ex` at `:9484`) | `g_ui_draw = ui_is_ui(pr->sh[0] ? pr->sh[0]->key : NULL);` |
| `draw_` viewport (`:9524-9532`) | squeeze `v` about `tw/2`, `th/2` before the origin flip |
| `draw_` scissor (`:9533-9540`) | squeeze the edges with `lround`, then the existing clamps and empty test |
| after `present_crop_rect` (`:11145`) | `ui_note_present()` — `present_viewport` → `ui_k_set((vp.width/r[2]) / (vp.height/r[3]))`, `g_ui_cw/ch` |
| `present_now` after `:11374` | `ui_note_present(src, crop, dr.texture.width, dr.texture.height);` |
| `dm/games/game.py` `header()` | `#define DM_GAME_UI_VS {…}` (default `{NULL}`) from the `ui_vs` profile key |
| `dm/games/<id>/game.tsv` | `ui_vs\t<key> <key> …` |
| `docs/env_switches.tsv` | rows for `DM_DUO_UI_SQUEEZE`, `DM_DUO_UI_LOG`, `DM_DUO_UI_VS`, `DM_DUO_UI_K` (the test fails until they exist) |

### Code sketch

```c
// ---------- Duo UI squeeze (duo/design/uisqueeze.md) ----------
// The present fills the drawable with the game's canvas (DM_PRESENT_FILL=stretch): on the Duo that is 1.486x across and
// 1.858x down for a 1920x1080 canvas, so a pixel drawn in canvas coordinates comes out 1.25x too tall. The HUD is drawn
// in canvas coordinates; its draws are squeezed back about the canvas centre by the same 1.25, and the present restores
// them at the scale the world is shown at. No matrix, no shader, no layout change.
static _Atomic uint32_t g_ui_k = 0x3f800000;   // float bits: the present's horizontal scale over its vertical scale; 1 = nothing to undo
static NSUInteger g_ui_cw, g_ui_ch;            // the canvas the present shows (its valid crop)
static int g_ui_draw;                          // this draw is squeezed: the pass proofs must not assume a full-target viewport
static char g_ui_vs[32][20]; static int g_ui_nvs = -1;   // the profile's UI vertex shader keys
static int g_ui_off = -1;                      // DM_DUO_UI_SQUEEZE=0
static long g_ui_log = -1;                     // DM_DUO_UI_LOG=<frames>: log the canvas draws of that many frames

static double ui_k(void) { uint32_t b = atomic_load_explicit(&g_ui_k, memory_order_relaxed); float f; memcpy(&f, &b, sizeof f); return f > 0 ? f : 1; }
static void ui_k_set(double k) { float f = (float)k; uint32_t b; memcpy(&b, &f, sizeof b); atomic_store_explicit(&g_ui_k, b, memory_order_relaxed); }

static void ui_vs_load(void) {   // the profile's list, checked against the shader map's vertex keys
    if (g_ui_nvs >= 0) return;
    g_ui_nvs = 0; shmap_load();
    const char *e = getenv("DM_DUO_UI_VS");           // diagnostic: key,key,… without a rebuild
    NSMutableArray<NSString *> *ks = [NSMutableArray array];
    if (e) [ks addObjectsFromArray:[@(e) componentsSeparatedByString:@","]];
    else for (size_t i = 0; DM_GAME_UI_VS[i]; i++) [ks addObject:@(DM_GAME_UI_VS[i])];
    for (NSString *k in ks) {
        NSString *t = [k stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (!t.length || g_ui_nvs >= 32) continue;
        if (![g_shmap[t] isEqual:@"vertex"]) { MLOG("[RED] UI squeeze: %s is not a vertex shader key of this game's shader map; ignored", t.UTF8String); continue; }
        strlcpy(g_ui_vs[g_ui_nvs++], t.UTF8String, sizeof g_ui_vs[0]);
    }
    if (g_ui_nvs) MLOG("UI squeeze: %d UI vertex shaders (%s)", g_ui_nvs, e ? "DM_DUO_UI_VS" : "the profile's ui_vs");
}
static int ui_on_canvas(void) {   // the draw's colour 0 is a texture the present shows
    if (R.rt.n <= 0 || !R.rt.color[0]) return 0;
    if (xv_present(R.rt.color[0]->serial)) return 1;
    return g_ui_cw && R.rt.color[0]->d.width == g_ui_cw && R.rt.color[0]->d.height == g_ui_ch;
}
static int ui_is_ui(const char *vs) {
    if (g_ui_off < 0) { const char *e = getenv("DM_DUO_UI_SQUEEZE"); g_ui_off = e && !strcmp(e, "0");
                        const char *l = getenv("DM_DUO_UI_LOG"); g_ui_log = l ? atol(l) : 0; }
    if (g_ui_off || !vs) return 0;
    double k = ui_k();
    if (k > 0.999 && k < 1.001) return 0;             // 16:9 within 0.1 %: bit-identical to today
    ui_vs_load();
    int hit = 0; for (int i = 0; i < g_ui_nvs && !hit; i++) hit = !strncmp(vs, g_ui_vs[i], 8);
    return hit && ui_on_canvas();
}
static void ui_squeeze(NSUInteger tw, NSUInteger th, double *ux, double *uy) {
    *ux = *uy = 1;
    if (!g_ui_draw || !tw || !th) return;
    double k = ui_k();
    if (k > 1) *ux = k; else *uy = 1 / k;
}

// next to present_viewport (:11118), after present_crop_rect (:11135):
static void ui_note_present(id<MTLTexture> src, const int crop[4], NSUInteger dw, NSUInteger dh) {
    NSUInteger r[4]; if (!dw || !dh || !present_crop_rect(src, crop, r)) return;
    MTLViewport vp = present_viewport(r[2], r[3], dw, dh);
    ui_k_set(((double)vp.width / r[2]) / ((double)vp.height / r[3]));   // stretch: the anisotropy; crop / off: 1
    g_ui_cw = r[2]; g_ui_ch = r[3];   // the canvas serials are the ones present_enqueue recorded (xv_present), not a snapshot's
}
```

In `draw_`, after `pr` is resolved (before `rp_begin_ex`, because `first_draw_covers` runs
inside it):

```c
g_ui_draw = ui_is_ui(pr->sh[0] ? pr->sh[0]->key : NULL);
```

and in the viewport/scissor block:

```c
NSUInteger tw = g_pass.tw, th = g_pass.th;
double ux, uy; ui_squeeze(tw, th, &ux, &uy);
{ MTLViewport v = S.has_vp ? (MTLViewport){S.vp[0][0], S.vp[0][1], S.vp[0][2], S.vp[0][3], S.dr[0], S.dr[1]} : (MTLViewport){0, 0, tw, th, 0, 1};
  if (ux != 1) { double cx = tw / 2.0; v.originX = cx + (v.originX - cx) / ux; v.width /= ux; }
  if (uy != 1) { double cy = th / 2.0; v.originY = cy + (v.originY - cy) / uy; v.height /= uy; }
  ... origin_ll flip, swizzle, g_ed dedupe, unchanged ... }
MTLScissorRect sc = {0, 0, tw, th};
if (R.has_sc && !S.rast_discard) {
    long x0 = ..., y0 = ..., x1 = ..., y1 = ...;
    if (ux != 1) { double cx = tw / 2.0; x0 = lround(cx + (x0 - cx) / ux); x1 = lround(cx + (x1 - cx) / ux); }
    if (uy != 1) { double cy = th / 2.0; y0 = lround(cy + (y0 - cy) / uy); y1 = lround(cy + (y1 - cy) / uy); }
    ... existing clamps and empty test, unchanged ...
}
```

The squeeze is applied in the same top-left space the viewport is built in; the lower-left
flip (`:9527`) and the `NEGATIVE_Y` swizzle (`:9530`) commute with a squeeze about the centre,
so they stay after it.

A diagnostic worth having from the first run (it is how the list is found for a new game):

```c
if (g_ui_log-- > 0) MLOG("[ui] F%llu pass %llu vs %.8s count %d squeeze %.3f/%.3f target %lux%lu ser %llu oncanvas %d",
    (unsigned long long)atomic_load(&g_cur_frame), g_stat_pass, pr->sh[0] ? pr->sh[0]->key : "-",
    dw ? dw->count : di->count, ux, uy, (unsigned long)tw, (unsigned long)th,
    R.rt.n ? R.rt.color[0]->serial : 0, ui_on_canvas());
```

`DM_DUO_UI_LOG=<frames>` arms it for that many frames.

### Why the proofs must be told

Two pass-level optimisations assume a draw's viewport is the whole target:

- `first_draw_covers` (`:7401`) passes `S.has_vp`, `S.vp`, `R.sc` and the attachment's size to
  `nvn_cover` (`:7419`) to elide a load. With a squeezed viewport the draw no longer
  covers the attachment, and eliding the load would drop the pass's previous contents.
- `uv_proof` (`:8549`) proves a 1:1 texel mapping from `S.vp == target` (`:8556`) for the
  on-chip read merge.

Both must return "not provable" for a squeezed draw (`g_ui_draw`). Everything else in the
draw path is per-draw state and needs no change. Conservative is fine: the proofs only cost a
load or a pass split.

## 5. Per-game data

### What is needed

A list of the game's **UI vertex shader keys**: 8-hex-character prefixes, exactly the
control-section keys in `dm/games/<id>/shader_map.tsv` column 4 (column 3 is the stage; the
key must be a `vertex` row). `shader_map.tsv` is the key inventory and the validation source;
it is *not* the place to store the selection, because `dm/gfx/tools/shader_split.py`
regenerates the file and cannot know which shader draws the HUD.

Placement: a profile key in `game.tsv`, compiled into `game_profile.h`:

```
ui_vs	8bb3ac2696d5ac6e
# HUD, menus, text: the screen-space sprite shader (a hypothesis — verify with DM_DUO_UI_LOG before shipping)
```

`dm/games/game.py` `header()` emits `#define DM_GAME_UI_VS {"8bb3ac2696d5ac6e", ...}` (and
`{NULL}` when the key is absent, so every other profile compiles unchanged). `ui_vs_load`
rejects keys that are not vertex keys of the map with a `[RED]` line — a typo cannot silently
squeeze nothing.

Alternative placement, if a profile rebuild per experiment is unwanted: a hand-authored
`dm/games/<id>/ui_vs.tsv` beside `shader_map.tsv`, read at runtime from
`[g_shmap_path stringByDeletingLastPathComponent]`. It costs one line in
`dm/ios/tools/build_ipa.sh:81` to ship it inside the app; the profile key avoids that.

`DM_DUO_UI_VS=key,key` overrides both for a single run.

### Scott Pilgrim

`dm/games/0100394011C30000/shader_map.tsv` has 18 vertex keys; two carry their source name:

| key | source |
|---|---|
| `04852552` | `/enginedata/switch/shaders/mvppos2_col_tex2.vs` |
| `8bb3ac26` | `/enginedata/switch/shaders/screenpos2_col_tex2.vs` |

Model-view-projection positions against screen positions: if the engine draws its HUD in
screen space, `8bb3ac26` is the first candidate and `04852552` the world. That is a
hypothesis, not evidence — the game has not been run under the log. Start with
`DM_DUO_UI_LOG=200` plus `DM_NVN_PASSDUMP` on one HUD-heavy frame and list the keys drawn into
the swapchain texture (the `ser` in the log line is one of the swapchain texture serials
the host registers at window setup, `hle_nvn.c:1289`).

### Finding the list for a new game

1. `DM_DUO_UI_LOG=<frames>` on a frame with the HUD, menu and a world scene each.
2. Keep the keys that appear only with the HUD/menus and that draw into the swapchain
   texture; check the vertex count (quads: 4 or 6) and the blend state.
3. Put them in `ui_vs`; check with a screenshot that the world did not change.
4. If a key appears in both the HUD and the world, it cannot go in the list (risk 1).

## 6. Interaction with the present

The factor is taken from the present itself, not from `DM_DUO_ASPECT`, so there is one source
of truth and no second constant to keep in sync:

`k = (vp.width / cw) / (vp.height / ch)`, from `present_viewport` and the crop rectangle.

| `DM_PRESENT_FILL` | present viewport | k | UI |
|---|---|---|---|
| `stretch` | the whole drawable | 1.2505 on the Duo | flattened by 1.25 about the canvas centre |
| `crop` | uniform aspect-fill | 1 | untouched (cropping does not distort) |
| unset | uniform, letterboxed | 1 | untouched; the `<1 %` whole-canvas exception at `:11132` gives k within 1 %, and then the HUD is squeezed by that same ≤1 % — correct, the present does stretch it there |

Consequences:

- **The HUD occupies the middle 80 % of the canvas height.** On the Duo it is drawn into
  canvas y 108…972 (864 px) and the present scales that to 2007×(864/1080) ≈ 1606 px, so
  ~200 px of world shows above and below the HUD. The HUD keeps the full canvas width.
- **Apparent scale is uniform 1.486.** The squeezed HUD is shown at 1.486× its designed size,
  the same scale the world is shown at; text and sprites stay sharp (one extra resample).
- **MetalFX**: the present draws the scaled picture 1:1 into `vp` (`:11249`, `:11266`); k is
  computed from that `vp`, so the scaler is irrelevant to the squeeze.
- **Present snapshots** (`present_snap`, `DM_PRESENT_SNAP`): `present_enqueue` swaps in a
  snapshot `tex_t` (`:11783`) whose serial is synthetic, so the canvas check must use
  `xv_present` (recorded at `:11766`, before the swap) and the crop dimensions, never the
  presented texture's serial.
- **Crop**: use `present_crop_rect`'s `r[2]`/`r[3]`, not `src.width/height`.
- **First frame / resize**: k is 1 until the first present has been seen, so one frame of
  distortion after a launch or a rotation. Acceptable; a re-note from the layer's
  `drawableSize` at enqueue time would remove it if it ever matters.
- **`DM_DUO_UI_K=<k>`** (diagnostic) sets k directly, for the replayer, which may present no
  drawable and would otherwise keep k = 1.

## 7. Risks

1. **HUD and world share the vertex shader.** This build is a 2D game; sprite and HUD quads
   plausibly run the same shader. A key list would then squeeze the world too — a wrong
   picture, not a wrong HUD. Detection: the `[ui]` log (a key present both with and without
   the HUD). Mitigations, in order: (a) a UBO fingerprint as a second column (the HUD's ortho
   projection / screen-size constant, read from `S.ubo[0][reg]`), (b) the BOTW rule — squeeze
   every quad drawn into the canvas after the frame's scene draw (`nvn_obj.h:210-212`),
   (c) leave the HUD stretched.
2. **Markers that follow world objects** (off-screen arrows, damage numbers, target
   reticles). Their positions are computed in world screen space and must not move; if they
   share the HUD shader they are displaced toward the centre by up to `(1 - 1/k)·y` — ~10 %
   of the height at the top and bottom edges on the Duo. Excluding their key is the correct
   fix; if they cannot be separated, they need a game-side or matrix-side change.
3. **UI drawn into the world pass, interleaved.** The per-draw viewport switch handles that
   correctly, but the two pass proofs above assume a full-target viewport and must be disabled
   for squeezed draws. Any future pass-level optimisation that bakes in the viewport inherits
   the same requirement.
4. **Pixel-snapped positions.** UI is laid out on integer canvas pixels; after a 1/1.25
   viewport scale, edges land on fractional pixels, so text is slightly softer and 1 px seams
   can appear between quads that share an edge (each quad's rasterisation rounds
   independently). Nothing can be done from the host; the present's bilinear stretch already
   resamples everything once.
5. **Full-screen UI effects** (fades, dimming, transition curtains) are squeezed into the
   middle 80 % and leave the world undimmed at the edges. The reference needed the
   `ui_cover_all` exception for exactly this (`nvn_mtl.m:10397`, `:11459`). First cut: do not
   list the effect shaders; add the exception if a fade shows the seam.
6. **Scissor rounding.** `lround` on both edges can leave a 1 px strip or clip a 1 px border;
   the reference clamps after rounding and drops the draw when the rect is empty. Same here.
7. **Canvas identification.** If the game renders into an offscreen 16:9 texture and blits to
   the swapchain, neither `xv_present` nor the exact-dimension fallback matches. The fallback
   would then have to compare the *aspect* (`tw/th` against the presented aspect), which risks
   matching a same-shape UI render texture. The `[ui]` log's `oncanvas` field settles it per
   game; do not guess.
8. **`nvnCommandBufferDrawTexture`** (`draw_tex`, `:10142`) composites with its own viewport
   and is not covered. If the HUD goes through it, it needs the same transform there.
9. **Edge-anchored HUD layout.** A HUD anchored to the screen edges moves inward by 10 % of
   the height; on a 1.25 panel that is visible but far milder than the 21:9 case the reference
   was built for.
10. **Games that already lay out for the panel** (or a future native-size canvas,
    `duo/DESIGN.md` "Bigger canvas") want no squeeze: `DM_DUO_UI_SQUEEZE=0` and an empty
    `ui_vs`.

## 8. Verification

- **Offline (no device, no install):** build the host, then `regress.py replay` a capture of a
  HUD frame with `DM_DUO_UI_K=1.2505` and without it, and compare the two screenshots: the
  world must be pixel-identical, the HUD's bounding box 20 % shorter and centred.
  `first_draw_covers` / `uv_proof` regressions show up as `[RED]` lines or a changed picture.
- **On device, when the main agent allows it:** one screenshot per screen (gameplay, menu),
  and the existing `present viewport …` log line (`:11158`) for the canvas/drawable numbers.
- **Static checks:** the profile header compiles for every game (`DM_GAME_UI_VS` default
  `{NULL}`), `test_env_switches.py` passes once the four rows exist, and
  `docs/env_switches.tsv` names no unread switch.

## 9. What this design does not do

- It does not change the camera, the canvas, the projection or the UI layout.
- It does not fix HUD *layout* for the panel (safe areas, edge anchoring) — only the shape.
- It does not touch the world, and it must not: a squeezed world draw is the failure mode of
  risk 1.
- It does not cover `draw_tex` or the compute/geometry paths.
