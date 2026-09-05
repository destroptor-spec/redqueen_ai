local EconomyBuildConditions = "/lua/editor/EconomyBuildConditions.lua"
local InstantBuildConditions = "/lua/editor/InstantBuildConditions.lua"
local MarkerBuildConditions = "/lua/editor/MarkerBuildConditions.lua"
local UnitCountBuildConditions = "/lua/editor/UnitCountBuildConditions.lua"
local Constants = import("/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua")

local function GetDemand(aiBrain)
    local modules = aiBrain.RedQueenModules
    if not modules or not modules.Strategy or not modules.Economy then
        return nil, nil
    end
    return modules.Strategy.ProductionDemand, modules.Economy.State
end

local function StrategicPriority(aiBrain, focus)
    local demand = GetDemand(aiBrain)
    if not demand or not demand.FocusWeights then
        return 0
    end
    local weight = demand.FocusWeights[focus] or 0
    if weight < Constants.Policy.StrategicFocusMinimumScore then
        return 0
    end
    local priority = 700 + weight * 3
    if demand.PrimaryFocus == focus then
        priority = priority + 25
    end
    return math.min(1000, math.floor(priority))
end

local function Tech2Priority(self, aiBrain)
    local priority = StrategicPriority(aiBrain, "Tech2")
    local demand = GetDemand(aiBrain)
    if priority == 0 and demand and demand.TierPolicy then
        for _, domain in pairs({ "Land", "Air", "Naval" }) do
            if demand.TierPolicy[domain] and demand.TierPolicy[domain].Highest >= 2 then
                return 910
            end
        end
    end
    return priority
end

local function Tech3Priority(self, aiBrain)
    local priority = StrategicPriority(aiBrain, "Tech3")
    local demand = GetDemand(aiBrain)
    if priority == 0 and demand and demand.TierPolicy then
        for _, domain in pairs({ "Land", "Air", "Naval" }) do
            if demand.TierPolicy[domain] and demand.TierPolicy[domain].Highest >= 3 then
                return 920
            end
        end
    end
    return priority
end

local function ExperimentalPriority(self, aiBrain)
    return StrategicPriority(aiBrain, "Experimental")
end

local function NukePriority(self, aiBrain)
    return StrategicPriority(aiBrain, "Nuke")
end

local function ShouldBuildGunships(aiBrain)
    local demand, economy = GetDemand(aiBrain)
    if not demand
        or economy.StallRisk
        or demand.Doctrine ~= "GunshipCounter"
    then
        return false
    end

    local gunships = aiBrain:GetCurrentUnits(
        categories.MOBILE * categories.AIR * categories.GROUNDATTACK
    )
    local combatUnits = aiBrain:GetCurrentUnits(
        categories.MOBILE * (categories.LAND + categories.AIR)
            - categories.ENGINEER
            - categories.COMMAND
            - categories.SCOUT
    )
    local desired = math.max(6, math.floor(combatUnits * demand.Gunships))
    return gunships < desired
end

local function ShouldBuildAirDefense(aiBrain)
    local demand, economy = GetDemand(aiBrain)
    if not demand
        or economy.StallRisk
        or demand.Doctrine ~= "AirDefense"
    then
        return false
    end

    local fighters = aiBrain:GetCurrentUnits(
        categories.MOBILE * categories.AIR * categories.ANTIAIR
            - categories.BOMBER
            - categories.TRANSPORTFOCUS
    )
    local airCombat = aiBrain:GetCurrentUnits(
        categories.MOBILE * categories.AIR - categories.TRANSPORTFOCUS - categories.SCOUT
    )
    local desired = math.max(8, math.floor(math.max(1, airCombat) * demand.AntiAir))
    return fighters < desired
end

local function CanAffordTech(economy, massIncome, energyIncome)
    return not economy.StallRisk
        and economy.MassIncome >= massIncome
        and economy.EnergyIncome >= energyIncome
        and (economy.MassStoredRatio >= 0.10 or economy.MassTrend >= 0)
        and (economy.EnergyStoredRatio >= 0.15 or economy.EnergyTrend >= 0)
