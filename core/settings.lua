--[[
    Noteorious - core/settings.lua

    The list of display/behaviour settings a note can have, their built-in
    defaults, and validation. Every setting can appear in `defaults = { }`
    at the top of a note library and be overridden inside any single note.

    settings.check(field, value) returns  true, normalized_value
                                      or  false, "human readable problem"
    Invalid values never stop a library from loading: the loader warns and
    falls back to the inherited value.
]]

local util = require('core/util')

local settings = {}

-- Built-in defaults, written exactly as a user would write them in notes.lua.
settings.builtin = {
    font = 'Consolas',
    font_size = 12,
    bold = false,
    italic = false,
    color = 'yellow',        -- title (accent) color
    text_color = 'white',    -- body text color
    background = 'dark',
    opacity = 220,           -- background opacity, 0-255
    outline = 0,             -- text outline width in pixels, 0-6
    outline_color = 'black',
    padding = 6,             -- pixels between the text and the edge of the background
    width = 50,              -- wrap lines at this many characters (0 = never wrap)
    max_lines = 30,          -- lines per page; longer notes get pages (0 = unlimited)
    position = { x = 800, y = 250 },
    icon = 'note',
    icon_style = 'image',    -- image | text | none
    icon_size = 24,
    mode = 'target',         -- target | combat | pinned | manual
    close_on_zone = true,
    close_on_death = true,
    close_on_logout = true,
}

-- Named colors. Text colors are bright; the last group suits backgrounds.
settings.colors = {
    white = { 255, 255, 255 }, black = { 0, 0, 0 },
    gray = { 150, 150, 155 }, grey = { 150, 150, 155 }, silver = { 205, 205, 215 },
    red = { 255, 90, 90 }, crimson = { 220, 40, 60 }, orange = { 255, 165, 60 },
    gold = { 255, 205, 60 }, yellow = { 255, 235, 100 }, lime = { 180, 255, 90 },
    green = { 110, 225, 110 }, teal = { 60, 205, 180 }, cyan = { 110, 230, 255 },
    blue = { 120, 165, 255 }, purple = { 190, 140, 255 }, magenta = { 255, 110, 220 },
    pink = { 255, 165, 205 }, brown = { 180, 120, 75 },
    -- backgrounds
    dark = { 18, 18, 26 }, charcoal = { 42, 42, 50 }, slate = { 40, 48, 66 },
    navy = { 14, 22, 58 }, maroon = { 64, 12, 18 }, forest = { 14, 46, 26 },
    plum = { 48, 18, 52 }, parchment = { 236, 224, 182 }, sticky = { 255, 236, 130 },
}

-- Built-in icons: the image file is icons/<name>.png; the text is the fallback.
settings.icons = {
    warning = '/!\\',
    skull = '(x_x)',
    info = '(i)',
    note = '[=]',
    reminder = '(!)',
    star = '(*)',
}

settings.icon_aliases = {
    information = 'info', alert = 'warning', danger = 'warning',
    death = 'skull', bell = 'reminder', clock = 'reminder', sticky = 'note',
}

settings.modes = { target = true, combat = true, pinned = true, manual = true }

-- How each field is validated.
settings.fields = {
    font = { kind = 'string' },
    font_size = { kind = 'number', min = 6, max = 72 },
    bold = { kind = 'boolean' },
    italic = { kind = 'boolean' },
    color = { kind = 'color' },
    text_color = { kind = 'color' },
    background = { kind = 'color' },
    opacity = { kind = 'number', min = 0, max = 255 },
    outline = { kind = 'number', min = 0, max = 6 },
    outline_color = { kind = 'color' },
    padding = { kind = 'number', min = 0, max = 60 },
    width = { kind = 'number', min = 10, max = 300, zero_ok = true },
    max_lines = { kind = 'number', min = 1, max = 500, zero_ok = true },
    position = { kind = 'position' },
    icon = { kind = 'icon' },
    icon_style = { kind = 'enum', values = { image = true, text = true, none = true } },
    icon_size = { kind = 'number', min = 8, max = 128 },
    mode = { kind = 'enum', values = settings.modes },
    close_on_zone = { kind = 'boolean' },
    close_on_death = { kind = 'boolean' },
    close_on_logout = { kind = 'boolean' },
}

