--[[
    Noteorious - core/identity.lua

    A monster's lasting identity is its zone id plus its name, written as
    "<zone id>:<name>", for example  154:Fafnir.

    Raw entity ids (17408018) are only used to look a loaded monster up.
    They are not stable identities: the same monster type has a different id
    in every zone and in every instance.
]]

local util = require('core/util')

local identity = {}

local KEYWORD_SUFFIX = '_note'

function identity.format(zone, name)
    return ('%d:%s'):format(zone, name)
end

-- Parses "<zone>:<name>". The zone may be an id or a zone name; `lookup(name)`
-- returns the ids for a zone name. Returns zone, name or nil, message.
function identity.parse(text, lookup)
    local zone_part, name = tostring(text):match('^%s*([^:]-)%s*:%s*(.-)%s*$')
    if not zone_part or zone_part == '' or name == '' then
        return nil, 'Expected <zone>:<monster name>, for example 154:Fafnir or Dragon\'s Aery:Fafnir.'
    end
    local zone = tonumber(zone_part)
    if not zone then
        local ids = lookup and lookup(zone_part)
        if not ids or #ids == 0 then
            return nil, ('Unknown zone "%s". Use the zone number shown by //nt id.'):format(zone_part)
        end
        if #ids > 1 then
            return nil, ('"%s" matches several zones (%s); use the zone number instead.'):format(zone_part, table.concat(ids, ', '))
        end
        zone = ids[1]
    end
    if zone < 0 or zone ~= math.floor(zone) then
        return nil, ('%s is not a valid zone id.'):format(zone_part)
    end
    return zone, name
end

-- Monster and NPC ids encode their zone: 0x01000000 + zone * 0x1000 + index.
-- Returns the zone id, or nil when `id` is not such an id (players, etc.).
function identity.zone_of_entity(id)
    if type(id) ~= 'number' or id < 0x01000000 or id >= 0x02000000 then
        return nil
    end
    return math.floor((id - 0x01000000) / 0x1000)
end

-- A readable Lua key for a note: "Gu'Dha Effigy" -> "gudha_effigy".
function identity.slug(name)
    local s = tostring(name):lower():gsub("'", '')
    s = s:gsub('[^a-z0-9]+', '_') -- explicit ASCII: %w follows the C locale in PUC Lua
    s = s:gsub('^_+', ''):gsub('_+$', '')
    if s == '' then
        s = 'note'
    end
    if s:match('^%d') then
        s = 'mob_' .. s
    end
    if not util.is_identifier(s) then
        s = s .. KEYWORD_SUFFIX
    end
    return s
end

-- A key not present in `taken`: base, then base_<zone>, then base_2, base_3 ...
function identity.unique_key(base, taken, zone_slug)
    if not taken[base] then
        return base
    end
    if zone_slug and zone_slug ~= '' then
        local with_zone = base .. '_' .. zone_slug
        if not taken[with_zone] then
            return with_zone
        end
    end
    local n = 2
    while taken[base .. '_' .. n] do
        n = n + 1
    end
    return base .. '_' .. n
end

return identity
