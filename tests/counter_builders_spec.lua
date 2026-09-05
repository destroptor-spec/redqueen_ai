local categoryMetatable = {}
categoryMetatable.__mul = function() return setmetatable({}, categoryMetatable) end
categoryMetatable.__add = function() return setmetatable({}, categoryMetatable) end
categoryMetatable.__sub = function() return setmetatable({}, categoryMetatable) end

categories = setmetatable({}, {
    __index = function(tableValue, key)
        local category = setmetatable({}, categoryMetatable)
        rawset(tableValue, key, category)
        return category
    end,
})

function EntityCategoryContains()
    return true
end

local builders = {}
local groups = {}

function Builder(definition)
    builders[definition.BuilderName] = definition
    return definition
end

function BuilderGroup(definition)
    groups[definition.BuilderGroupName] = definition
    return definition
end

local platoonTemplates = {}
function PlatoonTemplate(definition)
    platoonTemplates[definition.Name] = definition
    return definition
end

local constants = {
    Policy = {
        StrategicFocusMinimumScore = 35,
        Tech2MinimumMassIncome = 4,
        Tech2MinimumEnergyIncome = 60,
        Tech3MinimumMassIncome = 10,
        Tech3MinimumEnergyIncome = 250,
        ExperimentalMinimumMassIncome = 22,
        ExperimentalMinimumEnergyIncome = 800,
        NukeMinimumMassIncome = 30,
        NukeMinimumEnergyIncome = 1200,
    },
}

function import(path)
    if path == "/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua" then
        return constants
    end
    error("unexpected import: " .. tostring(path))
end

dofile("lua/AI/RedQueen/CounterBuilders.lua")

assert(groups.RedQueenCounterFactoryBuilders, "counter factory group must register")
assert(groups.RedQueenTechUpgradeBuilders, "tech upgrade group must register")
assert(groups.RedQueenTierDominanceBuilders, "tier dominance group must register")
assert(groups.RedQueenEndgameBuilders, "endgame builder group must register")

local economy = {
    StallRisk = false,
    MassIncome = 10,
    EnergyIncome = 250,
    MassStoredRatio = 0.10,
    EnergyStoredRatio = 0.15,
    MassTrend = 0,
    EnergyTrend = 0,
}
local demand = {
    Doctrine = "GunshipCounter",
    Gunships = 0.55,
    AntiAir = 0.10,
    FocusWeights = {
        Army = 60,
        Tech2 = 70,
        Tech3 = 70,
        Experimental = 0,
        Nuke = 0,
    },
    PrimaryFocus = "Tech2",
    MajorProjectSlots = 0,
    DesiredExperimentals = 0,
    DesiredNukes = 0,
    DefenseAlert = { Active = false },
    TierPolicy = {
        Land = { Highest = 1 },
        Air = { Highest = 1 },
        Naval = { Highest = 1 },
    },
}
local constructors = {}
local brain = {
    RedQueenModules = {
        Economy = { State = economy },
        Strategy = { ProductionDemand = demand },
        World = { MapType = "Land" },
    },
    GetCurrentUnits = function() return 0 end,
    GetListOfUnits = function() return constructors end,
}

local gunshipCondition = builders["Red Queen T3 Gunship Counter"].BuilderConditions[1][1]
assert(gunshipCondition(brain), "land-loss doctrine must enable native gunship builders")

local t2Builder = builders["Red Queen T1 Land Factory Tech"]
local t2Condition = t2Builder.BuilderConditions[1][1]
assert(t2Condition(brain), "a weighted T2 focus must enable a relevant factory upgrade")
assert(t2Builder:PriorityFunction(brain) == 935, "primary T2 weight must map to a deterministic live priority")
demand.FocusWeights.Tech2 = 34
assert(not t2Condition(brain), "sub-threshold T2 weight must disable the upgrade")
assert(t2Builder:PriorityFunction(brain) == 0, "sub-threshold strategic builders must have zero priority")
demand.FocusWeights.Tech2 = 70

local navalT2Condition = builders["Red Queen T1 Naval Factory Tech"].BuilderConditions[1][1]
assert(not navalT2Condition(brain), "land maps must not spend strategic focus on naval tier coverage")

economy.StallRisk = true
assert(not t2Condition(brain), "strategic focus must not override genuine recovery")
economy.StallRisk = false

