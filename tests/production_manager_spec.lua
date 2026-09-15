function ClassSimple(definition)
    return setmetatable(definition, {
        __call = function(class, ...)
            local instance = setmetatable({}, { __index = class })
            instance:__init(...)
            return instance
        end,
    })
end

local categoryMetatable = {}
local function Category(matches)
    return setmetatable({ Matches = matches }, categoryMetatable)
end
categoryMetatable.__mul = function(left, right)
    return Category(function(hash) return left.Matches(hash) and right.Matches(hash) end)
end
categoryMetatable.__add = function(left, right)
    return Category(function(hash) return left.Matches(hash) or right.Matches(hash) end)
end
categoryMetatable.__sub = function(left, right)
    return Category(function(hash) return left.Matches(hash) and not right.Matches(hash) end)
end
categories = setmetatable({}, {
    __index = function(value, key)
        local category = Category(function(hash) return hash[key] == true end)
        rawset(value, key, category)
        return category
    end,
})

function EntityCategoryContains(category, unit)
    return category.Matches({ ENGINEER = unit.IsEngineer, COMMAND = unit.IsCommander })
end

local counterModule
local experimentalModule
local counterDefinitions = {}
function Builder(definition)
    counterDefinitions[definition.BuilderName] = definition
    return definition
end
function BuilderGroup(definition) return definition end
function PlatoonTemplate(definition) return definition end

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
            { "T2Artillery", "ueb2303" },
            { "T1NavalDefense", "ueb2109" },
            { "T2NavalDefense", "ueb2205" },
        },
    },
}
local baseTemplates = { BaseTemplates = { [1] = {} }, ExpansionBaseTemplates = { [1] = {} } }
local constants = {
    Policy = {
        FactoryCheckCooldownSeconds = 30,
        ProductionBuildHoldSeconds = 60,
        FactoryAssistMassPerEngineer = 1.0,
        MaximumFactoryAssistants = 6,
        FactoryAssistSeconds = 30,
        EmergencyDefenseCooldownSeconds = 5,
        EmergencyDefenseEngineerHoldSeconds = 10,
        EmergencyDefenseLogCooldownSeconds = 30,
        EmergencyDefenseRadius = 60,
        ShoreArtilleryRearOffset = 25,
        ShoreArtilleryRadius = 90,
        ShoreArtilleryMinimumMassIncome = 1.5,
        Tech3MinimumMassIncome = 10,
        ExperimentalMinimumMassIncome = 22,
        NukeMinimumMassIncome = 30,
        ShoreTorpedoRadius = 60,
        ShoreTorpedoProbeRadius = 48,
        TierReadinessMinimumKilometers = 10,
        ForwardBaseSiteRadius = 60,
        ForwardBaseCooldownSeconds = 120,
        ForwardBaseDiagnosticSeconds = 60,
        ForwardBaseRecordRetentionSeconds = 300,
        ForwardBaseEstablishSeconds = 900,
        ForwardBaseRouteRecheckSeconds = 20,
        ForwardBaseRecallThreatRatio = 1.5,
        ForwardBaseSafetyRatio = 0.60,
        EngineerSurvivalHomeRadius = 80,
        EngineerSurvivalThreatFloor = 8,
        CommanderLeashRadius = 120,
        CommanderAssistSeconds = 45,
        ForwardBaseSourceMinimumEngineers = 2,
        FactoryCapDiagnosticSeconds = 60,
        MaximumManagedBases = 8,
        MaximumTransports = 10,
        ForwardBaseMinimumMassIncome = 4,
        ForwardBaseMinimumEnergyIncome = 40,
        Tech2MinimumMassIncome = 4,
        Tech2MinimumEnergyIncome = 60,
        StrategicFocusMinimumScore = 35,
        EngineersMaximum = 18,
        EngineerSuppressionPerFactory = 1.5,
        EngineerSuppressionMinimum = 45,
    },
}
lethalSites = {}
engineerSurvival = {
    IsRetreating = function(unit) return unit.RedQueenRetreatPosition ~= nil end,
    RememberLethalSite = function(brain, position, reason)
        table.insert(lethalSites, { Position = position, Reason = reason })
    end,
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
    elseif path == "/mods/TheRedQueen/lua/AI/RedQueen/EngineerSurvival.lua" then
        return engineerSurvival
    elseif path == "/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua" then
        return logger
    elseif path == "/mods/TheRedQueen/lua/AI/RedQueen/CounterBuilders.lua" then
        if not counterModule then
            counterModule = setmetatable({}, { __index = _G })
            setfenv(assert(loadfile("lua/AI/RedQueen/CounterBuilders.lua")), counterModule)()
        end
        return counterModule
    elseif path == "/mods/TheRedQueen/lua/AI/RedQueen/FortificationBuilders.lua" then
        return {}
    elseif path == "/mods/TheRedQueen/lua/AI/RedQueen/Experimentals.lua" then
        if not experimentalModule then
            -- Same environment-as-module semantics the engine's import uses.
            experimentalModule = setmetatable({}, { __index = _G })
            setfenv(assert(loadfile("lua/AI/RedQueen/Experimentals.lua")), experimentalModule)()
        end
        return experimentalModule
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
    -- AINewExpansionBase hands the engineer to the new base through its own
    -- manager, so a forward-base engineer must always have one.
    BuilderManagerData = { EngineerManager = {} },
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
local gunshipCount = 0
local brain = {
    Army = 1,
    Name = "ARMY_1",
    GetArmyIndex = function() return 1 end,
    GetCurrentUnits = function(_, category)
        local total = 0
        if category.Matches({ AIR = true, MOBILE = true, TRANSPORTFOCUS = true }) then
            total = total + transportCount
        end
        if category.Matches({ AIR = true, MOBILE = true, TRANSPORTFOCUS = true, GROUNDATTACK = true }) then
            total = total + gunshipCount
        end
        return total
    end,
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
        EnergyIncome = 100,
        MassStoredRatio = 0.2,
        EnergyStoredRatio = 0.2,
        MassTrend = 0,
        EnergyTrend = 0,
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
        FocusWeights = { Tech2 = 70 },
    },
}

brain.RedQueenModules = { Economy = economy, World = world, Strategy = strategy }

local module = setmetatable({}, { __index = _G })
setfenv(assert(loadfile("lua/AI/RedQueen/ProductionManager.lua")), module)()
local Create = module.Create

local manager = Create(brain, { FactionIndex = 1, ArmyDeficit = 2 }, world, economy, {}, strategy)
assert(manager:FindForwardEngineer() == engineer, "destroyed ArmyPool engineers must be skipped safely")

-- Base managers are the real engineer supply: EngineerManager:AddUnit claims
-- every new engineer, so ArmyPool holds one or two in transit. Sourcing only
-- from the pool blocked 82 forward-base attempts on no-idle-engineer.
local function ManagedEngineer(entityId, tier, idle)
    return {
        EntityId = entityId,
        IsEngineer = true,
        IsCommander = false,
        BuilderManagerData = { EngineerManager = {} },
        IsIdleState = function() return idle end,
        CanBuild = function() return true end,
        GetBlueprint = function()
            return { CategoriesHash = { ["TECH" .. tostring(tier)] = true } }
        end,
    }
end

local baseEngineers = {}
local sourceManager = {
    GetUnits = function() return baseEngineers end,
    GetLocationCoords = function() return { 64, 0, 64 } end,
}
brain.BuilderManagers.SOURCE = { EngineerManager = sourceManager }

-- At the retention floor nothing may be taken: a base must keep working.
baseEngineers = { ManagedEngineer(60, 3, false), ManagedEngineer(61, 3, false) }
poolUnits = { commander, destroyedEngineer }
assert(
    manager:FindForwardEngineer() == nil,
    "a base at its engineer retention floor must not be stripped"
)

-- Above the floor the surplus becomes available, even though none is idle.
baseEngineers = {
    ManagedEngineer(60, 3, false), ManagedEngineer(61, 3, false),
    ManagedEngineer(62, 3, false),
}
local sourced = manager:FindForwardEngineer()
assert(sourced, "a base above its retention floor must supply a forward-base engineer")
assert(sourced.EntityId == 60, "manager sourcing must be deterministic")

-- An idle engineer costs nothing to take, so it wins over a busy higher tier.
baseEngineers = {
    ManagedEngineer(60, 3, false), ManagedEngineer(61, 3, false),
    ManagedEngineer(62, 3, false), ManagedEngineer(63, 1, true),
}
assert(
    manager:FindForwardEngineer().EntityId == 63,
    "an idle engineer must be preferred over one taken off base duty"
)

-- Emergency defense outranks forward-base construction.
baseEngineers[4].RedQueenEmergencyDefenseUntil = 100000
assert(
    manager:FindForwardEngineer().EntityId ~= 63,
    "an engineer held for emergency defense must not be taken"
)

brain.BuilderManagers.SOURCE = nil
poolUnits = { commander, engineer, destroyedEngineer }
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
assert(captured[5] == true, "unshifted capacity templates require relative placement")
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

-- An engineer told to build a factory must not then be told to guard one.
-- Update runs TryExpandFactoryCapacity before UpdateFactoryAssistance, and
-- IssueGuard replaces the build order that was just queued. With a single
-- engineer in the pool that produced five expansion requests and no factory at
-- all in the Red Queen versus stock Adaptive rematch.
manager.FactoryAssistants = {}
assistEngineer.RedQueenFactoryAssistUntil = nil
assistEngineer.RedQueenProductionBuildUntil = GetGameTick() + 600
local guardedBeforeHold = table.getn(guarded)
manager:UpdateFactoryAssistance({ activeFactory })
assert(
    table.getn(guarded) == guardedBeforeHold,
    "an engineer holding a factory build order must not be reassigned to assist"
)
assert(
    not manager.FactoryAssistants[assistEngineer.EntityId],
    "a builder mid-factory must not be tracked as an assistant"
)

