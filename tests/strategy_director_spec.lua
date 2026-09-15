local currentTick = 0
local currentTime = 0
local knownTarget = nil
local localThreat = 0
local observedPressure = nil
local armyStats = { Lost = 0, Destroyed = 0 }
local waterPoint = nil
local waterZone = nil
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
    if waterZone and waterZone(x, z) then
        return 5
    end
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
        ShoreTorpedoMinimumDepth = 2.0,
        ShoreTorpedoProbeRadius = 48,
        TorpedoMinimumObservedNavalThreat = 6,
        LandLossWindowSeconds = 120,
        LandLossCountThreshold = 8,
        LandLossMassThreshold = 450,
        AirLossWindowSeconds = 120,
        EngineerLossWindowSeconds = 120,
        GarrisonLossWindowSeconds = 60,
        ScoutFractionMinimum = 0.05,
        ScoutFractionMaximum = 0.18,
        GarrisonLossFraction = 0.5,
        EngineersPerFactory = 0.75,
        EngineersMinimum = 2,
        EngineersMaximum = 18,
        EngineersPerForwardBase = 2,
        EngineerLossReplacementFactor = 1.5,
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
        ExperimentalConcurrentMaximum = 2,
        ExperimentalSecondProjectMassIncome = 40,
        ExperimentalUtilityMassIncome = 45,
        ExperimentalEscortMinimumFleet = 4,
        ExperimentalMinimumEnergyIncome = 800,
        NukeMinimumMassIncome = 30,
        NukeMinimumEnergyIncome = 1200,
        StrategicFocusMinimumScore = 35,
        StrategicFocusSwitchMargin = 15,
        StrategicFocusDwellSeconds = 90,
        DefenseAlertEndgameTaxPerSeverity = 0.20,
        DefenseAlertMinimumEndgameRetention = 0.35,
        EndgameWealthMultiple = 2.5,
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

-- Records where engineers die. Captured so a contract can assert the director
-- reports the loss position, without pulling the real module's policy reads in.
lethalSites = {}
local engineerSurvival = {
    RememberLethalSite = function(brain, position, reason)
        table.insert(lethalSites, { Brain = brain, Position = position, Reason = reason })
    end,
}

function import(path)
    if path == "/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua" then
        return constants
    elseif path == "/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua" then
        return logger
    elseif path == "/mods/TheRedQueen/lua/AI/RedQueen/EngineerSurvival.lua" then
        return engineerSurvival
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
assert(director.ProductionDemand.MajorProjectSlots >= 2, "safe exceptional headroom may fund two strategic projects")

-- Endgame volume is a flow: one or two experimentals always in production.
--
-- The original target could only ever be 1, because its second slot required
-- army weight below 70 and that never happened in twenty recorded matches. A
-- larger *stock* target was worse: it started three projects at once while the
-- count was low and regressed every measured Aeon run. So the contract is that
-- the owned count is added to a concurrency allowance rather than capping it.
local function experimentalDemandAt(massIncome, owned)
    economy.State.MassIncome = massIncome
    ownForces.Experimentals = owned
    director:UpdateDemand({ Type = "Raid" })
    return director.ProductionDemand.DesiredExperimentals,
        director.ProductionDemand.MajorProjectSlots
end

local gate = constants.Policy.ExperimentalMinimumMassIncome
local second = constants.Policy.ExperimentalSecondProjectMassIncome

-- Note the concurrency floor is not ours alone: the readiness path above can
-- already grant a second slot, and this only ever raises it. So the contract is
-- about the flow target, plus that concurrency never drops below the allowance.
local target, slots = experimentalDemandAt(gate, 0)
assert(target == 1, "at the affordability gate one project is wanted")
assert(slots >= 1, "an open experimental focus must leave at least one slot")

target = experimentalDemandAt(gate, 3)
assert(target == 4,
    "owning three must not stop production: the target follows the owned count")

target, slots = experimentalDemandAt(second, 0)
assert(slots >= constants.Policy.ExperimentalConcurrentMaximum,
    "income enough for two at once must leave room for both")
assert(target == constants.Policy.ExperimentalConcurrentMaximum,
    "with none owned the target is the concurrency allowance")

target = experimentalDemandAt(second, 5)
assert(target == 5 + constants.Policy.ExperimentalConcurrentMaximum,
    "the flow target must stay ahead of the owned count at every economy")
ownForces.Experimentals = 0

-- A dead engineer is recorded, and recorded as its own kind of loss.
--
-- It is not a combat casualty and must not inflate land loss pressure, which
-- drives doctrine -- but it is the most expensive loss to ignore, because it
-- stalls expansion, economy and production at once. Before this it was
-- discarded outright, so nothing could answer it.
local lostEngineer = {
    GetBlueprint = function()
        return {
            CategoriesHash = { MOBILE = true, LAND = true, ENGINEER = true },
            Economy = { BuildCostMass = 52 },
        }
    end,
}
director.RecentEngineerLosses = {}
local landLossesBefore = table.getn(director.RecentLandLosses)
for _ = 1, 3 do
    director:RecordUnitLoss(lostEngineer)
end
assert(table.getn(director.RecentEngineerLosses) == 3,
    "an engineer death must be recorded as an engineer loss")
assert(table.getn(director.RecentLandLosses) == landLossesBefore,
    "an engineer death must not be counted as a combat land loss")

-- The commander is an engineer by category and must never count as one.
director:RecordUnitLoss({
    GetBlueprint = function()
        return {
            CategoriesHash = { MOBILE = true, LAND = true, ENGINEER = true, COMMAND = true },
            Economy = { BuildCostMass = 18000 },
        }
    end,
})
assert(table.getn(director.RecentEngineerLosses) == 3,
    "the commander must not be counted as a lost engineer")
director.RecentEngineerLosses = {}

-- Engineers are established to a target, and losing them raises it.
--
-- FAF's own rule is a fixed "fewer than four at this location", which cannot
-- tell a quiet base from one losing an engineer a minute -- and an engineer
-- shortfall suppresses expansion, economy and production at the same time.
local function engineerTarget()
    director:UpdateDemand({ Type = "Raid" })
    return director.ProductionDemand.DesiredEngineers
end

