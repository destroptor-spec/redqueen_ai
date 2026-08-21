local InstantBuildConditions = "/lua/editor/InstantBuildConditions.lua"
local UnitCountBuildConditions = "/lua/editor/UnitCountBuildConditions.lua"

local function GetState(aiBrain)
    local modules = aiBrain.RedQueenModules
    if not modules or not modules.Strategy or not modules.Economy then
        return nil, nil
    end
    return modules.Strategy.ProductionDemand.DefenseAlert, modules.Economy.State
end

local function GetLocation(aiBrain, locationType)
    local managers = aiBrain.BuilderManagers
    local manager = managers and managers[locationType]
    local engineerManager = manager and manager.EngineerManager
    if not engineerManager or not engineerManager.GetLocationCoords then
        return nil, nil
    end
    return engineerManager:GetLocationCoords(), engineerManager.Radius or 100
end

local function DistanceSquared(a, b)
    local dx = a[1] - b[1]
    local dz = a[3] - b[3]
    return dx * dx + dz * dz
end

local function HasEngineer(aiBrain, locationType, tier)
    local managers = aiBrain.BuilderManagers
    local manager = managers and managers[locationType]
    local engineerManager = manager and manager.EngineerManager
    if not engineerManager or not engineerManager.GetNumCategoryUnits then
        return false
    end
    local category = categories.ENGINEER * categories["TECH" .. tostring(tier)]
    return engineerManager:GetNumCategoryUnits("Engineers", category) > 0
end

local function NeedsDefense(aiBrain, locationType, role, category)
    local alert = GetState(aiBrain)
    local position, radius = GetLocation(aiBrain, locationType)
    if not alert
        or not alert.Active
        or not position
        or DistanceSquared(position, alert.AnchorPosition) > math.max(40, radius) ^ 2
    then
        return false
    end
    local target = alert.Targets and alert.Targets[role] or 0
    if target <= 0 then
        return false
    end
    return aiBrain:GetNumUnitsAroundPoint(category, position, math.max(40, radius), "Ally") < target
end

local function NeedsT2GroundWithT3(aiBrain, locationType)
    return aiBrain:GetFactionIndex() ~= 1
        and HasEngineer(aiBrain, locationType, 3)
        and NeedsDefense(
            aiBrain,
            locationType,
            "Ground",
            categories.STRUCTURE * categories.DEFENSE * categories.DIRECTFIRE
        )
end

local function NeedsT3Ground(aiBrain, locationType)
    return aiBrain:GetFactionIndex() == 1
        and HasEngineer(aiBrain, locationType, 3)
        and NeedsDefense(
            aiBrain,
            locationType,
            "Ground",
            categories.STRUCTURE * categories.DEFENSE * categories.DIRECTFIRE
        )
end

local function NeedsT2Ground(aiBrain, locationType)
    return not HasEngineer(aiBrain, locationType, 3)
        and HasEngineer(aiBrain, locationType, 2)
        and NeedsDefense(
            aiBrain,
            locationType,
            "Ground",
            categories.STRUCTURE * categories.DEFENSE * categories.DIRECTFIRE
        )
end

local function NeedsTacticalMissileWithT3(aiBrain, locationType)
    return HasEngineer(aiBrain, locationType, 3)
        and NeedsDefense(
            aiBrain,
            locationType,
            "TacticalMissiles",
            categories.STRUCTURE * categories.TACTICALMISSILEPLATFORM
        )
end

local function NeedsT3AntiAir(aiBrain, locationType)
    return HasEngineer(aiBrain, locationType, 3)
        and NeedsDefense(
            aiBrain,
            locationType,
            "AntiAir",
            categories.STRUCTURE * categories.DEFENSE * categories.ANTIAIR
        )
end

local function NeedsT2AntiAir(aiBrain, locationType)
    return not HasEngineer(aiBrain, locationType, 3)
        and HasEngineer(aiBrain, locationType, 2)
        and NeedsDefense(
            aiBrain,
            locationType,
            "AntiAir",
            categories.STRUCTURE * categories.DEFENSE * categories.ANTIAIR
        )
end

local function NeedsT3Shield(aiBrain, locationType)
    return HasEngineer(aiBrain, locationType, 3)
        and NeedsDefense(
            aiBrain,
            locationType,
            "Shields",
            categories.STRUCTURE * categories.SHIELD
        )
end

local function NeedsT2Shield(aiBrain, locationType)
    return not HasEngineer(aiBrain, locationType, 3)
        and HasEngineer(aiBrain, locationType, 2)
        and NeedsDefense(
            aiBrain,
            locationType,
            "Shields",
            categories.STRUCTURE * categories.SHIELD
        )
end

local function NeedsStrategicMissileDefense(aiBrain, locationType)
    return HasEngineer(aiBrain, locationType, 3)
        and NeedsDefense(
            aiBrain,
            locationType,
            "StrategicMissileDefense",
            categories.STRUCTURE * categories.TECH3 * categories.ANTIMISSILE
        )
end

local function NeedsTacticalMissile(aiBrain, locationType)
    return not HasEngineer(aiBrain, locationType, 3)
        and HasEngineer(aiBrain, locationType, 2)
        and NeedsDefense(
            aiBrain,
            locationType,
            "TacticalMissiles",
            categories.STRUCTURE * categories.TACTICALMISSILEPLATFORM
        )
end

