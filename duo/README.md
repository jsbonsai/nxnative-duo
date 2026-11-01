# nxnative-duo

A fork of [nxnative](https://github.com/seedds/nxnative) tuned for one device: the
**iPhone Duo** (2007 × 2853, 1.4215:1). The point is not "more games" — it is that
every supported game fills the Duo's panel with correct proportions, and that the
per-game work needed to get there lives in one place.

Upstream stays upstream: `upstream/main` is tracked read-only, our work is on `duo`.

## What "fills the panel" means here

Not a stretched 16:9 picture. The camera's projection takes the **drawable's** aspect,
so more of the world is visible at the sides and shapes keep their proportions. The
game still draws into its own 16:9 canvas; the present pass widens that canvas back
over the drawable. That is the same approach MacNativeGames ships for TotK on iPhone
(MIT; mechanism reused with attribution, their code is not copied).

Two consequences, stated up front:

- **The canvas is the resolution.** 1920 px across covers a 2853 px drawable, so the
  picture is that much softer across than a native render. A true wider canvas is a
  separate, larger change (see DESIGN.md, "Bigger canvas").
- **The HUD is drawn in 16:9.** Widening the present stretches it horizontally by
  1.778/1.4215 ≈ 1.25 until the UI pass is flattened back. That is the second half of
  the per-game work, and it is why this is a fork and not a patch.

## Per-game model

Everything game-specific is a row in `duo/research/games.tsv` plus a `DUO_ASPECT` function in
`dm/games/<title id>/patches.py`. The framework (`dm/tools/duo_aspect.py`) emits the
stubs and asserts the site instructions; the registry only says where.

| Piece | Where |
|---|---|
| Site table (build ID → offsets) | `duo/research/games.tsv` |
| Stub installer | `dm/tools/duo_aspect.py` |
| Hook into the rewriter | `dm/tools/patch_nso.py`, gated by `DM_DUO=1` |
| Ratio at run time | state page `+0x40`, written by the loader from the drawable |
| Present | `DM_PRESENT_FILL=stretch` (already in the tree, from the `ios-fullscreen` work) |

## Status

| Piece | State |
|---|---|
| `duo_aspect.py` stub encoder | written, unit-tested (`dm/tools/tests/test_duo_aspect.py`, 12 tests) |
| `patch_nso.py` hook (`DM_DUO=1`) | written, gated: default builds unchanged |
| Loader ratio (`DM_DUO_ASPECT` → state +0x40) | written, compiles |
| Full-screen present (`DM_ASPECT`, `DM_PRESENT_FILL`) | written, compiles |
| TotK 1.4.3 sites | known (`0x628c74, 0xb43460, 0x1ff04f4, 0x253fbb0`), not yet built |
| BotW 1.9.0 sites | unknown — find with DESIGN.md once the NSO is here |
| Luigi's Mansion 3 1.4.0 | unknown; different engine, expect other instruction forms |

Nothing here has run on a device yet: no game files, no physical Duo.

## Designs (scoped, not built)

- `duo/design/dualscreen.md` — top half picture / bottom half controls, fold-aware.
  Evidence: iOS 27 exposes `UIHinge`/`UIHingeInteraction` with status + angle only
  (no hinge position), so bounds-change is the fallback; Duo inner panel is
  2007x2853 @3x = 669x951 pt.
- `duo/design/ingamemenu.md` — overlay above the Metal layer; fps target, render scale
  and the Duo aspect are live via the state page, the rest apply next start.
- `duo/design/framegen.md` — 120 Hz is reachable today only through
  `DM_PRESENT_INTERVAL=display DM_PRESENT_HZ=120 DM_PRESENT_LINK=2`; true MetalFX
  interpolation needs motion vectors a 2D sprite game does not provide.

## Building

```sh
DM_DUO=1 python3 scripts/build_ipa_from_nsp.py <game folder> -k <prod.keys> \
    --env-file duo/duo.env
```

`duo/duo.env` sets `DM_ASPECT=fill`, `DM_PRESENT_FILL=stretch`, and the Duo's ratio.