director.RecentEngineerLosses = {}
economy.State.DesiredFactories = 4
local quietEngineers = engineerTarget()
assert(quietEngineers >= constants.Policy.EngineersMinimum,
    "the target must never fall below the minimum establishment")

-- Production it has to feed raises the structural need.
economy.State.DesiredFactories = 12
local fedEngineers = engineerTarget()
assert(fedEngineers > quietEngineers, "more production to feed must want more engineers")

-- Expansion states its own requirement rather than hoping one is spare.
director.ProductionDemand.ForwardBasePlan = { Active = true }
assert(engineerTarget() >= fedEngineers + constants.Policy.EngineersPerForwardBase,
    "an expansion in flight must add its own engineer requirement")
director.ProductionDemand.ForwardBasePlan = { Active = false }

-- Losses are answered immediately, and with more than they cost, so the army
-- runs a surplus exactly while it is bleeding.
local lossTick = currentTick
local steadyEngineers = engineerTarget()
for _ = 1, 4 do
    table.insert(director.RecentEngineerLosses, { Tick = lossTick, Mass = 52 })
end
local bleedingEngineers = engineerTarget()
assert(bleedingEngineers > steadyEngineers + 4,
    "four engineers lost must queue more than four replacements, got "
        .. tostring(bleedingEngineers) .. " against " .. tostring(steadyEngineers))
assert(director.ProductionDemand.EngineerLossPressure.Count == 4,
    "engineer losses must be reported as pressure in their own right")

-- The surplus decays on its own as losses age out; nothing has to cancel it.
currentTick = lossTick + constants.Policy.EngineerLossWindowSeconds * 10 + 1
assert(engineerTarget() == steadyEngineers,
    "an aged-out loss window must return the target to its structural need")
assert(director.ProductionDemand.EngineerLossPressure.Count == 0,
    "stale engineer losses must be pruned from the window")
currentTick = lossTick

-- The target stays bounded, so a sustained bleed cannot spend the whole economy
-- on builders.
for _ = 1, 60 do
    table.insert(director.RecentEngineerLosses, { Tick = lossTick, Mass = 52 })
end
assert(engineerTarget() == constants.Policy.EngineersMaximum,
    "the engineer target must stay bounded under sustained losses")
director.RecentEngineerLosses = {}
economy.State.DesiredFactories = 4

economy.State.MassIncome = 30
director:UpdateDemand({ Type = "Raid" })

strategicPicture.HasReachableTarget = false
strategicPicture.HasUnreachableTarget = true
strategicPicture.Experimentals = 1
director:UpdateDemand({ Type = "Raid" })
assert(director.ProductionDemand.FocusWeights.Nuke > director.ProductionDemand.FocusWeights.Experimental, "unreachable strategic value must favor nuclear siege")
-- The investment is the substance; the focus label follows the switch margin.
-- Wealth now engages an endgame focus a cycle earlier, so a nuke opportunity
-- arrives with an experimental focus already standing -- and 13 points is
-- inside StrategicFocusSwitchMargin, which exists precisely so a project in
-- progress is not abandoned for a marginally better one. What must not happen
-- is the launcher going unbuilt.
assert(director.ProductionDemand.DesiredNukes >= 1,
    "a decisive siege opportunity must be invested in, whatever holds the focus label")
assert(director.ProductionDemand.PrimaryFocus == "Experimental"
        or director.ProductionDemand.PrimaryFocus == "Nuke",
    "and the focus must stay on an endgame project, got "
        .. tostring(director.ProductionDemand.PrimaryFocus))

-- From a non-endgame focus the same opportunity does take the label, so the
-- margin is what holds it above and not an inability to choose nuclear siege.
director.ProductionDemand.PrimaryFocus = "Army"
director.ProductionDemand.PrimaryFocusTick = 0
director:UpdateDemand({ Type = "Raid" })
assert(director.ProductionDemand.PrimaryFocus == "Nuke",
    "a decisive siege opportunity must become primary focus from a standing army focus, got "
        .. tostring(director.ProductionDemand.PrimaryFocus))

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
director.GetOwnThreatByArm = function(_, position)
    measuredDefensePosition = position
    if position == expansionAnchor then
        return { Surface = 50, Air = 50 }
    end
    return { Surface = 0, Air = 0 }
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
director.GetOwnThreatByArm = function() return { Surface = 20, Air = 20 } end
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
director.GetOwnThreatByArm = function() return { Surface = 20, Air = 20 } end
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

-- A rich army must always be able to commit to an endgame. Winning is the
-- objective, and an army that can fund a project *and* its defence must never
-- be priced out of the game it is trying to win.
--
-- Crossfire Canal is the case: 66 mass income, 3340 energy, a full Tech 3
-- economy, alert ratios above 1000 -- and an experimental weight of 20 against
-- a threshold of 35 for the entire match. It spent that economy on 101
-- engineers and lost on attrition. Relief is keyed on economy and never on
-- elapsed time, so it has to be earned rather than waited out.
-- Values are copied out, not the table: ProductionDemand is one object reused
-- every cycle, so holding a reference would compare a reading against itself.
local function endgameUnderAlert(massIncome, severity)
    economy.State.MassIncome = massIncome
    -- Every precondition stated here, so the helper does not depend on what
    -- some earlier block happened to leave behind.
    director.DefenseAlert.Active = true
    director.DefenseAlert.AnchorKind = "MainBase"
    director.DefenseAlert.Severity = severity or 1000
    director:UpdateStrategicFocus({ Type = "Raid" }, { Count = 0, Mass = 0 }, 10, 5)
    local demand = director.ProductionDemand
    return {
        Experimental = demand.FocusWeights.Experimental,
        Slots = demand.MajorProjectSlots,
        Retention = demand.WealthRetention,
        Reason = demand.FocusReason,
        Desired = demand.DesiredExperimentals,
    }
end

local gate = constants.Policy.ExperimentalMinimumMassIncome
local poor = endgameUnderAlert(gate)
local rich = endgameUnderAlert(gate * constants.Policy.EndgameWealthMultiple)
assert(rich.Experimental > poor.Experimental,
    "wealth must lift the endgame tax, got " .. tostring(rich.Experimental)
        .. " against " .. tostring(poor.Experimental))
assert(rich.Retention == 1,
    "at the wealth multiple the severity tax must be lifted entirely, got "
        .. tostring(rich.Retention))
