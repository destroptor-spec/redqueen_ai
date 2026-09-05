local currentTick = 0
local currentTime = 0
local knownTarget = nil
local localThreat = 0
local observedPressure = nil
local armyStats = { Lost = 0, Destroyed = 0 }
local waterPoint = nil
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

function GetSurfaceHeight(x, z)
    if waterPoint and waterPoint[1] == x and waterPoint[3] == z then
        return 5
    end
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

categories = {
    COMMAND = 1,
    MOBILE = 1,
    LAND = 1,
    AIR = 1,
    NAVAL = 1,
    ENGINEER = 1,
    SCOUT = 1,
    STRUCTURE = 1,
    DEFENSE = 1,
}

local constants = {
    Policy = {
        ObjectiveLifetimeTicks = 300,
        ObjectiveInterruptPriorityGap = 15,
        LocalDefenseThreat = 25,
        LandLossWindowSeconds = 120,
        LandLossCountThreshold = 8,
        LandLossMassThreshold = 450,
        AirLossWindowSeconds = 120,
        AirLossCountThreshold = 8,
        AirLossMassThreshold = 450,
        GunshipRecoverySeconds = 120,
        CounterDoctrineSeconds = 180,
        GunshipAirThreatRatio = 0.40,
        AirDropMaximumAirThreat = 6,
        AirDropRequestCooldownSeconds = 90,
        AirDropDiagnosticSeconds = 30,
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
        StrategicFocusDwellSeconds = 90,
        DefenseAlertEndgameTaxPerSeverity = 0.20,
        DefenseAlertMinimumEndgameRetention = 0.35,
        StrategicSecondProjectReadiness = 0.80,
        StrategicSecondProjectArmyMaximum = 70,
        MassiveArmyThreat = 40,
        MassiveArmyThreatRatio = 1.25,
        CommanderEmergencyThreat = 20,
        CommanderEmergencyThreatRatio = 0.75,
        CommanderEmergencyDistance = 100,
        CommanderAssassinationCriticality = 3,
        CommanderAnnihilationCriticality = 2,
        CommanderSupremacyCriticality = 1.5,
        MainBaseCriticality = 1.4,
        ExpansionCriticality = 1,
        ForwardBaseCriticality = 1.15,
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
    GetObservedArmyClusters = function()
        if not observedPressure then
            return {}
        end
        if observedPressure[1] then
            return observedPressure
        end
        return { observedPressure }
    end,
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

local commanderUnits = {}
local brain = {
    BuilderManagers = {},
    GetArmyStat = function(_, name)
        if name == "Units_MassValue_Lost" then
            return { Value = armyStats.Lost }
        end
        return { Value = armyStats.Destroyed }
    end,
    GetListOfUnits = function() return commanderUnits end,
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
    ExperimentalsUnderConstruction = 0,
    NukesUnderConstruction = 0,
}
director.GetOwnForces = function() return ownForces end

director:Update()
assert(director.CurrentObjective.Type == "Pressure", "public enemy starts must enable immediate pressure")
assert(table.getn(published) == 1, "timer-free pressure must be shared with allies")
assert(brain.TransportRequested, "an exposed economy target must request transport capacity immediately")
assert(director.ProductionDemand.FocusWeights.Tech2 >= 35, "a ready economy must proactively enable T2")

local returningDropOpportunity = dropOpportunity
dropOpportunity = nil
director:UpdateAirDropOpportunity(world.StartPosition)
assert(director.AirDropStatus.State == "Expired", "a lost airdrop target must enter a terminal diagnostic state")
dropOpportunity = returningDropOpportunity
director:UpdateAirDropOpportunity(world.StartPosition)
assert(director.AirDropStatus.State == "Opportunity", "the same airdrop target must reactivate after returning")

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
local lostAircraft = {
    GetBlueprint = function()
        return {
            CategoriesHash = { MOBILE = true, AIR = true },
            Economy = { BuildCostMass = 60 },
        }
    end,
}
for _ = 1, 8 do director:RecordUnitLoss(lostAircraft) end
for _ = 1, 8 do
    director:RecordUnitLoss(lostTank)
end
intel.Threat.Land = 100
intel.Threat.Air = 5
director:UpdateDemand({ Type = "Raid" })
assert(director.ProductionDemand.Doctrine == "GunshipCounter", "sustained land losses against weak AA must switch to gunships")
assert(director.ProductionDemand.FocusWeights.Army >= 80, "combat losses must shift weight back toward the field army")
director:UpdateDemand({ Type = "Raid" })
assert(director.ProductionDemand.Doctrine == "GunshipCounter", "air losses before the gunship doctrine must not abandon a new counter")
assert(director.GunshipAirLossBaseline.Tick == currentTick, "the gunship baseline must record when its measurement window opened")

-- AirLossWindowSeconds after the baseline opened, a trickle of aircraft losses
-- must not read as a failed counter: the thresholds are per window, not total.
currentTick = 1700
for _ = 1, 4 do director:RecordUnitLoss(lostAircraft) end
director:UpdateDemand({ Type = "Raid" })
assert(director.ProductionDemand.Doctrine == "GunshipCounter", "air losses spread beyond the loss window must not abandon a working counter")
assert(director.GunshipAirLossBaseline.Tick == 1700, "the gunship loss baseline must restart once its window expires")

for _ = 1, 8 do director:RecordUnitLoss(lostAircraft) end
director:UpdateDemand({ Type = "Raid" })
assert(director.ProductionDemand.Doctrine == "Balanced", "a badly trading gunship response must be abandoned early")
assert(director.GunshipRecoveryUntilTick > currentTick, "failed gunships must enter a bounded recovery period")

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
local expansionAnchor = { 240, 0, 240 }
brain.BuilderManagers.EXPANSION = {
    EngineerManager = {
        GetLocationCoords = function() return expansionAnchor end,
    },
}
observedPressure = {
    Position = { 420, 0, 420 },
    AnchorIndex = 2,
    DistanceToAnchor = 255,
    Threat = 50,
    Surface = 50,
    Air = 0,
    ClosingThreat = 0,
    Approaching = false,
}
local measuredDefensePosition = nil
director.GetOwnThreatNear = function(_, position)
    measuredDefensePosition = position
    if position == expansionAnchor then
        return 50
    end
    return 0
end
currentTick = 4900
director:UpdateDefenseAlert()
assert(measuredDefensePosition == expansionAnchor, "friendly threat must be measured at the protected anchor")
assert(not director.DefenseAlert.Active, "a defended anchor must not panic over a distant relative threat")
brain.BuilderManagers.EXPANSION = nil

local navalAnchor = { 320, 5, 320 }
waterPoint = navalAnchor
brain.BuilderManagers.NAVAL = {
    EngineerManager = {
        GetLocationCoords = function() return navalAnchor end,
    },
}
observedPressure = {
    Position = { 350, 5, 350 },
    AnchorIndex = 2,
    DistanceToAnchor = 42,
    Threat = 50,
    Surface = 50,
    Air = 0,
    ClosingThreat = 40,
    Approaching = true,
}
director.GetOwnThreatNear = function() return 20 end
currentTick = 4950
director:Update()
assert(director.DefenseAlert.Active, "a massive naval force must trigger a defense alert")
assert(director.CurrentObjective.Position == navalAnchor, "naval defense must protect the selected anchor")
assert(director.CurrentObjective.Layer == "Water", "a water anchor must dispatch naval defenders")

observedPressure = {
    Position = { 350, 0, 350 },
    AnchorIndex = 2,
    DistanceToAnchor = 42,
    Threat = 50,
    Land = 50,
    Naval = 0,
    Surface = 50,
    Air = 0,
    ClosingThreat = 40,
    Approaching = true,
}
director.DefenseAlert = { Active = false }
currentTick = 4975
director:Update()
assert(director.CurrentObjective.Layer == "Land", "land invasions must not inherit a shoreline anchor's water layer")
assert(director.CurrentObjective.DefenseLayers.Land, "land defenders must remain eligible at water-adjacent bases")
assert(director.CurrentObjective.LayerPositions.Land == observedPressure.Position, "land defenders must intercept at the observed land position")
brain.BuilderManagers.NAVAL = nil
waterPoint = nil

observedPressure = {
    Position = { 30, 0, 30 },
    AnchorIndex = 1,
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
assert(director.CurrentObjective.Layer == "Land", "a land anchor must dispatch land defenders")

local airRaidPosition = { 30, 0, 30 }
observedPressure = {
    Position = airRaidPosition,
    AnchorIndex = 1,
    DistanceToAnchor = 42,
    Threat = 50,
    Land = 0,
    Naval = 0,
    Surface = 0,
    Air = 50,
    ClosingThreat = 40,
    Approaching = true,
}
director.DefenseAlert = { Active = false }
currentTick = 5010
director:Update()
assert(director.DefenseAlert.Active, "a massive observed air formation must be acknowledged")
assert(director.CurrentObjective.Layer == "Land", "a land anchor under air attack must keep organizing its ground defenders")
assert(director.CurrentObjective.DefenseLayers.Land, "a single-layer attack must not leave the land task force without a destination")
assert(director.CurrentObjective.LayerPositions.Land == world.StartPosition, "ground defenders must hold the threatened anchor when there is no surface threat to intercept")
assert(not director.CurrentObjective.DefenseLayers.Water, "an inland anchor must not order naval defenders to an unreachable layer")
assert(director.CurrentObjective.LayerPositions.Air == airRaidPosition, "air defenders must intercept the observed air formation")
-- A defence alert taxes endgame investment in proportion to severity; it does
-- not cancel it. Zeroing the weights outright meant that a brain under
-- sustained pressure -- exactly the late game of a hard match -- could never
-- finish an experimental, however rich it was.
assert(director.ProductionDemand.FocusWeights.Army == 100, "a defense alert must make army production primary")
assert(
    director.ProductionDemand.FocusWeights.Experimental > 0
        and director.ProductionDemand.FocusWeights.Experimental < 80,
    "a non-commander alert must reduce experimental weight without zeroing it"
)
assert(
    director.ProductionDemand.MajorProjectSlots == 1,
    "a non-commander alert must fund at most one major project, not none"
)
assert(director.ProductionDemand.DesiredExperimentals == 1, "a taxed alert must still allow a single experimental")
assert(director.ProductionDemand.DesiredNukes == 0, "observed strategic defense must still suppress nuclear starts")

-- Severity scales the tax: a far worse ratio must retain less.
local taxedExperimental = director.ProductionDemand.FocusWeights.Experimental
director.DefenseAlert.Severity = 10
director:UpdateStrategicFocus({ Type = "Raid" }, { Count = 0, Mass = 0 }, 10, 5)
assert(
    director.ProductionDemand.FocusWeights.Experimental < taxedExperimental,
    "a more severe alert must retain less endgame investment"
)
assert(
    director.ProductionDemand.FocusWeights.Experimental > 0,
    "even a severe non-commander alert must not zero endgame investment outright"
)

-- The commander is the exception. In Assassination, losing the ACU ends the
-- match, so a credible attack on it vetoes every project absolutely.
local previousVictory = director.Context.VictoryCondition
local previousAnchorKind = director.DefenseAlert.AnchorKind
director.Context.VictoryCondition = "Assassination"
director.DefenseAlert.AnchorKind = "Commander"
director:UpdateStrategicFocus({ Type = "Raid" }, { Count = 0, Mass = 0 }, 10, 5)
assert(director.ProductionDemand.MajorProjectSlots == 0, "a commander emergency must veto every major project")
assert(director.ProductionDemand.FocusWeights.Experimental == 0, "a commander emergency must zero experimental weight")
assert(director.ProductionDemand.FocusWeights.Tech3 == 0, "a commander emergency must zero tier investment")
assert(director.ProductionDemand.FocusReason == "commander-emergency", "a commander emergency must be reported distinctly")

-- The same alert outside Assassination is graded, not absolute.
director.Context.VictoryCondition = "Annihilation"
director:UpdateStrategicFocus({ Type = "Raid" }, { Count = 0, Mass = 0 }, 10, 5)
assert(
    director.ProductionDemand.FocusReason == "defense-pressure",
    "a commander alert outside Assassination must remain a graded defense response"
)
-- A pause gates new starts, never work already under way. Even the absolute
-- commander veto must let a half-built experimental finish: abandoning it
-- strands its engineers and wastes everything already spent.
ownForces.ExperimentalsUnderConstruction = 1
ownForces.NukesUnderConstruction = 1
director.Context.VictoryCondition = "Assassination"
director.DefenseAlert.AnchorKind = "Commander"
director:UpdateStrategicFocus({ Type = "Raid" }, { Count = 0, Mass = 0 }, 10, 5)
assert(
    director.ProductionDemand.DesiredExperimentals == 1,
    "an experimental already under construction must keep its target through any veto"
)
assert(
    director.ProductionDemand.DesiredNukes == 1,
    "a nuclear launcher already under construction must keep its target through any veto"
)
assert(
    director.ProductionDemand.MajorProjectSlots >= 2,
    "an experimental and a nuclear launcher in flight need a slot each, not a shared one"
)
ownForces.ExperimentalsUnderConstruction = 0
ownForces.NukesUnderConstruction = 0

director.Context.VictoryCondition = previousVictory
director.DefenseAlert.AnchorKind = previousAnchorKind
director.DefenseAlert.Severity = 3.5

observedPressure = nil
currentTick = 5400
director:UpdateDefenseAlert()
assert(not director.DefenseAlert.Active, "a stale army alert must clear after its hold period")

armyStats.Lost = 500
armyStats.Destroyed = 50
local losingExpansionAnchor = { 240, 0, 240 }
brain.BuilderManagers.LOSS_EXPANSION = {
    EngineerManager = {
        GetLocationCoords = function() return losingExpansionAnchor end,
    },
}
local approachingPosition = { 50, 0, 50 }
observedPressure = {
    {
        FirstEntityId = 40,
        Position = { 400, 0, 400 },
        AnchorIndex = 2,
        DistanceToAnchor = 226,
        Threat = 100,
        Surface = 100,
        Air = 0,
        ClosingThreat = 0,
        Approaching = false,
    },
    {
        FirstEntityId = 41,
        Position = approachingPosition,
        AnchorIndex = 1,
        DistanceToAnchor = 70,
        Threat = 30,
        Surface = 30,
        Air = 0,
        ClosingThreat = 20,
        Approaching = true,
    },
}
local checkedMainAnchor = false
local checkedExpansionAnchor = false
director.GetOwnThreatNear = function(_, position)
    if position == losingExpansionAnchor then
        checkedExpansionAnchor = true
        return 100
    end
    if position == world.StartPosition then
        checkedMainAnchor = true
        return 30
    end
    return 0
end
currentTick = 5500
director:UpdateDefenseAlert()
assert(director.CombatMomentum.Losing, "unfavorable mass exchange must be tracked")
assert(checkedMainAnchor and checkedExpansionAnchor, "every observed cluster must be tested at its nearest anchor")
assert(director.DefenseAlert.Active, "a losing AI must react to a smaller approaching army")
assert(director.DefenseAlert.Position == approachingPosition, "a larger non-threatening cluster must not hide an approaching army")
brain.BuilderManagers.LOSS_EXPANSION = nil

local commanderPosition = { 20, 0, 20 }
commanderUnits = {
    {
        EntityId = 99,
        Dead = false,
        GetPosition = function() return commanderPosition end,
    },
}
local remoteAnchor = { 400, 0, 400 }
brain.BuilderManagers.REMOTE = {
    EngineerManager = {
        GetLocationCoords = function() return remoteAnchor end,
    },
}
director.Context.VictoryCondition = "Assassination"
director.DefenseAlert = { Active = false }
observedPressure = {
    {
        FirstEntityId = 50,
        Position = { 420, 0, 420 },
        AnchorIndex = 2,
        DistanceToAnchor = 28,
        Threat = 80,
        Land = 80,
        Naval = 0,
        Surface = 80,
        Air = 0,
        ClosingThreat = 0,
        Approaching = false,
    },
    {
        FirstEntityId = 51,
        Position = { 30, 0, 30 },
        AnchorIndex = 3,
        DistanceToAnchor = 14,
        Threat = 30,
        Land = 30,
        Naval = 0,
        Surface = 30,
        Air = 0,
        ClosingThreat = 20,
        Approaching = true,
    },
}
director.GetOwnThreatNear = function() return 20 end
currentTick = 5600
director:UpdateDefenseAlert()
assert(director.DefenseAlert.AnchorKind == "Commander", "a credible Assassination attack on the ACU must outrank a larger remote formation")
assert(director.DefenseAlert.AnchorPosition == commanderPosition, "commander emergencies must retain the live ACU position")
brain.BuilderManagers.REMOTE = nil
commanderUnits = {}

print("Red Queen strategy director contracts passed")
