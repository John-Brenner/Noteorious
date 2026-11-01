--[[
    Noteorious - core/matcher.lua

    Finds the single note for a monster, identified by (zone id, name).
    Entity ids are never used: every spawn of "Fafnir" in Dragon's Aery
    gets the same note.

    Precedence (first difference wins, so the result is always deterministic):
      1. How the name matched:
           tier 1  match.name        exact name
           tier 2  match.names       name listed in a group
           tier 3  match.name_prefix name starts with the prefix
      2. Zone specificity: a note for one zone beats a note for several
         zones, which beats a note for any zone ("*").
      3. For prefixes: the longer matching prefix wins.
      4. Alphabetical order of the note keys.

    Names are compared case-insensitively. Each note carries a `rule` built
    by core/library.lua:
      rule.zones      set of zone ids, or nil for any zone
      rule.zone_count number of zones (math.huge for any zone)
      rule.name       lowercased exact name, or nil
      rule.names      set of lowercased names, or nil
      rule.prefixes   lowercased prefixes, longest first, or nil
]]

local util = require('core/util')

local matcher = {}

local Matcher = {}
Matcher.__index = Matcher

local TIER_WORDS = { 'name', 'name in a names list', 'name prefix' }

-- Returns tier, prefix_length when `rule` matches the lowercased name.
function matcher.tier(rule, lname)
    if rule.name and rule.name == lname then
        return 1, 0
    end
    if rule.names and rule.names[lname] then
        return 2, 0
    end
    if rule.prefixes then
        for _, p in ipairs(rule.prefixes) do
            if lname:sub(1, #p) == p then
                return 3, #p
            end
        end
    end
    return nil
end

-- Sort order for candidates; see the precedence list above.
function matcher.before(a, b)
    if a.tier ~= b.tier then
        return a.tier < b.tier
    end
    if a.zone_count ~= b.zone_count then
        return a.zone_count < b.zone_count
    end
    if a.prefix_len ~= b.prefix_len then
        return a.prefix_len > b.prefix_len
    end
    return a.note.key < b.note.key
end

function matcher.new(notes)
    local self = setmetatable({ notes = {}, cache = {} }, Matcher)
    for _, note in ipairs(notes) do
        if note.rule then
            self.notes[#self.notes + 1] = note
        end
    end
    return self
end

-- Every note that matches, best first. Useful for diagnostics and tests.
function Matcher:candidates(zone, name)
    local lname = util.trim(name):lower()
    local out = {}
    for _, note in ipairs(self.notes) do
        local rule = note.rule
        if rule.zones == nil or rule.zones[zone] then
            local tier, prefix_len = matcher.tier(rule, lname)
            if tier then
                out[#out + 1] = {
                    note = note, tier = tier, prefix_len = prefix_len, zone_count = rule.zone_count,
                }
            end
        end
    end
    table.sort(out, matcher.before)
    return out
end

-- The best note for a monster: returns note, tier (or nil). Results are cached
-- until clear() is called, so rapid target switching costs a table lookup.
function Matcher:find(zone, name)
    if type(zone) ~= 'number' or type(name) ~= 'string' or name == '' then
        return nil
    end
    local key = zone .. '\0' .. name
    local hit = self.cache[key]
    if hit == nil then
        local best = self:candidates(zone, name)[1]
        hit = best and { best.note, best.tier } or false
        self.cache[key] = hit
    end
    if hit then
        return hit[1], hit[2]
    end
    return nil
end

function Matcher:clear()
    self.cache = {}
end

local function zones_overlap(a, b)
    if a == nil or b == nil then
        return true
    end
    for zone in pairs(a) do
        if b[zone] then
            return true
        end
    end
    return false
end

-- Warnings for pairs of notes whose precedence is decided only by key order:
-- same tier, same matching text, same zone specificity, overlapping zones.
-- Deliberate overrides (an exact note beating a group, a single-zone note
-- beating a multi-zone one) are not reported.
function matcher.conflicts(notes)
    local groups, order = {}, {}
    local function add(tier, term, note)
        local id = tier .. '|' .. term
        local group = groups[id]
        if not group then
            group = { tier = tier, term = term, notes = {} }
            groups[id] = group
            order[#order + 1] = id
        end
        group.notes[#group.notes + 1] = note
    end
    for _, note in ipairs(notes) do
        local rule = note.rule
        if rule then
            if rule.name then
                add(1, rule.name, note)
            end
            for name in pairs(rule.names or {}) do
                add(2, name, note)
            end
            for _, prefix in ipairs(rule.prefixes or {}) do
                add(3, prefix, note)
            end
        end
    end

    table.sort(order)
    local warnings = {}
    for _, id in ipairs(order) do
        local group = groups[id]
        local list = group.notes
        table.sort(list, function(a, b) return a.key < b.key end)
        for i = 1, #list - 1 do
            for j = i + 1, #list do
                local a, b = list[i], list[j]
                if a.rule.zone_count == b.rule.zone_count and zones_overlap(a.rule.zones, b.rule.zones) then
                    warnings[#warnings + 1] = ('notes \'%s\' and \'%s\' both match %s "%s" in the same zone; \'%s\' wins (alphabetical order)')
                        :format(a.key, b.key, TIER_WORDS[group.tier], group.term, a.key)
                end
            end
        end
    end
    return warnings
end

return matcher
