# Aspect-site scans

`duo/tools/find_aspect.py` narrows a module to candidate camera/viewport sites, scored
by the sead projection pattern (`str s, [x, #0xac]` before, `str s, [x, #0xb0]` after).
A candidate is only a lead: it still needs a device test, or a reference.

| Game | Build ID | fdiv in text | Scored candidates | 16:9 constant | Note |
|---|---|---|---|---|---|
| TotK 1.4.3 | `277178b7…` | 140,559 | 110 | `0x2d02534` | **validated**: all four known sites appear, camera pair top-scored |
| 3D World (derived build) | `891687f0…` | 36,622 | 7 | `0xda6934` | NintendoWare layout, no score-5 pattern |
| Sea of Stars | `092cd60e…` | 92,202 | 71 | none | Unity: aspect likely derived from the render target, not a constant |
| DQ VII 1.1.0 | `ab060209…` | 131,726 | 37 | `0x5183ddc` | Unreal: `r.ScreenPercentage`/viewport path likely |
| Burnout Paradise | — | — | 17 | — | provisional profile; needs the build ID from its scan header |
| Star Ocean 2R | — | — | 69 | — | provisional profile |
| Galaxy 2 | — | — | 22 | — | Hagi/Vulkan: shaders are captured at run time |

Raw scans: `duo/games/<titleID>-aspect.txt`.

## What the numbers mean

- **TotK** is the only game with a verified site set (`duo/research/games.tsv`), because the
  reference project publishes the four offsets and we reproduced them.
- **3D World** is the next best candidate: seven sites, two of which carry the
  projection-store pattern.
- **Unity (Sea of Stars, TMNT)** probably needs a different lever: if the engine derives
  the projection from the render target size, the patch belongs at the canvas size, not
  the camera. No 16:9 constant exists in its main, which supports that.
- **Unreal (DQ VII)** has a 16:9 constant and a viewport path; the constant is a good
  starting point.

## Method

```sh
duo/tools/find_aspect.py <extract>/ExeFS/main --window 4 > duo/games/<id>-aspect.txt
```

Then pick 2 camera + 2 viewport candidates, add a `duo/research/games.tsv` row, rebuild with
`DM_DUO=1`, and check on the device: the world must widen, not stretch.
