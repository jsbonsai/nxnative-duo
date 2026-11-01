# Quickstart — your own Switch game on the iPhone Duo

You need: a Mac, a USB cable, an iPhone Duo, **a free Apple ID**, your own game (`.nsp` or `.xci`) and your own
`prod.keys`. Nothing is downloaded for you and nothing copyrighted is included: this rebuilds the game you own so
its own code runs on the phone.

## 1. Get Duo Builder (once)

```sh
git clone <this repository> nxnative-duo
nxnative-duo/duo/app/package.sh          # makes "Duo Builder.app" in duo/app/build
open "nxnative-duo/duo/app/build/Duo Builder.app"
```

(Xcode must be installed first — free on the Mac App Store, about 10 GB. Open it once.)

## 2. Set up the Mac (once, about 10 minutes)

The bottom of the window says **Ready** or **N things to set up**. Click **Setup**:

| Item | Who does it |
|---|---|
| Xcode first-time setup, iOS SDK, build tools, .NET, Python | Duo Builder — press **Fix** (one asks for your Mac password) |
| **Apple ID in Xcode** | you — **Open Xcode** › Settings › Accounts › **+** › Apple ID (a free one works) |
| **iPhone** | you — connect it with a cable, unlock it, tap **Trust**; turn on Settings › Privacy & Security › Developer Mode |
| prod.keys | drop it on the window once (it is remembered) |

## 3. Install a game

1. **Drop the game** on the window — its banner, name and version appear in about a second.
2. Drop its **update** too, if you have one (or press **Add update**).
3. Press **Install on iPhone**. The first install of a game takes 10–40 minutes (its graphics are prepared once);
   installing it again takes about a minute.

The first time, the iPhone asks you to trust the developer: **Settings › General › VPN & Device Management ›
your Apple ID › Trust**. Duo Builder tells you when.

## The picture

Games play at their own shape (letterbox: black bars on the Duo's wide screen), exactly as the project they come
from. While playing, the **⚙** button (or a controller's Home) opens the menu: picture (Letterbox / Stretch / Crop),
split screen, touch controls, pad layout, moving the controls, and every other setting. On an iPhone Duo, a few games
also offer **Duo full screen (experimental)** before you install: the 3D world fills the inner screen at the right
proportions (some HUD elements look a little tall). It is off unless you turn it on.

## Limits of a free Apple ID

- **3 of your own apps** on the phone at a time — delete one to install a fourth.
- Each **expires after 7 days** — install it again to renew (a minute; nothing is rebuilt).

## Command line (same thing, no window)

```sh
bin/duo doctor                      # what the Mac still needs
bin/duo fix python                  # fix one item (tools, dotnet, python, xcode-setup, ios-sdk)
bin/duo info Game.nsp Update.nsp    # what the files are
bin/duo build Game.nsp Update.nsp --install
```
