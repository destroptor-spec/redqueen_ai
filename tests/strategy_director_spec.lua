local currentTick = 0
local currentTime = 0
local knownTarget = nil
local localThreat = 0
local observedPressure = nil
local armyStats = { Lost = 0, Destroyed = 0 }
local dropOpportunity = {
    EntityId = 90,
    Position = { 80, 0, 80 },
    AirDefense = 0,
    SurfaceThreat = 2,
}

function GetGameTick()
    return currentTick
end

function GetGameTimeSeconds()
    return currentTime
end

function GetSurfaceHeight()
    return 0
end

function GetTerrainHeight()
    return 0
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

table.getsize = function(value)
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    return count
end

local constants = {
    Policy = {
        ObjectiveLifetimeTicks = 300,
        ObjectiveInterruptPriorityGap = 15,
        LocalDefenseThreat = 25,
        LandLossWindowSeconds = 120,
        LandLossCountThreshold = 8,
        LandLossMassThreshold = 450,
        CounterDoctrineSeconds = 180,
        GunshipAirThreatRatio = 0.40,
        AirDropMaximumAirThreat = 6,
        AirDropRequestCooldownSeconds = 90,
        MaximumAirDropTransports = 2,
        Tech2MinimumMassIncome = 4,
        Tech2MinimumEnergyIncome = 60,
        Tech3MinimumMassIncome = 10,
        Tech3MinimumEnergyIncome = 250,
        ExperimentalMinimumMassIncome = 22,
        ExperimentalMinimumEnergyIncome = 800,
        NukeMinimumMassIncome = 30,
        NukeMinimumEnergyIncome = 1200,
        StrategicFocusMinimumScore = 35,
        StrategicFocusSwitchMargin = 15,
        StrategicSecondProjectReadiness = 0.80,
        StrategicSecondProjectArmyMaximum = 70,
        MassiveArmyThreat = 40,
        MassiveArmyThreatRatio = 1.25,
        PressureEscalationThreat = 30,
        CombatMomentumWindowSeconds = 120,
        CombatMomentumLossRatio = 1.25,
        CombatMomentumMassDifference = 300,
        DefenseAlertHoldSeconds = 30,
    },
}
local logger = { Info = function() end }

function import(path)
    if path == "/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua" then
        return constants
    elseif path == "/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua" then
        return logger
    end
    error("unexpected import: " .. tostring(path))
end

local world = {
    StartPosition = { 0, 0, 0 },
    Width = 512,
    MapType = "Land",
    GetClosestEnemyStart = function()
        return { 100, 0, 100 }
    end,
    CanPath = function() return true end,
}
local strategicPicture = {
    EnemyTech = 1,
    Fortification = 0,
    Experimentals = 0,
    Nukes = 0,
    StrategicDefense = 0,
    HasHighValueTarget = false,
    HasReachableTarget = false,
    HasUnreachableTarget = false,
    Fortified = false,
}
local intel = {
    Threat = { Land = 0, Air = 0, Naval = 0 },
    Observations = {},
    HighestObservedTech = 1,
    GetThreatNear = function() return localThreat end,
    GetBestKnownTarget = function() return knownTarget end,
    GetBestExposedEconomyTarget = function() return dropOpportunity end,
    GetStrategicPicture = function() return strategicPicture end,
    GetObservedArmyPressure = function() return observedPressure end,
}
local economy = {
    State = {
        Mode = "Opening",
        StallRisk = false,
        Surplus = true,
        MassIncome = 10,
        EnergyIncome = 250,
        MassRequested = 0,
        EnergyRequested = 0,
        MassStoredRatio = 0.50,
        EnergyStoredRatio = 0.50,
        MassTrend = 0,
        EnergyTrend = 0,
    },
    CanCommitAttack = function() return false end,
}
local published = {}
local team = {
    GetSupportRequest = function() return nil end,
    GetCoordinatedAttack = function() return nil end,
    PublishAttack = function(_, objective) table.insert(published, objective) end,
}
local pings = { GetBestRequest = function() return nil end }

dofile("lua/AI/RedQueen/StrategyDirector.lua")

local brain = {
    BuilderManagers = {},
    GetArmyStat = function(_, name)
        if name == "Units_MassValue_Lost" then
            return { Value = armyStats.Lost }
        end
        return { Value = armyStats.Destroyed }
    end,
    GetListOfUnits = function() return {} end,
    GetUnitsAroundPoint = function() return {} end,
}
local director = Create(brain, { VictoryCondition = "Supremacy" }, world, intel, economy, team, pings)
local ownForces = {
    T2Factories = 0,
    T3Factories = 0,
    T3Engineers = 0,
    MissingT2Coverage = 2,
    MissingT3Coverage = 2,
    Experimentals = 0,
    Nukes = 0,
}
director.GetOwnForces = function() return ownForces end

director:Update()
assert(director.CurrentObjective.Type == "Pressure", "public enemy starts must enable immediate pressure")
assert(table.getn(published) == 1, "timer-free pressure must be shared with allies")
assert(brain.TransportRequested, "an exposed economy target must request transport capacity immediately")
assert(director.ProductionDemand.FocusWeights.Tech2 >= 35, "a ready economy must proactively enable T2")

local earlyTechScore = director.ProductionDemand.FocusWeights.Tech2
currentTime = 5000
director:UpdateDemand({ Type = "Pressure" })
assert(director.ProductionDemand.FocusWeights.Tech2 == earlyTechScore, "elapsed game time must not alter strategic focus")

