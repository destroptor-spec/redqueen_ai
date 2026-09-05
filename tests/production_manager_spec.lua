function ClassSimple(definition)
    return setmetatable(definition, {
        __call = function(class, ...)
            local instance = setmetatable({}, { __index = class })
            instance:__init(...)
            return instance
        end,
    })
end

local categoryMetatable = {
    __sub = function(left, right)
        return { EngineerOnly = left == categories.ENGINEER and right == categories.COMMAND }
    end,
}

categories = {
    ENGINEER = setmetatable({}, categoryMetatable),
    COMMAND = setmetatable({}, categoryMetatable),
    STRUCTURE = 1,
    FACTORY = 1,
    DEFENSE = 1,
    DIRECTFIRE = 1,
}

function EntityCategoryContains(category, unit)
    return category.EngineerOnly and unit.IsEngineer and not unit.IsCommander
end

local captured = nil
local buildAllowed = true
local buildRaises = false
local expansionFailure = false
local expansionCalls = {}
local buildStructures = {
    AIExecuteBuildStructure = function(...)
        captured = { ... }
        -- FAF forwards argument 4 (closeToBuilder) straight into
        -- aiBrain:FindPlaceToBuild, whose matching parameter is a game object.
        -- A boolean there makes the engine raise "Expected a game object" and
        -- kill the calling scheduler task, so the stub refuses to accept one.
        assert(
            type(captured[4]) ~= "boolean",
            "closeToBuilder is a game-object slot and must never receive a boolean"
        )
        if buildRaises then
            error("simulated engine rejection: Expected a game object")
        end
        return buildAllowed
    end,
    AIBuildBaseTemplateFromLocation = function(template)
        return template
    end,
    AINewExpansionBase = function(aiBrain, baseName, position, builder, constructionData)
        table.insert(expansionCalls, {
            Brain = aiBrain,
            Name = baseName,
            Position = position,
            Builder = builder,
            ConstructionData = constructionData,
        })
        if expansionFailure then
            error("simulated expansion registration failure")
        end
        aiBrain.BuilderManagers[baseName] = { EngineerManager = {} }
    end,
}
local addedCounterGroups = {}
local addBuilderTable = {
    AddGlobalBuilderGroup = function(_, locationType, groupName)
        table.insert(addedCounterGroups, { locationType, groupName })
    end,
}
local buildingTemplates = {
    BuildingTemplates = {
        [1] = {
            { "T1LandFactory", "uel0101" },
            { "T1AirFactory", "uea0101" },
            { "T1SeaFactory", "ues0103" },
            { "T1GroundDefense", "ueb2101" },
        },
    },
}
local baseTemplates = { BaseTemplates = { [1] = {} }, ExpansionBaseTemplates = { [1] = {} } }
local constants = {
    Policy = {
        FactoryCheckCooldownSeconds = 30,
        FactoryAssistMassPerEngineer = 1.0,
        MaximumFactoryAssistants = 6,
        FactoryAssistSeconds = 30,
        EmergencyDefenseCooldownSeconds = 5,
        EmergencyDefenseEngineerHoldSeconds = 10,
        EmergencyDefenseLogCooldownSeconds = 30,
        EmergencyDefenseRadius = 60,
        ForwardBaseSiteRadius = 60,
        ForwardBaseCooldownSeconds = 120,
        ForwardBaseDiagnosticSeconds = 60,
        ForwardBaseRecordRetentionSeconds = 300,
        ForwardBaseEstablishSeconds = 900,
        FactoryCapDiagnosticSeconds = 60,
        MaximumManagedBases = 8,
        MaximumTransports = 10,
        ForwardBaseMinimumMassIncome = 4,
        ForwardBaseMinimumEnergyIncome = 40,
        Tech2MinimumMassIncome = 4,
        Tech2MinimumEnergyIncome = 60,
    },
}
local logger = {
    Info = function() end,
    Warning = function() end,
    Error = function() end,
}