assert(poor.Retention < 1,
    "at the gate itself the severity tax must still apply in full, got "
        .. tostring(poor.Retention))
assert(rich.Reason == "defense-pressure-funded",
    "a funded endgame under pressure must be reported distinctly from a starved one")
assert(poor.Reason == "defense-pressure",
    "a starved endgame must keep the plain defence-pressure reason")

-- And a rich army keeps its *normal* concurrency instead of being clamped to a
-- single project, which is what stopped a developed economy closing a game.
-- Asserted against the allowance itself, because `>= poor` would hold even if
-- both were clamped to one.
assert(rich.Slots == constants.Policy.ExperimentalConcurrentMaximum,
    "a funded army under pressure must keep its full concurrency, got "
        .. tostring(rich.Slots) .. " of " .. tostring(constants.Policy.ExperimentalConcurrentMaximum))
assert(rich.Desired == constants.Policy.ExperimentalConcurrentMaximum,
    "and must be allowed to want that many, got " .. tostring(rich.Desired))
local savedOwned = ownForces.Experimentals
for _, owned in ipairs({ 2, 4 }) do
    ownForces.Experimentals = owned
    local funded = endgameUnderAlert(gate * constants.Policy.EndgameWealthMultiple)
    assert(funded.Desired == owned + funded.Slots,
        "defense pressure must limit additional concurrency while preserving owned experimentals")
    local taxed = endgameUnderAlert(gate, 1)
    assert(taxed.Desired == owned + 1 and taxed.Slots == 1,
        "one pressured project must remain available even with multiple experimentals owned")
end
ownForces.Experimentals = savedOwned

-- The contrast: a starved army under the same severity is taxed below the
-- commitment threshold and starts nothing at all. That is the behaviour being
-- preserved for a poor army, and lifted for one that can pay.
assert(poor.Slots == 0 and poor.Desired == 0,
    "a starved army under severe pressure must commit to nothing, got slots "
        .. tostring(poor.Slots) .. " desired " .. tostring(poor.Desired))
assert(poor.Experimental < constants.Policy.StrategicFocusMinimumScore,
    "and its taxed weight must sit below the commitment threshold")
assert(rich.Experimental >= constants.Policy.StrategicFocusMinimumScore,
    "while a funded army's weight must clear it")

-- The measured case that wealth relief alone did not answer: a rich army whose
-- income is fully *spent* must still commit.
--
-- `readiness` is headroom -- income minus what is already requested -- so an
-- army spending what it earns reads as unready however rich it is, and the
-- base weight `10 + readiness * 30` cannot reach the threshold of 35 without
-- it. Across a 21-cell matrix armies on 30-70 mass income crossed that
-- threshold in 1 to 5 samples out of 45 to 98 and built 2 experimentals in 21
-- full matches. Committing only when income is idle means never committing.
local function endgameAtFullSpend(massIncome)
    economy.State.MassIncome = massIncome
    economy.State.MassRequested = massIncome
    economy.State.EnergyRequested = economy.State.EnergyIncome
    -- `Surplus` short-circuits readiness to 0.85, which is the one state where
    -- the base weight clears the threshold on its own. Across 809 state samples
    -- from a 21-cell matrix the median readiness was 0.22 and only 7% reached
    -- 0.83, so the ordinary case is the one modelled here.
    economy.State.Surplus = false
    director.DefenseAlert.Active = false
    director.DefenseAlert.AnchorKind = nil
    director:UpdateStrategicFocus({ Type = "Raid" }, { Count = 0, Mass = 0 }, 10, 5)
    local demand = director.ProductionDemand
    return {
        Experimental = demand.FocusWeights.Experimental,
        Nuke = demand.FocusWeights.Nuke,
        Desired = demand.DesiredExperimentals,
        DesiredNukes = demand.DesiredNukes,
        Readiness = demand.EconomicReadiness,
    }
end

local spentRich = endgameAtFullSpend(gate * constants.Policy.EndgameWealthMultiple)
local spentPoor = endgameAtFullSpend(gate)
assert(spentRich.Readiness < 0.5,
    "this case is only meaningful while a fully committed economy reads as unready, got "
        .. tostring(spentRich.Readiness))
assert(spentRich.Experimental >= constants.Policy.StrategicFocusMinimumScore,
    "a rich army spending all of its income must still commit to an endgame, got "
        .. tostring(spentRich.Experimental))
assert(spentRich.Desired >= 1, "and must actually want one")
assert(spentPoor.Experimental < spentRich.Experimental,
    "while an army at the gate itself must not be handed the same commitment")

-- Game-enders are endgame commitment too, and were named as such: a nuclear
-- launcher answers a target an army cannot reach. So the same wealth that lets
-- a fully committed economy start an experimental must let it start a launcher.
local previousHighValue = strategicPicture.HasHighValueTarget
strategicPicture.HasHighValueTarget = true
strategicPicture.HasUnreachableTarget = true
strategicPicture.StrategicDefense = 0
local spentRichSiege = endgameAtFullSpend(gate * constants.Policy.EndgameWealthMultiple)
-- Compared against an army that can already afford a launcher, not one below
-- NukeMinimumMassIncome: at the experimental gate the nuke weight is 0 for
-- affordability alone, which would pass this whether or not wealth counted.
local spentPoorSiege = endgameAtFullSpend(constants.Policy.NukeMinimumMassIncome)
assert(spentRichSiege.Nuke >= constants.Policy.StrategicFocusMinimumScore,
    "a rich army spending all of its income must still commit to a game-ender, got "
        .. tostring(spentRichSiege.Nuke))
assert(spentRichSiege.DesiredNukes >= 1, "and must actually want one")
assert(spentPoorSiege.Nuke > 0,
    "the comparison army must be able to afford a launcher at all")
assert(spentPoorSiege.Nuke < spentRichSiege.Nuke,
    "and wealth must be what separates them, got " .. tostring(spentPoorSiege.Nuke)
        .. " against " .. tostring(spentRichSiege.Nuke))
strategicPicture.HasHighValueTarget = previousHighValue
strategicPicture.HasUnreachableTarget = false
economy.State.MassRequested = 0
economy.State.EnergyRequested = 0
economy.State.Surplus = true

