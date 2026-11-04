--[[
    The real Noteorious.lua running in a fake Windower. Each test starts a
    fresh copy of the addon on its own data/notes.lua in TEST_DIR.
]]

local T = require('tests/harness')

local ROOT, DIR = NOTEORIOUS_ROOT, TEST_DIR
local NOTES, BACKUP = DIR .. 'data/notes.lua', DIR .. 'data/notes.lua.bak'
local ZONES = { [154] = { id = 154, en = "Dragon's Aery" }, [100] = { id = 100, en = 'West Ronfaure' } }

local function read(path)
    local file = io.open(path, 'rb')
    if not file then
        return nil
    end
    local text = file:read('*a')
    file:close()
    return text
end

local function write(path, text)
    local file = assert(io.open(path, 'wb'))
    file:write(text)
    file:close()
end

local function copy(t)
    local out = {}
    for k, v in pairs(t) do
        out[k] = type(v) == 'table' and copy(v) or v
    end
    return out
end

-- The notes file as data, the way the addon reads it.
local function file_data()
    local chunk = assert(loadstring(read(NOTES), '=notes'))
    setfenv(chunk, {})
    return chunk()
end

-- Starts the addon with `source` as data/notes.lua (nil: no file yet).
local function start(source)
    os.remove(NOTES)
    os.remove(BACKUP)
    if source then
        write(NOTES, source)
    end
    local w = { chat = {}, events = {}, zone = 154 }
    w.box = { visible = false, body = '' }
    function w.box.show(self) self.visible = true end
    function w.box.hide(self) self.visible = false end
    function w.box.destroy() end

    windower = {
        addon_path = DIR,
        add_to_chat = function(_, msg) w.chat[#w.chat + 1] = msg end,
        register_event = function(...)
            local names = { ... }
            local fn = table.remove(names)
            for _, name in ipairs(names) do
                w.events[name] = fn
            end
        end,
        file_exists = function(path) return read(path) ~= nil end,
        ffxi = {
            get_info = function() return { zone = w.zone } end,
            get_mob_by_target = function() return w.target end,
        },
    }
    package.loaded.config = { load = copy }
    package.loaded.texts = { new = function() return w.box end }
    package.loaded.resources = { zones = ZONES }
    _addon = {}
    dofile(ROOT .. 'Noteorious.lua')

    function w.cmd(...)
        w.events['addon command'](...)
    end
    function w.target_mob(name, is_npc)
        w.target = name and { name = name, is_npc = is_npc ~= false } or nil
        w.events['target change'](0)
    end
    function w.last()
        return w.chat[#w.chat] or ''
    end
    w.events.load()
    return w
end

local function shows(w, needle, label)
    T.ok(w.box.visible, (label or '') .. ' visible')
    T.has(w.box.body, needle, label)
end

local FAFNIR = [==[
return {
    ["dragon's aery"] = {
        ["FAFNIR"] = [[
            - Stay at its sides.
              - Spike Flail hits behind it.
        ]],
    },
    ["West Ronfaure"] = {
        ["Jaggedy-Eared Jack"] = [[Hops around.]],
    },
}
]==]

T.test('first load creates a notes file that loads back empty', function()
    local w = start(nil)
    T.any(w.chat, 'Created data/notes.lua')
    T.eq(next(file_data()), nil)
    T.no(w.box.visible)
end)

T.test('targeting shows the note by zone and name, ignoring case', function()
    local w = start(FAFNIR)
    w.target_mob('Fafnir')
    shows(w, 'FAFNIR') -- the title is spelled as in the file
    -- Shared indentation and the blank first and last lines are removed.
    T.has(w.box.body, 'FAFNIR\\cr\n- Stay at its sides.\n  - Spike Flail hits behind it.')
    T.lacks(w.box.body, '            -')

    w.target_mob('Nidhogg')
    T.no(w.box.visible, 'other monster')
    w.target_mob('Fafnir', false)
    T.no(w.box.visible, 'a player with the same name')
    w.zone = 100
    w.target_mob('Fafnir')
    T.no(w.box.visible, 'same name in another zone')
    w.target_mob(nil)
    T.no(w.box.visible, 'no target')
end)

-- Text in the file ends with a newline, so the closing ]] sits on its own
-- line. The addon removes it when loading.
T.test('add starts a note, appends lines and writes a file that loads back', function()
    local w = start(nil)
    w.target_mob('Fafnir')
    T.no(w.box.visible)
    w.cmd('add', 'Stay', 'at', 'its', 'sides.')
    shows(w, 'Stay at its sides.')
    w.cmd('add', 'Odd ]] and ]=] text')
    shows(w, 'Odd ]] and ]=] text')
    T.eq(file_data()["Dragon's Aery"].Fafnir, 'Stay at its sides.\nOdd ]] and ]=] text\n')

    w.cmd('reload')
    T.has(w.last(), 'Loaded 1 note.')
    shows(w, 'Stay at its sides.\nOdd ]] and ]=] text', 'after reload')
end)