end

local function DomainIsRelevant(aiBrain, domain)
    local modules = aiBrain.RedQueenModules
    local mapType = modules and modules.World and modules.World.MapType or "Land"
    if domain == "Air" then
        return true
    end
    if domain == "Land" then
        return mapType ~= "Naval"
    end
    return mapType ~= "Land"
end

local function ShouldTechToT2(aiBrain, domain)
    local demand, economy = GetDemand(aiBrain)
    local tier = demand
        and demand.TierPolicy
        and demand.TierPolicy[domain]
        and demand.TierPolicy[domain].Highest
    return demand
        and DomainIsRelevant(aiBrain, domain)
        and not (demand.DefenseAlert and demand.DefenseAlert.Active)
        and demand.FocusWeights
        and (demand.FocusWeights.Tech2 >= Constants.Policy.StrategicFocusMinimumScore
            or (tier or 1) >= 2)
        and CanAffordTech(
            economy,
            Constants.Policy.Tech2MinimumMassIncome,
            Constants.Policy.Tech2MinimumEnergyIncome
        )
end

local function ShouldTechToT3(aiBrain, domain)
    local demand, economy = GetDemand(aiBrain)
    local tier = demand
        and demand.TierPolicy
        and demand.TierPolicy[domain]
        and demand.TierPolicy[domain].Highest
    return demand
        and DomainIsRelevant(aiBrain, domain)
        and not (demand.DefenseAlert and demand.DefenseAlert.Active)
        and demand.FocusWeights
        and (demand.FocusWeights.Tech3 >= Constants.Policy.StrategicFocusMinimumScore
            or (tier or 1) >= 3)
        and CanAffordTech(
            economy,
            Constants.Policy.Tech3MinimumMassIncome,
            Constants.Policy.Tech3MinimumEnergyIncome
        )
end

local function ShouldBuildDominantTier(aiBrain, domain, tier)
    local demand, economy = GetDemand(aiBrain)
    local policy = demand and demand.TierPolicy and demand.TierPolicy[domain]
    return policy
        and policy.Highest == tier
        and not economy.StallRisk
end

local function ShouldBuildT2Land(aiBrain)
    return ShouldBuildDominantTier(aiBrain, "Land", 2)
end

local function ShouldBuildT3Land(aiBrain)
    return ShouldBuildDominantTier(aiBrain, "Land", 3)
end

local function ShouldBuildT2Air(aiBrain)
    return ShouldBuildDominantTier(aiBrain, "Air", 2)
end

local function ShouldBuildT3Air(aiBrain)
    return ShouldBuildDominantTier(aiBrain, "Air", 3)
end

local function ShouldBuildT2Naval(aiBrain)
    return ShouldBuildDominantTier(aiBrain, "Naval", 2)
end

local function ShouldBuildT3Naval(aiBrain)
    return ShouldBuildDominantTier(aiBrain, "Naval", 3)
end

local function ShouldTechLandToT2(aiBrain)
    return ShouldTechToT2(aiBrain, "Land")
end

local function ShouldTechAirToT2(aiBrain)
    return ShouldTechToT2(aiBrain, "Air")
end

local function ShouldTechNavalToT2(aiBrain)
    return ShouldTechToT2(aiBrain, "Naval")
end

local function ShouldTechLandToT3(aiBrain)
    return ShouldTechToT3(aiBrain, "Land")
end

local function ShouldTechAirToT3(aiBrain)
    return ShouldTechToT3(aiBrain, "Air")
end

local function ShouldTechNavalToT3(aiBrain)
    return ShouldTechToT3(aiBrain, "Naval")
end