-- The hold expires, and the engineer returns to the assistant pool.
assistEngineer.RedQueenProductionBuildUntil = GetGameTick() - 1
manager:UpdateFactoryAssistance({ activeFactory })
assert(
    manager.FactoryAssistants[assistEngineer.EntityId],
    "an expired production hold must return the engineer to assistance"
)
assistEngineer.RedQueenProductionBuildUntil = nil

-- Factory expansion draws from base managers too. Searching only ArmyPool left
-- four Red Queen subsystems contending for the one engineer FAF leaves there,
-- and several of them clear commands, so queued factories kept being cancelled.
local expansionBaseEngineers = {}
brain.BuilderManagers.EXPANSION_SOURCE = {
    EngineerManager = {
        GetUnits = function() return expansionBaseEngineers end,
        GetLocationCoords = function() return { 64, 0, 64 } end,
    },
}
local function ManagedBuilder(entityId, tier, idle, canBuild)
    return {
        EntityId = entityId,
        IsEngineer = true,
        IsCommander = false,
        BuilderManagerData = { EngineerManager = {} },
        IsIdleState = function() return idle end,
        CanBuild = function() return canBuild end,
        GetBlueprint = function()
            return { CategoriesHash = { ["TECH" .. tostring(tier)] = true } }
        end,
    }
end

poolUnits = { commander, destroyedEngineer }
expansionBaseEngineers = {}
assert(
    manager:FindIdleBuilder("uel0101") == nil,
    "an empty pool and no spare base engineer must yield no builder"
)

-- Above the retention floor an idle base engineer becomes available.
expansionBaseEngineers = {
    ManagedBuilder(70, 1, false, true),
    ManagedBuilder(71, 1, false, true),
    ManagedBuilder(72, 1, true, true),
}
local picked = manager:FindIdleBuilder("uel0101")
assert(picked, "factory expansion must source an idle engineer from a base manager")
assert(picked.EntityId == 72, "only the idle engineer may be taken for factory expansion")

-- A busy engineer is a fallback, not a disqualification. Every engineer in an
-- instrumented run reported idle=no for every sample, so requiring idle finds
-- nobody and expansion never fires at all.
expansionBaseEngineers = {
    ManagedBuilder(76, 1, false, true),
    ManagedBuilder(77, 1, false, true),
    ManagedBuilder(78, 1, false, true),
}
assert(
    manager:FindIdleBuilder("uel0101") ~= nil,
    "with no idle engineer available a busy one must still be usable"
)

-- A builder that cannot make the requested structure is never selected.
expansionBaseEngineers = {
    ManagedBuilder(73, 1, true, false),
    ManagedBuilder(74, 1, true, false),
    ManagedBuilder(75, 1, true, false),
}
assert(
    manager:FindIdleBuilder("uel0101") == nil,
    "an engineer that cannot build the structure must never be selected"
)

brain.BuilderManagers.EXPANSION_SOURCE = nil
-- Restore the state the defense-alert release test below expects.
poolUnits = { assistEngineer }

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
local t1LandFactory = {
    GetBlueprint = function()
        return { CategoriesHash = { LAND = true, FACTORY = true, TECH1 = true } }
    end,
}
manager:UpdateTierPolicy({ t1LandFactory })
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
-- Check both native upgrade builders and production against the same state.
local t2Condition = counterDefinitions["Red Queen T1 Land Factory Tech"].BuilderConditions[1][1]
local function CheckFallback(expectedUpgrade, message)
    manager:ApplyTierPolicy()
    assert((t2Condition(brain) or false) == expectedUpgrade, message .. " (upgrade)")
    assert(mainlineBuilder.Priority == (expectedUpgrade and 0 or 500), message .. " (production)")
end
economy.State.MassIncome = 4
economy.State.EnergyIncome = 10
CheckFallback(false, "4 mass and 10 energy cannot support a T2 upgrade")
economy.State.EnergyIncome = 60
CheckFallback(true, "meeting the exact income thresholds permits the upgrade")
strategy.ProductionDemand.DefenseAlert.Active = true
CheckFallback(false, "an active defense alert preserves fallback production")
strategy.ProductionDemand.DefenseAlert.Active = false
economy.State.MassStoredRatio = 0.09
economy.State.MassTrend = -1
CheckFallback(false, "low mass reserves with a negative trend block suppression")
economy.State.MassTrend = 0
CheckFallback(true, "a balanced trend permits low reserves")
economy.State.EnergyStoredRatio = 0.14
economy.State.EnergyTrend = -1
CheckFallback(false, "low energy reserves with a negative trend block suppression")
economy.State.EnergyStoredRatio = 0.15
CheckFallback(true, "adequate energy reserves permit a negative trend")
economy.State.EnergyTrend = 0
strategy.ProductionDemand.FocusWeights.Tech2 = 34
CheckFallback(false, "insufficient T2 focus preserves fallback production")
strategy.ProductionDemand.FocusWeights.Tech2 = 70
world.MapType = "Naval"
CheckFallback(false, "a naval map cannot suppress land production for an irrelevant upgrade")
world.MapType = "Land"
CheckFallback(true, "restoring upgrade eligibility suppresses T1 mainline")
for _, domain in ipairs({ "Air", "Naval" }) do
    local condition = counterDefinitions["Red Queen T1 " .. domain .. " Factory Tech"].BuilderConditions[1][1]
    local profile = { Tier = 1, Domain = domain, Role = "Mainline" }
    for _, mapType in ipairs({ "Land", "Naval" }) do
        world.MapType = mapType
        local expected = domain == "Air" or mapType == "Naval"
        assert((condition(brain) or false) == expected, "upgrade relevance must match the domain and map")
        assert(manager:IsObsoleteProfile(profile) == expected, "suppression must use its own domain's eligibility")
    end
end
world.MapType = "Land"

economy.State.MassIncome = 1
economy.State.SmoothedMassIncome = 1
manager:ApplyTierPolicy()
assert(
    mainlineBuilder.Priority == 500,
    "suppression must not apply when the Tech 2 upgrade is unaffordable"
)

-- Exercise blueprint classification rather than supplying preclassified roles.
__blueprints = {
    uel0104 = { CategoriesHash = { UEF = true, LAND = true, MOBILE = true, TECH1 = true, ANTIAIR = true } },
    uea0203 = { CategoriesHash = { UEF = true, AIR = true, MOBILE = true, TECH2 = true,
        GROUNDATTACK = true, TRANSPORTFOCUS = true, TRANSPORTATION = true } },
    uea0104 = { CategoriesHash = { UEF = true, AIR = true, MOBILE = true, TECH1 = true,
        TRANSPORTFOCUS = true, TRANSPORTATION = true } },
}
PlatoonTemplates = {}
local function BlueprintBuilder(blueprintId, priority)
    PlatoonTemplates[blueprintId] = { FactionSquads = { UEF = { { blueprintId } } } }
    return {
        Priority = priority,
        GetPlatoonTemplate = function() return blueprintId end,
        SetPriority = function(self, value) self.Priority = value end,
    }
end
function EntityCategoryGetUnitList(category)
    local result = {}
    for blueprintId, blueprint in pairs(__blueprints) do
        if category.Matches(blueprint.CategoriesHash) then
            table.insert(result, blueprintId)
        end
    end
    return result
end
local aaBuilder = BlueprintBuilder("uel0104", 450)
table.insert(brain.BuilderManagers.MAIN.FactoryManager.BuilderData.Land.Builders, aaBuilder)
economy.State.MassIncome = 20
manager:ApplyTierPolicy()
assert(mainlineBuilder.Priority == 0, "the AA regression must run with mainline suppression active")
assert(aaBuilder.Priority == 450, "T1 mobile AA must survive mainline suppression")
manager:UpdateTierPolicy({ t3LandFactory })
manager:ApplyTierPolicy()
assert(aaBuilder.Priority == 450, "AA must remain eligible without a same-domain replacement")
__blueprints.uel0205 = { CategoriesHash = { UEF = true, LAND = true, MOBILE = true, TECH2 = true, ANTIAIR = true } }
manager.RoleAvailability = {}
manager:ApplyTierPolicy()
assert(aaBuilder.Priority == 0, "an available higher-tier ground AA replacement retires T1 AA")
manager:UpdateTierPolicy({})

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
local transportBuilder = BlueprintBuilder("uea0104", 400)
local gunshipBuilder = BlueprintBuilder("uea0203", 800)
brain.BuilderManagers.MAIN.FactoryManager.BuilderData.Air = {
    Builders = { transportBuilder, gunshipBuilder },
}
gunshipCount = 10
manager:UpdateTierPolicy({})
manager:ApplyTierPolicy()
assert(manager.TransportCount == 0, "ten UEF gunships must not consume the transport budget")
assert(transportBuilder.Priority == 400, "gunships must not stop genuine transport production")
assert(not manager:HasRoleAtTier("Air", "Transport", 2), "a gunship is not a T2 transport replacement")
assert(manager:HasRoleAtTier("Air", "GroundAttack", 2), "the UEF gunship provides ground attack")
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
assert(gunshipBuilder.Priority == 800, "a full transport fleet must not disable the UEF gunship builder")
transportCount = 4
manager:UpdateTierPolicy({})
manager:ApplyTierPolicy()
assert(
    transportBuilder.Priority == 400,
    "losing transports must restore production below the budget"
)
brain.BuilderManagers.MAIN.FactoryManager.BuilderData.Air = nil
transportCount = 0
gunshipCount = 0

