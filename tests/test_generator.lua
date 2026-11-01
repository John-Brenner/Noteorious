local T = require('tests/harness')
local fakes = require('tests/fakes')
local util = require('core/util')
local library = require('core/library')
local generator = require('core/generator')
local identity = require('core/identity')
local world = require('core/world')
local remembered = require('core/remembered')

local ROOT = NOTEORIOUS_ROOT
local zones = fakes.zones()

local fs = {
    read = util.read_file,
    write = util.write_file,
    file_exists = fakes.file_exists,
    dir_exists = fakes.dir_exists,
    mkdir = fakes.mkdir,
    list = fakes.list,
    remove = os.remove,
}

local stamp = 0
local function options(dir)
    return {
        fs = fs,
        evaluate = library.evaluate,
        display_name = 'data/notes.lua',
        backup_dir = dir .. 'backups/',
        now = function()
            stamp = stamp + 1
            return ('20261031-%06d'):format(stamp)
        end,
    }
end

local function entry(key, zone, name)
    return generator.entry({ key = key, zone = zone, zone_name = zones.name_of(zone), name = name, defaults = { mode = 'target', color = 'yellow', icon = 'note' } })
end

local function setup(text)
    local dir = fakes.temp_dir('generator')
    local path = dir .. 'notes.lua'
    fakes.write(path, text or fakes.read(ROOT .. 'data/notes.lua'))
    return dir, path
end

local function load(path)
    return library.load({ { path = path, name = 'notes.lua' } }, { zones = zones })
end

