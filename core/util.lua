--[[
    Noteorious - core/util.lua

    Small, dependency-free helpers shared by the other modules. Nothing in
    this file touches the windower API, so it can be unit tested outside the
    game with any Lua 5.1 / LuaJIT interpreter.
]]

local util = {}

-- Lua keywords cannot be used as bare table keys in generated code.
local KEYWORDS = {}
for word in ([[and break do else elseif end false for function goto if in
    local nil not or repeat return then true until while]]):gmatch('%a+') do
    KEYWORDS[word] = true
end

function util.trim(s)
    return (tostring(s):match('^%s*(.-)%s*$'))
end

-- Splits a string into lines. Accepts \n, \r\n and lone \r line endings.
function util.lines(s)
    local text = tostring(s):gsub('\r\n?', '\n')
    local out = {}
    for line in (text .. '\n'):gmatch('(.-)\n') do
        out[#out + 1] = line
    end
    return out
end

-- Deep copy of plain data (functions and other values are copied by reference).
function util.copy(value)
    if type(value) ~= 'table' then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[util.copy(k)] = util.copy(v)
    end
    return out
end

-- Whether two plain data values are equal, comparing tables by content.
-- Very deep (or self-referencing) tables count as different.
function util.deep_equal(a, b, depth)
    if a == b then
        return true
    end
    if type(a) ~= 'table' or type(b) ~= 'table' then
        return false
    end
    depth = (depth or 0) + 1
    if depth > 50 then
        return false
    end
    for k, v in pairs(a) do
        if not util.deep_equal(v, b[k], depth) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

-- Keys of a table in a stable order: numbers first, then strings, each sorted.
function util.sorted_keys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then
            return ta < tb
        end
        if ta == 'number' or ta == 'string' then
            return a < b
        end
        return tostring(a) < tostring(b)
    end)
    return keys
end

