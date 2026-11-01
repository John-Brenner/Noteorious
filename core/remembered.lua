--[[
    Noteorious - core/remembered.lua

    Things the addon remembers for you, kept in data/remembered.lua and never
    in your note library (so notes.lua stays shareable and is only changed by
    you or by //nt new):

      auto       automatic display on/off (//nt toggle)
      positions  where you dragged notes

    Positions: notes without their own `position` share one remembered spot
    ("*"); a note with its own `position` remembers its own spot. Each saved
    spot also records the configured position it was dragged from. If you
    later edit that position in notes.lua, your edit wins and the old drag is
    ignored.

    The file is machine-written and safe to delete.
]]

local util = require('core/util')

local remembered = {}

local HEADER = '-- Written by Noteorious: remembered note positions and toggles.\n'
    .. '-- Safe to delete. Your notes live in notes.lua, not here.\n'

function remembered.fresh()
    return { auto = true, positions = {} }
end

local function clean(data)
    local out = remembered.fresh()
    if type(data) ~= 'table' then
        return out
    end
    if type(data.auto) == 'boolean' then
        out.auto = data.auto
    end
    if type(data.positions) == 'table' then
        for slot, p in pairs(data.positions) do
            if type(slot) == 'string' and type(p) == 'table'
                and type(p.x) == 'number' and type(p.y) == 'number'
                and type(p.base_x) == 'number' and type(p.base_y) == 'number' then
                out.positions[slot] = { x = p.x, y = p.y, base_x = p.base_x, base_y = p.base_y }
            end
        end
    end
    return out
end

-- Loads remembered data. `evaluate` is core/library.evaluate (sandboxed).
-- Returns data, problem (problem is set when the file existed but was unreadable).
function remembered.load(path, evaluate)
    local text = util.read_file(path)
    if not text then
        return remembered.fresh()
    end
    local data, err = evaluate(text, 'data/remembered.lua')
    if not data then
        return remembered.fresh(), err
    end
    return clean(data)
end

function remembered.save(path, data)
    return util.write_file(path, HEADER .. 'return ' .. util.serialize(clean(data)) .. '\n')
end

local function slot_of(note)
    return note.own_position and note.key or '*'
end

-- Where to draw a note: its dragged spot if still valid, else its configured position.
function remembered.position(data, note)
    local base = note.position
    local saved = data.positions[slot_of(note)]
    if saved and saved.base_x == base.x and saved.base_y == base.y then
        return saved.x, saved.y
    end
    return base.x, base.y
end

function remembered.set_position(data, note, x, y)
    data.positions[slot_of(note)] = {
        x = math.floor(x + 0.5), y = math.floor(y + 0.5),
        base_x = note.position.x, base_y = note.position.y,
    }
end

-- //nt resetpos: forgets the dragged spot `note` uses (shared by every note
-- without its own position). Returns true if there was one.
function remembered.reset(data, note)
    local slot = slot_of(note)
    local had = data.positions[slot] ~= nil
    data.positions[slot] = nil
    return had
end

-- //nt resetpos all: forgets every dragged spot. Returns how many there were.
function remembered.reset_all(data)
    local n = util.count(data.positions)
    data.positions = {}
    return n
end

return remembered
