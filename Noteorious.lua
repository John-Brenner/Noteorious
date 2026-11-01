--[[
    Noteorious - sticky notes for monsters, matched by zone and name.

    Target a monster, type //nt new, write your strategy into the generated
    entry in data/notes.lua, then //nt reload. From then on the note pops up
    whenever you target that monster.

    This file wires Windower events and commands to the modules in core/:
        core/library.lua    loads and validates note libraries
        core/matcher.lua    picks the note for (zone, monster name)
        core/state.lua      decides which note is visible and when it closes
        core/display.lua    draws the note (texts + images)
        core/generator.lua  adds entries to notes.lua for //nt new
        core/identity.lua   zone:name identifiers and note keys
        core/remembered.lua dragged positions and the auto toggle
        core/world.lua      reads game state, parses defeat messages
]]

_addon.name = 'Noteorious'
_addon.author = 'John'
_addon.version = '1.1.0'
_addon.commands = { 'nt', 'noteorious' }

local texts = require('texts')
local images = require('images')
local res = require('resources')

local util = require('core/util')
local library = require('core/library')
local state = require('core/state')
local identity = require('core/identity')
local generator = require('core/generator')
local display = require('core/display')
local remembered = require('core/remembered')
local world = require('core/world')

local ROOT = windower.addon_path
local paths = {
    notes = ROOT .. 'data/notes.lua',
    libraries = ROOT .. 'data/libraries/',
    remembered = ROOT .. 'data/remembered.lua',
    backups = ROOT .. 'data/backups/',
    icons = ROOT .. 'icons/',
}
local NOTES_NAME = 'data/notes.lua'

local CHAT_INFO, CHAT_ERROR = 207, 123
local MAX_PROBLEM_LINES = 8
local WRITE_HINT = 'Make sure Windower can write to the addons/Noteorious/data folder '
    .. '(a Windower folder under Program Files can block this).'

local game = world.new(windower)
local lib = library.empty()   -- replaced by the real library on load
local zones                   -- zone name lookup built from resources
local memory = remembered.fresh()
local view                    -- core/display object
local shown = {}              -- what is on screen: { note, pinned }
local last_tick = 0
local reported_errors = {}
local zoned_in                -- zone id while logged in, nil after logout
local last_load = { failed = false, problems = 0 } -- for //nt status

local fs = {
    read = util.read_file,
    write = util.write_file,
    file_exists = function(path) return windower.file_exists(path) end,
    dir_exists = function(path) return windower.dir_exists(path) end,
    mkdir = function(path) return windower.create_dir(path) end,
    list = function(path) return windower.get_dir(path) end,
    remove = function(path) return os.remove(path) end,
}

--[[ Chat output ]]

local function say(msg)
    windower.add_to_chat(CHAT_INFO, ('[Noteorious] %s'):format(msg))
end

local function complain(msg)
    windower.add_to_chat(CHAT_ERROR, ('[Noteorious] %s'):format(msg))
end

