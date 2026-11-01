# Duo status — 2026-10-30 (afternoon)

## Verified on the device: canvas = 1920x1350 (the Duo's 1.4222 vs 1.4215)

The game renders at the panel's aspect, so nothing is stretched and the present does no
scaling beyond 1:1. Proof is the device log line `WindowInitialize ... first 1920x1350`.

| Game | Method | Rows | State |
|---|---|---|---|
| Scott Pilgrim | `movz` height immediates (4) | `duo/research/res.tsv` | **verified on device** |
| Luigi's Mansion 3 | canvas-record constructors (86) | `duo/research/res.tsv` | **verified on device** |
| Super Mario 3D World | float pair `1080.0f -> 1350.0f` (2) | `duo/research/res.tsv` | **verified on device** |
| Wonder | float pair (1) | `duo/research/res.tsv` | patch did not move the canvas; needs the next writer (`duo/games/010015100B514000-canvas.md`) |
| Burnout | immediates (3) | `duo/research/res.tsv` | not built yet |
| DQ VII | canvas size is a UE4 RHI argument | — | constant patch only |
| TotK | camera sites + present stretch | `duo/research/games.tsv` | full screen, HUD 1.25x tall |

Installed on the Duo right now: TotK, Scott Pilgrim, 3D World (free Apple ID: 3 apps max).

## Signing

Xcode's account session is currently unavailable (`No Accounts`), so automatic
provisioning fails for new bundle IDs. Manual signing with an existing profile works
(`CODE_SIGN_STYLE=Manual`, `CODE_SIGN_IDENTITY=Apple Development: …`,
`PROVISIONING_PROFILE_SPECIFIER=<uuid>`). Sign in to Xcode → Settings → Accounts when
convenient to restore automatic signing.

## Still to do

- Wonder: find the live canvas writer (the float pair is patched but not read at boot).
- Burnout: build and verify with its three rows.
- DQ VII: canvas site is dynamic; the constant row is the fallback.
- FF Tactics: 1.4.0 update is on the union drive; build against the registered profile.
- HUD squeeze for the const-patch games: `duo/design/uisqueeze.md`.