-- An attack that has arrived is not abandoned for a couple of raiders at home.
--
-- Observed: an army with the strength to cripple an enemy base was recalled
-- repeatedly and killed only a few engineers. Any Defend used to preempt
-- unconditionally, and `LocalDefenseThreat` is 25 -- so a small home threat
-- pulled the army back, the objective expired after ObjectiveLifetimeTicks, the
-- attack resumed, and it walked back and forth without landing a blow.
local committedThreat = 0
director.GetOwnThreatNear = function(_, position)
    -- Strength at the enemy base only; nothing of ours at home.
    return (position and position[1] == 900) and committedThreat or 0
end

local function attackThenDefend(defence, ownStrengthAtTarget)
    committedThreat = ownStrengthAtTarget
    currentTick = 10000
    director.CurrentObjective = nil
    local attack = director:SetObjective({
        Type = "Raid",
        Position = { 900, 0, 900 },
        Priority = 82,
        Layer = "Land",
        CreatedTick = currentTick,
    })
    assert(attack.Type == "Raid", "the attack must be taken first")
    currentTick = currentTick + 10
    return director:SetObjective(defence)
end

local marginal = {
    Type = "Defend", Position = { 0, 0, 0 }, Priority = 120, Layer = "Land",
    CreatedTick = 10010,
}
local critical = {
    Type = "Defend", Position = { 0, 0, 0 }, Priority = 140, Layer = "Land",
    Critical = true, CreatedTick = 10010,
}

-- In contact: the marginal defence must not take the army home.
local held = attackThenDefend(marginal, 250)
assert(held.Type == "Raid",
    "an attack in contact must not be abandoned for a local threat, got " .. held.Type)

-- The real thing still preempts, whatever the attack is doing.
local preempted = attackThenDefend(critical, 250)
assert(preempted.Type == "Defend",
    "an observed cluster threatening an anchor must always preempt, got " .. preempted.Type)

-- An attack that never arrived is not protected: nothing of ours is there.
local notArrived = attackThenDefend(marginal, 0)
assert(notArrived.Type == "Defend",
    "an attack with no force at the objective must yield to defence, got " .. notArrived.Type)

-- And the hold ends by itself as that force dies, rather than needing a timer.
local dying = attackThenDefend(marginal, 0)
assert(dying.Type == "Defend", "a dead assault force must release the hold")

-- The hold is for attacks only. Staging or recovering has nothing to protect,
-- so a local threat takes precedence there as it always did.
committedThreat = 250
currentTick = 20000
director.CurrentObjective = nil
director:SetObjective({
    Type = "Stage", Position = { 900, 0, 900 }, Priority = 60, Layer = "Land",
    CreatedTick = currentTick,
})
currentTick = currentTick + 10
local staged = director:SetObjective({
    Type = "Defend", Position = { 0, 0, 0 }, Priority = 120, Layer = "Land",
    CreatedTick = currentTick,
})
assert(staged.Type == "Defend",
    "staging must still yield to a local threat, got " .. staged.Type)

-- The alert-driven defence is the one marked critical, and it is marked where
-- it is built rather than by the caller.
local alertObjective = nil
local previousUpdateAlert = director.UpdateDefenseAlert
local previousAlertState = director.DefenseAlert
director.UpdateDefenseAlert = function(self)
    local alert = {
        Active = true,
        AnchorPosition = { 0, 0, 0 },
        Position = { 60, 0, 60 },
        PrimaryLayer = "Land",
        AnchorKind = "MainBase",
        Severity = 2,
        Threat = 100,
        Ratio = 2,
        -- Per-layer figures the objective reads to place each task force.
        Land = 100,
        Naval = 0,
        Air = 0,
        Surface = 100,
        -- The real alert carries a hold window; later contracts read it back
        -- from self.DefenseAlert, so the stub must not omit it.
        ExpiresTick = 0,
    }
    self.DefenseAlert = alert
    self.ProductionDemand.DefenseAlert = alert
    return alert
end
director.CurrentObjective = nil
director:Update()
alertObjective = director.CurrentObjective
assert(alertObjective and alertObjective.Type == "Defend",
    "an active alert must produce a defensive objective")
assert(alertObjective.Critical,
    "the alert-driven defence must be marked critical, or it can no longer "
        .. "preempt an attack in contact")
director.UpdateDefenseAlert = previousUpdateAlert
director.DefenseAlert = previousAlertState
director.ProductionDemand.DefenseAlert = previousAlertState
director.CurrentObjective = nil
director.GetOwnThreatNear = nil
director.CurrentObjective = nil

-- An engineer death records the ground that killed it, so the replacement is
-- not posted straight back to the same place. That loop is what turns a few
-- losses into an army of engineers: each loss raises the target, and the
-- engineer builders' shared priority passes every combat builder at a shortfall
-- of five.
lethalSites = {}
local deadEngineer = {
    GetPosition = function() return { 400, 0, 400 } end,
    GetBlueprint = function()
        return {
            CategoriesHash = { MOBILE = true, ENGINEER = true },
            Economy = { BuildCostMass = 52 },
        }
    end,
}
local engineerLossesBefore = table.getn(director.RecentEngineerLosses)
director:RecordUnitLoss(deadEngineer)
assert(table.getn(director.RecentEngineerLosses) == engineerLossesBefore + 1,
    "an engineer death must still count toward loss pressure")
assert(table.getn(lethalSites) == 1,
    "and must record where it died, got " .. table.getn(lethalSites) .. " sites")
assert(lethalSites[1].Position[1] == 400 and lethalSites[1].Position[3] == 400,
    "the recorded position must be where the engineer was lost")
assert(lethalSites[1].Reason == "engineer-lost", "with the cause named")

-- A combat loss is not an engineer loss and must not poison the map.
director:RecordUnitLoss({
    GetPosition = function() return { 700, 0, 700 } end,
    GetBlueprint = function()
        return {
            CategoriesHash = { MOBILE = true, LAND = true },
            Economy = { BuildCostMass = 52 },
        }
    end,
})
assert(table.getn(lethalSites) == 1,
    "a tank dying must not mark the ground lethal for engineers")

-- Scout production follows coverage, not the existence of any observation.
--
-- The old rule asked for 15% while the army had seen nothing and 7% forever
-- after, so one sighting anywhere counted as being informed. What the
-- commitment gate depends on is coverage *at the positions that matter*: a wave
-- judged against an unobserved destination is judged against a threat of 0.
local function scoutFractionAt(blindShare)
    director.Modules = director.Modules or {}
    director.Modules.Combat = {
        ScoutSummary = { Targets = 10, Blind = blindShare * 10, Sent = 0 },
    }
    director:UpdateDemand({ Type = "Raid" })
    return director.ProductionDemand.Scouts
