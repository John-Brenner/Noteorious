local T = require('tests/harness')
local matcher = require('core/matcher')

-- Builds a note with a hand-written rule.
local function note(key, zones, how)
    local rule = { zone_count = zones and 0 or math.huge }
    if zones then
        rule.zones = {}
        for _, z in ipairs(zones) do
            rule.zones[z] = true
            rule.zone_count = rule.zone_count + 1
        end
    end
    if how.name then
        rule.name = how.name:lower()
    end
    if how.names then
        rule.names = {}
        for _, n in ipairs(how.names) do
            rule.names[n:lower()] = true
        end
    end
    if how.prefixes then
        rule.prefixes = {}
        for i, p in ipairs(how.prefixes) do
            rule.prefixes[i] = p:lower()
        end
        table.sort(rule.prefixes, function(a, b) return #a > #b end)
    end
    return { key = key, rule = rule }
end

local function best(m, zone, name)
    local n = m:find(zone, name)
    return n and n.key
end

T.test('exact name beats names list beats prefix (spec example)', function()
    local m = matcher.new({
        note('sortie_fomors', { 133 }, { prefixes = { 'Demisang ' } }),
        note('fomor_list', { 133 }, { names = { 'Demisang Deleterious', 'Demisang Hoodoo' } }),
        note('demisang_deleterious', { 133 }, { name = 'Demisang Deleterious' }),
    })
    T.eq(best(m, 133, 'Demisang Deleterious'), 'demisang_deleterious')
    T.eq(best(m, 133, 'Demisang Hoodoo'), 'fomor_list')
    T.eq(best(m, 133, 'Demisang Whatever'), 'sortie_fomors')
    local _, tier = m:find(133, 'Demisang Whatever')
    T.eq(tier, 3)
end)

T.test('zone scoping: notes only match in their zones', function()
    local m = matcher.new({ note('sortie_fomors', { 133, 189, 275 }, { prefixes = { 'Demisang ' } }) })
    T.eq(best(m, 189, 'Demisang Hoodoo'), 'sortie_fomors')
    T.eq(best(m, 154, 'Demisang Hoodoo'), nil, 'unrelated zone')
    T.eq(best(m, 133, 'Fomor Hoodoo'), nil, 'unrelated name')
end)

T.test('prefixes keep their trailing space', function()
    local m = matcher.new({ note('demi', { 1 }, { prefixes = { 'Demisang ' } }) })
    T.eq(best(m, 1, 'Demisangs'), nil)
    T.eq(best(m, 1, 'Demisang X'), 'demi')
end)

T.test('within a tier: one zone beats several zones beats any zone', function()
    local m = matcher.new({
        note('anywhere', nil, { name = 'Fafnir' }),
        note('two_zones', { 154, 128 }, { name = 'Fafnir' }),
        note('aery_only', { 154 }, { name = 'Fafnir' }),
    })
    T.eq(best(m, 154, 'Fafnir'), 'aery_only')
    T.eq(best(m, 128, 'Fafnir'), 'two_zones')
    T.eq(best(m, 5, 'Fafnir'), 'anywhere')
end)

T.test('longer prefix wins, then alphabetical key order', function()
    local m = matcher.new({
        note('short', { 1 }, { prefixes = { 'Tonberry ' } }),
        note('long', { 1 }, { prefixes = { 'Tonberry Ha' } }),
        note('b_same', { 2 }, { name = 'Crab' }),
        note('a_same', { 2 }, { name = 'Crab' }),
    })
    T.eq(best(m, 1, 'Tonberry Hacker'), 'long')
    T.eq(best(m, 1, 'Tonberry Cutter'), 'short')
    T.eq(best(m, 2, 'Crab'), 'a_same')
end)

T.test('matching is case-insensitive and ignores surrounding spaces', function()
    local m = matcher.new({ note('fafnir', { 154 }, { name = 'Fafnir' }) })
    T.eq(best(m, 154, 'FAFNIR'), 'fafnir')
    T.eq(best(m, 154, ' fafnir '), 'fafnir')
end)

T.test('special characters in names are matched literally', function()
    local m = matcher.new({
        note('effigy', { 1 }, { name = "Gu'Dha Effigy" }),
        note('pct', { 1 }, { prefixes = { '100% (' } }),
        note('mammet', { 1 }, { names = { 'Mammet-22 Zeta' } }),
    })
    T.eq(best(m, 1, "Gu'Dha Effigy"), 'effigy')
    T.eq(best(m, 1, '100% (real)'), 'pct')
    T.eq(best(m, 1, 'Mammet-22 Zeta'), 'mammet')
    T.eq(best(m, 1, 'Mammet-22 Zet'), nil)
end)

T.test('find caches results until clear()', function()
    local n = note('fafnir', { 154 }, { name = 'Fafnir' })
    local m = matcher.new({ n })
    T.eq(best(m, 154, 'Fafnir'), 'fafnir')
    n.rule.name = 'other'
    T.eq(best(m, 154, 'Fafnir'), 'fafnir', 'cached')
    m:clear()
    T.eq(best(m, 154, 'Fafnir'), nil, 'recomputed')
end)

T.test('find rejects missing input', function()
    local m = matcher.new({ note('fafnir', { 154 }, { name = 'Fafnir' }) })
    T.eq(m:find(nil, 'Fafnir'), nil)
    T.eq(m:find(154, ''), nil)
    T.eq(m:find(154, nil), nil)
end)

T.test('notes without a rule (manual notes) never match', function()
    local m = matcher.new({ { key = 'manual' } })
    T.eq(#m.notes, 0)
end)

T.test('conflicts reports only ties decided by key order', function()
    local warnings = matcher.conflicts({
        note('a_same', { 2 }, { name = 'Crab' }),
        note('b_same', { 2, 3 }, { name = 'Crab' }),   -- different zone count: deliberate, no warning
        note('c_same', { 2 }, { name = 'Crab' }),      -- ties with a_same
        note('d_any', nil, { name = 'Crab' }),
        note('group', { 2 }, { names = { 'Crab' } }),   -- different tier: no warning
        note('p1', { 4 }, { prefixes = { 'Ton ' } }),
        note('p2', { 4 }, { prefixes = { 'Ton ' } }),
        note('p3', { 5 }, { prefixes = { 'Ton ' } }),   -- different zone: no warning
    })
    T.eq(#warnings, 2)
    T.any(warnings, "'a_same' and 'c_same'")
    T.any(warnings, "'p1' and 'p2'")
end)
