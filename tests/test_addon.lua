--[[
    End-to-end tests: the real Noteorious.lua running inside a fake Windower
    (see tests/fakes.lua). Each test gets its own copy of the addon's data
    folder under tests/tmp/.
]]

local T = require('tests/harness')
local fakes = require('tests/fakes')
local util = require('core/util')

local ROOT = NOTEORIOUS_ROOT
local FAFNIR, NIDHOGG = 17408018, 17408019

local function visible(w)
    return w.view().visible
end

local function content(w)
    return w.view().content
end

-- The note box is visible and contains `needle`. (A hidden box keeps its
-- last text, so checking the text alone is not enough.)
local function shows(w, needle, label)
    local view = w.view()
    if not view.visible then
        error(('%sexpected a visible note containing %s, but nothing is shown'):format(
            label and (label .. ': ') or '', T.repr(needle)), 2)
    end
    T.has(view.content, needle, label)
end

local function notes_file(w)
    return w.dir .. 'data/notes.lua'
end

-- A path the way the addon copies it to the clipboard (Windows separators).
local function native(path)
    return (path:gsub('/', '\\'))
end

local function line_of(path, needle)
    for i, line in ipairs(util.lines(fakes.read(path))) do
        if line == needle then
            return i
        end
    end
end

local function aery(opts)
    opts = opts or {}
    opts.zone = opts.zone or 154
    local w = fakes.boot(opts)
    local mobs = {
        fafnir = w.add_mob({ id = FAFNIR, name = 'Fafnir' }),
        nidhogg = w.add_mob({ id = NIDHOGG, name = 'Nidhogg' }),
    }
    return w, mobs
end

local function sortie()
    local w = fakes.boot({ name = 'sortie', zone = 133 })
    return w, {
        fomor = w.add_mob({ index = 0x101, name = 'Demisang Hoodoo' }),
        fomor2 = w.add_mob({ index = 0x102, name = 'Demisang Agent' }),
        boss = w.add_mob({ index = 0x150, name = 'Demisang Deleterious' }),
        crab = w.add_mob({ index = 0x200, name = 'Crab' }),
    }
end