end

local blindScouts = scoutFractionAt(1.0)
local seeingScouts = scoutFractionAt(0.0)
assert(blindScouts > seeingScouts,
    "an army that cannot see what it cares about must build more scouts, got "
        .. tostring(blindScouts) .. " against " .. tostring(seeingScouts))
assert(blindScouts <= constants.Policy.ScoutFractionMaximum
        and seeingScouts >= constants.Policy.ScoutFractionMinimum,
    "and the fraction must stay within its bounds")
local halfScouts = scoutFractionAt(0.5)
assert(halfScouts > seeingScouts and halfScouts < blindScouts,
    "the response must be graded rather than a switch, got " .. tostring(halfScouts))
-- Observations existing is not the same as seeing what matters: with a full
-- observation table but nothing covered where it counts, scouting must still
-- rise.
director.Intel.Observations = { [1] = {}, [2] = {}, [3] = {} }
assert(scoutFractionAt(1.0) > seeingScouts,
    "a populated observation table must not count as being informed")

local scoutingConfig = setmetatable({}, { __index = _G })
setfenv(assert(loadfile("lua/AI/RedQueen/ScoutingConfig.lua")), scoutingConfig)()
director.Brain.RedQueenScouting = scoutingConfig.Create({ RedQueenScoutingMode = "production-only" })
assert(scoutFractionAt(0) == seeingScouts and scoutFractionAt(1) == blindScouts,
    "production-only must keep the same adaptive fraction when dispatch is disabled")
director.Brain.RedQueenScouting = scoutingConfig.Create({ RedQueenScoutingMode = "dispatch-only" })
for _, observations in ipairs({ {}, { [7] = {} } }) do
    director.Intel.Observations = observations
    local expected = table.getsize(observations) == 0 and 0.15 or 0.07
    for _, share in ipairs({ 0, 0.5, 1 }) do
        assert(scoutFractionAt(share) == expected,
            "dispatch-only must use exactly 15% with no observations and 7% otherwise")
        assert(director.ProductionDemand.ScoutBlindShare == share,
            "restoring binary production must not suppress coverage measurement")
    end
end
director.Brain.RedQueenScouting = nil
assert(scoutFractionAt(1) == blindScouts, "an unconfigured brain retains adaptive production")
director.Modules.Combat = nil

-- Severity still matters for an army that cannot afford the fight.
local calm = endgameUnderAlert(gate, 1)
local stormed = endgameUnderAlert(gate, 1000)
assert(stormed.Experimental < calm.Experimental,
    "a poor army must still be taxed by severity")
economy.State.MassIncome = 30
director.DefenseAlert.Severity = 4

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
director.GetOwnThreatByArm = function(_, position)
    if position == losingExpansionAnchor then
        checkedExpansionAnchor = true
        return { Surface = 100, Air = 100 }
    end
    if position == world.StartPosition then
        checkedMainAnchor = true
        return { Surface = 30, Air = 30 }
    end
    return { Surface = 0, Air = 0 }
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

-- Reproduction: irrelevant land strength near a naval anchor must not hide
-- a qualifying observed fleet. Use the real strength method, not a stub.
brain.BuilderManagers.NAVAL = { EngineerManager = { GetLocationCoords = function() return navalAnchor end } }
waterPoint = navalAnchor
director.GetOwnThreatNear = nil
brain.GetUnitsAroundPoint = function()
    return { { GetBlueprint = function() return {
        CategoriesHash = { LAND = true, MOBILE = true },
        Defense = { SurfaceThreatLevel = 500 },
        Weapon = {},
    } end, GetPosition = function() return { 290, 0, 290 } end } }
end
observedPressure = {
    FirstEntityId = 700, Position = { 350, 5, 350 }, AnchorIndex = 2,
    DistanceToAnchor = 42, Threat = 50, Surface = 50, Naval = 50, Land = 0, Air = 0,
    ClosingThreat = 40, Approaching = true,
}
director.DefenseAlert = { Active = false }
director:UpdateDefenseAlert()
assert(director.DefenseAlert.Active, "irrelevant land forces cannot suppress a qualifying naval alert")
assert(director.DefenseAlert.FriendlyThreat == 0)
-- Point defence and tactical missiles both engage ships, and artillery covers
-- the standoff band beyond their reach. A fleet-only cluster must still raise
-- all three, or a bombarded base builds nothing.
assert(director.DefenseAlert.Targets.Ground > 0,
    "a fleet-only attack must still call for point defence, which fires on ships")
assert(director.DefenseAlert.Targets.TacticalMissiles > 0,
    "a fleet-only attack must still call for tactical missiles")
assert(director.DefenseAlert.Targets.Artillery > 0,
    "a fleet-only attack must call for artillery to answer the standoff band")

-- Step 1 of docs/threat-accounting-plan.md: what actually counts against ships.
-- Blueprint shapes below are the real ones from units.nx2, not invented: an
-- interceptor's caps really do list Water, and it really does carry no surface
-- or sub damage, which is why the sum excludes it without a category exception.
local savedAround = brain.GetUnitsAroundPoint
director.GetOwnThreatNear = nil
director.GetOwnThreatByArm = nil
local function navalStrength(hash, defense, caps, position)
    brain.GetUnitsAroundPoint = function()
        return { {
            GetBlueprint = function()
                return {
                    CategoriesHash = hash,
                    Defense = defense,
                    Weapon = { { FireTargetLayerCapsTable = caps, MaxRadius = 30 } },
                }
            end,
            GetPosition = function() return position or { 0, 0, 0 } end,
        } }
    end
    return director:GetOwnThreatNear({ 0, 0, 0 }, 100, "Water", { 0, 0, 0 })
end

local airCaps = { Air = "Air|Land|Water|Seabed", Land = "Air|Land|Water|Seabed" }
assert(navalStrength({ AIR = true, MOBILE = true }, { SurfaceThreatLevel = 5 }, airCaps) == 5,
    "a gunship's guns reach the water, so it must count against ships")
