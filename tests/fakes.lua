--[[
    Test doubles for the parts of Windower 4 that Noteorious uses, plus
    small filesystem helpers. Only used by the offline tests.

    fakes.boot(opts) loads the real Noteorious.lua inside a fake Windower:
      * windower.* functions backed by tables the test controls (mobs, zone,
        target, chat log, clipboard) and a real folder under tests/tmp/
      * the `texts` library: Windower's real texts.lua when WINDOWER_LIBS
        points at it (drawing calls go to a recording backend), otherwise a
        small fake with the same methods
      * `images` and `resources` fakes (resources reads tests/fixtures/zones.lua)
]]

local fakes = {}

local ROOT = NOTEORIOUS_ROOT
local TMP = ROOT .. 'tests/tmp/'
local WINDOWS = package.config:sub(1, 1) == '\\'

--[[ Filesystem ]]

local function native(path)
    return WINDOWS and path:gsub('/', '\\') or path
end

function fakes.file_exists(path)
    local f = io.open(path, 'rb')
    if f then
        f:close()
        return true
    end
    return false
end

function fakes.dir_exists(path)
    local p = path:gsub('[/\\]+$', '')
    return os.rename(p, p) == true
end

function fakes.mkdir(path)
    if not fakes.dir_exists(path) then
        if WINDOWS then
            os.execute('mkdir "' .. native(path) .. '" >nul 2>nul')
        else
            os.execute("mkdir -p '" .. path .. "'")
        end
    end
    return fakes.dir_exists(path)
end

function fakes.rmtree(path)
    if fakes.dir_exists(path) then
        if WINDOWS then
            os.execute('rmdir /s /q "' .. native(path) .. '" >nul 2>nul')
        else
            os.execute("rm -rf '" .. path .. "'")
        end
    end
end