function import(path)
    if path == "/lua/AI/aibuildstructures.lua" then
        return buildStructures
    elseif path == "/lua/AI/AIAddBuilderTable.lua" then
        return addBuilderTable
    elseif path == "/lua/basetemplates.lua" then
        return baseTemplates
    elseif path == "/lua/buildingtemplates.lua" then
        return buildingTemplates
    elseif path == "/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua" then
        return constants
    elseif path == "/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua" then
        return logger
    elseif path == "/mods/TheRedQueen/lua/AI/RedQueen/CounterBuilders.lua" then
        return {}
    elseif path == "/mods/TheRedQueen/lua/AI/RedQueen/FortificationBuilders.lua" then
        return {}
    end
    error("unexpected import: " .. tostring(path))
end

function GetGameTick()
    return 1000
end

local guarded = {}
local cleared = {}
function IssueGuard(units, target)
    table.insert(guarded, { Units = units, Target = target })
end
function IssueClearCommands(units)
    table.insert(cleared, units)
end

local commander = {
    EntityId = 1,
    IsEngineer = true,
    IsCommander = true,
    IsIdleState = function() return true end,
    CanBuild = function() return true end,
}
local engineer = {
    EntityId = 2,
    IsEngineer = true,
    IsCommander = false,
    IsIdleState = function() return true end,
    CanBuild = function() return true end,
    GetBlueprint = function()
        return { CategoriesHash = { TECH2 = true } }
    end,
}
local destroyedEngineer = {
    EntityId = 3,
    IsEngineer = true,
    IsCommander = false,
    BeenDestroyed = function() return true end,
    IsIdleState = function() error("destroyed units must not be queried") end,
    CanBuild = function() return true end,
}
local poolUnits = { commander, engineer, destroyedEngineer }
local pool = { GetPlatoonUnits = function() return poolUnits end }
local forwardFactory = {
    EntityId = 10,
    Dead = false,
    GetArmy = function() return 1 end,
    GetPosition = function() return { 128, 0, 128 } end,
}
local transportCount = 0
local brain = {
    Army = 1,
    Name = "ARMY_1",
    GetArmyIndex = function() return 1 end,
    GetCurrentUnits = function() return transportCount end,
    GetPlatoonUniquelyNamed = function() return pool end,
    GetUnitsAroundPoint = function()
        if forwardFactory.Dead then
            return {}
        end
        return { forwardFactory }
    end,
    BuilderManagers = {
        MAIN = {
            BuilderHandles = {},
            FactoryManager = {
                HasBuilderList = function() return true end,
                SortBuilderList = function() end,
            },
        },
    },
}
ScenarioInfo = {
    ArmySetup = {
        ARMY_1 = {},
    },
}
local economy = {
    State = {
        DesiredFactories = 3,
        MassIncome = 8,
        StallRisk = false,
    },
    CanExpandProduction = function() return true end,
}
local world = { WaterRatio = 0 }
local strategy = {
    ProductionDemand = {
        Land = 0.55,
        Air = 0.30,
        Naval = 0.15,
        DefenseAlert = { Active = false },
    },
}

dofile("lua/AI/RedQueen/ProductionManager.lua")

local manager = Create(brain, { FactionIndex = 1, ArmyDeficit = 2 }, world, economy, {}, strategy)
assert(manager:FindForwardEngineer() == engineer, "destroyed ArmyPool engineers must be skipped safely")
manager:RegisterCounterBuilders()
assert(table.getn(addedCounterGroups) == 0, "custom builders must wait for FAF's native base setup")
ScenarioInfo.ArmySetup.ARMY_1.AIBase = "RushMainBalanced"
manager:RegisterCounterBuilders()
assert(table.getn(addedCounterGroups) == 0, "AIBase and a partial builder list must not imply native setup is complete")
brain.BuilderManagers.MAIN.BaseSettings = {}
manager:RegisterCounterBuilders()
assert(addedCounterGroups[1][1] == "MAIN", "counter builders must register at the main base")
assert(addedCounterGroups[1][2] == "RedQueenTierDominanceBuilders", "tier builder group name")
assert(addedCounterGroups[2][2] == "RedQueenCounterFactoryBuilders", "counter builder group name")
manager:TryExpandFactoryCapacity({ Total = 1, Land = 1, Air = 0, Naval = 0 })

