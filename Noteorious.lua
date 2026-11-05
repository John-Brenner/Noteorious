--[[
    Noteorious: sticky notes for monsters.

    Target a monster and its note pops up. Notes live in data/notes.lua,
    grouped by zone name and monster name. //nt add <text> adds a line to
    your target's note; for longer changes, edit the file and //nt reload.
    Font, colors and position are in data/settings.xml. Drag the note to
    move it.
]]

_addon.name = 'Noteorious'
_addon.author = 'John'
_addon.version = '2.0.0'
_addon.commands = { 'nt', 'noteorious' }

local config = require('config')
local texts = require('texts')
local res = require('resources')

local NOTES_PATH = windower.addon_path .. 'data/notes.lua'
local BACKUP_PATH = windower.addon_path .. 'data/notes.lua.bak'
local LIST_LIMIT = 20

local defaults = {
    pos = { x = 800, y = 250 },
    bg = { alpha = 220, red = 18, green = 18, blue = 26 },
    padding = 6,
    text = { font = 'Consolas', size = 12, red = 255, green = 255, blue = 255 },
    title = { red = 255, green = 235, blue = 100 }, -- color of the monster name
    wrap = 50, -- wrap lines at this many characters (0 = never)
}

local settings = config.load(defaults) -- also creates the data folder
local box = texts.new('${body}', settings) -- dragging saves the position

local notes = {}   -- zone name -> monster name -> text, as in the file
local index = {}   -- lowercase zone -> lowercase name -> { zone, name, text }
local pinned       -- note kept on screen by //nt show, until //nt hide

local HEADER = [[
-- Noteorious notes: zone name -> monster name -> note text.
-- Edit this file, save it, then type //nt reload in game.
-- //nt add rewrites this file, so comments you add here are not kept.
-- Colors inside a note: \cs(255,90,90)red words\cr
]]

--[[ Chat ]]

local function say(msg)
    windower.add_to_chat(207, '[Noteorious] ' .. msg)
end

local function warn(msg)
    windower.add_to_chat(123, '[Noteorious] ' .. msg)
end

--[[ Helpers ]]

local function trim(s)
    return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function sorted_keys(t)
    local keys = {}
    for key in pairs(t) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

-- Note text without surrounding blank lines or the indentation shared by
-- every line, so text can be indented to match the file.
local function tidy(text)
    text = text:gsub('\r\n?', '\n'):gsub('^%s*\n', ''):gsub('%s+$', '')
    local indent
    for line in text:gmatch('[^\n]+') do
        if line:find('%S') then
            local n = #line:match('^[ \t]*')
            indent = indent and math.min(indent, n) or n
        end
    end
    if indent and indent > 0 then
        text = text:gsub('[^\n]+', function(line) return line:sub(indent + 1) end)
    end
    return text
end

