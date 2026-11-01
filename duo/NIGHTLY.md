# Night of 2026-10-29 → 30

Autonomous work while you slept. Everything is committed on branch `duo`.

## Built (9 IPAs, `/path/to/builds/`)

| Game | Size | Profile |
|---|---|---|
| Luigi's Mansion 3 | 6.8 GB | registered (1.4.0) — installed on the Duo |
| Super Mario Bros. Wonder | 3.9 GB | registered (1.0.0) |
| Sea of Stars | 3.5 GB | registered |
| Super Mario 3D World | 3.1 GB | derived (we have 1.2.1, profile wants 1.2.2) |
| DRAGON QUEST VII Reimagined | 4.4 GB | registered; **62,901 shaders, ~2 h** |
| STAR OCEAN THE SECOND STORY R | 4.4 GB | provisional (no profile) |
| Burnout Paradise Remastered | 4.0 GB | provisional |
| Super Mario Galaxy 2 | 3.4 GB | registered |
| Scott Pilgrim | 883 MB | **brought up from scratch** (no upstream profile) |

TotK (17.3 GB) was built earlier and is installed.

## Failed, with causes (documented in `duo/games/`)

| Game | Cause |
|---|---|
| Luigi's Mansion 2 HD | **32-bit ARM** binary — Apple silicon cannot run it. Not portable, ever. |
| TMNT: Shredder's Revenge | shader split: shaders in a container the splitter does not read |
| Assassin's Creed: Ezio Collection | same shader-split blocker |
| Demon Slayer | same shader-split blocker (heap check did run: 62.08 GB alias region) |
| FF Tactics | waiting on the 1.4.0 update (profile registers 1.4.0, we have 1.2.0) |

The shader-split blocker is now a pattern across three engines; that is the next
research item in `docs/agents/04-graphics.md`.

## Aspect (the Duo ratio) — honest status

- `duo/tools/find_aspect.py` written and **validated on TotK**: all four known sites are
  found, the camera pair top-scored.
- Scans recorded for 3D World, Sea of Stars, DQ VII, and (this pass) Burnout,
  Star Ocean, Galaxy 2. Summary: `duo/games/aspect-scan.md`.
- **Only TotK has verified sites**, so every other IPA is letterboxed *on purpose*:
  stretching the present without a camera patch distorts the picture, which is the one
  thing the Duo work is meant to avoid. Turning candidates into rows needs a device test
  per game.

## Designs

`duo/design/`: dual-screen, in-game menu, frame generation, framework vision.

## iDeck

Security review done (source-available GPL-3.0, hash matches `SHA256SUMS`, no odd
endpoints). Ad-hoc signed with no profile; needs re-signing for a free team (app + appex)
before install. Staged at `/path/to/ideck/`.