assert(captured, "sustainable deficit should request a factory")
assert(captured[2] == engineer, "custom capacity must use an idle non-commander engineer")
assert(captured[4] == nil, "factory placement must not follow an arbitrary builder")
assert(captured[5] == false, "base placement must use the engine's absolute result")
assert(manager.FillIdleFactories == nil, "adaptive factory manager must remain the only unit-queue owner")

local landFactoryBuilder = {
    Priority = 500,
    OriginalPriority = 500,
    RedQueenConstructionTypes = { "T1LandFactory" },
    SetPriority = function(self, priority) self.Priority = priority end,
}
local navalFactoryBuilder = {
    Priority = 500,
    OriginalPriority = 500,
    RedQueenConstructionTypes = { "T1SeaFactory" },
    SetPriority = function(self, priority) self.Priority = priority end,
}
local airFactoryBuilder = {
    Priority = 500,
    OriginalPriority = 500,
    RedQueenConstructionTypes = { "T1AirFactory" },
    SetPriority = function(self, priority) self.Priority = priority end,
}
brain.BuilderManagers.MAIN.EngineerManager = {
    BuilderData = {
        Any = { Builders = { landFactoryBuilder, airFactoryBuilder, navalFactoryBuilder } },
    },
    SortBuilderList = function() end,
}
manager:ApplyFactoryCapacityPolicy({ Total = 3, Land = 1, Air = 1, Naval = 1 })
assert(landFactoryBuilder.Priority == 0, "native factory builders must stop at the sustainable total cap")
assert(navalFactoryBuilder.Priority == 0, "factory caps must cover every construction domain")
manager:ApplyFactoryCapacityPolicy({ Total = 2, Land = 1, Air = 1, Naval = 0 })
assert(landFactoryBuilder.Priority == 0, "a satisfied land target must remain capped")
assert(navalFactoryBuilder.Priority == 500, "a missing naval factory must restore only naval construction")

economy.State.DesiredFactories = 2
strategy.ProductionDemand.Naval = 0.05
manager:ApplyFactoryCapacityPolicy({ Total = 2, Land = 2, Air = 0, Naval = 0 })
assert(landFactoryBuilder.Priority == 0, "an overrepresented factory domain must remain capped")
assert(airFactoryBuilder.Priority == 500, "a missing domain must remain buildable when the total cap has the wrong mix")
assert(navalFactoryBuilder.Priority == 0, "an irrelevant absent domain must not bypass the total allocation")

local ratchetCounts = { Total = 3, Land = 1, Air = 1, Naval = 1 }
manager:ApplyFactoryCapacityPolicy(ratchetCounts)
assert(ratchetCounts.TargetTotal == 2, "an existing off-demand factory must not ratchet the sustainable factory total upward")
assert(navalFactoryBuilder.Priority == 0, "an off-demand domain must stay capped even once it already owns a factory")

-- FAF ships two kinds of builder that both mention a factory. The pure ones
-- build only a factory. The mixed ones create a whole expansion or naval base
-- and list a factory as one late line item; capping those on factory count
-- stopped the AI taking and holding ground in match 27741743.
local expansionPackageBuilder = {
    Priority = 850,
    OriginalPriority = 850,
    RedQueenConstructionTypes = {
        "T1GroundDefense", "T1Radar", "T2AADefense", "T2GroundDefense",
        "T2StrategicMissile", "T1LandFactory", "T2ShieldDefense",
    },
    SetPriority = function(self, priority) self.Priority = priority end,
}
local navalPackageBuilder = {
    Priority = 850,
    OriginalPriority = 850,
    RedQueenConstructionTypes = {
        "T1SeaFactory", "T1AADefense", "T1NavalDefense", "T1Sonar",
    },
    SetPriority = function(self, priority) self.Priority = priority end,
}
brain.BuilderManagers.MAIN.EngineerManager.BuilderData.Any.Builders = {
    landFactoryBuilder,
    airFactoryBuilder,
    navalFactoryBuilder,
    expansionPackageBuilder,
    navalPackageBuilder,
}

