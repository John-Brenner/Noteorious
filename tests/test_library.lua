local T = require('tests/harness')
local fakes = require('tests/fakes')
local library = require('core/library')

local ROOT = NOTEORIOUS_ROOT
local zones = fakes.zones()

-- Writes library files into a temp folder and loads them (first = main).
local function load_texts(texts)
    local dir = fakes.temp_dir('library')
    local files = {}
    for i, text in ipairs(texts) do
        local name = i == 1 and 'notes.lua' or ('extra%d.lua'):format(i)
        fakes.write(dir .. name, text)
        files[i] = { path = dir .. name, name = name }
    end
    return library.load(files, { zones = zones })
end

local function load_text(text)
    return load_texts({ text })
end

-- What a new install gets: the starter notes.lua, plus the shipped examples
-- copied into data/libraries/ (as the examples file tells players to do).
local function shipped()
    local generator = require('core/generator')
    local dir = fakes.temp_dir('shipped')
    fakes.write(dir .. 'notes.lua', generator.STARTER)
    return library.load({
        { path = dir .. 'notes.lua', name = 'data/notes.lua' },
        { path = ROOT .. 'examples/example-notes.lua', name = 'data/libraries/example-notes.lua' },
    }, { zones = zones })
end

T.test('a new install starts with no notes, and loads cleanly', function()
    local generator = require('core/generator')
    local lib, report = load_text(generator.STARTER)
    T.ok(lib, 'loaded')
    T.eq(#report.errors + #report.warnings, 0, table.concat(report.warnings, ' | '))
    T.eq(report.count, 0)
end)

T.test('the shipped examples load as an extra library without problems', function()
    local lib, report = shipped()
    T.ok(lib, 'loaded')
    T.eq(#report.errors, 0, 'errors: ' .. table.concat(report.errors, ' | '))
    T.eq(#report.warnings, 0, 'warnings: ' .. table.concat(report.warnings, ' | '))
    T.eq(report.count, 6)
    T.ok(lib.notes.checklist and lib.notes.checklist.mode == 'manual')
    T.eq(lib.zone_groups.sortie[1], 133)
    T.eq(#lib.zone_groups.sortie, 3)
end)

T.test('the spec example matches as described', function()
    local lib = shipped()
    local m = lib.matcher
    T.eq(m:find(133, 'Demisang Hoodoo').key, 'sortie_fomors', 'ordinary fomor in Sortie')
    T.eq(m:find(275, 'Demisang Hoodoo').key, 'sortie_fomors', 'another Sortie layer')
    T.eq(m:find(189, 'Demisang Deleterious').key, 'demisang_deleterious', 'the boss gets its own note')
    T.eq(m:find(154, 'Demisang Hoodoo'), nil, 'fomors elsewhere get nothing')
    T.eq(m:find(154, 'Fafnir').key, 'dragons_aery_wyrms')
    T.eq(m:find(154, 'Nidhogg').key, 'nidhogg', 'exact beats the names list')
    T.eq(m:find(160, 'Tonberry Pontifex').key, 'tonberries')
    T.eq(m:find(159, 'Tonberry Cutter').key, 'tonberries')
end)

T.test('notes inherit defaults and override them', function()
    local lib = shipped()
    local fomors = lib.notes.sortie_fomors
    T.eq(fomors.mode, 'combat')
    T.eq(fomors.color[1], 255, 'orange')
    T.eq(fomors.color[2], 165)
    T.eq(fomors.font, 'Consolas', 'inherited')
    T.eq(fomors.font_size, 12)
    T.eq(fomors.text, 'General Fomor mechanics:\n- Add strategy here\n- Add warnings here')
    T.eq(lib.notes.nidhogg.title, 'Nidhogg', 'title defaults to the exact name')
    T.eq(lib.notes.tonberries.title, 'Tonberries')
    T.ok(lib.notes.checklist.own_position)
    T.no(fomors.own_position)
    T.has(lib.notes.tonberries.rule.desc, 'names starting with "Tonberry "')
    T.has(lib.notes.tonberries.rule.desc, 'Temple of Uggalepih')
end)

T.test('a missing main file is reported', function()
    local lib, report = library.load({ { path = ROOT .. 'tests/tmp/does_not_exist.lua', name = 'notes.lua' } }, { zones = zones })
    T.eq(lib, nil)
    T.ok(report.fatal)
    T.has(report.errors[1], 'could not be read')
end)

T.test('a syntax error is reported with its line and nothing loads', function()
    local lib, report = load_text('return {\n  notes = {\n    a = { text = "x" \n  },\n}')
    T.eq(lib, nil)
    T.has(report.errors[1], 'notes.lua:')
    T.ok(report.errors[1]:match('notes%.lua:%d+:'), 'has a line number')
end)

T.test('runtime errors and non-table results are reported', function()
    local lib, report = load_text('local x = nil\nreturn { notes = x.y }')
    T.eq(lib, nil)
    T.has(report.errors[1], 'notes.lua:2')
    lib, report = load_text('return "hello"')
    T.eq(lib, nil)
    T.has(report.errors[1], 'must end with')
end)

T.test('the sandbox blocks os, io and require, and refuses bytecode', function()
    local lib, report = load_text('os.execute("echo hi")\nreturn { notes = {} }')
    T.eq(lib, nil)
    T.has(report.errors[1], "'os'")
    lib, report = load_text('return { notes = { a = { text = io.read() } } }')
    T.eq(lib, nil)
    lib, report = load_text('require("socket")\nreturn {}')
    T.eq(lib, nil)
    local bytecode = string.dump(function() return { notes = {} } end)
    local result, err = library.evaluate(bytecode, 'evil.lua')
    T.eq(result, nil)
    T.has(err, 'precompiled')
    result, err = library.evaluate('\239\187\191' .. bytecode, 'evil.lua')
    T.eq(result, nil, 'a byte order mark in front does not get bytecode through')
    T.has(err, 'precompiled')
end)

T.test('a file that never finishes is stopped; the others still load', function()
    local saved = library.INSTRUCTION_LIMIT
    library.INSTRUCTION_LIMIT = 200000
    local lib, report = load_texts({ 'return { notes = { a = { match = { zone = 154, name = "A" } } } }', 'while true do end' })
    library.INSTRUCTION_LIMIT = saved
    T.ok(lib)
    T.ok(lib.notes.a)
    T.any(report.errors, 'extra2.lua: took too long to load')
    local again = load_text('return { notes = {} }')
    T.ok(again, 'normal loading works afterwards')
end)

T.test('a library cannot schedule code to run later', function()
    -- Windower's functions library gives every function :schedule() and :loop().
    local scheduled = 0
    local saved_schedule = coroutine.schedule
    coroutine.schedule = function() scheduled = scheduled + 1 end
    debug.setmetatable(print, { __index = {
        schedule = function(fn, delay) return coroutine.schedule(fn, delay) end,
    } })
    local ok, lib, report = pcall(load_text, 'local f = function() end\nf:schedule(1)\nreturn { notes = {} }')
    debug.setmetatable(print, nil)
    local restored = coroutine.schedule
    coroutine.schedule = saved_schedule
    T.ok(ok, lib)
    T.eq(lib, nil)
    T.has(report.errors[1], 'scheduling code is not allowed')
    T.eq(scheduled, 0)
    T.ok(restored ~= nil and restored ~= saved_schedule, 'the real scheduler is put back afterwards')
end)

T.test('the sandbox cannot change the addon\'s string library', function()
    local lib = load_text('string.format = nil\nreturn { notes = {} }')
    T.ok(lib)
    T.eq(type(string.format), 'function')
end)

T.test('a UTF-8 byte order mark is accepted', function()
    local lib, report = load_text('\239\187\191return { notes = { a = { match = { zone = 154, name = "Fafnir" } } } }')
    T.ok(lib, report.errors[1])
    T.ok(lib.notes.a)
end)

T.test('invalid settings fall back to the inherited value with a warning', function()
    local lib, report = load_text([[
return {
    defaults = { color = "red", font_size = "huge", opacity = 100, wobble = true },
    notes = {
        crab = {
            match = { zone = 154, name = "Crab" },
            color = "purpleish", font_size = "big", mode = "sticky", opacity = 999,
            colour = "blue", width = 3, icon = 42, text = { "not", "a", "string" },
        },
    },
}]])
    T.ok(lib)
    local crab = lib.notes.crab
    T.eq(crab.color[1], 255, 'inherits the default red')
    T.eq(crab.color[2], 90)
    T.eq(crab.font_size, 12, 'built-in size, since the default was invalid too')
    T.eq(crab.mode, 'target')
    T.eq(crab.opacity, 100, 'inherited from defaults')
    T.eq(crab.width, 50)
    T.eq(crab.icon, 'note')
    T.eq(crab.text, '')
    local w = report.warnings
    T.any(w, 'defaults.font_size "huge" must be a number')
    T.any(w, 'defaults.wobble is not a known setting')
    T.any(w, "note 'crab': color \"purpleish\" is not a color name")
    T.any(w, "note 'crab': mode \"sticky\" must be one of")
    T.any(w, "note 'crab': opacity 999 must be from 0 to 255")
    T.any(w, "note 'crab': colour is not a known setting")
    T.any(w, "note 'crab': text must be a string")
end)

T.test('notes with unusable match blocks are skipped, others still load', function()
    local lib, report = load_text([[
return {
    notes = {
        no_zone = { match = { name = "Crab" } },
        bad_zone = { match = { zone = "Atlantis", name = "Crab" } },
        no_name = { match = { zone = 154 } },
        no_match = { text = "hi" },
        not_table = "oops",
        good = { match = { zone = { "Atlantis", 154 }, name = "Crab", typo = 1 } },
        [1] = { match = { zone = 154, name = "Array style" } },
    },
}]])
    T.ok(lib)
    T.eq(report.count, 1)
    T.ok(lib.notes.good)
    local e = report.errors
    T.any(e, "'no_zone' was skipped: match needs a zone")
    T.any(e, "'bad_zone' was skipped: none of its zones could be found")
    T.any(e, "'no_name' was skipped: match needs name, names or name_prefix")
    T.any(e, "'no_match' was skipped: it has no match")
    T.any(e, "'not_table' was skipped")
    T.any(e, 'note #1 has no key')
    T.any(report.warnings, 'unknown zone "Atlantis"')
    T.any(report.warnings, 'match.typo is not a match field')
    T.ok(lib.raw_keys.no_zone, 'skipped keys still count as taken')
end)

T.test('zones resolve by id, name (any case), group, list or "*"', function()
    local lib = load_text([[
return {
    zone_groups = { Aery = { "dragon's aery" }, Broken = { "Nowhere" } },
    notes = {
        by_id = { match = { zone = 154, name = "A" } },
        by_name = { match = { zone = "DRAGON'S AERY", name = "B" } },
        by_group = { match = { zone = "aery", name = "C" } },
        by_list = { match = { zones = { 127, "Valley of Sorrows" }, name = "D" } },
        anywhere = { match = { zone = "*", name = "E" } },
        numeric_string = { match = { zone = "154", name = "F" } },
        japanese = { match = { zone = "Ryuu no Negura", name = "G" } },
    },
}]])
    local m = lib.matcher
    T.eq(m:find(154, 'A').key, 'by_id')
    T.eq(m:find(154, 'B').key, 'by_name')
    T.eq(m:find(154, 'C').key, 'by_group')
    T.eq(m:find(128, 'D').key, 'by_list')
    T.eq(m:find(127, 'D').key, 'by_list')
    T.eq(m:find(9999, 'E').key, 'anywhere')
    T.eq(m:find(154, 'F').key, 'numeric_string')
    T.eq(m:find(154, 'G').key, 'japanese')
    T.eq(lib.zone_groups.broken, nil, 'a group with no valid zones is dropped')
end)

T.test('name lists may be written as name = { ... }', function()
    local lib = load_text('return { notes = { pair = { match = { zone = 154, name = { "Fafnir", "Nidhogg" } } } } }')
    local note, tier = lib.matcher:find(154, 'nidhogg')
    T.eq(note.key, 'pair')
    T.eq(tier, 2)
end)

T.test('manual notes need no match; titles and text are normalized', function()
    local lib, report = load_text([==[
return {
    notes = {
        manual = { mode = "manual", title = "Line one\nline two", text = 42 },
        indented = {
            match = { zone = 154, name = "Fafnir" },
            text = [[
                first
                    nested
                last
            ]],
        },
    },
}]==])
    T.eq(#report.errors, 0)
    T.eq(lib.notes.manual.title, 'Line one line two')
    T.eq(lib.notes.manual.text, '42')
    T.eq(lib.notes.manual.rule, nil)
    T.eq(lib.notes.indented.text, 'first\n    nested\nlast')
    T.eq(lib.notes.indented.title, 'Fafnir')
end)

T.test('duplicate matches are reported with the winner', function()
    local _, report = load_text([[
return { notes = {
    one = { match = { zone = 154, name = "Fafnir" } },
    two = { match = { zone = "Dragon's Aery", name = "fafnir" } },
} }]])
    T.any(report.warnings, "notes 'one' and 'two' both match name \"fafnir\"")
end)

T.test('extra libraries add notes; their defaults are ignored; duplicates keep the first', function()
    local lib, report = load_texts({
        'return { defaults = { color = "red" }, notes = { mine = { match = { zone = 154, name = "Fafnir" } } } }',
        [[return {
            defaults = { color = "blue" },
            zone_groups = { Aery = { 154 } },
            notes = {
                mine = { match = { zone = 154, name = "Nidhogg" } },
                friend = { match = { zone = "Aery", name = "Nidhogg" }, title = "From a friend" },
            },
        }]],
        'this is not lua',
    })
    T.ok(lib)
    T.eq(report.files, 2)
    T.eq(lib.notes.mine.rule.name, 'fafnir', 'first definition wins')
    T.eq(lib.notes.friend.title, 'From a friend')
    T.eq(lib.notes.friend.color[1], 255, 'main defaults apply (red)')
    T.eq(lib.notes.friend.color[2], 90)
    T.eq(lib.notes.friend.source_name, 'extra2.lua')
    T.any(report.warnings, 'extra2.lua: defaults in extra libraries are ignored')
    T.any(report.warnings, "extra2.lua: note 'mine' already exists in an earlier file")
    T.any(report.errors, 'extra3.lua')
    T.any(report.errors, '(file skipped)')
end)

T.test('unknown top-level sections are reported', function()
    local _, report = load_text('return { notes = {}, note = {} }')
    T.any(report.warnings, 'unknown section note')
end)

T.test('library.empty() is usable when nothing could be loaded', function()
    local lib = library.empty()
    T.ok(lib.broken)
    T.eq(lib.matcher:find(154, 'Fafnir'), nil)
    T.eq(lib.defaults.mode, 'target')
end)
