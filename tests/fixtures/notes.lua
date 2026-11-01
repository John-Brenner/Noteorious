--[==[
    Noteorious note library
    =======================
    This file is yours. Edit it in any text editor, save, then type
    //nt reload in game. To share notes, send this file to a friend.

    Layout
      defaults     settings every note inherits; any note can override any of them
      zone_groups  names for lists of zones, usable anywhere a zone is expected
      notes        one entry per note:  key = { match = { ... }, title = "...", text = [[ ... ]] }

    Matching (strongest first; README.md has the full rules)
      match.name         one exact monster name
      match.names        any name in a list
      match.name_prefix  names that start with this text (spaces count)
      match.zone / zones a zone name, zone id, zone group, a list of those, or "*" for any zone
    Get a monster's exact zone and name in game with //nt id.

    Modes
      target   visible while you target a matching monster
      combat   stays up for that fight, even while you target other monsters
      pinned   stays up until you dismiss it with //nt hide
      manual   only shown with //nt show <key>

    Text
      Write it between [[ and ]]. Indentation shared by every line is removed,
      so you can indent text to line up with the code. Inline colors work:
      \cs(255,90,90)red words\cr
]==]

return {
    defaults = {
        font = "Consolas",
        font_size = 12,
        color = "yellow",          -- title color: a name, "#RRGGBB" or { r, g, b }
        text_color = "white",      -- body text color
        background = "dark",
        opacity = 220,             -- background opacity: 0 (none) to 255 (solid)
        outline = 0,               -- text outline in pixels; try 1 or 2 with a low opacity
        padding = 6,
        width = 50,                -- wrap body lines at this many characters (0 = off)
        max_lines = 30,            -- longer notes are split into pages
        position = { x = 800, y = 250 },
        icon = "note",             -- warning | skull | info | note | reminder | star | false
        icon_style = "image",      -- image | text | none
        icon_size = 24,
        mode = "target",           -- target | combat | pinned | manual
        close_on_zone = true,
        close_on_death = true,
        close_on_logout = true,
    },

    zone_groups = {
        -- Sortie runs in the [U1], [U2] and [U3] layers of Outer Ra'Kaznar.
        Sortie = { "Outer Ra'Kaznar [U1]", "Outer Ra'Kaznar [U2]", "Outer Ra'Kaznar [U3]" },
    },

    notes = {
        -- Every "Demisang ..." monster in Sortie shares this note (prefix match).
        sortie_fomors = {
            match = {
                zone = "Sortie",
                name_prefix = "Demisang ",
            },
            title = "Sortie Fomors",
            color = "orange",
            icon = "warning",
            mode = "combat",
            text = [[
                General Fomor mechanics:
                - Add strategy here
                - Add warnings here
            ]],
        },

        -- The boss has its own note. An exact name beats the prefix note above.
        demisang_deleterious = {
            match = {
                zone = "Sortie",
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

        -- One note for several monsters (names list).
        dragons_aery_wyrms = {
            match = {
                zone = "Dragon's Aery",
                names = { "Fafnir", "Nidhogg" },
            },
            title = "Fafnir / Nidhogg",
            color = "cyan",
            icon = "info",
            text = [[
                - Stay at its sides: Spike Flail hits everyone behind it.
                - Absolute Terror: have a way to remove terror ready.
            ]],
        },

        -- An exact name beats the names list above, so Nidhogg gets this note.
        nidhogg = {
            match = {
                zone = 154, -- zone ids work too (154 is Dragon's Aery)
                name = "Nidhogg",
            },
            color = "magenta",
            icon = "skull",
            mode = "combat",
            text = [[
                Everything from the Fafnir note applies.
                - \cs(255,90,90)Red text\cr like this uses an inline color code.
            ]],
        },

        -- A prefix match across several zones.
        tonberries = {
            match = {
                zones = { "Den of Rancor", "Temple of Uggalepih" },
                name_prefix = "Tonberry ",
            },
            title = "Tonberries",
            icon = "warning",
            text = [[
                Everyone's Grudge hits harder the more tonberries you have killed.
            ]],
        },

        -- A manual note has no match. Show it with  //nt show checklist
        checklist = {
            mode = "manual",
            title = "Before you go",
            color = "lime",
            icon = "reminder",
            position = { x = 800, y = 520 }, -- has its own spot, remembered separately when dragged
            text = [[
                - Food and medicines
                - Reraise
                - Temporary items
            ]],
        },

        -- [noteorious:generated:begin] Notes made by //nt new are added below. Keep both marker lines.

        -- [noteorious:generated:end]
    },
}
