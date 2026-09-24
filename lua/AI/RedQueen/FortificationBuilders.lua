local Constants = import("/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua")
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

-- `standing` is a target the base holds whether or not anything is attacking it.
-- Omitted, this behaves exactly as before: no alert, no defence.
--
-- Anti-air is the one role that passes it. Measured across eighteen mirror
-- cells, 63% of active alerts qualify on surface and only 12% on air, so an
-- anti-air target keyed on an alert is zero most of the match and cannot
-- accumulate between raids -- which is why 17.9 point defences stand beside 3.8
-- SAM while the opponent builds 222 air units a match. Reported from a human
-- match: one air experimental killed both Red Queen armies.
--
-- A base that waits for an air alert to build SAM has already taken the raid.
local function NeedsDefense(aiBrain, locationType, role, category, standing)
    local position, radius = GetLocation(aiBrain, locationType)
    if not position then
        return false
    end
    local extent = math.max(Constants.Policy.FortificationMinimumRadius, radius)
    local target = standing or 0
    -- An alert on this base raises the target for the arm under attack.
    local alert = GetState(aiBrain)
    if alert
        and alert.Active
        and alert.AnchorPosition
        and DistanceSquared(position, alert.AnchorPosition) <= extent ^ 2
    then
        target = math.max(target, (alert.Targets and alert.Targets[role]) or 0)
    end
    if target <= 0 then
        return false
    end
    return aiBrain:GetNumUnitsAroundPoint(category, position, extent, "Ally") < target
end

-- What counts toward a tier's ground-defence need.
--
-- Not "any point defence": observed in a live match, four Tech 1 point
-- defences satisfied a Ground target of four, so the Tech 2 point defence
-- builder's condition went false while the base was under pressure and the
-- next passing builder -- a tactical missile launcher at priority 980 -- became
-- the first Tech 2 structure built. Four Tech 1 point defences are not four
-- Tech 2 point defences against a Tech 2 enemy.
--
-- A tier's need is therefore measured in structures of that tier or better.
-- Tech 1 still counts everything, because it is the floor and anything at all
-- satisfies it.
local function GroundDefenseCategory(tier)
    local ground = categories.STRUCTURE * categories.DEFENSE * categories.DIRECTFIRE
    if tier >= 3 then
        return ground * categories.TECH3
    end
    if tier >= 2 then
        return ground * (categories.TECH2 + categories.TECH3)
    end
    return ground
end

local function NeedsT2GroundWithT3(aiBrain, locationType)
    return aiBrain:GetFactionIndex() ~= 1
        and HasEngineer(aiBrain, locationType, 3)
        and NeedsDefense(aiBrain, locationType, "Ground", GroundDefenseCategory(2))
end

local function NeedsT3Ground(aiBrain, locationType)
    return aiBrain:GetFactionIndex() == 1
        and HasEngineer(aiBrain, locationType, 3)
        and NeedsDefense(aiBrain, locationType, "Ground", GroundDefenseCategory(3))
end

local function NeedsT2Ground(aiBrain, locationType)
    return not HasEngineer(aiBrain, locationType, 3)
        and HasEngineer(aiBrain, locationType, 2)
        and NeedsDefense(aiBrain, locationType, "Ground", GroundDefenseCategory(2))
end

local function NeedsT1Ground(aiBrain, locationType)
    return not HasEngineer(aiBrain, locationType, 3)
        and not HasEngineer(aiBrain, locationType, 2)
        and HasEngineer(aiBrain, locationType, 1)
        and NeedsDefense(aiBrain, locationType, "Ground", GroundDefenseCategory(1))
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

-- What counts toward a tier's anti-air need, on the same rule as ground.
--
-- The standing floor was first written against a tier-blind category, and it
-- reproduced the exact defect this file already records for point defence:
-- cheap Tech 2 flak filled a floor of six, the Tech 3 builder saw the floor
-- satisfied and laid no SAM. Measured across eighteen cells -- flak 3.9 to 7.8
-- while SAM went 3.8 to 2.8. Flak is not SAM against an air experimental, which
-- is the threat the floor exists for.
local function AntiAirCategory(tier)
    local antiAir = categories.STRUCTURE * categories.DEFENSE * categories.ANTIAIR
    if tier >= 3 then
        return antiAir * categories.TECH3
    end
    if tier >= 2 then
        return antiAir * (categories.TECH2 + categories.TECH3)
    end
    return antiAir
end

local function NeedsT3AntiAir(aiBrain, locationType)
    return HasEngineer(aiBrain, locationType, 3)
        and NeedsDefense(
            aiBrain,
            locationType,
            "AntiAir",
            AntiAirCategory(3),
            Constants.Policy.StandingAntiAirPerBase
        )
end

local function NeedsT2AntiAir(aiBrain, locationType)
    return not HasEngineer(aiBrain, locationType, 3)
        and HasEngineer(aiBrain, locationType, 2)
        and NeedsDefense(
            aiBrain,
            locationType,
            "AntiAir",
            AntiAirCategory(2),
            Constants.Policy.StandingAntiAirPerBase
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
        BuilderName = "Red Queen Emergency T1 Point Defense",
        PlatoonTemplate = "EngineerBuilder",
        Priority = 1000,
        InstanceCount = 4,
        BuilderType = "Any",
        BuilderConditions = {
            { NeedsT1Ground, { "LocationType" } },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { UnitCountBuildConditions, "LocationEngineersBuildingLess", { "LocationType", 4, categories.DEFENSE } },
        },
        BuilderData = {
            Construction = {
                BuildClose = true,
                BuildStructures = { "T1GroundDefense" },
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
