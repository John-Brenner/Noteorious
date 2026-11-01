local T = require('tests/harness')
local fakes = require('tests/fakes')
local settings = require('core/settings')
local display = require('core/display')

local function make_note(overrides)
    local note = settings.normalized_builtin()
    note.key, note.title, note.text = 'crab', 'Crab', 'Pinch warning'
    for k, v in pairs(overrides or {}) do
        note[k] = v
    end
    return note
end

local function make_view(opts)
    opts = opts or {}
    local texts, images = fakes.texts_lib(), fakes.images_lib()
    local warnings, moves = {}, {}
    local view = display.new({
        texts = texts,
        images = images,
        file_exists = function(path) return opts.files == nil or opts.files[path] == true end,
        screen = function() return 1920, 1080 end,
        icon_dir = 'ICONS/',
        position = function(note) return note.position.x, note.position.y end,
        moved = function(note, x, y) moves[#moves + 1] = { note = note, x = x, y = y } end,
        warn = function(msg) warnings[#warnings + 1] = msg end,
    })
    return view, texts.created[1], images.created[1], warnings, moves
end

T.test('compose: colored header, glyph, pinned marker and body', function()
    local note = make_note({ color = { 1, 2, 3 } })
    T.eq(display.compose(note), '\\cs(1,2,3)Crab\\cr\nPinch warning')
    T.eq(display.compose(note, { glyph = '(i)', pinned = true }), '\\cs(1,2,3)(i) Crab [pinned]\\cr\nPinch warning')
    T.eq(display.compose(make_note({ text = '' })), '\\cs(255,235,100)Crab\\cr')
    T.eq(display.compose(make_note({ title = '' })), 'Pinch warning')
end)

T.test('compose: wraps and truncates long notes', function()
    local lines = {}
    for i = 1, 40 do
        lines[i] = 'line ' .. i
    end
    local note = make_note({ text = table.concat(lines, '\n'), max_lines = 5 })
    local out = display.compose(note)
    local shown = {}
    for line in (out .. '\n'):gmatch('(.-)\n') do
        shown[#shown + 1] = line
    end
    T.eq(#shown, 6, 'header + 5 body lines')
    T.eq(shown[5], 'line 4')
    T.eq(shown[6], '... (36 more lines in the note file)')
    local unlimited = display.compose(make_note({ text = table.concat(lines, '\n'), max_lines = 0 }))
    T.has(unlimited, 'line 40')
    local wrapped = display.compose(make_note({ text = string.rep('word ', 30), width = 20 }))
    for line in wrapped:gmatch('[^\n]+') do
        if not line:find('\\cs', 1, true) then
            T.ok(#line <= 20, line)
        end
    end
end)

T.test('compose: text that looks like a template variable is shown as is', function()
    local out = display.compose(make_note({ text = 'costs ${gil} and 50% off' }))
    T.has(out, 'costs ${gil} and 50% off')
end)

T.test('show applies the note style with font fallbacks', function()
    local view, text = make_view({ files = { ['ICONS/note.png'] = true } })
    local note = make_note({ font = 'Comic Sans MS', font_size = 14, opacity = 0, outline = 2, bold = true })
    view:show(note)
    T.ok(text.shown)
    T.eq(text.style.font[1], 'Comic Sans MS')
    T.eq(text.style.font[2], 'Consolas')
    T.eq(text.style.font[3], 'Arial')
    T.eq(text.style.size[1], 14)
    T.eq(text.style.bg_alpha[1], 0)
    T.eq(text.style.bg_visible[1], false, 'opacity 0 hides the background')
    T.eq(text.style.stroke_width[1], 2)
    T.eq(text.style.bold[1], true)
    T.eq(text.template, '${body}', 'the note is passed as a variable value')
    view:show(make_note({ font = 'consolas' }))
    T.eq(#text.style.font, 2, 'no duplicate Consolas')
end)

T.test('show draws the icon image left of the box', function()
    local view, text, icon = make_view({ files = { ['ICONS/skull.png'] = true } })
    view:show(make_note({ icon = 'skull', icon_size = 24, padding = 6, position = { x = 500, y = 300 } }))
    T.ok(icon.shown)
    T.eq(icon.file, 'ICONS/skull.png')
    T.eq(icon.w, 24)
    T.eq(icon.settings.texture.fit, false, 'scaled to icon_size, not the file size')
    T.eq(icon.settings.draggable, false, 'only the box is draggable')
    T.eq(icon.x, 500 - 6 - 4 - 24)
    T.eq(icon.y, 300 - 6)
    T.lacks(text:content(), '(x_x)', 'no text icon when the image exists')
end)

T.test('a missing icon image falls back to a text icon and warns once', function()
    local view, text, icon, warnings = make_view({ files = {} })
    view:show(make_note({ icon = 'warning' }))
    T.no(icon.shown)
    T.has(text:content(), '/!\\ Crab')
    view:show(make_note({ icon = 'warning' }))
    T.eq(#warnings, 1)
    T.has(warnings[1], 'ICONS/warning.png')
end)

T.test('custom icon files and icon styles', function()
    local view, text, icon = make_view({ files = { ['ICONS/boss.png'] = true, ['ICONS/x.bmp'] = true } })
    view:show(make_note({ icon = 'boss' }))
    T.eq(icon.file, 'ICONS/boss.png')
    view:show(make_note({ icon = 'x.bmp' }))
    T.eq(icon.file, 'ICONS/x.bmp')
    local checked = {}
    view.deps.file_exists = function(path) checked[#checked + 1] = path return true end
    view:show(make_note({ icon = '\\\\host\\share\\x.png' }))
    T.eq(#checked, 0, 'a path is never handed to the file system')
    T.no(icon.shown)
    view:show(make_note({ icon = 'skull', icon_style = 'text' }))
    T.no(icon.shown)
    T.has(text:content(), '(x_x) Crab')
    view:show(make_note({ icon = 'skull', icon_style = 'none' }))
    T.no(icon.shown)
    T.lacks(text:content(), '(x_x)')
    view:show(make_note({ icon = false }))
    T.eq(text:content():find('Crab', 1, true), #'\\cs(255,235,100)' + 1, 'no icon at all')
end)

T.test('notes are kept on screen', function()
    local view, text = make_view({ files = { ['ICONS/note.png'] = true } })
    view:show(make_note({ position = { x = -500, y = 5000 } }))
    T.eq(text.x, 6 + 24 + 4, 'room for padding and the icon')
    T.eq(text.y, 1080 - 30)
end)

T.test('dragging moves the icon and saves on release only', function()
    local view, text, icon, _, moves = make_view({ files = { ['ICONS/note.png'] = true } })
    local note = make_note()
    view:show(note)
    text:drag_to(100, 120)
    T.eq(icon.x, 100 - 6 - 4 - 24, 'icon follows the box')
    T.eq(#moves, 0, 'nothing saved mid-drag')
    view:mouse(0)
    T.eq(#moves, 0)
    view:mouse(2)
    T.eq(#moves, 1)
    T.eq(moves[1].note, note)
    T.eq(moves[1].x, 100)
    view:mouse(2)
    T.eq(#moves, 1, 'a plain click does not save')
end)

T.test('hide and destroy', function()
    local view, text, icon = make_view({ files = { ['ICONS/note.png'] = true } })
    view:show(make_note())
    view:hide()
    T.no(text.shown)
    T.no(icon.shown)
    view:destroy()
    T.ok(text.destroyed and icon.destroyed)
end)
