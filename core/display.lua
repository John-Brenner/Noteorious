--[[
    Noteorious - core/display.lua

    Draws the one visible note with Windower's `texts` library, plus an
    optional icon with the `images` library to the left of the box.

    Layout:   [icon]  +-----------------------------+
                      | Title            (accent)   |
                      | body text, word-wrapped     |
                      | page 1/2 - //nt next, ...   |  (long notes only)
                      +-----------------------------+

    * The text object is created from the template '${body}' and the note is
      passed in as the value of `body`. texts.lua does not parse variable
      values, so "${...}" inside your note text is shown literally.
    * Inline colors in note text (\cs(r,g,b)...\cr) are drawn by Windower.
    * Notes longer than max_lines are split into pages (//nt next, //nt prev).
    * The box is draggable (texts.lua handles the drag). The icon follows via
      the text object's 'drag' event; the position is saved on mouse release.
    * Missing icon images fall back to a text icon in the title.
    * Fonts are passed with fallbacks (your font, then Consolas, then Arial),
      so an uninstalled font does not leave the note blank.

    Staying on screen: the box size comes from texts:extents() (Windower's
    windower.text.get_extents). Windower does not document whether that
    size includes the background padding, or how soon it reflects new text,
    so the padding is counted outside the measured size (at worst a few
    pixels too careful), and the box is measured again for a few frames
    after every change (settle(), called from prerender). The whole note
    and its icon are kept on screen when they fit; a note larger than the
    screen keeps its top-left corner, with the title, on screen.

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

local settings = require('core/settings')
local util = require('core/util')

local unpack = unpack or table.unpack

local display = {}

local Display = {}
Display.__index = Display

local ICON_GAP = 4
local FOOTER_COLOR = '\\cs(160,160,160)'

-- Frames to keep re-measuring the box after its text or style changed.
display.SETTLE_FRAMES = 10

-- The string shown in the box: a colored header line, the wrapped body and,
-- for a note longer than max_lines, one page of it plus a page footer.
-- opts.glyph: text icon before the title; opts.pinned: add a marker;
-- opts.page: which page to show (default 1).
-- Returns the text and the number of pages.
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
    local per_page, pages = #body, 1
    local max = note.max_lines
    if max > 0 and #body > max then
        per_page = math.max(1, max - 1) -- the last line is the page footer
        pages = math.ceil(#body / per_page)
    end
    local page = math.min(math.max(opts.page or 1, 1), pages)
    local first = (page - 1) * per_page + 1
    for i = first, math.min(#body, first + per_page - 1) do
        out[#out + 1] = body[i]
    end
    if pages > 1 then
        out[#out + 1] = ('%spage %d/%d - //nt next, //nt prev\\cr'):format(FOOTER_COLOR, page, pages)
    end
    return table.concat(out, '\n'), pages
end

function display.new(deps)
    local self = setmetatable({
        deps = deps, missing = {}, note = nil, dragging = false, icon_size = 0,
        page = 1, pages = 1, settle_left = 0, width = 0, height = 0,
    }, Display)

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
    -- texts.lua has already moved the box to (x, y); pull it back on screen.
    self.text:register_event('drag', function(_, x, y)
        if not self.note then
            return
        end
        self.dragging = true
        local cx, cy = self:clamp(x, y)
        if cx ~= x or cy ~= y then
            self.text:pos(cx, cy)
        end
        self:place_icon(cx, cy)
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

-- Reads the drawn size of the box. Keeps the last size while Windower
-- reports none (text not drawn yet). Returns true when the size changed.
function Display:measure()
    local w, h = self.text:extents()
    if type(w) == 'number' and type(h) == 'number' and w > 0 and h > 0 then
        local changed = w ~= self.width or h ~= self.height
        self.width, self.height = w, h
        return changed
    end
    return false
end

-- The closest position to (x, y) that keeps the box, its padding and its
-- icon on screen. When the note is larger than the screen, its top-left
-- corner (with the title) stays visible.
function Display:clamp(x, y)
    local pad = self.note.padding
    local icon = self.icon_size > 0 and (self.icon_size + ICON_GAP) or 0
    local right = self.width + pad
    local bottom = math.max(self.height + pad, self.icon_size - pad)
    local sw, sh = self.deps.screen()
    if sw and sh then
        x = math.min(x, sw - right)
        y = math.min(y, sh - bottom)
    end
    return math.max(x, pad + icon), math.max(y, pad)
end

function Display:place_icon(x, y)
    if self.icon_size > 0 and self.note then
        local pad = self.note.padding
        self.icon:pos(x - pad - ICON_GAP - self.icon_size, y - pad)
    end
end

-- Puts the box as close to (x, y) as fits on screen.
function Display:place(x, y)
    self.anchor_x, self.anchor_y = x, y
    local cx, cy = self:clamp(x, y)
    self.text:pos(cx, cy)
    self:place_icon(cx, cy)
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

-- Puts the current page of the note into the box and starts re-measuring.
function Display:render()
    local body, pages = display.compose(self.note, { pinned = self.pinned, glyph = self.glyph, page = self.page })
    self.pages = pages
    self.page = math.min(self.page, pages)
    self.text:update({ body = body })
    self:measure()
    self.settle_left = display.SETTLE_FRAMES
end

-- Shows `note`. opts.pinned adds a "[pinned]" marker to the title.
-- Showing the note that is already up keeps its page.
function Display:show(note, opts)
    opts = opts or {}
    if not (self.note and self.note.key == note.key) then
        self.page = 1
    end
    self.note = note
    self.pinned = opts.pinned
    self:apply_style(note)

    local image = note.icon_style == 'image' and self:icon_path(note.icon) or nil
    self.glyph = nil
    if note.icon and note.icon_style ~= 'none' and not image then
        self.glyph = settings.icons[note.icon] or '(*)'
    end
    self.icon_size = image and note.icon_size or 0
    self:render()

    if image then
        self.icon:path(image)
        self.icon:size(note.icon_size, note.icon_size)
        self.icon:show()
    else
        self.icon:hide()
    end
    self:place(self.deps.position(note))
    self.text:show()
end

-- Turns the page of a long note (wrapping around). Returns page, pages,
-- or nil when no note is shown.
function Display:turn(delta)
    if not self.note then
        return nil
    end
    if self.pages > 1 then
        self.page = (self.page - 1 + delta) % self.pages + 1
        self:render()
        self:place(self.anchor_x, self.anchor_y)
    end
    return self.page, self.pages
end

-- Called every frame. For a few frames after a change, moves the box back
-- on screen if its drawn size turns out different from what was measured.
function Display:settle()
    if self.settle_left <= 0 or not self.note or self.dragging then
        return
    end
    self.settle_left = self.settle_left - 1
    if self:measure() then
        local x, y = self:clamp(self.anchor_x, self.anchor_y)
        self.text:pos(x, y)
        self:place_icon(x, y)
    end
end

function Display:hide()
    self.text:hide()
    self.icon:hide()
    self.note = nil
    self.dragging = false
    self.page, self.pages, self.settle_left = 1, 1, 0
end

-- Forward of the 'mouse' event. Saves the position when a drag ends.
-- Never blocks the event (texts.lua already handles clicks on the box).
function Display:mouse(kind)
    if kind == 2 and self.dragging then
        self.dragging = false
        if self.note then
            local x, y = self.text:pos()
            self.anchor_x, self.anchor_y = x, y
            self.deps.moved(self.note, x, y)
            self.settle_left = display.SETTLE_FRAMES
        end
    end
end

function Display:destroy()
    self.text:destroy()
    self.icon:destroy()
end

return display
