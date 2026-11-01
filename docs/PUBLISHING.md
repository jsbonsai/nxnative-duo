# Publishing nxnative-duo

A checklist for making this repository public. **Nothing in this file has been run against GitHub**: every `gh`/`git`
command that creates or pushes something is for the owner to execute, in order, after the checks pass.

What is published: the tree at `HEAD` of the branch `duo`, as **one fresh commit** on the public default branch
`main`, under MIT, as an experimental fork of [seedds/nxnative](https://github.com/seedds/nxnative).
[`duo/tools/make_public.py`](../duo/tools/make_public.py) makes that commit reproducibly (§2).

## 1. Pre-flight checks (read-only)

Run from the repository root. Every command here only reads. The patterns are written with `[x]` classes so that
this file, which quotes them, does not match itself.

| # | Check | Command | Pass when |
|---|---|---|---|
| 1 | Worktree clean, nothing uncommitted | `git status --short` | no output |
| 2 | On the branch being published | `git branch --show-current` | `duo` |
| 3 | No game files | `git ls-files \| grep -Ei '\.(nsp\|xci\|nsz\|xcz\|nca\|nro\|kip\|romfs)$\|romfs\.img'` | no output |
| 4 | No keys | `git ls-files \| grep -Ei 'prod\.keys\|title\.keys\|\.keys$'` | no output |
| 5 | No build outputs or signing material | `git ls-files \| grep -Ei '\.(ipa\|app\|mobileprovision\|provisionprofile\|p12\|pem\|cer\|xcarchive)$'` | no output |
| 6 | No home-directory paths | `git grep -nI '/User[s]/'` | no output |
| 7 | No tokens or private keys | `git grep -nIE '(gh[p]_\|github_pa[t]_\|sk-[A-Za-z0-9]{20}\|AKIA[0-9A-Z]{16}\|BEGIN [A-Z ]*PRIVATE KE[Y])'` | no output |
| 8 | No CI secrets | `grep -rn 'secrets\.' .github` | no output (the workflows use none) |
| 9 | License and attribution | `head -5 LICENSE` | MIT, naming this fork **and** nxnative and d2r-mobile |
| 10 | Docs links and gallery consistent | `python3 -m unittest -v dm/tools/tests/test_docs.py` | OK (GitHub must not get a dead relative link) |
| 11 | Personal identifiers (device UDIDs, names, team IDs, places) | `git grep -nIiE '0000816[0]-\|0000814[0]-\|anmolsing[h]\|jsbonsa[i]\|james\.stings\|4qgg47c2f[2]\|EJ592MXD4[H]\|Rosevill[e]'` | no output |
| 12 | The owner's disk paths | `git grep -nIE '/Volumes/(T5-500[B]\|SD12[8])'` | no output |
| 13 | All of the above on the exported tree | `python3 duo/tools/make_public.py --target /tmp/nxduo-public-check --force` | `all checks passed` |

Check 12 covers the owner's drives only. Upstream's own notes mention its maintainer's drives (`/Volumes/T7/…` and
others); they are upstream's text, already public, and stay as they are so upstream merges do not conflict.

Also check by eye, because no grep covers them:

- `README.md` states plainly: experimental fork, not an emulator, ships no game data or keys, not affiliated with
  Nintendo, the free-Apple-ID limits (3 apps per phone, 7 days, 10 new app IDs per 7 days).
- `duo/research/*.tsv` contain only build IDs, offsets and notes — no keys, no title keys, no decompressed data.
- `docs/images/` (upstream's gallery) and `duo/design/img/` are game screenshots, used as documentation as upstream
  does; none shows a home screen, notifications or an account name. `duo/design/img/split-reference.png` is a photo
  of the owner's hands holding the phone: confirm you are happy to publish it.
- Commit authors: the export's commit is authored by `make_public.py --author` (default
  `nxnative-duo <nxnative-duo@users.noreply.github.com>`), never the Mac's own git identity.

## 2. History: publish one fresh commit

**Recommended (2c): a single commit, made by the export script.** The private history (its commit messages,
earlier revisions of notes, device-specific paths in old commits) never leaves this Mac; `duo` keeps it locally.

