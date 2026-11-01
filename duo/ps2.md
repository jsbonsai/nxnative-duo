# .iso (ps2) games

Duo Builder handles `.iso (ps2)` games as a second kind of input, the same shape as `.xci / .nsp`: drop a file, read its
card, press Install. The Mac app draws and `bin/duo` decides; the engine that rebuilds an `.iso` game lives in the
`ps2-duo` checkout, whose contract for this wrapper is `docs/ARCHITECTURE.md` §7 there.

What a player sees, in one line: **drop the .iso (ps2), see the game's card, Install on iPhone.** The app installs a
small app for that game and copies the disc itself into the app's Documents, once.

## The two commands

```
duo info GAME.iso [--json]                 # same card as duo info, .iso told apart by its name
duo ps2 info GAME.iso [--json]             # the same, spelled out
duo ps2 build --iso GAME.iso [--game SERIAL] [--out DIR] [--install] [--device UDID]
              [--bios PATH] [--setting K=V] [--progress lines|json]
```

`duo info` reads an `.iso` through the same path, so the app can keep one drop target: files whose name ends in `.iso`
go to `duo ps2 info`, everything else to the package reader. Mixing the two kinds in one call is refused with a
sentence (`one game at a time`), and so is more than one image.

## Where the pipeline is

`tools/ps2info`, `tools/ps2build` and `ios/build-ios.sh` come from the `ps2-duo` checkout. The wrapper looks for:

1. `DUO_PS2_ROOT` (the folder itself, not `tools/`);
2. the remembered `ps2_root` in `~/Library/Application Support/Duo Builder/config.json`;
3. `ps2-duo` beside this repository, then inside it.

Without one it says so and stops; `duo doctor` shows the pipeline's own missing pieces only where the pipeline exists,
so a Mac that only builds `.xci / .nsp` games is not held back by them.

## The card (`--json`)

`duo info --json GAME.iso` keeps the shape the app already decodes and adds one object:

| Field | Meaning |
|---|---|
| `game.title` | the serial (`SCUS-97399`) |
| `game.name` | the game's name, from the pipeline's profile |
| `game.bytes` | the image's size (the phone's free-space requirement) |
| `base` | `{"file": …, "kind": "iso", "name": …}` — so the app's file list is not empty |
| `support.state` | `verified` (plays), `provisional` (boots, still being brought up), `new` |
| `support.note` | one plain line from the profile |
| `duo.state` | always `none`: Duo full screen is a `.nsp / .xci` patch, not an `.iso` one |
| `ps2` | everything `tools/ps2info` said, unchanged: `serial`, `region`, `layers`, `boot`, `boot_crc`, `boot_sha256`, `bios`, `modules`, `multielf`, `profile`, `patch_file` |

`support.state` is the pipeline's own word; the human line reads "plays" / "boots" / "new here". An error from
`ps2info` (`iso_missing`, `not_iso9660`, `no_system_cnf`, `no_boot2`, `no_boot_elf`) is turned into one sentence with
the thing to do, never a stack trace, and exits 1 (2 for a usage error).

## The build

`duo ps2 build` runs `tools/ps2build --game <serial> --iso <file> --out <dir> --progress json [--bios PATH]
[--setting K=V]…`. Without `--game`, the serial the image names is used. Without `--out`:

1. `DUO_PS2_OUT`;
2. a mounted `*/ps2-duo` folder (the pipeline's own big-volume convention);
3. the pipeline's `out/`;

then `<that>/<serial>`. A build tree needs about 12 GB free; the wrapper checks before starting and says how to point
`--out` elsewhere.

The wrapper's steps, as `stage` events (n = 2 without `--install`, 6 with it):

| k | name | what happens |
|---|---|---|
| 1 | Reading the game | `tools/ps2info`, the free-space check, the flags |
| 2 | Rebuilding the game | `tools/ps2build`: translate, explore, compile VU1, link, verify |
| 3 | Building the app | `ios/build-ios.sh --generated <out>/generated --metal`, signed |
| 4 | Installing on \<name\> | `xcrun devicectl device install app` |
| 5 | Copying the game to the phone | free-space check, then `Documents/ps2.iso` |
| 6 | Starting the game | `devicectl device process launch` |

The pipeline's own nine stages (`reading-disc`, `reading-executable`, `translating`, `exploring`, `compiling-vu`,
`building`, `vu-aot`, `linking`, `verifying`) arrive nested under step 2 as `stage` / `progress` lines with
`"sub": true`, `k`/`n` over those nine and the pipeline's message in `note` — the same protocol the app decodes for the
`.xci / .nsp` pipeline (`docs/frontends.md`). `vu-aot` is skipped when the pipeline has no `tools/vu/aotc.py`.