BuilderGroup {
    BuilderGroupName = "RedQueenEmergencyFortificationBuilders",
    BuildersType = "EngineerBuilder",

    Builder {
        BuilderName = "Red Queen Emergency T3 Sentry",
        PlatoonTemplate = "UEFT3EngineerBuilder",
        Priority = 1000,
        InstanceCount = 3,
        BuilderType = "Any",
        BuilderConditions = {
            { NeedsT3Ground, { "LocationType" } },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { UnitCountBuildConditions, "LocationEngineersBuildingLess", { "LocationType", 3, categories.DEFENSE } },
        },
        BuilderData = {
            Construction = {
                BuildClose = true,
                BuildStructures = { "T3GroundDefense" },
                Location = "LocationType",
            },
        },
    },
    Builder {
        BuilderName = "Red Queen Emergency T2 Point Defense T3 Engineer",
        PlatoonTemplate = "T3EngineerBuilder",
        Priority = 1000,
        InstanceCount = 3,
        BuilderType = "Any",
        BuilderConditions = {
            { NeedsT2GroundWithT3, { "LocationType" } },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { UnitCountBuildConditions, "LocationEngineersBuildingLess", { "LocationType", 3, categories.DEFENSE } },
        },
        BuilderData = {
            Construction = {
                BuildClose = true,
                BuildStructures = { "T2GroundDefense" },
                Location = "LocationType",
            },
        },
    },
    Builder {
        BuilderName = "Red Queen Emergency T2 Point Defense",
        PlatoonTemplate = "T2EngineerBuilder",
        Priority = 1000,
        InstanceCount = 3,
        BuilderType = "Any",
        BuilderConditions = {
            { NeedsT2Ground, { "LocationType" } },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { UnitCountBuildConditions, "LocationEngineersBuildingLess", { "LocationType", 3, categories.DEFENSE } },
        },
        BuilderData = {
            Construction = {
                BuildClose = true,
                BuildStructures = { "T2GroundDefense" },
                Location = "LocationType",
            },
        },
    },
    Builder {
        BuilderName = "Red Queen Emergency T3 AA",
        PlatoonTemplate = "T3EngineerBuilder",
        Priority = 995,
        InstanceCount = 2,
        BuilderType = "Any",
        BuilderConditions = {
            { NeedsT3AntiAir, { "LocationType" } },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { UnitCountBuildConditions, "LocationEngineersBuildingLess", { "LocationType", 3, categories.DEFENSE } },
        },
        BuilderData = {
            Construction = {
                BuildClose = true,
                BuildStructures = { "T3AADefense" },
                Location = "LocationType",
            },
        },
    },
    Builder {
        BuilderName = "Red Queen Emergency T2 AA",
        PlatoonTemplate = "T2EngineerBuilder",
        Priority = 995,
        InstanceCount = 2,
        BuilderType = "Any",
        BuilderConditions = {
            { NeedsT2AntiAir, { "LocationType" } },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { UnitCountBuildConditions, "LocationEngineersBuildingLess", { "LocationType", 3, categories.DEFENSE } },
        },
        BuilderData = {
            Construction = {
                BuildClose = true,
                BuildStructures = { "T2AADefense" },
                Location = "LocationType",
            },
        },
    },
    Builder {
        BuilderName = "Red Queen Emergency T3 Shield",
        PlatoonTemplate = "T3EngineerBuilder",
        Priority = 990,
        InstanceCount = 2,
        BuilderType = "Any",
        BuilderConditions = {
            { NeedsT3Shield, { "LocationType" } },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { UnitCountBuildConditions, "LocationEngineersBuildingLess", { "LocationType", 3, categories.SHIELD } },
        },
        BuilderData = {
            Construction = {
                BuildClose = true,
                BuildStructures = { "T3ShieldDefense" },
                Location = "LocationType",
            },
        },
    },
    Builder {
        BuilderName = "Red Queen Emergency T2 Shield",
        PlatoonTemplate = "T2EngineerBuilder",
        Priority = 990,
        InstanceCount = 2,
        BuilderType = "Any",
        BuilderConditions = {
            { NeedsT2Shield, { "LocationType" } },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { UnitCountBuildConditions, "LocationEngineersBuildingLess", { "LocationType", 3, categories.SHIELD } },
        },
        BuilderData = {
            Construction = {
                BuildClose = true,
                BuildStructures = { "T2ShieldDefense" },
                Location = "LocationType",
            },
        },
    },
    Builder {
        BuilderName = "Red Queen Emergency Strategic Missile Defense",
        PlatoonTemplate = "T3EngineerBuilder",
        Priority = 985,
        InstanceCount = 1,
        BuilderType = "Any",
        BuilderConditions = {
            { NeedsStrategicMissileDefense, { "LocationType" } },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
        },
        BuilderData = {
            Construction = {
                BuildClose = true,
                BuildStructures = { "T3StrategicMissileDefense" },
                Location = "LocationType",
            },
        },
    },
    Builder {
        BuilderName = "Red Queen Emergency Tactical Missile T3 Engineer",
        PlatoonTemplate = "T3EngineerBuilder",
        Priority = 980,
        InstanceCount = 2,
        BuilderType = "Any",
        BuilderConditions = {
            { NeedsTacticalMissileWithT3, { "LocationType" } },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
        },
        BuilderData = {
            Construction = {
                BuildClose = true,
                BuildStructures = { "T2StrategicMissile" },
                Location = "LocationType",
            },
        },
    },
    Builder {
        BuilderName = "Red Queen Emergency Tactical Missile",
        PlatoonTemplate = "T2EngineerBuilder",
        Priority = 980,
        InstanceCount = 2,
        BuilderType = "Any",
        BuilderConditions = {
            { NeedsTacticalMissile, { "LocationType" } },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
        },
        BuilderData = {
            Construction = {
                BuildClose = true,
                BuildStructures = { "T2StrategicMissile" },
                Location = "LocationType",
            },
        },
    },
}
