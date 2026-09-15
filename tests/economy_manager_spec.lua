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
        MinimumProductionMassIncome = 0.8,
        MassIncomePerFactory = 0.8,
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

-- Income figures are per tick throughout, so 0.5 here is 5 mass per second.
-- Reading these thresholds as per-second figures is what made the production
-- gate ten times too strict: in the Red Queen versus stock Adaptive 1v1 the
-- land factory target sat at one for the whole match, logged as
-- "factory cap L1/1" from the first minute to the defeat at 18:46, because
-- income cannot grow past a gate that withholds the production it needs.
currentTime = 400
sample.MassIncome = 0.5
balanced:Update()
assert(balanced.State.Mode == "ExpandProduction", "mature positive storage should expose surplus")
assert(balanced:CanCommitAttack(), "sustainable mature economy may commit an attack")
assert(not balanced:CanExpandProduction(0), "income below the production minimum must block expansion")

-- 20 mass per second is an ordinary early economy and must fund more than one
-- factory; a Tech 1 factory building continuously draws roughly 5 to 10.
sample.MassIncome = 2.0
balanced:Update()
assert(
    balanced.State.DesiredFactories == 3,
    "20 mass per second must support three factories, not one"
)
assert(
    balanced:CanExpandProduction(2),
    "a balanced match must still expand its own production; a zero deficit must not disable it"
)
assert(not balanced:CanExpandProduction(3), "factory target must stop additional expansion")

sample.MassIncome = 4.0
balanced:Update()
assert(
    balanced.State.DesiredFactories == 6,
    "40 mass per second must support six factories"
)
sample.MassIncome = 0.5
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
sample.MassIncome = 0.5
underdog:Update()
assert(not underdog:CanExpandProduction(1), "low income must block deficit factory expansion")

sample.MassIncome = 2.0
underdog:Update()
assert(
    underdog.State.DesiredFactories == 3,
    "the factory target must be income-driven for every match shape"
)
assert(underdog:CanExpandProduction(2), "outnumbered surplus economy should add production capacity")
assert(not underdog:CanExpandProduction(3), "factory target must stop additional expansion")

print("Red Queen economy manager contracts passed")
