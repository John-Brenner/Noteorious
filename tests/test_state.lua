local T = require('tests/harness')
local state = require('core/state')

-- A small world: notes by monster name, and a status per monster id.
local function setup(note_defs)
    local notes = {}
    for key, def in pairs(note_defs) do
        notes[key] = {
            key = key,
            mode = def.mode or 'target',
            close_on_zone = def.close_on_zone ~= false,
            close_on_death = def.close_on_death ~= false,
            close_on_logout = def.close_on_logout ~= false,
            names = def.names,
        }
    end
    local world = { status = {}, now = 0 }
    local function find(mob)
        for _, note in pairs(notes) do
            for _, n in ipairs(note.names or {}) do
                if n == mob.name then
                    return note
                end
            end
        end
        return nil
    end
    world.st = state.new({
        find = find,
        mob_status = function(id) return world.status[id] or 'gone' end,
        clock = function() return world.now end,
    })
    -- Moves the clock and runs the periodic check.
    world.advance = function(seconds)
        world.now = world.now + seconds
        world.st:tick()
    end
    world.notes = notes
    world.mob = function(id, name, status)
        world.status[id] = status or 'alive'
        return { id = id, name = name, zone = 1 }
    end
    world.visible = function()
        local note, slot = world.st:visible()
        return note and note.key, slot
    end
    return world
end

T.test('target mode follows the target exactly', function()
    local w = setup({ fafnir = { names = { 'Fafnir' } } })
    local fafnir, crab = w.mob(1, 'Fafnir'), w.mob(2, 'Crab')
    w.st:target_changed(fafnir)
    T.eq(w.visible(), 'fafnir')
    w.st:target_changed(crab)
    T.eq(w.visible(), nil)
    w.st:target_changed(fafnir)
    w.st:target_changed(nil)
    T.eq(w.visible(), nil)
end)

T.test('manual notes are never shown automatically', function()
    local w = setup({ secret = { mode = 'manual', names = { 'Fafnir' } } })
    w.st:target_changed(w.mob(1, 'Fafnir'))
    T.eq(w.visible(), nil)
    w.st:show(w.notes.secret)
    T.eq(w.visible(), 'secret')
end)

T.test('target mode closes on death, or stays until the target changes', function()
    local w = setup({ a = { names = { 'A' } }, b = { names = { 'B' }, close_on_death = false } })
    w.st:target_changed(w.mob(1, 'A'))
    T.ok(w.st:needs_tick())
    T.ok(w.st:tracks(1))
    w.st:mob_died(1)
    T.eq(w.visible(), nil, 'closed by the defeat message')

    w.st:target_changed(w.mob(2, 'B'))
    w.st:mob_died(2)
    T.eq(w.visible(), 'b', 'close_on_death = false keeps it on the corpse')
    w.st:target_changed(nil)
    T.eq(w.visible(), nil)

    w.st:target_changed(w.mob(3, 'A'))
    w.status[3] = 'dead'
    w.st:tick()
    T.eq(w.visible(), nil, 'the periodic check also notices a death')
end)

T.test('combat mode stays up while the encounter is being fought', function()
    local w = setup({ fomors = { mode = 'combat', names = { 'Fomor' } } })
    local f1, f2, crab = w.mob(1, 'Fomor'), w.mob(2, 'Fomor'), w.mob(9, 'Crab')
    w.st:target_changed(f1)
    T.eq(w.visible(), 'fomors')
    w.status[1] = 'fighting'
    w.st:target_changed(crab)
    T.eq(w.visible(), 'fomors', 'switching to an add keeps the note')
    w.st:target_changed(f2)
    T.ok(w.st.encounter.mobs[2], 'other matching monsters join the encounter')
    w.st:target_changed(nil)
    T.eq(w.visible(), 'fomors')
    w.st:mob_died(1)
    T.eq(w.visible(), 'fomors', 'f2 is still part of the fight')
    w.status[2] = 'fighting'
    w.st:mob_died(2)
    T.eq(w.visible(), nil, 'all dead: encounter over')
end)