-- Map still offers unclaimed base sites: the base-creating builders must run
-- however saturated their factory domain already is.
world.ForwardBaseCandidates = { {}, {}, {} }
economy.State.DesiredFactories = 2
manager:ApplyFactoryCapacityPolicy({ Total = 4, Land = 3, Air = 1, Naval = 1 })
assert(
    expansionPackageBuilder.Priority == 850,
    "an expansion package must not be capped on factory count while base slots remain"
)
assert(
    navalPackageBuilder.Priority == 850,
    "a naval base package must not be capped on factory count while base slots remain"
)
assert(
    landFactoryBuilder.Priority == 0,
    "a pure factory builder must still be capped when its domain is saturated"
)

-- Base slots exhausted: the expansion package has no further ground to take,
-- so its incidental factory may now be capped like any other.
world.ForwardBaseCandidates = {}
manager:ApplyFactoryCapacityPolicy({ Total = 4, Land = 3, Air = 1, Naval = 1 })
assert(
    expansionPackageBuilder.Priority == 0,
    "an expansion package must be capped once the map has no unclaimed base slots"
)
assert(
    navalPackageBuilder.Priority == 0,
    "a naval base package must be capped once the map has no unclaimed base slots"
)

-- Restoring base slots must release the mixed builders again.
world.ForwardBaseCandidates = { {}, {}, {} }
manager:ApplyFactoryCapacityPolicy({ Total = 4, Land = 3, Air = 1, Naval = 1 })
assert(
    expansionPackageBuilder.Priority == 850,
    "a mixed builder must recover its original priority when base slots return"
)
world.ForwardBaseCandidates = nil
brain.BuilderManagers.MAIN.EngineerManager.BuilderData.Any.Builders = {
    landFactoryBuilder, airFactoryBuilder, navalFactoryBuilder,
}
economy.State.DesiredFactories = 3

local expansionTargets = { Land = 2, Air = 1, Naval = 0, Total = 3 }
assert(
    manager:SelectFactoryType({ Total = 2, Land = 1, Air = 1, Naval = 0 }, expansionTargets) == "T1LandFactory",
    "direct expansion must build the domain the capacity policy still wants"
)
assert(
    manager:SelectFactoryType({ Total = 3, Land = 2, Air = 1, Naval = 0 }, expansionTargets) == nil,
    "direct expansion must never build into a domain the capacity policy has capped"
)
local navalTargets = { Land = 1, Air = 0, Naval = 1, Total = 2 }
world.WaterRatio = 0.50
assert(
    manager:SelectFactoryType({ Total = 1, Land = 1, Air = 0, Naval = 0 }, navalTargets) == "T1SeaFactory",
    "a wet map must satisfy an unmet naval target"
)
world.WaterRatio = 0
assert(
    manager:SelectFactoryType({ Total = 1, Land = 1, Air = 0, Naval = 0 }, navalTargets) == nil,
    "a dry map must never select a naval factory"
)

economy.State.DesiredFactories = 3
strategy.ProductionDemand.Naval = 0.15

local assistEngineer = {
    EntityId = 40,
    IsEngineer = true,
    IsCommander = false,
    IsIdleState = function() return true end,
    CanBuild = function() return true end,
    GetPosition = function() return { 10, 0, 10 } end,
    GetBlueprint = function()
        return { CategoriesHash = { ENGINEER = true, TECH1 = true } }
    end,
}
local assignedEngineer = {
    EntityId = 39,
    IsEngineer = true,
    IsCommander = false,
    IsIdleState = function() return true end,
    GetBlueprint = function()
        return { CategoriesHash = { ENGINEER = true, TECH1 = true } }
    end,
}
local activeFactory = {
    EntityId = 41,
    IsUnitState = function(_, state) return state == "Building" end,
    GetBlueprint = function()
        return { CategoriesHash = { FACTORY = true, LAND = true, TECH3 = true } }
    end,
}
brain.GetListOfUnits = function() return { assignedEngineer, assistEngineer } end
brain.GetNumUnitsAroundPoint = function() return 0 end
poolUnits = {}
manager:UpdateFactoryAssistance({ activeFactory })
assert(table.getn(guarded) == 0, "idle engineers owned by native managers must not be taken for factory assistance")
poolUnits = { assistEngineer }
manager:UpdateFactoryAssistance({ activeFactory })
assert(table.getn(guarded) == 1, "idle T1 engineers must assist active factories instead of adding factory shells")
assert(guarded[1].Target == activeFactory, "factory assistance must prefer the active highest-tier target")
assert(manager.FactoryAssistants[assistEngineer.EntityId], "assistant ownership must be tracked deterministically")

