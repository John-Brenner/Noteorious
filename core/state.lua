--[[
    Noteorious - core/state.lua

    Decides which single note is visible. Pure logic: it never calls the
    windower API. The addon passes in:

        find(mob)        -> the best note for a monster record, or nil
        mob_status(id)   -> 'fighting' (claimed by you, your party or alliance,
                            or engaged without any claim)
                          | 'alive' | 'dead' | 'gone' (despawned / out of range)
        clock()          -> seconds (optional, defaults to os.time)

    A monster record is { id = entity id, name = , zone = zone id }.

    Three slots, highest priority first; the first one that is set is shown:

      held       stays until dismissed. Filled by //mn pin (how = 'pin'),
                 //mn show (how = 'show') or a note whose mode is "pinned"
                 (how = 'pinned'). An automatic note never replaces it.
      focus      a "target" mode note. Follows the current target exactly.
      encounter  a "combat" mode note plus the set of monsters that belong to
                 the fight. It survives target switches while one of those
                 monsters is still being fought (or targeted) and ends when
                 they are all dead or despawned, or when none of them has
                 been fought or targeted for ENCOUNTER_GRACE seconds (the
                 grace covers the moment between a pull and its claim).

    Close conditions:
      close_on_death   focus closes when its monster dies; an encounter closes
                       when its last monster dies; a pinned-mode or //mn show
                       note closes when the monsters it was opened for die.
                       With close_on_death = false the note stays until the
                       next target change instead.
      close_on_zone    held notes ("pinned" mode, //mn show) close on zoning.
                       Target and combat notes always end on zoning because
                       their monsters no longer exist.
      close_on_logout  any note, including //mn pin, closes on logout.
    A note pinned with //mn pin ignores close_on_zone and close_on_death.
]]

local state = {}

state.ENCOUNTER_GRACE = 5

local State = {}
State.__index = State

local function same(a, b)
    return a ~= nil and b ~= nil and a.key == b.key
end

function state.new(deps)
    deps.clock = deps.clock or os.time
    return setmetatable({
        deps = deps,
        auto = true,     -- automatic display (//mn toggle)
        target = nil,    -- current target record
        held = nil,      -- { note, how, mobs = { [id] = true } }
        focus = nil,     -- { note, mob_id }
        encounter = nil, -- { note, mobs = { [id] = true }, deaths, done, seen }
    }, State)
end

-- The note to display and the slot it came from.
function State:visible()
    local slot = self.held or self.focus or self.encounter
    if slot then
        return slot.note, slot
    end
    return nil
end

-- Whether the addon should call tick() (about once per second).
function State:needs_tick()
    if self.encounter then
        return true
    end
    if self.focus and self.focus.note.close_on_death then
        return true
    end
    local h = self.held
    return h ~= nil and h.how ~= 'pin' and h.note.close_on_death and next(h.mobs) ~= nil
end

-- Whether a monster id matters to the current state (cheap filter for death packets).
function State:tracks(id)
    if self.focus and self.focus.mob_id == id then
        return true
    end
    if self.held and self.held.mobs[id] then
        return true
    end
    return self.encounter ~= nil and self.encounter.mobs[id] == true
end

-- Drops dead or vanished monsters from the encounter and ends it when the
-- fight is over, or when none of its monsters has been fought or targeted
-- for ENCOUNTER_GRACE seconds.
function State:check_encounter()
    local enc = self.encounter
    if not enc or enc.done then
        return
    end
    local alive, fighting = false, false
    for id in pairs(enc.mobs) do
        local status = self.deps.mob_status(id)
        if status == 'dead' then
            enc.mobs[id] = nil
            enc.deaths = true
        elseif status == 'gone' then
            enc.mobs[id] = nil
        else
            alive = true
            fighting = fighting or status == 'fighting'
        end
    end
    if not alive then
        if enc.deaths and not enc.note.close_on_death then
            enc.done = true -- keep it up until the next unrelated target
        else
            self.encounter = nil
        end
        return
    end
    local now = self.deps.clock()
    local targeted = self.target ~= nil and enc.mobs[self.target.id]
    if fighting or targeted then
        enc.seen = now
    elseif now - enc.seen >= state.ENCOUNTER_GRACE then
        self.encounter = nil
    end
end

-- The player targeted `mob` (a record) or cleared the target (nil).
function State:target_changed(mob)
    self.target = mob
    local note = mob and self.auto and self.deps.find(mob) or nil
    if note and note.mode == 'manual' then
        note = nil
    end

    self.focus = nil
    if note then
        if note.mode == 'target' then
            self.focus = { note = note, mob_id = mob.id }
        elseif note.mode == 'combat' then
            local enc = self.encounter
            if enc and same(enc.note, note) then
                enc.mobs[mob.id] = true
                enc.done = false
                enc.seen = self.deps.clock()
            else
                self.encounter = {
                    note = note, mobs = { [mob.id] = true }, deaths = false, done = false, seen = self.deps.clock(),
                }
            end
        elseif note.mode == 'pinned' then
            local h = self.held
            if not h then
                self.held = { note = note, how = 'pinned', mobs = { [mob.id] = true } }
            elseif h.how ~= 'pin' and same(h.note, note) then
                h.mobs[mob.id] = true
            end
        end
    end

    local enc = self.encounter
    if enc and not (note and same(enc.note, note)) then
        if enc.done then
            self.encounter = nil
        else
            self:check_encounter()
        end
    end
end

-- A monster died (from a defeat message or a status check).
function State:mob_died(id)
    local f = self.focus
    if f and f.mob_id == id and f.note.close_on_death then
        self.focus = nil
    end
    local h = self.held
    if h and h.how ~= 'pin' and h.mobs[id] then
        h.mobs[id] = nil
        if h.note.close_on_death and next(h.mobs) == nil then
            self.held = nil
        end
    end
    local enc = self.encounter
    if enc and enc.mobs[id] then
        enc.mobs[id] = nil
        enc.deaths = true
        if next(enc.mobs) == nil then
            if enc.note.close_on_death then
                self.encounter = nil
            else
                enc.done = true
            end
        end
    end
end

-- Periodic check for deaths and despawns that no message reported.
function State:tick()
    local f = self.focus
    if f and f.note.close_on_death and self.deps.mob_status(f.mob_id) == 'dead' then
        self:mob_died(f.mob_id)
    end
    local h = self.held
    if h and h.how ~= 'pin' then
        for id in pairs(h.mobs) do
            local status = self.deps.mob_status(id)
            if status == 'dead' then
                self:mob_died(id)
            elseif status == 'gone' then
                h.mobs[id] = nil
            end
        end
    end
    self:check_encounter()
end

function State:zone_changed()
    self.target, self.focus, self.encounter = nil, nil, nil
    local h = self.held
    if h then
        if h.how ~= 'pin' and h.note.close_on_zone then
            self.held = nil
        else
            h.mobs = {} -- its monsters belong to the old zone
        end
    end
end

function State:logged_out()
    self.target, self.focus, self.encounter = nil, nil, nil
    local h = self.held
    if h then
        if h.note.close_on_logout then
            self.held = nil
        else
            h.mobs = {}
        end
    end
end

-- //mn hide: dismisses everything. Returns the note that was visible.
function State:hide()
    local note = self:visible()
    self.held, self.focus, self.encounter = nil, nil, nil
    return note
end

-- //mn pin: pins the visible note (or `fallback` when nothing is visible),
-- or unpins a pinned one. Returns 'pinned' | 'unpinned' | nil, note.
function State:pin(fallback)
    local h = self.held
    if h and h.how == 'pin' then
        self.held = nil
        return 'unpinned', h.note
    end
    local note = self:visible() or fallback
    if not note then
        return nil
    end
    self.held = { note = note, how = 'pin', mobs = {} }
    return 'pinned', note
end

-- //mn show: displays a note explicitly. `mob` (optional) is the monster it
-- was opened for; close_on_death then applies to it.
function State:show(note, mob)
    self.held = { note = note, how = 'show', mobs = mob and { [mob.id] = true } or {} }
end

-- //mn toggle: automatic display on or off. Explicit notes stay.
function State:set_auto(on)
    self.auto = on and true or false
    if self.auto then
        if self.target then
            self:target_changed(self.target)
        end
    else
        self.focus, self.encounter = nil, nil
        if self.held and self.held.how == 'pinned' then
            self.held = nil
        end
    end
end

-- After //mn reload: swaps in the reloaded notes by key, drops notes that no
-- longer exist (or changed mode), and re-evaluates the current target.
function State:reload(lookup)
    local h = self.held
    if h then
        local note = lookup(h.note.key)
        if note and (h.how ~= 'pinned' or note.mode == 'pinned') then
            h.note = note
        else
            self.held = nil
        end
    end
    local enc = self.encounter
    if enc then
        local note = lookup(enc.note.key)
        if note and note.mode == 'combat' then
            enc.note = note
        else
            self.encounter = nil
        end
    end
    self.focus = nil
    if self.target then
        self:target_changed(self.target)
    end
end

return state
