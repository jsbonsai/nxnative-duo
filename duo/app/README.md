# Duo Builder

A Mac app that puts your own Switch games on an iPhone Duo. Drop a game, press **Install on iPhone**.

```
cd duo/app
swift run                 # the app
swift test                # its tests
swift run DuoBuilder --snapshot /tmp/shots --info info.json --doctor doctor.json   # every screen as PNG, no display needed
```

## What the player sees

| Screen | What is on it |
|---|---|
| Drop | one drop target: a game's `.nsp` / `.xci` (and its update, DLC, or `prod.keys`) — or Choose File… |
| Game | the game's own banner, name, publisher, version; chips for the game / update / DLC (Add update…); the Duo full-screen switch when the game has a patch; **Install on iPhone** |
| Working | one headline per step, one bar, a count and the time left; Details hides the log; Cancel stops everything it started |
| Done | "<game> is on <iPhone>", and the Trust step the first time a free Apple ID's app is installed |
| Setup (sheet) | only what is missing, each with a Fix / Fix… / Open Xcode / Choose… button; the rest in a compact Ready list |

The bottom bar always says whether the Mac is ready ("Ready — installs to iPhone" or "1 thing to set up").

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

The wrapper always runs on `/usr/bin/python3` (macOS's own 3.9); the build itself runs in the Python 3.12
environment `duo fix python` makes in `~/Library/Application Support/Duo Builder/python`.

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
