# Noteorious

Sticky notes for FFXI monsters, for Windower 4. Target a monster and your notes for it pop up: boss mechanics, warnings, reminders.

Notes are matched by **zone + monster name**, so every "Fafnir" in Dragon's Aery gets the same note. They live in a plain Lua file you can edit like a GearSwap file and share with friends.

## Install

1. Download and extract the addon. The folder must be named `Noteorious`. A GitHub download is called `Noteorious-main`, so rename it.
2. Put the folder in `Windower4/addons/`, so that `Windower4/addons/Noteorious/Noteorious.lua` exists.
3. In game, type `//lua load noteorious`.
4. Optional: to load it every time, add `lua load noteorious` to `Windower4/scripts/init.txt`.

## Quick start

1. Type `//nt demo` to see what a note looks like. Drag it to where you want notes to appear, then `//nt hide`.
2. Target a monster and type `//nt new`. A note for that monster is added to `data/notes.lua` and shown right away.
3. Add reminders without leaving the game: `//nt append Kill the adds first`.
4. For longer notes, type `//nt edit`, open `data/notes.lua` (the path is copied for you), write in the new entry, save, then `//nt reload`.

From then on, the note pops up whenever you target that monster.

## Common commands

`//nt` and `//noteorious` both work.

| Command | What it does |
|---|---|
| `//nt new` | Add a note for your target to `data/notes.lua` |
| `//nt append <text>` | Add a line to the note on screen |
| `//nt edit` | Show the file and line of your target's note (or the note on screen), and copy the file path |
| `//nt list [word]` | List your notes, or the ones matching a word |
| `//nt show <note>` / `//nt hide` | Show a note now / close the note on screen |
| `//nt pin` | Keep the note on screen while you target other things. Again to release it |
| `//nt next` / `//nt prev` | Turn the pages of a long note |
| `//nt resetpos [all]` | Move the note on screen (or every note) back to its configured position |
| `//nt demo` | Show a sample note, to try the look and the position |
| `//nt toggle [on\|off]` | Turn automatic notes on or off (remembered between sessions) |
| `//nt status` | Whether automatic notes are on, how many notes are loaded, and what is showing |
| `//nt reload` | Reload your note files after editing them |
| `//nt help` | List the commands |

## Writing notes

Each note in `data/notes.lua` looks like this:

```lua
fafnir = {
    match = { zone = "Dragon's Aery", name = "Fafnir" },
    title = "Fafnir",
    color = "red",
    icon = "skull",
    text = [[
        - Stay at its sides: Spike Flail hits everyone behind it.
        - Absolute Terror: have a way to remove terror ready.
    ]],
},
```

