# Pre-release usability improvements (v1.1.0)

Source: the user's "Noteorious — Pre-Release Usability Improvements" spec
(8 sections), authorized 2026-10-31. Push and PR are not authorized.

## Decisions

- **Prefix.** `//nt` plus `//noteorious`. None of the 103 official addons
  that declare commands (Windower/Lua @18551d8) uses `nt`.
- **Examples.** Move the sample notes to `examples/example-notes.lua` (library
  format, no defaults) so they never load by default. `data/notes.lua` is no
  longer shipped or tracked; the starter template creates it on first load.
  The old sample stays as the test fixture `tests/fixtures/notes.lua`.
- **Packaging.** `.gitattributes` export-ignore for dev files, plus
  `git archive --prefix=Noteorious/`. No script or installer.
- **Positioning.** Measure the box with `texts:extents()`
  (`windower.text.get_extents`). The docs do not say whether it includes the
  background border or when it updates, so padding is treated as outside the
  measured size, and the box is re-measured for a few frames after each
  change. The whole note and icon stay on screen when they fit. Otherwise
  the top-left corner (the title) stays visible. Clamped during drags too.
- **Long notes.** Pages of `max_lines`, with a footer line only when there is
  more than one page. `//nt next` and `//nt prev` wrap around.
- **append.** Edits only the note's `[[...]]` text in `data/notes.lua`.
  Replaces the `//nt new` placeholder. The write happens only if the edited
  file evaluates to the same library with just that text changed.
  Otherwise nothing is written.
- **demo.** A built-in manual note styled by the current defaults, using the
  shared position. Dragging it sets where notes appear, and `resetpos` undoes
  that. It is never written to any file.
- **list.** At most 15 lines, with a hint to narrow the search.

## Order and checks

1. Rename the prefix.
2. Examples, starter and gitignore.
3. new/edit feedback and append.
4. Positioning, resetpos and paging.
5. list, status, demo and help.
6. README and packaging.
7. Tests under LuaJIT 2.1, LuaJIT 2.0 and Lua 5.1, with fake and real
   texts.lua.

In-game behaviour (real extents timing, font metrics, drag feel) cannot be
verified offline.

## Status (2026-10-31)

All eight sections are implemented and uncommitted. 144 tests pass under
LuaJIT 2.1, LuaJIT 2.0 and Lua 5.1, with both the fake and the real
`texts.lua`. A `git archive` zip of a scratch commit contains only runtime
files, and the suite passes against the extracted zip.

Not verified, because it needs the game:
- `get_extents` timing and padding
- clamping at real resolutions
- drag feel
- chat wrapping of the help text
