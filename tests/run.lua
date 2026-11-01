--[[
    Noteorious offline test suite. No game or Windower needed.

    From the addon folder, with any Lua 5.1 or LuaJIT interpreter:
        luajit tests/run.lua
    or with the helper that runs LuaJIT 2.1, LuaJIT 2.0 and Lua 5.1 through
    the `lupa` Python package (pip install lupa):
        python tests/run_tests.py

    To also run the end-to-end tests against Windower's real texts library,
    point WINDOWER_LIBS at a folder containing texts.lua, for example a
    checkout of https://github.com/Windower/Lua (addons/libs/):
        WINDOWER_LIBS=/path/to/Lua/addons/libs/ luajit tests/run.lua
        python tests/run_tests.py --windower-libs /path/to/Lua/addons/libs
]]

local root = NOTEORIOUS_ROOT
if not root then
    local script = arg and arg[0] or ''
    root = script:match('^(.*[/\\])tests[/\\]run%.lua$') or './'
end
root = root:gsub('\\', '/')
NOTEORIOUS_ROOT = root
package.path = root .. '?.lua;' .. package.path

WINDOWER_LIBS = WINDOWER_LIBS or os.getenv('WINDOWER_LIBS')
if WINDOWER_LIBS and WINDOWER_LIBS ~= '' then
    WINDOWER_LIBS = WINDOWER_LIBS:gsub('\\', '/')
    if not WINDOWER_LIBS:match('/$') then
        WINDOWER_LIBS = WINDOWER_LIBS .. '/'
    end
else
    WINDOWER_LIBS = nil
end

local T = require('tests/harness')
local fakes = require('tests/fakes')
fakes.cleanup()

local suites = { 'test_util', 'test_matcher', 'test_library', 'test_state', 'test_generator', 'test_display', 'test_addon' }
for _, name in ipairs(suites) do
    T.suite = name
    local ok, err = xpcall(function() require('tests/' .. name) end, debug.traceback)
    if not ok then
        T.failed = T.failed + 1
        T.failures[#T.failures + 1] = name .. ' could not run:\n' .. tostring(err)
    end
end

local runtime = _VERSION .. (jit and (' / ' .. jit.version) or '')
local texts_mode = WINDOWER_LIBS and "Windower's texts.lua" or 'fake texts library'
print(('[%s, %s] %d passed, %d failed'):format(runtime, texts_mode, T.passed, T.failed))
for _, failure in ipairs(T.failures) do
    print('FAIL ' .. failure)
end
fakes.cleanup()

if NOTEORIOUS_EMBEDDED then
    return T.failed
end
os.exit(T.failed == 0 and 0 or 1)