function util.count(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

-- ASCII-only on purpose: %a/%w follow the C locale in PUC Lua.
function util.is_identifier(s)
    return type(s) == 'string' and s:match('^[A-Za-z_][A-Za-z0-9_]*$') ~= nil and not KEYWORDS[s]
end

-- A double-quoted Lua string literal that always stays on one line.
function util.quote(s)
    local q = string.format('%q', tostring(s))
    q = q:gsub('\\\n', '\\n')
    q = q:gsub('\r', '\\r')
    return q
end

-- `key` or `["key"]`, whichever is valid Lua inside a table constructor.
function util.key_literal(key)
    if util.is_identifier(key) then
        return key
    end
    return '[' .. util.quote(key) .. ']'
end

-- A long-bracket literal ([[...]], [=[...]=], ...) that the text cannot close early.
function util.long_string(s)
    local level = 0
    while (s .. ']'):find(']' .. string.rep('=', level) .. ']', 1, true) do
        level = level + 1
    end
    local eq = string.rep('=', level)
    -- Lua drops the newline that directly follows the opening bracket.
    return '[' .. eq .. '[\n' .. s .. ']' .. eq .. ']'
end

-- Compact one-line rendering of plain data, used in messages and generated hints.
function util.inline(value)
    local t = type(value)
    if t == 'string' then
        return util.quote(value)
    elseif t == 'table' then
        local parts = {}
        local keys = util.sorted_keys(value)
        local array = #value == #keys
        for _, k in ipairs(keys) do
            local v = util.inline(value[k])
            if array then
                parts[#parts + 1] = v
            else
                local key = type(k) == 'string' and util.key_literal(k) or '[' .. tostring(k) .. ']'
                parts[#parts + 1] = key .. ' = ' .. v
            end
        end
        return #parts == 0 and '{}' or '{ ' .. table.concat(parts, ', ') .. ' }'
    end
    return tostring(value)
end

-- Multi-line, deterministic Lua source for plain data (strings, numbers, booleans, tables).
function util.serialize(value, indent)
    indent = indent or ''
    local t = type(value)
    if t == 'string' then
        return util.quote(value)
    elseif t == 'number' then
        if value == math.floor(value) and math.abs(value) < 2^53 then
            return string.format('%d', value)
        end
        return string.format('%.17g', value)
    elseif t == 'boolean' then
        return tostring(value)
    elseif t == 'table' then
        local keys = util.sorted_keys(value)
        if #keys == 0 then
            return '{}'
        end
        local inner = indent .. '    '
        local array = #value == #keys
        local parts = {}
        for _, k in ipairs(keys) do
            local prefix = ''
            if not array then
                prefix = (type(k) == 'string' and util.key_literal(k) or '[' .. util.serialize(k) .. ']') .. ' = '
            end
            parts[#parts + 1] = inner .. prefix .. util.serialize(value[k], inner) .. ','
        end
        return '{\n' .. table.concat(parts, '\n') .. '\n' .. indent .. '}'
    end
    error('cannot serialize a ' .. t)
end

--[[
    Text helpers for note bodies.
    Note text may contain Windower inline color codes: \cs(r,g,b)...\cr.
    They take no space on screen, so widths are measured without them.
]]

function util.visible_len(s)
    local plain = s:gsub('\\cs%b()', '')
    plain = plain:gsub('\\cr', '')
    return #plain
end

-- Removes the indentation shared by every non-blank line (spaces only).
function util.dedent(lines)
    local min
    for _, line in ipairs(lines) do
        if line:find('%S') then
            local n = #line:match('^ *')
            if not min or n < min then
                min = n
            end
        end
    end
    if min and min > 0 then
        for i, line in ipairs(lines) do
            lines[i] = line:sub(min + 1)
        end
    end
    return lines
end

-- Cleans note text: unified newlines, tabs as 4 spaces, no trailing spaces,
-- no leading/trailing blank lines, and common indentation removed (so text
-- can be indented to match the surrounding Lua code).
function util.normalize_text(s)
    local lines = util.lines((tostring(s):gsub('\t', '    ')))
    for i, line in ipairs(lines) do
        lines[i] = (line:gsub('%s+$', ''))
    end
    while #lines > 0 and lines[1] == '' do
        table.remove(lines, 1)
    end
    while #lines > 0 and lines[#lines] == '' do
        lines[#lines] = nil
    end
    return table.concat(util.dedent(lines), '\n')
end

-- Word-wraps one line that is longer than `width`. Continuation lines are
-- indented under the text of a bullet ("- ", "* ", "1. ") for readability.
local function wrap_line(line, width, out)
    local lead = line:match('^%s*[-*+]%s+') or line:match('^%s*%d+[.)]%s+') or line:match('^%s*')
    local rest = line:sub(#lead + 1)
    local hang = string.rep(' ', #lead)
    if #lead >= width - 4 then
        -- Absurdly deep indentation: drop it rather than wrap one character per line.
        lead = lead:match('%S.*$') or ''
        hang = ''
    end

    local cur, cur_len, fresh = lead, #lead, true
    local function flush()
        out[#out + 1] = cur
        cur, cur_len, fresh = hang, #hang, true
    end

    for word in rest:gmatch('%S+') do
        local wlen = util.visible_len(word)
        if not fresh and cur_len + 1 + wlen > width then
            flush()
        end
        if fresh then
            -- A plain word that does not fit even on an empty line is split.
            -- (Words containing color codes are never split, so codes stay intact.)
            while cur_len + wlen > width and wlen == #word do
                local room = width - cur_len
                cur = cur .. word:sub(1, room)
                word = word:sub(room + 1)
                wlen = #word
                flush()
            end
            cur = cur .. word
            cur_len = cur_len + wlen
        else
            cur = cur .. ' ' .. word
            cur_len = cur_len + 1 + wlen
        end
        fresh = false
    end
    if not fresh then
        out[#out + 1] = cur
    end
end

-- Returns the text as a list of display lines no wider than `width`
-- characters (0 disables wrapping). Existing line breaks are kept.
function util.wrap(text, width)
    local out = {}
    for _, line in ipairs(util.lines(text)) do
        if width <= 0 or util.visible_len(line) <= width then
            out[#out + 1] = line
        else
            wrap_line(line, width, out)
        end
    end
    return out
end

--[[
    Files and bytes.
]]

function util.read_file(path)
    local f, err = io.open(path, 'rb')
    if not f then
        return nil, err
    end
    local data = f:read('*a')
    f:close()
    return data
end

function util.write_file(path, data)
    local f, err = io.open(path, 'wb')
    if not f then
        return nil, err
    end
    local ok, werr = f:write(data)
    f:close()
    if not ok then
        return nil, werr
    end
    return true
end

-- Little-endian unsigned integers from a binary string (1-based position).
function util.u16le(s, pos)
    local a, b = s:byte(pos, pos + 1)
    if not b then
        return nil
    end
    return a + b * 256
end

function util.u32le(s, pos)
    local a, b, c, d = s:byte(pos, pos + 3)
    if not d then
        return nil
    end
    return a + b * 256 + c * 65536 + d * 16777216
end

return util
