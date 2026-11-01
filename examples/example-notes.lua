--[==[
    Noteorious example notes
    ========================
    These examples show the different ways to match monsters. They are not
    loaded unless you choose to:

      * Try them all: copy this file into data/libraries/ and type
        //nt reload in game. Remove it from there to stop using them.
      * Keep a few: copy the entries you like into the notes = { ... }
        section of your data/notes.lua, then //nt reload.

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
]==]

return {
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
    },
}
