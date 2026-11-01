# Duo patch packs

A **Duo patch pack** changes how one exact build of one game draws its 3D camera, so that the picture can fill a
screen whose shape is not 16:9 (the iPhone Duo's inner screen is 1.4215:1) without stretching the world. Nothing in a
pack is applied unless the player turns on **Duo full screen** for that game in Duo Builder (or `duo build --duo on`).

Every game plays without a pack: Letterbox (its true shape), Crop and Stretch are the in-game menu's choices, for all
games. A pack only adds the camera change that makes Stretch look right.

## The file

One JSON file named `<anything>.duopatch.json` — or a `.zip` holding exactly one such file.

```json
{
  "format": 1,
  "name": "Tears of the Kingdom — Duo camera",
  "game": "The Legend of Zelda: Tears of the Kingdom",
  "title_id": "0100F2C0115B6000",
  "version": "1.4.3",
  "main_build_id": "277178b7dba1b6d4949a84778d4abc58",
  "camera": {
    "sites": ["0x628c74", "0xb43460", "0x1ff04f4", "0x253fbb0"],
    "const": null
  },
  "canvas": [],
  "author": "nxnative-duo",
  "checked": "how it was checked on a device, by whom, when"
}
```

| Field | Required | Meaning |
|---|---|---|
| `format` | yes | `1` |
| `name`, `game`, `version` | yes | what Duo Builder shows |
| `title_id` | yes | 16 hex digits, the base game's title ID |
| `main_build_id` | yes | 32 hex digits: the build ID of the game's `main` module **for the version the pack was made for**. A pack applies to that build and nothing else — an update changes `main`, and the pack then simply does not show up. `duo info <game files> --json` prints it (`game.build_id`). |
| `camera.sites` | one of sites/const | image offsets (hex strings) of instructions that **produce the camera's aspect ratio** — never one that computes a matrix element from it (that applies the ratio twice: the picture comes out squashed). Accepted instructions: `fdiv s<d>, …` or `ldr s<d>, …` (the result becomes the screen's ratio); a `movz w<d>` + `movk w<d>, lsl #16` pair building the 16:9 float; prefix `~` for an instruction that computes **height / width** (it gets 1/ratio). The rewriter refuses any other instruction. |
| `camera.const` | one of sites/const | image offset of a rodata `float` holding 16:9 (`0x3FE38E39`) that the camera reads, or `null` |
| `canvas` | no | `[offset, old_word, old_neighbour, new_word, new_neighbour]` rows (hex strings) that rewrite one render-size instruction; asserted before written. Leave empty unless you know you need it: changing the canvas usually breaks a game. |
| `author`, `checked` | yes | who made it, and how it was checked on a device — say whether you compared against a 16:9 picture (a measured number) or judged by eye |

The ratio is not in the pack: the build fills in the target screen's shape.

## How a pack gets used

| Where it lives | Who uses it |
|---|---|
| `duo/patches/*.duopatch.json` in this repository | shipped with the project (today: Tears of the Kingdom 1.4.3) |
| `~/Library/Application Support/Duo Builder/patches/` | packs a player added: drop the file on Duo Builder, or `duo patch add FILE` |

When a dropped game's `main` matches a pack's `main_build_id`, Duo Builder offers **Duo full screen (experimental)**
— off by default. With it on, `duo build` passes the pack to the rewriter (`DUO_PATCH=<file>`), and that build's
Picture fill defaults to Stretch.

## Making one

`duo/design/aspect.md` is the method and its traps, and `duo/research/` holds what was found for other games —
including the candidates that did **not** work (DRAGON QUEST VII Reimagined: the stretch still looked tall). Check a
pack the way §5 and §8 of aspect.md say: the same 3D scene, Letterbox against Stretch on the Duo, characters must keep
their shape.