local function CountMajorProjectsBeingBuilt(aiBrain)
    if not aiBrain.GetListOfUnits then
        return 0
    end
    local constructors = aiBrain:GetListOfUnits(categories.CONSTRUCTION, false) or {}
    local category = categories.EXPERIMENTAL + categories.NUKE * categories.STRUCTURE
    local count = 0
    for _, unit in pairs(constructors) do
        local destroyed = unit.BeenDestroyed and unit:BeenDestroyed()
        if not destroyed and unit.IsUnitState and unit:IsUnitState("Building") then
            local project = unit.UnitBeingBuilt
            if project and not project.Dead and EntityCategoryContains(category, project) then
                count = count + 1
            end
        end
    end
    return count
end

local function HasMajorProjectSlot(aiBrain)
    local demand = GetDemand(aiBrain)
    return demand
        and demand.MajorProjectSlots > 0
        and CountMajorProjectsBeingBuilt(aiBrain) < demand.MajorProjectSlots
end

local function ShouldBuildExperimental(aiBrain, naval)
    local demand, economy = GetDemand(aiBrain)
    local modules = aiBrain.RedQueenModules
    if not demand
        or not demand.FocusWeights
        or demand.FocusWeights.Experimental < Constants.Policy.StrategicFocusMinimumScore
        or demand.DesiredExperimentals < 1
        or not modules.World
        or (naval and modules.World.MapType ~= "Naval")
        or (not naval and modules.World.MapType == "Naval")
    then
        return false
    end

    if not CanAffordTech(
        economy,
        Constants.Policy.ExperimentalMinimumMassIncome,
        Constants.Policy.ExperimentalMinimumEnergyIncome
    ) then
        return false
    end

    local current = aiBrain:GetCurrentUnits(categories.EXPERIMENTAL)
    return current < demand.DesiredExperimentals
end

local function ShouldBuildLandExperimental(aiBrain)
    return ShouldBuildExperimental(aiBrain, false)
end

local function ShouldBuildNavalExperimental(aiBrain)
    return ShouldBuildExperimental(aiBrain, true)
end

local function ShouldBuildNuke(aiBrain)
    local demand, economy = GetDemand(aiBrain)
    if not demand
        or not demand.FocusWeights
        or demand.FocusWeights.Nuke < Constants.Policy.StrategicFocusMinimumScore
        or demand.DesiredNukes < 1
    then
        return false
    end

    return CanAffordTech(
        economy,
        Constants.Policy.NukeMinimumMassIncome,
        Constants.Policy.NukeMinimumEnergyIncome
    ) and aiBrain:GetCurrentUnits(categories.NUKE * categories.STRUCTURE) < demand.DesiredNukes
end

