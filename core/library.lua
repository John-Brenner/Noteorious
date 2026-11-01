--[==[
    Noteorious - core/library.lua

    Loads note libraries: data/notes.lua (your main file) plus any extra
    files dropped into data/libraries/. A library is a plain Lua file that
    returns a table, in the style of a GearSwap user file:

        return {
            defaults    = { ... },   -- main file only
            zone_groups = { ... },   -- optional named lists of zones
            notes       = { key = { match = { ... }, title = ..., text = [[...]] }, ... },
        }

    Files run in a sandbox (string/table/math only, no io/os/require/debug),
    so a library shared by another player cannot read or write files or run
    commands. Precompiled bytecode is refused, a file that runs too long is
    stopped, and scheduling code to run later is blocked while it loads.

    Problems are collected, not thrown:
      * a broken main file      -> load() returns nil; the caller keeps its old library
      * a broken extra library  -> that file is skipped
      * a broken note           -> that note is skipped
      * a broken setting        -> warning, the inherited value is used
]==]

local util = require('core/util')
local settings = require('core/settings')
local matcher = require('core/matcher')

local library = {}

local SAFE_GLOBALS = { 'assert', 'error', 'ipairs', 'next', 'pairs', 'pcall', 'select', 'tonumber', 'tostring', 'type', 'unpack' }
local SAFE_LIBS = { 'string', 'table', 'math' }
local TOP_LEVEL = { defaults = true, zone_groups = true, notes = true }
local NOTE_ONLY = { match = true, title = true, text = true }
local MATCH_FIELDS = { zone = true, zones = true, name = true, names = true, name_prefix = true }

function library.sandbox()
    local env = {}
    for _, name in ipairs(SAFE_GLOBALS) do
        env[name] = _G[name]
    end
    for _, name in ipairs(SAFE_LIBS) do
        -- Shallow copies of the functions and constants only, so a library
        -- file cannot replace functions the addon uses. (In Windower these
        -- tables are extended by the tables/strings/maths libraries; nested
        -- tables in them are deliberately not copied or exposed.)
        local copy = {}
        for key, value in pairs(_G[name]) do
            local kind = type(value)
            if kind == 'function' or kind == 'number' then
                copy[key] = value
            end
        end
        env[name] = copy
    end
    return env
end

-- Note files only build tables; this is far more work than any of them needs.
library.INSTRUCTION_LIMIT = 10000000

local function refuse()
    error('scheduling code is not allowed in note files', 2)
end

-- Runs a compiled library chunk with guards against files that never finish
-- or that try to leave code running after loading (Windower's functions
-- library gives every function :schedule() and :loop() methods).
local function run_guarded(fn, chunkname)
    if jit and jit.off then
        jit.off(fn, true) -- count hooks only fire in interpreted code
    end
    local co = coroutine
    local schedule, sleep = co.schedule, co.sleep
    if schedule then co.schedule = refuse end
    if sleep then co.sleep = refuse end
    local sethook = debug and debug.sethook
    if sethook then
        sethook(function()
            error(chunkname .. ': took too long to load (an endless loop?)', 0)
        end, '', library.INSTRUCTION_LIMIT)
    end
    local ok, result = pcall(fn)
    if sethook then
        sethook()
    end
    co.schedule, co.sleep = schedule, sleep
    return ok, result
end

-- Compiles and runs Lua source in the sandbox. Returns the table it returns,
-- or nil plus an error message that includes the file name and line.
function library.evaluate(text, chunkname)
    if type(text) ~= 'string' then
        return nil, chunkname .. ': could not be read'
    end
    if text:sub(1, 3) == '\239\187\191' then
        text = text:sub(4) -- UTF-8 byte order mark added by some editors
    end
    -- Checked after removing the BOM: Lua would run precompiled bytecode, which
    -- is not verified and could escape the sandbox.
    if text:byte(1) == 27 then
        return nil, chunkname .. ': precompiled Lua files are not accepted'
    end
    local env = library.sandbox()
    local fn, err
    if setfenv then
        fn, err = loadstring(text, '@' .. chunkname)
        if fn then
            setfenv(fn, env)
        end
    else
        fn, err = load(text, '@' .. chunkname, 't', env)
    end
    if not fn then
        return nil, tostring(err)
    end
    local ok, result = run_guarded(fn, chunkname)
    if not ok then
        return nil, tostring(result)
    end
    if type(result) ~= 'table' then
        return nil, ('%s: the file must end with  return { ... }  (it returned %s)'):format(chunkname, type(result))
    end
    return result
end

function library.read(path, chunkname)
    local text, err = util.read_file(path)
    if not text then
        return nil, ('%s: could not be read (%s)'):format(chunkname, tostring(err))
    end
    return library.evaluate(text, chunkname)
