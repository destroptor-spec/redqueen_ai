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
}

function EntityCategoryContains(category, unit)
    return category.EngineerOnly and unit.IsEngineer and not unit.IsCommander
end

local captured = nil
local buildAllowed = true
local expansionFailure = false
local expansionCalls = {}
local buildStructures = {
    AIExecuteBuildStructure = function(...)
        captured = { ... }
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
        },
    },
}
local baseTemplates = { BaseTemplates = { [1] = {} }, ExpansionBaseTemplates = { [1] = {} } }
local constants = {
    Policy = {
        FactoryCheckCooldownSeconds = 30,
        ForwardBaseSiteRadius = 60,
        ForwardBaseCooldownSeconds = 120,
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
local pool = { GetPlatoonUnits = function() return { commander, engineer, destroyedEngineer } end }
local forwardFactory = {
    EntityId = 10,
    Dead = false,
    GetArmy = function() return 1 end,
    GetPosition = function() return { 128, 0, 128 } end,
}
local brain = {
    Army = 1,
    Name = "ARMY_1",
    GetArmyIndex = function() return 1 end,
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
    State = { DesiredFactories = 3 },
    CanExpandProduction = function() return true end,
}
local world = { WaterRatio = 0 }
local strategy = { ProductionDemand = { Air = 0.30, Naval = 0.15 } }

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
assert(captured[4] == false, "factory placement must not follow an arbitrary builder")
assert(captured[5] == false, "base placement must use the engine's absolute result")
assert(manager.FillIdleFactories == nil, "adaptive factory manager must remain the only unit-queue owner")

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