BuilderGroup {
    BuilderGroupName = "RedQueenTechUpgradeBuilders",
    BuildersType = "PlatoonFormBuilder",

    Builder {
        BuilderName = "Red Queen T1 Land Factory Tech",
        PlatoonTemplate = "T1LandFactoryUpgrade",
        Priority = 910,
        PriorityFunction = Tech2Priority,
        InstanceCount = 1,
        FormRadius = 10000,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldTechLandToT2, {} },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.FACTORY * categories.LAND * categories.TECH1 } },
            { UnitCountBuildConditions, "HaveLessThanUnitsInCategoryBeingUpgraded", { 1, categories.FACTORY * categories.TECH1 } },
        },
    },
    Builder {
        BuilderName = "Red Queen T1 Air Factory Tech",
        PlatoonTemplate = "T1AirFactoryUpgrade",
        Priority = 905,
        PriorityFunction = Tech2Priority,
        InstanceCount = 1,
        FormRadius = 10000,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldTechAirToT2, {} },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.FACTORY * categories.AIR * categories.TECH1 } },
            { UnitCountBuildConditions, "HaveLessThanUnitsInCategoryBeingUpgraded", { 1, categories.FACTORY * categories.TECH1 } },
        },
    },
    Builder {
        BuilderName = "Red Queen T1 Naval Factory Tech",
        PlatoonTemplate = "T1SeaFactoryUpgrade",
        Priority = 900,
        PriorityFunction = Tech2Priority,
        InstanceCount = 1,
        FormRadius = 10000,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldTechNavalToT2, {} },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.FACTORY * categories.NAVAL * categories.TECH1 } },
            { UnitCountBuildConditions, "HaveLessThanUnitsInCategoryBeingUpgraded", { 1, categories.FACTORY * categories.TECH1 } },
        },
    },

    Builder {
        BuilderName = "Red Queen T2 Land Factory Tech",
        PlatoonTemplate = "T2LandFactoryUpgrade",
        Priority = 920,
        PriorityFunction = Tech3Priority,
        InstanceCount = 1,
        FormRadius = 10000,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldTechLandToT3, {} },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.FACTORY * categories.LAND * categories.TECH2 } },
            { UnitCountBuildConditions, "HaveLessThanUnitsInCategoryBeingUpgraded", { 1, categories.FACTORY * categories.TECH2 } },
        },
    },
    Builder {
        BuilderName = "Red Queen T2 Air Factory Tech",
        PlatoonTemplate = "T2AirFactoryUpgrade",
        Priority = 915,
        PriorityFunction = Tech3Priority,
        InstanceCount = 1,
        FormRadius = 10000,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldTechAirToT3, {} },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.FACTORY * categories.AIR * categories.TECH2 } },
            { UnitCountBuildConditions, "HaveLessThanUnitsInCategoryBeingUpgraded", { 1, categories.FACTORY * categories.TECH2 } },
        },
    },
    Builder {
        BuilderName = "Red Queen T2 Naval Factory Tech",
        PlatoonTemplate = "T2SeaFactoryUpgrade",
        Priority = 910,
        PriorityFunction = Tech3Priority,
        InstanceCount = 1,
        FormRadius = 10000,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldTechNavalToT3, {} },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.FACTORY * categories.NAVAL * categories.TECH2 } },
            { UnitCountBuildConditions, "HaveLessThanUnitsInCategoryBeingUpgraded", { 1, categories.FACTORY * categories.TECH2 } },
        },
    },
}

BuilderGroup {
    BuilderGroupName = "RedQueenTierDominanceBuilders",
    BuildersType = "FactoryBuilder",

    Builder {
        BuilderName = "Red Queen T3 Land Dominance",
        PlatoonTemplate = "T3LandBot",
        Priority = 940,
        BuilderType = "Land",
        BuilderConditions = {
            { ShouldBuildT3Land, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.65, 0.90 } },
        },
    },
    Builder {
        BuilderName = "Red Queen T2 Land Dominance",
        PlatoonTemplate = "T2AttackTank",
        Priority = 930,
        BuilderType = "Land",
        BuilderConditions = {
            { ShouldBuildT2Land, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.65, 0.90 } },
        },
    },
    Builder {
        BuilderName = "Red Queen T3 Air Dominance",
        PlatoonTemplate = "T3AirGunship",
        Priority = 940,
        BuilderType = "Air",
        BuilderConditions = {
            { ShouldBuildT3Air, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.65, 0.90 } },
        },
    },
    Builder {
        BuilderName = "Red Queen T2 Air Dominance",
        PlatoonTemplate = "T2AirGunship",
        Priority = 930,
        BuilderType = "Air",
        BuilderConditions = {
            { ShouldBuildT2Air, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.65, 0.90 } },
        },
    },
    Builder {
        BuilderName = "Red Queen T3 Naval Dominance",
        PlatoonTemplate = "T3SeaBattleship",
        Priority = 940,
        BuilderType = "Sea",
        BuilderConditions = {
            { ShouldBuildT3Naval, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.65, 0.90 } },
        },
    },
    Builder {
        BuilderName = "Red Queen T2 Naval Dominance",
        PlatoonTemplate = "T2SeaDestroyer",
        Priority = 930,
        BuilderType = "Sea",
        BuilderConditions = {
            { ShouldBuildT2Naval, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.65, 0.90 } },
        },
    },
}