local function report_problems(report)
    local lines = {}
    for _, e in ipairs(report.errors) do
        lines[#lines + 1] = 'Error: ' .. e
    end
    for _, w in ipairs(report.warnings) do
        lines[#lines + 1] = 'Warning: ' .. w
    end
    for i = 1, math.min(#lines, MAX_PROBLEM_LINES) do
        complain(lines[i])
    end
    if #lines > MAX_PROBLEM_LINES then
        complain(('...and %d more. Fix the ones above and //nt reload to see the rest.'):format(#lines - MAX_PROBLEM_LINES))
    end
end

-- Runs an event handler, reporting each distinct error once instead of
-- spamming the chat log every frame.
local function guard(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            err = tostring(err)
            if not reported_errors[err] then
                reported_errors[err] = true
                complain('Internal error (please report it): ' .. err)
            end
        end
    end
end

--[[ Zones ]]

-- Case-insensitive zone name -> ids, built from Windower's resources.
-- English and Japanese names both work, so libraries can be shared.
local function build_zone_index()
    local by_name = {}
    for id, zone in pairs(res.zones) do
        if type(id) == 'number' and type(zone) == 'table' then
            for _, field in ipairs({ 'en', 'ja' }) do
                local name = zone[field]
                if type(name) == 'string' and name ~= '' then
                    local key = name:lower()
                    local ids = by_name[key] or {}
                    by_name[key] = ids
                    local seen = false
                    for _, existing in ipairs(ids) do
                        seen = seen or existing == id
                    end
                    if not seen then
                        ids[#ids + 1] = id
                        table.sort(ids)
                    end
                end
            end
        end
    end
    return {
        lookup = function(name)
            return by_name[util.trim(name):lower()]
        end,
        name_of = function(id)
            local zone = res.zones[id]
            return zone and (zone.name or zone.en) or nil
        end,
    }
end

local function zone_label(id)
    return zones and zones.name_of(id) or ('zone ' .. tostring(id))
end

--[[ Library ]]

local function library_files()
    local files = { { path = paths.notes, name = NOTES_NAME } }
    if windower.dir_exists(paths.libraries) then
        local names = {}
        for _, file in ipairs(windower.get_dir(paths.libraries) or {}) do
            if file:lower():match('%.lua$') then
                names[#names + 1] = file
            end
        end
        table.sort(names)
        for _, file in ipairs(names) do
            files[#files + 1] = { path = paths.libraries .. file, name = 'data/libraries/' .. file }
        end
    end
    return files
end

-- Loads (or reloads) every library. On failure the previous library stays active.
local function load_library(verbose)
    -- Double-checked with io before writing, so an existing file is never replaced.
    if not windower.file_exists(paths.notes) and not util.read_file(paths.notes) then
        if not windower.dir_exists(ROOT .. 'data/') then
            windower.create_dir(ROOT .. 'data/')
        end
        local ok, err = util.write_file(paths.notes, generator.STARTER)
        if ok then
            say(('Created %s for your notes. Target a monster and type //nt new to add one, '
                .. 'or //nt demo to see how notes look.'):format(NOTES_NAME))
        else
            complain(('Could not create %s (%s). %s'):format(NOTES_NAME, tostring(err), WRITE_HINT))
        end
    end

    local new_lib, report = library.load(library_files(), { zones = zones })
    last_load.failed = not new_lib
    if not new_lib then
        report_problems(report)
        if lib.broken then
            complain('No notes are active until the file is fixed. Then use //nt reload.')
        else
            complain('Keeping the notes that were loaded before. Fix the file, then //nt reload.')
        end
        return false
    end

    lib = new_lib
    local problems = #report.errors + #report.warnings
    last_load.problems = problems
    if verbose or problems > 0 then
        say(('Loaded %d note%s from %d file%s%s.'):format(
            report.count, report.count == 1 and '' or 's',
            report.files, report.files == 1 and '' or 's',
            problems > 0 and (' with %d problem%s'):format(problems, problems == 1 and '' or 's') or ''))
        report_problems(report)
    end
    return true
end

-- "data/notes.lua line 42" for a note.
local function locate(note)
    local text = util.read_file(note.source)
    local line = text and generator.find_line(text, note.key)
    if line then
        return ('%s line %d'):format(note.source_name, line)
    end
    return note.source_name
end

--[[ Visibility ]]

-- The best note for a monster record (any mode), or nil. Players never match.
local function note_for(mob)
    if not mob or not mob.is_npc or not mob.zone then
        return nil
    end
    return (lib.matcher:find(mob.zone, mob.name))
end

local st = state.new({ find = note_for, mob_status = game.mob_status })

-- Pushes the state's visible note to the screen when it changed.
local function refresh(force)
    if not view then
        return
    end
    local note, slot = st:visible()
    local pinned = slot ~= nil and slot.how == 'pin'
    if not force and note == shown.note and pinned == shown.pinned then
        return
    end
    shown.note, shown.pinned = note, pinned
    if note then
        view:show(note, { pinned = pinned })
    else
        view:hide()
    end
end

local function save_memory()
    local ok, err = remembered.save(paths.remembered, memory)
    if not ok then
        complain(('Could not save data/remembered.lua (%s), so note positions and the toggle '
            .. 'will not be remembered. %s'):format(tostring(err), WRITE_HINT))
    end
end

-- //nt demo: a built-in manual note drawn with your current defaults. It is
-- never written to a file. It uses the shared note position, so dragging it
-- sets where notes appear.
local DEMO_KEY = '(demo)'
local DEMO = {
    mode = 'manual',
    title = 'Noteorious demo',
    text = [[
        This is how your notes look.
        - Drag this box to choose where notes appear.
        - Fonts, colors and sizes are in the defaults section of data/notes.lua. Save it, then //nt reload.
        - //nt hide closes this note.
    ]],
}

local function demo_note()
    local note = library.build_note(DEMO_KEY, DEMO, lib, { name = 'demo' }, zones, function() end)
    note.demo = true
    return note
end

-- Reload notes and keep whatever is visible in sync with the new definitions.
local function reload(verbose)
    local ok = load_library(verbose)
    if ok then
        st:reload(function(key)
            if key == DEMO_KEY then
                return demo_note() -- redrawn with the reloaded defaults
            end
            return lib.notes[key]
        end)
        refresh(true)
    end
    return ok
end

--[[ Command helpers ]]

local function current_target()
    local mob = game.target()
    if not mob then
        complain('You have no target. Target a monster first, or name one like this: 154:Fafnir')
    end
    return mob
end

-- Turns command arguments into { zone, name, mob? }. Accepts nothing (the
-- current target), "<zone>:<name>", or a raw entity id of a loaded monster.
local function resolve_spec(args)
    local text = util.trim(table.concat(args, ' '))
    text = text:match('^"(.*)"$') or text
    if text == '' then
        local mob = current_target()
        return mob and { zone = mob.zone, name = mob.name, mob = mob } or nil
    end
    if text:match('^%d+$') then
        local id = tonumber(text)
        local mob = game.by_id(id)
        if mob then
            return { zone = mob.zone, name = mob.name, mob = mob }
        end
        local zone = identity.zone_of_entity(id)
        if zone then
            complain(('Entity %d belongs to %s but is not loaded right now, so its name is unknown. '
                .. 'Raw ids only work while the monster is nearby. Target it and use //nt id, or type %d:<monster name>.')
                :format(id, zone_label(zone), zone))
        else
            complain(('%d is not a loaded monster id. Use //nt id on a target for a lasting zone:name identifier.'):format(id))
        end
        return nil
    end
    local zone, name = identity.parse(text, zones and zones.lookup)
    if not zone then
        complain(name)
        return nil
    end
    return { zone = zone, name = name }
end

-- A note by key, or the note matching a target/identifier/raw id.
-- Returns note, spec (spec is nil when a key was given).
local function resolve_note(args)
    local text = util.trim(table.concat(args, ' '))
    if text ~= '' and lib.notes[text] then
        return lib.notes[text]
    end
    local spec = resolve_spec(args)
    if not spec then
        return nil
    end
    if spec.mob and not spec.mob.is_npc then
        complain('That is a player. Notes are for monsters and NPCs.')
        return nil
    end
    local note = lib.matcher:find(spec.zone, spec.name)
    if not note then
        say(('No note matches %s in %s. Create one with //nt new%s'):format(
            spec.name, zone_label(spec.zone), text ~= '' and (' ' .. text) or ''))
    end
    return note, spec
end

local function generator_options()
    return {
        fs = fs,
        evaluate = library.evaluate,
        display_name = NOTES_NAME,
        backup_dir = paths.backups,
        now = function() return os.date('%Y%m%d-%H%M%S') end,
    }
end

-- A file path the way Windows writes it, for pasting into Explorer or an editor.
local function native_path(path)
    return (tostring(path):gsub('/', '\\'))
end

-- Explains why //nt new (entry_lines given) or //nt append could not change
-- notes.lua. The file is never changed when this is called.
local function explain_failure(failure, entry_lines)
    local reason = failure.reason
    if entry_lines and (reason == 'missing_marker' or reason == 'marker_not_on_own_line' or reason == 'verify') then
        windower.copy_to_clipboard(generator.as_text(entry_lines))
        if reason == 'verify' then
            complain(('Could not add the note safely (%s), so %s was not changed.'):format(failure.message, NOTES_NAME))
        elseif reason == 'marker_not_on_own_line' then
            complain(('The generated-notes marker in %s shares a line with other code, so the file was not changed.'):format(NOTES_NAME))
        else
            complain(('%s has no generated-notes marker line, so it was not changed.'):format(NOTES_NAME))
        end
        say('The new entry is on your clipboard: paste it inside  notes = { ... }  and use //nt reload.')
        say('For //nt new to save by itself, this line must sit on its own line inside notes = { ... }:')
        say('    ' .. generator.END_MARKER)
    elseif reason == 'invalid' then
        complain(('%s has an error, so it was not changed: %s'):format(NOTES_NAME, tostring(failure.message)))
        complain('Fix the file, then //nt reload and try again.')
    elseif reason == 'duplicate' then
        complain(("A note named '%s' already exists in %s."):format(tostring(failure.message), NOTES_NAME))
    elseif reason == 'missing' then
        complain(('That note is no longer in %s. Use //nt reload.'):format(NOTES_NAME))
    elseif reason == 'closing' then
        complain(('The text cannot contain %s. Add it by hand instead (//nt edit shows where).'):format(failure.message))
    elseif reason == 'no_text' or reason == 'verify' then
        complain(("Could not add the line safely, so %s was not changed. This works when the note's text is "
            .. 'written as text = [[ ... ]]. Add it by hand instead (//nt edit shows where).'):format(NOTES_NAME))
    else
        complain(('Could not save the change (%s: %s), so %s was not changed. %s'):format(
            reason, tostring(failure.message), NOTES_NAME, WRITE_HINT))
    end
end

-- The note //nt append acts on: the one on screen, else the target's note.
-- Complains (with `hint`) and returns nil when there is none.
local function current_note(hint)
    local note = st:visible()
    if note then
        return note
    end
    if not game.target() then
        complain('No note is showing. ' .. hint)
        return nil
    end
    return resolve_note({})
end

--[[ Commands ]]

local commands = {}

local HELP = {
    'Noteorious (//nt or //noteorious). Your notes are in data/notes.lua.',
    '  new [zone:name] - add a note for your target (or for that monster)',
    '  append <text> - add a line to the note on screen',
    '  edit [note] - find a note in its file (copies the file path)',
    '  list [word] - list your notes',
    '  show [note] - show a note now;  hide - close it',
    '  pin - keep the note on screen (pin again to release it)',
    '  next / prev - turn the pages of a long note',
    '  resetpos [all] - move the note (or every note) back to its spot',
    '  demo - show a sample note to try the look and position',
    '  toggle [on|off] - turn automatic notes on or off',
    '  status - what is loaded and showing',
    '  reload - reload your note files after editing them',
    '  id / rawid - copy the target\'s zone:name / raw entity id',
}

local LIST_LIMIT = 15

local function plural(n, word)
    return ('%d %s%s'):format(n, word, n == 1 and '' or 's')
end

function commands.help()
    for _, line in ipairs(HELP) do
        say(line)
    end
end

function commands.id()
    local mob = current_target()
    if not mob then
        return
    end
    local id = identity.format(mob.zone, mob.name)
    windower.copy_to_clipboard(id)
    say(('Copied %s  (%s in %s)'):format(id, mob.name, zone_label(mob.zone)))
end

function commands.rawid()
    local mob = current_target()
    if not mob then
        return
    end
    windower.copy_to_clipboard(tostring(mob.id))
    say(('Copied raw entity id %d (0x%08X, index %d) for %s.'):format(mob.id, mob.id, mob.index or 0, mob.name))
    say('Raw ids differ per zone and instance; notes use zone + name. Use //nt id for a lasting identifier.')
end

function commands.new(args)
    local spec = resolve_spec(args)
    if not spec then
        return
    end
    if spec.mob and not spec.mob.is_npc then
        complain('That is a player. Notes are for monsters and NPCs.')
        return
    end
    local existing, tier = lib.matcher:find(spec.zone, spec.name)
    if existing and tier == 1 then
        say(("%s already has a note: '%s' in %s. Use //nt edit to find it."):format(spec.name, existing.key, locate(existing)))
        return
    end

    local key = identity.unique_key(identity.slug(spec.name), lib.raw_keys, identity.slug(zone_label(spec.zone)))
    local lines = generator.entry({
        key = key, zone = spec.zone, zone_name = zones and zones.name_of(spec.zone),
        name = spec.name, defaults = lib.raw_defaults,
    })
    local result, failure = generator.add_note(paths.notes, key, lines, generator_options())
    if not result then
        explain_failure(failure, lines)
        return
    end

    reload(false)
    windower.copy_to_clipboard(native_path(paths.notes))
    say(("Added note '%s' (%s, %s) at %s line %s. File path copied."):format(
        key, spec.name, zone_label(spec.zone), NOTES_NAME, tostring(result.line or '?')))
    say('Write the note there and //nt reload, or add lines with //nt append <text>.')
    if existing then
        say(("It takes priority over the group note '%s' for this monster."):format(existing.key))
    end
end

-- //nt edit [note]: without a name, the target's note, else the note on screen.
function commands.edit(args)
    local note
    if #args == 0 and not game.target() then
        note = st:visible()
        if not note then
            complain('No note is showing. Target a monster, or name a note: //nt edit <note key>')
        end
    else
        note = resolve_note(args)
    end
    if not note then
        return
    end
    if note.demo then
        say('The demo note is built into the addon and is not in any file.')
        return
    end
    windower.copy_to_clipboard(native_path(note.source))
    say(("'%s' is at %s. File path copied."):format(note.key, locate(note)))
    if note.rule then
        say(('It matches %s (mode: %s). Save your changes, then //nt reload.'):format(note.rule.desc, note.mode))
    else
        say(('It is a manual note: //nt show %s displays it. Save your changes, then //nt reload.'):format(note.key))
    end
end

-- //nt append <text>: adds a line to the note on screen (or the target's note).
function commands.append(args)
    local line = util.trim(table.concat(args, ' '))
    if line == '' then
        complain('Type the text to add: //nt append <text>')
        return
    end
    local note = current_note('Target a monster that has a note, or create one with //nt new.')
    if not note then
        return
    end
    if note.demo then
        complain('The demo note cannot be changed. Create a real note with //nt new.')
        return
    end
    if note.source ~= paths.notes then
        complain(("'%s' is in %s. //nt append only changes %s; use //nt edit to find the note."):format(
            note.key, note.source_name, NOTES_NAME))
        return
    end
    local result, failure = generator.append(paths.notes, note.key, line, generator_options())
    if not result then
        explain_failure(failure)
        return
    end
    reload(false)
    say(("Added a line to '%s' (%s line %s)."):format(note.key, NOTES_NAME, tostring(result.line or '?')))
end

function commands.show(args)
    local note, spec = resolve_note(args)
    if not note then
        return
    end
    st:show(note, spec and spec.mob)
    refresh()
end

function commands.hide()
    local note = st:hide()
    refresh()
    if not note then
        say('No note is showing.')
    end
end

function commands.pin()
    local target = game.target()
    local what, note = st:pin(note_for(target))
    refresh()
    if what == 'pinned' then
        say(("Pinned '%s'. It stays until //nt pin again or //nt hide."):format(note.title))
    elseif what == 'unpinned' then
        say(("Unpinned '%s'."):format(note.title))
    else
        complain('There is no note to pin. Target a monster that has a note first.')
    end
end

function commands.toggle(args)
    local arg = (args[1] or ''):lower()
    local on
    if arg == 'on' then
        on = true
    elseif arg == 'off' then
        on = false
    else
        on = not st.auto
    end
    st:set_auto(on)
    refresh()
    memory.auto = on
    save_memory()
    say(on and 'Automatic notes are on.' or 'Automatic notes are off. //nt show still displays a note.')
end

-- Reads data/remembered.lua (positions and the auto toggle).
local function load_memory()
    local data, problem = remembered.load(paths.remembered, library.evaluate)
    memory = data
    if problem then
        complain('data/remembered.lua could not be read and will be rewritten: ' .. tostring(problem))
    end
end

function commands.reload()
    load_memory() -- so deleting remembered.lua and reloading resets positions
    st:set_auto(memory.auto)
    reload(true)
end

-- //nt list [word]: note keys and what they match, sorted, at most LIST_LIMIT lines.
function commands.list(args)
    local term = util.trim(table.concat(args, ' ')):lower()
    local found = {}
    for _, note in ipairs(lib.list) do
        local text = (note.key .. '\n' .. note.title .. '\n' .. (note.rule and note.rule.desc or '')):lower()
        if term == '' or text:find(term, 1, true) then
            found[#found + 1] = note
        end
    end
    if #found == 0 then
        if lib.broken then
            complain(('No notes are loaded: %s has an error. Fix it, then //nt reload.'):format(NOTES_NAME))
        elseif term == '' then
            say('You have no notes yet. Target a monster and type //nt new.')
        else
            say(('No notes match "%s".'):format(term))
        end
        return
    end
    table.sort(found, function(a, b) return a.key < b.key end)
    say(term == '' and (plural(#found, 'note') .. ':') or ('%s match "%s":'):format(plural(#found, 'note'), term))
    for i = 1, math.min(#found, LIST_LIMIT) do
        local note = found[i]
        say(('  %s - %s'):format(note.key, note.rule and note.rule.desc or ('manual, //nt show ' .. note.key)))
    end
    if #found > LIST_LIMIT then
        say(('  ...and %d more. Narrow the list: //nt list <word>'):format(#found - LIST_LIMIT))
    end
end

function commands.status()
    local auto = ('Automatic notes are %s.'):format(st.auto and 'on' or 'off')
    if lib.broken then
        complain(('%s No notes are loaded: %s has an error. Fix it, then //nt reload.'):format(auto, NOTES_NAME))
    else
        local loaded = ('%s loaded from %s.'):format(plural(#lib.list, 'note'), plural(#lib.files, 'file'))
        if last_load.failed then
            loaded = loaded .. ' The last //nt reload failed, so these are the notes from before it.'
        elseif last_load.problems > 0 then
            loaded = loaded .. (' The last reload reported %s; //nt reload lists them.'):format(plural(last_load.problems, 'problem'))
        end
        say(auto .. ' ' .. loaded)
    end
    local note, slot = st:visible()
    if not note then
        say('No note is showing.')
        return
    end
    local extra = note.demo and ' (the demo)' or (" ('%s')"):format(note.key)
    if slot.how == 'pin' then
        extra = extra .. ', pinned'
    end
    if view and view.pages > 1 then
        extra = extra .. (', page %d of %d'):format(view.page, view.pages)
    end
    say(('Showing %s%s.'):format(note.title ~= '' and note.title or note.key, extra))
end

function commands.demo()
    st:show(demo_note())
    refresh()
    say('Showing a demo note. Drag it to set where notes appear; //nt hide closes it.')
end

-- //nt resetpos [all]: forgets dragged positions.
function commands.resetpos(args)
    if (args[1] or ''):lower() == 'all' then
        local n = remembered.reset_all(memory)
        save_memory()
        refresh(true)
        say(n > 0 and 'Every note is back at its position from the note files.' or 'No note had been moved.')
        return
    end
    local note = st:visible()
    if not note then
        complain('No note is showing. Show one first, or reset every note with //nt resetpos all.')
        return
    end
    remembered.reset(memory, note)
    save_memory()
    refresh(true)
    if note.own_position then
        say(("'%s' is back at its own position from the note file."):format(note.title))
    else
        say('Notes are back at the default position (defaults.position in data/notes.lua).')
    end
end

local function turn(delta)
    if not (view and shown.note) then
        complain('No note is showing.')
        return
    end
    local _, pages = view:turn(delta)
    if pages <= 1 then
        say('This note fits on one page.')
    end
end

function commands.next()
    turn(1)
end

function commands.prev()
    turn(-1)
end

local ALIASES = { ['?'] = 'help', r = 'reload', unpin = 'pin' }

--[[ Events ]]

windower.register_event('load', guard(function()
    zones = build_zone_index()
    load_memory()
    st.auto = memory.auto
    zoned_in = game.zone()

    view = display.new({
        texts = texts,
        images = images,
        file_exists = function(path) return windower.file_exists(path) end,
        screen = function()
            local s = windower.get_windower_settings()
            return s.ui_x_res, s.ui_y_res
        end,
        icon_dir = paths.icons,
        position = function(note) return remembered.position(memory, note) end,
        moved = function(note, x, y)
            remembered.set_position(memory, note, x, y)
            save_memory()
        end,
        warn = complain,
    })

    load_library(false)
    if game.zone() then
        st:target_changed(game.target())
    end
    refresh(true)
end))

windower.register_event('unload', guard(function()
    if view then
        view:destroy()
        view = nil
    end
end))

windower.register_event('login', guard(function()
    st:target_changed(nil)
    refresh()
end))

windower.register_event('logout', guard(function()
    st:logged_out()
    zoned_in = nil
    lib.matcher:clear()
    refresh()
end))

-- Windower also fires "zone change" when logging in and out. Those are not
-- zone lines: logging out applies close_on_logout, logging in closes nothing.
windower.register_event('zone change', guard(function(new_id, old_id)
    local zone = game.zone()
    if not zone or new_id == 0 then
        st:logged_out()
        zoned_in = nil
    elseif zoned_in == nil or old_id == 0 then
        st:target_changed(nil)
        zoned_in = zone
    else
        st:zone_changed()
        zoned_in = zone
    end
    lib.matcher:clear()
    refresh()
end))

windower.register_event('target change', guard(function(index)
    if zoned_in == nil then
        zoned_in = game.zone() -- logged in without a login zone change
    end
    st:target_changed(game.by_index(index))
    refresh()
end))

-- Defeat messages close notes immediately instead of waiting for the next check.
windower.register_event('incoming chunk', guard(function(id, data)
    if id ~= 0x029 then
        return
    end
    local dead = world.death_from_packet(data)
    if dead and st:tracks(dead) then
        st:mob_died(dead)
        refresh()
    end
end))

-- Every frame: the display re-measures a note for a few frames after it
-- changed (nothing to do otherwise). Then a once-per-second check, only
-- while a note depends on monsters being alive.
windower.register_event('prerender', guard(function()
    if view then
        view:settle()
    end
    if not st:needs_tick() then
        return
    end
    local now = os.time()
    if now == last_tick then
        return
    end
    last_tick = now
    st:tick()
    refresh()
end))

windower.register_event('mouse', guard(function(kind)
    if view then
        view:mouse(kind)
    end
end))

windower.register_event('addon command', function(command, ...)
    command = (command or 'help'):lower()
    command = ALIASES[command] or command
    local handler = commands[command]
    if not handler then
        complain(('Unknown command "%s". Type //nt help for the list.'):format(command))
        return
    end
    local ok, err = pcall(handler, { ... })
    if not ok then
        complain(('//nt %s failed: %s'):format(command, tostring(err)))
    end
end)