local clearedBeforeIncomeDrop = table.getn(cleared)
poolUnits = {}
economy.State.MassIncome = 0
manager:UpdateFactoryAssistance({ activeFactory })
assert(not manager.FactoryAssistants[assistEngineer.EntityId], "reduced build power must release excess factory assistants")
assert(table.getn(cleared) == clearedBeforeIncomeDrop, "a reclaimed engineer must not have its new native orders cleared")
economy.State.MassIncome = 8
poolUnits = { assistEngineer }
manager:UpdateFactoryAssistance({ activeFactory })
assert(manager.FactoryAssistants[assistEngineer.EntityId], "factory assistance must resume when build power recovers")

strategy.ProductionDemand.DefenseAlert = {
    Active = true,
    AnchorKind = "Commander",
    AnchorPosition = { 20, 0, 20 },
    Targets = { Ground = 4 },
}
manager:UpdateFactoryAssistance({ activeFactory })
assert(not manager.FactoryAssistants[assistEngineer.EntityId], "defense alerts must release factory assistants")
assert(table.getn(cleared) > 0, "released assistants must have their factory orders cleared")
captured = nil
buildAllowed = true
manager:UpdateEmergencyDefense()
assert(captured, "a commander defense alert must directly queue point defense")
assert(captured[2] == assistEngineer, "direct emergency construction must use an available non-commander engineer")
assert(captured[3] == "T1GroundDefense", "T1 engineers must provide an early point-defense fallback")

captured = nil
manager.LastEmergencyDefenseTick = -100000
strategy.ProductionDemand.DefenseAlert = {
    Active = true,
    AnchorKind = "MainBase",
    AnchorLocationType = "MAIN",
    AnchorPosition = { 0, 0, 0 },
    Targets = { Ground = 4 },
}
assert(manager:HasManagedEmergencyDefense(strategy.ProductionDemand.DefenseAlert), "registered local fortification builders must own managed anchors")
manager:UpdateEmergencyDefense()
assert(not captured, "direct emergency construction must not duplicate a managed base builder queue")
strategy.ProductionDemand.DefenseAlert = { Active = false }

local mainlineBuilder = {
    Priority = 500,
    RedQueenUnitProfile = { Tier = 1, Domain = "Land", Role = "Mainline" },
    SetPriority = function(self, priority) self.Priority = priority end,
}
local shieldBuilder = {
    Priority = 500,
    RedQueenUnitProfile = { Tier = 2, Domain = "Land", Role = "Shield" },
    SetPriority = function(self, priority) self.Priority = priority end,
}
brain.BuilderManagers.MAIN.FactoryManager.BuilderData = {
    Land = { Builders = { mainlineBuilder, shieldBuilder } },
}
local t3LandFactory = {
    GetBlueprint = function()
        return { CategoriesHash = { LAND = true, FACTORY = true, TECH3 = true } }
    end,
}
manager.RoleAvailability["Land:Shield:3"] = false
manager:UpdateTierPolicy({ t3LandFactory })
manager:ApplyTierPolicy()
assert(mainlineBuilder.Priority == 0, "T3 access must disable T1 land mainline production")
assert(shieldBuilder.Priority == 500, "unique lower-tier shields must remain eligible")

manager.RoleAvailability["Land:Shield:3"] = true
manager:ApplyTierPolicy()
assert(shieldBuilder.Priority == 0, "a higher-tier role equivalent must obsolete lower-tier support")

manager:UpdateTierPolicy({})
manager:ApplyTierPolicy()
assert(mainlineBuilder.Priority == 500, "losing higher-tier access must restore lower-tier production")
assert(shieldBuilder.Priority == 500, "support priorities must restore with the domain tier")