end

-- A library with no notes, used when the main file cannot be loaded at all.
function library.empty()
    local lib = {
        notes = {}, list = {}, raw_keys = {}, zone_groups = {}, files = {},
        raw_defaults = util.copy(settings.builtin),
        defaults = settings.normalized_builtin(),
        broken = true,
    }
    lib.matcher = matcher.new(lib.list)
    return lib
end

-- Resolves one zone reference: a zone id, a zone name, a zone group name,
-- or "*" / "any". Returns a list of ids, the string '*', or nil + problem.
function library.resolve_zone(z, groups, zones)
    if type(z) == 'number' then
        if z < 0 or z ~= math.floor(z) then
            return nil, ('zone %s is not a valid zone id'):format(tostring(z))
        end
        return { z }
    end
    if type(z) ~= 'string' then
        return nil, 'zones must be zone names, zone ids or zone group names'
    end
    local s = util.trim(z)
    if s == '*' or s:lower() == 'any' then
        return '*'
    end
    if tonumber(s) then
        return library.resolve_zone(tonumber(s), groups, zones)
    end
    local group = groups and groups[s:lower()]
    if group then
        return group
    end
    local ids = zones and zones.lookup(s)
    if ids and #ids > 0 then
        return ids
    end
    return nil, ('unknown zone "%s" (check the spelling, or use the zone id shown by //mn id)'):format(s)
end

local function zone_label(zones, id)
    local name = zones and zones.name_of(id)
    return name or ('zone ' .. id)
end

