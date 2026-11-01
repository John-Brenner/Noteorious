--[[
    Noteorious - core/generator.lua

    Writes new note entries into data/notes.lua for //mn new, without
    rewriting anything you wrote by hand:

      1. The file is read and must already load cleanly. A file with errors
         is never modified.
      2. The entry is inserted just above the end marker line
             -- [noteorious:generated:end]
         which lives inside  notes = { ... }. Every other byte of the file is
         kept as is (comments, formatting, line endings). If the marker text
         appears more than once, each marker line is tried, last first.
      3. The edited text is loaded in memory first. The write only happens if
         the new note is present and every existing note is still there.
      4. A copy of the old file is saved to data/backups/ before writing.

    If the marker is missing, nothing is written and the caller offers the
    entry on the clipboard instead.
]]

local util = require('core/util')

local generator = {}

generator.BEGIN_MARKER = '-- [noteorious:generated:begin]'
generator.END_MARKER = '-- [noteorious:generated:end]'
generator.BACKUPS_KEPT = 20

-- Written when data/notes.lua does not exist.
generator.STARTER = [==[
--[[
    Noteorious note library.

    Target a monster and type  //mn new  to add a note for it here, edit the
    text, save, then  //mn reload . See README.md for every setting.
]]

return {
    defaults = {
        font = "Consolas",
        font_size = 12,
        color = "yellow",        -- title color
        text_color = "white",    -- body text color
        background = "dark",
        opacity = 220,
        position = { x = 800, y = 250 },
        icon = "note",
        mode = "target",         -- target | combat | pinned | manual
        close_on_zone = true,
        close_on_death = true,
        close_on_logout = true,
    },

    zone_groups = {
    },

    notes = {
        -- [noteorious:generated:begin] Notes made by //mn new are added below. Keep both marker lines.

        -- [noteorious:generated:end]
    },
}
]==]

local function one_line(s)
    return (tostring(s):gsub('[\r\n]+', ' '))
end

--[[
    Lines of a new entry, indented relative to the marker. Text inside the
    long string is indented too; the loader removes shared indentation.
    args: key, zone, zone_name (optional), name, defaults (raw defaults)
]]
function generator.entry(args)
    local d = args.defaults or {}
    local lines = {
        util.key_literal(args.key) .. ' = {',
        '    match = {',
        ('        zone = %d,%s'):format(args.zone, args.zone_name and (' -- ' .. one_line(args.zone_name)) or ''),
        ('        name = %s,'):format(util.quote(args.name)),
        '    },',
        ('    title = %s,'):format(util.quote(args.name)),
        '    -- Optional overrides; remove the "--" to use one. Defaults are at the top of this file.',
        ('    -- mode = %s, -- target | combat | pinned | manual'):format(util.inline(d.mode or 'target')),
        ('    -- color = %s,'):format(util.inline(d.color or 'yellow')),
        ('    -- icon = %s, -- warning | skull | info | note | reminder | star | false'):format(util.inline(d.icon or 'note')),
        '    text = [[',
        '        Add strategy, warnings and reminders here.',
        '    ]],',
        '},',
    }
    return lines
end

