--[[
    A tiny test harness: T.test(name, fn) plus a few assertions.
]]

local T = { passed = 0, failed = 0, failures = {}, suite = '' }

local function repr(v)
    if type(v) == 'string' then
        return string.format('%q', v)
    end
    if type(v) == 'table' then
        local ok, util = pcall(require, 'core/util')
        if ok then
            local ok2, s = pcall(util.inline, v)
            if ok2 then
                return s
            end
        end
    end
    return tostring(v)
end
T.repr = repr

local function prefix(label)
    return label and (label .. ': ') or ''
end

function T.test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        T.passed = T.passed + 1
    else
        T.failed = T.failed + 1
        T.failures[#T.failures + 1] = ('%s > %s\n%s'):format(T.suite, name, tostring(err))
    end
end

function T.eq(actual, expected, label)
    if actual ~= expected then
        error(('%sexpected %s, got %s'):format(prefix(label), repr(expected), repr(actual)), 2)
    end
end

function T.ok(value, label)
    if not value then
        error(('%sexpected a true value, got %s'):format(prefix(label), repr(value)), 2)
    end
end

function T.no(value, label)
    if value then
        error(('%sexpected a false value, got %s'):format(prefix(label), repr(value)), 2)
    end
end

function T.has(haystack, needle, label)
    if type(haystack) ~= 'string' or not haystack:find(needle, 1, true) then
        error(('%sexpected %s to contain %s'):format(prefix(label), repr(haystack), repr(needle)), 2)
    end
end

function T.lacks(haystack, needle, label)
    if type(haystack) == 'string' and haystack:find(needle, 1, true) then
        error(('%sexpected %s not to contain %s'):format(prefix(label), repr(haystack), repr(needle)), 2)
    end
end

-- Some string in `list` contains `needle`; returns it.
function T.any(list, needle, label)
    for _, s in ipairs(list) do
        if tostring(s):find(needle, 1, true) then
            return s
        end
    end
    error(('%sno entry contains %s in %s'):format(prefix(label), repr(needle), repr(list)), 2)
end

function T.none(list, needle, label)
    for _, s in ipairs(list) do
        if tostring(s):find(needle, 1, true) then
            error(('%sunexpected entry %s'):format(prefix(label), repr(s)), 2)
        end
    end
end

return T
