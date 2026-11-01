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
    return view, texts.created[1], images.created[1], warnings, moves, texts
end

-- One frame in Windower order: prerender (settle), then drawing.
local function frame(view, texts)
    view:settle()
    texts.render_all()
end

local function split(out)
    local lines = {}
    for line in (out .. '\n'):gmatch('(.-)\n') do
        lines[#lines + 1] = line
    end
    return lines
end

T.test('compose: colored header, glyph, pinned marker and body', function()
    local note = make_note({ color = { 1, 2, 3 } })
    T.eq(display.compose(note), '\\cs(1,2,3)Crab\\cr\nPinch warning')
    T.eq(display.compose(note, { glyph = '(i)', pinned = true }), '\\cs(1,2,3)(i) Crab [pinned]\\cr\nPinch warning')
    T.eq(display.compose(make_note({ text = '' })), '\\cs(255,235,100)Crab\\cr')
    T.eq(display.compose(make_note({ title = '' })), 'Pinch warning')
end)

T.test('compose: wraps long lines and splits long notes into pages', function()
    local lines = {}
    for i = 1, 40 do
        lines[i] = 'line ' .. i
    end
    local note = make_note({ text = table.concat(lines, '\n'), max_lines = 5 })
    local out, pages = display.compose(note)
    T.eq(pages, 10, 'four body lines per page')
    local shown = split(out)
    T.eq(#shown, 6, 'header + max_lines (4 body lines and the footer)')
    T.eq(shown[2], 'line 1')
    T.eq(shown[5], 'line 4')
    T.eq(shown[6], '\\cs(160,160,160)page 1/10 - //nt next, //nt prev\\cr')
    local last = split(display.compose(note, { page = 10 }))
    T.eq(last[2], 'line 37')
    T.eq(last[5], 'line 40')
    T.has(last[6], 'page 10/10')
    T.has(display.compose(note, { page = 99 }), 'page 10/10', 'out-of-range pages are clamped')
    local fits, one = display.compose(make_note({ text = 'a\nb', max_lines = 2 }))
    T.eq(one, 1)
    T.lacks(fits, 'page', 'no footer when the note fits')
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

T.test('notes stay fully on screen, measured at their drawn size with the icon', function()
    local view, text, icon, _, _, texts = make_view({ files = { ['ICONS/note.png'] = true } })
    view:show(make_note({ position = { x = 5000, y = 5000 } }))
    frame(view, texts)
    frame(view, texts)
    local w, h = text:extents()
    T.ok(w > 0 and h > 0, 'drawn')
    T.eq(text.x, 1920 - w - 6, 'right edge and padding on screen')
    T.eq(text.y, 1080 - h - 6, 'bottom edge and padding on screen')

    view:show(make_note({ key = 'other', position = { x = -500, y = -500 } }))
    T.eq(text.x, 6 + 24 + 4, 'room for the padding and the icon')
    T.eq(text.y, 6)
    T.eq(icon.x, 0, 'the icon touches the left edge')
    T.eq(icon.y, 0)
end)

T.test('a note larger than the screen keeps its title corner on screen', function()
    local view, text, _, _, _, texts = make_view({ files = { ['ICONS/note.png'] = true } })
    view:show(make_note({ text = string.rep('x', 400), width = 0, position = { x = 900, y = 500 } }))
    frame(view, texts)
    frame(view, texts)
    T.ok(text:extents() > 1920, 'wider than the screen')
    T.eq(text.x, 6 + 24 + 4, 'left side (title and icon) visible')
    T.eq(text.y, 500, 'the height fits, so y is kept')
end)

T.test('the size is re-measured for a few frames after a change, then left alone', function()
    local view, text, icon, _, _, texts = make_view({ files = { ['ICONS/note.png'] = true } })
    view:show(make_note({ position = { x = 100, y = 1075 } }))
    T.eq(text.y, 1080 - (24 - 6), 'before the first frame only the icon size is known')
    frame(view, texts)
    frame(view, texts)
    local _, h = text:extents()
    T.eq(text.y, 1080 - h - 6, 'moved up once the drawn size is known')
    T.eq(icon.y, text.y - 6, 'the icon followed')

    local calls, extents = 0, text.extents
    text.extents = function(self)
        calls = calls + 1
        return extents(self)
    end
    for _ = 1, 50 do
        view:settle()
    end
    T.ok(calls < display.SETTLE_FRAMES, 'stops measuring')
    local settled = calls
    for _ = 1, 10 do
        view:settle()
    end
    T.eq(calls, settled, 'no polling while nothing changes')
end)

T.test('dragging stays on screen, moves the icon and saves on release only', function()
    local view, text, icon, _, moves, texts = make_view({ files = { ['ICONS/note.png'] = true } })
    local note = make_note()
    view:show(note)
    frame(view, texts)
    frame(view, texts)
    text:drag_to(100, 120)
    T.eq(icon.x, 100 - 6 - 4 - 24, 'icon follows the box')
    T.eq(#moves, 0, 'nothing saved mid-drag')
    view:mouse(0)
    T.eq(#moves, 0)
    text:drag_to(-300, 5000)
    local _, h = text:extents()
    T.eq(text.x, 6 + 24 + 4, 'cannot be dragged off the left edge')
    T.eq(text.y, 1080 - h - 6, 'or off the bottom')
    view:mouse(2)
    T.eq(#moves, 1)
    T.eq(moves[1].note, note)
    T.eq(moves[1].x, 6 + 24 + 4, 'the on-screen spot is saved')
    T.eq(moves[1].y, 1080 - h - 6)
    view:mouse(2)
    T.eq(#moves, 1, 'a plain click does not save')
end)

T.test('turning pages wraps around and keeps the page while the note stays up', function()
    local lines = {}
    for i = 1, 12 do
        lines[i] = 'line ' .. i
    end
    local view, text = make_view()
    local long = make_note({ text = table.concat(lines, '\n'), max_lines = 5 })
    view:show(long)
    T.has(text:content(), 'page 1/3')
    T.eq(view:turn(1), 2)
    T.has(text:content(), 'line 5')
    T.has(text:content(), 'page 2/3')
    T.eq(view:turn(1), 3)
    T.eq(view:turn(1), 1, 'wraps to the first page')
    T.eq(view:turn(-1), 3, 'and backwards to the last')
    view:show(long, { pinned = true })
    T.eq(view.page, 3, 'pinning the same note keeps its page')
    T.has(text:content(), '[pinned]')
    view:show(make_note({ key = 'other', text = table.concat(lines, '\n'), max_lines = 5 }))
    T.eq(view.page, 1, 'another note starts at its first page')
    local page, pages = view:turn(1)
    T.eq(page, 2)
    T.eq(pages, 3)
    view:show(make_note())
    page, pages = view:turn(1)
    T.eq(page, 1)
    T.eq(pages, 1, 'a short note has one page')
    view:hide()
    T.eq(view:turn(1), nil, 'nothing to turn')
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
