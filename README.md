# Noteorious

Sticky notes for FFXI monsters, for Windower 4. Target a monster and your note for it pops up.

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

## Look and position

Font, size, colors, background and position are in `data/settings.xml`, created on first load. `title` is the color of the monster name, and `wrap` breaks lines longer than that many characters (0 = never). After editing the file, type `//lua reload noteorious`.