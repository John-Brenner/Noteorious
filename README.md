# Noteorious

Sticky notes for FFXI monsters, for Windower 4. Target a monster and your note for it pops up.

## Install

1. Put the `Noteorious` folder in `Windower4/addons/`. A GitHub download is called `Noteorious-main`, so rename it.
2. In game, type `//lua load noteorious`. To load it every time, add `lua load noteorious` to `Windower4/scripts/init.txt`.

## Use

Target a monster and type `//nt add Stay at its sides.` The note appears right away, and from then on whenever you target that monster in that zone. Each `//nt add` adds a line. Drag the note to move it.

| Command | What it does |
|---|---|
| `//nt add <text>` | Add a line to your target's note, starting the note if needed |
| `//nt show [name]` | Keep a note on screen while you target other things: your target's, or a monster's by name |
| `//nt hide` | Close the note |
| `//nt list [word]` | List your notes, or the ones matching a word |
| `//nt reload` | Reload `data/notes.lua` after editing it |
| `//nt help` | List the commands |

`//noteorious` works too.

## Notes file

Notes are kept in `data/notes.lua` by zone and monster name (not case-sensitive):

```lua
return {
    ["Dragon's Aery"] = {
        ["Fafnir"] = [[
- Stay at its sides: Spike Flail hits everyone behind it.
- Absolute Terror: have a way to remove terror ready.
]],
    },
}
```

- For longer notes, edit the file in any text editor, save it, then type `//nt reload`. If the file has a mistake, the chat log says where, and your previous notes stay active.
- Zone names are the English zone names. A zone name that matches no zone is reported when the notes load.
- Colors inside a note: `\cs(255,90,90)red words\cr`.
- `//nt add` rewrites the file, so comments you add to it are not kept. The version before each change is saved as `data/notes.lua.bak`. `//nt add` never changes a file that has a mistake.
- To share notes, send your `data/notes.lua`. Only use note files from people you trust.

## Look and position

Font, size, colors, background and position are in `data/settings.xml`, created on first load. `title` is the color of the monster name, and `wrap` breaks lines longer than that many characters (0 = never). After editing the file, type `//lua reload noteorious`.

## Updating

Your `data` folder is not part of the download. Extract the new version over your `Windower4/addons/Noteorious` folder, then type `//lua reload noteorious`.

### From 1.x

2.0 is a simpler addon with a different notes file. A 1.x `data/notes.lua` is not loaded or changed. To bring your notes over:

1. Rename `data/notes.lua` to `data/notes-1.x.lua`, then type `//lua reload noteorious` to start a new `data/notes.lua`.
2. Copy each note's text into the new file under its zone and monster name, then `//nt reload`.
3. Fonts and colors from the old `defaults` now go in `data/settings.xml`.
4. You can delete the old `core`, `icons` and `examples` folders and `data/remembered.lua`, `data/backups/` and `data/libraries/`.

Combat, pinned and manual modes, name prefixes, name lists, zone groups, icons and per-note styles are gone. `//nt show` keeps a note up when you need it.

## For developers

The tests run without the game, under LuaJIT 2.1, LuaJIT 2.0 and Lua 5.1:

```bash
pip install lupa
python tests/run_tests.py
```

To try a working copy in game, link it into Windower (Command Prompt):

```bat
mklink /J "C:\Path\To\Windower4\addons\Noteorious" "C:\path\to\your\checkout"
```

To make a release zip from the latest commit (`.gitattributes` leaves out tests and docs):

```bash
git archive --format=zip --prefix=Noteorious/ -o Noteorious-2.0.0.zip HEAD
```
