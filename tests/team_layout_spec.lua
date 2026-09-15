-- Contracts for the match layouts in hook/lua/aibrains/index.lua.
--
-- These are pure table manipulation over ScenarioInfo, and they are worth
-- testing because the failure mode is silent: the old 2v2 sentinel produced a
-- 2v1 on a four-start map -- the launching player consumed a slot, leaving three
-- AI starts for a layout that needed four -- and every result labelled 2v2 for
-- weeks was actually 2v1. Nothing in the log said so.

-- Start positions drive team assignment, so the fixture must supply them.
-- Slot order is deliberately NOT team order here: these are Saltrock Colony's
-- real six starts, whose numbering is interleaved.
local saltrock = {
    ARMY_1 = { 114.5, 19, 313.5 },
    ARMY_2 = { 398.5, 19, 314.5 },
    ARMY_3 = { 304.5, 19, 147.5 },
    ARMY_4 = { 167.5, 19, 400.5 },
    ARMY_5 = { 350.5, 19, 406.5 },
    ARMY_6 = { 203.5, 19, 153.5 },
}
local markers = {}

function import(path)
    if path == "/lua/sim/ScenarioUtilities.lua" then
        return {
            GetMarker = function(name)
                local position = markers[name]
                return position and { position = position } or nil
            end,
        }
    end
    if path == "/mods/TheRedQueen/lua/AI/RedQueen/TeamLayout.lua" then
        local env = setmetatable({}, { __index = _G })
        setfenv(assert(loadfile("lua/AI/RedQueen/TeamLayout.lua")), env)()
        return env
    end
    error("unexpected import: " .. tostring(path))
end

local function scenario(startCount, difficulty, positions, humanSlots)
    local setup = {}
    for index = 1, startCount do
        setup["ARMY_" .. index] = {
            Human = humanSlots ~= false and index == 1,
            Civilian = false,
            AIPersonality = "rush",
        }
    end
    markers = positions or {}
    ScenarioInfo = { ArmySetup = setup, Options = { Difficulty = difficulty } }
    ArmyBrains = {}
    keyToBrain = {}
    dofile("hook/lua/aibrains/index.lua")
    return setup
end

local function summarise(setup)
    local byTeam, redQueen, adaptive, civilian = {}, {}, 0, 0
    for name, army in pairs(setup) do
        if army.Human then
            -- the launching player
        elseif army.Civilian then
            civilian = civilian + 1
        elseif army.AIPersonality == "redqueen" then
            table.insert(redQueen, name)
            byTeam[army.Team] = (byTeam[army.Team] or 0) + 1
        elseif army.AIPersonality == "adaptive" then
            adaptive = adaptive + 1
            byTeam[army.Team] = (byTeam[army.Team] or 0) + 1
        end
    end
    return byTeam, redQueen, adaptive, civilian
end

-- 3v3 on an eight-start map: six contestants in two teams of three, one Red
-- Queen among stock allies, and the surplus start neutralised.
local setup = scenario(8, 49)
local byTeam, redQueen, adaptive, civilian = summarise(setup)
assert(table.getn(redQueen) == 1, "a team layout must field exactly one Red Queen army")
assert(adaptive == 5, "every other contestant must be FAF's stock Adaptive brain, got " .. adaptive)
local teams = 0
for team, count in pairs(byTeam) do
    teams = teams + 1
    assert(count == 3, "each 3v3 team must hold three armies, team " .. team .. " had " .. count)
end
assert(teams == 2, "a 3v3 has two teams, found " .. teams)
assert(civilian == 1, "the start left over after the layout must be civilian")
assert(ScenarioInfo.Options.TeamLock == "locked", "teams must be locked so the layout holds")

-- Red Queen must have a real ally, which is the whole point of a team layout:
-- the symmetric 1v1 sentinel cannot show whether it cooperates.
local redQueenTeam = setup[redQueen[1]].Team
local allies = 0
for name, army in pairs(setup) do
    if not army.Human and not army.Civilian and army.Team == redQueenTeam and name ~= redQueen[1] then
        allies = allies + 1
        assert(army.AIPersonality == "adaptive", "allies must be ordinary AIs, not mirrors")
    end
end
assert(allies == 2, "Red Queen must have two stock allies in a 3v3, got " .. allies)

