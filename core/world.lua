--[[
    Noteorious - core/world.lua

    The only place (besides the addon file) that reads game state. It turns
    windower.ffxi tables into the small records the rest of the addon uses,
    and parses the defeat messages in incoming 0x029 packets.

    Verified against the Windower 4 Lua wiki and existing addons:
      * mob tables have id, index, name, status, claim_id, is_npc,
        valid_target, in_party, in_alliance
      * status 2 = Dead, 3 = Engaged dead (resources/statuses.lua)
      * the "action message" event is deprecated; 0x029 is parsed instead,
        the same way the Debuffed addon does it
]]

local util = require('core/util')

local world = {}

-- Action messages whose ${target} has died (see resources/action_messages.lua):
--   6 "${actor} defeats ${target}."            20 "${target} falls to the ground."
--   113/406/646 "... ${target} falls to the ground."
--   605 "Additional effect: ${target} falls to the ground."
world.DEATH_MESSAGES = { [6] = true, [20] = true, [113] = true, [406] = true, [605] = true, [646] = true }

-- Incoming 0x029 layout (byte offsets from the packet start):
--   0x04 actor id, 0x08 target id, 0x0C param 1, 0x10 param 2,
--   0x14 actor index, 0x16 target index, 0x18 message id (low 15 bits).
-- Returns the id of the entity that died, or nil.
function world.death_from_packet(data)
    if type(data) ~= 'string' or #data < 0x1A then
        return nil
    end
    local message = util.u16le(data, 0x19) % 0x8000
    if world.DEATH_MESSAGES[message] then
        return util.u32le(data, 0x09)
    end
    return nil
end

function world.new(windower)
    local ffxi = windower.ffxi
    local self = {}

    -- Current zone id, or nil while not logged in.
    function self.zone()
        local info = ffxi.get_info()
        if info and info.logged_in ~= false and info.zone and info.zone ~= 0 then
            return info.zone
        end
        return nil
    end

    -- { id, index, name, zone, is_npc } for a mob table, or nil.
    function self.record(m, zone)
        if type(m) ~= 'table' or not m.id or type(m.name) ~= 'string' or m.name == '' then
            return nil
        end
        return { id = m.id, index = m.index, name = m.name, zone = zone or self.zone(), is_npc = m.is_npc ~= false }
    end

    function self.by_index(index)
        if not index or index == 0 then
            return nil
        end
        return self.record(ffxi.get_mob_by_index(index))
    end

    function self.by_id(id)
        return self.record(ffxi.get_mob_by_id(id))
    end

    function self.target()
        return self.record(ffxi.get_mob_by_target('t'))
    end

    -- Whether a claim belongs to you, your party or your alliance.
    local function our_claim(claim_id)
        if not claim_id or claim_id == 0 then
            return false
        end
        local player = ffxi.get_player()
        if player and player.id == claim_id then
            return true
        end
        local claimer = ffxi.get_mob_by_id(claim_id)
        return type(claimer) == 'table' and (claimer.in_party == true or claimer.in_alliance == true)
    end

    -- 'fighting' | 'alive' | 'dead' | 'gone', as core/state.lua expects.
    -- 'fighting' = claimed by you, your party or alliance, or engaged without a claim.
    function self.mob_status(id)
        local m = ffxi.get_mob_by_id(id)
        if type(m) ~= 'table' then
            return 'gone'
        end
        if m.status == 2 or m.status == 3 then
            return 'dead'
        end
        if our_claim(m.claim_id) then
            return 'fighting'
        end
        -- Engaged but unclaimed: fights that have no claim (Reives, Domain
        -- Invasion, Campaign). A claim by someone outside your party or
        -- alliance is their fight, not yours.
        if m.status == 1 and (m.claim_id or 0) == 0 then
            return 'fighting'
        end
        if m.valid_target == false and m.status ~= 1 then
            return 'gone'
        end
        return 'alive'
    end

    return self
end

return world
