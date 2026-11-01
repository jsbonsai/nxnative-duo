# Design questions — "Shelf" redesign

Every place where `IMPLEMENTATION.md` / `COPY.md` and the current app, the CLI, or the reference PNGs do not agree
on one reading. Nothing here was decided by inventing a design: the app implements the closest literal reading,
listed under **Now**, and the element is omitted where the data does not exist (the spec's own rule in §3: "ship the
screen without that element rather than faking it").

Numbering is stable. "Live" means with today's `bin/duo`; "fixture" means the state renders only through
`DuoBuilder --snapshot --fixtures fixtures/`.

---

## A. The CLI cannot supply what the screens ask for

### Q1. No `plan` event, so the timeline cannot show future stages

**Spec:** §3 — *"A `plan` event at start listing the stages this run will go through"*; §6.11 maps stages to
timeline rows and screens 11/12 draw pending rows ("Build the app for the phone", "Pack the app", …). §3 also
gives the fallback: *"Without it, only draw stages already reached."*

**Problem:** `bin/duo build --progress json` sends `stage`, `step`, `progress`, `stage_end` and `say`; it never
sends the run's stage list before the run.

**Now:** the timeline draws stages that have started, with done/active states. Screens 11 and 12 render their
pending rows only from `fixtures/run-*.json`.

**Decision needed:** add the `plan` event, or accept a timeline without future rows. The fixtures already model the
designed shape.

### Q2. Nothing reports what is on a phone, so slots and renewals are fixture-only

**Spec:** §3 rows *"`bin/duo device apps --json`: bundle id, title, install date, profile expiry date"*,
*"`bin/duo renew <bundle-id> --device <id>`"* and *"Weekly new-app-ID budget"*; §6.02 slot row, §6.15–6.16 slot
row, §6.17 renew sheet, §10 expiry arithmetic.

**Problem:** `bin/duo` has `doctor`, `fix`, `info`, `build`, `devices`, `keys`, `patch`, `status`. There is no
`device apps`, no `renew`, and no profile-expiry or weekly-budget field anywhere.

**Now:** `InstallsStore` decodes this contract (ISO-8601 dates, snake_case):

```json
{"devices": [{"device_id": "…", "device_name": "iPhone Duo", "slots": 3,
  "apps": [{"bundle_id": "…", "title": "…", "installed_at": "…", "expires_at": "…"}],
  "free_bytes": 65000000000, "weekly_app_ids_left": 7}]}
```

Live, the store stays empty: the "On this iPhone" section is not drawn, the device pill's "On This iPhone…" item
is disabled, and Done shows headline/duration/Trust without the slot row. Home decides "first run" from an empty
library when installs data is absent (an empty shelf is the only signal there is). All slot, Done-slot, renew-sheet
and failed-ladder chip states render from `fixtures/installs*.json`.

**Decisions needed:** add the commands; confirm the JSON shape above (or give the real one); and verify §14.1/§14.2
before shipping their sentences — *"Renewing reuses the app already built, so the phone keeps your saves."*
(`phoneSub`) and *"Renewing does not use any."* (`phoneWeekly`).

### Q3. What counts as "already prepared"

**Spec:** §3 — *"`bin/duo cache list --json` or a path convention"*; §6.02/§6.09 `Ready · about 1 min`;
§9 `cacheKey` — *"non-nil = 'Ready · about 1 min'"*.

**Problem:** there is no cache command and no cache directory the app owns; the pipeline builds into
`<game folder>[/.duo/<title>]/<TITLE>_build`.

**Now:** `CacheProbe` treats an existing, non-empty `<TITLE>_build` folder in either location as the path
convention the spec allows. A failed build leaves such a folder behind, so the tile can say "Ready" when only part
of the build is there.

**Decision needed:** add `cache list`, or confirm that `_build` presence is the intended test.

### Q4. File-set problems are one sentence, not roles

**Spec:** §3 — *"In `info` JSON: per-file role, title id, and a `mismatch` reason"*; §6.07 shows a red chip
*"Update 1.3.0 is for another game ✕"* and a reason *"Remove the update for another game to continue. It belongs to
Night Courier."*

**Problem:** `duo info` reports `problems: ["not part of this game: stone-update-1.3.0.nsp"]`. It names the file but
not the version, the other title id, or which dropped file to remove. The app may not parse that sentence into a
chip (the spec says the ladder/copy must not come from parsing text).

**Now:** the card shows the CLI's problem sentence as the disabled button's red reason. There is no problem
`FileChip` with a ✕, and no library lookup for *"It belongs to …"*. The `card.reason.mismatch` strings are
transcribed but unused.

**Decision needed:** add the per-file roles/mismatch to `info`.

### Q5. PS2 has no data path at all

**Spec:** §3 (`copy` stage, phone free space), §6.08 (PS2 card, BIOS chip, room panel), §6.13 (copy panel),
§10 (BIOS as a setup input).

**Now (after the `duo` rebase):** `.iso (ps2)` is live. `duo info` dispatches an `.iso` to `duo ps2 info` and the
app decodes the `ps2` object (serial, region, layers, size, the title's BIOS requirement); `duo ps2 build` is used
for Install; the doctor's `ps2-tools`/`ps2-space` rows appear when the pipeline is installed; Setup has a BIOS
choice and the build passes `--bios`. The card shows the disc chip, a BIOS chip ("Your BIOS · from Setup" when a dump
is chosen, the problem chip when the title says `bios: required` and none is), and the room panel.

Still open:
- **Phone free space** cannot be measured through devicectl. The panel now states the requirement only:
  `ps2.size_bytes` + the pipeline's 512 MB copy headroom (4.7 GB for a 4.2 GB image), with no bar and no "GB free".
  The design's *"Needs 4.4 GB · 61 GB free"* is not reproducible; the copy's failure is the only truth.
- **BIOS semantics:** `ps2.bios` is the title's requirement (`required`/`optional`), not whether a dump is present.
  A chosen dump is the app's `settings.json` path; `required` with no path disables Install. The runtime's own note
  says a required BIOS "may not get past its first screens" even when supplied.
- **Serial/region:** available in `ps2` but the spec's card has no slot for them; only the game name/size are drawn.
- **Support wording:** `verified` maps to the existing *"Tested with nxnative"* badge; `support.note`
  ("plays"/"boots…") is not drawn because §4.4's four sentences are fixed.
- **Cache:** the PS2 build tree is not the `_build` convention, so a PS2 tile never says "Ready"; the design has no
  PS2 cached state.
- **Copy cells:** slots-after comes from installs data (Q2); room-after cannot be computed without free space.
- The game card's PS2 step 1 uses `COPY.md`'s *"2 · Build the app"* with its number changed to 1 (the deck has no
  *"1 · Build the app"*); screenshot 08's subtitle *"The game itself is not changed"* is not in the deck, so it is
  omitted; the screenshot-only label *"Slots on <phone>"* is taken verbatim from the image.
- `ps2-tools`/`ps2-space` titles come from the CLI, already in the file-format wording; they are appended after the
  eleven designed rows, so the segment count grows where the pipeline exists.

**Decision needed:** how to state the phone requirement (copy), where serial/region should appear, the PS2 support
badge wording, and whether a PS2 cache is wanted.

### Q6. Failures have no `code`, and only `slots_full`'s ladder is described

**Spec:** §3 — *"Stable `code` per failure (`slots_full`, `device_locked`, `device_gone`, `disk_full`, …)"*; §6.14 —
*"The ladder in §6.14 is chosen by code, never by parsing text."* Only `slots_full`'s three rows are specified;
`unknown`'s three rows are named (`Try Again`, `Show Details`, `Copy Details`).

**Problem:** `bin/duo` prints a plain sentence and an exit code. No stable code, no date for the weekly limit, no
free-space numbers attached to a code. The trust success path still uses the old heuristic (exit 3 + the sentence
contains "trust"), which is parsing text.

**Now:** `FailureLadder` has the table for all seed codes, but live failures are `.unknown`: the CLI sentence stays
above the unknown ladder (Try Again / Details / Copy Details). `slots_full` renders from
`fixtures/failure-slots-full.json`. Ladders for `app_id_limit`, `device_gone`, `device_locked`, `trust_needed`,
`disk_full_mac`, `disk_full_phone` and `signing_failed` were not described by the design, so they use the unknown
ladder with their own sentence; the paid-account tip appears only for the two limit codes. §14.6's paid-account
facts are unverified.

**Decision needed:** add `code` (and its data) to failures, describe the other ladders if they should differ, and
give a non-textual trust signal.

### Q7. No measured build or renew durations

**Spec:** §5 — *"Durations must be real: … 'About 2 minutes' only if measured"*; `COPY.md` `next.build.time`
(*"About <n> minutes"*) and `phone.renewAll` (*"Renew All · about <n> min"*).

**Problem:** the CLI reports progress/ETA for the current run but no completed-build history; there is no renew at
all.

**Now:** the card's *"2 · Build the app"* cell has no time line (it would be a guess); the renew sheet's primary
button is *"Renew All"* without an estimate; *"Ready · about 1 min"* and *"Installing takes about a minute"* are
kept because `COPY.md` itself states them for a cached build.

**Decision needed:** a measured duration source, or approval to leave the two estimates out.

### Q8. Help pages do not exist

**Spec:** §7.1 Help menu — *"Duo Builder Help, About free Apple ID limits"*; §6.14 — the paid tip's *"How to
switch" link (opens a help page)*.

**Problem:** the repository has no help page, no limits page, no URL.

**Now:** the paid-account tip is shown without the link (a dead link would be worse); the two Help menu items are
not built. All other menu items in §7.1 are implemented.

**Decision needed:** provide the content/URLs, or approve the omission.

### Q9. The reference PNGs and `COPY.md` disagree

These are reference-vs-deck conflicts, not CLI gaps. The rule followed is: `IMPLEMENTATION.md` > `COPY.md` >
PNG. Each difference is listed so it can be ruled on.

1. **09 meta.** PNG: *"Lowtide Works · Version 2.1.0 · built Oct 24"*. §6.06 and `card.meta`:
   *"\<publisher\> · Version \<v\> · \<size\>"*. **Now:** the size (5.7 GB); "built \<date\>" is not drawn.
2. **09 cached row.** PNG: *"Uses your last free slot"*. Deck `next.install.lastSlot`: *"Uses your last free slot
   (3 of 3)"*. **Now:** the deck string.
3. **Done, renewed (16) vs first install (15).** 16 has no reminder checkbox, an enclosing panel and slot rows with
   bars/days (*"7 days · renewed now"*, *"Until tomorrow"*); 15 has compact cards and *"Until Sat, Nov 7"*. §6.15/16
   says one Done screen with compact cards and the checkbox. **Now:** one layout everywhere — compact cards, no
   bars, `Until <date>`, checkbox after success. *"Until tomorrow"* and *"renewed now"* are not in the deck and are
   not drawn.
4. **11's pending row** *"Build, pack and install on iPhone Duo"* is in no deck key and not in §6.11's table; 12 uses
   three separate rows. **Now:** the §6.11 rows (and only reached ones, Q1).
5. **Duo picture body.** 06 shows *"The 3D world fills the inner screen. Letterbox, crop or stretch can be changed
   while playing."*; 09 shows *"Pack \\"…\\" by nxnative-duo. HUD elements look a little tall."*; deck
   `picture.duo.body` is *"Uses the pack \\"\<pack\>\\" by \<author\>. \<pack note\>"*. **Now:** the deck sentence; the
   note comes from the pack (`duo.note`) and is usually absent from today's `info`.
6. **Setup gear.** 01 has none; 02/05 have one. §5 lists a Setup gear on Home. **Now:** always on Home.
7. **Library count at 0 prepared games.** The deck has one form (*"\<n\> games · \<k\> reinstall in about a
   minute"*). **Now:** *"\<n\> games"* when k = 0, rather than *"0 reinstall…"*.
8. **"Not affiliated with Nintendo"** is in 01's status strip only. **Now:** first run only (empty library).
9. **Library tile status.** 02 shows Tidewalker (a provisional profile) as *"Not built yet"*; `COPY.md` has a
   `tile.bringUp` (*"May not start"*) that §5's tile-state list does not mention. **Now:** the tile uses
   *"Not built yet"* for a provisional, unbuilt game; the card's support badge still says *"Still being brought
   up — may not start"*.
10. **Strings not in `COPY.md` but used** (from the spec/image, kept verbatim): *"Locate…"* (§6.02), *"Show in
   Library"* (§7.3), *"Stop"* (the only label available for the destructive cancel-confirmation button; the deck
   gives the title/body but no button names), and *"Slots on \<phone\>"* (image 13).

### Q10. Reading has no real progress

**Spec:** §6.04 — *"a real bar with '1.9 of ~5.0 GB · 38%'"*.

**Problem:** `duo info` is a one-shot capture with no `--progress` stream (the app's own 300 s timeout). There is no
byte count to draw.

**Now:** the Reading screen shows the real skeleton, spinner, file name and Cancel, with no bar or count; reads
under ~400 ms go straight to the card. A fixture could not make a live bar honest.

**Decision needed:** add progress to `info`, or accept the barless skeleton.

### Q11. App icon direction

**Spec:** §13 offers A (refined current), B (shelf) and C (fold), and says *"Whichever is chosen is still drawn in
code"* — no choice is made in the pack.

**Now:** the current abstract icon is unchanged; the three PNGs are reference only.

**Decision needed:** A, B or C.

### Q12. Folders during a drag

**Spec:** §6.03 — classification during hover *"uses extension only"*; anything else is *"not a game file, left
out"*. The current app expanded a dropped folder into the packages inside it.

**Now:** a folder is classified as not a game file and is not read on drop (the overlay says so). Folder expansion
remains in `AppModel.add` for other callers but no live caller reaches it.

**Decision needed:** keep folder drops (then the overlay needs a folder row) or drop the feature.

### Q13. Two games in one drop cannot be split

**Spec:** §8 — *"Files for two different games → read the first, queue the rest, and show a small '2 more games
added to your library' toast."*

**Problem:** telling a base game from an update requires reading the files; `info` takes the set as one game and
reports *"more than one base game"*.

**Now:** one set is read as today, and the CLI's problem sentence is shown. The `drop.queued` string is transcribed
but unused. Sequential probing of each file would multiply the 1 s read and still not group them without roles.

**Decision needed:** per-file roles from the CLI (Q4), or accept one game per drop.

### Q14. The setup rows lack the design's values and percentage

**Spec:** §6.10 — a running fix shows *"progress bar with %"*; done rows show a value (*"27.2"*, *"signed in"*).

**Problem:** `doctor` items carry one `detail` string; a fix streams log lines with no percentage. The app stores
the streamed lines but cannot compute a percent.

**Now:** a running fix shows an indeterminate spinner and its latest line (honest, no fake number); a done row's
right value is a short form of `detail` (*"ready"* for Python, *"signed in"* for the Apple ID, the path's basename
for keys, *"installed"* for Xcode). The full detail is on expansion.

**Decision needed:** structured fields (`value`, `percent`) in the doctor output.

### Q15. The files group is not a doctor item

**Spec:** §6.10 — the group *"Files from your own console · at least one"* has two sub-rows, Switch keys and PS2
BIOS; either satisfies it. §4/§6.08 says each card checks only the file its platform needs.

**Problem:** the doctor has a `keys` item; it has no BIOS item. The `.iso (ps2)` pipeline takes `--bios`, and the
design puts the choice in this group.

**Now:** the group has both sub-rows — keys and a BIOS choice stored in `settings.json` (the doctor still does not
report a BIOS). The group is satisfied by either; a done group keeps its sub-rows visible so the other can still be
added. `duo ps2 build` receives the chosen path as `--bios`.

**Decision needed:** whether the doctor should own the BIOS row (and validate the dump) instead of the app's setting.

### Q16. Auto-renew's completion has no copy

**Spec:** §10 — auto-renew runs in the background, shows progress in the slot card, and *"post a notification on
completion"*; §7.4 lists only the expiry and build-finished notifications.

**Now:** the opt-in setting is real: when installs data changes and the setting is on, an app with ≤ 2 days left is
renewed once per session (never without the setting). Progress appears through `InstallsStore.renewing` on the
sheet's Renew button; there is no completion notification because the deck has no renew-finished sentence.

**Decision needed:** a renew-notification string.

### Q17. Missing local files keep the Install button enabled

**Spec:** §6.02 — *"if the file moved, show the card with a 'Locate…' chip instead of the file chips."*

**Problem:** the chip is shown, but there is no copy for a disabled-install reason in that state, and the CLI would
fail on the stale paths.

**Now:** the card shows **Locate…** instead of the file chips and the primary button stays enabled; pressing it hands
the stale paths to the CLI, which reports its own failure. `Locate…` opens the picker and re-reads the files.

**Decision needed:** a sentence for the disabled reason (or confirmation that the CLI's failure is acceptable).

### Q18. Renew does not lead to the renewed Done screen

**Spec:** §6.16 — the Done screen also represents *"Renew finished, no Trust step"*; §6.17's Renew / Renew All are
the entry points.

**Problem:** there is no `renew` command to test against, and no decision on what a multi-app Renew All shows at the
end. The app cannot know the new expiry until the phone reports it again.

**Now:** Renew and Renew All run the (future) CLI command, show a spinner on the sheet and refresh installs; the
sheet stays open. The renewed Done layout exists and renders from `fixtures/done-renewed.json`.

**Decision needed:** wire a successful renew to a renewed Done screen (single app and Renew All), or keep the sheet.

### Q19. Keyboard navigation of the library grid

**Spec:** §11 — *"library grid is focusable (.focusable() + arrow keys), Return opens a card"*.

**Now:** tiles are buttons in the accessibility tree and open with a click; there is no arrow-key focus model or
Return-on-focus handling (macOS 13 target; SwiftUI has no grid focus primitive). VoiceOver reads tile + status;
banners are hidden; the timeline is combined per row; the disabled primary's reason is its accessibility hint.

**Decision needed:** approve a custom focus engine (a real implementation, not a one-liner) or defer.

### Q20. Dock progress was optional and is not built

**Spec:** §6.11 — *"Optional: mirror progress in the Dock tile"*.

**Now:** not built. The window's own progress and the completion notification are built.

### Q21. PS2 card wording and free space

**Spec:** §6.08 — *"`SupportBadge(.bringUp)`"*, *"Room on <phone> … Needs 4.4 GB · 61 GB free"*, *"Your BIOS · from
Setup"*; §4.4's four fixed support sentences.

**Now:** `verified` uses *"Tested with nxnative"*; a provisional `.iso` uses *"Still being brought up — may not
start"*; the room panel states *"Needs 4.7 GB"* (image + 512 MB) and draws no bar because the phone's free space
cannot be measured; the BIOS chip uses the deck's sentences and Setup choice. **Decision needed:** approve these
readings, or supply PS2-specific badge/room copy and a free-space source.

---

## B. Owner copy rule (2026-10-31): no console names

The owner's later rule overrides the deck's wording while keeping its layout, hierarchy and everything else:
user-facing copy names **file formats**, never consoles. Every replacement made under that rule:

| Key / place | Design text | Shipped text |
|---|---|---|
| `firstRun.types` / home drop area | `.nsp · .xci · .iso` | `.xci / .nsp · .iso (ps2)` |
| `tile.add.hint` | `Or drop .nsp, .xci or .iso anywhere` | `Or drop .xci / .nsp · .iso (ps2) anywhere` |
| `tile.ps2` (library tile, card banner, working/failed banner tag) | `PS2` | `.iso` |
| `chip.biosMissing` | `Needs your PS2 BIOS · Add…` | `Needs your BIOS for .iso (ps2) · Add…` |
| `card.reason.noKeys` | `Add your Switch keys in Setup to install Switch games.` | `Add your prod.keys in Setup to install .xci / .nsp games.` |
| `card.reason.noBios` | `Add your PS2 BIOS in Setup to install PS2 games.` | `Add your BIOS for .iso (ps2) in Setup to install .iso games.` |
| `step.keys` | `Switch keys` | `Keys for .xci / .nsp` |
| `step.keys.body` | `prod.keys, for .nsp and .xci games` | `prod.keys, for .xci / .nsp games` |
| `step.bios` | `PS2 BIOS` | `BIOS for .iso (ps2)` |
| `step.bios.body` | `your own BIOS, for .iso games` | `your own BIOS, for .iso (ps2) games` |

`Copy.statusNotAffiliated` is still *"Not affiliated with Nintendo"*: the rule lists console names
("Nintendo Switch", "Switch", "PlayStation", "PS2"), and this is the legal non-affiliation line naming the company,
not a console. **Decision needed:** if the company name must also go, the replacement needs the owner's preferred
legal wording. Everything else in `COPY.md` is unchanged.

`docs/COPY-STYLE.md` is present after the rebase and confirms the same phrases: `.xci / .nsp` and `.iso (ps2)`.
The app's replacements follow it literally.

---

## C. Implemented literal readings that are not questions

- Window is 720×560 (§2.1), not `DESIGN.md`'s 680×500.
- The whole window is a drop target; the free slot card highlights while files are over it (§8). Hovered file names
  come from the drag pasteboard while SwiftUI reports the target.
- One filled accent button per screen: Home's Add tile is the accent element and first-run has the only filled
  button; Renew on an expiring slot is outlined; Done's Back to Shelf is the only filled button; Failed's Try Again
  is the only filled button (Back is outlined); Setup has no filled primary.
- Support state is mapped one-to-one (`tested`, `other-version`, `provisional` → *Still being brought up*,
  `unknown` → *New*); no state is merged. An "other version" with no named version is reported as New instead of
  printing *"(tested: )"*.
- Every number that changes over time uses `.monospacedDigit()`; stage elapsed is *"0m 42s"* as drawn in 12.
- No ETA is computed: the active row shows *"time left: not known yet"* unless the pipeline sent `eta`.
- No indeterminate bar is used as a progress bar: the timeline omits the bar until a fraction arrives.