-- Adds `line` to `out`, broken at spaces into pieces of at most `width`
-- visible characters (color codes take no room).
local function wrap(line, width, out)
    local function len(s)
        return #(s:gsub('\\cs%b()', ''):gsub('\\cr', ''))
    end
    if width <= 0 or len(line) <= width then
        out[#out + 1] = line
        return
    end
    local indent = line:match('^%s*')
    local current
    for word in line:gmatch('%S+') do
        if current and len(current) + 1 + len(word) > width then
            out[#out + 1] = current
            current = nil
        end
        current = current and (current .. ' ' .. word) or (indent .. word)
    end
    out[#out + 1] = current or ''
end

--[[ Notes file ]]

local function write_file(path, text)
    local file, err = io.open(path, 'wb')
    if not file then
        return nil, err
    end
    local ok, werr = file:write(text)
    file:close()
    return ok ~= nil, werr
end

-- A Lua long string holding `text`, with enough '=' to contain any ]].
local function long_string(text)
    local eq = ''
    while text:find(']' .. eq .. ']', 1, true) do
        eq = eq .. '='
    end
    return '[' .. eq .. '[\n' .. text .. '\n]' .. eq .. ']'
end

local function serialize(data)
    local out = { HEADER .. 'return {' }
    for _, zone in ipairs(sorted_keys(data)) do
        out[#out + 1] = ('    [%q] = {'):format(zone)
        for _, name in ipairs(sorted_keys(data[zone])) do
            out[#out + 1] = ('        [%q] = %s,'):format(name, long_string(data[zone][name]))
        end
        out[#out + 1] = '    },'
    end
    out[#out + 1] = '}'
    return table.concat(out, '\n') .. '\n'
end

-- Reads data/notes.lua. Returns notes, source text or nil, problem.
-- The file runs with no access to anything, so it can only build tables.
local function read_notes()
    local file = io.open(NOTES_PATH, 'rb')
    if not file then
        return nil, 'data/notes.lua could not be read'
    end
    local source = file:read('*a')
    file:close()
    source = source:gsub('^\239\187\191', '') -- byte order mark some editors add
    if source:byte(1) == 27 then
        return nil, 'precompiled Lua is not accepted'
    end
    local chunk, err = loadstring(source, '@data/notes.lua')
    if not chunk then
        return nil, err
    end
    setfenv(chunk, {})
    local ok, data = pcall(chunk)
    if not ok then
        return nil, tostring(data)
    end
    if type(data) ~= 'table' then
        return nil, 'data/notes.lua must end with  return { ... }'
    end
    if data.notes ~= nil or data.defaults ~= nil then
        return nil, 'it is from Noteorious 1.x, which 2.0 cannot read. Rename it, type //nt reload '
            .. 'to start a new one, and copy your notes into it.'
    end
    for zone, mobs in pairs(data) do
        if type(zone) ~= 'string' or type(mobs) ~= 'table' then
            return nil, ('%s: each zone must look like  ["Zone name"] = { ... }'):format(tostring(zone))
        end
        for name, text in pairs(mobs) do
            if type(name) ~= 'string' or type(text) ~= 'string' then
                return nil, ('%s, %s: each note must look like  ["Monster name"] = [[ text ]]'):format(zone, tostring(name))
            end
            mobs[name] = tidy(text)
        end
    end
    return data, source
end

local function build_index(data)
    local out = {}
    for zone, mobs in pairs(data) do
        local z = zone:lower()
        out[z] = out[z] or {}
        for name, text in pairs(mobs) do
            out[z][name:lower()] = { zone = zone, name = name, text = text }
        end
    end
    return out
end

local function use(data)
    notes, index = data, build_index(data)
    if pinned then
        local mobs = index[pinned.zone:lower()]
        pinned = mobs and mobs[pinned.name:lower()]
    end
end

-- Loads data/notes.lua, creating it on first use. After a mistake the
-- previous notes stay active. Returns true when the file was loaded.
local function load_notes()
    if not windower.file_exists(NOTES_PATH) then
        local ok, err = write_file(NOTES_PATH, serialize({}))
        if ok then
            say('Created data/notes.lua. Target a monster and type //nt add <text> to write a note.')
        else
            warn('Could not create data/notes.lua: ' .. tostring(err))
        end
    end
    local data, err = read_notes()
    if not data then
        warn('data/notes.lua was not loaded: ' .. tostring(err))
        return false
    end
    use(data)
    return true
end

-- Warns about zones in the file that match no zone name (usually a typo).
local function check_zones()
    local known = {}
    for _, zone in pairs(res.zones) do
        if type(zone) == 'table' and zone.en then
            known[zone.en:lower()] = true
        end
    end
    for _, zone in ipairs(sorted_keys(notes)) do
        if not known[zone:lower()] then
            warn(('Unknown zone "%s" in data/notes.lua, so its notes never show. Check the spelling.'):format(zone))
        end
    end
end

--[[ Display ]]

local function current_zone()
    local info = windower.ffxi.get_info()
    local zone = info and info.zone and res.zones[info.zone]
    return zone and zone.en
end

local function note_for(zone, name)
    local mobs = zone and index[zone:lower()]
    return mobs and mobs[name:lower()]
end

local function target_note()
    local mob = windower.ffxi.get_mob_by_target('t')
    return mob and mob.is_npc and note_for(current_zone(), mob.name) or nil
end

local function refresh()
    local note = pinned or target_note()
    if not note then
        box:hide()
        return
    end
    local c = settings.title
    local lines = { ('\\cs(%d,%d,%d)%s\\cr'):format(c.red, c.green, c.blue, note.name) }
    if note.text ~= '' then
        for line in (note.text .. '\n'):gmatch('(.-)\n') do
            wrap(line, settings.wrap, lines)
        end
    end
    box.body = table.concat(lines, '\n')
    box:show()
end

--[[ Commands ]]

local commands = {}

function commands.help()
    say('Commands (//nt or //noteorious):')
    say('  add <text>   add a line to your target\'s note (starts one if needed)')
    say('  show [name]  keep a note on screen: your target\'s, or a monster\'s by name')
    say('  hide         close the note')
    say('  list [word]  list your notes')
    say('  reload       reload data/notes.lua after editing it')
    say('Notes file: ' .. NOTES_PATH)
end

-- //nt add <text>: your target's note, or the note kept up by //nt show.
function commands.add(args)
    local line = trim(table.concat(args, ' '))
    if line == '' then
        warn('Type the text to add: //nt add <text>')
        return
    end
    local zone, name
    local mob = windower.ffxi.get_mob_by_target('t')
    if mob then
        if not mob.is_npc then
            warn('That is a player. Notes are for monsters.')
            return
        end
        zone, name = current_zone(), mob.name
    elseif pinned then
        zone, name = pinned.zone, pinned.name
    end
    if not (zone and name) then
        warn('Target a monster first.')
        return
    end

    -- Read the file again, so changes saved since the last reload are kept.
    local data, source = read_notes()
    if not data then
        warn('data/notes.lua has a mistake, so nothing was added: ' .. tostring(source))
        return
    end
    use(data)
    local existing = note_for(zone, name) -- keep the spelling used in the file
    if existing then
        zone, name = existing.zone, existing.name
    end
    notes[zone] = notes[zone] or {}
    local old = notes[zone][name]
    notes[zone][name] = old and old ~= '' and (old .. '\n' .. line) or line

    local ok, err = write_file(BACKUP_PATH, source)
    if not ok then
        warn('Could not write data/notes.lua.bak, so nothing was added: ' .. tostring(err))
    else
        ok, err = write_file(NOTES_PATH, serialize(notes))
        if not ok then
            warn(('Could not save data/notes.lua (%s). The previous version is in data/notes.lua.bak.')
                :format(tostring(err)))
        end
    end
    if not ok then
        notes[zone][name] = old -- back to what the file held
        if next(notes[zone]) == nil then
            notes[zone] = nil
        end
        return
    end
    use(notes)
    refresh()
    say(('Added to %s (%s).'):format(name, zone))
end

function commands.show(args)
    local name = trim(table.concat(args, ' '))
    local note
    if name == '' then
        note = target_note()
        if not note then
            warn('Your target has no note. To show one by name: //nt show <monster name>')
            return
        end
    else
        note = note_for(current_zone(), name)
        if not note then
            local lname = name:lower()
            for _, zone in ipairs(sorted_keys(index)) do
                note = note or index[zone][lname]
            end
        end
        if not note then
            warn(('No note for "%s". //nt list shows your notes.'):format(name))
            return
        end
    end
    pinned = note
    refresh()
end

function commands.hide()
    pinned = nil
    box:hide()
end

function commands.list(args)
    local word = trim(table.concat(args, ' ')):lower()
    local found = {}
    for _, zone in ipairs(sorted_keys(notes)) do
        for _, name in ipairs(sorted_keys(notes[zone])) do
            if (name .. '\n' .. zone):lower():find(word, 1, true) then
                found[#found + 1] = ('  %s (%s)'):format(name, zone)
            end
        end
    end
    if #found == 0 then
        say(word == '' and 'No notes yet. Target a monster and type //nt add <text>.'
            or ('No notes match "%s".'):format(word))
        return
    end
    say(('%d note%s:'):format(#found, #found == 1 and '' or 's'))
    for i = 1, math.min(#found, LIST_LIMIT) do
        say(found[i])
    end
    if #found > LIST_LIMIT then
        say(('  ...and %d more. Narrow it down: //nt list <word>'):format(#found - LIST_LIMIT))
    end
end

function commands.reload()
    if load_notes() then
        check_zones()
        refresh()
        local count = 0
        for _, mobs in pairs(notes) do
            for _ in pairs(mobs) do
                count = count + 1
            end
        end
        say(('Loaded %d note%s.'):format(count, count == 1 and '' or 's'))
    end
end

--[[ Events ]]

windower.register_event('load', function()
    if load_notes() then
        check_zones()
    end
    refresh()
end)

windower.register_event('target change', 'zone change', 'login', refresh)

windower.register_event('logout', function()
    pinned = nil
    box:hide()
end)

windower.register_event('unload', function()
    box:destroy()
end)

windower.register_event('addon command', function(command, ...)
    local handler = commands[(command or 'help'):lower()] or commands.help
    handler({ ... })
end)