-- 2v2v2: three teams of two. Two opposing teams is the case a two-sided layout
-- cannot produce, and it is where target selection has to choose between them.
setup = scenario(8, 50)
byTeam, redQueen, adaptive, civilian = summarise(setup)
assert(table.getn(redQueen) == 1, "2v2v2 must field exactly one Red Queen army")
assert(adaptive == 5, "2v2v2 must field five stock armies, got " .. adaptive)
teams = 0
for team, count in pairs(byTeam) do
    teams = teams + 1
    assert(count == 2, "each 2v2v2 team must hold two armies, team " .. team .. " had " .. count)
end
assert(teams == 3, "a 2v2v2 has three teams, found " .. teams)
assert(civilian == 1, "the surplus start must be civilian")

-- Team numbers must be distinct and start above the launching player's team 1.
local seen = {}
for _, army in pairs(setup) do
    if not army.Human and not army.Civilian then
        assert(army.Team and army.Team >= 2, "contestant teams must not collide with the player's team 1")
        seen[army.Team] = true
    end
end

-- A map with too few starts must not silently produce a smaller match. This is
-- the 2v1 defect: the layout should be recognisable as short from the setup.
setup = scenario(4, 50)
byTeam, redQueen, adaptive, civilian = summarise(setup)
local contestants = table.getn(redQueen) + adaptive
assert(contestants == 3,
    "a four-start map has only three AI starts, so a 2v2v2 cannot be complete: " ..
    "callers must use a seven-start map or larger")
assert(contestants < 6, "an incomplete layout must be detectable by counting contestants")

print("Red Queen team layout contracts passed")

-- Teams follow the map, not the slot numbering.
--
-- Saltrock Colony numbers its six starts interleaved. Pairing them
-- sequentially puts every army's nearest neighbour on the opposing team:
-- allies about 285 apart on a 512 map, enemies about 100 apart. The intended
-- pairs are (1,4), (2,5) and (3,6), each roughly 100 apart.
local function separation(a, b)
    local dx, dz = a[1] - b[1], a[3] - b[3]
    return math.sqrt(dx * dx + dz * dz)
end

local placed = scenario(6, 50, saltrock, false)
local byTeam = {}
for name, army in pairs(placed) do
    if not army.Civilian and army.AIPersonality ~= "" then
        byTeam[army.Team] = byTeam[army.Team] or {}
        table.insert(byTeam[army.Team], name)
    end
end
local teamCount = 0
for team, members in pairs(byTeam) do
    teamCount = teamCount + 1
    assert(table.getn(members) == 2,
        "a 2v2v2 team must hold two armies, team " .. team .. " had " .. table.getn(members))
    table.sort(members)
    local apart = separation(saltrock[members[1]], saltrock[members[2]])
    assert(apart < 150,
        "allies must start near each other, " .. members[1] .. "+" .. members[2]
            .. " were " .. string.format("%.0f", apart) .. " apart")
end
assert(teamCount == 3, "with no human slot a six-start map must seat a full 2v2v2, got " .. teamCount)

-- And every army's nearest neighbour must now be its ally, which is the exact
-- property sequential pairing inverted.
for name, army in pairs(placed) do
    if army.AIPersonality ~= "" then
        local nearest, nearestDistance = nil, nil
        for other in pairs(saltrock) do
            if other ~= name then
                local distance = separation(saltrock[name], saltrock[other])
                if not nearestDistance or distance < nearestDistance then
                    nearest, nearestDistance = other, distance
                end
            end
        end
        assert(placed[nearest].Team == army.Team,
            name .. "'s nearest neighbour " .. nearest .. " must be an ally, not an enemy")
    end
end

-- Exactly one Red Queen among stock allies, as before.
local redQueen = 0
for _, army in pairs(placed) do
    if army.AIPersonality == "redqueen" then redQueen = redQueen + 1 end
end
assert(redQueen == 1, "a team layout must field exactly one Red Queen army")

