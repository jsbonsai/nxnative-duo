# Duo backlog

Ordered by priority. Each item says what exists already, what is missing, and how to know it is done.
P1 work in progress lives in `duo/STATUS.md` and the design docs; this file is for parked items.

## P3 — Synced saves between the Mac port and the iPhone (Duo) port of a game

**Ask (owner, 2026-10-30):** play a game on the Mac, carry on from the same save on the Duo, and back.

**What exists (upstream nxnative, already in our tree — no new engine work needed for the basic case):**

| Piece | Where | What it does |
|---|---|---|
| Sync engine | `dm/host/save_sync.c`, `dm/host/save_sync.h` | Packs the game's committed save into one file `<folder>/<title ID>/save.dmsync` (header `DMSYNC1`, SHA-256 over every entry, refuses a truncated file); on start pulls the newer one, on commit pushes. Plain C + CommonCrypto: the Mac launcher links the same file. |
| Switch | `DM_SAVE_SYNC` (`docs/env_switches.tsv:263`) | The folder to sync through; `icloud` = iCloud Drive/nxnative Saves on the Mac; unset / `0` = off. |
| iPhone side | `dm/ios/Sources/CloudSaves.{h,m}` | The player picks an iCloud Drive folder in the launcher's **Cloud saves** row; the app keeps its security scope for the session and sets `DM_SAVE_SYNC` before the game starts (`CloudSaves.m:68-74`). Downloads through `NSFileCoordinator` (`SaveSync.m`). |
| Mac side | `dm/mac/launcher.c`, `dm/mac/pack_app.py` | The Mac app's settings window picks the folder. |

**Why it is off on our Duo builds today:**

1. Our env files set `DM_LAUNCHER=0` (`duo/test.env`, `duo/duo.env`), so the launcher — the only place the iPhone app lets you pick the cloud folder — never shows.
2. We have never built the **Mac** app of a game in this tree (`--platform mac` of `scripts/build_ipa_from_nsp.py`); the pairing needs both apps.
3. Bundle IDs: `bin/duo` builds `org.nxnativeduo.<team>.t<title id>` with a free Personal Team. iCloud Drive access from the iPhone app uses the document picker (security-scoped bookmark), not an iCloud container entitlement, so a free team should work — **unverified**.

**To do:**

- [ ] Add a **Cloud saves** row to the in-game ⚙ menu (`dm/ios/Sources/DmGamepad.m`), reusing `CloudSaves.m`'s picker, so it works with `DM_LAUNCHER=0`. A folder picked mid-game applies at the next start (the host reads `DM_SAVE_SYNC` once).
- [ ] Build the Mac app of one game (LM3 is a good candidate: it runs plain) and pick the same iCloud Drive folder there.
- [ ] Check that the per-game Duo patches (`duo/research/res.tsv`, `duo/research/games.tsv`) do not change the save format (they patch rendering only; they should not).

**Done when:** a save made on the Mac (e.g. LM3 after the first save point) loads on the Duo after relaunch, and a later save made on the Duo loads on the Mac; the log shows the `[dm] save sync:` pull/push lines on both; no `[RED] save sync` lines.

**Risks:** two devices playing at the same time (the engine keeps the newer file; the other side's progress since its last pull is lost — the engine's own rule, read `save_sync.h` before changing it); iCloud's download latency on first start (the iPhone side waits through `NSFileCoordinator`).

## P3 — Stretched HUD on games whose world is fixed

The world is correct (camera aspect patched, `duo/design/aspect.md`), the HUD is 1.25x tall because the game draws it
into the 16:9 canvas and the present stretches that to the screen. Two experiments on 3D World changed nothing (the
`nn::ui2d` UI-resolution table; `GetScreenHeight()`); the HUD's own projection is not visible in a `passdump`
(scene and UI are pre-built NVN command lists). Owner: "not a big deal", so parked. Done when a NintendoWare title's
HUD measures round (see `duo/tools/hudcheck.py`). Options if revisited: trace command-list replay; or letterbox
(`⚙ → Picture fill → Letterbox`) which has no stretch anywhere but adds bars.

## P3 — On-screen controls, further options (the editor exists, `duo/design/dualscreen.md` §0.9a)

- [ ] Per-orientation offsets (today one set of offsets for both landscape and split portrait).
- [ ] Control **size** (a scale per control, not just position).
- [ ] A "keyboard on the bottom half" mode for games that type (the guest's software keyboard is an in-game overlay today).

## P2 — Device verification of the camera patches already found

Burnout Paradise (`0x13d2c`, `0x1610ac`), AC Ezio (`0xff4ef0`, the movz+movk kind), DQ VII (`~0x10384bc`, the inverse
kind), Galaxy 2 (`0x2fe2e0`, `0x2fe4a0`, `0x2fe5f8`): each needs build + install (retarget the bundle id, see
`duo/design/aspect.md` §6a) + a drive to gameplay + `hudcheck.py`/NCC. Registered rows are in `duo/research/games.tsv`.