-- A domain reduced to Tech 1 while the enemy is observed at Tech 3 must not
-- pour mass into units that cannot trade. Suppressing the obsolete mainline
-- leaves the surviving factory free to upgrade instead.
manager.Intel.HighestObservedTech = 3
economy.State.MassIncome = 20
economy.State.SmoothedMassIncome = 20
economy.State.StallRisk = false
manager:ApplyTierPolicy()
assert(
    mainlineBuilder.Priority == 0,
    "Tech 1 mainline must be suppressed when the enemy is observed at Tech 3"
)
assert(
    shieldBuilder.Priority == 500,
    "specialist lower-tier roles must survive the Tech 1 mainline suppression"
)

-- A brain that cannot afford the upgrade must keep building something.
economy.State.StallRisk = true
manager:ApplyTierPolicy()
assert(
    mainlineBuilder.Priority == 500,
    "a stalled brain must not be left with nothing its factories can build"
)
economy.State.StallRisk = false
economy.State.MassIncome = 1
economy.State.SmoothedMassIncome = 1
manager:ApplyTierPolicy()
assert(
    mainlineBuilder.Priority == 500,
    "suppression must not apply when the Tech 2 upgrade is unaffordable"
)

-- Against a Tech 2 enemy, Tech 1 mainline remains a reasonable trade.
manager.Intel.HighestObservedTech = 2
economy.State.MassIncome = 20
economy.State.SmoothedMassIncome = 20
manager:ApplyTierPolicy()
assert(
    mainlineBuilder.Priority == 500,
    "Tech 1 mainline must remain eligible against an observed Tech 2 enemy"
)
manager.Intel.HighestObservedTech = 1

-- Transports are excluded from combat waves and garrisons, so a surplus does
-- nothing but sit still. The budget caps the fleet; falling back under it must
-- restore production.
local transportBuilder = {
    Priority = 400,
    OriginalPriority = 400,
    RedQueenUnitProfile = { Tier = 1, Domain = "Air", Role = "Transport" },
    SetPriority = function(self, priority) self.Priority = priority end,
}
brain.BuilderManagers.MAIN.FactoryManager.BuilderData.Air = {
    Builders = { transportBuilder },
}
transportCount = 3
manager:UpdateTierPolicy({})
manager:ApplyTierPolicy()
assert(
    transportBuilder.Priority == 400,
    "transport production must run while the fleet is under budget"
)
transportCount = 10
manager:UpdateTierPolicy({})
manager:ApplyTierPolicy()
assert(
    transportBuilder.Priority == 0,
    "transport production must stop once the fleet reaches its budget"
)
transportCount = 4
manager:UpdateTierPolicy({})
manager:ApplyTierPolicy()
assert(
    transportBuilder.Priority == 400,
    "losing transports must restore production below the budget"
)
brain.BuilderManagers.MAIN.FactoryManager.BuilderData.Air = nil
transportCount = 0

local forwardSite = {
    Name = "Forward Marker 1",
    Type = "Expansion Area",
    Position = { 128, 0, 128 },
    RouteThreat = 12,
}
assert(manager:StartForwardBase(engineer, forwardSite), "a viable forward base must start")
assert(table.getn(expansionCalls) == 1, "forward base registration must use the build-structures exporter")
assert(expansionCalls[1].Name == "RQFB_1_1", "forward bases must have deterministic unique names")
assert(table.getn(manager.ForwardBases) == 1, "a successful start must create exactly one record")
assert(manager.ForwardBases[1].State == "Building", "a registered forward base must be tracked as building")
assert(manager.ForwardBases[1].Registered, "the tracked base must record successful registration")
assert(manager.ForwardBases[1].Queued > 0, "the tracked base must include its queued structures")
assert(manager.ForwardBaseClaims[forwardSite.Name], "the selected site must be claimed")
assert(manager.ForwardBaseActive == manager.ForwardBases[1], "the registered base must be active")

manager:UpdateForwardBaseStatus()
assert(manager.ForwardBases[1].State == "Established", "a live local factory must establish the forward base")
assert(manager.ForwardBases[1].Factory == forwardFactory, "the established base must track its live factory")
assert(manager.ForwardBaseActive == nil, "an established base must clear the active construction slot")

