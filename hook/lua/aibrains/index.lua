local RedQueenBrainReference = {
    "/mods/TheRedQueen/lua/AI/RedQueenBrain.lua",
    "AIBrain",
}

keyToBrain.redqueen = RedQueenBrainReference

-- Direct `/map` launches create Rush opponents before UI hooks are mounted.
-- The smoke runner carries an out-of-range skirmish difficulty sentinel into
-- the simulation. Lobby difficulty values never use 42.
local RedQueenSmoke = ScenarioInfo.Options.Difficulty
if RedQueenSmoke == 42 or RedQueenSmoke == "42" then
    keyToBrain.rush = RedQueenBrainReference
end

-- Start position of an army, from the scenario's own Blank Marker.
local function RedQueenStartPosition(name)
    local ok, utilities = pcall(import, "/lua/sim/ScenarioUtilities.lua")
    if not ok or not utilities or not utilities.GetMarker then
        return nil
    end
    local found, marker = pcall(utilities.GetMarker, name)
    if not found or not marker then
        return nil
    end
    return marker.position or marker.Position
end

local RedQueenTeamLayout = import("/mods/TheRedQueen/lua/AI/RedQueen/TeamLayout.lua")
local function RedQueenProximityTeams(names, teamCount, teamSize)
    return RedQueenTeamLayout.ProximityTeams(names, teamCount, teamSize, RedQueenStartPosition)
end

-- Opt-in mixed match: the first AI start becomes Red Queen, the second FAF's
-- stock Adaptive brain.
--
-- Every start that is not one of those two is marked civilian.
-- MatchContext.IsActiveArmy skips civilians, so the launching player and any
-- surplus start no longer inflate the enemy count. Without this a four-start
-- map reported allies=1 enemies=3 deficit=2 income=1.20, handing Red Queen a
-- twenty percent income handicap its opponent did not get and making the
-- comparison something other than the 1v1 it claimed to be.
--
-- Sentinel 43 enables bounded tracing for 1v1; 46 does the same for 2v2.
-- Team assignment is consumed by native BeginSessionTeams after brain creation.
local function RedQueenMixedMatch(withTrace, redQueenCount)
    if withTrace then
        ScenarioInfo.Options.RedQueenProductionTrace = true
    end
    local names = {}
    for name, setup in pairs(ScenarioInfo.ArmySetup) do
        if not setup.Human and not setup.Civilian then table.insert(names, name) end
    end
    table.sort(names)
    redQueenCount = redQueenCount or 1
    local contestants = {}

    -- A symmetric team match has the same geometry problem as a layout: slot
    -- order is not team order. Crossfire Canal numbers its six starts
    -- interleaved, so pairing the first four sequentially puts allies 594 apart
    -- on a 1024 map while each army's nearest neighbour, about 300 away, is an
    -- enemy. Group by proximity instead once there are teams to get wrong.
    --
    -- The one-against-one path is deliberately left exactly as it was: it has
    -- no pairing to decide, and it is the configuration every recorded 1v1
    -- result was measured on.
    if redQueenCount > 1 then
        local grouped = RedQueenProximityTeams(names, 2, redQueenCount)
        for index, team in ipairs(grouped) do
            for _, name in ipairs(team) do
                local setup = ScenarioInfo.ArmySetup[name]
                setup.AIPersonality = index == 1 and "redqueen" or "adaptive"
                setup.Team = 1 + index
                contestants[name] = true
            end
        end
        for _, name in ipairs(names) do
            if not contestants[name] then
                ScenarioInfo.ArmySetup[name].AIPersonality = ""
            end
        end
    else
        for index, name in ipairs(names) do
            local setup = ScenarioInfo.ArmySetup[name]
            if index <= redQueenCount then
                setup.AIPersonality = "redqueen"
                setup.Team = 2
                contestants[name] = true
            elseif index <= redQueenCount * 2 then
                setup.AIPersonality = "adaptive"
                setup.Team = 3
                contestants[name] = true
            else
                setup.AIPersonality = ""
            end
        end
    end
    if redQueenCount > 1 then
        ScenarioInfo.Options.TeamLock = "locked"
    end
    for name, setup in pairs(ScenarioInfo.ArmySetup) do
        if not contestants[name] then
            setup.Civilian = true
        end
    end
    -- Brains created before this import ran already copied their flag.
    for _, brain in pairs(ArmyBrains or {}) do
        local setup = brain.Name and ScenarioInfo.ArmySetup[brain.Name]
        if setup and setup.Civilian then brain.Civilian = true end
    end
