# Research notes: per-game camera and canvas findings

These tables record what was found for each game build while looking for its Duo camera patch, including the
candidates that did NOT work. **No build reads them.** A build applies a Duo patch only from a patch pack
(`duo/patches/README.md`, the contract): to ship a finding, turn its row into a `*.duopatch.json` after checking it
on a device.

| File | What it is |
|---|---|
| `games.tsv` | build ID → camera aspect sites / 16:9 constant / notes (the patch-pack `camera` block in TSV form) |
| `res.tsv` | build ID → render-size word rewrites (the pack's `canvas` rows); mostly `#off`: the canvas route breaks games |
| `verified.tsv` | what was checked on a device, and how |

Per-game write-ups are in `duo/games/<title id>-camera.md` / `-canvas.md`. Results so far (2026-10-30): Tears of the
Kingdom 1.4.3 — shipped as `duo/patches/totk-1.4.3.duopatch.json`; Super Mario 3D World, Wonder, Galaxy 2 — looked
right on a Duo but are not shipped (opt-in packs only, owner's call); DRAGON QUEST VII Reimagined 1.2.0 — **does not
work** (owner, Letterbox vs Stretch on the Duo: characters taller in Stretch); Link's Awakening 1.1.0 — sites found,
never tried; Luigi's Mansion 3, Demon Slayer — no native site; Burnout, AC Ezio — the games do not run yet.

## Toy Story double-pack cartridge (2026-10-30)

One XCI holding two games, plus one update per game; needs prod.keys with master_key_15.
- **Toy Story: Retro Roundup! 1.0.4** (`0100F98025BC0000`, main `c41be91d…` with the update): **plays on the Duo** after the
  bring-up (profile `dm/games/0100F98025BC0000`, SDK 21.4.4 address-region fix, GL layer work); owner: "plays perfectly, 10/10".
  Before the bring-up it built and installed, then **aborted at startup**: `StandardAllocator::Initialize(nullptr, 7.91 GB)` gets 4.06 GB (the
  alias region's room), then `nn::diag abort` at `sdk+0x141b9c` called from `main+0x2c8b3c`. Bring-up: a larger address region
  for this title (profile memory keys, `region_check`; maybe the iOS extended virtual addressing entitlement).
- **Toy Story 3 Complete Edition 1.0.3** (`01001DC025BC4000`, main `b2f8dcb5…`): **plays on the Duo** (provisional profile) once
  the Avalanche reader (front-EOCD zips holding `.tfx` effects: 0 -> 3,070 shaders) was added; gameplay fine, **video audio
  corrupted** — upstream `ec9c3aa` "Restore Vorbis movie audio after Flush (#787)" is the likely fix (in the upstream merge).

## Retest on the merged engine (2026-10-31, iPhone Duo, iOS 27.2)

Upstream nxnative merged as of 2026-10-31 (5474c6f); every game below was rebuilt and booted on the phone with the merge,
launcher skipped, 60 s and 150 s screenshots, log pulled. Evidence per game in /tmp/duotest on the Mac at the time; the log
lines quoted here are the decisive ones.

| Game | Frames | Errors | Note |
|---|---|---|---|
| Tears of the Kingdom 1.4.3 + Duo pack | ~ | 0 | `DM_DUO_ASPECT=2853:2007`, "the camera takes the drawable's shape"; first launch prepares pipelines |
| DRAGON QUEST VII Reimagined 1.2.0 | 9,000 | 0 | 59 fps at the title, "save data created!" (fresh save: the app had been removed) |
| Toy Story: Retro Roundup! 1.0.4 | 7,200 | 0 | 60 fps; menu idle ~2 min starts a live PlayStation demo that closes the game (known) |
| Super Mario Bros. Wonder 1.0.0 | 9,300 | 0 | one benign `[RED] SetRenderEnableConditional` note |
| Luigi's Mansion 3 1.4.0 | 9,000 | 0 | 60 fps at the title; same benign `[RED]` note |
| Super Mario Galaxy 2 1.0.0 | 7,800 | 0 | 60 fps at the title; two shaders missing from the library, one Vulkan stage unimplemented (may show as a missing effect) |
| Super Mario 3D World + Bowser's Fury 1.2.1 | 8,800 | 0 | no `[RED]` lines |
| Toy Story 3 Complete Edition 1.0.3 | 600+ | 0 | boots and plays (owner); video audio distorted (possibly the dump) |