T.test('add_note inserts above the end marker and keeps everything else', function()
    local dir, path = setup()
    local before = fakes.read(path)
    local result, failure = generator.add_note(path, 'king_behemoth', entry('king_behemoth', 127, 'King Behemoth'), options(dir))
    T.ok(result, failure and failure.reason)
    local after = fakes.read(path)

    local marker = after:find(generator.END_MARKER, 1, true)
    local entry_at = after:find('        king_behemoth = {', 1, true)
    T.ok(entry_at and entry_at < marker, 'entry sits above the marker, indented like it')
    T.has(after, 'zone = 127, -- Behemoth\'s Dominion')
    T.has(after, 'name = "King Behemoth",')

    -- Removing the inserted block gives back the original file byte for byte.
    local block_start = after:find('        king_behemoth = {', 1, true)
    local block_end = after:find('        },\n\n', block_start, true) + #'        },\n\n' - 1
    T.eq(after:sub(1, block_start - 1) .. after:sub(block_end + 1), before)

    local lines = util.lines(after)
    T.eq(lines[result.line], '        king_behemoth = {', 'reported line')

    local lib, report = load(path)
    T.eq(#report.errors + #report.warnings, 0, table.concat(report.errors, ' | '))
    T.eq(lib.matcher:find(127, 'King Behemoth').key, 'king_behemoth')
    T.eq(lib.notes.king_behemoth.text, 'Add strategy, warnings and reminders here.')
    T.eq(lib.notes.king_behemoth.mode, 'target', 'the commented overrides stay inactive')
    T.eq(report.count, 7)

    T.ok(fakes.file_exists(result.backup), 'backup written')
    T.eq(fakes.read(result.backup), before, 'backup holds the old file')
end)

T.test('add_note keeps CRLF line endings', function()
    local crlf = fakes.read(ROOT .. 'data/notes.lua'):gsub('\r?\n', '\r\n')
    local dir, path = setup(crlf)
    T.ok(generator.add_note(path, 'crab', entry('crab', 154, 'Crab'), options(dir)))
    local after = fakes.read(path)
    T.no(after:find('[^\r]\n'), 'no bare LF line endings')
    T.ok(load(path).notes.crab)
end)

T.test('add_note refuses to touch a file with errors', function()
    local broken = 'return { notes = { -- [noteorious:generated:end]\n'
    local dir, path = setup(broken)
    local result, failure = generator.add_note(path, 'crab', entry('crab', 154, 'Crab'), options(dir))
    T.eq(result, nil)
    T.eq(failure.reason, 'invalid')
    T.eq(fakes.read(path), broken)
    T.no(fakes.dir_exists(dir .. 'backups/'), 'no backup either')
end)

T.test('add_note without a marker changes nothing', function()
    local text = 'return { notes = { a = { match = { zone = 154, name = "A" } } } }\n'
    local dir, path = setup(text)
    local result, failure = generator.add_note(path, 'crab', entry('crab', 154, 'Crab'), options(dir))
    T.eq(result, nil)
    T.eq(failure.reason, 'missing_marker')
    T.eq(fakes.read(path), text)
end)

T.test('a marker sharing a line with code is refused', function()
    local text = 'return { notes = { x = 1, -- [noteorious:generated:end]\n} }\n'
    local dir, path = setup(text)
    local _, failure = generator.add_note(path, 'crab', entry('crab', 154, 'Crab'), options(dir))
    T.eq(failure.reason, 'marker_not_on_own_line')
end)

T.test('a marker outside the notes table is caught before writing', function()
    local text = 'return {\n    -- [noteorious:generated:end]\n    notes = {},\n}\n'
    local dir, path = setup(text)
    local _, failure = generator.add_note(path, 'crab', entry('crab', 154, 'Crab'), options(dir))
    T.eq(failure.reason, 'verify')
    T.eq(fakes.read(path), text)
end)

T.test('marker text elsewhere in the file does not misplace the entry', function()
    local text = table.concat({
        '--[[ Tip: //mn new writes above this line:',
        '-- [noteorious:generated:end]',
        ']]',
        'return {',
        '    notes = {',
        '        -- [noteorious:generated:end]',
        '    },',
        '}',
        '--[[',
        '    -- [noteorious:generated:end]',
        ']]',
    }, '\n')
    local dir, path = setup(text)
    local result, failure = generator.add_note(path, 'crab', entry('crab', 154, 'Crab'), options(dir))
    T.ok(result, failure and failure.message)
    local lines = util.lines(fakes.read(path))
    T.eq(lines[6], '        crab = {', 'inserted at the marker inside notes')
    T.eq(lines[2], '-- [noteorious:generated:end]', 'decoys untouched')
    T.ok(load(path).notes.crab)
end)

T.test('a write that would lose an existing note is refused', function()
    local text = table.concat({
        'local notes = {',
        '    -- [noteorious:generated:end]',
        '}',
        'if not notes.crab then',
        '    notes.keep = { match = { zone = 154, name = "Keep" } }',
        'end',
        'return { notes = notes }',
    }, '\n')
    local dir, path = setup(text)
    local _, failure = generator.add_note(path, 'crab', entry('crab', 154, 'Crab'), options(dir))
    T.eq(failure.reason, 'verify')
    T.has(failure.message, "note 'keep' would have been lost")
    T.eq(fakes.read(path), text)
end)

T.test('a duplicate key is refused', function()
    local dir, path = setup()
    local _, failure = generator.add_note(path, 'nidhogg', entry('nidhogg', 154, 'Nidhogg'), options(dir))
    T.eq(failure.reason, 'duplicate')
end)

T.test('names with quotes, backslashes and brackets are written safely', function()
    local dir, path = setup()
    local names = { 'Odd "Name" \\ Thing', "Gu'Dha Effigy", 'Ends with ]]', 'Mammet-22 Zeta' }
    for i, name in ipairs(names) do
        local key = identity.slug(name)
        local ok, failure = generator.add_note(path, key, entry(key, 154, name), options(dir))
        T.ok(ok, name .. ': ' .. tostring(failure and (failure.reason .. ' ' .. tostring(failure.message))))
    end
    local lib, report = load(path)
    T.eq(#report.errors, 0, table.concat(report.errors, ' | '))
    for _, name in ipairs(names) do
        local note = lib.matcher:find(154, name)
        T.ok(note, name)
        T.eq(note.title, name)
    end
end)

T.test('the starter library loads and accepts new notes', function()
    local dir, path = setup(generator.STARTER)
    local lib, report = load(path)
    T.ok(lib)
    T.eq(#report.errors + #report.warnings, 0)
    T.eq(report.count, 0)
    local result = generator.add_note(path, 'crab', entry('crab', 154, 'Crab'), options(dir))
    T.ok(result)
    T.eq(load(path).matcher:find(154, 'Crab').key, 'crab')
    T.eq(util.lines(fakes.read(path))[result.line], '        crab = {')
end)

T.test('backups are pruned to the newest few', function()
    local dir, path = setup()
    local saved = generator.BACKUPS_KEPT
    generator.BACKUPS_KEPT = 3
    for i = 1, 5 do
        local key = 'mob_' .. i
        T.ok(generator.add_note(path, key, entry(key, 154, 'Mob ' .. i), options(dir)))
    end
    generator.BACKUPS_KEPT = saved
    local files = fakes.list(dir .. 'backups/')
    T.eq(#files, 3)
end)

T.test('find_line finds note keys, not fields with the same name', function()
    local text = table.concat({
        'return {',            -- 1
        '    defaults = { mode = "target" },', -- 2
        '    notes = {',       -- 3
        '        -- a comment', -- 4
        '        first = {',   -- 5
        '            title = "x",', -- 6
        '        },',          -- 7
        '        title = {',   -- 8
        '        },',          -- 9
        '        ["odd key"] = {},', -- 10
        '    },',
        '}',
    }, '\n')
    T.eq(generator.find_line(text, 'first'), 5)
    T.eq(generator.find_line(text, 'title'), 8)
    T.eq(generator.find_line(text, 'odd key'), 10)
    T.eq(generator.find_line(text, 'missing'), nil)
end)

T.test('identity: format, parse and entity ids', function()
    T.eq(identity.format(154, 'Fafnir'), '154:Fafnir')
    local zone, name = identity.parse(' 154 : Fafnir ', zones.lookup)
    T.eq(zone, 154)
    T.eq(name, 'Fafnir')
    zone, name = identity.parse("Dragon's Aery:Fafnir", zones.lookup)
    T.eq(zone, 154)
    zone, name = identity.parse('133:Name: with colon', zones.lookup)
    T.eq(name, 'Name: with colon')
    T.eq((identity.parse('Fafnir', zones.lookup)), nil)
    local _, msg = identity.parse('Atlantis:Fafnir', zones.lookup)
    T.has(msg, 'Unknown zone "Atlantis"')
    _, msg = identity.parse('Twin:Fafnir', function() return { 1, 2 } end)
    T.has(msg, 'several zones (1, 2)')
    T.eq(identity.zone_of_entity(17408018), 154, 'Fafnir')
    T.eq(identity.zone_of_entity(0x01000000 + 288 * 0x1000 + 5), 288)
    T.eq(identity.zone_of_entity(1000), nil, 'a player id')
end)

T.test('identity: slugs and unique keys', function()
    T.eq(identity.slug("Gu'Dha Effigy"), 'gudha_effigy')
    T.eq(identity.slug('Mammet-22 Zeta'), 'mammet_22_zeta')
    T.eq(identity.slug('22nd Wyvern'), 'mob_22nd_wyvern')
    T.eq(identity.slug('End'), 'end_note')
    T.eq(identity.slug('\131\140\131\147'), 'note', 'non-ASCII names')
    local taken = { fafnir = true, fafnir_dragons_aery = true, fafnir_2 = true }
    T.eq(identity.unique_key('crab', taken, 'x'), 'crab')
    T.eq(identity.unique_key('fafnir', { fafnir = true }, 'dragons_aery'), 'fafnir_dragons_aery')
    T.eq(identity.unique_key('fafnir', taken, 'dragons_aery'), 'fafnir_3')
end)

T.test('world: defeat messages in 0x029 packets', function()
    T.eq(world.death_from_packet(fakes.action_message(1000, 17408018, 6)), 17408018)
    T.eq(world.death_from_packet(fakes.action_message(1000, 17408018, 20)), 17408018)
    T.eq(world.death_from_packet(fakes.action_message(1000, 17408018, 6 + 0x8000)), 17408018, 'high bit ignored')
    T.eq(world.death_from_packet(fakes.action_message(1000, 17408018, 97)), nil, 'player defeated message')
    T.eq(world.death_from_packet(fakes.action_message(1000, 17408018, 15)), nil, 'a miss')
    T.eq(world.death_from_packet('short'), nil)
end)

T.test('world: mob status from mob tables', function()
    local mobs = {
        [1] = { id = 1, status = 0, claim_id = 0 },
        [2] = { id = 2, status = 1, claim_id = 1000 },
        [3] = { id = 3, status = 2, claim_id = 0 },
        [4] = { id = 4, status = 1, claim_id = 50 },
        [5] = { id = 5, status = 0, claim_id = 0, valid_target = false },
        [6] = { id = 6, status = 1, claim_id = 51, valid_target = false },
        [7] = { id = 7, status = 1, claim_id = 0 },
        [50] = { id = 50, in_party = true },
        [51] = { id = 51, in_alliance = true },
    }
    local w = world.new({ ffxi = {
        get_mob_by_id = function(id) return mobs[id] end,
        get_player = function() return { id = 1000 } end,
        get_info = function() return { logged_in = true, zone = 154 } end,
    } })
    T.eq(w.mob_status(1), 'alive')
    T.eq(w.mob_status(2), 'fighting', 'claimed by you')
    T.eq(w.mob_status(3), 'dead')
    T.eq(w.mob_status(4), 'fighting', 'claimed by a party member')
    T.eq(w.mob_status(5), 'gone', 'invalid and idle')
    T.eq(w.mob_status(6), 'fighting', 'untargetable but in your fight')
    T.eq(w.mob_status(7), 'fighting', 'engaged without a claim (Reive, Domain Invasion)')
    T.eq(w.mob_status(99), 'gone')
    mobs[50].in_party = false
    T.eq(w.mob_status(4), 'alive', 'claimed by an outsider')
end)

T.test('remembered positions: shared spot, own spot, and edits win', function()
    local data = remembered.fresh()
    local shared = { key = 'a', position = { x = 800, y = 250 } }
    local own = { key = 'b', position = { x = 10, y = 20 }, own_position = true }
    T.eq(select(1, remembered.position(data, shared)), 800)
    remembered.set_position(data, shared, 300.4, 400.6)
    local x, y = remembered.position(data, { key = 'other', position = { x = 800, y = 250 } })
    T.eq(x, 300, 'other notes share the default spot')
    T.eq(y, 401)
    remembered.set_position(data, own, 5, 6)
    T.eq(select(1, remembered.position(data, own)), 5)
    x = remembered.position(data, { key = 'a', position = { x = 900, y = 100 } })
    T.eq(x, 900, 'a changed configured position beats the old drag')
end)

T.test('remembered data round-trips and survives a corrupt file', function()
    local dir = fakes.temp_dir('remembered')
    local path = dir .. 'remembered.lua'
    local data = remembered.fresh()
    data.auto = false
    remembered.set_position(data, { key = 'a', position = { x = 1, y = 2 } }, 3, 4)
    T.ok(remembered.save(path, data))
    local back = remembered.load(path, library.evaluate)
    T.eq(back.auto, false)
    T.eq(back.positions['*'].x, 3)
    fakes.write(path, 'return {{{')
    local fresh, problem = remembered.load(path, library.evaluate)
    T.eq(fresh.auto, true)
    T.ok(problem)
    fakes.write(path, 'return { auto = "yes", positions = { ["*"] = { x = "a" } } }')
    fresh = remembered.load(path, library.evaluate)
    T.eq(fresh.auto, true)
    T.eq(fresh.positions['*'], nil)
    local missing = remembered.load(dir .. 'nope.lua', library.evaluate)
    T.eq(missing.auto, true)
end)
