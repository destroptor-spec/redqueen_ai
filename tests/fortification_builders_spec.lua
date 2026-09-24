local categoryMetatable = {}
local function CombineCategories(left, right)
    local result = { Keys = {} }
    for key, present in pairs(left.Keys or {}) do result.Keys[key] = present end
    for key, present in pairs(right.Keys or {}) do result.Keys[key] = present end
    return setmetatable(result, categoryMetatable)
end
categoryMetatable.__mul = CombineCategories
categoryMetatable.__add = CombineCategories
categoryMetatable.__sub = CombineCategories

categories = setmetatable({}, {
    __index = function(value, key)
        local category = setmetatable({ Keys = { [key] = true } }, categoryMetatable)
        rawset(value, key, category)
        return category
    end,
})

local builders = {}
local groups = {}

function Builder(definition)
    builders[definition.BuilderName] = definition
    return definition
end

function BuilderGroup(definition)
    groups[definition.BuilderGroupName] = definition
    return definition
end

function import(path)
    -- The radius floor is shared with DefenseCoverage so the measurement cannot
    -- drift from the extent the builder actually uses.
    if path == "/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua" then
        return { Policy = { FortificationMinimumRadius = 40, StandingAntiAirPerBase = 6 } }
    end
    return path
end

dofile("lua/AI/RedQueen/FortificationBuilders.lua")

assert(groups.RedQueenEmergencyFortificationBuilders, "emergency fortification group must register")

local factionIndex = 1
local engineerCounts = {
    MAIN = { [1] = 0, [2] = 0, [3] = 1 },
    EXPANSION = { [1] = 0, [2] = 1, [3] = 0 },
}
local function EngineerManager(locationType, position)
    return {
        Radius = 80,
        GetLocationCoords = function() return position end,
        GetNumCategoryUnits = function(_, unitType, category)
            assert(unitType == "Engineers", "fortification checks must query the local engineer roster")
            if category.Keys.TECH3 then
                return engineerCounts[locationType][3]
            end
            if category.Keys.TECH2 then
                return engineerCounts[locationType][2]
            end
            if category.Keys.TECH1 then
                return engineerCounts[locationType][1]
            end
            return 0
        end,
    }
end
local brain = {
    RedQueenModules = {
        Strategy = {
            ProductionDemand = {
                DefenseAlert = {
                    Active = true,
                    AnchorPosition = { 0, 0, 0 },
                    Targets = {
                        Ground = 8,
                        AntiAir = 4,
                        Shields = 2,
                        StrategicMissileDefense = 1,
                        TacticalMissiles = 2,
                    },
                },
            },
        },
        Economy = { State = { StallRisk = true } },
    },
    BuilderManagers = {
        MAIN = {
            EngineerManager = EngineerManager("MAIN", { 0, 0, 0 }),
        },
        EXPANSION = {
            EngineerManager = EngineerManager("EXPANSION", { 200, 0, 200 }),
        },
    },
    GetNumUnitsAroundPoint = function() return 0 end,
    GetFactionIndex = function() return factionIndex end,
}

local sentry = builders["Red Queen Emergency T3 Sentry"]
assert(sentry.BuilderConditions[1][1](brain, "MAIN"), "UEF must prefer T3 sentries during a massive-army alert")
assert(sentry.BuilderData.Construction.BuildStructures[1] == "T3GroundDefense", "UEF sentry must use T3 point defense")

factionIndex = 3
local cybranDefense = builders["Red Queen Emergency T2 Point Defense T3 Engineer"]
assert(cybranDefense.BuilderConditions[1][1](brain, "MAIN"), "non-UEF T3 engineers must build T2 point defense")
assert(cybranDefense.BuilderData.Construction.BuildStructures[1] == "T2GroundDefense", "non-UEF fallback must use T2 point defense")

local smd = builders["Red Queen Emergency Strategic Missile Defense"]
local tml = builders["Red Queen Emergency Tactical Missile T3 Engineer"]
assert(smd.BuilderConditions[1][1](brain, "MAIN"), "mature emergency bases must request strategic missile defense")
assert(tml.BuilderConditions[1][1](brain, "MAIN"), "mature emergency bases must request tactical missiles")