local t3Condition = builders["Red Queen T2 Land Factory Tech"].BuilderConditions[1][1]
assert(t3Condition(brain), "a weighted T3 focus must enable a relevant factory upgrade")
economy.MassIncome = 9
assert(not t3Condition(brain), "T3 must retain its economic safety floor")

economy.MassIncome = 10
demand.TierPolicy.Land.Highest = 3
local dominantT3Condition = builders["Red Queen T3 Land Dominance"].BuilderConditions[1][1]
assert(dominantT3Condition(brain), "live T3 access must keep a dominant-tier land queue available")
demand.FocusWeights.Tech3 = 0
assert(t3Condition(brain), "T3 access must keep upgrading remaining T2 land factories")
demand.DefenseAlert.Active = true
assert(not t3Condition(brain), "defense alerts must pause new factory tech work")
demand.DefenseAlert.Active = false
demand.FocusWeights.Tech3 = 70

economy.MassIncome = 30
economy.EnergyIncome = 1200
demand.FocusWeights.Experimental = 80
demand.PrimaryFocus = "Experimental"
demand.MajorProjectSlots = 2
demand.DesiredExperimentals = 2
local experimentalBuilder = builders["Red Queen Land Experimental"]
local experimentalCondition = experimentalBuilder.BuilderConditions[1][1]
local projectSlotCondition = experimentalBuilder.BuilderConditions[2][1]
assert(experimentalCondition(brain), "evidence-weighted breakthrough focus must enable an experimental")
assert(projectSlotCondition(brain), "available director project slots must allow construction")
assert(experimentalBuilder:PriorityFunction(brain) == 965, "experimental focus must map to live builder priority")

demand.FocusWeights.Nuke = 90
demand.PrimaryFocus = "Nuke"
demand.DesiredNukes = 2
local nukeBuilder = builders["Red Queen Strategic Missile"]
local nukeCondition = nukeBuilder.BuilderConditions[1][1]
assert(nukeCondition(brain), "evidence-weighted siege focus must enable a strategic missile project")
assert(nukeBuilder:PriorityFunction(brain) == 995, "nuclear focus must map to live builder priority")

local project = { Dead = false }
local constructor = {
    UnitBeingBuilt = project,
    BeenDestroyed = function() return false end,
    IsUnitState = function(_, state) return state == "Building" end,
}
constructors = { constructor }
demand.MajorProjectSlots = 1
assert(not projectSlotCondition(brain), "a full major-project portfolio must block another expensive start")
demand.MajorProjectSlots = 2
assert(projectSlotCondition(brain), "exceptional safe headroom must allow a second major project")

print("Red Queen counter builder contracts passed")

-- Support commander production. FAF's own T3 Sub Commander builder names a
-- platoon template that is not registered, and the one real SACU template is a
-- three-unit HuntAI combat platoon whose units never reach an engineer manager.
local sacuTemplate = platoonTemplates["RedQueenSupportCommander"]
assert(sacuTemplate, "support commander production needs its own platoon template")
assert(not sacuTemplate.Plan, "a support commander must return to the pool, not take a combat plan")
for _, faction in pairs({ "UEF", "Aeon", "Cybran", "Seraphim" }) do
    local squad = sacuTemplate.FactionSquads[faction]
    assert(squad, "support commanders must be buildable by every faction: " .. faction)
    assert(squad[1][2] == 1 and squad[1][3] == 1, "one support commander per platoon: " .. faction)
end

local sacuBuilder = builders["Red Queen Support Commander"]
assert(sacuBuilder, "support commander builder must be registered")
assert(sacuBuilder.BuilderType == "Gate", "support commanders are produced by a Quantum Gateway")
assert(
    sacuBuilder.PlatoonTemplate == "RedQueenSupportCommander",
    "the support commander builder must use the registered template"
)
assert(groups["RedQueenSupportCommanderBuilders"], "support commander group must exist")
assert(
    groups["RedQueenSupportCommanderBuilders"].BuildersType == "FactoryBuilder",
    "gateway production is factory production"
)

local gateway = builders["Red Queen Quantum Gateway"]
assert(gateway, "a Quantum Gateway builder is required before support commanders can exist")
local gatewayConditions = ""
for _, condition in pairs(gateway.BuilderConditions) do
    gatewayConditions = gatewayConditions .. tostring(condition[2])
end
assert(
    not string.find(gatewayConditions, "Experimental"),
    "the gateway must not inherit FAF's requirement to already own experimentals"
)
print("Red Queen support commander contracts passed")