expansionFailure = true
local failedSite = {
    Name = "Forward Marker 2",
    Type = "Expansion Area",
    Position = { 256, 0, 256 },
    RouteThreat = 18,
}
assert(not manager:StartForwardBase(engineer, failedSite), "registration errors must fail without escaping")
local failedRecord = manager.ForwardBases[2]
assert(failedRecord.State == "Failed", "a failed registration must remain tracked")
assert(failedRecord.Failure == "ExpansionRegistration", "registration failure must identify its cause")
assert(failedRecord.Queued > 0, "a failed registration must track its partial construction queue")
assert(not failedRecord.Registered, "a failed registration must not be marked registered")
assert(manager.ForwardBaseActive == nil, "a failed registration must not become active")
assert(manager:CountViableForwardBases() == 1, "failed registrations must not count toward the base cap")
assert(manager.ForwardBaseClaims[failedSite.Name], "a partial queued base must retain its site claim")

expansionFailure = false
buildAllowed = false
local emptySite = {
    Name = "Forward Marker 3",
    Type = "Expansion Area",
    Position = { 384, 0, 384 },
    RouteThreat = 6,
}
assert(not manager:StartForwardBase(engineer, emptySite), "an empty construction queue must abort")
assert(table.getn(expansionCalls) == 2, "an empty queue must not create an expansion manager")
assert(table.getn(manager.ForwardBases) == 2, "an empty queue must not leave a forward-base record")
assert(not manager.ForwardBaseClaims[emptySite.Name], "an empty queue must release its site claim")

-- An engine rejection inside AIExecuteBuildStructure must be contained. Before
-- this contract existed, one unbuildable site aborted the whole production task
-- and leaked a record plus a permanent site claim on every retry.
buildAllowed = true
buildRaises = true
local raisingSite = {
    Name = "Forward Marker 4",
    Type = "Expansion Area",
    Position = { 400, 0, 400 },
    RouteThreat = 6,
}
local sequenceBeforeRaise = manager.ForwardBaseSequence
manager.LastForwardBaseTick = -100000
local raiseCompleted, raiseResult = pcall(manager.StartForwardBase, manager, engineer, raisingSite)
assert(raiseCompleted, "an engine rejection must not escape StartForwardBase")
assert(not raiseResult, "an engine rejection must report failure")
assert(table.getn(manager.ForwardBases) == 2, "an engine rejection must not leave a forward-base record")
assert(not manager.ForwardBaseClaims[raisingSite.Name], "an engine rejection must not claim its site")
assert(
    manager.ForwardBaseSequence == sequenceBeforeRaise,
    "an engine rejection must not consume a base name"
)
assert(
    manager.LastForwardBaseTick ~= -100000,
    "a rejected attempt must still advance the cooldown so it is not retried immediately"
)
assert(table.getn(expansionCalls) == 2, "an engine rejection must not register an expansion")
buildRaises = false

forwardFactory.Dead = true
manager:UpdateForwardBaseStatus()
assert(manager.ForwardBases[1].State == "Destroyed", "losing the local factory must invalidate an established base")
assert(not manager.ForwardBases[1].FactoryPresent, "a destroyed base must expose the missing factory")
assert(not manager.ForwardBaseClaims[forwardSite.Name], "destroyed bases must release their marker claim")
assert(manager:CountViableForwardBases() == 0, "destroyed bases must not count toward the map cap")

local capturedFactory = {
    EntityId = 11,
    GetArmy = function() return 2 end,
    GetPosition = function() return { 512, 0, 512 } end,
}
brain.BuilderManagers.RQFB_CAPTURED = { EngineerManager = {} }
brain.GetUnitsAroundPoint = function() return { capturedFactory } end
local capturedRecord = {
    Name = "RQFB_CAPTURED",
    SiteName = "Captured Marker",
    Position = { 512, 0, 512 },
    Factory = capturedFactory,
    State = "Established",
}
table.insert(manager.ForwardBases, capturedRecord)
manager.ForwardBaseClaims[capturedRecord.SiteName] = true
manager:UpdateForwardBaseStatus()
assert(capturedRecord.State == "Destroyed", "captured factories must invalidate established bases")
assert(not capturedRecord.FactoryPresent, "captured or allied factories must not satisfy ownership checks")
assert(not manager.ForwardBaseClaims[capturedRecord.SiteName], "captured bases must release their marker claim")

