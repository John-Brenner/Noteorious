Extra note libraries
====================

Drop .lua note files from other players (or your own collections) into this
folder, then type //nt reload. Every .lua file here is loaded after
data/notes.lua, in alphabetical order.

* A file here has the same layout as data/notes.lua (zone_groups and notes).
* Its defaults section is ignored: your data/notes.lua decides how notes look.
* If two files define a note with the same key, the first one loaded wins
  and the reload reports the duplicate.
* //nt new and //nt append only change data/notes.lua, never files here.
* Files are loaded in a sandbox: a shared file cannot run commands, read or
  write files, or schedule code; icons must come from your icons folder; and
  a file that runs too long is stopped and skipped. Still, only use files
  from people you trust.

To try the examples that come with the addon, copy
examples/example-notes.lua into this folder and //nt reload.

To stop using a file, move it out of this folder and //nt reload.
