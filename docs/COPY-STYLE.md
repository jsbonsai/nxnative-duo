# Copy style: what we call things

Owner's rule (2026-10-31): in **user-facing copy** — the Mac app, the in-game menu, error messages, the public
README, release notes, store text — never name consoles: no "Nintendo Switch", no "Switch", no "PlayStation", no "PS2"
as a brand in the sentence. Name the **file formats** instead, exactly like this and no other way:

| Instead of | Say |
|---|---|
| a Switch game / your Nintendo Switch game | **.xci / .nsp** |
| a PS2 game / your PlayStation 2 game | **.iso (ps2)** |

Examples:
- "Drop your .xci / .nsp file, or an .iso (ps2)."
- "Your own .xci / .nsp — the game, and its update if you have one."
- "An .iso (ps2) needs about 9 GB free on the phone."

Terminology that stays: the formats themselves (`.xci`, `.nsp`, `.iso`), and the product's own names (Duo Builder,
nxnative, "Duo full screen"). Game titles are written as the game's own name.

Technical documentation (`dm/`, `ps2-duo/docs/`, `docs/agents/`, game profiles) keeps precise platform words where the
engineering needs them — the rule is about what the user reads, not about accuracy in the engine's notes.

Open: the current public README and app copy still say "Switch game" in places; converting them is a pending cleanup
(`duo/BACKLOG.md`).