assert(navalStrength({ AIR = true, MOBILE = true }, { SurfaceThreatLevel = 2 },
    { Air = "Land|Water|Seabed", Land = "Land|Water|Seabed" }) == 2,
    "a bomber must count against ships too")
assert(navalStrength({ AIR = true, MOBILE = true }, { SubThreatLevel = 8 },
    { Air = "Seabed|Sub|Water", Land = "Seabed|Sub|Water" }) == 8,
    "a torpedo bomber must still count, as it did before")
assert(navalStrength({ AIR = true, MOBILE = true }, { AirThreatLevel = 50 },
    { Air = "Air|Land|Water", Land = "Air|Land|Water" }) == 0,
    "an interceptor carries no anti-ship damage and must count nothing")
assert(navalStrength({ AIR = true, MOBILE = true }, { SurfaceThreatLevel = 9 },
    { Air = "Air" }) == 0,
    "an aircraft that can only engage air must count nothing against ships")

-- The other branches are unchanged and pinned so this stays honest.
assert(navalStrength({ NAVAL = true, MOBILE = true },
    { SurfaceThreatLevel = 23, SubThreatLevel = 3, AirThreatLevel = 1 }, {}) == 26,
    "a destroyer counts its surface and sub damage and not its flak")
assert(navalStrength({ STRUCTURE = true, DEFENSE = true }, { AirThreatLevel = 7 },
    { Land = "Air" }) == 0,
    "an AA tower cannot fire on water and must count nothing")
assert(navalStrength({ STRUCTURE = true, DEFENSE = true }, { SurfaceThreatLevel = 17 },
    { Land = "Land|Water|Seabed" }, { 10, 0, 10 }) == 17,
    "point defence in range of the water must still count")
assert(navalStrength({ STRUCTURE = true, DEFENSE = true }, { SurfaceThreatLevel = 17 },
    { Land = "Land|Water|Seabed" }, { 400, 0, 400 }) == 0,
    "and point defence out of range must not")
brain.GetUnitsAroundPoint = savedAround

-- Step 2 of docs/threat-accounting-plan.md: the same defenders, read per arm.
-- No production caller yet; step 3 is what consumes this.
local savedWater = waterPoint
local function stubUnit(hash, defense, caps, position)
    return {
        GetBlueprint = function()
            return {
                CategoriesHash = hash,
                Defense = defense,
                Weapon = { { FireTargetLayerCapsTable = caps, MaxRadius = 30 } },
            }
        end,
        GetPosition = function() return position or { 10, 0, 10 } end,
    }
end
local function armsFor(units, contact)
    brain.GetUnitsAroundPoint = function() return units end
    return director:GetOwnThreatByArm({ 0, 0, 0 }, 100, contact)
end

local aaTower = stubUnit({ STRUCTURE = true, DEFENSE = true },
    { AirThreatLevel = 7 }, { Land = "Air" })
local pointDefence = stubUnit({ STRUCTURE = true, DEFENSE = true },
    { SurfaceThreatLevel = 17 }, { Land = "Land|Water|Seabed" })
local gunship = stubUnit({ AIR = true, MOBILE = true },
    { SurfaceThreatLevel = 5 }, { Air = "Air|Land|Water|Seabed" })
local interceptor = stubUnit({ AIR = true, MOBILE = true },
    { AirThreatLevel = 50 }, { Air = "Air|Land|Water" })
local torpedoBomber = stubUnit({ AIR = true, MOBILE = true },
    { SubThreatLevel = 8 }, { Air = "Seabed|Sub|Water" })
local destroyer = stubUnit({ NAVAL = true, MOBILE = true },
    { SurfaceThreatLevel = 23, SubThreatLevel = 3, AirThreatLevel = 1 }, {})

-- A contact on the water.
local seaContact = { 0, 0, 0 }
waterPoint = seaContact
local sea = armsFor({ aaTower, pointDefence, gunship, interceptor, destroyer }, seaContact)
assert(sea.Air == 7 + 50 + 1,
    "anti-air is the tower, the interceptor and the destroyer's flak, got " .. sea.Air)
assert(sea.Surface == 17 + 5 + 26,
    "anti-ship is point defence, the gunship and the destroyer's guns, got " .. sea.Surface)
assert(armsFor({ aaTower }, seaContact).Surface == 0,
    "an AA tower answers no part of a fleet")
assert(armsFor({ interceptor }, seaContact).Surface == 0,
    "nor does an interceptor, which carries no anti-ship damage")

-- The same defenders against a contact on land. Reach is judged on the
-- contact's own layer, so the torpedo bomber drops out and the gunship does not.
waterPoint = nil
local shore = { 0, 0, 0 }
assert(armsFor({ torpedoBomber }, shore).Surface == 0,
    "a torpedo bomber cannot strike a land contact")
assert(armsFor({ torpedoBomber }, seaContact).Surface == 0,
    "and with no water under the contact it still cannot, whatever its caps say")
assert(armsFor({ gunship }, shore).Surface == 5,
    "a gunship's guns do reach a land contact")
assert(armsFor({ pointDefence }, shore).Surface == 17,
    "point defence answers a land contact in range")
assert(armsFor({ aaTower }, shore).Air == 7,
    "and anti-air is unchanged by what the contact is standing on")

-- Anti-air carries no reach test: an aircraft comes to the tower.
assert(armsFor({ stubUnit({ STRUCTURE = true, DEFENSE = true },
    { AirThreatLevel = 7 }, { Land = "Air" }, { 900, 0, 900 }) }, shore).Air == 7,
    "a distant AA tower still answers aircraft")
assert(armsFor({ stubUnit({ STRUCTURE = true, DEFENSE = true },
    { SurfaceThreatLevel = 17 }, { Land = "Land|Water|Seabed" }, { 900, 0, 900 }) }, shore).Surface == 0,
    "while a gun out of range answers nothing on the surface")

waterPoint = savedWater
brain.GetUnitsAroundPoint = savedAround