T.test('add keeps the spelling in the file and changes saved since the last reload', function()
    local w = start(FAFNIR)
    local edited = FAFNIR:gsub('Hops around.', 'Hops around a lot.')
    write(NOTES, edited)
    w.target_mob('Fafnir')
    w.cmd('add', 'Have a way to remove terror.')
    local data = file_data()
    T.eq(data["dragon's aery"].FAFNIR, '- Stay at its sides.\n  - Spike Flail hits behind it.\nHave a way to remove terror.\n')
    T.eq(data["Dragon's Aery"], nil, 'no second spelling of the zone')
    T.eq(data['West Ronfaure']['Jaggedy-Eared Jack'], 'Hops around a lot.\n')
    T.eq(read(BACKUP), edited, 'backup of the file before the change')
end)

T.test('a file with a mistake is never overwritten, and the previous notes stay active', function()
    local w = start(FAFNIR)
    local broken = FAFNIR:gsub('}%s*$', '')
    write(NOTES, broken)
    w.cmd('reload')
    T.any(w.chat, 'data/notes.lua was not loaded: data/notes.lua:')
    w.target_mob('Fafnir')
    shows(w, 'Stay at its sides.', 'previous notes')
    w.cmd('add', 'Lost?')
    T.has(w.last(), 'has a mistake, so nothing was added')
    T.eq(read(NOTES), broken)
end)

T.test('a Noteorious 1.x file is refused, not converted or overwritten', function()
    local old = 'return { defaults = { font = "Arial" }, notes = { fafnir = { match = { zone = 154, name = "Fafnir" }, text = [[x]] } } }'
    local w = start(old)
    T.any(w.chat, 'Noteorious 1.x')
    w.target_mob('Fafnir')
    w.cmd('add', 'hello')
    T.eq(read(NOTES), old)
end)

T.test('show keeps a note up across targets until hide', function()
    local w = start(FAFNIR)
    w.cmd('show', 'jaggedy-eared', 'jack')
    shows(w, 'Hops around.', 'found in another zone by name')
    w.target_mob('Fafnir')
    shows(w, 'Hops around.', 'kept over the target note')
    w.zone, w.target = 100, nil
    w.events['zone change'](100, 154)
    shows(w, 'Hops around.', 'kept through zoning')
    w.zone = 154
    w.events['zone change'](154, 100)
    w.cmd('hide')
    T.no(w.box.visible)
    w.target_mob('Fafnir')
    shows(w, 'Stay at its sides.', 'target notes again after hide')

    w.cmd('show')
    w.target_mob(nil)
    shows(w, 'Stay at its sides.', 'show without a name keeps the target note')
    w.cmd('add', 'Added while shown.')
    T.has(w.last(), 'Added to FAFNIR')
    shows(w, 'Added while shown.', 'add goes to the shown note without a target')
    w.events.logout()
    T.no(w.box.visible, 'logout closes it')
end)

T.test('long lines wrap at spaces, and color codes take no room', function()
    local red = '\\cs(255,90,90)'
    local text = 'Intro\n  ' .. red .. 'Careful:\\cr ' .. ('word '):rep(20)
    local w = start('return { ["Dragon\'s Aery"] = { Fafnir = [[' .. text .. ']] } }')
    w.target_mob('Fafnir')
    local lines = {}
    for line in (w.box.body .. '\n'):gmatch('(.-)\n') do
        lines[#lines + 1] = line
    end
    T.eq(lines[2], 'Intro')
    T.ok(#lines > 4, 'wrapped into several lines')
    for i = 3, #lines do
        local visible = lines[i]:gsub('\\cs%b()', ''):gsub('\\cr', '')
        T.ok(#visible <= 50, 'line ' .. i .. ' fits')
        T.ok(lines[i]:match('^  %S'), 'line ' .. i .. ' keeps the indentation')
    end
    T.has(lines[3], '  ' .. red .. 'Careful:\\cr word word')
end)

T.test('unknown zone names are reported on load', function()
    local w = start('return { ["Dragons Aery"] = { Fafnir = [[x]] } }')
    T.any(w.chat, 'Unknown zone "Dragons Aery"')
end)

T.test('add and show explain what is missing', function()
    local w = start(FAFNIR)
    w.cmd('add', 'text')
    T.has(w.last(), 'Target a monster first.')
    w.target_mob('Some Player', false)
    w.cmd('add', 'text')
    T.has(w.last(), 'That is a player.')
    w.cmd('show', 'Nobody')
    T.has(w.last(), 'No note for "Nobody"')
    w.cmd('bogus')
    T.any(w.chat, 'add <text>', 'unknown commands show help')
end)

T.test('list shows notes matching a word', function()
    local w = start(FAFNIR)
    w.cmd('list')
    T.any(w.chat, '2 notes:')
    w.chat = {}
    w.cmd('list', 'ronfaure')
    T.any(w.chat, '1 note:')
    T.any(w.chat, 'Jaggedy-Eared Jack (West Ronfaure)')
    T.none(w.chat, 'FAFNIR')
end)