BuilderGroup {
    BuilderGroupName = "RedQueenEndgameBuilders",
    BuildersType = "EngineerBuilder",

    Builder {
        BuilderName = "Red Queen Land Experimental",
        PlatoonTemplate = "T3EngineerBuilder",
        Priority = 930,
        PriorityFunction = ExperimentalPriority,
        InstanceCount = 1,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldBuildLandExperimental, {} },
            { HasMajorProjectSlot, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyCombined", { 0.85, 1.0 } },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.ENGINEER * categories.TECH3 } },
        },
        BuilderData = {
            Construction = {
                BuildClose = false,
                BaseTemplate = "ExpansionBaseTemplates",
                NearMarkerType = "Rally Point",
                BuildStructures = { "T4LandExperimental1" },
                Location = "LocationType",
            },
        },
    },
    Builder {
        BuilderName = "Red Queen Naval Experimental",
        PlatoonTemplate = "T3EngineerBuilder",
        Priority = 930,
        PriorityFunction = ExperimentalPriority,
        InstanceCount = 1,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldBuildNavalExperimental, {} },
            { HasMajorProjectSlot, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyCombined", { 0.85, 1.0 } },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.ENGINEER * categories.TECH3 } },
            { MarkerBuildConditions, "MarkerLessThanDistance", { "Naval Area", 400 } },
        },
        BuilderData = {
            Construction = {
                BuildClose = false,
                BaseTemplate = "ExpansionBaseTemplates",
                NearMarkerType = "Naval Area",
                BuildStructures = { "T4SeaExperimental1" },
                Location = "LocationType",
            },
        },
    },
    -- FAF gates the Quantum Gateway behind already owning more than one
    -- experimental (T3 Gate Engineer, AIFactoryConstructionBuilders), which no
    -- Red Queen match has ever reached: it built zero support commanders across
    -- match 27741743 and its verification run while the two strongest humans
    -- built 43 and 37. This gates on the tier and power that actually pay for a
    -- gateway instead.
    Builder {
        BuilderName = "Red Queen Quantum Gateway",
        PlatoonTemplate = "T3EngineerBuilder",
        Priority = 910,
        InstanceCount = 1,
        BuilderType = "Any",
        BuilderConditions = {
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyCombined", { 0.85, 1.0 } },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.ENGINEER * categories.TECH3 } },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 1, categories.ENERGYPRODUCTION * categories.TECH3 } },
            { UnitCountBuildConditions, "HaveLessThanUnitsWithCategory", { 1, categories.GATE * categories.STRUCTURE } },
            { UnitCountBuildConditions, "UnitCapCheckLess", { 0.8 } },
        },
        BuilderData = {
            Construction = {
                BuildClose = true,
                BuildStructures = { "T3QuantumGate" },
                Location = "LocationType",
            },
        },
    },
    Builder {
        BuilderName = "Red Queen Strategic Missile",
        PlatoonTemplate = "T3EngineerBuilder",
        Priority = 940,
        PriorityFunction = NukePriority,
        InstanceCount = 1,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldBuildNuke, {} },
            { HasMajorProjectSlot, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyCombined", { 0.85, 1.0 } },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.ENGINEER * categories.TECH3 } },
        },
        BuilderData = {
            Construction = {
                BuildClose = true,
                BuildStructures = { "T3StrategicMissile" },
                Location = "LocationType",
            },
        },
    },
}

