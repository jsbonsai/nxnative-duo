# Duo Builder — design brief

*Current state: v0.1.0, 2026-10-31. This document describes the shipped Mac app as it is (every string is quoted from
the source), the product rules that a redesign must keep, and where design can do the most good. Screenshots in
`screens/` were rendered by the app itself.*

---

## 1. What Duo Builder is

A small macOS app that turns a game the user already owns into an app on their iPhone. The user drops their own
game files (and, once, points it at their own keys), presses **one** button, and a few minutes later the game is
installed on the phone and runs natively — no emulator, no JIT, no developer account.

It exists because the underlying project (nxnative) works, but building a game means a terminal, Xcode, signing
identity, provisioning profiles and 20 browser tabs. Duo Builder is the friendly front door.

**Who it is for:** a curious phone owner with a Mac, an iPhone, a free Apple ID, a game they dumped themselves, and
no patience for developer tooling. They are not necessarily technical; they *are* impatient and they hate being
lied to.

**What it is not:** an emulator, a downloader, a store. Nothing copyrighted ships. Not affiliated with Nintendo.

---

## 2. The job, in three moments

1. **"Here is my game."** Drag files in → see what the app understood: banner, name, publisher, version, whether
   this exact build is known to work, which files make up the game (game / update / DLC), and — on a cartridge
   holding two games — which game you mean.
2. **"Put it on my phone."** One button. Progress with a real percentage and a plain-language headline. Cancel
   always works. Failure is a sentence a person can act on, not a stack trace.
3. **"It's on my phone."** A clear confirmation, the one macOS-Trust step if iOS will ask for it, and a friendly
   reminder of the free-Apple-ID rules (3 apps, 7 days).

Everything else — Xcode, SDK, build tools, .NET, Python, the Apple ID, the phone, the keys, disk space — is the
app's problem, surfaced only when something needs the human.

---

## 3. Product rules a redesign must keep

These are not styling preferences; they are why the app is trusted.

- **One primary action per screen.** Exactly one prominent button: Install (or, when something is missing, "Set Up
  and Install").
- **No false certainty.** Support state is stated honestly and differently: *Tested with nxnative* / *Another version
  was tested (tested: 1.0.0) — likely works* / *Still being brought up — may not start* / *New to nxnative — it may
  not start*. A redesign may restyle these, never merge them into one "Works!" badge.
- **Plain language, no jargon.** Never "provisioning profile", "entitlement", "NSP", "shader". Say "the phone",
  "sign in to your Apple ID in Xcode", "preparing the game's graphics".
- **Never fake progress.** The percentage and the ETA come from the real pipeline. If the app does not know, it says
  so rather than animating.
- **Cancel is always available** while working, and it stops the whole process, not just the animation.
- **The user's files stay the user's.** Nothing is uploaded; the game never leaves the Mac except as a built app.

---

## 4. Hard constraints that shape the UI

| Constraint | Consequence for design |
|---|---|
| Free Apple ID: **3 apps per phone, 7-day expiry, 10 new app IDs per week** | The Done screen must set the 7-day expectation; a future "on this iPhone" list with slots and a Renew action is planned |
| **First build of a game takes 10–40 minutes** (shader compilation); later builds about a minute | Progress must be interesting and honest for 40 minutes; the long stage must say it is the long one |
| The app is a **thin front end over a CLI** (`bin/duo`) | Every state must come from data the CLI emits; no invented intermediate states |
| macOS **680×500** window, content-sized, hidden title bar | Designs should be composed for exactly this canvas; a taller window is possible if it earns its height |
| **Light and dark** appearances | Every screen must work in both; system colours and materials preferred |
| **Free Apple ID setup is fiddly** (Xcode, SDK, tools, .NET, Python, Apple ID, phone, keys, disk) | The Setup sheet is a first-class screen, not an error dialog |
| **PS2 support is coming**: drop an `.iso`, optional user-supplied BIOS, a much larger file that must be copied to the phone | Design for a second input type now (file-type-neutral drop zone, "Copying the game to the phone…" stage, free-space checks) |
| iOS shows its own **Trust** prompt on first launch | The Done screen must include the exact Settings path, once, without alarm |

---

## 5. Current UI, screen by screen

Canvas: 680×500 pt, fixed, hidden title bar, system font throughout (rounded design for titles). Accent: the user's
system accent. Surfaces: `.background` for the window, `.bar` for the status strip, `Color.primary.opacity(0.03–0.07)`
for filled panels, 14–24 pt continuous corner radii. Spacing: 28 pt page padding, 14–22 pt between groups.

### 5.1 Home — nothing dropped yet (`screens/1-drop-dark.png`, `1-drop-light.png`)

A single large dashed drop target filling the content area.

- Dashed 2 pt border, 24 pt radius, `9 7` dash, tinted accent at 8% when files are dragged over it; otherwise
  `primary` at 3% fill and 15% border.
- Centred stack: `gamecontroller.fill` at 54 pt light, **"Drop a Switch game"** (26 pt semibold rounded),
  "Your own .nsp or .xci — the game, and its update if you have one." (secondary), and a large **"Choose File…"**
  button.
- While parsing: a large spinner and **"Reading the game…"**.
- Problems (e.g. missing keys, wrong file type) appear as an orange `exclamationmark.triangle.fill` label under the
  drop zone.

Status strip (always visible on Home, 12 pt vertical padding, `.bar` material): a coloured dot and either
"Checking this Mac…", "**N** things to set up" (orange), or "Installs to **iPhone ▾**" (green) with a device menu;
right-aligned link **"Setup"**. The device list refreshes every 6 s; unplugged devices are listed and greyed with
"(not connected)".

### 5.2 Home — game understood (`screens/2-game-dark.png`, `2-game-duo.png`, `2-game-16pro.png`)

A card, not a form:

- **Banner** 150×150, 21 pt radius, soft shadow (game's own icon extracted from the file; gradient + controller
  fallback if absent).
- **Title** 25 pt bold rounded, up to two lines. Under it: `Publisher · Version 1.4.3` in secondary.
- **Support badge** (coloured icon + short sentence, see §3).
- **File chips**: `✓ Game 1.0.0`, `✓ Update 1.4.3`, or a clickable `+ Add update`; `✓ DLC ×2` when present.
- Top-right: a quiet `xmark.circle.fill` to clear and choose another game.
- Two-game cartridge: one extra row, "This cartridge holds 2 games:" with a menu picker.
- **Picture row** (the only build-time choice): a panel with an icon, "Duo full screen (experimental)" + a switch,
  and an explanatory sentence, or a static "Original shape" panel for phones without the Duo and for games without
  a patch. It deliberately explains that letterbox/crop/stretch are changed *while playing*, in the in-game menu.
- Bottom: the single prominent button, full width: **"Install on iPhone"** (or **"Set Up and Install"** when Setup
  is incomplete; disabled while the file set is invalid).

### 5.3 Working (`screens/3-working.png`)

- Small banner (64 pt) + game title + "Duo full screen" / "Original shape".
- A rounded headline: "Preparing the game", "Compiling shaders (this is the long one, 10–40 minutes the first
  time)…" etc., 20 pt semibold rounded.