local pruneManager = Create(brain, {}, world, economy, {}, strategy)
for _, state in ipairs({ "Preparing", "Building", "Established" }) do
    for _, reverse in ipairs({ false, true }) do
        local expired = { State = "Destroyed", SiteName = "Rebuilt", DestroyedTick = -2000 }
        local replacement = { State = state, SiteName = "Rebuilt" }
        pruneManager.ForwardBases = reverse and { replacement, expired } or { expired, replacement }
        pruneManager.ForwardBaseClaims = { Rebuilt = true }
        pruneManager:PruneForwardBaseRecords()
        assert(table.getn(pruneManager.ForwardBases) == 1, "the expired record must be pruned at retention")
        assert(pruneManager.ForwardBases[1] == replacement, "the replacement record must remain")
        assert(pruneManager.ForwardBaseClaims.Rebuilt, "a retained live replacement must keep its marker claim")
    end
end
pruneManager.ForwardBases = {
    { State = "Failed", SiteName = "Expired", FailedTick = -2000 },
    { State = "Destroyed", SiteName = "Recent", DestroyedTick = -1999 },
}
pruneManager.ForwardBaseClaims = { Expired = true, Recent = true }
pruneManager:PruneForwardBaseRecords()
assert(not pruneManager.ForwardBaseClaims.Expired, "an expired unowned site must release its claim")
assert(pruneManager.ForwardBaseClaims.Recent, "a terminal record within retention keeps its claim")

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
manager.ForwardBaseClaims[capturedRecord.SiteName] = capturedRecord
manager:UpdateForwardBaseStatus()
assert(capturedRecord.State == "Destroyed", "captured factories must invalidate established bases")
assert(not capturedRecord.FactoryPresent, "captured or allied factories must not satisfy ownership checks")
assert(not manager.ForwardBaseClaims[capturedRecord.SiteName], "captured bases must release their marker claim")

-- An engineer already walking to a site must be turned around when the route
-- stops being safe.
--
-- A single assessment at dispatch cannot carry the journey: observed walks ran
-- 75 to 175 seconds while intel lives 180, so the picture that authorised the
-- trip is about as old as the trip. The engineers that died were dispatched on
-- routes at coverage 1.00 and well inside the limit -- the assessment was not
-- wrong, it simply stopped being true.
local recallCleared = {}
local recallMoved = {}
local killedRecallThreads = {}
function KillThread(thread) killedRecallThreads[thread] = true end
function IssueClearCommands(units)
    local unit = units[1]
    assert(not unit.ProcessBuild and not unit.NotBuildingThread,
        "native build threads must be stopped before clearing engine orders")
    assert(not unit.EngineerBuildQueue or #unit.EngineerBuildQueue == 0,
        "clearing orders must not leave queued structures for callbacks to retry")
    table.insert(recallCleared, unit)
end
function IssueMove(units, destination)
    assert(not units[1].PlatoonHandle, "release construction ownership before returning home")
    table.insert(recallMoved, destination)
end

local transitEngineer = {
    EntityId = 44,
    GetPosition = function() return { 600, 0, 600 } end,
    GetBlueprint = function() return { CategoriesHash = { TECH1 = true } } end,
}
local routeDanger = 0
-- Declared before assignment: the closure below refers to the table, and a
-- `local x = { ... x ... }` initializer cannot see x yet.
local recallWorld
recallWorld = {
    StartPosition = { 100, 0, 100 },
    GetMaximumForwardBases = function() return 2 end,
    GetObservedRouteThreat = function(_, origin, destination, intel, radius, layer)
        recallWorld.AskedLayer = layer
        if routeDanger < 0 then
            return nil, 0
        end
        return routeDanger, 1
    end,
}
local recallStrategy = {
    CurrentObjective = { Type = "Pressure", Position = { 900, 0, 900 } },
    ProductionDemand = { DefenseAlert = { Active = false }, ForwardBasePlan = {} },
    GetOwnThreatNear = function() return 20 end,
}
local function transitAttempt(danger, sinceCheck)
    routeDanger = danger
    local watcher = Create(brain, { FactionIndex = 1 }, recallWorld,
        routeEconomy, {}, recallStrategy)
    local record = {
        Name = "RQFB_TRANSIT",
        SiteName = "MassCluster9",
        Position = { 800, 0, 800 },
        Layer = "Hover",
        RouteThreat = 1.0,
        Engineer = transitEngineer,
        Tech = 1,
        StartTick = GetGameTick() - 300,
        State = "Building",
        Queued = 6,
        RouteCheckedTick = sinceCheck and GetGameTick() or nil,
    }
    watcher.ForwardBases = { record }
    watcher.ForwardBaseActive = record
    watcher.ForwardBaseClaims = { [record.SiteName] = record }
    watcher.FindForwardBaseFactory = function() return nil end
    watcher.RevalidateEstablishedForwardBases = function() end
    brain.BuilderManagers.RQFB_TRANSIT = { EngineerManager = {} }
    watcher:UpdateForwardBaseStatus()
    return record
end

-- Safe enough: the escort is 20, so the dispatch limit is 12 and the recall
-- margin puts the turn-around point at 18.
local held = transitAttempt(5)
assert(held.State == "Building", "a route still within the margin must not turn an engineer around")
assert(table.getn(recallCleared) == 0, "nothing should be recalled while the route holds")
assert(recallWorld.AskedLayer == "Hover",
    "the re-check must use the layer the engineer travels, not the land graph")

-- The margin is what stops an already-committed engineer thrashing. Escort 20
-- gives a dispatch limit of 12, so a route at 15 would have been refused at
-- dispatch, yet is not worth abandoning a walk already underway for.
local marginal = transitAttempt(15)
assert(marginal.State == "Building",
    "a route inside the recall margin must not turn a committed engineer around")
assert(table.getn(recallCleared) == 0, "and nothing should be recalled for it")

-- Now the route has become dangerous while the engineer is still walking.
recallCleared = {}
recallMoved = {}
local nativeTransit, nativeWatch, nativeAssignment, disbandAssignment = {}, {}, {}, {}
transitEngineer.EngineerBuildQueue = { { "ueb0101", { 800, 800, 0 }, false } }
transitEngineer.ProcessBuild = nativeTransit
transitEngineer.NotBuildingThread = nativeWatch
transitEngineer.ProcessBuildDone = true
transitEngineer.ForkedEngineerTask = nativeAssignment
local buildDisbanded = false
transitEngineer.PlatoonHandle = {
    PlatoonDisband = function()
        assert(killedRecallThreads[nativeTransit] and killedRecallThreads[nativeWatch],
            "kill suspended native transit and retry coroutines before disbanding")
        assert(killedRecallThreads[nativeAssignment], "cancel the prior native assignment before disband")
        assert(transitEngineer.RedQueenRetreatPosition, "hold reassignment before disband callbacks")
        transitEngineer.ForkedEngineerTask = disbandAssignment
        transitEngineer.PlatoonHandle = nil
        buildDisbanded = true
    end,
}
local turned = transitAttempt(40)
assert(killedRecallThreads[disbandAssignment] and not transitEngineer.ForkedEngineerTask,
    "cancel the native task newly created by disband before moving")
assert(turned.State == "Failed" and turned.Failure == "route-unsafe",
    "a route that became unsafe in transit must fail the base, got "
        .. tostring(turned.Failure))
assert(recallCleared[1] == transitEngineer,
    "the engineer's queued structures must be cleared so it is released")
assert(recallMoved[1], "and it must be sent somewhere rather than left standing")
assert(buildDisbanded and not transitEngineer.ProcessBuildDone,
    "recall must disband the native build task and clear its completion state")

-- A route that no longer exists on the engineer's own graph is not a judgement
-- call.
recallCleared = {}
local stranded = transitAttempt(-1)
assert(stranded.Failure == "route-lost",
    "a vanished route must be reported distinctly from a dangerous one")

-- The re-check is throttled, so a committed engineer is not re-judged every
-- cycle.
recallCleared = {}
local throttled = transitAttempt(40, true)
assert(throttled.State == "Building",
    "a base re-checked this cycle must not be judged again immediately")
assert(table.getn(recallCleared) == 0, "throttling must prevent a recall too")