- **Text** goes between `[[` and `]]`. Indentation shared by all lines is removed, so you can indent the text to match the code.
- **Inline colors**: `\cs(255,90,90)red words\cr`.
- **Look**: `defaults` at the top of the file sets the font, colors, size and position for every note. Any note can override any setting, like `color` above. See [Settings](#settings).
- After saving the file, type `//nt reload`. If the file has a mistake, the chat log names the line, and your previous notes stay active until it is fixed.
- `//nt new` adds entries between the two `-- [noteorious:generated:...]` marker lines. Keep those lines. Apart from them, the addon only changes the file when `//nt append` adds a line to a note's text.

**Examples.** `examples/example-notes.lua` shows every way to match monsters: zone groups, name lists, name prefixes and manual notes. The examples are not loaded on their own. To try them, copy the file into `data/libraries/` and `//nt reload`. To keep some, copy those entries into your `data/notes.lua`.

## Updating

Your own files are never part of the download:

- `data/notes.lua` holds your notes.
- `data/libraries/*.lua` holds extra note files.
- `data/remembered.lua` holds dragged positions and the on/off toggle.
- `data/backups/` holds older copies of your notes.

To update, extract the new version over your `Windower4/addons/Noteorious` folder and let it replace the files. Your `data` files stay as they are. Then type `//lua reload noteorious`. A copy of the `data` folder before updating does not hurt.

---

# Reference

## Settings

Every setting can go in `defaults` and be overridden in any note. An invalid value is reported on reload, and the inherited value is used.

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
| `width` | `50` | Wrap lines at this many characters (0 = never) |
| `max_lines` | `30` | Longer notes are split into pages for `//nt next` and `//nt prev` (0 = no limit) |
| `position` | `{ x = 800, y = 250 }` | Screen position of the box |
| `icon` | `"note"` | `warning`, `skull`, `info`, `note`, `reminder`, `star`, `false`, or the file name of an image you put in `icons/` (no paths) |
| `icon_style` | `"image"` | `image`, `text` (a text symbol in the title) or `none` |
| `icon_size` | `24` | 8 to 128 px |
| `mode` | `"target"` | `target`, `combat`, `pinned`, `manual` (see [When notes show and close](#when-notes-show-and-close)) |
| `close_on_zone`, `close_on_death`, `close_on_logout` | `true` | See [When notes show and close](#when-notes-show-and-close) |

Color names: white, black, gray, silver, red, crimson, orange, gold, yellow, lime, green, teal, cyan, blue, purple, magenta, pink, brown. For backgrounds there are also dark, charcoal, slate, navy, maroon, forest, plum, parchment and sticky.

## Matching

A monster is identified by its zone and its name (case-insensitive). Raw entity ids are never stored, because they change between zones and instances.

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
4. Otherwise the alphabetically first note key wins, and `//nt reload` warns about the tie.

For example, a shared `sortie_fomors` prefix note covers every Demisang fomor in Sortie, `demisang_deleterious` overrides it for the boss, and fomors outside Sortie get nothing. If the best match is a `manual` note, nothing is shown automatically.

**Zone groups** name a list of zones once, at the top of the file:

```lua
zone_groups = {
    Sortie = { "Outer Ra'Kaznar [U1]", "Outer Ra'Kaznar [U2]", "Outer Ra'Kaznar [U3]" },
},
```

`//nt id` copies your target's exact zone and name, like `154:Fafnir`. `//nt new 154:Fafnir` or `//nt new Dragon's Aery:Fafnir` adds a note for a monster you are not targeting.

## When notes show and close

| Mode | Shows | Closes |
|---|---|---|
| `target` | While you target a matching monster | When you target something else, or when it dies |
| `combat` | When you target a matching monster | When the fight is over: every matching monster you targeted is dead or gone, or for 5 seconds none of them has been targeted or fought by you, your party or alliance. Switching to adds keeps it up. Fights without claims (Reives, Domain Invasion, Campaign) count while the monster is engaged |
| `pinned` | When you target a matching monster | Only with `//nt hide`, or by the close settings below. Other automatic notes wait |
| `manual` | Only with `//nt show <note>` | With `//nt hide` |

- `close_on_death`: close when the monster dies. Set it to `false` to keep the note up until your next target change.
- `close_on_zone`: close `pinned` and `//nt show` notes when you zone. `target` and `combat` notes always end on zoning, because their monsters are gone.
- `close_on_logout`: close any note on logout. Logging out and back in does not count as zoning.
- `//nt pin` keeps a note over all automatic notes until you unpin it. Pinned notes ignore `close_on_zone` and `close_on_death`.
- While a `pinned` or `//nt show` note is up, a `target` note does not replace it. A `target` note does show over a running `combat` note, and the combat note returns when you target away.
- Without a note name, `//nt edit` uses your target's note, or the note on screen when nothing is targeted. `//nt append` uses the note on screen, or else your target's note.

## Position and long notes

Drag a note with the mouse to move it. The position is saved in `data/remembered.lua`, not in your notes.

- Notes without their own `position` share one spot, so moving one (or the demo) moves them all.
- A note with its own `position` remembers its own spot.
- If you later change a `position` in `notes.lua`, your edit wins over the old drag.
- Notes, including their icon, are kept fully on screen at any resolution, and cannot be dragged off it. A note too big for the screen keeps its title corner visible.
- `//nt resetpos` moves the note on screen back to its configured spot. `//nt resetpos all` forgets every dragged spot.

A note longer than `max_lines` is split into pages, with a `page 1/3` line at the bottom. `//nt next` and `//nt prev` turn the pages, and wrap around at the end. The note starts at page 1 each time it appears.

## Sharing notes

Your notes are just `data/notes.lua`. Send that file to a friend, who puts it in their `data` folder.

To combine collections, put extra `.lua` note files in `data/libraries/`. They load after `notes.lua` in alphabetical order. Their `defaults` are ignored, so the notes keep your own look. A duplicate note key keeps the first one loaded. `//nt new` and `//nt append` only change `data/notes.lua`.

Note files run in a sandbox: they cannot read or write files, run commands, or schedule code, icons must come from your `icons/` folder, and a file that runs too long is stopped and skipped. Still, only load note files from people you trust.

## Files

| Path | Purpose |
|---|---|
| `Noteorious.lua` | The addon: events and commands |
| `core/` | Loading, matching, visibility, display, note editing |
| `icons/` | Icon images |
| `examples/example-notes.lua` | Example notes. Not loaded unless you copy them |
| `data/notes.lua` | Your notes. Created on first load; changed by you, `//nt new` and `//nt append` |
| `data/libraries/` | Extra note files to load |
| `data/remembered.lua` | Dragged positions and the on/off toggle. Machine-written, safe to delete |
| `data/backups/` | A copy of `notes.lua` from before each `//nt new` and `//nt append` (newest 20 kept) |

## Troubleshooting

- **A note does not appear.** Target the monster and use `//nt edit`, which says which note matches, if any. Compare with `//nt id`, which gives the zone and exact name. `//nt status` shows whether automatic notes are on. `manual` notes only appear with `//nt show`. Player characters never get notes.
- **`//nt reload` reports an error.** The message includes the file and line. Until you fix it, the previously loaded notes stay active. `//nt new` and `//nt append` refuse to change a file with errors.
- **`//nt new` says there is no marker line.** The entry was copied to your clipboard, so paste it into `notes = { ... }`. To make `//nt new` save by itself again, put `-- [noteorious:generated:end]` on its own line inside `notes = { ... }`.
- **`//nt append` says it could not add the line safely.** It only edits text written as `text = [[ ... ]]`, and only when nothing else in the file would change. Add the line by hand. `//nt edit` shows where the note is.
- **Something in `notes.lua` went wrong.** The addon never writes a file that fails to load. Every previous version is in `data/backups/`.
- **A note is in the wrong place.** Use `//nt resetpos`, or `//nt resetpos all`.
- **"Could not save" or "Could not create" messages.** Windower cannot write to the addon's `data` folder. This can happen when Windower is installed under `Program Files`.
- **An icon shows as text like `(i)`.** The image file was not found. The chat log names the missing path.
- **The font looks wrong.** The font is not installed, so Consolas or Arial is used.

## For developers

The tests run without the game:

```bash
pip install lupa
python tests/run_tests.py
```

This runs the suite under LuaJIT 2.1, LuaJIT 2.0 and Lua 5.1. Windower 4 embeds LuaJIT. With a plain interpreter, run `luajit tests/run.lua` from this folder. To run the end-to-end tests against Windower's real `texts` library, point the runner at a checkout of https://github.com/Windower/Lua:

```bash
python tests/run_tests.py --windower-libs /path/to/Lua/addons/libs
```

To try a working copy in game, link it into Windower instead of copying it (Command Prompt):

```bat
mklink /J "C:\Path\To\Windower4\addons\Noteorious" "C:\path\to\your\checkout"
```

To make a release zip from the latest commit, use `git archive`. The `.gitattributes` file leaves out tests, tools and other development files. Personal data is never committed.

```bash
git archive --format=zip --prefix=Noteorious/ -o Noteorious-1.1.0.zip HEAD
```

`tools/make_icons.py` regenerates the icons.