end

-- Team layouts for long matches with ordinary allies and opponents.
--
-- RedQueenMixedMatch above is a symmetric contest: N Red Queen against N
-- Adaptive. That answers "is this brain better than the stock one", which is
-- not the same question as "does it play well on a team". Here exactly one army
-- is Red Queen and every other contestant is FAF's stock Adaptive brain, so the
-- match measures Red Queen cooperating with ordinary allies and fighting
-- ordinary opponents.
--
-- Teams are numbered from 2 because team 1 belongs to the launching player, who
-- is civilian in these runs. A surplus start beyond the layout is marked
-- civilian so it cannot inflate the enemy count and hand out an income
-- multiplier the opponents did not get.
--
-- The layout needs teamCount * teamSize AI starts, and the launching player
-- consumes one slot, so a 3v3 or a 2v2v2 needs a seven-start map. This is why
-- the old 2v2 sentinel produced a 2v1 on a four-start map.
local function RedQueenTeamMatch(teamCount, teamSize)
    local names = {}
    for name, setup in pairs(ScenarioInfo.ArmySetup) do
        if not setup.Human and not setup.Civilian then table.insert(names, name) end
    end
    table.sort(names)
    local contestants = {}
    local grouped = RedQueenProximityTeams(names, teamCount, teamSize)
    local first = true
    for index, team in ipairs(grouped) do
        for _, name in ipairs(team) do
            local setup = ScenarioInfo.ArmySetup[name]
            setup.Team = 1 + index
            -- Red Queen takes one slot on the first team; every other
            -- contestant is FAF's stock brain.
            setup.AIPersonality = first and "redqueen" or "adaptive"
            first = false
            contestants[name] = true
        end
    end
    for _, name in ipairs(names) do
        if not contestants[name] then
            ScenarioInfo.ArmySetup[name].AIPersonality = ""
        end
    end
    ScenarioInfo.Options.TeamLock = "locked"
    for name, setup in pairs(ScenarioInfo.ArmySetup) do
        if not contestants[name] then
            setup.Civilian = true
        end
    end
    for _, brain in pairs(ArmyBrains or {}) do
        local setup = brain.Name and ScenarioInfo.ArmySetup[brain.Name]
        if setup and setup.Civilian then brain.Civilian = true end
    end
end

if RedQueenSmoke == 43 or RedQueenSmoke == "43" then
    RedQueenMixedMatch(true, 1)
elseif RedQueenSmoke == 44 or RedQueenSmoke == "44" then
    RedQueenMixedMatch(false, 1)
elseif RedQueenSmoke == 45 or RedQueenSmoke == "45" then
    RedQueenMixedMatch(false, 2)
elseif RedQueenSmoke == 46 or RedQueenSmoke == "46" then
    RedQueenMixedMatch(true, 2)
elseif RedQueenSmoke == 47 or RedQueenSmoke == "47" then
    RedQueenMixedMatch(true, 1)
    ScenarioInfo.Options.RedQueenLifecycleFixture = true
elseif RedQueenSmoke == 48 or RedQueenSmoke == "48" then
    RedQueenMixedMatch(true, 1)
    ScenarioInfo.Options.RedQueenDefenseFixture = true
elseif RedQueenSmoke == 49 or RedQueenSmoke == "49" then
    RedQueenTeamMatch(2, 3)
elseif RedQueenSmoke == 50 or RedQueenSmoke == "50" then
    RedQueenTeamMatch(3, 2)
end
