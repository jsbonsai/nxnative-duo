# Duo Builder — the public release plan

Status: plan (2026-10-30). Goal: a non-technical person who is willing to spend **an afternoon** goes from
"a Mac, an iPhone Duo, a Switch game dump and prod.keys" to **the game running on the Duo**, without an LLM,
a terminal, or reading a wiki.

## 0. What the user must bring (and what we never touch)

* **Their own game**: NSP files (base + update) or the folder holding them.
* **Their own `prod.keys`**.
* A Mac, a USB cable, a **free Apple ID** (no paid developer account needed).

We ship **no** game content, **no** keys, and the tool never downloads either. Same rule as the upstream project:
it is not an emulator — the game's own code runs on the device; the tool only rebuilds its executable and assets
for the phone. First line of the README and a checkbox in the app.

## 1. The three picture modes (pick one, no second thoughts)

| Mode | What it does | Who should pick it |
|---|---|---|
| **Letterbox** (default) | unmodified game, correct picture, black bars above/below | everyone on their first try; nothing can break |
| **Crop** | unmodified game, fills the panel, keeps proportions, cuts the sides | people who want edge-to-edge |
| **Duo (experimental)** | only for games in our registry: the camera is rebuilt for the Duo's aspect, so the 3D world fills the screen correctly; **some HUD elements look 1.25x tall** | the demo; clearly labelled experimental, per game |

The registry (`duo/research/games.tsv`, one row per game build) is what makes a game eligible for **Duo (experimental)**;
the app shows "supported / experimental" next to the game name, and hides the option for games we have no patch for
(or where the patch is known to hurt, e.g. Luigi's Mansion 3's canvas route).

## 2. The flow the user sees

1. **Setup (once, guided)**: Xcode installed? Apple ID signed into Xcode? device paired and trusted?
   → a checklist with big buttons and the two facts that surprise everyone: **7-day expiry** and **3 apps at a time**
   on a free account.
2. **Drop**: the app has one window. Drop the NSP folder (or the .nsp files) and `prod.keys` (or a folder containing it).
3. **Pick the picture mode** (three big buttons; Letterbox preselected).
4. **Build & Install**: one button. Progress in plain language ("Reading the game… Rebuilding its executable…
   Compiling shaders (this is the long one, 10–40 min)… Installing on the Duo…").
5. **Done**: "Wonder is on your Duo. Open it on the phone." with the two limitations spelled out.

No Xcode steps, no scheme selection, no signing dialogs: the app runs `xcodebuild -allowProvisioningUpdates`
with the team it finds in Xcode's accounts, then `devicectl device install app`. If signing fails, it says exactly
which one thing to fix ("Sign into Xcode with your Apple ID: Xcode → Settings → Accounts → +").

## 3. Architecture

```
Duo Builder.app  (SwiftUI, macOS 14+)
 ├─ DropView          NSP folder + prod.keys, drag & drop
 ├─ OptionsView       Letterbox | Crop | Duo (experimental)   ← sets DM_ASPECT / DM_PRESENT_FILL / DM_DUO
 ├─ BuildModel        runs scripts/build_ipa_from_nsp.py --prepare-xcode --progress json
 │                    (or the pipeline directly for the IPA path), parses the JSON progress lines
 ├─ DeployModel       xcodebuild -workspace … -allowProvisioningUpdates DEVELOPMENT_TEAM=<found>
 │                    xcrun devicectl device install app
 └─ SetupView         Xcode present? account? device trusted? limits explained
```

The three picture modes are just the env file handed to the pipeline:

| Mode | env file |
|---|---|
| Letterbox | `DM_ASPECT=fill`, `DM_PRESENT_FILL=` (unset/off), `DM_DUO` unset |
| Crop | `DM_ASPECT=fill`, `DM_PRESENT_FILL=crop` |
| Duo (experimental) | `DM_ASPECT=fill`, `DM_PRESENT_FILL=stretch`, `DM_DUO=1`, `DM_DUO_ASPECT=2853:2007` |

(That is exactly what `duo/test.env` plus the registry does today; the app writes a small env file per build.)

## 4. Phases

**P0 — today's engine state (done).** Pipeline, camera-aspect method with a per-game registry, in-game menu
(picture fill, split screen, on-screen controls: move/hide/reset), split layout, documented handoff.

**P1 — make it runnable by hand in ten minutes (no GUI yet).**
- [ ] `duo/quickstart.md`: the four commands, copy-paste, with the free-account setup.
- [x] A single wrapper (`bin/duo`): `duo setup`, `duo status`, and `duo build <game> --keys <prod.keys>
      [--mode letterbox|crop|duo] [--install]` does prepare → build → sign → install → launch, borrowing a profile
      this Mac already owns when the free account cannot make a new one (the §6a pitfall, handled). Verified:
      `duo setup` and `duo status` on this Mac; a full `duo build --install` run is the next live test.
- [ ] `duo/quickstart.md`: the four commands with the free-account setup (next).
- [ ] The `Duo (experimental)` mode refuses games not in the registry, with a friendly explanation.

**P2 — the app.** SwiftUI shell around the same wrapper (the wrapper stays the single source of truth; the app is
a front end). Ship as an unsigned .app in a zip (right-click → Open), plus a one-page setup guide with screenshots.

**P3 — polish.** Per-game notes page ("HUD stretch", "cutscenes", known issues), an "update check" for the registry,
and a "re-sign before 7 days" reminder (the expiry is in the app's provisioning profile; upstream's front end already
parses it — reuse that idea).

## 5. What we say we support (honesty section)

| Claim | Evidence today |
|---|---|
| Runs on a free Apple ID, 3 apps, 7 days | yes, used all day (bundle ids with a Personal Team profile) |
| Letterbox / Crop work for every brought-up game | yes — no game modification |
| "Duo (experimental)": world fills the screen at the right shape | 3D World and Wonder verified on device; TotK from earlier work |
| Known-good camera patches | 3D World, Wonder, TotK, plus registered-unverified: Burnout, AC Ezio, DQ VII, Galaxy 2 |
| No camera patch exists (kept honest) | Luigi's Mansion 3, Demon Slayer — documented negative results |
| HUD in Duo mode | **stretched in the games we patched** (1.25x); parked, with the reasons and the letterbox escape hatch |
| 2D games (Unity/2D engines) | Duo mode does not apply; Letterbox or Crop |

## 6. Naming

"Duo Builder" is fine as a working title; the README should say plainly: *"Rebuilds your own Switch games for the
iPhone Duo. Bring your own games and keys. Not affiliated with Nintendo."*