-- A team of three must be grown by single linkage, not by distance from the
-- seed alone. Here ARMY_3 sits 50 from ARMY_2 but 150 from the seed, while
-- ARMY_4 sits 120 from the seed and 156 from ARMY_2. Measuring only from the
-- seed takes ARMY_4 and splits the real cluster; measuring from the nearest
-- member takes ARMY_3, which is the cluster.
local chain = {
    ARMY_1 = { 0, 19, 0 },
    ARMY_2 = { 0, 19, 100 },
    ARMY_3 = { 0, 19, 150 },
    ARMY_4 = { 120, 19, 0 },
    ARMY_5 = { 1000, 19, 1000 },
    ARMY_6 = { 1010, 19, 1000 },
}
local linked = scenario(6, 49, chain, false)
assert(linked.ARMY_1.Team == linked.ARMY_2.Team,
    "the seed must team with its nearest neighbour")
assert(linked.ARMY_3.Team == linked.ARMY_1.Team,
    "the third member must be the one nearest an existing member, not the seed")
assert(linked.ARMY_4.Team ~= linked.ARMY_1.Team,
    "a candidate closer to the seed but far from the cluster must not join it")

-- Without marker positions the assignment must degrade to declaration order
-- rather than failing.
local blind = scenario(8, 49, nil, true)
local blindTeams = {}
for _, army in pairs(blind) do
    if not army.Human and not army.Civilian and army.AIPersonality ~= "" then
        blindTeams[army.Team] = (blindTeams[army.Team] or 0) + 1
    end
end
local blindCount = 0
for _, size in pairs(blindTeams) do
    blindCount = blindCount + 1
    assert(size == 3, "a 3v3 must still form teams of three without marker positions")
end
assert(blindCount == 2, "missing positions must fall back to two teams, not to nothing")

print("Red Queen proximity team contracts passed")

-- A symmetric 2v2 must respect the map too. Crossfire Canal's six starts are
-- interleaved: pairing the first four sequentially puts allies 594 apart on a
-- 1024 map while each nearest neighbour, about 300 away, is an enemy.
local crossfire = {
    ARMY_1 = { 368.5, 19, 770.5 },
    ARMY_2 = { 657.5, 19, 251.5 },
    ARMY_3 = { 808.5, 19, 505.5 },
    ARMY_4 = { 212.5, 19, 513.5 },
    ARMY_5 = { 357.5, 19, 255.5 },
    ARMY_6 = { 664.5, 19, 761.5 },
}
local mixed2v2 = scenario(6, 45, crossfire, false)
local sides = {}
for name, army in pairs(mixed2v2) do
    if army.AIPersonality == "redqueen" or army.AIPersonality == "adaptive" then
        sides[army.Team] = sides[army.Team] or {}
        table.insert(sides[army.Team], name)
    end
end
local sideCount = 0
for team, members in pairs(sides) do
    sideCount = sideCount + 1
    assert(table.getn(members) == 2,
        "a 2v2 side must hold two armies, team " .. team .. " had " .. table.getn(members))
    table.sort(members)
    local apart = separation(crossfire[members[1]], crossfire[members[2]])
    assert(apart < 400,
        "2v2 allies must start near each other, " .. members[1] .. "+" .. members[2]
            .. " were " .. string.format("%.0f", apart) .. " apart")
end
assert(sideCount == 2, "a 2v2 has two sides, found " .. sideCount)

-- Both Red Queen armies must be on one side, and it must be a real pair.
local redQueenSide, redQueenArmies = nil, 0
for _, army in pairs(mixed2v2) do
    if army.AIPersonality == "redqueen" then
        redQueenArmies = redQueenArmies + 1
        assert(redQueenSide == nil or redQueenSide == army.Team,
            "both Red Queen armies must share a team")
        redQueenSide = army.Team
    end
end
assert(redQueenArmies == 2, "a 2v2 must field two Red Queen armies, got " .. redQueenArmies)

-- The one-against-one path must be untouched: first two sorted names, teams 2
-- and 3, whatever the geometry says.
local duel = scenario(6, 44, crossfire, false)
assert(duel.ARMY_1.AIPersonality == "redqueen" and duel.ARMY_1.Team == 2,
    "a 1v1 must still put Red Queen on the first sorted army")
assert(duel.ARMY_2.AIPersonality == "adaptive" and duel.ARMY_2.Team == 3,
    "a 1v1 must still take its opponent by slot order, not proximity")
for index = 3, 6 do
    assert(duel["ARMY_" .. index].AIPersonality == "",
        "a 1v1 must leave every other start out of the contest")
end

print("Red Queen symmetric-pairing contracts passed")