-- Every line whose first non-blank text is the end marker, as
-- { start = position of the line, indent = leading whitespace }, in file order.
-- Also returns whether the marker appears elsewhere (sharing a line with code).
function generator.marker_lines(text)
    local found, inline = {}, false
    local from = 1
    while true do
        local at = text:find(generator.END_MARKER, from, true)
        if not at then
            break
        end
        local line_start = at
        while line_start > 1 do
            local c = text:sub(line_start - 1, line_start - 1)
            if c == '\n' or c == '\r' then
                break
            end
            line_start = line_start - 1
        end
        local indent = text:sub(line_start, at - 1)
        if indent:find('%S') then
            inline = true
        else
            found[#found + 1] = { start = line_start, indent = indent }
        end
        from = at + 1
    end
    return found, inline
end

-- Inserts entry lines above one marker line (default: the last one).
-- Returns new text, or nil + reason ('missing_marker' | 'marker_not_on_own_line').
function generator.insert(text, entry_lines, marker)
    if not marker then
        local found, inline = generator.marker_lines(text)
        if #found == 0 then
            return nil, inline and 'marker_not_on_own_line' or 'missing_marker'
        end
        marker = found[#found]
    end
    local eol = text:find('\r\n', 1, true) and '\r\n' or '\n'
    local block = {}
    for i, line in ipairs(entry_lines) do
        block[i] = line == '' and '' or marker.indent .. line
    end
    local insertion = table.concat(block, eol) .. eol .. eol
    return text:sub(1, marker.start - 1) .. insertion .. text:sub(marker.start)
end

-- Line number of a note's key in a library file (or nil). Looks inside the
-- notes section, preferring lines at the indentation of the note keys.
function generator.find_line(text, key)
    local lines = util.lines(text)
    local start = 1
    for i, line in ipairs(lines) do
        if line:match('^%s*notes%s*=%s*{') then
            start = i + 1
            break
        end
    end
    local entry_indent
    for i = start, #lines do
        local line = lines[i]
        if line:find('%S') and not line:match('^%s*%-%-') then
            entry_indent = line:match('^(%s*)')
            break
        end
    end
    local q1, q2 = '["' .. key .. '"]', "['" .. key .. "']"
    local plain = util.is_identifier(key) and key or nil
    local function is_key_line(line)
        if plain and line:match('^%s*' .. plain .. '%s*=') and not line:match('^%s*' .. plain .. '%s*==') then
            return true
        end
        return line:find(q1, 1, true) ~= nil or line:find(q2, 1, true) ~= nil
    end
    local fallback
    for i = start, #lines do
        local line = lines[i]
        if is_key_line(line) then
            if entry_indent == nil or line:match('^(%s*)') == entry_indent then
                return i
            end
            fallback = fallback or i
        end
    end
    return fallback
end

-- Saves a copy of `text` into the backup folder; keeps the newest BACKUPS_KEPT.
function generator.backup(text, opts)
    local fs, dir = opts.fs, opts.backup_dir
    if not fs.dir_exists(dir) then
        fs.mkdir(dir)
        if not fs.dir_exists(dir) then
            return nil, 'could not create ' .. dir
        end
    end
    local stamp = opts.now()
    local name = ('notes-%s.lua'):format(stamp)
    local n = 1
    while fs.file_exists(dir .. name) do
        n = n + 1
        name = ('notes-%s-%d.lua'):format(stamp, n)
    end
    local ok, err = fs.write(dir .. name, text)
    if not ok then
        return nil, err
    end
    if fs.list and fs.remove then
        local old = {}
        for _, file in ipairs(fs.list(dir) or {}) do
            if file:match('^notes%-%d+%-%d+.*%.lua$') then
                old[#old + 1] = file
            end
        end
        table.sort(old)
        for i = 1, #old - generator.BACKUPS_KEPT do
            fs.remove(dir .. old[i])
        end
    end
    return dir .. name
end

--[[
    Adds a note entry to the library file at `path`.
    opts: fs = { read, write, file_exists, dir_exists, mkdir, list?, remove? },
          evaluate(text, chunkname) -> table | nil, err   (core/library.evaluate)
          display_name, backup_dir, now() -> timestamp string
    Returns { line = , backup = } or nil, { reason = , message = }.
    reasons: read, invalid, duplicate, missing_marker, marker_not_on_own_line,
             verify, backup, write
]]
function generator.add_note(path, key, entry_lines, opts)
    local fs = opts.fs
    local text, err = fs.read(path)
    if not text then
        return nil, { reason = 'read', message = tostring(err) }
    end
    local current, problem = opts.evaluate(text, opts.display_name)
    if not current then
        return nil, { reason = 'invalid', message = problem }
    end
    local notes = type(current.notes) == 'table' and current.notes or {}
    if notes[key] ~= nil then
        return nil, { reason = 'duplicate', message = key }
    end

    local markers, inline = generator.marker_lines(text)
    if #markers == 0 then
        return nil, { reason = inline and 'marker_not_on_own_line' or 'missing_marker' }
    end

    -- The marker text may also appear in a comment or a note; try each marker
    -- line, last first, and keep the first result that verifies.
    local new_text, problem
    for i = #markers, 1, -1 do
        local candidate = generator.insert(text, entry_lines, markers[i])
        local check, check_err = opts.evaluate(candidate, opts.display_name)
        if not check or type(check.notes) ~= 'table' or check.notes[key] == nil then
            problem = check_err or 'the generated-notes marker is not inside the notes = { ... } table'
        else
            problem = nil
            for existing in pairs(notes) do
                if check.notes[existing] == nil then
                    problem = ("note '%s' would have been lost"):format(tostring(existing))
                    break
                end
            end
        end
        if not problem then
            new_text = candidate
            break
        end
    end
    if not new_text then
        return nil, { reason = 'verify', message = problem }
    end

    local backup, berr = generator.backup(text, opts)
    if not backup then
        return nil, { reason = 'backup', message = tostring(berr) }
    end
    local ok, werr = fs.write(path, new_text)
    if not ok then
        return nil, { reason = 'write', message = tostring(werr) }
    end
    return { line = generator.find_line(new_text, key), backup = backup }
end

-- Entry lines joined into a pasteable block (for the clipboard fallback).
function generator.as_text(entry_lines, indent)
    indent = indent or '        '
    local out = {}
    for i, line in ipairs(entry_lines) do
        out[i] = indent .. line
    end
    return table.concat(out, '\n')
end

return generator
