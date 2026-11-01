# Duo Builder

A Mac app that puts your own games on an iPhone Duo. Drop a game, press **Install on iPhone**.

```
cd duo/app
swift run                 # the app
swift test                # its tests
swift run DuoBuilder --snapshot /tmp/shots --fixtures fixtures   # every state as PNGs, no display needed
swift run DuoBuilder --snapshot /tmp/shots --info info.json --doctor doctor.json   # the two original fixtures
```

## What the player sees

The "Shelf" redesign of `design-handoff/` (spec: `design-handoff/IMPLEMENTATION.md`, strings:
`design-handoff/COPY.md`, work list: `UI-PLAN.md`, open questions: `DESIGN-QUESTIONS.md`).

| Screen | What is on it |
|---|---|
| Home | the phone's three free-Apple-ID slots (days left, Renew) above a library of every game read before: "Ready · about 1 min", "Not built yet", "On iPhone Duo", "New to nxnative"; **Add Game…** first; the whole window is the drop target |
| First run | three slot placeholders, a dashed drop area and the three-step welcome with **Set Up This Mac** |
| Drop overlay | every dragged file named during hover, classed by extension, with the ones that will be left out in orange |
| Reading | a card skeleton with the file name and Cancel; no invented progress bar (the CLI sends none) |
| Game card | banner, title, publisher/version/size, one of four support badges, file chips, the Duo picture row, "What happens next" with real durations and slot use, and the one primary button; a disabled button always shows its reason. `.iso (ps2)` variant: disc tag, room panel, copy step |
| Working | a stage timeline (done time, active bar/count/ETA-if-sent, no pending rows without a plan event), overall %, Details log, Cancel |
| Failed | "Install stopped", the failure sentence and a numbered "What you can do" ladder chosen by failure code (unknown until the CLI emits codes) |
| Done | the game on the phone, the real duration/expiry when known, the one-time Trust step, the phone's slot row, the reminder opt-in |
| Setup (sheet) | one ordered checklist: done rows folded, the running fix expanded, rows that need you outlined with their action; closing is safe |
| On this iPhone (sheet) | slots, days left, per-app Renew, Renew All, reminder and auto-renew |

## How it works

The app is a front end. **Every decision is in `bin/duo`** (the CLI the app runs), so the app and the command line
never disagree:

| The app needs | It runs | Answer |
|---|---|---|
| what this Mac lacks | `duo doctor --json` | items with `ok`, `detail`, and how each is fixed (`auto`, `admin`, `manual`) |
| to fix one | `duo fix <item> --json` | streamed lines; `xcode-setup` asks for the Mac password once (macOS's own prompt) |
| a Duo patch pack | `duo patch add FILE` | checked against the contract, kept in Application Support |
| what the dropped files are | `duo info --json FILE…` | name, publisher, version, banner, the main module's build ID, Duo support — in about a second, without unpacking (`nx_extract --info`) |
| to remember prod.keys | `duo keys PATH` | checked (it must have `header_key`) and remembered |
| to install | `duo build --duo on/off --install --progress json FILE…` | the pipeline's JSON progress, nested under six plain steps |
| what is on a phone / to renew | `duo device apps --json`, `duo renew <bundle-id> --device <id>` | **not implemented yet**; the installs store stays empty live and those elements are left out (see `DESIGN-QUESTIONS.md` Q2) |
| what an `.iso (ps2)` game is | `duo info --json GAME.iso` (or `duo ps2 info`) | the same card, plus a `ps2` object: serial, region, layers, BIOS state, the disc's boot CRC/SHA-256 |
| to install an `.iso (ps2)` game | `duo ps2 build --iso GAME.iso --install --progress json` | the `.iso` pipeline's JSON progress, nested under six plain steps; the app is installed and the image copied to `Documents/ps2.iso` |

`.iso (ps2)` games run through the pipeline in the `ps2-duo` checkout beside this repository (`DUO_PS2_ROOT` picks
another); Setup shows its two extra rows (`ps2-tools`, `ps2-space`) only where that pipeline is installed, so a Mac
that builds `.xci / .nsp` games is not held back by them.

The wrapper always runs on `/usr/bin/python3` (macOS's own 3.9); the build itself runs in the Python 3.12
environment `duo fix python` makes in `~/Library/Application Support/Duo Builder/python`.

## The shelf

`~/Library/Application Support/Duo Builder/` now also holds `library.json` (every game read, its card, bookmarks and
a 256 px banner, so the shelf draws without touching a game file) and `settings.json` (reminder, auto-renew, chosen
phone). Bookmarks, not paths, are saved, so a file that moved within its volume is still found; a file that is gone
shows a **Locate…** chip on its card.

A build counts as prepared when the pipeline's `_build` folder is present (the spec's allowed path convention until
`duo cache list` exists). If the CLI's per-stage `plan` event is added later, the Working timeline can draw future
rows too; today it draws only stages that have started, per the spec's fallback.

## The picture

Every game installs at its own shape — letterbox, nxnative's tested default. Crop and stretch are one tap away in
the in-game menu (⚙), live. **Duo full screen (experimental)** is an opt-in switch, off by default, offered only when a
**Duo patch pack** names the dropped game's exact build (`duo/patches/README.md`, the contract) and the install goes to
an iPhone Duo. Shipped: Tears of the Kingdom 1.4.3. Players add packs by dropping a `.duopatch.json` (or a `.zip` with
one) on the window — `duo patch add` from the command line.

## Signing

With an Apple ID signed in to Xcode (the one manual setup step), the wrapper lets Xcode make the free account's
profile itself (`xcodebuild -allowProvisioningUpdates`) under a bundle ID made from the team and the title ID.
Developers without an account in Xcode can set `DUO_SIGN_AS=<bundle id>` to sign as an app ID this Mac already has
a profile for (that app is replaced on the phone).
