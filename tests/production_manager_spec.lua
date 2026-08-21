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
}

function EntityCategoryContains(category, unit)
    return category.EngineerOnly and unit.IsEngineer and not unit.IsCommander
end

local captured = nil
local buildStructures = {
    AIExecuteBuildStructure = function(...)
        captured = { ... }
        return true
    end,
    AIBuildBaseTemplateFromLocation = function(template)
        return template
    end,
}
local addedCounterGroups = {}
local addBuilderTable = {
    AddGlobalBuilderGroup = function(_, locationType, groupName)
        table.insert(addedCounterGroups, { locationType, groupName })
    end,
}
local aiUtilities = { AINewExpansionBase = function() end }
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
local constants = { Policy = { FactoryCheckCooldownSeconds = 30 } }
local logger = { Info = function() end }

function import(path)
    if path == "/lua/AI/aibuildstructures.lua" then
        return buildStructures
    elseif path == "/lua/AI/AIAddBuilderTable.lua" then
        return addBuilderTable
    elseif path == "/lua/AI/aiutilities.lua" then
        return aiUtilities
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
local brain = {
    Army = 1,
    Name = "ARMY_1",
    GetPlatoonUniquelyNamed = function() return pool end,
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

print("Red Queen production manager contracts passed")
