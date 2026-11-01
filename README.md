# Noteorious

Sticky notes for FFXI monsters, for Windower 4. Target a monster and your notes for it pop up: boss mechanics, warnings, reminders.

Notes are matched by **zone + monster name**, so every spawn of "Fafnir" in Dragon's Aery gets the same note. They live in a plain Lua file you edit like a GearSwap file and can share with friends.

## Install

1. Put this folder in Windower's addons folder, so that `Windower4/addons/Noteorious/Noteorious.lua` exists.
   While developing you can link it instead of copying (Command Prompt):
   `mklink /J "C:\Path\To\Windower4\addons\Noteorious" "C:\dev\Noteorious"`
2. In game: `//lua load noteorious`
3. To load it every time, add `lua load noteorious` to `Windower4/scripts/init.txt`.

## Quick start

1. Target a monster.
2. `//mn new`. An entry for that monster is added to `data/notes.lua` and shown right away.
3. Open `data/notes.lua`, write your text in the new entry, save.
4. `//mn reload`. Done: the note now appears whenever you target that monster.

## Commands

`//mn` and `//noteorious` both work.

| Command | What it does |
|---|---|
| `//mn new` | Add a note for your target to `data/notes.lua` |
| `//mn new <zone>:<name>` | Add a note for a monster you are not targeting, e.g. `//mn new 154:Fafnir` or `//mn new Dragon's Aery:Fafnir` |
| `//mn new <raw id>` | Same, from a raw entity id. Only works while that monster is loaded near you |
| `//mn id` | Copy the target's lasting identifier (`154:Fafnir`) to the clipboard |
| `//mn rawid` | Copy the target's raw entity id (diagnostics only) |
| `//mn edit` | Show which file and line holds the target's note, and copy the file path |
| `//mn edit <key or zone:name>` | Same for a specific note |
| `//mn show [key or zone:name]` | Display a note now (also works for `manual` notes) |
| `//mn hide` | Dismiss the visible note. It returns the next time you target a match |
| `//mn pin` | Pin or unpin the visible note. Pinned notes stay over automatic ones |
| `//mn toggle [on\|off]` | Turn automatic notes on or off (remembered between sessions) |
| `//mn reload` | Reload `data/notes.lua` and `data/libraries/*.lua` |
| `//mn help` | List the commands |

## Writing notes

`data/notes.lua` returns a table with `defaults`, optional `zone_groups`, and `notes`. Each note looks like this:

```lua
demisang_deleterious = {
    match = {
        zone = "Sortie",                -- a zone group, zone name, zone id, a list, or "*"
        name = "Demisang Deleterious",
    },
    title = "Demisang Deleterious",
    color = "red",
    icon = "skull",
    mode = "pinned",
    text = [[
        Boss mechanics:
        - Dangerous abilities
        - Important reminders
    ]],
},
```

- **Text** goes between `[[` and `]]`. Indentation shared by all lines is removed, so you can indent text to match the code.
- **Inline colors**: `\cs(255,90,90)red words\cr`.
- **Title** defaults to the exact monster name, or the note key.
- Anything left out is taken from `defaults` at the top of the file.
- `//mn new` adds entries between the two `-- [noteorious:generated:...]` marker lines. Keep those lines. Everything else in the file is never touched by the addon.

## Settings

Every setting can go in `defaults` and be overridden in any note. An invalid value is reported on reload and the inherited value is used.

| Setting | Default | Values |
|---|---|---|
| `font` | `"Consolas"` | Any installed font. Falls back to Consolas, then Arial |
| `font_size` | `12` | 6 to 72 |
| `bold`, `italic` | `false` | `true` / `false` |
| `color` | `"yellow"` | Title color: a name, `"#RRGGBB"` or `{ r, g, b }` |
| `text_color` | `"white"` | Body text color |
| `background` | `"dark"` | Background color |
| `opacity` | `220` | Background opacity, 0 (none) to 255 (solid) |
| `outline`, `outline_color` | `0`, `"black"` | Text outline width 0 to 6 px, and its color |
| `padding` | `6` | Pixels around the text |
| `width` | `50` | Wrap body lines at this many characters (0 = never) |
| `max_lines` | `30` | Longer notes end with "... (N more lines)" (0 = no limit) |
| `position` | `{ x = 800, y = 250 }` | Screen position of the box |
| `icon` | `"note"` | `warning`, `skull`, `info`, `note`, `reminder`, `star`, `false`, or the file name of an image you put in `icons/` (no paths) |
| `icon_style` | `"image"` | `image`, `text` (a text symbol in the title) or `none` |
| `icon_size` | `24` | 8 to 128 px |
| `mode` | `"target"` | `target`, `combat`, `pinned`, `manual` (see below) |
| `close_on_zone`, `close_on_death`, `close_on_logout` | `true` | See below |

Color names: white, black, gray, silver, red, crimson, orange, gold, yellow, lime, green, teal, cyan, blue, purple, magenta, pink, brown, and for backgrounds dark, charcoal, slate, navy, maroon, forest, plum, parchment, sticky.

## Matching

A monster is identified by its zone and its name (case-insensitive). Raw entity ids are never stored; they change between zones and instances.