T.test('combat mode does not follow you into unrelated fights', function()
    local w = setup({ fomors = { mode = 'combat', names = { 'Fomor' } } })
    w.st:target_changed(w.mob(1, 'Fomor'))
    T.eq(w.visible(), 'fomors')
    w.st:target_changed(w.mob(9, 'Crab'))
    T.eq(w.visible(), 'fomors', 'kept during the grace period')
    w.advance(state.ENCOUNTER_GRACE - 1)
    T.eq(w.visible(), 'fomors')
    w.advance(1)
    T.eq(w.visible(), nil, 'nobody fought the fomor')

    w.st:target_changed(w.mob(1, 'Fomor'))
    w.status[1] = 'fighting'
    w.st:target_changed(w.mob(9, 'Crab'))
    w.advance(60)
    T.eq(w.visible(), 'fomors', 'still fought, however long it takes')
    w.status[1] = 'alive' -- the fomor lost its claim (wipe, deaggro, someone else's fight)
    w.advance(1)
    T.eq(w.visible(), 'fomors')
    w.advance(state.ENCOUNTER_GRACE)
    T.eq(w.visible(), nil)
end)

T.test('combat mode: switching away right after a pull keeps the note', function()
    local w = setup({ fomors = { mode = 'combat', names = { 'Fomor' } } })
    w.st:target_changed(w.mob(1, 'Fomor'))
    w.st:target_changed(w.mob(50, 'Party Member'))
    w.advance(1)
    w.status[1] = 'fighting' -- the claim registers a moment later
    w.advance(1)
    w.advance(30)
    T.eq(w.visible(), 'fomors')
end)

T.test('combat mode: despawned monsters leave the encounter', function()
    local w = setup({ fomors = { mode = 'combat', names = { 'Fomor' } } })
    w.st:target_changed(w.mob(1, 'Fomor', 'fighting'))
    w.st:target_changed(nil)
    w.status[1] = 'gone'
    w.st:tick()
    T.eq(w.visible(), nil)
end)

T.test('combat mode with close_on_death = false lingers until an unrelated target', function()
    local w = setup({ boss = { mode = 'combat', names = { 'Boss' }, close_on_death = false } })
    w.st:target_changed(w.mob(1, 'Boss', 'fighting'))
    w.st:mob_died(1)
    T.eq(w.visible(), 'boss')
    w.st:tick()
    T.eq(w.visible(), 'boss', 'ticks do not end a finished encounter')
    w.st:target_changed(w.mob(2, 'Boss'))
    T.eq(w.visible(), 'boss', 'a new matching monster revives it')
    T.no(w.st.encounter.done)
    w.st:target_changed(w.mob(9, 'Crab'))
    w.advance(state.ENCOUNTER_GRACE)
    T.eq(w.visible(), nil, 'unclaimed boss and unrelated target')
end)

T.test('a target note shows over an encounter, then the encounter returns', function()
    local w = setup({
        fomors = { mode = 'combat', names = { 'Fomor' } },
        add = { names = { 'Add' } },
    })
    w.st:target_changed(w.mob(1, 'Fomor', 'fighting'))
    w.st:target_changed(w.mob(2, 'Add'))
    T.eq(w.visible(), 'add')
    w.st:target_changed(w.mob(9, 'Crab'))
    T.eq(w.visible(), 'fomors')
end)

T.test('pinned mode holds until hidden and blocks automatic notes', function()
    local w = setup({
        boss = { mode = 'pinned', names = { 'Boss' } },
        other = { names = { 'Other' } },
        fomors = { mode = 'combat', names = { 'Fomor' } },
    })
    w.st:target_changed(w.mob(1, 'Boss'))
    T.eq(w.visible(), 'boss')
    w.st:target_changed(w.mob(2, 'Other'))
    T.eq(w.visible(), 'boss', 'other notes do not replace it')
    w.st:target_changed(w.mob(3, 'Fomor', 'fighting'))
    T.eq(w.visible(), 'boss')
    T.eq(w.st:hide(), w.notes.boss)
    T.eq(w.visible(), nil, 'hide dismisses everything')
    T.eq(w.st:hide(), nil)
end)

T.test('pinned mode closes when its monster dies, not when it despawns', function()
    local w = setup({ boss = { mode = 'pinned', names = { 'Boss' } }, keep = { mode = 'pinned', names = { 'Keep' }, close_on_death = false } })
    w.st:target_changed(w.mob(1, 'Boss'))
    w.st:target_changed(nil)
    w.status[1] = 'gone'
    w.st:tick()
    T.eq(w.visible(), 'boss', 'out of range is not death')
    w.st:hide()

    w.st:target_changed(w.mob(2, 'Boss'))
    w.st:target_changed(nil)
    w.st:mob_died(2)
    T.eq(w.visible(), nil)

    w.st:target_changed(w.mob(3, 'Keep'))
    w.st:mob_died(3)
    T.eq(w.visible(), 'keep')
end)

T.test('pinned mode honours close_on_zone', function()
    local w = setup({ a = { mode = 'pinned', names = { 'A' } }, b = { mode = 'pinned', names = { 'B' }, close_on_zone = false } })
    w.st:target_changed(w.mob(1, 'A'))
    w.st:zone_changed()
    T.eq(w.visible(), nil)
    w.st:target_changed(w.mob(2, 'B'))
    w.st:zone_changed()
    T.eq(w.visible(), 'b')
    T.no(w.st:needs_tick(), 'its monsters are gone with the old zone')
end)

T.test('//nt pin overrides automatic notes and survives zoning and deaths', function()
    local w = setup({ a = { names = { 'A' } }, b = { names = { 'B' } } })
    w.st:target_changed(w.mob(1, 'A'))
    local what, note = w.st:pin()
    T.eq(what, 'pinned')
    T.eq(note.key, 'a')
    local _, slot = w.visible()
    T.eq(slot.how, 'pin')
    w.st:target_changed(w.mob(2, 'B'))
    T.eq(w.visible(), 'a', 'automatic notes wait')
    w.st:mob_died(1)
    w.st:zone_changed()
    T.eq(w.visible(), 'a')
    T.eq((w.st:pin()), 'unpinned')
    T.eq(w.visible(), nil)
end)

T.test('unpinning falls back to the target note', function()
    local w = setup({ a = { names = { 'A' } }, b = { names = { 'B' } } })
    w.st:target_changed(w.mob(1, 'A'))
    w.st:pin()
    w.st:target_changed(w.mob(2, 'B'))
    w.st:pin()
    T.eq(w.visible(), 'b')
end)

T.test('//nt pin uses the fallback note when nothing is visible', function()
    local w = setup({ a = { mode = 'manual', names = { 'A' } } })
    T.eq((w.st:pin()), nil)
    local what, note = w.st:pin(w.notes.a)
    T.eq(what, 'pinned')
    T.eq(note.key, 'a')
end)

T.test('logout closes notes, including pins, unless close_on_logout = false', function()
    local w = setup({ a = { names = { 'A' } }, b = { names = { 'B' }, close_on_logout = false } })
    w.st:target_changed(w.mob(1, 'A'))
    w.st:pin()
    w.st:logged_out()
    T.eq(w.visible(), nil)
    w.st:target_changed(w.mob(2, 'B'))
    w.st:pin()
    w.st:logged_out()
    T.eq(w.visible(), 'b')
end)

T.test('//nt show holds a note; close_on_death applies to the monster it was opened for', function()
    local w = setup({ a = { names = { 'A' } } })
    local mob = w.mob(1, 'A')
    w.st:show(w.notes.a, mob)
    w.st:target_changed(nil)
    T.eq(w.visible(), 'a')
    w.st:mob_died(1)
    T.eq(w.visible(), nil)
    w.st:show(w.notes.a)
    w.st:zone_changed()
    T.eq(w.visible(), nil, 'close_on_zone')
end)

T.test('automatic display can be toggled', function()
    local w = setup({ a = { names = { 'A' } }, boss = { mode = 'pinned', names = { 'Boss' } } })
    w.st:target_changed(w.mob(1, 'Boss'))
    w.st:set_auto(false)
    T.eq(w.visible(), nil, 'automatic pinned-mode note goes away')
    w.st:target_changed(w.mob(2, 'A'))
    T.eq(w.visible(), nil)
    w.st:show(w.notes.a)
    T.eq(w.visible(), 'a', 'explicit show still works')
    w.st:hide()
    w.st:set_auto(true)
    T.eq(w.visible(), 'a', 're-evaluates the current target')
end)

T.test('reload swaps notes by key and drops removed ones', function()
    local w = setup({ a = { names = { 'A' } }, boss = { mode = 'pinned', names = { 'Boss' } } })
    w.st:target_changed(w.mob(1, 'Boss'))
    w.st:target_changed(w.mob(2, 'A'))
    local new_boss = { key = 'boss', mode = 'pinned', close_on_death = true, close_on_zone = true, close_on_logout = true }
    local new_a = { key = 'a', mode = 'target', close_on_death = true, close_on_zone = true, close_on_logout = true, names = { 'A' } }
    w.notes.a = new_a
    w.st:reload(function(key) return ({ boss = new_boss, a = new_a })[key] end)
    T.eq(w.st:visible(), new_boss)
    w.st:reload(function(key) return ({ a = new_a })[key] end)
    T.eq(w.st:visible(), new_a, 'boss note removed; target note shows')
    w.notes.a = nil
    w.st:reload(function() return nil end)
    T.eq(w.visible(), nil)
end)

T.test('reload drops a pinned-mode hold when the note changed mode', function()
    local w = setup({ boss = { mode = 'pinned', names = { 'Boss' } } })
    w.st:target_changed(w.mob(1, 'Boss'))
    local changed = { key = 'boss', mode = 'target', close_on_death = true, close_on_zone = true, close_on_logout = true, names = { 'Boss' } }
    w.notes.boss = changed
    w.st:reload(function() return changed end)
    local _, slot = w.st:visible()
    T.eq(slot, w.st.focus, 'now shown as a target note')
end)

T.test('rapid target changes always end in the right state', function()
    local w = setup({
        a = { names = { 'A' } },
        fomors = { mode = 'combat', names = { 'Fomor' } },
        boss = { mode = 'pinned', names = { 'Boss' } },
    })
    local mobs = { w.mob(1, 'A'), w.mob(2, 'Fomor'), w.mob(3, 'Crab'), false }
    for i = 1, 500 do
        w.st:target_changed(mobs[i % 4 + 1] or nil)
    end
    T.eq(w.visible(), 'a', 'last target was A')
    w.st:target_changed(w.mob(4, 'Boss'))
    for i = 1, 500 do
        w.st:target_changed(mobs[i % 4 + 1] or nil)
    end
    T.eq(w.visible(), 'boss', 'the pinned note held throughout')
end)

T.test('needs_tick is false when nothing depends on monsters', function()
    local w = setup({ a = { names = { 'A' }, close_on_death = false } })
    T.no(w.st:needs_tick())
    w.st:target_changed(w.mob(1, 'A'))
    T.no(w.st:needs_tick())
    w.st:pin()
    T.no(w.st:needs_tick())
end)