-- Anti-air is standing infrastructure, not a reaction. With no alert at all, a
-- base must still request it, while every other role stays silent.
--
-- Across eighteen mirror cells only 12% of active alerts qualified on air
-- against 63% on surface, so an alert-keyed anti-air target is zero for most of
-- a match and cannot accumulate between raids -- 3.8 SAM beside 17.9 point
-- defences, and one air experimental killing both Red Queen armies in a human
-- match.
do
    local alert = brain.RedQueenModules.Strategy.ProductionDemand.DefenseAlert
    local restore = { Active = alert.Active, Targets = alert.Targets }
    alert.Active = false
    local t3AntiAir = builders["Red Queen Emergency T3 AA"]
    local t3Ground = builders["Red Queen Emergency T3 Point Defense"]
        or builders["Red Queen Emergency T3 Sentry"]
    assert(t3AntiAir.BuilderConditions[1][1](brain, "MAIN"),
        "a quiet base must still hold anti-air")
    assert(not t3Ground.BuilderConditions[1][1](brain, "MAIN"),
        "but a quiet base must not build point defence: only anti-air stands by default")

    -- Flak must not satisfy a SAM's floor. Tech 2 anti-air counts toward the
    -- Tech 2 need and not the Tech 3 one, exactly as point defence already
    -- works -- the first version of this floor was tier-blind and cheap flak
    -- crowded SAM out, 3.9 to 7.8 while SAM fell 3.8 to 2.8.
    brain.GetNumUnitsAroundPoint = function(_, category)
        return category.Keys.TECH3 and 0 or 8
    end
    assert(t3AntiAir.BuilderConditions[1][1](brain, "MAIN"),
        "eight flak must not satisfy the Tech 3 anti-air floor")
    brain.GetNumUnitsAroundPoint = function() return 0 end

    -- The floor is a floor, not a cap: an air alert still raises it.
    alert.Active = true
    alert.Targets = { AntiAir = 8 }
    brain.GetNumUnitsAroundPoint = function() return 6 end
    assert(t3AntiAir.BuilderConditions[1][1](brain, "MAIN"),
        "an alert above the standing floor must still raise the target")
    brain.GetNumUnitsAroundPoint = function() return 0 end
    alert.Active, alert.Targets = restore.Active, restore.Targets
end

brain.RedQueenModules.Strategy.ProductionDemand.DefenseAlert.AnchorPosition = { 200, 0, 200 }
local t2Ground = builders["Red Queen Emergency T2 Point Defense"]
local t2AntiAir = builders["Red Queen Emergency T2 AA"]
local t2Shield = builders["Red Queen Emergency T2 Shield"]
local t2Missile = builders["Red Queen Emergency Tactical Missile"]
assert(t2Ground.BuilderConditions[1][1](brain, "EXPANSION"), "a T2-only expansion must retain ground defense fallback")
assert(t2AntiAir.BuilderConditions[1][1](brain, "EXPANSION"), "a T2-only expansion must retain anti-air fallback")
assert(t2Shield.BuilderConditions[1][1](brain, "EXPANSION"), "a T2-only expansion must retain shield fallback")
assert(t2Missile.BuilderConditions[1][1](brain, "EXPANSION"), "a T2-only expansion must retain tactical missile fallback")
assert(not cybranDefense.BuilderConditions[1][1](brain, "EXPANSION"), "a remote T3 engineer must not enable T3 builders at an expansion")
assert(not smd.BuilderConditions[1][1](brain, "EXPANSION"), "a remote T3 engineer must not enable strategic defense at an expansion")

engineerCounts.EXPANSION[1] = 1
engineerCounts.EXPANSION[2] = 0
local t1Ground = builders["Red Queen Emergency T1 Point Defense"]
assert(t1Ground.BuilderConditions[1][1](brain, "EXPANSION"), "a T1-only threatened base must retain an emergency point-defense fallback")
assert(t1Ground.PlatoonTemplate == "EngineerBuilder", "the T1 fallback must use FAF's registered engineer platoon template")
assert(t1Ground.BuilderData.Construction.BuildStructures[1] == "T1GroundDefense", "the early fallback must use T1 point defense")

brain.RedQueenModules.Strategy.ProductionDemand.DefenseAlert.Active = false
assert(not t2Ground.BuilderConditions[1][1](brain, "EXPANSION"), "fortification builders must stop when the alert clears")

-- A tier's need is measured in structures of that tier or better.
--
-- Observed in a live match: four Tech 1 point defences satisfied a Ground
-- target of four, so the Tech 2 point defence builder's condition went false
-- while the base was under pressure, and the first Tech 2 structure built was a
-- tactical missile launcher -- the next builder down at priority 980. Four Tech
-- 1 point defences are not four Tech 2 point defences against a Tech 2 enemy.
brain.RedQueenModules.Strategy.ProductionDemand.DefenseAlert.Active = true
-- An earlier case cleared the Tech 2 engineer at this location; this need is
-- about what is standing, not about who can build it.
engineerCounts.EXPANSION[2] = 1
engineerCounts.EXPANSION[3] = 0
local counted = {}
brain.GetNumUnitsAroundPoint = function(_, category)
    -- This spec's categories carry a Keys set rather than a name.
    local keys = (category and category.Keys) or {}
    table.insert(counted, keys)
    -- Four Tech 1 point defences standing, and nothing above Tech 1.
    if keys.TECH2 or keys.TECH3 then
        return 0
    end
    return 4
end
assert(t2Ground.BuilderConditions[1][1](brain, "EXPANSION"),
    "four Tech 1 point defences must not satisfy the Tech 2 point defence need")
local askedForTier = false
for _, keys in ipairs(counted) do
    if keys.TECH2 then askedForTier = true end
end
assert(askedForTier, "the Tech 2 need must be counted in Tech 2 structures")

brain.GetNumUnitsAroundPoint = function() return 0 end

print("Red Queen fortification builder contracts passed")