knownTarget = { Position = { 40, 0, 40 } }
currentTick = 400
director:Update()
assert(director.CurrentObjective.Type == "Raid", "observed enemy contact must immediately replace fallback pressure")
assert(director.CurrentObjective.Position == knownTarget.Position, "raid must target the observed position")

ownForces.T2Factories = 1
ownForces.MissingT2Coverage = 0
strategicPicture.EnemyTech = 3
director:UpdateDemand({ Type = "Raid" })
assert(director.ProductionDemand.FocusWeights.Tech3 >= 75, "observed enemy T3 must create urgent T3 investment")
assert(director.ProductionDemand.PrimaryFocus == "Tech3", "a decisive enemy tech gap must become primary focus")

local lostTank = {
    GetBlueprint = function()
        return {
            CategoriesHash = { MOBILE = true, LAND = true },
            Economy = { BuildCostMass = 60 },
        }
    end,
}
for _ = 1, 8 do
    director:RecordUnitLoss(lostTank)
end
intel.Threat.Land = 100
intel.Threat.Air = 5
director:UpdateDemand({ Type = "Raid" })
assert(director.ProductionDemand.Doctrine == "GunshipCounter", "sustained land losses against weak AA must switch to gunships")
assert(director.ProductionDemand.FocusWeights.Army >= 80, "combat losses must shift weight back toward the field army")

currentTick = 4000
director.RecentLandLosses = {}
intel.Threat.Land = 20
intel.Threat.Air = 100
director:UpdateDemand({ Type = "Raid" })
assert(director.ProductionDemand.Doctrine == "AirDefense", "dominant enemy air threat must switch to fighter production")

economy.State.MassIncome = 30
economy.State.EnergyIncome = 1200
ownForces.T3Factories = 1
ownForces.T3Engineers = 1
ownForces.MissingT3Coverage = 0
intel.Threat.Land = 20
intel.Threat.Air = 5
strategicPicture.Fortification = 80
strategicPicture.Fortified = true
strategicPicture.HasHighValueTarget = true
strategicPicture.HasReachableTarget = true
strategicPicture.HasUnreachableTarget = false
strategicPicture.StrategicDefense = 0
director:UpdateDemand({ Type = "Raid" })
assert(director.ProductionDemand.FocusWeights.Experimental >= 75, "reachable fortification must favor an experimental breakthrough")
assert(director.ProductionDemand.MajorProjectSlots == 2, "safe exceptional headroom may fund two strategic projects")

strategicPicture.HasReachableTarget = false
strategicPicture.HasUnreachableTarget = true
strategicPicture.Experimentals = 1
director:UpdateDemand({ Type = "Raid" })
assert(director.ProductionDemand.FocusWeights.Nuke > director.ProductionDemand.FocusWeights.Experimental, "unreachable strategic value must favor nuclear siege")
assert(director.ProductionDemand.PrimaryFocus == "Nuke", "a decisive siege opportunity must become primary focus")

strategicPicture.StrategicDefense = 1
director:UpdateDemand({ Type = "Raid" })
assert(director.ProductionDemand.FocusWeights.Nuke == 0, "observed strategic missile defense must suppress nuclear investment")

economy.State.StallRisk = true
director:UpdateDemand({ Type = "Raid" })
assert(director.ProductionDemand.FocusWeights.Tech2 == 0, "genuine stalls must block new tier investment")
assert(director.ProductionDemand.FocusWeights.Experimental == 0, "genuine stalls must block new major projects")
localThreat = 0
knownTarget = nil
currentTick = 4400
director:Update()
assert(director.CurrentObjective.Type == "Pressure", "economic recovery must not idle existing combat forces")

economy.State.StallRisk = false
localThreat = 30
currentTick = 4800
director:Update()
assert(director.CurrentObjective.Type == "Defend", "immediate base danger must redirect the army")
assert(director.ProductionDemand.FocusWeights.Tech3 == 0, "base danger must block new strategic investment")

localThreat = 0
observedPressure = {
    Position = { 30, 0, 30 },
    AnchorPosition = { 0, 0, 0 },
    DistanceToAnchor = 42,
    Threat = 50,
    Surface = 45,
    Air = 5,
    ClosingThreat = 40,
    Approaching = true,
}
director.GetOwnThreatNear = function() return 20 end
currentTick = 5000
director:Update()
assert(director.DefenseAlert.Active, "a massive observed army must be acknowledged")
assert(director.CurrentObjective.Type == "Defend", "a massive army must override the active objective")
assert(director.ProductionDemand.MajorProjectSlots == 0, "defense alerts must pause new major projects")
assert(director.ProductionDemand.DesiredNukes == 0, "defense alerts must block new nuclear starts")

observedPressure = nil
currentTick = 5400
director:UpdateDefenseAlert()
assert(not director.DefenseAlert.Active, "a stale army alert must clear after its hold period")

armyStats.Lost = 500
armyStats.Destroyed = 50
observedPressure = {
    Position = { 50, 0, 50 },
    AnchorPosition = { 0, 0, 0 },
    DistanceToAnchor = 70,
    Threat = 30,
    Surface = 30,
    Air = 0,
    ClosingThreat = 20,
    Approaching = true,
}
director.GetOwnThreatNear = function() return 30 end
currentTick = 5500
director:UpdateDefenseAlert()
assert(director.CombatMomentum.Losing, "unfavorable mass exchange must be tracked")
assert(director.DefenseAlert.Active, "a losing AI must react to a smaller approaching army")

print("Red Queen strategy director contracts passed")
