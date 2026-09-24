local function RedQueenSeparation(left, right)
    if not left or not right then
        return nil
    end
    local dx = left[1] - right[1]
    local dz = left[3] - right[3]
    return dx * dx + dz * dz
end

-- Group contestants into teams by how close their starts actually are.
--
-- Slot order is not team order. Saltrock Colony numbers its six starts
-- interleaved, so pairing them sequentially puts each army's *nearest*
-- neighbour on the opposing team: allies land roughly 285 apart on a 512 map
-- while enemies sit about 100 apart. That is not a 2v2v2, it is three duels
-- with the partners exiled, and it silently misdescribes every team result
-- measured on such a map.
--
-- Grown by single linkage from a deterministic seed -- the lexicographically
-- first unassigned army -- and each further member is the nearest unassigned
-- army to anything already in the team, so a team is a genuine cluster rather
-- than a radius around one slot. Ties fall to the earlier name because
-- `remaining` stays sorted, which keeps the simulation deterministic.
--
-- With no usable marker positions this falls back to declaration order, which
-- is the previous behaviour rather than an error.
function ProximityTeams(names, teamCount, teamSize, getPosition)
    local positions = {}
    local located = 0
    for _, name in ipairs(names) do
        positions[name] = getPosition(name)
        if positions[name] then located = located + 1 end
    end

    local teams = {}
    if located < teamCount * teamSize then
        for index = 1, math.min(table.getn(names), teamCount * teamSize) do
            local team = 1 + math.floor((index - 1) / teamSize)
            teams[team] = teams[team] or {}
            table.insert(teams[team], names[index])
        end
        return teams
    end

    local remaining = {}
    for _, name in ipairs(names) do table.insert(remaining, name) end
    while table.getn(teams) < teamCount and table.getn(remaining) > 0 do
        local team = { table.remove(remaining, 1) }
        while table.getn(team) < teamSize and table.getn(remaining) > 0 do
            local bestIndex, bestDistance = 1, nil
            for index, candidate in ipairs(remaining) do
                for _, member in ipairs(team) do
                    local distance = RedQueenSeparation(positions[candidate], positions[member])
                    if distance and (not bestDistance or distance < bestDistance) then
                        bestIndex, bestDistance = index, distance
                    end
                end
            end
            table.insert(team, table.remove(remaining, bestIndex))
        end
        table.insert(teams, team)
    end
    return teams
end