function fakes.list(path)
    local listing = TMP .. '_listing.txt'
    fakes.mkdir(TMP)
    if WINDOWS then
        os.execute('dir /b "' .. native(path) .. '" > "' .. native(listing) .. '" 2>nul')
    else
        os.execute("ls -1 '" .. path .. "' > '" .. listing .. "' 2>/dev/null")
    end
    local out = {}
    local f = io.open(listing, 'rb')
    if f then
        for line in f:lines() do
            line = line:gsub('\r$', '')
            if line ~= '' then
                out[#out + 1] = line
            end
        end
        f:close()
    end
    os.remove(listing)
    return out
end

function fakes.read(path)
    local f = assert(io.open(path, 'rb'))
    local data = f:read('*a')
    f:close()
    return data
end

function fakes.write(path, data)
    local f = assert(io.open(path, 'wb'))
    f:write(data)
    f:close()
end

function fakes.copy(from, to)
    fakes.write(to, fakes.read(from))
end

-- A fresh, empty folder under tests/tmp/.
local counter = 0
function fakes.temp_dir(name)
    counter = counter + 1
    local dir = ('%s%s_%d/'):format(TMP, (name or 'case'):gsub('[^%w]+', '_'), counter)
    fakes.rmtree(dir)
    assert(fakes.mkdir(dir), 'could not create ' .. dir)
    return dir
end

function fakes.cleanup()
    if not os.getenv('NOTEORIOUS_KEEP_TMP') then
        fakes.rmtree(TMP)
    end
end

--[[ Zones (shaped like Windower's resources) ]]

function fakes.zone_table()
    local zones = dofile(ROOT .. 'tests/fixtures/zones.lua')
    for _, z in pairs(zones) do
        z.name = z.en -- the real resources library maps .name to the client language
    end
    return zones
end

-- The adapter core/library.lua expects (same logic as the addon's).
function fakes.zones()
    local zones = fakes.zone_table()
    local by_name = {}
    for id, z in pairs(zones) do
        for _, field in ipairs({ 'en', 'ja' }) do
            local key = z[field]:lower()
            by_name[key] = by_name[key] or {}
            table.insert(by_name[key], id)
        end
    end
    return {
        lookup = function(name)
            return by_name[(name:gsub('^%s+', ''):gsub('%s+$', '')):lower()]
        end,
        name_of = function(id)
            return zones[id] and zones[id].en or nil
        end,
    }
end

--[[ Fake texts library (used when Windower's texts.lua is not available) ]]

local STYLE_METHODS = {
    'font', 'size', 'bold', 'italic', 'color', 'alpha', 'bg_color', 'bg_alpha',
    'bg_visible', 'pad', 'stroke_width', 'stroke_color', 'stroke_alpha',
}

function fakes.texts_lib()
    local texts = { created = {} }
    local Text = {}
    Text.__index = Text

    function texts.new(str, settings)
        local t = setmetatable({
            template = str, settings = settings, values = {}, shown = false,
            x = 0, y = 0, events = {}, style = {},
        }, Text)
        texts.created[#texts.created + 1] = t
        return t
    end

    function Text:update(attr)
        for k, v in pairs(attr or {}) do
            self.values[k] = v
        end
    end

    function Text:content()
        return (self.template:gsub('%${(%w+)}', function(k)
            return tostring(self.values[k] or '')
        end))
    end

    function Text:show() self.shown = true end
    function Text:hide() self.shown = false end
    function Text:visible() return self.shown end

    function Text:pos(x, y)
        if x == nil then
            return self.x, self.y
        end
        self.x, self.y = x, y
    end

    for _, name in ipairs(STYLE_METHODS) do
        Text[name] = function(self, ...)
            self.style[name] = { ... }
        end
    end

    function Text:register_event(name, fn)
        self.events[name] = self.events[name] or {}
        table.insert(self.events[name], fn)
    end

    function Text:destroy()
        self.destroyed = true
    end

    -- Test helper: what texts.lua does while the mouse drags the box.
    function Text:drag_to(x, y)
        self.x, self.y = x, y
        for _, fn in ipairs(self.events.drag or {}) do
            fn(self, x, y)
        end
    end

    return texts
end

--[[ Recording backend for Windower's real texts.lua ]]

function fakes.text_backend(w)
    local items = {}
    local function set(field)
        return function(name, ...)
            items[name][field] = { ... }
        end
    end
    w.text_items = items
    w.text = {
        create = function(name)
            items[name] = { name = name, text = '', visible = false, x = 0, y = 0, size = 12 }
        end,
        delete = function(name)
            items[name] = nil
        end,
        set_text = function(name, s) items[name].text = s end,
        set_location = function(name, x, y) items[name].x, items[name].y = x, y end,
        get_location = function(name) return items[name].x, items[name].y end,
        set_visibility = function(name, v) items[name].visible = v end,
        set_font_size = function(name, s) items[name].size = s end,
        get_extents = function(name)
            local item = items[name]
            local plain = item.text:gsub('\\cs%b()', '')
            plain = plain:gsub('\\cr', '')
            local width, lines = 0, 0
            for line in (plain .. '\n'):gmatch('(.-)\n') do
                lines = lines + 1
                width = math.max(width, #line)
            end
            return width * math.ceil(item.size * 0.6), lines * math.ceil(item.size * 1.4)
        end,
        set_font = set('fonts'),
        set_bg_border_size = set('padding'),
        set_color = set('color'),
        set_bg_color = set('bg_color'),
        set_bg_visibility = set('bg_visible'),
        set_italic = set('italic'),
        set_bold = set('bold'),
        set_right_justified = set('right'),
        set_stroke_width = set('stroke_width'),
        set_stroke_color = set('stroke_color'),
    }
end

--[[ Fake images library ]]

function fakes.images_lib()
    local images = { created = {} }
    local Image = {}
    Image.__index = Image

    function images.new(settings)
        local img = setmetatable({ settings = settings, shown = false, x = 0, y = 0, file = '', w = 0, h = 0 }, Image)
        images.created[#images.created + 1] = img
        return img
    end

    function Image:show() self.shown = true end
    function Image:hide() self.shown = false end
    function Image:visible() return self.shown end
    function Image:path(p) self.file = p end
    function Image:size(w, h) self.w, self.h = w, h end
    function Image:destroy() self.destroyed = true end

    function Image:pos(x, y)
        if x == nil then
            return self.x, self.y
        end
        self.x, self.y = x, y
    end

    return images
end

--[[ Fake windower ]]

function fakes.windower(opts)
    local w = {
        addon_path = opts.root,
        windower_path = opts.root,
        events = {},
        chat = {},
        clipboard = nil,
        mobs = {},
        target_id = nil,
        info = { logged_in = opts.logged_in ~= false, zone = opts.zone or 154, language = 'English' },
        player = { id = 1000, index = 1, name = 'Tester' },
        settings = { ui_x_res = 1920, ui_y_res = 1080, x_res = 1920, y_res = 1080 },
    }

    function w.register_event(...)
        local n = select('#', ...)
        local fn = select(n, ...)
        for i = 1, n - 1 do
            local name = select(i, ...)
            w.events[name] = w.events[name] or {}
            table.insert(w.events[name], fn)
        end
        return n
    end

    function w.unregister_event() end

    function w.fire(name, ...)
        for _, fn in ipairs(w.events[name] or {}) do
            fn(...)
        end
    end

    -- Mouse events pass "blocked" along like Windower does.
    function w.mouse(kind, x, y)
        local blocked = false
        for _, fn in ipairs(w.events.mouse or {}) do
            if fn(kind, x, y, 0, blocked) == true then
                blocked = true
            end
        end
        return blocked
    end

    function w.add_to_chat(mode, msg)
        w.chat[#w.chat + 1] = msg
    end

    function w.copy_to_clipboard(s)
        w.clipboard = s
    end

    w.file_exists = fakes.file_exists
    w.dir_exists = fakes.dir_exists
    w.create_dir = function(path)
        return fakes.mkdir(path)
    end
    w.get_dir = fakes.list

    function w.get_windower_settings()
        return w.settings
    end

    w.ffxi = {
        get_info = function() return w.info end,
        get_player = function() return w.player end,
        get_mob_by_id = function(id) return w.mobs[id] end,
        get_mob_by_index = function(index)
            for _, m in pairs(w.mobs) do
                if m.index == index then
                    return m
                end
            end
            return nil
        end,
        get_mob_by_target = function(t)
            if t == 't' and w.target_id then
                return w.mobs[w.target_id]
            end
            return nil
        end,
    }

    --[[ Test helpers ]]

    -- Adds a mob table shaped like windower.ffxi.get_mob_by_id's result.
    function w.add_mob(m)
        local zone = m.zone or w.info.zone
        m.index = m.index or (m.id and m.id % 0x1000) or 1
        m.id = m.id or (0x01000000 + zone * 0x1000 + m.index)
        if m.is_npc == nil then m.is_npc = true end
        m.status = m.status or 0
        m.claim_id = m.claim_id or 0
        m.hpp = m.hpp or 100
        if m.valid_target == nil then m.valid_target = true end
        m.zone = nil
        w.mobs[m.id] = m
        return m
    end

    function w.target(m)
        w.target_id = m and m.id or nil
        w.fire('target change', m and m.index or 0)
    end

    function w.go_to_zone(zone)
        local old = w.info.zone
        w.target_id = nil
        w.mobs = {}
        w.info.zone = zone
        w.fire('target change', 0)
        w.fire('zone change', zone, old)
    end

    function w.command(...)
        w.fire('addon command', ...)
    end

    -- Simulated incoming 0x029 packet: `target_id` died (message 6).
    function w.defeat(target_id, message)
        w.fire('incoming chunk', 0x029, fakes.action_message(w.player.id, target_id, message or 6))
    end

    function w.tick()
        w.fire('prerender')
    end

    -- Moves the clock forward, then runs the once-per-second check.
    function w.advance(seconds)
        fakes.now = fakes.now + seconds
        w.fire('prerender')
    end

    -- What Windower fires around logging out and back in.
    function w.logout()
        local old = w.info.zone
        w.info.logged_in, w.info.zone = false, 0
        w.target_id = nil
        w.fire('zone change', 0, old)
        w.fire('logout', w.player.name)
    end

    function w.login(zone)
        w.info.logged_in, w.info.zone = true, zone
        w.fire('login', w.player.name)
        w.fire('zone change', zone, 0)
    end

    function w.chat_text()
        return table.concat(w.chat, '\n')
    end

    function w.clear_chat()
        w.chat = {}
    end

    return w
end

-- Builds an incoming 0x029 (action message) packet.
function fakes.action_message(actor, target, message)
    local function u32(n)
        return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
    end
    local function u16(n)
        return string.char(n % 256, math.floor(n / 256) % 256)
    end
    return u16(0x029) .. u16(0) .. u32(actor) .. u32(target) .. u32(0) .. u32(0)
        .. u16(actor % 0x1000) .. u16(target % 0x1000) .. u16(message) .. u16(0)
end

--[[ Windower's global library changes ]]

-- In Windower, `require('resources')` loads the tables library, which
-- replaces table.sort (now returns the table) and table.concat (rebuilt on a
-- next()-based iterator). Windower's libs cannot load in stock Lua (they use
-- patched syntax), so the same behavior is reproduced here for the
-- end-to-end tests.
function fakes.windower_globals()
    if fakes.globals_patched then
        return
    end
    fakes.globals_patched = true
    local raw_sort = table.sort
    table.sort = function(t, ...)
        raw_sort(t, ...)
        return t
    end
    table.concat = function(t, delim, from, to)
        delim = delim or ''
        local res = ''
        if from or to then
            from = from or 1
            to = to or #t
            for key = from, to do
                res = res .. tostring(rawget(t, key))
                if key < to then
                    res = res .. delim
                end
            end
        else
            local key = next(t)
            while key ~= nil do
                res = res .. tostring(t[key])
                key = next(t, key)
                if key ~= nil then
                    res = res .. delim
                end
            end
        end
        return res
    end
end

--[[ A controllable clock: os.time() returns fakes.now during end-to-end tests ]]

fakes.now = 1800000000
local real_time = os.time

function fakes.install_clock()
    if fakes.clock_installed then
        return
    end
    fakes.clock_installed = true
    os.time = function(t)
        if t ~= nil then
            return real_time(t)
        end
        return fakes.now
    end
end

--[[ Booting the addon ]]

local LIB_MODULES = { 'texts', 'images', 'resources' }

-- Loads Noteorious.lua in a fresh fake Windower. opts:
--   name        label for the temp folder
--   dir         reuse an existing addon folder (to test a restart)
--   notes       text for data/notes.lua (default: a copy of the shipped one)
--   no_notes    start without data/notes.lua
--   no_icons    start without the icons folder
--   zone, logged_in, mobs (list of mob tables to add before load)
function fakes.boot(opts)
    opts = opts or {}
    fakes.windower_globals()
    fakes.install_clock()
    local dir = opts.dir
    if not dir then
        dir = fakes.temp_dir(opts.name)
        fakes.mkdir(dir .. 'data')
        if opts.notes then
            fakes.write(dir .. 'data/notes.lua', opts.notes)
        elseif not opts.no_notes then
            fakes.copy(ROOT .. 'data/notes.lua', dir .. 'data/notes.lua')
        end
        if not opts.no_icons then
            fakes.mkdir(dir .. 'icons')
            for _, icon in ipairs({ 'warning', 'skull', 'info', 'note', 'reminder', 'star' }) do
                fakes.copy(ROOT .. 'icons/' .. icon .. '.png', dir .. 'icons/' .. icon .. '.png')
            end
        end
    end

    local w = fakes.windower({ root = dir, zone = opts.zone, logged_in = opts.logged_in })
    _G.windower = w
    _G._addon = {}

    for _, name in ipairs(LIB_MODULES) do
        package.loaded[name] = nil
    end
    local images = fakes.images_lib()
    w.images = images
    package.preload.images = function() return images end
    local zone_table = fakes.zone_table()
    package.preload.resources = function() return { zones = zone_table } end
    if WINDOWER_LIBS then
        fakes.text_backend(w)
        package.preload.texts = function() return dofile(WINDOWER_LIBS .. 'texts.lua') end
        w.real_texts = true
    else
        local texts = fakes.texts_lib()
        w.texts = texts
        package.preload.texts = function() return texts end
    end

    for _, m in ipairs(opts.mobs or {}) do
        w.add_mob(m)
    end
    dofile(ROOT .. 'Noteorious.lua')
    w.fire('load')
    w.dir = dir

    -- The note box as drawn: { visible, content, x, y }, plus the icon.
    function w.view()
        local box
        if w.real_texts then
            for _, item in pairs(w.text_items) do
                box = { visible = item.visible, content = item.text, x = item.x, y = item.y, item = item }
            end
        else
            local t = w.texts.created[1]
            box = { visible = t.shown, content = t:content(), x = t.x, y = t.y, item = t }
        end
        local icon = images.created[1]
        box.icon = { visible = icon.shown, file = icon.file, x = icon.x, y = icon.y, w = icon.w }
        return box
    end

    -- Drags the note box with the mouse from its current spot to (x, y).
    function w.drag_note(x, y)
        local box = w.view()
        if w.real_texts then
            w.mouse(1, box.x + 2, box.y + 2)
            w.mouse(0, x + 2, y + 2)
            w.mouse(2, x + 2, y + 2)
        else
            box.item:drag_to(x, y)
            w.mouse(2, x, y)
        end
    end

    return w
end

return fakes
