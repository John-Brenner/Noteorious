--[[
    Noteorious - core/display.lua

    Draws the one visible note with Windower's `texts` library, plus an
    optional icon with the `images` library to the left of the box.

    Layout:   [icon]  +-----------------------------+
                      | Title            (accent)   |
                      | body text, word-wrapped     |
                      +-----------------------------+

    * The text object is created from the template '${body}' and the note is
      passed in as the value of `body`. texts.lua does not parse variable
      values, so "${...}" inside your note text is shown literally.
    * Inline colors in note text (\cs(r,g,b)...\cr) are drawn by Windower.
    * The box is draggable (texts.lua handles the drag). The icon follows via
      the text object's 'drag' event; the position is saved on mouse release.
    * Missing icon images fall back to a text icon in the title.
    * Fonts are passed with fallbacks (your font, then Consolas, then Arial),
      so an uninstalled font does not leave the note blank.

    deps = {
        texts, images,            -- the Windower libraries (or test fakes)
        file_exists(path),
        screen() -> width, height -- UI resolution, for keeping notes on screen
        icon_dir,                 -- folder with the built-in icons
        position(note) -> x, y    -- where to draw a note
        moved(note, x, y),        -- called after the user drags a note
        warn(message),
    }
]]

local util = require('core/util')
local settings = require('core/settings')

local unpack = unpack or table.unpack

local display = {}

local Display = {}
Display.__index = Display

local ICON_GAP = 4

-- The string shown in the box: a colored header line and the wrapped body.
-- opts.glyph: text icon to put before the title; opts.pinned: add a marker.
function display.compose(note, opts)
    opts = opts or {}
    local header = {}
    if opts.glyph then
        header[#header + 1] = opts.glyph
    end
    if note.title and note.title ~= '' then
        header[#header + 1] = note.title
    end
    if opts.pinned then
        header[#header + 1] = '[pinned]'
    end

    local out = {}
    if #header > 0 then
        local c = note.color
        out[1] = ('\\cs(%d,%d,%d)%s\\cr'):format(c[1], c[2], c[3], table.concat(header, ' '))
    end

    local body = {}
    if note.text and note.text ~= '' then
        body = util.wrap(note.text, note.width)
    end
    local max = note.max_lines
    if max > 0 and #body > max then
        local hidden = #body - max + 1
        for i = #body, max, -1 do
            body[i] = nil
        end
        body[max] = ('... (%d more line%s in the note file)'):format(hidden, hidden == 1 and '' or 's')
    end
    for _, line in ipairs(body) do
        out[#out + 1] = line
    end
    return table.concat(out, '\n')
end

function display.new(deps)
    local self = setmetatable({ deps = deps, missing = {}, note = nil, dragging = false, icon_size = 0 }, Display)

    self.text = deps.texts.new('${body}', {
        pos = { x = 0, y = 0 },
        bg = { alpha = 220, red = 18, green = 18, blue = 26, visible = true },
        flags = { draggable = true, bold = false, italic = false, right = false, bottom = false },
        padding = 6,
        text = {
            font = 'Consolas', fonts = { 'Arial' }, size = 12,
            alpha = 255, red = 255, green = 255, blue = 255,
            stroke = { width = 0, alpha = 255, red = 0, green = 0, blue = 0 },
        },
    })
    self.text:hide()
    self.text:register_event('drag', function(_, x, y)
        self.dragging = true
        self:place_icon(x, y)
    end)

    self.icon = deps.images.new({
        pos = { x = 0, y = 0 },
        visible = false,
        draggable = false,
        color = { alpha = 255, red = 255, green = 255, blue = 255 },
        size = { width = 24, height = 24 },
        -- fit = false: draw at icon_size instead of the image's own size
        -- (the same settings equipviewer uses for its scaled icons).
        texture = { path = '', fit = false },
        repeatable = { x = 1, y = 1 },
    })
    self.icon:hide()
    return self
end

-- Path of the image for an icon setting, or nil when there is no usable file.
function Display:icon_path(icon)
    if not icon then
        return nil
    end
    if icon:find('[/\\:]') or icon:find('..', 1, true) then
        return nil -- only files inside the icons folder (settings.lua refuses paths too)
    end
    local path = self.deps.icon_dir .. icon
    if settings.icons[icon] or not icon:match('%.%w+$') then
        path = path .. '.png'
    end
    if self.deps.file_exists(path) then
        return path
    end
    if not self.missing[path] then
        self.missing[path] = true
        self.deps.warn(('Icon image not found: %s (using a text icon instead).'):format(path))
    end
    return nil
end

-- Keeps the box (and its icon) on screen.
function Display:clamp(x, y)
    local pad = self.note.padding
    local min_x = pad + (self.icon_size > 0 and (self.icon_size + ICON_GAP) or 0)
    local w, h = self.deps.screen()
    if w and h then
        x = math.min(x, w - 60)
        y = math.min(y, h - 30)
    end
    return math.max(min_x, x), math.max(pad, y)
end

function Display:place_icon(x, y)
    if self.icon_size > 0 and self.note then
        local pad = self.note.padding
        self.icon:pos(x - pad - ICON_GAP - self.icon_size, y - pad)
    end
end

function Display:apply_style(note)
    local t = self.text
    local fonts = { note.font }
    if note.font:lower() ~= 'consolas' then
        fonts[#fonts + 1] = 'Consolas'
    end
    fonts[#fonts + 1] = 'Arial'
    t:font(unpack(fonts))
    t:size(note.font_size)
    t:bold(note.bold)
    t:italic(note.italic)
    local tc, bg, oc = note.text_color, note.background, note.outline_color
    t:alpha(255)
    t:color(tc[1], tc[2], tc[3])
    t:bg_alpha(note.opacity)
    t:bg_color(bg[1], bg[2], bg[3])
    t:bg_visible(note.opacity > 0)
    t:pad(note.padding)
    t:stroke_width(note.outline)
    t:stroke_alpha(255)
    t:stroke_color(oc[1], oc[2], oc[3])
end

-- Shows `note`. opts.pinned adds a "[pinned]" marker to the title.
function Display:show(note, opts)
    opts = opts or {}
    self.note = note
    self:apply_style(note)

    local image = note.icon_style == 'image' and self:icon_path(note.icon) or nil
    local glyph
    if note.icon and note.icon_style ~= 'none' and not image then
        glyph = settings.icons[note.icon] or '(*)'
    end
    self.text:update({ body = display.compose(note, { pinned = opts.pinned, glyph = glyph }) })

    self.icon_size = image and note.icon_size or 0
    local x, y = self:clamp(self.deps.position(note))
    self.text:pos(x, y)
    if image then
        self.icon:path(image)
        self.icon:size(note.icon_size, note.icon_size)
        self:place_icon(x, y)
        self.icon:show()
    else
        self.icon:hide()
    end
    self.text:show()
end

function Display:hide()
    self.text:hide()
    self.icon:hide()
    self.note = nil
    self.dragging = false
end

-- Forward of the 'mouse' event. Saves the position when a drag ends.
-- Never blocks the event (texts.lua already handles clicks on the box).
function Display:mouse(kind)
    if kind == 2 and self.dragging then
        self.dragging = false
        if self.note then
            local x, y = self.text:pos()
            self.deps.moved(self.note, x, y)
        end
    end
end

function Display:destroy()
    self.text:destroy()
    self.icon:destroy()
end

return display