Exit status: 0 built (and verified when the pipeline runs its check), 1 build failure, 2 bad usage (and a pipeline
refusal such as a missing profile), 3 built but the verification did not pass — or, with `--install`, the app was
installed and the launch failed. The sentences are the ones the pipeline's codes map to (`no_profile`,
`out_not_writable`, `bios_missing`, `bios_invalid`, `bash4_missing`, `translate_failed`, `link_failed`, …), each with
the thing to do; the full log is `<out>/logs/ps2build.log`, the app build's log in
`~/Library/Application Support/Duo Builder/logs/`.

## The phone

- **App ID**: `org.nxnativeduo.<team>.ps2.<serial>`, the team and the serial lowercased (the serial stripped to
  letters and digits, so `org.nxnativeduo.<team>.ps2.scus97399`); `DUO_PS2_BUNDLE_ID` (or `DUO_BUNDLE_ID`) overrides
  it. When a free Apple ID's ten weekly app IDs are spent, an ID this Mac already has a profile for is reused, exactly
  as in the `.xci / .nsp` path.
- **Signing**: `--install` needs an Apple ID signed in to Xcode (Setup's `account` row). The wrapper checks before it
  starts translating, because `ios/build-ios.sh` signs with `xcodebuild`'s automatic signing and has no
  local-profile fallback: a team on its own would translate for an hour and then fail at signing.
- **Documents**: the disc is copied to `Documents/ps2.iso`; the app reads `disc.iso`, then `ps2.iso`, then any single
  `.iso` in its Documents, and checks the image's size and the boot executable's SHA-256 against the build's
  `build-report.json` at launch.
- **Free space**: the wrapper asks the phone for its free space before building and before copying (image size plus
  512 MB). `devicectl` reports the phone's *capacity* but today no free-space figure, so on such a phone the copy is
  attempted and a full phone is reported as one sentence ("delete a game from the phone"); the copy's measured time is
  said and sent in the stage's `elapsed`.
- **BIOS**: optional and user-provided, never shipped. `--bios PATH` must be exactly 4,194,304 bytes; the pipeline
  validates it and records it in `build-report.json`. The runtime does not consume a BIOS yet, so a title whose profile
  says `bios = required` is shown as such on the card and may not get past its first screens.

## Setup items

Where the pipeline is installed, `duo doctor` adds:

| id | pass condition | fix |
|---|---|---|
| `ps2-tools` | bash ≥ 4, cmake ≥ 3.20, ninja, xcodegen | `duo fix ps2-tools` → `brew install bash cmake ninja xcodegen` |
| `ps2-space` | ≥ 12 GB free on the build volume | free space, or point `DUO_PS2_OUT` (or `--out`) at a drive with room |

## What the app still has to add

- `GameInfo` in the app has no `ps2` member; it decodes the card without it, and nothing draws the serial, region,
  layers or BIOS state yet.
- `StageCopy` has no plain-language names for the nine pipeline stages, so step 2 shows them capitalized as they arrive
  (`Translating`, `Exploring`, …). Mapping them ("Rebuilding the game's executable…", "Compiling the VU1 programs…") is
  a one-line change in the app, not in the CLI.
- The app's own free-space row for the phone cannot be measured by `devicectl` today; it should say the requirement
  (`ps2.size_bytes` plus headroom) and use the copy's failure to learn the truth.
- The `.xci / .nsp` six-step bar is unchanged; an `.iso` build's six steps are the table above, with no separate
  Signing step (the app build signs).
