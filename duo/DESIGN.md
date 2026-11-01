# Duo aspect design

## The mechanism (verified in a shipping implementation)

MacNativeGames' iPhone build of TotK fills the screen by patching **four sites** in
`main`, not by resizing the canvas:

- 2 camera sites: where the aspect ratio is handed to the perspective projection
- 2 viewport sites: the width/height division

At each site the original instruction (which produces the game's 16:9 ratio) is kept,
but execution is diverted to an 8-word stub that runs it and then, if a runtime ratio
is set, replaces the result. The present pass stretches the 16:9 canvas back over the
drawable, so the world is correct and only the HUD needs flattening.

Their site lists, which are offsets in the **same original `main`** we rewrite:

| Version | Sites | Meaning |
|---|---|---|
| TotK 1.4.3 | `0x628c74, 0xb43460, 0x1ff04f4, 0x253fbb0` | camera update, camera setup, viewport ×2 |
| TotK 1.2.1 | `0xcb4b10, 0x12521cc, 0x19b36f0, 0x1ecdf68` | camera ×2, viewport ×2 |

## Site instructions

A site holds one of two forms (checked before writing anything):

```python
(ins & 0xffe0fc00) == 0x1e201800   # fdiv s<d>, s<n>, s<m>     (the ratio computed)
(ins & 0xffc00000) == 0xbd400000   # ldr  s<d>, [x<n>, #imm]   (the ratio from rodata)
```

Both leave the ratio in `s<d>`, so the stub only has to overwrite that register.

## The stub (8 words, ported from the reference)

```
0: <the site's original instruction>          ; the game's own ratio into s<d>
1: str  x10, [sp, #-16]!                      ; scratch on the stack: no liveness assumed
2: adrp x10, <data page>
3: ldr  w10, [x10, #<slot>]                   ; the runtime ratio, float bits
4: cbz  w10, +8                               ; 0 = off, keep the game's value
5: fmov s<d>, w10                             ; the drawable's ratio
6: ldr  x10, [sp], #16
7: b    <site + 4>                            ; the instruction after the site
```

Encoders (from `dm/tools/duo_aspect.py`):

```python
b(from, to)      = 0x14000000 | ((to - from) >> 2 & 0x3ffffff)
adrp(reg, at, to)= 0x90000000 | ((pages & 3) << 29) | ((pages >> 2) << 5) | reg
```

Both return 0 when out of range; the installer refuses rather than guessing.

## Where the ratio lives

The frame-step state page already exists for TotK and BotW (`patch_nso.py`:
`FS_STATE_OFF = KEY_PAGE_OFF + 0x4000`, zeroed in the file, read-write at run time).
Offsets `+0x00…+0x30` are taken by the frame step; the Duo aspect slot is **`+0x40`**
(float bits of width/height, 0 = the game's own ratio).

The loader writes it from the drawable size the iOS front end reports, so a rotation
or a resize needs no rebuild.

## Present

`DM_PRESENT_FILL=stretch` (from branch `ios-fullscreen`) fills the drawable with the
canvas. With the camera patch in place the picture is no longer distorted — the extra
width is real world, squeezed into the canvas and unsqueezed here.

## UI (second half of the per-game work)

The HUD, menus and markers are laid out in the 16:9 canvas, so the present stretches
them by 1.25. Options, in order of effort:

1. **Ship it stretched** and judge on the device — the Duo's 1.42 is much closer to
   16:9 than 21:9, so this may be tolerable for a first build.
2. **Flatten the UI pass** (what the reference does): identify draws in the UI pass and
   pre-squeeze them horizontally so the present's stretch restores them.
3. **Patch UI layout** (what the reference notes is still incomplete): markers that
   follow world objects and pixel-snapped positions need their own routines.

## Finding the sites for a new game

`duo/tools/find_aspect.py <module.nso>` does the first pass automatically: it decodes
the module and lists every `fdiv`/`ldr s` that could be the ratio, scored by the sead
projection pattern (`str s, [x, #0xac]` before, `str s, [x, #0xb0]` after). Validated on
TotK 1.4.3: all four known sites (`0x628c74`, `0xb43460`, `0x1ff04f4`, `0x253fbb0`)
are in its output, the two camera ones at the top score. It narrows a 45 MB module to a
few dozen candidates; picking the final four still needs a device test (or a reference
like the one we have for TotK).

The manual method, if the finder's output is ambiguous:

The reference's method, reproducible without their code:

1. `python3 dm/tools/patch_nso.py` already surveys rewrite sites; start from the
   extracted `main`.
2. Search the text for the 16:9 constant: `0x3FE38E39` (1.7777778f) in rodata and
   `fmov s*, #1.7777778` immediates.
3. For each candidate, look at the surrounding block for `str s, [x, #0xb0]` (sead
   camera projection) or a width/height `fdiv`.
4. Verify with a watchpoint or by patching one site and observing the projection.

## Bigger canvas (future)

The reference keeps the 16:9 canvas, so 1920 px across covers 2853. Rendering a
2048 × 1440 canvas (1.4222, within 0.05 % of the Duo) would give native sharpness and
remove the need for the present stretch — but the canvas size is chosen by the game
and feeds many allocations, so it is a larger, separate change. Tracked here, not
attempted first.

## Licensing

The mechanism is reimplemented from MacNativeGames (MIT) with attribution in the file
headers. The community TOTK-Ultrawide mod is GPL and none of its code is used; only
observable addresses and behaviour are reproduced, as the reference project also did.