local remoteEngineerPosition = { 700, 0, 700 }
local routeEngineerMotion = "RULEUMT_AmphibiousFloating"
local routeEngineer = {
    EntityId = 20,
    IsEngineer = true,
    IsCommander = false,
    BuilderManagerData = { EngineerManager = {} },
    IsIdleState = function() return true end,
    GetPosition = function() return remoteEngineerPosition end,
    GetBlueprint = function()
        return {
            CategoriesHash = { TECH2 = true },
            -- Real engineers are never land-only: UEF and Cybran float, Aeon
            -- and Seraphim hover, at all three tiers.
            Physics = { MotionType = routeEngineerMotion },
        }
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
routeManager.ForwardBaseClaims[staleRecord.SiteName] = staleRecord
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

-- A persistent Defend objective is not evidence that an expansion route is
-- unsafe. Preserve recovery, economic and active-defense reservations, but let
-- the site selector decide route safety for Defend just as it does for Pressure.
local selectedLayer
local function ExpansionAttempt(objectiveType, safeSite, alert, stall)
    local selected = false
    local started = false
    local candidateWorld = {
        GetMaximumForwardBases = function() return 2 end,
        SelectForwardBaseSite = function(_, origin, objective, intel, claims, escort, rebuildable, layer)
            selected = true
            selectedLayer = layer
            assert(origin == remoteEngineerPosition, "defensive expansion must use the engineer origin")
            assert(escort == 75, "defensive expansion must retain local safety limits")
            return safeSite and replacementSite or nil
        end,
    }
    local candidateStrategy = {
        CurrentObjective = { Type = objectiveType, Position = { 900, 0, 900 } },
        ProductionDemand = { DefenseAlert = { Active = alert } },
        GetOwnThreatNear = routeStrategy.GetOwnThreatNear,
    }
    local attempt = Create(routeBrain, { FactionIndex = 1 }, candidateWorld,
        routeEconomy, {}, candidateStrategy)
    attempt.FindForwardEngineer = function() return routeEngineer end
    attempt.StartForwardBase = function(_, engineer, site)
        assert(engineer == routeEngineer and site == replacementSite)
        started = true
        return true
    end
    routeEconomy.State.StallRisk = stall or false
    attempt:UpdateForwardBases()
    routeEconomy.State.StallRisk = false
    return selected, started, attempt.LastForwardBaseBlockReason
end
for _, objectiveType in ipairs({ "Pressure", "Defend" }) do
    local selected, started = ExpansionAttempt(objectiveType, true, false)
    assert(selected and started, "safe expansion must start during " .. objectiveType)
    local _, unsafeStarted, reason = ExpansionAttempt(objectiveType, false, false)
    assert(not unsafeStarted and reason == "no-safe-site", "unsafe routes must block expansion")
end
for _, objectiveType in ipairs({ "Stage", "Recover" }) do
    local selected, started = ExpansionAttempt(objectiveType, true, false)
    assert(not selected and not started, "opening and recovery reservations must remain")
end
local _, alertStarted, alertReason = ExpansionAttempt("Defend", true, true)
assert(not alertStarted and alertReason == "defense-alert", "active emergency defense must retain engineers")
local _, stallStarted, stallReason = ExpansionAttempt("Defend", true, false, true)
assert(not stallStarted and stallReason == "stall-risk", "defensive expansion must remain affordable")

-- The route must be judged on the graph the engineer actually travels. Passing
-- a hardcoded "Land" leaves the layer-aware site selection inert, and no
-- engineer in the game is land-only.
routeEngineerMotion = "RULEUMT_AmphibiousFloating"
ExpansionAttempt("Pressure", true, false)
assert(selectedLayer == "Amphibious",
    "a floating engineer must be routed on the amphibious graph, got " .. tostring(selectedLayer))
routeEngineerMotion = "RULEUMT_Hover"
ExpansionAttempt("Pressure", true, false)
assert(selectedLayer == "Hover",
    "a hover engineer must be routed on the hover graph, got " .. tostring(selectedLayer))
routeEngineerMotion = "RULEUMT_Land"
ExpansionAttempt("Pressure", true, false)
assert(selectedLayer == "Land", "a genuinely land-bound builder still uses the land graph")
routeEngineerMotion = "RULEUMT_AmphibiousFloating"

-- Shore artillery placement. The 50 minimum radius is a dead zone around the
-- gun, not around the base, so the battery is set back from the threat: that
-- widens what it covers instead of blinding it.
local artilleryAnchor = { 100, 0, 100 }
local artilleryPosition = manager:ShoreArtilleryPosition({
    AnchorPosition = artilleryAnchor,
    Position = { 100, 0, 40 },
})
assert(artilleryPosition[3] > artilleryAnchor[3],
    "artillery must be placed away from the threat, not between the base and it")
assert(math.abs(artilleryPosition[3] - 125) < 0.01 and math.abs(artilleryPosition[1] - 100) < 0.01,
    "the battery must sit one rear offset directly behind the anchor")

local diagonal = manager:ShoreArtilleryPosition({
    AnchorPosition = artilleryAnchor,
    Position = { 40, 0, 40 },
})
local dx = diagonal[1] - artilleryAnchor[1]
local dz = diagonal[3] - artilleryAnchor[3]
assert(math.abs(math.sqrt(dx * dx + dz * dz) - 25) < 0.01,
    "the offset must be normalised, so a diagonal threat moves the gun the same distance")

assert(manager:ShoreArtilleryPosition({ AnchorPosition = artilleryAnchor }) == artilleryAnchor,
    "with no observed threat position the anchor itself must be used")
local coincident = manager:ShoreArtilleryPosition({
    AnchorPosition = artilleryAnchor,
    Position = artilleryAnchor,
})
assert(coincident == artilleryAnchor, "a threat on top of the anchor must not divide by zero")

-- A commander anchor walks, so a structure quota measured around it never fills
-- and the build is reissued every cooldown. On SCMP_037 that put nine artillery
-- pieces and fourteen torpedo launchers -- about half of all production -- into
-- static defence while the match was lost.
local staticAnchorAttempts = {}
manager.Economy = { State = { StallRisk = false, MassIncome = 10 } }
manager.Brain.GetNumUnitsAroundPoint = function() return 0 end
manager.FindEmergencyDefenseEngineer = function(_, _, blueprintId)
    staticAnchorAttempts[blueprintId] = true
    return nil
end
local function attempted(blueprintId) return staticAnchorAttempts[blueprintId] == true end
manager.Strategy.ProductionDemand.DefenseAlert = {
    Active = true,
    AnchorKind = "Commander",
    AnchorPosition = { 100, 0, 100 },
    Position = { 100, 0, 40 },
    WaterPosition = { 120, 0, 100 },
    Targets = { Artillery = 4, Torpedo = 4 },
}
manager.LastShoreArtilleryTick = -100000
manager.LastShoreTorpedoTick = -100000
manager:UpdateShoreArtillery({})
manager:UpdateShoreTorpedo({})
assert(not next(staticAnchorAttempts),
    "a walking commander anchor must not host static defences")

manager.Strategy.ProductionDemand.DefenseAlert.AnchorKind = "NavalBase"
manager.LastShoreArtilleryTick = -100000
manager.LastShoreTorpedoTick = -100000
manager:UpdateShoreArtillery({})
manager:UpdateShoreTorpedo({})
assert(attempted("ueb2303"), "a static base anchor must still site shore artillery")
assert(attempted("ueb2205"), "a static base anchor must still site torpedo defences")

-- The torpedo quota must be measured from the static anchor, not from the water
-- position, which is re-probed toward the moving enemy fleet each alert. Count
-- from a drifting point and standing launchers fall outside the window, so the
-- quota never fills: SCMP_037 logged `current=0 target=2` six times at one
-- anchor while launchers were already built.
local countedAt = nil
local torpedoAnchor = { 200, 0, 200 }
manager.Brain.GetNumUnitsAroundPoint = function(_, _, position, radius)
    countedAt = { position, radius }
    return 0
end
manager.Strategy.ProductionDemand.DefenseAlert = {
    Active = true,
    AnchorKind = "NavalBase",
    AnchorPosition = torpedoAnchor,
    Position = { 200, 0, 120 },
    WaterPosition = { 244, 0, 200 },
    Targets = { Torpedo = 2 },
}
manager.LastShoreTorpedoTick = -100000
manager:UpdateShoreTorpedo({})
assert(countedAt, "the torpedo quota must be counted")
assert(countedAt[1] == torpedoAnchor,
    "existing torpedo cover must be counted from the static anchor, not the drifting water site")
assert(countedAt[2] >= 48,
    "the count radius must cover the whole water-probe area or the drift returns at its edge")

-- Each response holds its own cooldown. Point defence is deliberately the first
-- call on the same engineers and the same mass, and Targets.Ground is keyed on
-- land + naval so a fleet shelling the base raises a defence at all. But a
-- destroyer at 60 to 80 outranges point defence -- 26 at Tech 1, 50 at Tech 2 --
-- and the launchers that do reach it must not be locked out by the point
-- defence that just built. Three separate timers is what makes that true, and
-- nothing else pinned it: folding them into one shared tick would silently let
-- point defence starve the only answer to a standoff fleet.
staticAnchorAttempts = {}
manager.Strategy.ProductionDemand.DefenseAlert = {
    Active = true,
    AnchorKind = "NavalBase",
    AnchorPosition = torpedoAnchor,
    Position = { 200, 0, 120 },
    WaterPosition = { 244, 0, 200 },
    Targets = { Ground = 8, Torpedo = 4 },
}
-- Point defence has just built and stamped its own cooldown.
manager.LastEmergencyDefenseTick = GetGameTick()
manager.LastShoreTorpedoTick = -100000
manager:UpdateShoreTorpedo({})
assert(attempted("ueb2205"),
    "a torpedo launcher must still be sited in the window the point defence just built in")

-- Artillery is a late supplement, never a first response. Two independent
-- brakes: the economy must have reached the late game, and the anchor's primary
-- point defence must already be standing. Building it early put eight batteries
-- on a dry map and turned a controlled Sentry Point victory into a defeat.
local artilleryTried
local function TryArtillery(massIncome, groundBuilt, groundTarget)
    artilleryTried = false
    manager.Economy = { State = { StallRisk = false, MassIncome = massIncome } }
    manager.Brain.GetNumUnitsAroundPoint = function(_, category, _, _)
        -- Distinguish the point-defence query from the existing-artillery one.
        if category.Matches and category.Matches({
            STRUCTURE = true, DEFENSE = true, DIRECTFIRE = true,
        }) then
            return groundBuilt
        end
        return 0
    end
    manager.FindEmergencyDefenseEngineer = function() artilleryTried = true; return nil end
    manager.Strategy.ProductionDemand.DefenseAlert = {
        Active = true, AnchorKind = "NavalBase",
        AnchorPosition = { 100, 0, 100 }, Position = { 100, 0, 40 },
        Targets = { Artillery = 4, Ground = groundTarget },
    }
    manager.LastShoreArtilleryTick = -100000
    manager:UpdateShoreArtillery({})
    return artilleryTried
end

-- The economic ladder, using the same thresholds that gate Tech 3 and above.
assert(not TryArtillery(9, 99, 0), "below the Tech 3 economy artillery must not be built at all")
assert(TryArtillery(10, 99, 0), "a Tech 3 economy must permit a first battery")
assert(TryArtillery(30, 99, 0), "a late-game economy must permit artillery")

-- Supplemental: primary point defence comes first on the same mass.
assert(not TryArtillery(30, 1, 4),
    "artillery must wait while the anchor's defensive line is barely started")
assert(TryArtillery(30, 2, 4),
    "an established line -- half the point-defence target -- may be supplemented")
assert(TryArtillery(30, 4, 4),
    "a complete line may certainly be supplemented")

-- Both shore structures must measure their quota from the fixed anchor. The
-- torpedo site is probed toward the fleet and the artillery site is offset away
-- from it, so both build points move with the enemy; counting there loses sight
-- of what is already standing and the build is reissued forever.
local artilleryCountedAt = nil
manager.Economy = { State = { StallRisk = false, MassIncome = 30 } }
manager.Brain.GetNumUnitsAroundPoint = function(_, category, position)
    if category.Matches and category.Matches({ STRUCTURE = true, ARTILLERY = true }) then
        artilleryCountedAt = position
    end
    return 99
end
manager.FindEmergencyDefenseEngineer = function() return nil end
local artAnchor = { 300, 0, 300 }
manager.Strategy.ProductionDemand.DefenseAlert = {
    Active = true, AnchorKind = "NavalBase",
    AnchorPosition = artAnchor, Position = { 300, 0, 200 },
    Targets = { Artillery = 4, Ground = 0 },
}
manager.LastShoreArtilleryTick = -100000
manager:UpdateShoreArtillery({})
assert(artilleryCountedAt == artAnchor,
    "artillery cover must be counted from the static anchor, not the drifting offset site")

-- A Tech 3 upgrade is a Tech 3 unit from the instant it starts, but cannot
-- build for the ~219 simulation seconds it takes to finish. Counting it as
-- readiness suppressed every lower-tier combat builder for that whole window on
-- Fields of Isis. It must still count toward capacity, or planning orders a
-- duplicate of the factory already building.
local function Factory(domainCategory, tier, fraction)
    return {
        GetBlueprint = function()
            return { CategoriesHash = {
                [domainCategory] = true, STRUCTURE = true, FACTORY = true,
                ["TECH" .. tostring(tier)] = true,
            } }
        end,
        GetFractionComplete = function() return fraction end,
    }
end

-- Quantum Gateways have FACTORY/TECH3/GATE, but no combat domain. Keeping one
-- after the last real T3 land factory dies must restore surviving production
-- and leave room for the replacement factory under both tier policies.
do
    local gateway = {
        GetBlueprint = function()
            return { CategoriesHash = {
                FACTORY = true, GATE = true, PRODUCTSC1 = true,
                RALLYPOINT = true, STRUCTURE = true, TECH3 = true, UEF = true,
            } }
        end,
        GetFractionComplete = function() return 1 end,
    }
    for _, readiness in ipairs({ true, false }) do
        for _, survivingTier in ipairs({ 1, 2 }) do
            local mainline = {
                Priority = 700,
                RedQueenUnitProfile = { Domain = "Land", Role = "Mainline", Tier = survivingTier },
            }
            local construction = {
                Priority = 500,
                RedQueenConstructionTypes = { "T1LandFactory" },
            }
            local supportCommander = { Priority = 900 }
            local quantumConstruction = {
                Priority = 910,
                RedQueenConstructionTypes = { "T3QuantumGate" },
            }
            local advanced = Factory("LAND", 3, 1)
            local inventory = { Factory("LAND", survivingTier, 1), advanced, gateway }
            local testBrain = {
                GetListOfUnits = function() return inventory end,
                RedQueenProfile = { Flag = function() return readiness end },
                BuilderManagers = { MAIN = {
                    FactoryManager = { BuilderData = {
                        Land = { Builders = { mainline } },
                        Gate = { Builders = { supportCommander } },
                    } },
                    EngineerManager = { BuilderData = {
                        Any = { Builders = { construction, quantumConstruction } },
                    } },
                } },
            }
            local testManager = Create(testBrain, { FactionIndex = 1 },
                { WaterRatio = 0 }, { State = { DesiredFactories = 2 } }, {},
                { ProductionDemand = { Land = 1 } })
            local factories, counts = testManager:CountFactories()
            testManager:UpdateTierPolicy(factories)
            testManager:ApplyTierPolicy()
            testManager:ApplyFactoryCapacityPolicy(counts)
            assert(mainline.Priority == 0 and construction.Priority == 0,
                "a real T3 land factory must suppress lower tiers and satisfy land capacity")

            advanced.Dead = true
            factories, counts = testManager:CountFactories()
            local policy = testManager:UpdateTierPolicy(factories)
            testManager:ApplyTierPolicy()
            local targets = testManager:ApplyFactoryCapacityPolicy(counts)
            assert(policy.Land.Ready == survivingTier and policy.Land.Highest == survivingTier
                and policy.Land.T3 == 0,
                "a surviving gateway must not retain T3 land readiness or capability")
            assert(mainline.Priority == 700 and not mainline.RedQueenTierDisabled,
                "losing the real T3 factory must restore surviving T1/T2 land builders")
            assert(counts.Land == 1 and counts.Total == 1,
                "gateways must not consume domain or total combat factory capacity")
            assert(construction.Priority == 500 and not construction.RedQueenCapacityDisabled,
                "a gateway must not block construction of the second land factory")
            assert(testManager:SelectFactoryType(counts, targets) == "T1LandFactory",
                "direct expansion must still select the missing land factory")
            assert(factories == inventory and supportCommander.Priority == 900
                and quantumConstruction.Priority == 910,
                "the raw factory list and native Gate production must remain available")
        end
    end

    local inventory = {
        gateway, Factory("UNCLASSIFIED", 3, 1),
        Factory("LAND", 1, 1), Factory("AIR", 2, 1), Factory("NAVAL", 3, 0.4),
    }
    local testManager = Create({ GetListOfUnits = function() return inventory end },
        { FactionIndex = 1 }, {}, {}, {}, { ProductionDemand = {} })
    local factories, counts = testManager:CountFactories()
    local policy = testManager:UpdateTierPolicy(factories)
    assert(counts.Total == 3 and counts.Land == 1 and counts.Air == 1 and counts.Naval == 1,
        "only explicit combat domains count, including unfinished factories")
    assert(policy.Land.Highest == 1 and policy.Air.Ready == 2
        and policy.Naval.Highest == 3 and policy.Naval.Ready == 1,
        "domainless factories must not affect tiers or completed-factory readiness")
end

local upgrading = manager:UpdateTierPolicy({
    Factory("LAND", 2, 1.0),
    Factory("LAND", 3, 0.4),
})
assert(upgrading.Land.Ready == 2,
    "an unfinished Tech 3 factory must not yet obsolete Tech 2 production")
assert(upgrading.Land.Highest == 3,
    "capability must not dip while a factory upgrades, or the exact-match "
    .. "dominance gates thrash between tiers")
assert(upgrading.Land.T3 == 1,
    "an unfinished Tech 3 factory must still count toward capacity planning")

local finished = manager:UpdateTierPolicy({
    Factory("LAND", 2, 1.0),
    Factory("LAND", 3, 1.0),
})
assert(finished.Land.Ready == 3 and finished.Land.Highest == 3,
    "a completed Tech 3 factory must raise both capability and readiness")

-- A unit stub without the accessor must not be treated as unfinished.
local legacy = manager:UpdateTierPolicy({
    { GetBlueprint = function()
        return { CategoriesHash = { AIR = true, STRUCTURE = true, FACTORY = true, TECH2 = true } }
    end },
})
assert(legacy.Air.Ready == 2, "a factory that cannot report progress must count as complete")

-- Which figure obsoletes production is a profile behaviour, not a map test at
-- the point of use. Holding lower tiers alive through an upgrade lifted Fields
-- of Isis and was contradicted by Syrtis Major at the same size and terrain, so
-- it stays a flag that can be moved against a recorded baseline.
manager.TierPolicy = { Land = { Highest = 3, Ready = 2 } }

manager.Brain.RedQueenProfile = { Flag = function(_, name)
    return name == "TierReadinessObsolescence"
end }
assert(not manager:IsObsoleteProfile({ Domain = "Land", Role = "Mainline", Tier = 2 }),
    "with the readiness behaviour on, Tech 2 survives an unfinished Tech 3 upgrade")

manager.Brain.RedQueenProfile = { Flag = function() return false end }
assert(manager:IsObsoleteProfile({ Domain = "Land", Role = "Mainline", Tier = 2 }),
    "with it off the capability ceiling decides, so Tech 2 is retired at once")

manager.TierPolicy = { Land = { Highest = 3, Ready = 3 } }
for _, enabled in ipairs({ true, false }) do
    manager.Brain.RedQueenProfile = { Flag = function() return enabled end }
    assert(manager:IsObsoleteProfile({ Domain = "Land", Role = "Mainline", Tier = 1 }),
        "a finished Tech 3 factory must retire Tech 1 production either way")
end

-- A manager built without a profile must still exercise the behaviour, so a
-- contract tests the code rather than the selection.
manager.Brain.RedQueenProfile = nil
manager.TierPolicy = { Land = { Highest = 3, Ready = 2 } }
assert(not manager:IsObsoleteProfile({ Domain = "Land", Role = "Mainline", Tier = 2 }),
    "absent a profile every optional behaviour must be on")

print("Red Queen production manager contracts passed")

-- Engineer production answers the army's target, not the base count.
--
-- FAF's own rule is per location -- "fewer than four here" -- so it scales with
-- how many bases exist rather than with need. Crossfire Canal ran 21 managed
-- bases and reached 101 engineers against a target of 18, spending a 66-mass
-- economy on units that do not fight. Red Queen's own builders already stop at
-- the target; the native ones have to be held too or the target cannot bind.
local engineerBuilder = {
    Priority = 850,
    OriginalPriority = 850,
    GetPlatoonTemplate = function() return "T1BuildEngineer" end,
    -- Stands in for FAF's own recalculation, which would happily restore the
    -- priority every cycle. The guard has to beat it, so the stub must
    -- actually try.
    CalculatePriority = function(self)
        self.Priority = self.OriginalPriority
        return true
    end,
}
local tankBuilder = {
    Priority = 700,
    OriginalPriority = 700,
    GetPlatoonTemplate = function() return "T1LandDFTank" end,
    CalculatePriority = function(self) return false end,
}
PlatoonTemplates = {
    T1BuildEngineer = { FactionSquads = { UEF = { { "uel0105", 1, 1 } } } },
    T1LandDFTank = { FactionSquads = { UEF = { { "uel0201", 1, 1 } } } },
}
__blueprints = {
    uel0105 = { CategoriesHash = { MOBILE = true, LAND = true, ENGINEER = true, TECH1 = true } },
    uel0201 = { CategoriesHash = { MOBILE = true, LAND = true, TECH1 = true } },
}

local engineerDemand = { DesiredEngineers = 18 }
local engineerHeld = 101
local sorted = {}
local engineerBrain = {
    GetArmyIndex = function() return 2 end,
    GetCurrentUnits = function() return engineerHeld end,
    BuilderManagers = {
        MAIN = {
            FactoryManager = {
                BuilderData = { Land = { Builders = { engineerBuilder, tankBuilder } } },
                SortBuilderList = function(_, kind) table.insert(sorted, kind) end,
            },
        },
    },
}
local engineerManagerUnderTest = Create(engineerBrain, { FactionIndex = 1 }, {},
    routeEconomy, {}, { ProductionDemand = engineerDemand })

-- Well over target *and* over the ceiling: native production is suppressed.
local policy = engineerManagerUnderTest:ApplyEngineerPolicy()
assert(policy.Held == 101 and policy.Target == 18, "the policy must report what it saw")
assert(policy.Ceiling and policy.Ceiling >= policy.Target,
    "the cut must be reported, and must never sit below the target it builds toward")
assert(engineerBuilder.Priority == 0, "a surplus must suppress native engineer production")
assert(engineerBuilder.RedQueenEngineerDisabled, "and record why it was suppressed")
assert(tankBuilder.Priority == 700, "combat production must never be touched by it")
assert(policy.Suppressed == 1, "exactly the engineer builder must be counted")

-- FAF's own recalculation must not revive it while the surplus stands. The
-- stub above restores OriginalPriority when called, exactly as the native
-- implementation would, so this isolates the guard's contribution.
engineerBuilder:CalculatePriority({})
assert(engineerBuilder.Priority == 0,
    "native recalculation must not revive a suppressed builder, got "
        .. tostring(engineerBuilder.Priority))
tankBuilder:CalculatePriority({})
assert(tankBuilder.Priority == 700,
    "and an unsuppressed builder must recalculate normally")

-- Losses lift the target above what is held, and production resumes at once.
engineerHeld = 4
engineerManagerUnderTest:ApplyEngineerPolicy()
assert(engineerBuilder.Priority == 850,
    "falling below target must restore native engineer production, got "
        .. tostring(engineerBuilder.Priority))
assert(not engineerBuilder.RedQueenEngineerDisabled, "and clear the suppression flag")

-- Reaching the ceiling is enough to stop building, so the army does not
-- oscillate around it. Read the ceiling from the policy rather than restating a
-- constant: a contract that hardcodes the number passes a stub and proves
-- nothing about what the army does.
local reported = engineerManagerUnderTest:ApplyEngineerPolicy()
engineerHeld = reported.Ceiling
engineerManagerUnderTest:ApplyEngineerPolicy()
assert(engineerBuilder.Priority == 0, "reaching the ceiling is enough to stop building")

-- The counts armies actually hold must never be cut. Measured across ten
-- baseline cells: 24, 35, 44, 51, 53, 55, 56, 63, 66 and one runaway at 101.
-- Putting the floor at the target's own maximum of 18 cut Sentry Point from a
-- natural 53 to exactly 18, taking its income from 32.2 to 7.3, and turned a
-- Seton's victory into a defeat.
engineerHeld = 40
engineerBuilder.Priority = 850
engineerBuilder.RedQueenEngineerDisabled = false
local ordinary = engineerManagerUnderTest:ApplyEngineerPolicy({ Total = 10 })
assert(engineerBuilder.Priority == 850,
    "40 engineers on a ten-factory economy is an ordinary count, not a runaway")
assert(ordinary.Ceiling > 40,
    "the floor must sit above the counts armies hold, got " .. tostring(ordinary.Ceiling))

-- The regression this ceiling exists for: being at or over the *target* is not
-- a reason to stop, because the target is derived from factory count and the
-- engineers are what build factories. Cutting there locked two measured
-- Crossfire cells at 3 engineers and 6 factories, against 15-33 engineers and
-- 26 factories with native production left alone.
engineerHeld = 12
engineerDemand.DesiredEngineers = 3
engineerBuilder.Priority = 850
engineerBuilder.RedQueenEngineerDisabled = false
engineerBuilder.Priority = 850
engineerBuilder.RedQueenEngineerDisabled = false
local opening = engineerManagerUnderTest:ApplyEngineerPolicy({ Total = 4 })
assert(opening.Held > opening.Target,
    "this case is only meaningful while more engineers are held than targeted")
assert(engineerBuilder.Priority == 850,
    "an opening army over its factory-derived target must keep building engineers")
assert(opening.Suppressed == 0, "and nothing may be reported as suppressed")

-- Planned capacity counts as well as built, or the ceiling is the same loop one
-- step removed: an army that intends 40 factories has to be allowed the
-- engineers that will build them before they stand.
engineerHeld = 40
routeEconomy.State.DesiredFactories = 40
local planned = engineerManagerUnderTest:ApplyEngineerPolicy({ Total = 2 })
assert(planned.Ceiling > 18,
    "planned factory capacity must raise the ceiling before the factories exist, got "
        .. tostring(planned.Ceiling))
assert(engineerBuilder.Priority == 850,
    "and native production must not be cut while that build-out is still owed")
routeEconomy.State.DesiredFactories = nil

-- And the ceiling tracks capacity, so a developed economy is trimmed rather
-- than capped: at 40 factories the cut is well above the flat minimum.
engineerHeld = 55
local developed = engineerManagerUnderTest:ApplyEngineerPolicy({ Total = 40 })
assert(developed.Ceiling > 18,
    "the ceiling must rise with what there is to feed, got "
        .. tostring(developed.Ceiling))
assert(engineerBuilder.Priority == 850,
    "55 engineers on a 40-factory economy is not yet a runaway")
engineerHeld = 101
engineerManagerUnderTest:ApplyEngineerPolicy({ Total = 40 })
assert(engineerBuilder.Priority == 0,
    "but a runaway is still cut on a developed economy")
engineerHeld = 101
engineerDemand.DesiredEngineers = 18
engineerBuilder.Priority = 850
engineerBuilder.RedQueenEngineerDisabled = false
engineerManagerUnderTest:ApplyEngineerPolicy()

-- With no target expressed the policy must not touch anything.
engineerHeld = 101
engineerBuilder.Priority = 850
engineerBuilder.RedQueenEngineerDisabled = false
engineerDemand.DesiredEngineers = 0
engineerManagerUnderTest:ApplyEngineerPolicy()
assert(engineerBuilder.Priority == 850,
    "an absent engineer target must leave native production alone")
engineerDemand.DesiredEngineers = 18

-- Engineers already under way are pulled out of danger they are standing in.
--
-- The forward-base path re-checks its own routes, but nothing watched the
-- engineers native builders send to extractors and expansions -- observed in a
-- match as engineers walking into the enemy base. Judged on where the engineer
-- *is*, because that position is known for certain whatever the errand was.
local retreatEngineers, retreatHome = {}, { 0, 0, 0 }
local function retreatUnit(entityId, position)
    return {
        EntityId = entityId,
        Dead = false,
        GetPosition = function() return position end,
        EngineerBuildQueue = { { "T1Resource", 1, 1 } },
        ProcessBuild = "thread-handle",
    }
end
local retreatThreatAt = {}
local function retreatRun(units, ownThreat, configure)
    retreatEngineers = units
    local manager = Create({
        GetArmyIndex = function() return 2 end,
        GetListOfUnits = function() return retreatEngineers end,
        GetCurrentUnits = function() return 0 end,
    }, { FactionIndex = 2 }, { StartPosition = retreatHome }, routeEconomy,
    {
        GetThreatNear = function(_, position)
            return retreatThreatAt[position[1]] or 0
        end,
    },
    {
        GetOwnThreatNear = function() return ownThreat or 0 end,
        ProductionDemand = { DefenseAlert = { Active = false }, ForwardBasePlan = {} },
    })
    if configure then configure(manager) end
    lethalSites = {}
    local recalled = manager:UpdateEngineerRetreat()
    return recalled, manager
end

-- Standing in danger far from home: pulled out, and the ground remembered so
-- the replacement is not posted straight back to it.
retreatThreatAt = { [900] = 90 }
local exposed = retreatUnit(1, { 900, 0, 900 })
local recalled = retreatRun({ exposed }, 0)
assert(recalled == 1, "an engineer standing in danger must be recalled, got " .. recalled)
assert(table.getn(exposed.EngineerBuildQueue) == 0,
    "the native build queue must be cancelled before the move")
assert(exposed.ProcessBuild == nil,
    "the callback that would re-issue the order must be killed")
assert(table.getn(lethalSites) == 1 and lethalSites[1].Reason == "engineer-withdrawn",
    "and the ground must be remembered with its own reason")

-- A quiet errand is left alone.
retreatThreatAt = { [900] = 0 }
local working = retreatUnit(2, { 900, 0, 900 })
assert(retreatRun({ working }, 0) == 0, "a safe errand must not be interrupted")
assert(table.getn(working.EngineerBuildQueue) == 1,
    "and its queue must be untouched")

-- Home is never a retreat: an army under attack still has to repair itself.
retreatThreatAt = { [10] = 9999 }
local athome = retreatUnit(3, { 10, 0, 10 })
assert(retreatRun({ athome }, 0) == 0,
    "an engineer working at home must never be recalled, whatever the threat")

-- An engineer another stage of this same pass dispatched is left where it was
-- sent. UpdateEmergencyDefense posts one to a threatened anchor, and the threat
-- that raised the alert is exactly what this test trips on -- so without the
-- hold the point defence is never built, the cooldown holds the next attempt,
-- and the cycle repeats for every alert outside the home radius.
retreatThreatAt = { [900] = 90 }
local defending = retreatUnit(4, { 900, 0, 900 })
defending.RedQueenEmergencyDefenseUntil = GetGameTick() + 600
assert(retreatRun({ defending }, 0) == 0,
    "an engineer held to build emergency defence must not be recalled from it")
assert(table.getn(defending.EngineerBuildQueue) == 1,
    "and its build queue must survive")
-- Skipped outright, not recalled-but-remembered: the route verdict reads lethal
-- sites, so marking this anchor would refuse the next engineer sent to defend
-- the very place under attack.
assert(table.getn(lethalSites) == 0,
    "the anchor it was sent to defend must not be remembered as lethal")

-- The hold is bounded, so a genuinely stuck engineer is reconsidered.
defending.RedQueenEmergencyDefenseUntil = GetGameTick() - 1
assert(retreatRun({ defending }, 0) == 1,
    "and it must be reconsidered as soon as the hold lapses")

-- The capacity-expansion hold is honoured the same way.
local expanding = retreatUnit(5, { 900, 0, 900 })
expanding.RedQueenProductionBuildUntil = GetGameTick() + 600
assert(retreatRun({ expanding }, 0) == 0,
    "an engineer held to expand factory capacity must not be recalled either")

-- Escort raises the tolerance, so a covered advance is not undone.
retreatThreatAt = { [900] = 90 }
local covered = retreatUnit(4, { 900, 0, 900 })
assert(retreatRun({ covered }, 300) == 0,
    "an escorted engineer must be left to work")

-- Completing the first factory clears ForwardBaseActive while the engineer
-- still has the rest of the site's package queued. Exercise the real plan
-- publisher so the exemption cannot silently use a nonexistent plan or key.
do
    local builder = retreatUnit(5, { 900, 0, 900 })
    local unrelated = retreatUnit(6, { 900, 0, 900 })
    local queued = { { "ueb2101", { 900, 900, 0 }, false } }
    builder.EngineerBuildQueue = queued
    local beforeCleared, beforeMoved = #recallCleared, #recallMoved
    local record
    local count, watcher = retreatRun({ builder, unrelated }, 0, function(current)
        local location = "RQFB_RETREAT_TEST"
        local engineerManager = {}
        current.Brain.BuilderManagers = {
            [location] = { EngineerManager = engineerManager },
        }
        builder.BuilderManagerData = {
            LocationType = location, EngineerManager = engineerManager,
        }
        record = {
            Name = location, SiteName = "RetreatTestSite", State = "Building",
            Position = { 900, 0, 900 }, Engineer = builder,
            StartTick = GetGameTick(), Tech = 1,
            BuildQueueEntries = { [queued[1]] = true },
            Factory = { GetArmy = function() return 2 end },
        }
        current.ForwardBases = { record }
        current.ForwardBaseActive = record
        current.World.GetMaximumForwardBases = function() return 1 end
        current:UpdateForwardBases()
        assert(record.State == "Established" and not current.ForwardBaseActive,
            "factory completion must end the active construction slot")
        assert(current.Strategy.ProductionDemand.ForwardBasePlan.Sites == current.ForwardBases,
            "the live forward-base plan must publish its site records")
    end)
    assert(count == 1 and unrelated.RedQueenRetreatPosition,
        "only the unrelated engineer should be recalled from the threatened site")
    assert(builder.EngineerBuildQueue == queued and builder.ProcessBuild == "thread-handle"
        and not builder.RedQueenRetreatPosition,
        "an established site's engineer must keep its remaining build queue and thread")
    assert(#recallCleared == beforeCleared + 1 and #recallMoved == beforeMoved + 1,
        "establishment must not issue clear or return-home orders to its builder")
    assert(#lethalSites == 1,
        "forward-base work must not create a general engineer-withdrawn report")
end

-- Historical site references must not grant immunity to subsequent jobs. The
-- active slot uses the same ownership test even before the plan is published.
do
    -- Record the entries actually appended by the build request, excluding an
    -- older errand already present on the engineer's queue.
    local originalExecute = buildStructures.AIExecuteBuildStructure
    buildStructures.AIExecuteBuildStructure = function(_, unit, buildingType, _, _, template)
        for _, item in ipairs(template) do
            if item[1] == buildingType then
                table.insert(unit.EngineerBuildQueue, { item[2], { 900, 900, 0 }, false })
                return true
            end
        end
        return false
    end
    local recorder = Create({
        GetArmyIndex = function() return 2 end, BuilderManagers = {},
    }, { FactionIndex = 1 }, {}, {}, {}, { ProductionDemand = {} })
    local builder = retreatUnit(8, { 900, 0, 900 })
    builder.GetBlueprint = function() return { CategoriesHash = { TECH1 = true } } end
    assert(recorder:StartForwardBase(builder, {
        Name = "QueuedWorkSite", Position = { 900, 0, 900 }, Type = "Expansion Area",
    }), "a forward-base package must queue successfully")
    buildStructures.AIExecuteBuildStructure = originalExecute
    local entries = recorder.ForwardBaseActive.BuildQueueEntries
    assert(entries and not entries[builder.EngineerBuildQueue[1]],
        "the recorded forward-base work must not include a pre-existing errand")
    assert(#builder.EngineerBuildQueue > 1, "the stub must append native-shaped queue entries")
    for index = 2, #builder.EngineerBuildQueue do
        assert(entries[builder.EngineerBuildQueue[index]],
            "each appended package task must retain its native queue-entry identity")
    end

    local function ForwardRetreatCase(state, change, activeOnly)
        local builder = retreatUnit(7, { 900, 0, 900 })
        local first = { "ueb2101", { 900, 900, 0 }, false }
        local second = { "ueb2101", { 905, 900, 0 }, false }
        builder.EngineerBuildQueue = { first, second }
        local count = retreatRun({ builder }, 0, function(current)
            local nativeManager = {}
            current.Brain.BuilderManagers = { RQFB_CURRENT = { EngineerManager = nativeManager } }
            builder.BuilderManagerData = {
                LocationType = "RQFB_CURRENT", EngineerManager = nativeManager,
            }
            local record = {
                Name = "RQFB_CURRENT", State = state, Engineer = builder,
                BuildQueueEntries = { [first] = true, [second] = true },
            }
            current.ForwardBaseActive = record
            current.Strategy.ProductionDemand.ForwardBasePlan = { Sites = { record } }
            if activeOnly then current.Strategy.ProductionDemand.ForwardBasePlan = nil end
            if change then change(builder, record, current) end
        end)
        return count, builder
    end
    for _, activeOnly in ipairs({ false, true }) do
        for _, state in ipairs({ "Preparing", "Building", "Established" }) do
            assert(ForwardRetreatCase(state, nil, activeOnly) == 0,
                "current forward-base work must remain exempt in " .. state)
        end
        for _, state in ipairs({ "Failed", "Destroyed" }) do
            assert(ForwardRetreatCase(state, nil, activeOnly) == 1,
                "a terminal site or stale active slot must not exempt its former engineer")
        end
        local departed = {
            function(unit) unit.EngineerBuildQueue = {} end,
            function(unit) unit.EngineerBuildQueue = nil end,
            function(unit) unit.EngineerBuildQueue = { { "ueb2101", { 900, 900, 0 }, false } } end,
            function(unit)
                table.remove(unit.EngineerBuildQueue, 1)
                table.remove(unit.EngineerBuildQueue, 1)
                table.insert(unit.EngineerBuildQueue, { "ueb2101", { 900, 900, 0 }, false })
            end,
            function(unit)
                table.insert(unit.EngineerBuildQueue, 1, { "ueb1103", { 950, 950, 0 }, false })
            end,
            function(unit) unit.BuilderManagerData.EngineerManager = {} end,
            function(unit) unit.BuilderManagerData = nil end,
            function(_, _, current) current.Brain.BuilderManagers.RQFB_CURRENT = nil end,
            function(_, record) record.BuildQueueEntries = nil end,
        }
        for _, change in ipairs(departed) do
            assert(ForwardRetreatCase("Established", change, activeOnly) == 1,
                "finished, replaced or reassigned work must release the exemption")
        end
        assert(ForwardRetreatCase("Established", function(unit)
            table.remove(unit.EngineerBuildQueue, 1)
        end, activeOnly) == 0,
            "finishing one package entry must preserve the remaining forward-base work")
    end
end

-- The commander: kept home, and put to work while it is there.
--
-- Red Queen excluded it from every engineer pool it manages, so after the
-- opening it never asked the strongest build power on the field for anything --
-- observed as an idle ACU through the early and mid game, and as an Aeon
-- commander wandering alone to the centre of the map.
local commanderHome = { 0, 0, 0 }
local function commanderRun(position, idle, alertActive, factoryPositions, nativeManager)
    local acu = {
        EntityId = 900,
        Dead = false,
        IsCommander = true,
        IsEngineer = true,
        Categories = { COMMAND = true, MOBILE = true, ENGINEER = true },
        GetPosition = function() return position end,
        IsIdleState = function() return idle end,
        EngineerBuildQueue = { { "T1Resource", 1, 1 } },
        ProcessBuild = "thread-handle",
    }
    -- The real ACU is a member of an EngineerManager -- StrategyDirector reads
    -- its BuilderManagerData.LocationType -- so a case that cares whether
    -- native is re-polled has to supply one. Without it the release path finds
    -- no manager and schedules nothing, which is why this went unnoticed.
    if nativeManager then
        acu.BuilderManagerData = { EngineerManager = nativeManager }
    end
    local factories = {}
    for index, factoryPosition in ipairs(factoryPositions or {}) do
        table.insert(factories, {
            EntityId = index,
            Dead = false,
            Categories = { STRUCTURE = true, FACTORY = true },
            GetPosition = function() return factoryPosition end,
        })
    end
    local guardsBefore = table.getn(guarded)
    local manager = Create({
        GetArmyIndex = function() return 2 end,
        -- This spec's category fake matches on a predicate rather than a
        -- name, so the commander list is selected by asking the category
        -- whether a commander satisfies it.
        GetListOfUnits = function(_, category)
            if category and category.Matches and category.Matches({ COMMAND = true }) then
                return { acu }
            end
            return factories
        end,
        GetCurrentUnits = function() return 0 end,
    }, { FactionIndex = 2 }, { StartPosition = commanderHome }, routeEconomy, {},
    {
        ProductionDemand = {
            DefenseAlert = { Active = alertActive or false },
            ForwardBasePlan = {},
        },
    })
    local verdict = manager:UpdateCommanderTasking()
    local issued = {}
    for index = guardsBefore + 1, table.getn(guarded) do
        table.insert(issued, guarded[index])
    end
    return verdict, acu, issued
end

-- Strayed beyond the leash: brought back, with native ownership released first
-- or it simply turns around and walks out again.
local verdict, strayed = commanderRun({ 600, 0, 600 }, true, false, { { 10, 0, 10 } })
assert(verdict == "recalled", "a commander beyond its leash must be recalled, got " .. tostring(verdict))
assert(table.getn(strayed.EngineerBuildQueue) == 0,
    "the build queue that sent it out must be cancelled")
assert(strayed.ProcessBuild == nil, "and the callback that would re-issue it")

-- Idle at home: put on a factory, so the build power stops standing still.
local assisted, assistOrders
verdict, assisted, assistOrders = commanderRun(
    { 20, 0, 20 }, true, false, { { 40, 0, 40 }, { 300, 0, 300 } })
assert(verdict == "assist", "an idle commander at home must assist, got " .. tostring(verdict))
assert(table.getn(assistOrders) == 1, "exactly one guard order must be issued")
assert(assistOrders[1].Target.EntityId == 1,
    "and it must assist the nearest factory, got " .. tostring(assistOrders[1].Target.EntityId))
assert(assisted.RedQueenAssistUntil, "the assignment must be held for a period")
-- Native ownership must be released before the assist, or the queued build
-- re-issues and the commander walks off again. The strict IssueClearCommands
-- above enforces the ordering.
assert(table.getn(assisted.EngineerBuildQueue) == 0 and assisted.ProcessBuild == nil,
    "the commander's native build ownership must be released before assisting")

-- The assist issues its own order and holds the commander for 45 seconds, so it
-- must not also schedule the native re-poll. That poll lands about five seconds
-- later, AssignEngineerTask re-platoons the ACU, and a bare IssueGuard does not
-- set UnitBeingAssist -- the one thing that would have made native leave it
-- alone. RedQueenAssistUntil then reports it as assisting for the other forty.
local assistPolls = {}
verdict = commanderRun({ 20, 0, 20 }, true, false, { { 40, 0, 40 } }, {
    DelayAssign = function(_, unit, delay)
        table.insert(assistPolls, { Unit = unit, Delay = delay })
    end,
})
assert(verdict == "assist", "the assist case must still assist, got " .. tostring(verdict))
assert(table.getn(assistPolls) == 0,
    "assisting must not schedule the native re-poll that would replace its own guard")

-- The recall still hands the engineer back: the hook defers that poll until the
-- commander is home, and native work resumes from there.
local recallPolls = {}
verdict = commanderRun({ 600, 0, 600 }, true, false, { { 10, 0, 10 } }, {
    DelayAssign = function(_, unit, delay)
        table.insert(recallPolls, { Unit = unit, Delay = delay })
    end,
})
assert(verdict == "recalled", "the recall case must still recall, got " .. tostring(verdict))
assert(table.getn(recallPolls) == 1,
    "a recall must still schedule the poll the hook defers until arrival")

-- Already busy: native has usefully tasked it, so leave it alone.
verdict = commanderRun({ 20, 0, 20 }, false, false, { { 40, 0, 40 } })
assert(verdict == "busy", "a working commander must not be interrupted, got " .. tostring(verdict))

-- Defence outranks both: a commander alert drives its own response.
verdict = commanderRun({ 600, 0, 600 }, true, true, { { 40, 0, 40 } })
assert(verdict == "defense",
    "an active alert must own the commander, got " .. tostring(verdict))

-- Nothing to assist is not an error.
verdict = commanderRun({ 20, 0, 20 }, true, false, {})
assert(verdict == "no-factory", "no factory to assist must be reported, got " .. tostring(verdict))

print("Red Queen engineer establishment contracts passed")

-- Forward-base packages are tiered, and lead with something that shoots.
--
-- Every tier previously began with T1LandFactory and T1Radar, so an engineer
-- at a contested site built a 240-mass factory and a radar before its first
-- gun. Across the 21-cell matrix only 21% of started bases established.
local tierManager = Create({ GetArmyIndex = function() return 2 end },
    { FactionIndex = 2 }, {}, routeEconomy, {}, { ProductionDemand = {} })

local defenceKinds = { GroundDefense = true, AADefense = true }
local function isDefence(name)
    for kind in pairs(defenceKinds) do
        if string.find(name, kind, 1, true) then return true end
    end
    return false
end

for tech = 1, 3 do
    local tier = tierManager:ForwardBaseTier(tech)
    assert(tier.Tier == tech, "tier " .. tech .. " must report itself")
    assert(isDefence(tier.Package[1]),
        "tier " .. tech .. " must lead with a defence, led with " .. tier.Package[1])
    assert(not string.find(tier.Package[1], "Factory", 1, true),
        "tier " .. tech .. " must not lead with a factory")

    -- A tier can never demand a structure it does not queue, or it is
    -- permanently short of its own minimum.
    local pd, aa, shields = 0, 0, 0
    for _, name in ipairs(tier.Package) do
        if string.find(name, "GroundDefense", 1, true) then pd = pd + 1 end
        if string.find(name, "AADefense", 1, true) then aa = aa + 1 end
        if string.find(name, "Shield", 1, true) then shields = shields + 1 end
    end
    assert(pd >= tier.MinimumDefenses,
        "tier " .. tech .. " queues " .. pd .. " point defences but demands " .. tier.MinimumDefenses)
    assert(aa >= tier.MinimumAntiAir,
        "tier " .. tech .. " queues " .. aa .. " anti-air but demands " .. tier.MinimumAntiAir)
    assert(shields >= tier.MinimumShields,
        "tier " .. tech .. " queues " .. shields .. " shields but demands " .. tier.MinimumShields)
end

-- Tech 1 has no shield in the game, so its minimum must not ask for one.
local foothold = tierManager:ForwardBaseTier(1)
assert(foothold.MinimumShields == 0, "a Tech 1 base cannot be asked for a shield")
assert(foothold.MinimumDefenses >= 2, "a foothold still needs point defence")

-- Tech 2 keeps Tech 1 guns in the mix: they are shooting while the Tech 2
-- pieces are still building.
local holding = tierManager:ForwardBaseTier(2)
local hasT1Gun, hasT2Gun, hasShield = false, false, false
for _, name in ipairs(holding.Package) do
    if name == "T1GroundDefense" then hasT1Gun = true end
    if name == "T2GroundDefense" then hasT2Gun = true end
    if string.find(name, "Shield", 1, true) then hasShield = true end
end
assert(hasT1Gun and hasT2Gun, "tier 2 must mix Tech 1 cover with Tech 2 guns")
assert(hasShield and holding.MinimumShields == 1, "tier 2 must require its shield")

-- Tech 3 wants more than a handful of Tech 2 or better guns, and a shield.
local projecting = tierManager:ForwardBaseTier(3)
assert(projecting.MinimumDefenses >= 5,
    "tier 3 must want more than a handful of guns, wants " .. projecting.MinimumDefenses)
assert(projecting.MinimumShields >= 1, "tier 3 must require a shield or better")

-- T3GroundDefense is UEF only; naming it elsewhere means the queue silently
-- drops the entry.
for _, faction in ipairs({ 2, 3, 4 }) do
    local other = Create({ GetArmyIndex = function() return 2 end },
        { FactionIndex = faction }, {}, routeEconomy, {}, { ProductionDemand = {} })
    for _, name in ipairs(other:ForwardBaseTier(3).Package) do
        assert(name ~= "T3GroundDefense",
            "faction " .. faction .. " cannot build T3GroundDefense")
    end
end
local uef = Create({ GetArmyIndex = function() return 2 end },
    { FactionIndex = 1 }, {}, routeEconomy, {}, { ProductionDemand = {} })
local uefHasBest = false
for _, name in ipairs(uef:ForwardBaseTier(3).Package) do
    if name == "T3GroundDefense" then uefHasBest = true end
end
assert(uefHasBest, "UEF should use its Tech 3 ground defence at tier 3")

-- Artillery has a 50 minimum radius, a dead zone around the gun, so it must
-- never be early cover.
for tech = 1, 3 do
    local package = tierManager:ForwardBaseTier(tech).Package
    for index = 1, math.min(4, table.getn(package)) do
        assert(not string.find(package[index], "Artillery", 1, true),
            "artillery must not be queued as early cover at tier " .. tech)
    end
end

print("Red Queen forward-base tier contracts passed")