-- Text like `name "Fafnir" in Dragon's Aery` for chat messages.
local function describe_rule(rule, raw_names, zones)
    local what = {}
    if rule.display_name then
        what[#what + 1] = ('name "%s"'):format(rule.display_name)
    end
    if raw_names and #raw_names > 0 then
        what[#what + 1] = ('names "%s"'):format(table.concat(raw_names, '", "'))
    end
    if rule.raw_prefixes then
        what[#what + 1] = ('names starting with "%s"'):format(table.concat(rule.raw_prefixes, '", "'))
    end
    local where
    if not rule.zones then
        where = 'any zone'
    else
        local ids = util.sorted_keys(rule.zones)
        if #ids == 1 then
            where = zone_label(zones, ids[1])
        else
            local labels = {}
            for i = 1, math.min(#ids, 3) do
                labels[i] = zone_label(zones, ids[i])
            end
            where = table.concat(labels, ', ') .. (#ids > 3 and (' and %d more zones'):format(#ids - 3) or '')
        end
    end
    return table.concat(what, ' or ') .. ' in ' .. where
end

-- Collects non-empty strings from a string-or-list value.
local function string_list(value, field, where, warn, keep_spaces)
    local out = {}
    local list = type(value) == 'table' and value or { value }
    for _, s in ipairs(list) do
        if type(s) == 'string' and util.trim(s) ~= '' then
            out[#out + 1] = keep_spaces and s or util.trim(s)
        else
            warn('%s: match.%s entries must be non-empty strings (%s ignored)', where, field, util.inline(s))
        end
    end
    return out
end

-- Builds the normalized match rule used by core/matcher.lua.
function library.build_rule(m, groups, zones, where, warn)
    if type(m) ~= 'table' then
        return nil, 'match must be a table like { zone = "Dragon\'s Aery", name = "Fafnir" }'
    end
    for _, field in ipairs(util.sorted_keys(m)) do
        if not MATCH_FIELDS[field] then
            warn('%s: match.%s is not a match field (use zone, zones, name, names or name_prefix)', where, tostring(field))
        end
    end

    -- Zones: `zone` and `zones` both accept one value or a list.
    local refs = {}
    for _, field in ipairs({ 'zone', 'zones' }) do
        local v = m[field]
        if type(v) == 'table' then
            for _, z in ipairs(v) do
                refs[#refs + 1] = z
            end
        elseif v ~= nil then
            refs[#refs + 1] = v
        end
    end
    if #refs == 0 then
        return nil, 'match needs a zone: a zone name, a zone id, a zone group, or "*" for any zone'
    end
    local rule = {}
    local ids, any = {}, false
    for _, ref in ipairs(refs) do
        local resolved, problem = library.resolve_zone(ref, groups, zones)
        if resolved == '*' then
            any = true
        elseif resolved then
            for _, id in ipairs(resolved) do
                if zones and not zones.name_of(id) then
                    warn('%s: zone id %d is not a known zone', where, id)
                end
                ids[id] = true
            end
        else
            warn('%s: %s', where, problem)
        end
    end
    if any then
        rule.zones, rule.zone_count = nil, math.huge
    else
        local n = util.count(ids)
        if n == 0 then
            return nil, 'none of its zones could be found'
        end
        rule.zones, rule.zone_count = ids, n
    end

    -- Names. `name = { ... }` is accepted and treated like `names`.
    local raw_names = {}
    if type(m.name) == 'table' then
        for _, s in ipairs(string_list(m.name, 'name', where, warn)) do
            raw_names[#raw_names + 1] = s
        end
    elseif m.name ~= nil then
        local s = string_list(m.name, 'name', where, warn)[1]
        if s then
            rule.name, rule.display_name = s:lower(), s
        end
    end
    if m.names ~= nil then
        for _, s in ipairs(string_list(m.names, 'names', where, warn)) do
            raw_names[#raw_names + 1] = s
        end
    end
    if #raw_names > 0 then
        rule.names = {}
        for _, s in ipairs(raw_names) do
            rule.names[s:lower()] = true
        end
    end

    -- Prefixes keep their spaces: "Demisang " must not match "Demisangs".
    if m.name_prefix ~= nil then
        local prefixes = string_list(m.name_prefix, 'name_prefix', where, warn, true)
        if #prefixes > 0 then
            table.sort(prefixes, function(a, b)
                if #a ~= #b then
                    return #a > #b
                end
                return a < b
            end)
            rule.prefixes, rule.raw_prefixes = {}, prefixes
            for i, p in ipairs(prefixes) do
                rule.prefixes[i] = p:lower()
            end
        end
    end

    if not rule.name and not rule.names and not rule.prefixes then
        return nil, 'match needs name, names or name_prefix'
    end
    rule.desc = describe_rule(rule, raw_names, zones)
    return rule
end

-- Validates the main file's defaults. Returns raw (as written) and normalized tables.
function library.build_defaults(raw, file_name, warn)
    local raw_out = util.copy(settings.builtin)
    local out = settings.normalized_builtin()
    if raw ~= nil and type(raw) ~= 'table' then
        warn('%s: defaults must be a table; using the built-in defaults', file_name)
        raw = nil
    end
    for _, field in ipairs(util.sorted_keys(raw or {})) do
        local value = raw[field]
        if settings.fields[field] then
            local ok, v = settings.check(field, value)
            if ok then
                out[field], raw_out[field] = v, value
            else
                warn('%s: defaults.%s %s; using %s', file_name, field, v, util.inline(settings.builtin[field]))
            end
        else
            warn('%s: defaults.%s is not a known setting (ignored)', file_name, tostring(field))
        end
    end
    return raw_out, out
end

-- Builds one note. Returns the note, or nil plus the reason it was skipped.
function library.build_note(key, raw, lib, file, zones, warn)
    if type(raw) ~= 'table' then
        return nil, 'a note must be a table like { match = { ... }, text = [[ ... ]] }'
    end
    local where = ("%s: note '%s'"):format(file.name, key)
    local note = { key = key, source = file.path, source_name = file.name }
    for field, value in pairs(lib.defaults) do
        note[field] = value
    end

    for _, field in ipairs(util.sorted_keys(raw)) do
        local value = raw[field]
        if settings.fields[field] then
            local ok, v = settings.check(field, value)
            if ok then
                note[field] = v
                if field == 'position' then
                    note.own_position = true
                end
            else
                warn('%s: %s %s; using the default', where, field, v)
            end
        elseif not NOTE_ONLY[field] then
            warn('%s: %s is not a known setting (ignored)', where, tostring(field))
        end
    end

    if raw.match == nil then
        if note.mode ~= 'manual' then
            return nil, 'it has no match = { ... } (only mode = "manual" notes can leave it out)'
        end
    else
        local rule, problem = library.build_rule(raw.match, lib.zone_groups, zones, where, warn)
        if not rule then
            return nil, problem
        end
        note.rule = rule
    end

    local text = raw.text
    if type(text) == 'number' then
        text = tostring(text)
    elseif text ~= nil and type(text) ~= 'string' then
        warn('%s: text must be a string', where)
        text = nil
    end
    note.text = util.normalize_text(text or '')

    local title = raw.title
    if type(title) == 'number' then
        title = tostring(title)
    elseif title ~= nil and type(title) ~= 'string' then
        warn('%s: title must be a string', where)
        title = nil
    end
    title = title and util.trim(title:gsub('[\r\n]+', ' '))
    if title == nil then
        title = note.rule and note.rule.display_name or key
    end
    note.title = title
    return note
end

-- Adds a file's zone_groups. Earlier files win; group members are plain zones
-- (zone names, ids or "*"), not other groups.
local function add_zone_groups(lib, groups, file, zones, warn)
    if groups == nil then
        return
    end
    if type(groups) ~= 'table' then
        warn('%s: zone_groups must be a table', file.name)
        return
    end
    for _, name in ipairs(util.sorted_keys(groups)) do
        local members = groups[name]
        local where = ("%s: zone group '%s'"):format(file.name, tostring(name))
        if type(name) ~= 'string' then
            warn('%s: zone group names must be strings', file.name)
        elseif lib.zone_groups[name:lower()] then
            if file ~= lib.files[1] then
                warn('%s is already defined in an earlier file (ignored)', where)
            else
                warn('%s is defined twice', where)
            end
        else
            local list = type(members) == 'table' and members or { members }
            local ids, seen = {}, {}
            for _, member in ipairs(list) do
                local resolved, problem = library.resolve_zone(member, nil, zones)
                if type(resolved) == 'table' then
                    for _, id in ipairs(resolved) do
                        if not seen[id] then
                            seen[id] = true
                            ids[#ids + 1] = id
                        end
                    end
                elseif resolved == '*' then
                    warn('%s: "*" cannot be used inside a zone group', where)
                else
                    warn('%s: %s', where, problem)
                end
            end
            if #ids > 0 then
                table.sort(ids)
                lib.zone_groups[name:lower()] = ids
            else
                warn('%s has no valid zones (ignored)', where)
            end
        end
    end
end

--[[
    Loads every library file. `files` is a list of { path = , name = }; the
    first entry is the main file. `opts.zones` resolves zone names:
        zones.lookup(name) -> list of zone ids (case-insensitive) or nil
        zones.name_of(id)  -> zone name or nil
    Returns lib, report. lib is nil when the main file cannot be used.
    report = { errors = { ... }, warnings = { ... }, count = n, files = n }
]]
function library.load(files, opts)
    opts = opts or {}
    local zones = opts.zones
    local report = { errors = {}, warnings = {}, count = 0, files = 0 }
    local function warn(fmt, ...)
        report.warnings[#report.warnings + 1] = fmt:format(...)
    end
    local function fail(fmt, ...)
        report.errors[#report.errors + 1] = fmt:format(...)
    end

    local main = files[1]
    local main_data, main_err = library.read(main.path, main.name)
    if not main_data then
        fail('%s', main_err)
        report.fatal = true
        return nil, report
    end

    local lib = {
        notes = {}, list = {}, raw_keys = {}, zone_groups = {}, files = {},
        main_path = main.path,
    }
    local loaded = { { file = main, data = main_data } }
    lib.files[1] = main
    for i = 2, #files do
        local data, err = library.read(files[i].path, files[i].name)
        if data then
            loaded[#loaded + 1] = { file = files[i], data = data }
            lib.files[#lib.files + 1] = files[i]
        else
            fail('%s (file skipped)', err)
        end
    end

    lib.raw_defaults, lib.defaults = library.build_defaults(main_data.defaults, main.name, warn)

    for _, set in ipairs(loaded) do
        for _, field in ipairs(util.sorted_keys(set.data)) do
            if not TOP_LEVEL[field] then
                warn('%s: unknown section %s (expected defaults, zone_groups or notes)', set.file.name, tostring(field))
            end
        end
        if set.file ~= main and set.data.defaults ~= nil then
            warn('%s: defaults in extra libraries are ignored; data/notes.lua sets the defaults', set.file.name)
        end
        add_zone_groups(lib, set.data.zone_groups, set.file, zones, warn)
    end

    for _, set in ipairs(loaded) do
        local name = set.file.name
        local notes = set.data.notes
        if notes == nil then
            warn('%s: has no notes = { ... } section', name)
        elseif type(notes) ~= 'table' then
            fail('%s: notes must be a table', name)
        else
            for _, key in ipairs(util.sorted_keys(notes)) do
                if type(key) ~= 'string' then
                    fail('%s: note #%s has no key; write it as  my_note_name = { ... }', name, tostring(key))
                elseif lib.raw_keys[key] then
                    warn("%s: note '%s' already exists in an earlier file (this copy is ignored)", name, key)
                else
                    lib.raw_keys[key] = true
                    local note, problem = library.build_note(key, notes[key], lib, set.file, zones, warn)
                    if note then
                        lib.notes[key] = note
                        lib.list[#lib.list + 1] = note
                    else
                        fail("%s: note '%s' was skipped: %s", name, key, problem)
                    end
                end
            end
        end
    end

    lib.matcher = matcher.new(lib.list)
    for _, w in ipairs(matcher.conflicts(lib.list)) do
        warn('%s', w)
    end
    report.count = #lib.list
    report.files = #loaded
    return lib, report
end

return library
