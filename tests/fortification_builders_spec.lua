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
    return path
end

dofile("lua/AI/RedQueen/FortificationBuilders.lua")

assert(groups.RedQueenEmergencyFortificationBuilders, "emergency fortification group must register")

local factionIndex = 1
local engineerCounts = {
    MAIN = { [2] = 0, [3] = 1 },
    EXPANSION = { [2] = 1, [3] = 0 },
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

brain.RedQueenModules.Strategy.ProductionDemand.DefenseAlert.Active = false
assert(not t2Ground.BuilderConditions[1][1](brain, "EXPANSION"), "fortification builders must stop when the alert clears")

print("Red Queen fortification builder contracts passed")