local function byte(v)
    return type(v) == 'number' and v >= 0 and v <= 255
end

-- Accepts a color name, "#RRGGBB", { r, g, b } or { red = , green = , blue = }.
function settings.parse_color(v)
    if type(v) == 'string' then
        local s = util.trim(v):lower()
        local named = settings.colors[s]
        if named then
            return { named[1], named[2], named[3] }
        end
        local hex = s:match('^#(%x%x%x%x%x%x)$')
        if hex then
            return { tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16) }
        end
        return nil, 'is not a color name or "#RRGGBB"'
    elseif type(v) == 'table' then
        local r, g, b = v[1] or v.r or v.red, v[2] or v.g or v.green, v[3] or v.b or v.blue
        if byte(r) and byte(g) and byte(b) then
            return { math.floor(r), math.floor(g), math.floor(b) }
        end
        return nil, 'must be { r, g, b } with each value from 0 to 255'
    end
    return nil, 'must be a color name, "#RRGGBB" or { r, g, b }'
end

local checkers = {}

function checkers.string(_, v)
    if type(v) == 'string' and util.trim(v) ~= '' then
        return true, util.trim(v)
    end
    return false, 'must be a non-empty string'
end

function checkers.boolean(_, v)
    if type(v) == 'boolean' then
        return true, v
    end
    return false, 'must be true or false'
end

function checkers.number(spec, v)
    if type(v) == 'string' then
        v = tonumber(v)
    end
    if type(v) ~= 'number' or v ~= v then
        return false, 'must be a number'
    end
    v = math.floor(v + 0.5)
    if spec.zero_ok and v == 0 then
        return true, 0
    end
    if v < spec.min or v > spec.max then
        return false, ('must be from %d to %d%s'):format(spec.min, spec.max, spec.zero_ok and ' (or 0)' or '')
    end
    return true, v
end

function checkers.color(_, v)
    local c, problem = settings.parse_color(v)
    if c then
        return true, c
    end
    return false, problem
end

function checkers.enum(spec, v)
    local s = type(v) == 'string' and util.trim(v):lower() or nil
    if s and spec.values[s] then
        return true, s
    end
    local names = util.sorted_keys(spec.values)
    return false, 'must be one of: ' .. table.concat(names, ', ')
end

function checkers.position(_, v)
    if type(v) == 'table' then
        local x, y = v.x or v[1], v.y or v[2]
        if type(x) == 'number' and type(y) == 'number' and math.abs(x) < 20000 and math.abs(y) < 20000 then
            return true, { x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
        end
    end
    return false, 'must look like { x = 800, y = 250 }'
end

-- false/"none" disables the icon; built-in names (and aliases) are lowercased;
-- anything else must be a plain file name inside the icons folder. Paths are
-- refused so a shared library cannot point at network shares (\\host\...).
function checkers.icon(_, v)
    if v == false then
        return true, false
    end
    if type(v) == 'string' then
        local s = util.trim(v)
        local lower = s:lower()
        if lower == '' or lower == 'none' then
            return true, false
        end
        lower = settings.icon_aliases[lower] or lower
        if settings.icons[lower] then
            return true, lower
        end
        if s:find('[/\\:]') or s:find('..', 1, true) then
            return false, 'must be an icon name or a file name inside the icons folder, not a path'
        end
        return true, s
    end
    return false, 'must be an icon name, an image file name in the icons folder, or false'
end

-- Validates one setting. Returns true, value or false, message.
function settings.check(field, value)
    local spec = settings.fields[field]
    if not spec then
        return false, 'is not a known setting'
    end
    local ok, result = checkers[spec.kind](spec, value)
    if ok then
        return true, result
    end
    return false, ('%s %s'):format(util.inline(value), result)
end

-- The built-in defaults in normalized form.
function settings.normalized_builtin()
    local out = {}
    for field, value in pairs(settings.builtin) do
        local ok, v = settings.check(field, value)
        assert(ok, 'invalid built-in default for ' .. field)
        out[field] = v
    end
    return out
end

return settings
