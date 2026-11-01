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