- Linear progress bar, then `detail · percentage` (detail is the pipeline's real count: "18,204 of 62,901").
- A quiet hint: "The first install of a game prepares its graphics: 10–40 minutes. After that it takes about a
  minute."
- Folded **Details** disclosure with a monospaced, selectable, auto-scrolling log (160 pt).
- **Cancel** at the bottom right.

### 5.4 Failed (`screens/4-failed.png`)

Same header, then a red-tinted panel: `xmark.octagon.fill` "Install stopped" + one practical sentence, e.g.
"A free Apple ID allows 3 of your own apps on the phone: delete one of them from the phone, then try again."
Buttons: **Back** and **Try Again**.

### 5.5 Done (`screens/5-done.png`, `5-done-trust.png`)

Centred: banner 120 pt with a green `checkmark.circle.fill` badge, **"<game> is on <phone>"** (24 pt bold rounded),
then either the trust step (orange panel: "One last step on the iPhone: Settings › General › VPN & Device
Management › your Apple ID › Trust. Then open the game.") or "Open it from the Home Screen. The ⚙ button in the
game has the picture and control settings."
Footnote: "A free Apple ID keeps up to 3 of your apps on the phone, for 7 days. Install again to renew."
Button: **"Install Another Game"**.

### 5.6 Setup sheet (`screens/6-setup.png`)

560×520 sheet. Title: "This Mac is ready" or "Set up this Mac", with a subtitle that says whether the app can fix
everything ("Duo Builder can do all of it for you.") or how many steps need a human ("3 steps need you.").
Then only the **missing** items, each a row: status icon (spinner while fixing), title, one-line explanation, and a
right-aligned action — **Fix**, **Fix…** (asks for a password), **App Store**, **Open Xcode**, **Choose…**. Below,
a compact green "READY" list of what is already fine. Footer: "Check Again" and "Done".

Current items: Xcode, Xcode first-time setup, Xcode's Metal compiler (a note when it is newer than the tested one),
iOS SDK, build tools, .NET 10 SDK, the Python environment, Apple ID in Xcode, iPhone, prod.keys, free space.

---

## 6. Progress model (what the app may show)

Stages arrive from the pipeline as JSON; the app maps them to plain-language headlines:

| Stage from the pipeline | Headline shown |
|---|---|
| extract / decompress / build id lookup / survey | "Reading the game…" |
| rewrite | "Rebuilding the game's executable…" |
| shader / glsl / vulkan | "Compiling shaders (this is the long one, 10–40 minutes the first time)…" |
| prepare xcode | "Preparing Xcode…" |
| app build | "Building the app for the phone…" |
| ipa pack | "Packing the app…" |
| heap check / address regions | "Checking the game's memory layout…" |
| anything else | the stage's own name |

Counts are real: "1.9 of ~5.0 GB", "1,203 of ~19,592 shaders", "2,301 files"; times as "4m 12s", "1h 03m".

---

## 7. Assets

- **Game banner** — extracted from the user's own game file (the game's NACP icon), never downloaded. Square,
  rounded, shadowed. Fallback: red→pink gradient with a white controller glyph.
- **App icon** — drawn in code (`AppIcon` view, 1024 px): a red→orange gradient rounded square, a black "phone"
  panel inside with a thin light hinge line, and a white `gamecontroller.fill`. Deliberately abstract (no game art,
  no Nintendo marks). Regenerated at every package build into `AppIcon.icns`.
- **Screens** — `screens/*.png`, rendered by the app itself, light and dark.

**How to re-render after a design change:** the app has an offscreen renderer:
`DuoBuilder --snapshot <dir> --info <duo-info.json> --doctor <duo-doctor.json>` draws every state
(including both appearances and both phones) with real AppKit controls, no display needed. This is also how a
designer can produce mockups that match the real typography exactly.

---

## 8. Where the current UI is weak (design headroom)

1. **Empty space on the card screen.** The card is short, the button is pinned to the bottom; the middle is dead
   space. Options: let the card breathe with a larger banner, show a "What happens next" strip, or size the window
   to content.
2. **Disabled Install is silent.** When the file set is invalid the button is simply greyed; the reason is only in
   orange text elsewhere. The button should explain itself.
3. **Setup is a drawer, not a journey.** It is good at listing, weak at confidence: progress across steps, what
   happens if you close it, what to do if "Fix" fails.
4. **Working screen is functional, not reassuring.** For 40 minutes the only motion is a bar. A stage timeline
   (read → rebuild → shaders → app → pack → install) would answer "how much is left" better than a percentage.
5. **Done screen sells nothing beyond "it's installed".** No next step (open it, join the phone to Wi-Fi for next
   time), no expectation of expiry beyond a footnote.
6. **No memory of anything.** The app forgets the last game, has no library, no "on this iPhone" list, no renewal —
   all planned (see §10), and all wants a place in the layout.
7. **Errors are one sentence.** Good for common cases; a "what to do" ladder (retry, choose another phone, read
   details) would help the hard ones.
8. **No drag-over affordances beyond a tint.** Drop zones outside the window, multiple files, wrong file types.
9. **PS2 will break the word "Switch"** in the drop zone and the status copy; the input model must become
   file-type-neutral.

---

## 9. Tone of voice

- Second person, present tense, short sentences. "Your game, on your phone."
- Say the number when there is one; say "about" only when it is an estimate.
- Never blame the user, never blame the phone; name the next action.
- No exclamation marks, no marketing adjectives, no "Amazing!", no emoji in chrome.
- Examples of the register that exists today: *"The first install of a game prepares its graphics: 10–40 minutes.
  After that it takes about a minute."* · *"New to nxnative — it may not start."* · *"A free Apple ID allows 3 of
  your own apps on the phone."*

---

## 10. Planned scope the redesign should make room for

1. **PS2 games**: drop an `.iso` next to Switch files; optional user-supplied BIOS in Setup; a "Copying the game to
   the phone…" stage (multi-GB file to the device); support states per game as today.
2. **"On this iPhone"**: a list of what is installed, with slot count (3), days left (7), and **Renew** without
   rebuilding.
3. **Expiry reminder** (optional, local notification or a banner when the app opens) and an optional auto-renew.
4. **Several phones**: the device menu exists; a per-phone view may follow.
5. **Duo patch packs**: users can add a pack (a JSON file) for a game; today the card only shows when one is
   available. A "Packs" area could make sharing them a first-class idea.
6. **In-game experience** (separate, iOS): the ⚙ menu, split screen, layout editor. Mentioned so the Mac app's
   language ("Duo full screen", "the ⚙ button in the game") stays consistent.

---

## 11. What a designer should deliver

- **Pixel-composed screens at 680×500** (light + dark) for: empty drop, drag-over, reading, game card (tested /
  other version / new, with and without Duo pack, with a two-game cartridge), Setup sheet open, working (early and
  shader stage), failed, done (with and without trust step), and a first-run empty state.
- **A second pass that adds PS2**: drop zone accepting `.iso`, an ISO game card, a "copying to the phone" stage.
- **A renewal/"On this iPhone" concept** (slot count, days left, Renew) as an additional screen or sheet.
- **Type scale, spacing scale, corner radii, colour roles** (semantic, appearance-aware — no hardcoded brand
  colours beyond the accent), and component states (hover, pressed, disabled, focus).
- **Icon direction**: 3 variants of the app icon (1024 px), keeping it abstract and non-infringing.
- **Copy deck**: every string used, in the register of §9.

Constraints for the deliverable: macOS native feel (SwiftUI, system fonts and materials, no custom chrome that
fights the OS), no web-only patterns, no fake progress, no merged support states, and nothing that requires a
window larger than about 720×560.