T.test('a note appears while its monster is targeted', function()
    local w, m = aery({ name = 'basic' })
    T.no(visible(w), 'nothing before targeting')
    w.target(m.fafnir)
    T.ok(visible(w))
    shows(w, 'Fafnir / Nidhogg')
    shows(w, 'Spike Flail')
    T.ok(w.view().icon.visible, 'image icon shown')
    T.has(w.view().icon.file, 'icons/info.png')
    w.target(nil)
    T.no(visible(w))
    T.eq(#w.chat, 0, 'loading the shipped notes is silent: ' .. w.chat_text())
end)

T.test('an exact note beats the names list; inline colors pass through', function()
    local w, m = aery({ name = 'exact' })
    w.target(m.nidhogg)
    shows(w, 'Nidhogg')
    T.lacks(content(w), 'Fafnir / Nidhogg')
    shows(w, '\\cs(255,90,90)Red text\\cr')
end)

T.test('players never trigger notes', function()
    local w = aery({ name = 'player' })
    local pc = w.add_mob({ id = 2000, index = 2, name = 'Fafnir', is_npc = false })
    w.target(pc)
    T.no(visible(w))
    w.command('new')
    T.any(w.chat, 'That is a player')
end)

T.test('combat notes last for the fight, not for unrelated targets', function()
    local w, m = sortie()
    w.target(m.fomor)
    shows(w, 'Sortie Fomors')
    w.target(m.crab)
    T.ok(visible(w), 'a short grace period after targeting away')
    w.advance(5)
    T.no(visible(w), 'nobody was fighting the fomor')
    w.target(m.fomor)
    m.fomor.claim_id = w.player.id
    w.target(m.crab)
    T.ok(visible(w), 'the fomor is still being fought')
    shows(w, 'Sortie Fomors')
    w.defeat(m.fomor.id)
    T.no(visible(w), 'the defeat message ends the encounter')
end)

T.test('pinned notes hold until dismissed or their monster dies', function()
    local w, m = sortie()
    w.target(m.boss)
    shows(w, 'Demisang Deleterious')
    w.target(m.crab)
    w.target(m.fomor)
    shows(w, 'Demisang Deleterious', 'automatic notes do not replace it')
    w.command('hide')
    T.no(visible(w))
    w.target(m.boss)
    T.ok(visible(w))
    m.boss.status = 2
    w.tick()
    T.no(visible(w), 'the status check closes it')
end)

T.test('//nt pin keeps a note through target changes and zoning', function()
    local w, m = aery({ name = 'pin' })
    w.target(m.fafnir)
    w.command('pin')
    T.any(w.chat, "Pinned 'Fafnir / Nidhogg'")
    shows(w, '[pinned]')
    w.target(m.nidhogg)
    shows(w, 'Fafnir / Nidhogg')
    w.go_to_zone(127)
    T.ok(visible(w))
    w.command('pin')
    T.any(w.chat, "Unpinned 'Fafnir / Nidhogg'")
    T.no(visible(w))
    w.command('unpin')
    T.any(w.chat, 'There is no note to pin')
end)

T.test('toggle, show and manual notes; the toggle survives a restart', function()
    local w, m = aery({ name = 'toggle' })
    w.command('toggle')
    T.any(w.chat, 'Automatic notes are off')
    w.target(m.fafnir)
    T.no(visible(w))
    w.command('show')
    shows(w, 'Fafnir / Nidhogg')
    w.command('hide')
    w.command('show', 'checklist')
    shows(w, 'Before you go')
    T.eq(w.view().y, 520, 'its own position')
    T.has(fakes.read(w.dir .. 'data/remembered.lua'), 'auto = false')

    local w2 = fakes.boot({ dir = w.dir, zone = 154 })
    local fafnir = w2.add_mob({ id = FAFNIR, name = 'Fafnir' })
    w2.target(fafnir)
    T.no(visible(w2), 'still off after a restart')
    w2.command('toggle', 'on')
    T.ok(visible(w2))
end)

T.test('//nt new adds a working note without disturbing the file', function()
    local w = fakes.boot({ name = 'new', zone = 127 })
    local kb = w.add_mob({ index = 0x0AB, name = 'King Behemoth' })
    local path = notes_file(w)
    local before = fakes.read(path)
    w.target(kb)
    T.no(visible(w))
    w.command('new')
    T.any(w.chat, "Added note 'king_behemoth' (King Behemoth, Behemoth's Dominion) at data/notes.lua line")
    local after = fakes.read(path)
    T.ok(#after > #before)
    T.eq(after:sub(1, 200), before:sub(1, 200), 'the top of the file is untouched')
    T.has(after, 'zone = 127, -- Behemoth\'s Dominion')
    local line = line_of(path, '        king_behemoth = {')
    T.any(w.chat, 'line ' .. line .. '. File path copied.')
    T.eq(w.clipboard, native(path), 'the file path is ready to paste')
    T.ok(visible(w), 'the new note shows right away')
    shows(w, 'King Behemoth')
    shows(w, 'Add strategy, warnings and reminders here.')
    T.eq(#fakes.list(w.dir .. 'data/backups/'), 1, 'one backup')

    w.clear_chat()
    w.command('new')
    T.any(w.chat, "already has a note: 'king_behemoth'")

    fakes.write(path, (fakes.read(path):gsub('Add strategy, warnings and reminders here%.', 'Watch for Meteor.')))
    w.command('reload')
    T.any(w.chat, 'Loaded 7 notes from 1 file.')
    shows(w, 'Watch for Meteor.')
end)

T.test('//nt new for a monster in a group note creates an overriding note', function()
    local w = fakes.boot({ name = 'override', zone = 160 })
    local ton = w.add_mob({ index = 0x050, name = 'Tonberry Pontifex' })
    w.target(ton)
    shows(w, 'Tonberries')
    w.command('new')
    T.any(w.chat, "takes priority over the group note 'tonberries'")
    shows(w, 'Tonberry Pontifex')
end)

T.test('identifiers: //nt id, rawid and new with arguments', function()
    local w, m = aery({ name = 'ids' })
    w.target(m.fafnir)
    w.command('id')
    T.eq(w.clipboard, '154:Fafnir')
    w.command('rawid')
    T.eq(w.clipboard, tostring(FAFNIR))

    w.command('new', '154:Bahamut', 'Copy')
    T.any(w.chat, "Added note 'bahamut_copy'")
    w.command('new', "Dragon's", 'Aery:Vrtra', 'Copy')
    T.any(w.chat, "Added note 'vrtra_copy'")
    w.command('new', tostring(FAFNIR))
    T.any(w.chat, "Added note 'fafnir'")
    T.any(w.chat, "group note 'dragons_aery_wyrms'")
    w.target(m.fafnir)
    shows(w, 'Add strategy', 'Fafnir now has its own note')

    w.clear_chat()
    w.command('new', tostring(FAFNIR + 900))
    T.any(w.chat, "belongs to Dragon's Aery but is not loaded")
    w.command('new', '4242')
    T.any(w.chat, '4242 is not a loaded monster id')
    w.command('new', 'Atlantis:Crab')
    T.any(w.chat, 'Unknown zone "Atlantis"')
    w.command('new', 'justaname')
    T.any(w.chat, 'Expected <zone>:<monster name>')

    local lib_text = fakes.read(notes_file(w))
    T.has(lib_text, 'name = "Bahamut Copy"')
    T.has(lib_text, 'name = "Vrtra Copy"')
end)

T.test('//nt edit names the file and line', function()
    local w, m = aery({ name = 'edit' })
    w.target(m.fafnir)
    w.command('edit')
    local line = line_of(notes_file(w), '        dragons_aery_wyrms = {')
    T.any(w.chat, ("'dragons_aery_wyrms' is at data/notes.lua line %d. File path copied."):format(line))
    T.any(w.chat, 'It matches names "Fafnir", "Nidhogg" in Dragon\'s Aery (mode: target).')
    T.eq(w.clipboard, native(notes_file(w)))
    w.command('edit', 'nidhogg')
    T.any(w.chat, ("line %d."):format(line_of(notes_file(w), '        nidhogg = {')))
    w.command('edit', 'checklist')
    T.any(w.chat, 'It is a manual note: //nt show checklist displays it.')
    w.command('edit', '154:Nobody')
    T.any(w.chat, "No note matches Nobody in Dragon's Aery")
    w.target(nil)
    w.clear_chat()
    w.command('edit')
    T.any(w.chat, 'No note is showing. Target a monster, or name a note')

    -- Without a name, the note on screen wins over the target's note.
    w.command('show', 'checklist')
    w.target(m.nidhogg)
    w.command('edit')
    T.any(w.chat, "'checklist' is at data/notes.lua line")
end)

T.test('//nt append adds a line to the note on screen', function()
    local w = fakes.boot({ name = 'append', zone = 127 })
    local kb = w.add_mob({ index = 0x0AB, name = 'King Behemoth' })
    w.target(kb)
    w.command('new')
    w.clear_chat()
    w.command('append', 'Watch', 'for', 'Meteor.')
    T.any(w.chat, "Added a line to 'king_behemoth' (data/notes.lua line")
    shows(w, 'Watch for Meteor.')
    T.lacks(content(w), 'Add strategy', 'the //nt new placeholder is replaced')
    w.command('append', 'Sleep', 'the', 'adds.')
    shows(w, 'Watch for Meteor.\nSleep the adds.')
    T.eq(#fakes.list(w.dir .. 'data/backups/'), 3, 'a backup before every change')

    local w2 = fakes.boot({ dir = w.dir, zone = 127 })
    w2.target(w2.add_mob({ index = 0x0AB, name = 'King Behemoth' }))
    shows(w2, 'Watch for Meteor.\nSleep the adds.', 'saved in the file')
end)

T.test('//nt append refuses what it cannot change safely', function()
    local text = 'return {\n    notes = {\n'
        .. '        crab = { match = { zone = 154, name = "Crab" }, text = "Pinch." },\n'
        .. '        -- [noteorious:generated:end]\n    },\n}\n'
    local w = fakes.boot({ name = 'append_refuse', zone = 154, notes = text })
    w.command('append', 'x')
    T.any(w.chat, 'No note is showing. Target a monster that has a note')
    local crab = w.add_mob({ index = 0x0CC, name = 'Crab' })
    w.target(crab)
    w.command('append')
    T.any(w.chat, 'Type the text to add')
    w.command('append', 'More', 'pinching.')
    T.any(w.chat, 'Could not add the line safely, so data/notes.lua was not changed.')
    w.command('append', 'a', ']]', 'b')
    T.eq(fakes.read(notes_file(w)), text, 'never changed')
    T.eq(#fakes.list(w.dir .. 'data/backups/'), 0)

    fakes.mkdir(w.dir .. 'data/libraries')
    fakes.write(w.dir .. 'data/libraries/shared.lua',
        'return { notes = { bahamut = { match = { zone = 154, name = "Bahamut" }, text = [[Megaflare.]] } } }')
    w.command('reload')
    w.target(w.add_mob({ index = 0x0BB, name = 'Bahamut' }))
    w.command('append', 'x')
    T.any(w.chat, "'bahamut' is in data/libraries/shared.lua. //nt append only changes data/notes.lua")
    T.eq(fakes.read(w.dir .. 'data/libraries/shared.lua'),
        'return { notes = { bahamut = { match = { zone = 154, name = "Bahamut" }, text = [[Megaflare.]] } } }')
end)

T.test('a broken notes.lua keeps the previous notes and is never overwritten', function()
    local w, m = aery({ name = 'broken' })
    local path = notes_file(w)
    local good = fakes.read(path)
    local broken = good:gsub('title = "Fafnir / Nidhogg",', 'title = "Fafnir / Nidhogg"')
    fakes.write(path, broken)
    w.command('reload')
    local err = T.any(w.chat, 'Error: data/notes.lua:')
    T.ok(err:match('data/notes%.lua:%d+:'), 'with a line number')
    T.any(w.chat, 'Keeping the notes that were loaded before')
    w.target(m.nidhogg)
    T.ok(visible(w), 'old notes still work')

    w.command('new', '154:Crab')
    T.any(w.chat, 'data/notes.lua has an error, so it was not changed')
    T.eq(fakes.read(path), broken)

    fakes.write(path, good)
    w.clear_chat()
    w.command('reload')
    T.any(w.chat, 'Loaded 6 notes from 1 file.')
end)

T.test('a broken notes.lua at startup leaves the addon usable', function()
    local w = fakes.boot({ name = 'broken_start', zone = 154, notes = 'return { notes = { ' })
    T.any(w.chat, 'Error: data/notes.lua:')
    T.any(w.chat, 'No notes are active until the file is fixed')
    local fafnir = w.add_mob({ id = FAFNIR, name = 'Fafnir' })
    w.target(fafnir)
    T.no(visible(w))
    w.command('help')
    T.any(w.chat, 'Noteorious (//nt or //noteorious)')
    w.command('status')
    T.any(w.chat, 'No notes are loaded: data/notes.lua has an error. Fix it, then //nt reload.')
end)

T.test('a new install starts with an empty library; the examples are not loaded', function()
    local generator = require('core/generator')
    local dir = fakes.temp_dir('new_install')
    fakes.mkdir(dir .. 'examples')
    fakes.copy(ROOT .. 'examples/example-notes.lua', dir .. 'examples/example-notes.lua')
    local w = fakes.boot({ dir = dir, zone = 154 })
    T.any(w.chat, 'Created data/notes.lua for your notes. Target a monster and type //nt new to add one')
    T.eq(fakes.read(notes_file(w)), generator.STARTER)
    local fafnir = w.add_mob({ id = FAFNIR, name = 'Fafnir' })
    w.target(fafnir)
    T.no(visible(w), 'no example note shows up')
    w.command('list')
    T.any(w.chat, 'You have no notes yet. Target a monster and type //nt new.')

    w.command('new')
    T.any(w.chat, "Added note 'fafnir'")
    shows(w, 'Fafnir')

    fakes.mkdir(dir .. 'data/libraries')
    fakes.copy(ROOT .. 'examples/example-notes.lua', dir .. 'data/libraries/example-notes.lua')
    w.command('reload')
    T.any(w.chat, 'Loaded 7 notes from 2 files.')
    w.target(w.add_mob({ id = NIDHOGG, name = 'Nidhogg' }))
    shows(w, 'Everything from the Fafnir note applies.', 'examples work once copied in')
end)

T.test('a missing data folder is created too', function()
    local dir = fakes.temp_dir('no_data')
    local w = fakes.boot({ dir = dir, zone = 154 })
    T.any(w.chat, 'Created data/notes.lua')
    T.ok(fakes.file_exists(dir .. 'data/notes.lua'))
end)

T.test('without the marker, //nt new offers the entry on the clipboard', function()
    local text = 'return {\n    notes = {\n        a = { match = { zone = 154, name = "A" } },\n    },\n}\n'
    local w = fakes.boot({ name = 'no_marker', zone = 154, notes = text })
    local crab = w.add_mob({ index = 0x0CC, name = 'Crab' })
    w.target(crab)
    w.command('new')
    T.any(w.chat, 'has no generated-notes marker line, so it was not changed')
    T.any(w.chat, '-- [noteorious:generated:end]')
    T.has(w.clipboard, 'crab = {')
    T.has(w.clipboard, 'name = "Crab",')
    T.eq(fakes.read(notes_file(w)), text)
end)

T.test('dragged positions are saved, restored and overridden by edits', function()
    local w, m = aery({ name = 'drag' })
    w.target(m.fafnir)
    T.eq(w.view().x, 800)
    T.eq(w.view().y, 250)
    w.drag_note(300, 400)
    T.eq(w.view().x, 300)
    T.eq(w.view().icon.x, 300 - 6 - 4 - 24, 'the icon followed')
    T.has(fakes.read(w.dir .. 'data/remembered.lua'), 'x = 300')

    local w2 = fakes.boot({ dir = w.dir, zone = 154 })
    local fafnir = w2.add_mob({ id = FAFNIR, name = 'Fafnir' })
    w2.target(fafnir)
    T.eq(w2.view().x, 300, 'restored after a restart')
    T.eq(w2.view().y, 400)
    w2.command('show', 'checklist')
    T.eq(w2.view().y, 520, 'notes with their own position keep it')

    local path = notes_file(w2)
    fakes.write(path, (fakes.read(path):gsub('position = { x = 800, y = 250 }', 'position = { x = 900, y = 100 }')))
    w2.command('hide')
    w2.command('reload')
    w2.target(nil)
    w2.target(fafnir)
    T.eq(w2.view().x, 900, 'editing the position in notes.lua wins over the old drag')
end)

T.test('notes stay on screen at small resolutions and cannot be dragged away', function()
    local w, m = aery({ name = 'screen' })
    w.settings.ui_x_res, w.settings.ui_y_res = 1024, 600
    w.target(m.fafnir)
    w.frames(3)
    local v = w.view()
    T.ok(v.w > 0, 'measured')
    T.eq(v.x, 1024 - v.w - 6, 'moved left so the right edge fits (x = 800 is configured)')
    T.eq(v.y, 250)

    w.drag_note(5000, 5000)
    v = w.view()
    T.eq(v.x, 1024 - v.w - 6, 'still fully on screen after the drag')
    T.eq(v.y, 600 - v.h - 6)
    T.has(fakes.read(w.dir .. 'data/remembered.lua'), ('x = %d'):format(v.x), 'the visible spot is saved')

    local w2 = fakes.boot({ dir = w.dir, zone = 154 })
    w2.target(w2.add_mob({ id = FAFNIR, name = 'Fafnir' }))
    w2.frames(3)
    T.eq(w2.view().x, v.x, 'the saved spot is used at the next login')
    T.eq(w2.view().y, v.y)
end)

T.test('//nt resetpos puts a note back; resetpos all forgets every spot', function()
    local w, m = aery({ name = 'resetpos' })
    w.command('resetpos')
    T.any(w.chat, 'No note is showing. Show one first, or reset every note with //nt resetpos all.')
    w.target(m.fafnir)
    w.drag_note(300, 400)
    w.command('show', 'checklist')
    w.drag_note(100, 100)
    T.eq(w.view().x, 100)
    w.command('resetpos')
    T.any(w.chat, "'Before you go' is back at its own position from the note file.")
    T.eq(w.view().x, 800)
    T.eq(w.view().y, 520)
    w.command('hide')
    w.target(nil)
    w.target(m.fafnir)
    T.eq(w.view().x, 300, 'other notes keep their dragged spot')
    w.command('resetpos', 'all')
    T.any(w.chat, 'Every note is back at its position from the note files.')
    T.eq(w.view().x, 800)
    T.lacks(fakes.read(w.dir .. 'data/remembered.lua'), 'x = 300')
    w.command('resetpos', 'all')
    T.any(w.chat, 'No note had been moved.')
end)

T.test('//nt list shows notes, filters them and does not flood the chat', function()
    local w = aery({ name = 'list' })
    w.clear_chat()
    w.command('list')
    T.eq(w.chat[1], '[Noteorious] 6 notes:')
    T.eq(w.chat[2], '[Noteorious]   checklist - manual, //nt show checklist', 'sorted by key')
    T.any(w.chat, '  dragons_aery_wyrms - names "Fafnir", "Nidhogg" in Dragon\'s Aery')
    w.clear_chat()
    w.command('list', 'TONBERRY')
    T.eq(#w.chat, 2)
    T.eq(w.chat[1], '[Noteorious] 1 note match "tonberry":')
    w.command('list', 'nothing-like-this')
    T.any(w.chat, 'No notes match "nothing-like-this".')

    local parts = { 'return { notes = {' }
    for i = 1, 40 do
        parts[#parts + 1] = ('n%02d = { match = { zone = 154, name = "Mob %d" } },'):format(i, i)
    end
    parts[#parts + 1] = '} }'
    local w2 = fakes.boot({ name = 'list_many', zone = 154, notes = table.concat(parts, '\n') })
    w2.clear_chat()
    w2.command('list')
    T.eq(#w2.chat, 17, 'a header, 15 notes and a hint')
    T.eq(w2.chat[17], '[Noteorious]   ...and 25 more. Narrow the list: //nt list <word>')
end)

T.test('//nt status reports the toggle, the notes and what is showing', function()
    local w, m = aery({ name = 'status' })
    w.command('status')
    T.any(w.chat, 'Automatic notes are on. 6 notes loaded from 1 file.')
    T.any(w.chat, 'No note is showing.')
    w.target(m.fafnir)
    w.command('pin')
    w.command('status')
    T.any(w.chat, "Showing Fafnir / Nidhogg ('dragons_aery_wyrms'), pinned.")
    w.command('toggle', 'off')
    fakes.write(notes_file(w), 'return { notes = {')
    w.command('reload')
    w.clear_chat()
    w.command('status')
    T.any(w.chat, 'Automatic notes are off. 6 notes loaded from 1 file. The last //nt reload failed')
end)

T.test('//nt demo shows a sample note without changing your files', function()
    local w, m = aery({ name = 'demo' })
    local before = fakes.read(notes_file(w))
    w.command('demo')
    shows(w, 'Noteorious demo')
    shows(w, 'Drag this box to choose where notes appear.')
    T.eq(fakes.read(notes_file(w)), before)
    T.no(fakes.file_exists(w.dir .. 'data/remembered.lua'), 'nothing saved just by showing it')
    w.command('status')
    T.any(w.chat, 'Showing Noteorious demo (the demo).')
    w.command('edit')
    T.any(w.chat, 'The demo note is built into the addon and is not in any file.')
    w.command('append', 'x')
    T.any(w.chat, 'The demo note cannot be changed.')
    T.eq(fakes.read(notes_file(w)), before)

    fakes.write(notes_file(w), (before:gsub('color = "yellow"', 'color = "#102030"', 1)))
    w.command('reload')
    shows(w, '\\cs(16,32,48)', 'redrawn with the edited defaults')
    shows(w, 'Noteorious demo')

    w.drag_note(300, 300)
    w.command('hide')
    w.target(m.fafnir)
    T.eq(w.view().x, 300, 'dragging the demo sets where notes appear')
end)

T.test('missing icon images fall back to text icons', function()
    local w, m = aery({ name = 'no_icons', no_icons = true })
    w.target(m.fafnir)
    shows(w, '(i) Fafnir / Nidhogg')
    T.no(w.view().icon.visible)
    w.target(nil)
    w.target(m.fafnir)
    local count = 0
    for _, line in ipairs(w.chat) do
        if line:find('Icon image not found', 1, true) then
            count = count + 1
        end
    end
    T.eq(count, 1, 'warned once')
end)

T.test('long notes have pages; template-like text is shown literally', function()
    local lines = {}
    for i = 1, 50 do
        lines[i] = '                line ' .. i
    end
    lines[2] = '                costs ${gil} and 100% effort'
    local text = 'return { defaults = { max_lines = 5 }, notes = { crab = { match = { zone = 154, name = "Crab" }, text = [[\n'
        .. table.concat(lines, '\n') .. '\n]] } } }'
    local w = fakes.boot({ name = 'long', zone = 154, notes = text })
    local crab = w.add_mob({ index = 0x0CC, name = 'Crab' })
    w.target(crab)
    shows(w, 'costs ${gil} and 100% effort')
    shows(w, 'page 1/13 - //nt next, //nt prev')
    T.lacks(content(w), 'line 5\n')
    w.command('next')
    shows(w, 'line 5\n')
    shows(w, 'page 2/13')
    w.command('prev')
    w.command('prev')
    shows(w, 'line 50')
    shows(w, 'page 13/13')
    w.command('status')
    T.any(w.chat, 'page 13 of 13')
    w.target(nil)
    w.target(crab)
    shows(w, 'page 1/13', 'shown again from the first page')
    w.target(nil)
    w.command('next')
    T.any(w.chat, 'No note is showing.')
end)

T.test('reloading while a note is visible updates or removes it', function()
    local w, m = aery({ name = 'reload' })
    local path = notes_file(w)
    w.target(m.fafnir)
    fakes.write(path, (fakes.read(path):gsub('title = "Fafnir / Nidhogg"', 'title = "Wyrms of the Aery"')))
    w.command('reload')
    shows(w, 'Wyrms of the Aery')
    fakes.write(path, (fakes.read(path):gsub('names = { "Fafnir", "Nidhogg" }', 'names = { "Somebody Else" }')))
    w.command('reload')
    T.no(visible(w), 'Fafnir no longer has a note')
end)

T.test('zoning and logging out close notes', function()
    local w, m = sortie()
    w.target(m.boss)
    T.ok(visible(w))
    w.go_to_zone(275)
    T.no(visible(w), 'close_on_zone')
    w.command('show', 'checklist')
    T.ok(visible(w))
    w.fire('logout', 'Tester')
    T.no(visible(w), 'close_on_logout')
end)

T.test('combat notes stay up in fights without claims (Reives, Domain Invasion)', function()
    local w, m = sortie()
    w.target(m.fomor)
    m.fomor.status = 1 -- engaged, claim_id stays 0
    w.target(m.crab)
    w.advance(30)
    shows(w, 'Sortie Fomors')
end)

T.test('logging out and in is not a zone line; close_on_logout decides', function()
    local text = [[
return {
    notes = {
        keep = { match = { zone = 154, name = "Fafnir" }, mode = "pinned", close_on_logout = false },
        other = { match = { zone = 154, name = "Nidhogg" }, mode = "pinned" },
    },
}]]
    local w = fakes.boot({ name = 'logout', zone = 154, notes = text })
    local fafnir = w.add_mob({ id = FAFNIR, name = 'Fafnir' })
    w.target(fafnir)
    w.logout()
    T.ok(visible(w), 'close_on_logout = false keeps it, even though close_on_zone is on')
    w.login(154)
    T.ok(visible(w), 'logging back in is not a zone line')
    w.go_to_zone(127)
    T.no(visible(w), 'a real zone change still closes it')

    local nidhogg = w.add_mob({ id = NIDHOGG, name = 'Nidhogg' })
    w.go_to_zone(154)
    w.add_mob(nidhogg)
    w.target(nidhogg)
    T.ok(visible(w))
    w.logout()
    T.no(visible(w), 'the default closes on logout')
end)

T.test('//nt reload re-reads remembered positions', function()
    local w, m = aery({ name = 'reload_positions' })
    w.target(m.fafnir)
    w.drag_note(300, 400)
    T.eq(w.view().x, 300)
    os.remove(w.dir .. 'data/remembered.lua')
    w.command('reload')
    T.eq(w.view().x, 800, 'back to the configured position')
    w.command('toggle', 'off')
    T.lacks(fakes.read(w.dir .. 'data/remembered.lua'), 'x = 300', 'old positions are not written back')
end)

T.test('an existing notes.lua is never replaced by the starter file', function()
    local w = aery({ name = 'no_overwrite' })
    local path = notes_file(w)
    local before = fakes.read(path)
    w.file_exists = function() return false end
    w.command('reload')
    T.eq(fakes.read(path), before)
    T.none(w.chat, 'Created data/notes.lua')
end)

T.test('icons cannot point outside the icons folder', function()
    local w = aery({ name = 'icon_paths' })
    fakes.mkdir(w.dir .. 'data/libraries')
    fakes.write(w.dir .. 'data/libraries/shady.lua', [==[
return { notes = { crab = { match = { zone = 154, name = "Crab" }, icon = [[\\evil-host\share\x.png]] } } }]==])
    w.command('reload')
    T.any(w.chat, 'not a path; using the default')
    local crab = w.add_mob({ index = 0x0CC, name = 'Crab' })
    w.target(crab)
    T.has(w.view().icon.file, 'icons/note.png', 'the default icon instead')
end)

T.test('rapid target changes stay consistent and error-free', function()
    local w, m = sortie()
    local order = { m.fomor, m.crab, m.fomor2, m.boss, false, m.crab }
    for i = 1, 300 do
        w.target(order[i % #order + 1] or nil)
    end
    shows(w, 'Demisang Deleterious', 'the boss note held')
    T.eq(#w.chat, 0, w.chat_text())
end)

T.test('extra libraries are loaded and sandboxed', function()
    local w = aery({ name = 'libraries' })
    fakes.mkdir(w.dir .. 'data/libraries')
    fakes.write(w.dir .. 'data/libraries/friend.lua', [[
return {
    defaults = { color = "blue" },
    notes = {
        crab_tips = { match = { zone = "Dragon's Aery", name = "Crab" }, title = "Friend's crab tips" },
        nidhogg = { match = { zone = 154, name = "Nidhogg" } },
    },
}]])
    fakes.write(w.dir .. 'data/libraries/evil.lua', 'os.execute("echo pwned")\nreturn {}')
    w.command('reload')
    T.any(w.chat, 'Loaded 7 notes from 2 files')
    T.any(w.chat, 'data/libraries/friend.lua: defaults in extra libraries are ignored')
    T.any(w.chat, "data/libraries/friend.lua: note 'nidhogg' already exists")
    T.any(w.chat, "data/libraries/evil.lua:1: attempt to index global 'os'")
    local crab = w.add_mob({ index = 0x0CC, name = 'Crab' })
    w.target(crab)
    shows(w, "Friend's crab tips")
    w.command('edit')
    T.any(w.chat, "is at data/libraries/friend.lua line 4")
end)

T.test('unknown commands and help', function()
    local w = aery({ name = 'help' })
    w.command('frobnicate')
    T.any(w.chat, 'Unknown command "frobnicate"')
    w.clear_chat()
    w.command()
    for _, cmd in ipairs({ 'new [zone:name]', 'append <text>', 'edit [note]', 'list [word]', 'show [note]', 'hide',
        'pin', 'next / prev', 'resetpos [all]', 'demo', 'toggle [on|off]', 'status', 'reload', 'id / rawid' }) do
        T.any(w.chat, cmd, 'help lists ' .. cmd)
    end
    T.ok(#w.chat <= 15, 'help fits in the chat log')
    T.eq(_addon.commands[1], 'nt')
    T.eq(_addon.commands[2], 'noteorious')
    T.eq(#_addon.commands, 2, 'no //mn')
    w.command('?')
    w.command('ID')
    T.any(w.chat, 'You have no target')
end)

T.test('loading while logged out, then logging in', function()
    local w = fakes.boot({ name = 'logged_out', zone = 0, logged_in = false })
    T.eq(#w.chat, 0)
    w.info.logged_in, w.info.zone = true, 154
    w.fire('login', 'Tester')
    local fafnir = w.add_mob({ id = FAFNIR, name = 'Fafnir' })
    w.target(fafnir)
    T.ok(visible(w))
end)

T.test('errors inside event handlers are reported once, not every frame', function()
    local w, m = aery({ name = 'errors' })
    w.ffxi.get_mob_by_index = function() error('boom') end
    w.target(m.fafnir)
    w.target(m.fafnir)
    local count = 0
    for _, line in ipairs(w.chat) do
        if line:find('Internal error', 1, true) then
            count = count + 1
        end
    end
    T.eq(count, 1)
end)
