local categoryMetatable = {}
categoryMetatable.__mul = function() return setmetatable({}, categoryMetatable) end
categoryMetatable.__add = function() return setmetatable({}, categoryMetatable) end
categoryMetatable.__sub = function() return setmetatable({}, categoryMetatable) end

categories = setmetatable({}, {
    __index = function(value, key)
        local category = setmetatable({}, categoryMetatable)
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
local alertActive = true
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
            EngineerManager = {
                Radius = 80,
                GetLocationCoords = function() return { 0, 0, 0 } end,
            },
        },
    },
    GetCurrentUnits = function() return 1 end,
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

brain.RedQueenModules.Strategy.ProductionDemand.DefenseAlert.Active = false
assert(not cybranDefense.BuilderConditions[1][1](brain, "MAIN"), "fortification builders must stop when the alert clears")

print("Red Queen fortification builder contracts passed")