-- The same cluster with no Surface field. cluster.Surface is raw, unlike Land
-- and Naval which are back-filled from the anchor layer, so a role keyed on it
-- would silently evaluate to zero here and the contract would still go green.
observedPressure = {
    FirstEntityId = 701, Position = { 350, 5, 350 }, AnchorIndex = 2,
    DistanceToAnchor = 42, Threat = 50, Naval = 50, Land = 0, Air = 0,
    ClosingThreat = 40, Approaching = true,
}
director.DefenseAlert = { Active = false }
director:UpdateDefenseAlert()
assert(director.DefenseAlert.Active, "a naval cluster without a Surface field must still alert")
assert(director.DefenseAlert.Targets.Ground > 0,
    "defence targets must derive from normalised land+naval, never from raw cluster.Surface")
assert(director.DefenseAlert.Targets.Artillery > 0,
    "artillery targets must derive from normalised land+naval, never from raw cluster.Surface")

-- An air raid with a token escort is not a naval attack, and the base's own
-- air defence must be visible to the comparison. Judged as one undifferentiated
-- sum on the water view, NavalDefenseThreat credited an interceptor with its
-- SubThreatLevel -- zero -- and an AA tower with nothing at all, so a base
-- holding 25 interceptors behind a ring of AA measured friendly=0 against 300
-- of air and panicked over the attack it was built to stop.
director.GetOwnThreatByArm = function() return { Surface = 0, Air = 400 } end
observedPressure = {
    FirstEntityId = 702, Position = { 350, 5, 350 }, AnchorIndex = 2,
    DistanceToAnchor = 42, Threat = 306, Naval = 6, Land = 0, Air = 300,
    ClosingThreat = 40, Approaching = true,
}
director.DefenseAlert = { Active = false }
director:UpdateDefenseAlert()
assert(not director.DefenseAlert.Active,
    "a base holding air defence must not panic over an air raid escorted by one frigate")

-- The same base against a fleet it genuinely cannot answer. The air arm is
-- well covered and the surface arm is not, so the surface arm is what qualifies.
observedPressure = {
    FirstEntityId = 703, Position = { 350, 5, 350 }, AnchorIndex = 2,
    DistanceToAnchor = 42, Threat = 210, Naval = 200, Land = 0, Air = 10,
    ClosingThreat = 40, Approaching = true,
}
director.DefenseAlert = { Active = false }
director:UpdateDefenseAlert()
assert(director.DefenseAlert.Active,
    "a fleet the anchor cannot answer must still raise an alert")
assert(director.DefenseAlert.QualifiedArm == "surface",
    "and must name the arm that qualified, got " .. tostring(director.DefenseAlert.QualifiedArm))

-- Combined arms: neither arm clears its own magnitude floor, but together they
-- outweigh everything defending the anchor. Only the combined row catches this.
director.GetOwnThreatByArm = function() return { Surface = 20, Air = 20 } end
observedPressure = {
    FirstEntityId = 704, Position = { 350, 5, 350 }, AnchorIndex = 2,
    DistanceToAnchor = 42, Threat = 60, Naval = 30, Land = 0, Air = 30,
    ClosingThreat = 40, Approaching = true,
}
director.DefenseAlert = { Active = false }
director:UpdateDefenseAlert()
assert(director.DefenseAlert.Active,
    "a combined-arms push must still register when neither arm qualifies alone")
assert(director.DefenseAlert.QualifiedArm == "combined",
    "and must name the combined arm, got " .. tostring(director.DefenseAlert.QualifiedArm))

-- A token contact with nothing to answer it must not qualify on ratio alone:
-- that is the six-mass frigate that used to raise a massive alert.
director.GetOwnThreatByArm = function() return { Surface = 0, Air = 400 } end
observedPressure = {
    FirstEntityId = 705, Position = { 350, 5, 350 }, AnchorIndex = 2,
    DistanceToAnchor = 42, Threat = 6, Naval = 6, Land = 0, Air = 0,
    ClosingThreat = 0, Approaching = true,
}
director.DefenseAlert = { Active = false }
director:UpdateDefenseAlert()
assert(not director.DefenseAlert.Active,
    "a token fleet below the magnitude floor must not alert however unanswered it is")
director.GetOwnThreatByArm = nil
director.GetOwnThreatNear = nil

-- Leave the alert as the cases below found it: they read the same 701 cluster.
observedPressure = {
    FirstEntityId = 701, Position = { 350, 5, 350 }, AnchorIndex = 2,
    DistanceToAnchor = 42, Threat = 50, Naval = 50, Land = 0, Air = 0,
    ClosingThreat = 40, Approaching = true,
}
director.DefenseAlert = { Active = false }
director:UpdateDefenseAlert()
assert(director.DefenseAlert.Active, "the naval cluster must still alert on the real reading")

-- Torpedo launchers are water-only structures. An inland anchor cannot host one
-- at all, so it must raise no torpedo target rather than queue a build that
-- silently fails on dry land.
assert(director.DefenseAlert.Targets.Torpedo == 0,
    "an anchor with no water near it must raise no torpedo target")
assert(not director.DefenseAlert.WaterPosition, "a dry anchor must offer no water position")

-- Same fleet, but now there is sea to the east of the anchor.
waterZone = function(x) return x >= 330 end
director.DefenseAlert = { Active = false }
director:UpdateDefenseAlert()
assert(director.DefenseAlert.Active, "a coastal naval alert must still qualify")
local water = director.DefenseAlert.WaterPosition
assert(water, "a coastal anchor must resolve a water position for anti-navy structures")
assert(water[1] >= 330, "the torpedo site must actually be in water")
assert(director.DefenseAlert.Targets.Torpedo > 0,
    "an observed fleet at a coastal anchor must call for torpedo defences")

-- The site is biased toward the threat, which lies to the south-east.
local towardThreat = (water[1] - navalAnchor[1]) * (350 - navalAnchor[1])
    + (water[3] - navalAnchor[3]) * (350 - navalAnchor[3])
assert(towardThreat > 0, "the torpedo site must sit on the threatened approach, not behind the base")

-- Intelligence gate. Unclassified surface threat near a water anchor is
-- back-filled as naval so the right task force defends, but that is an
-- inference, not a sighting. Torpedo launchers cost more than a Tech 2 point
-- defence and shoot nothing but ships, so an unscouted contact must build none.
observedPressure = {
    FirstEntityId = 703, Position = { 350, 5, 350 }, AnchorIndex = 2,
    DistanceToAnchor = 42, Threat = 50, Surface = 50, Air = 0,
    ClosingThreat = 40, Approaching = true,
}
brain.GetUnitsAroundPoint = function() return {} end
director.DefenseAlert = { Active = false }
director:UpdateDefenseAlert()
assert(director.DefenseAlert.Active, "an unclassified surface contact must still raise an alert")
assert(director.DefenseAlert.Targets.Torpedo == 0,
    "surface threat inferred as naval must not commit mass to anti-navy structures")
