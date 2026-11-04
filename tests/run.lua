--[[
    Noteorious offline tests. Run them with  python tests/run_tests.py
    (needs  pip install lupa), which sets NOTEORIOUS_ROOT and TEST_DIR, an
    empty folder that has a data/ subfolder.
]]

package.path = NOTEORIOUS_ROOT .. '?.lua;' .. package.path

local T = require('tests/harness')
for _, name in ipairs({ 'test_addon' }) do
    T.suite = name
    local ok, err = xpcall(function() require('tests/' .. name) end, debug.traceback)
    if not ok then
        T.failed = T.failed + 1
        T.failures[#T.failures + 1] = name .. ' could not run:\n' .. tostring(err)
    end
end

print(('[%s] %d passed, %d failed'):format(_VERSION .. (jit and (' / ' .. jit.version) or ''), T.passed, T.failed))
for _, failure in ipairs(T.failures) do
    print('FAIL ' .. failure)
end
return T.failed