```sh
python3 duo/tools/make_public.py --commit --version v0.1.0      # → ../nxnative-duo-public, branch main, one commit
git -C ../nxnative-duo-public log --format='%h %an <%ae> %s'
```

The script exports `git archive HEAD` (uncommitted changes are left out), runs the checks of §1 on the exported
files, and only then commits. Run it again for each later release: it replaces the files (`--force`) and starts
the history again with one root commit, keeping the target's `.git` so its remotes survive. Pushing that requires
`--force` (§3).

The alternatives, not recommended: **2a** publishing `duo` as-is publishes every earlier revision, including
identifiers removed since; **2b** rewriting history with `git filter-repo --replace-text` needs a complete
redaction list, and a missed string stays public.

## 3. Create the repository and push

Replace `OWNER` with the GitHub account or organisation that will hold it. Both routes push from the export folder.

**3a. Create it first, then add the remote:**

```sh
gh auth status
gh repo create OWNER/nxnative-duo --public \
  --description "Experimental fork of nxnative for iPhones, tuned for the iPhone Duo: a Mac app that installs your own Switch games, Letterbox by default, opt-in Duo full screen through per-game patch packs, split-screen touch controls. Bring your own games and prod.keys. Not an emulator; not affiliated with Nintendo."
cd ../nxnative-duo-public
git remote add origin git@github.com:OWNER/nxnative-duo.git
git remote add upstream https://github.com/seedds/nxnative.git
git push -u origin main
```

**3b. Fork on GitHub first, so GitHub records the fork relationship:**

```sh
gh auth status
gh repo fork seedds/nxnative --org OWNER --fork-name nxnative-duo --clone=false
cd ../nxnative-duo-public
git remote add origin git@github.com:OWNER/nxnative-duo.git
git remote add upstream https://github.com/seedds/nxnative.git
git push --force -u origin main     # replaces the fork's copy of upstream's main with the single commit
```

For later releases (`make_public.py --commit --force`), push with `git push --force origin main`.

Either way, confirm the remotes afterwards are exactly these two:

```sh
git remote -v
# origin    git@github.com:OWNER/nxnative-duo.git (fetch/push)
# upstream  https://github.com/seedds/nxnative.git (fetch/push)
```

Then set the repository metadata (see §4):

```sh
gh repo edit OWNER/nxnative-duo \
  --default-branch main \
  --enable-issues \
  --add-topic nintendo-switch --add-topic ios --add-topic iphone --add-topic metal \
  --add-topic nxnative --add-topic aspect-ratio --add-topic foldable --add-topic homebrew
```

## 4. Repository description and topics