BuilderGroup {
    BuilderGroupName = "RedQueenCounterFactoryBuilders",
    BuildersType = "FactoryBuilder",

    Builder {
        BuilderName = "Red Queen T3 Gunship Counter",
        PlatoonTemplate = "T3AirGunship",
        Priority = 975,
        BuilderType = "Air",
        BuilderConditions = {
            { ShouldBuildGunships, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.70, 0.95 } },
            { UnitCountBuildConditions, "LocationFactoriesBuildingLess", { "LocationType", 3, categories.AIR * categories.GROUNDATTACK } },
        },
    },
    Builder {
        BuilderName = "Red Queen T2 Gunship Counter",
        PlatoonTemplate = "T2AirGunship",
        Priority = 965,
        BuilderType = "Air",
        BuilderConditions = {
            { ShouldBuildGunships, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.70, 0.95 } },
            { UnitCountBuildConditions, "LocationFactoriesBuildingLess", { "LocationType", 3, categories.AIR * categories.GROUNDATTACK } },
        },
    },
    Builder {
        BuilderName = "Red Queen T1 Gunship Counter",
        PlatoonTemplate = "T1Gunship",
        Priority = 955,
        BuilderType = "Air",
        BuilderConditions = {
            { ShouldBuildGunships, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.70, 0.95 } },
            { UnitCountBuildConditions, "LocationFactoriesBuildingLess", { "LocationType", 3, categories.AIR * categories.GROUNDATTACK } },
        },
    },

    Builder {
        BuilderName = "Red Queen T3 Fighter Counter",
        PlatoonTemplate = "T3AirFighter",
        Priority = 980,
        BuilderType = "Air",
        BuilderConditions = {
            { ShouldBuildAirDefense, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.70, 0.95 } },
            { UnitCountBuildConditions, "LocationFactoriesBuildingLess", { "LocationType", 3, categories.AIR * categories.ANTIAIR - categories.BOMBER } },
        },
    },
    Builder {
        BuilderName = "Red Queen T2 Fighter-Bomber Counter",
        PlatoonTemplate = "T2FighterBomber",
        Priority = 970,
        BuilderType = "Air",
        BuilderConditions = {
            { ShouldBuildAirDefense, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.70, 0.95 } },
            { UnitCountBuildConditions, "LocationFactoriesBuildingLess", { "LocationType", 3, categories.AIR * categories.ANTIAIR - categories.BOMBER } },
        },
    },
    Builder {
        BuilderName = "Red Queen T1 Fighter Counter",
        PlatoonTemplate = "T1AirFighter",
        Priority = 960,
        BuilderType = "Air",
        BuilderConditions = {
            { ShouldBuildAirDefense, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.70, 0.95 } },
            { UnitCountBuildConditions, "LocationFactoriesBuildingLess", { "LocationType", 3, categories.AIR * categories.ANTIAIR - categories.BOMBER } },
        },
    },
}

-- FAF's own T3 Sub Commander builder names PlatoonTemplate 'T3LandSubCommander',
-- which is not a registered template -- only 'T3LandSubCommander1' exists, and
-- that one is a three-unit HuntAI combat platoon. A support commander produced
-- through it would never reach an engineer manager. This template produces a
-- single support commander with no plan, so it returns to the pool, is claimed
-- by a base manager like any other engineer, and becomes available to forward
-- base construction with the highest build power on the field.
PlatoonTemplate {
    Name = "RedQueenSupportCommander",
    FactionSquads = {
        UEF = { { "uel0301", 1, 1, "support", "None" } },
        Aeon = { { "ual0301", 1, 1, "support", "None" } },
        Cybran = { { "url0301", 1, 1, "support", "None" } },
        Seraphim = { { "xsl0301", 1, 1, "support", "None" } },
    },
}

BuilderGroup {
    BuilderGroupName = "RedQueenSupportCommanderBuilders",
    BuildersType = "FactoryBuilder",

    Builder {
        BuilderName = "Red Queen Support Commander",
        PlatoonTemplate = "RedQueenSupportCommander",
        Priority = 900,
        BuilderConditions = {
            { InstantBuildConditions, "BrainNotLowMassMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.9, 1.1 } },
            { UnitCountBuildConditions, "UnitCapCheckLess", { 0.8 } },
            { UnitCountBuildConditions, "HaveLessThanUnitsWithCategory", { 6, categories.SUBCOMMANDER } },
        },
        BuilderType = "Gate",
    },
}