assert(director.DefenseAlert.Targets.Ground > 0,
    "an unclassified contact must still raise point defence, which engages either way")

-- A contact too faint to be worth a launcher is also not enough. Observation
-- confidence decays as a sighting goes stale, so a fading blip lands here.
observedPressure = {
    FirstEntityId = 704, Position = { 350, 5, 350 }, AnchorIndex = 2,
    DistanceToAnchor = 42, Threat = 50, Naval = 3, Land = 47, Air = 0,
    ClosingThreat = 40, Approaching = true,
}
director.DefenseAlert = { Active = false }
director:UpdateDefenseAlert()
assert(director.DefenseAlert.Targets.Torpedo == 0,
    "a faded naval contact below one frigate must not trigger torpedo defences")

-- One frigate actually seen is enough.
observedPressure = {
    FirstEntityId = 705, Position = { 350, 5, 350 }, AnchorIndex = 2,
    DistanceToAnchor = 42, Threat = 50, Naval = 6, Land = 44, Air = 0,
    ClosingThreat = 40, Approaching = true,
}
director.DefenseAlert = { Active = false }
director:UpdateDefenseAlert()
assert(director.DefenseAlert.Targets.Torpedo > 0,
    "an observed warship must call for torpedo defences")
assert(director.DefenseAlert.ObservedNaval == 6, "the alert must report what was actually observed")

-- Land-only threat raises no torpedo target even on a coast: they shoot ships.
-- The land defenders above legitimately counter a land attack, so clear them or
-- the alert never qualifies and the assertions below prove nothing.
brain.GetUnitsAroundPoint = function() return {} end
observedPressure = {
    FirstEntityId = 702, Position = { 350, 5, 350 }, AnchorIndex = 2,
    DistanceToAnchor = 42, Threat = 50, Naval = 0, Land = 50, Air = 0,
    ClosingThreat = 40, Approaching = true,
}
director.DefenseAlert = { Active = false }
director:UpdateDefenseAlert()
assert(director.DefenseAlert.Targets.Torpedo == 0,
    "a purely land attack must not call for anti-navy structures")
assert(director.DefenseAlert.Targets.Ground > 0, "a land attack must still call for point defence")
-- The alert states what the threat would justify; whether any of it is
-- affordable is production's call. Artillery is held there behind the anchor's
-- primary point defence and a late-game economic ladder, which is what stops it
-- becoming a first response.
assert(director.DefenseAlert.Targets.Artillery > 0,
    "a surface attack must express artillery demand, which production then paces")
waterZone = nil

-- Offensive layer selection. An enemy start is dry land, so a water route to
-- it can never exist; a fleet must be aimed at the water beside it instead.
observedPressure = nil
waterPoint = nil
brain.GetUnitsAroundPoint = function() return {} end
director.DefenseAlert = { Active = false }
localThreat = 0
knownTarget = nil

local navalApproach = { 900, 0, 900 }
local approachRequests = {}
world.GetNavalApproach = function(_, origin, target)
    table.insert(approachRequests, { Origin = origin, Target = target })
    return navalApproach
end
-- Surface routes to the enemy start itself never succeed on open water.
world.CanPath = function(_, layer) return layer == "Air" end
world.GetClosestEnemyStart = function(_, _, layer)
    return layer == "Air" and { 100, 0, 100 } or nil
end

world.MapType = "Naval"
currentTick = 6000
director:Update()
assert(director.CurrentObjective.Type == "Pressure", "a naval map must still press the enemy")
assert(director.CurrentObjective.Layer == "Water",
    "a naval map must produce a Water objective, not fall through to Air")
assert(director.CurrentObjective.Position == navalApproach,
    "the fleet's destination must be the water-reachable approach itself")
assert(table.getn(approachRequests) > 0, "the water layer must resolve through the naval approach")

-- A mixed map must still offer the fleet an objective when land cannot reach.
world.MapType = "Mixed"
currentTick = 6400
director:Update()
assert(director.CurrentObjective.Layer == "Water",
    "a mixed map must fall through to the fleet when no land route exists")

-- Air remains the last resort, reached only when no surface layer can.
world.GetNavalApproach = function() return nil end
world.MapType = "Naval"
currentTick = 6800
director:Update()
assert(director.CurrentObjective.Layer == "Air",
    "Air must be chosen only when no surface layer has a reachable destination")

-- A land map with a land route must be unaffected by any of this.
world.CanPath = function() return true end
world.GetClosestEnemyStart = function() return { 100, 0, 100 } end
world.MapType = "Land"
currentTick = 7200
director:Update()
assert(director.CurrentObjective.Layer == "Land", "land maps must keep pressing on the land layer")

-- The common mixed case, and the one that went unnoticed. With a land route
-- available the layer loop breaks on Land, so the objective is Land and
-- IssueOrders dispatches Land, Amphibious and Hover -- never the fleet, which
-- cannot sail to a land coordinate. Naval production keeps running on a Mixed
-- map, so every ship built sat in the ArmyPool for the whole match. The fleet
-- must be handed the water beside the same target.
world.GetNavalApproach = function(_, origin, target)
    table.insert(approachRequests, { Origin = origin, Target = target })
    return navalApproach
end
world.MapType = "Mixed"
currentTick = 7600
director:Update()
assert(director.CurrentObjective.Layer == "Land",
    "a mixed map with a land route must still lead on the land layer")
assert(director.CurrentObjective.LayerPositions
    and director.CurrentObjective.LayerPositions.Water == navalApproach,
    "and must hand the fleet a water destination of its own")

-- Where no water route exists the field stays absent: nothing is invented and
-- the fleet is dispatched exactly as it was before.
world.GetNavalApproach = function() return nil end
currentTick = 8000
director:Update()
assert(director.CurrentObjective.Layer == "Land",
    "an inland map must keep pressing on the land layer")
assert(not (director.CurrentObjective.LayerPositions or {}).Water,
    "and must invent no water destination where the fleet cannot sail")

print("Red Queen strategy director contracts passed")