Description (the same line as in §3a, under GitHub's 350-character limit):

> Experimental fork of nxnative for iPhones, tuned for the iPhone Duo: a Mac app that installs your own Switch games,
> Letterbox by default, opt-in Duo full screen through per-game patch packs, split-screen touch controls. Bring your
> own games and prod.keys. Not an emulator; not affiliated with Nintendo.

Topics: `nintendo-switch`, `ios`, `iphone`, `metal`, `nxnative`, `aspect-ratio`, `foldable`, `homebrew`.

Deliberately **not** in the description: "emulator" as a claim (it is not one), any game title, "free games",
"download", or a support promise.

## 5. First release note (v0.1.0)

Every claim below is something the owner saw on a phone, or is stated as untested. Keep the wording.

```sh
gh release create v0.1.0 --title "v0.1.0 — first public build (experimental)" -F - <<'NOTES'
nxnative-duo v0.1.0 — experimental.

An experimental fork of nxnative (MIT) for iPhones, tuned for the iPhone Duo foldable. It is not an emulator: your
game's own code is rebuilt to run on the phone. No game content and no keys are included; you bring your own
NSP/XCI files and prod.keys. Not affiliated with Nintendo.

What is in it:
- Duo Builder, a Mac app (build it with duo/app/package.sh): drop your game files and prod.keys, see the game's
  card (banner, name, version, how well nxnative knows it), press Install on iPhone. Its Setup sheet checks and
  fixes Xcode, the iOS SDK, the build tools, .NET, Python, the Apple ID in Xcode, the phone, the keys and the free
  disk space. With several iPhones you choose one; on a two-game cartridge you pick the game.
- bin/duo, the same from the command line: doctor, fix, info, keys, devices, build, patch, status.
- The picture: every game starts in Letterbox; Crop and Stretch are in the in-game menu. Duo full screen (opt-in)
  rebuilds the camera for the Duo's 1.42:1 screen through a Duo patch pack keyed to one exact game build. One pack
  ships: The Legend of Zelda: Tears of the Kingdom 1.4.3. Anyone can make and share packs (duo/patches/README.md).
- The in-game menu (⚙, bottom centre): picture, split screen (held upright: picture on top, controls below), touch
  controls, pad layout, moving and resetting the controls, and the engine's settings.
- New, not yet tried by hand on a device: a layout editor (resize controls and the picture, move the picture,
  separate portrait and landscape layouts, controls opacity, a background photo).
- A free Apple ID registers at most 10 new app IDs a week; when they are used up, the builder reuses one already
  registered whose app is not on the phone.
- Upstream nxnative merged as of 2026-10-31, including its shader capture (PR #747) with readers for Avalanche
  games (Toy Story 3).

Played by the owner (iPhone Duo, iOS 27.2; iPhone 16 Pro, iOS 27.0.1):
- iPhone Duo: Tears of the Kingdom 1.4.3 (with Duo full screen), Super Mario Bros. Wonder, DRAGON QUEST VII
  Reimagined 1.2.0, Luigi's Mansion 3, Super Mario 3D World + Bowser's Fury, Super Mario Galaxy 2, Toy Story:
  Retro Roundup! 1.0.4 (new profile in this fork), Toy Story 3 Complete Edition 1.0.3 (gameplay).
- iPhone 16 Pro: Scott Pilgrim vs The World 1.0.3 (new profile in this fork).
- Not working: Burnout Paradise (stalls at its first frame); Assassin's Creed: The Ezio Collection and Demon Slayer
  (their shaders cannot be read yet).

Known issues:
- Duo full screen: HUD elements look about 1.25x tall.
- DRAGON QUEST VII Reimagined: its Duo camera patch does not work (it stays Letterbox), so no pack ships for it.
- Toy Story: Retro Roundup!: its PlayStation games, and the main menu's live demo after about 2 minutes idle, close
  the game.
- Toy Story 3: video audio is distorted (possibly the dump).
- From upstream: Tears of the Kingdom can slow down inside shrines (#737); Link's Awakening needs L+R on the title
  screen; cheats are Mac-only. The external display (picture on the TV, controls on the phone) has not been tested
  on a device in this fork.

Requirements: a Mac with Apple silicon and Xcode; an iPhone and a cable (or the same Wi-Fi after pairing); a free
Apple ID signed into Xcode; your own games and prod.keys (newer games need newer master keys); about 15 GB free per
build. The first build of a game compiles its shaders (10-40 minutes).

A free Apple ID allows 3 apps per phone; each expires after 7 days (install it again to renew).
NOTES
```

(`gh release create -F -` reads the notes from standard input; the heredoc above is literal text, not a file.)

## 6. After the first push

- Actions: the workflows in `.github/workflows/` run on the first push. Fix red ones before announcing anything;
  they are upstream's and expect no secrets.
- Releases: attach **no binaries** (no IPA, no `.app`, no build products).
- Issues: the templates under `.github/ISSUE_TEMPLATE/` already refuse game files; keep the checkbox in the bug
  report.
- Security: no `SECURITY.md` exists. Create one only if the owner wants a private channel; otherwise the issue
  template is the channel.
- Upstream: nothing is pushed upstream. If a Duo improvement is generic (engine-side), offer it as a pull request to
  `seedds/nxnative` separately, with its own history.

## 7. Never publish

Game dumps (`nsp`, `xci`, `nsz`, `xcz`, `nca`, extracted `RomFS`), `prod.keys`/`title.keys` or any key file, built
IPAs/apps, provisioning profiles, `Documents/log.txt` files (they contain the user's paths), personal Apple IDs,
team IDs, device UDIDs and serials, and screenshots that show the owner's account, notifications or home screen.
