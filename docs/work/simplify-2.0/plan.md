# Simplification to 2.0.0

Authorized 2026-11-04: the user found 1.1.0 over-engineered for "sticky
notes that open for the monster you target" and approved the cut list below.
Supersedes the 1.1.0 design in `../pre-release-usability/plan.md`.

## Evidence

Compared with the 34 addons in the user's Windower install
(`Documents/Windower/addons`): 1.1.0 had ~3,600 runtime lines and 17
commands. `thtracker` (a text box for the current target) has 125 lines and
4 commands. `equipviewer` and `Skillchains` have 1,000-1,300. Usual layout:
`Name.lua`, `README.md`, and `data/settings.xml` from the `config` library,
which 24 of the 34 use. With a `config` settings table, `texts.new` saves
dragged positions by itself (`libs/texts.lua`, mouse release handler).

## Decisions

- One file, `Noteorious.lua` (~400 lines).
- Notes: `data/notes.lua` as `zone name -> monster name -> text`. The addon
  owns the file and rewrites it whole on `//nt add`. It re-reads the file
  first, refuses to write if the file has a mistake, and keeps one
  `notes.lua.bak`. Hand-written comments are not kept, which the user accepted.
- Look and position: `data/settings.xml` via `config` + `texts`.
- Commands: add, show, hide, list, reload, help. `show` keeps a note up,
  which replaces combat/pinned/manual modes and `pin`.
- Cut: modes, `close_on_*`, prefix, name-list and zone-group matching,
  `data/libraries/`, icons, per-note styles, paging, screen clamping,
  `new`/`edit`/`id`/`rawid`/`demo`/`status`/`toggle`/`resetpos`/`next`/`prev`.
- A 1.x notes file is detected and refused, not converted. The README explains
  how to move notes by hand. There are no user notes in this repo.

## Verification

11 tests (`tests/test_addon.lua`, fake Windower) pass under LuaJIT 2.1,
LuaJIT 2.0 and Lua 5.1. Six mutations each failed at least one test:
long-string escaping, re-reading before a write, refusing 1.x files,
dedenting, `show` persistence, and excluding players.

Not verified, because it needs the game: drawing, the drag-save, settings.xml
creation, and the target and zone event timing.