| Field | Matches |
|---|---|
| `name = "Fafnir"` | That exact name |
| `names = { "Fafnir", "Nidhogg" }` | Any name in the list |
| `name_prefix = "Demisang "` | Names starting with the text. Spaces count |
| `zone` / `zones` | A zone name, zone id, zone group, a list of these, or `"*"` for any zone |

Only one note shows at a time. When several match, the winner is decided in this order:

1. `name` beats `names`, which beats `name_prefix`.
2. A note for one zone beats a note for several zones, which beats `"*"`.
3. Among prefixes, the longer prefix wins.
4. Otherwise the alphabetically first note key wins, and `//mn reload` warns about the tie.

So a shared `sortie_fomors` prefix note covers every Demisang fomor in Sortie, `demisang_deleterious` overrides it for the boss, and fomors outside Sortie get nothing. If the best match is a `manual` note, nothing is shown automatically.

**Zone groups** name a list of zones once, at the top of the file:

```lua
zone_groups = {
    Sortie = { "Outer Ra'Kaznar [U1]", "Outer Ra'Kaznar [U2]", "Outer Ra'Kaznar [U3]" },
},
```

Use `//mn id` in game to see the exact zone id and name of your target.

## When notes show and close

| Mode | Shows | Closes |
|---|---|---|
| `target` | While you target a matching monster | When you target something else, or when it dies |
| `combat` | When you target a matching monster | When the fight is over: every matching monster you targeted is dead or gone, or for 5 seconds none of them has been targeted or fought by you, your party or alliance. Switching to adds keeps it up. Fights without claims (Reives, Domain Invasion, Campaign) count while the monster is engaged |
| `pinned` | When you target a matching monster | Only with `//mn hide`, or by the close settings below. Other automatic notes wait |
| `manual` | Only with `//mn show` | With `//mn hide` |

- `close_on_death`: close when the monster dies. Set it to `false` to keep the note up until your next target change.
- `close_on_zone`: close `pinned` and `//mn show` notes when you zone. `target` and `combat` notes always end on zoning, because their monsters are gone.
- `close_on_logout`: close any note on logout. Logging out and back in does not count as zoning.
- `//mn pin` keeps a note over all automatic notes until you unpin it. Pinned notes ignore `close_on_zone` and `close_on_death`.
- While a `pinned` or `//mn show` note is up, a `target` note does not replace it. A `target` note does show over a running `combat` note, and the combat note returns when you target away.

## Moving notes

Drag the box with the mouse. The position is saved in `data/remembered.lua`, not in your notes.

- Notes without their own `position` share one spot, so moving one moves them all.
- A note with its own `position` remembers its own spot.
- If you later change a `position` in `notes.lua`, your edit wins over the old drag.
- Notes are kept on screen. Delete `data/remembered.lua` to forget all dragged positions.

## Sharing notes

Your notes are just `data/notes.lua`. Send that file to a friend, and they copy it into their `data` folder.

To combine collections, drop extra `.lua` note files into `data/libraries/`. They load after `notes.lua` in alphabetical order. Their `defaults` are ignored, so notes keep your own look. A duplicate note key keeps the first one loaded.

Note files run in a sandbox: they cannot read or write files, run commands, or schedule code, icons must come from your `icons/` folder, and a file that runs too long is stopped and skipped. Still, only load note files from people you trust.

## Files

| Path | Purpose |
|---|---|
| `Noteorious.lua` | The addon: events and commands |
| `core/` | Loading, matching, visibility, display, note generation |
| `data/notes.lua` | Your notes. Edited by you, plus entries added by `//mn new` |
| `data/libraries/` | Extra note files to load |
| `data/remembered.lua` | Dragged positions and the auto toggle. Machine-written, safe to delete |
| `data/backups/` | A copy of `notes.lua` from before each `//mn new` (newest 20 kept) |
| `icons/` | Icon images. `tools/make_icons.py` regenerates them |
| `tests/` | Offline tests |

## Troubleshooting

- **A note does not appear.** Target the monster and run `//mn edit`. It shows which note matches, if any. Compare with `//mn id`, which gives the zone and exact name. Check that `//mn toggle` is on and that the note is not `manual`. Player characters never get notes.
- **`//mn reload` reports an error.** The message includes the file and line. Until you fix it, the previously loaded notes stay active. `//mn new` refuses to change a file with errors.
- **`//mn new` says there is no marker line.** The entry was copied to your clipboard, so paste it into `notes = { ... }`. To restore automatic saving, put `-- [noteorious:generated:end]` on its own line inside `notes = { ... }`.
- **`//mn new` damaged something.** It never writes a file that fails to load afterwards. Every previous version is in `data/backups/`.
- **The note is off screen or in the wrong place.** Delete `data/remembered.lua` and `//mn reload`.
- **An icon shows as text like `(i)`.** The image file was not found. The chat log names the missing path.
- **The font looks wrong.** The font is not installed, so Consolas or Arial is used.

## Tests

The tests run without the game:

```bash
pip install lupa
python tests/run_tests.py
```

This runs the suite under LuaJIT 2.1, LuaJIT 2.0 and Lua 5.1. Windower 4 embeds LuaJIT. With a plain interpreter, run `luajit tests/run.lua` from this folder.

To run the end-to-end tests against Windower's real `texts` library, point the runner at a checkout of https://github.com/Windower/Lua:

```bash
python tests/run_tests.py --windower-libs /path/to/Lua/addons/libs
```