local remoteEngineerPosition = { 700, 0, 700 }
local routeEngineer = {
    EntityId = 20,
    IsEngineer = true,
    IsCommander = false,
    BuilderManagerData = { EngineerManager = {} },
    IsIdleState = function() return true end,
    GetPosition = function() return remoteEngineerPosition end,
    GetBlueprint = function()
        return { CategoriesHash = { TECH2 = true } }
    end,
}
local routePool = { GetPlatoonUnits = function() return { routeEngineer } end }
local staleFactory = {
    EntityId = 30,
    GetArmy = function() return 1 end,
    GetPosition = function() return { 700, 0, 700 } end,
}
local routeBrain = {
    GetPlatoonUniquelyNamed = function() return routePool end,
    GetArmyIndex = function() return 1 end,
    GetUnitsAroundPoint = function() return { staleFactory } end,
    BuilderManagers = {},
}
local selectedRouteOrigin = nil
local selectedEscortThreat = nil
local staleClaimReleasedBeforeSelection = false
local staleMarkerRebuildable = false
local replacementSite = {
    Name = "Stale Marker",
    Type = "Expansion Area",
    Position = remoteEngineerPosition,
    RouteThreat = 9,
}
local routeWorld = {
    StartPosition = { 0, 0, 0 },
    GetMaximumForwardBases = function() return 1 end,
    SelectForwardBaseSite = function(_, origin, _, _, claims, escortThreat, rebuildable)
        selectedRouteOrigin = origin
        selectedEscortThreat = escortThreat
        staleClaimReleasedBeforeSelection = not claims["Stale Marker"]
        staleMarkerRebuildable = rebuildable["Stale Marker"] == true
        return replacementSite
    end,
}
local routeEconomy = {
    State = {
        StallRisk = false,
        MassTrend = 1,
        EnergyTrend = 1,
        MassStoredRatio = 0.50,
        EnergyStoredRatio = 0.50,
        MassIncome = 10,
        EnergyIncome = 250,
    },
}
local routeStrategy = {
    CurrentObjective = { Type = "Pressure", Position = { 900, 0, 900 } },
    ProductionDemand = {},
    GetOwnThreatNear = function(_, position)
        assert(position == remoteEngineerPosition, "escort threat must use the selected engineer position")
        return 75
    end,
}
local routeManager = Create(
    routeBrain,
    { FactionIndex = 1 },
    routeWorld,
    routeEconomy,
    {},
    routeStrategy
)
local staleRecord = {
    Name = "RQFB_1_0",
    SiteName = "Stale Marker",
    Position = { 700, 0, 700 },
    Factory = staleFactory,
    State = "Established",
}
routeManager.ForwardBases = { staleRecord }
routeManager.ForwardBaseClaims[staleRecord.SiteName] = true
buildAllowed = true
routeManager:UpdateForwardBases()
assert(staleRecord.State == "Destroyed", "losing the expansion manager must invalidate an established base")
assert(staleRecord.FactoryPresent, "manager loss must invalidate a base even while its factory survives")
assert(not staleRecord.ManagerPresent, "manager loss must be recorded on the destroyed base")
assert(staleClaimReleasedBeforeSelection, "replacement selection must see the released stale marker")
assert(staleMarkerRebuildable, "destroyed markers must be explicitly eligible for nearby rebuilding")
assert(selectedRouteOrigin == remoteEngineerPosition, "route checks must start from the selected engineer")
assert(selectedRouteOrigin ~= routeWorld.StartPosition, "route checks must not use the original army start")
assert(selectedEscortThreat == 75, "site safety must use the engineer's local escort threat")
assert(table.getn(routeManager.ForwardBases) == 2, "a destroyed base must leave room for a replacement")
assert(routeManager.ForwardBases[2].State == "Building", "the replacement forward base must start immediately")
assert(routeManager.ForwardBaseActive == routeManager.ForwardBases[2], "the replacement must occupy the active construction slot")

print("Red Queen production manager contracts passed")
