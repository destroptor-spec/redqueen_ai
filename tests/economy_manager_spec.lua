local currentTime = 0

function GetGameTimeSeconds()
    return currentTime
end

function ClassSimple(definition)
    return setmetatable(definition, {
        __call = function(class, ...)
            local instance = setmetatable({}, { __index = class })
            instance:__init(...)
            return instance
        end,
    })
end

local constants = {
    Policy = {
        OpeningDurationSeconds = 300,
        MinimumAttackMassIncome = 6,
        MinimumProductionMassIncome = 8,
        IncomeSmoothingWeight = 0.25,
    },
}

function import(path)
    if path == "/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua" then
        return constants
    end
    error("unexpected import: " .. tostring(path))
end

local sample = {
    MassIncome = 0.1,
    EnergyIncome = 2,
    MassTrend = 0,
    EnergyTrend = 0,
    MassStoredRatio = 1,
    EnergyStoredRatio = 1,
    MassRequested = 0,
    EnergyRequested = 0,
}

local brain = {
    GetEconomyIncome = function(_, resource)
        return resource == "MASS" and sample.MassIncome or sample.EnergyIncome
    end,
    GetEconomyTrend = function(_, resource)
        return resource == "MASS" and sample.MassTrend or sample.EnergyTrend
    end,
    GetEconomyStoredRatio = function(_, resource)
        return resource == "MASS" and sample.MassStoredRatio or sample.EnergyStoredRatio
    end,
    GetEconomyRequested = function(_, resource)
        return resource == "MASS" and sample.MassRequested or sample.EnergyRequested
    end,
}

dofile("lua/AI/RedQueen/EconomyManager.lua")

local balanced = Create(brain, { ArmyDeficit = 0 })
balanced:Update()
assert(balanced.State.Mode == "Opening", "full starting storage must remain in opening mode")
assert(balanced.State.DesiredFactories == 1, "opening must not assume two custom factories")
assert(balanced:CanCommitAttack(), "opening time must never hold existing combat units")
assert(not balanced:HasResourceSurplus(), "opening storage must not be donated as mature surplus")

currentTime = 400
sample.MassIncome = 7
balanced:Update()
assert(balanced.State.Mode == "ExpandProduction", "mature positive storage should expose surplus")
assert(balanced:CanCommitAttack(), "sustainable mature economy may commit an attack")
assert(not balanced:CanExpandProduction(0), "income below the production minimum must block expansion")

sample.MassIncome = 8
balanced:Update()
assert(
    balanced.State.DesiredFactories == 2,
    "the factory target must follow income alone, not the army deficit"
)
assert(
    balanced:CanExpandProduction(1),
    "a balanced match must still expand its own production; a zero deficit must not disable it"
)
assert(not balanced:CanExpandProduction(2), "factory target must stop additional expansion")
sample.MassIncome = 7
balanced:Update()

sample.EnergyStoredRatio = 0.01
sample.EnergyTrend = 1
balanced:Update()
assert(not balanced.State.StallRisk, "low storage with a positive trend must not cause recovery oscillation")
assert(balanced:CanCommitAttack(), "combat units should keep pressure while energy is recovering")

sample.EnergyTrend = -1
balanced:Update()
assert(balanced.State.StallRisk, "low and falling energy must still trigger genuine recovery")
sample.EnergyStoredRatio = 1
sample.EnergyTrend = 0

local underdog = Create(brain, { ArmyDeficit = 2 })
underdog:Update()
assert(not underdog:CanExpandProduction(1), "low income must block deficit factory expansion")

sample.MassIncome = 8
underdog:Update()
assert(underdog.State.DesiredFactories == 2, "the factory target must be income-driven for every match shape")
assert(underdog:CanExpandProduction(1), "outnumbered surplus economy should add production capacity")
assert(not underdog:CanExpandProduction(2), "factory target must stop additional expansion")

print("Red Queen economy manager contracts passed")
