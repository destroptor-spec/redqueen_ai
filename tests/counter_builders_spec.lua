-- Category expressions carry a composed name so a composite has a stable
-- identity. The engine returns opaque handles, and an earlier version of this
-- fake returned a fresh empty table per operation -- which meant a contract
-- could never key anything on `categories.NAVAL * categories.MOBILE`, because
-- the expression built in the test was never equal to the one built in the code
-- under test.
local categoryMetatable = {}
local function composite(operator)
    return function(left, right)
        local name = "(" .. tostring(left.Name) .. operator .. tostring(right.Name) .. ")"
        return setmetatable({ Name = name }, categoryMetatable)
    end
end
categoryMetatable.__mul = composite("*")
categoryMetatable.__add = composite("+")
categoryMetatable.__sub = composite("-")

categories = setmetatable({}, {
    __index = function(tableValue, key)
        local category = setmetatable({ Name = key }, categoryMetatable)
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
        EngineerReplacementPriorityCeiling = 910,
        EngineerRecoveryFloor = 3,
        UpperTierEngineerFloor = 3,
        StrategicFocusMinimumScore = 35,
        Tech2MinimumMassIncome = 4,
        Tech2MinimumEnergyIncome = 60,
        Tech3MinimumMassIncome = 10,
        Tech3MinimumEnergyIncome = 250,
        ExperimentalMinimumMassIncome = 22,
        ExperimentalMinimumEnergyIncome = 800,
        NukeMinimumMassIncome = 30,
        NukeMinimumEnergyIncome = 1200,
        NavalDominanceMinimumDemand = 0.30,
        LargeEnergyDeficit = 150,
        ExperimentalConcurrentMaximum = 2,
        ExperimentalSecondProjectMassIncome = 40,
        ExperimentalUtilityMassIncome = 45,
        ExperimentalEscortMinimumFleet = 4,
    },
}

-- The experimental catalog is pure data and pure functions, so the contract
-- loads the real module rather than a stub: a fake catalog could not catch a
-- template key that resolves to the wrong unit, which is the defect this
-- classification exists to prevent.
-- Load the module the way the engine does. FAF's import() runs the file in a
-- fresh environment and returns *that environment*, ignoring any value the file
-- returns. dofile() does the opposite, so a module exporting via `return {...}`
-- passes a dofile-based contract and then fails in game with a strict-global
-- error -- which is exactly what happened here.
local function importModule(path)
    local environment = setmetatable({}, { __index = _G })
    setfenv(assert(loadfile(path)), environment)()
    return environment
end

local experimentals = importModule("lua/AI/RedQueen/Experimentals.lua")

function import(path)
    if path == "/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua" then
        return constants
    end
    if path == "/mods/TheRedQueen/lua/AI/RedQueen/Experimentals.lua" then
        return experimentals
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
-- Which layers can actually reach an enemy start. The experimental path gate
-- asks this per candidate, so the stub answers per layer rather than yes or no:
-- a catalog entry gated on the wrong graph is exactly the defect under test.
local reachableLayers = { Land = true, Amphibious = true, Air = true, Water = true }
local world = {
    MapType = "Land",
    StartPosition = { 10, 0, 10 },
    EnemyStarts = { { Position = { 90, 0, 90 } } },
    GetNavalApproach = function() return reachableLayers.Water and { 80, 0, 80 } or nil end,
    GetClosestEnemyStart = function(_, origin, layer)
        if not origin then
            return nil
        end
        return reachableLayers[layer] and { 90, 0, 90 } or nil
    end,
}
local unitCounts = {}
local brain = {
    RedQueenContext = { FactionIndex = 2 },
    RedQueenModules = {
        Economy = { State = economy },
        Strategy = { ProductionDemand = demand },
        World = world,
    },
    GetCurrentUnits = function(_, category)
        return unitCounts[category and category.Name] or 0
    end,
    GetListOfUnits = function() return constructors end,
}

local gunshipCondition = builders["Red Queen T3 Gunship Counter"].BuilderConditions[1][1]
assert(gunshipCondition(brain), "land-loss doctrine must enable native gunship builders")

-- Scouts are asked for by share of the army, the same way gunships are. Before
-- this existed demand.Scouts was computed, clamped and reported and nothing
-- consumed it: every builder here subtracts categories.SCOUT, so every scout
-- came from FAF's own builders. The isolation arms proved it -- dispatch-only
-- reproduced combined tick for tick across eight LandLarge cells, because the
-- only difference between those arms was a number nothing read.
local scoutCategory = (categories.MOBILE * categories.SCOUT).Name
local scoutArmy = (categories.MOBILE * (categories.LAND + categories.AIR)
    - categories.ENGINEER - categories.COMMAND - categories.SCOUT).Name
for _, name in ipairs({ "Red Queen Air Scout", "Red Queen Land Scout" }) do
    assert(builders[name], name .. " must register, or demand.Scouts drives nothing")
end
local scoutCondition = builders["Red Queen Air Scout"].BuilderConditions[1][1]
demand.Scouts = 0.10
unitCounts[scoutArmy] = 40
unitCounts[scoutCategory] = 2
assert(scoutCondition(brain),
    "two scouts against a forty-strong army at a tenth share must ask for more")
unitCounts[scoutCategory] = 4
assert(not scoutCondition(brain),
    "and the share being met must stop the request, so scouts cannot crowd the queue")

-- The floor keeps one scout coming for an army too small to earn a share.
unitCounts[scoutArmy] = 2
unitCounts[scoutCategory] = 0
assert(scoutCondition(brain), "a small army must still get its first pair of eyes")
unitCounts[scoutCategory] = 1
assert(not scoutCondition(brain), "but only the floor, not a scout per unit")

-- A stalling economy buys nothing, scouts included.
unitCounts[scoutCategory] = 0
economy.StallRisk = true
assert(not scoutCondition(brain), "a stalling economy must not spend on scouts")
economy.StallRisk = false
unitCounts[scoutArmy] = nil
unitCounts[scoutCategory] = nil
demand.Scouts = nil

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
local experimentalBuilder = builders["Red Queen Assault Experimental Land"]
local experimentalCondition = experimentalBuilder.BuilderConditions[1][1]
local experimentalTemplate = experimentalBuilder.BuilderConditions[1][2][1]
local projectSlotCondition = experimentalBuilder.BuilderConditions[2][1]
assert(experimentalTemplate == "T4LandExperimental1",
    "the gate must be parameterised with the key the builder actually builds")
assert(experimentalCondition(brain, experimentalTemplate),
    "evidence-weighted breakthrough focus must enable a reachable assault experimental")
assert(projectSlotCondition(brain), "available director project slots must allow construction")
assert(experimentalBuilder:PriorityFunction(brain) == 965, "experimental focus must map to live builder priority")

-- Role ordering must survive into the runtime priority. FAF replaces the static
-- Priority field with whatever PriorityFunction returns, so seven builders
-- sharing one function would otherwise all tie and the declared 930-to-924
-- ordering would never take effect.
local siegeBuilder = builders["Red Queen Siege Experimental Rapid Artillery"]
assert(siegeBuilder, "Aeon's Salvation needs its own builder")
local assaultPriority = experimentalBuilder:PriorityFunction(brain)
local siegePriority = siegeBuilder:PriorityFunction(brain)
assert(assaultPriority > siegePriority,
    "an assault experimental that arrives must outrank a siege piece that may not")

-- A builder whose key this faction must not build has no priority at all, so it
-- cannot win a sort and then fail its condition every cycle.
local rejectedBuilder = builders["Red Queen Assault Experimental Megabot"]
assert(rejectedBuilder:PriorityFunction(brain) == 0,
    "a key belonging to another faction must carry no priority here")
brain.RedQueenContext.FactionIndex = 3
assert(rejectedBuilder:PriorityFunction(brain) > 0,
    "Cybran's Megalith builder must carry priority for Cybran")
brain.RedQueenContext.FactionIndex = 2

-- The classification is what makes an experimental worth its mass, so the
-- contract drives the real catalog rather than asserting on constants.
--
-- Aeon's Galactic Colossus is RULEUMT_Amphibious. Gating it on the Land graph
-- asks about a graph it does not use -- the same defect that once left a whole
-- hover army without orders -- so withdrawing Amphibious alone must stop it.
reachableLayers.Amphibious = false
assert(not experimentalCondition(brain, "T4LandExperimental1"),
    "an assault experimental with no amphibious route must not be started")
reachableLayers.Amphibious = true
assert(experimentalCondition(brain, "T4LandExperimental1"),
    "restoring the amphibious route must make it available again")

-- Air is always pathable, so an air assault experimental survives losing every
-- surface route.
reachableLayers.Amphibious = false
reachableLayers.Water = false
assert(experimentalCondition(brain, "T4AirExperimental1"),
    "an air assault experimental must not be gated on surface routes")
reachableLayers.Amphibious = true
reachableLayers.Water = true

-- Template keys that resolve to the wrong unit must stay inert. FAF maps Aeon
-- T4Artillery to uab2302, Tech 3 heavy artillery, so a builder trusting the key
-- would spend an endgame engineer on a Tech 3 structure.
assert(not experimentalCondition(brain, "T4Artillery"),
    "Aeon T4Artillery resolves to Tech 3 artillery and must never be built as an experimental")
assert(not experimentalCondition(brain, "T4LandExperimental3"),
    "a key another faction owns must not be buildable here")

-- Cybran and Seraphim T4SeaExperimental1 resolve to a Tech 1 land factory.
brain.RedQueenContext.FactionIndex = 3
assert(not experimentalCondition(brain, "T4SeaExperimental1"),
    "Cybran T4SeaExperimental1 resolves to a Tech 1 land factory and must stay inert")
assert(experimentalCondition(brain, "T4LandExperimental3"),
    "Cybran must be able to build its Megalith")
assert(experimentalCondition(brain, "T4LandExperimental2"),
    "Cybran mobile siege must be available when it can reach")
brain.RedQueenContext.FactionIndex = 4
assert(not experimentalCondition(brain, "T4SeaExperimental1"),
    "Seraphim T4SeaExperimental1 resolves to a Tech 1 land factory and must stay inert")
assert(experimentalCondition(brain, "T4Artillery"),
    "Seraphim T4Artillery is the Yolona Oss and must remain buildable")

-- A support experimental cannot engage ground, so it needs a fleet to escort.
brain.RedQueenContext.FactionIndex = 1
local navalMobile = (categories.NAVAL * categories.MOBILE).Name
assert(not experimentalCondition(brain, "T4SeaExperimental1"),
    "an Atlantis with no fleet to escort must not be started")
unitCounts[navalMobile] = constants.Policy.ExperimentalEscortMinimumFleet
assert(experimentalCondition(brain, "T4SeaExperimental1"),
    "an Atlantis beside a real fleet must be available")
unitCounts[navalMobile] = nil
assert(not experimentalCondition(brain, "T4AirExperimental1"),
    "UEF T4AirExperimental1 resolves to the land-bound Fatboy and must stay inert")
brain.RedQueenContext.FactionIndex = 2

-- Volume is a flow, so the target stays ahead of the owned count and owning
-- some is not a reason to stop. The brake is the per-role in-flight allowance.
--
-- Work in flight is reported by blueprint, which is why the gate classifies it
-- rather than counting raw experimentals: one assault walker under construction
-- must block a second walker while still leaving a game-ender available.
local function building(blueprint)
    return {
        BeenDestroyed = function() return false end,
        IsUnitState = function(_, state) return state == "Building" end,
        UnitBeingBuilt = {
            Dead = false,
            GetBlueprint = function() return { BlueprintId = blueprint } end,
        },
    }
end

local function priorityFor(template)
    for _, builder in pairs(builders) do
        local first = (builder.BuilderConditions or {})[1] or {}
        if first[2] and first[2][1] == template then
            return builder:PriorityFunction(brain)
        end
    end
end

-- Crowding must lower a role's rank and never veto it. The in-flight count
-- cannot tell Red Queen's projects from the engine's, and FAF's own builders
-- keep assault experimentals going, so a veto fired on their work and locked
-- Red Queen out for whole matches: two runs built nothing and lost.
constructors = { building("ual0401") }
assert(experimentalCondition(brain, "T4LandExperimental1"),
    "work in flight must never veto a role -- the count includes the engine's own projects")
assert(priorityFor("T3RapidArtillery") > priorityFor("T4LandExperimental1"),
    "with an assault project already running the next slot must prefer a game-ender")

constructors = { building("xab2307") }
assert(experimentalCondition(brain, "T3RapidArtillery"),
    "a game-ender in flight must not veto another")
assert(priorityFor("T4LandExperimental1") > priorityFor("T3RapidArtillery"),
    "with a game-ender running the on-grid force takes the next slot")

-- Two of a role in flight must rank below one, so crowding keeps accumulating.
constructors = { building("ual0401"), building("url0402") }
brain.RedQueenContext.FactionIndex = 3
local crowdedTwice = priorityFor("T4LandExperimental1")
constructors = { building("ual0401") }
local crowdedOnce = priorityFor("T4LandExperimental1")
assert(crowdedOnce > crowdedTwice, "each project of a role must lower that role's rank further")
brain.RedQueenContext.FactionIndex = 2
constructors = {}

-- Utility experimentals are built rather than merely classified, on their own
-- economic justification: a Paragon is 250200 mass and a Novax 32000.
economy.MassIncome = constants.Policy.ExperimentalUtilityMassIncome - 1
assert(not experimentalCondition(brain, "T4EconExperimental"),
    "a resource generator must wait for an economy that would otherwise idle")
economy.MassIncome = constants.Policy.ExperimentalUtilityMassIncome
assert(experimentalCondition(brain, "T4EconExperimental"),
    "at the utility income a Paragon becomes a legitimate project")
unitCounts[(categories.EXPERIMENTAL * categories.ECONOMIC).Name] = 1
assert(not experimentalCondition(brain, "T4EconExperimental"),
    "a second Paragon buys nothing")
unitCounts[(categories.EXPERIMENTAL * categories.ECONOMIC).Name] = nil
brain.RedQueenContext.FactionIndex = 1
assert(experimentalCondition(brain, "T4SatelliteExperimental"),
    "UEF's satellite is the intel case and must be reachable")
assert(not experimentalCondition(brain, "T4EconExperimental"),
    "UEF has no resource generator; the key belongs to Aeon alone")
brain.RedQueenContext.FactionIndex = 2
assert(not experimentalCondition(brain, "T4SatelliteExperimental"),
    "Aeon has no satellite; the key belongs to UEF alone")
economy.MassIncome = 30

-- Ranking: the on-grid force outranks a game-ender, which outranks utility.
local ranks = {}
for name, template in pairs({
    assault = "T4LandExperimental1",
    siege = "T3RapidArtillery",
    economy = "T4EconExperimental",
}) do
    for _, builder in pairs(builders) do
        local conditions = builder.BuilderConditions or {}
        local first = conditions[1] or {}
        if first[2] and first[2][1] == template then
            ranks[name] = builder:PriorityFunction(brain)
        end
    end
end
assert(ranks.assault > ranks.siege, "an experimental that arrives outranks one that shells")
assert(ranks.siege > ranks.economy, "a game-ender outranks an economy multiplier")

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

-- First-tier naval production is terrain-gated: on a water map the naval
-- factories must actually produce, and on a dry map nothing changes.
--
-- SCMP_037 held three to five naval factories and produced six warships all
-- match against the opponent's twenty-nine, because the tier-dominance group
-- only ever fired at Tech 2 and 3 while naval sat at Tech 1.
local t1Naval = builders["Red Queen T1 Naval Dominance"]
assert(t1Naval, "a first-tier naval dominance builder must exist")
assert(t1Naval.PlatoonTemplate == "T1SeaFrigate", "first-tier naval must build frigates")
assert(t1Naval.BuilderType == "Sea", "first-tier naval must sort onto the sea factory list")
local t1NavalCondition = t1Naval.BuilderConditions[1][1]

demand.Naval = 0.55
demand.TierPolicy = { Naval = { Highest = 1 } }
economy.StallRisk = false
assert(t1NavalCondition(brain), "a water map with naval at first tier must produce frigates")

demand.Naval = 0.05
assert(not t1NavalCondition(brain), "a dry map must not gain first-tier naval production")

demand.Naval = 0.55
demand.TierPolicy = { Naval = { Highest = 2 } }
assert(not t1NavalCondition(brain),
    "once naval reaches a higher tier the first-tier builder must stand down")

-- Energy is the one input Red Queen gates itself on but never produced. On
-- Fields of Isis the economy peaked at 212 a tick against a 250 Tech 3 gate and
-- stayed there all match, finishing with three Tech 3 units to the opponent's
-- forty-four. This must fire only when energy alone is missing.
assert(groups.RedQueenEnergyBuilders, "the energy builder group must register")
local energyT3 = builders["Red Queen Tech Energy T3"]
local energyT2 = builders["Red Queen Tech Energy T2"]
assert(energyT3 and energyT2, "both engineer tiers must be able to raise power")
assert(energyT3.BuilderData.Construction.BuildStructures[1] == "T3EnergyProduction")
assert(energyT2.BuilderData.Construction.BuildStructures[1] == "T2EnergyProduction")
local energyLarge = energyT3.BuilderConditions[1][1]
local energySmall = energyT2.BuilderConditions[1][1]

-- Fields of Isis: mass clears the Tech 3 gate at 16, energy sits at 212 against
-- 250. A 38 shortfall is one Tech 2 generator, not a Tech 3 one.
economy.StallRisk = false
economy.MassIncome = 16
economy.EnergyIncome = 212
assert(energySmall(brain), "a small shortfall must be closed with Tech 2 power")
assert(not energyLarge(brain),
    "a 38 shortfall must not buy a 57600-energy Tech 3 generator; that "
    .. "over-investment cost the Sentry Point victory")

-- A genuine chasm justifies the expensive generator.
unitCounts[(categories.ENGINEER * categories.TECH3).Name] = 1
economy.EnergyIncome = 40
assert(energyLarge(brain), "a large shortfall justifies a Tech 3 generator")
assert(not energySmall(brain), "the cheap arm must stand down when Tech 3 is warranted")

unitCounts[(categories.ENGINEER * categories.TECH3).Name] = 0
economy.MassIncome = 10
economy.EnergyIncome = 90
assert(energySmall(brain),
    "a T2-only army must be able to close a large deficit before unlocking T3")

-- Energy already sufficient: nothing to fix, do not divert engineers.
economy.EnergyIncome = 260
assert(not energySmall(brain) and not energyLarge(brain),
    "a satisfied energy gate must not divert engineers to power")

-- Mass is the shortage, not energy: power would not unblock anything.
economy.MassIncome = 2
economy.EnergyIncome = 20
assert(not energySmall(brain) and not energyLarge(brain),
    "when mass is short too, power is not the binding constraint")

-- An opening economy sitting on the Tech 2 gate must be left alone.
economy.MassIncome = 4.5
economy.EnergyIncome = 56
assert(not energySmall(brain) and not energyLarge(brain),
    "the opening economy must not divert engineers to power at the Tech 2 gate")

-- A genuine stall must never be answered by starting more construction.
economy.MassIncome = 16
economy.EnergyIncome = 212
economy.StallRisk = true
assert(not energySmall(brain) and not energyLarge(brain),
    "a stalling economy must not start new power")
economy.StallRisk = false

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
-- Engineer replacement must never outrank the army that prevents the losses.
--
-- The shared priority function used to ignore the tier and return
-- min(1000, 850 + shortfall * 20) for all three builders. Since each loss adds
-- EngineerLossReplacementFactor to the desired count, four deaths reached 930
-- and tied the Tech 2 mainline, five passed Tech 3 Land Dominance at 940, and
-- eight reached 1000 -- so a few engineer deaths stopped unit production in
-- every factory. Observed directly in a match.
local engineerT1 = builders["Red Queen Engineer T1"]
local engineerT2 = builders["Red Queen Engineer T2"]
local engineerT3 = builders["Red Queen Engineer T3"]
assert(engineerT1 and engineerT2 and engineerT3,
    "the engineer builders must be registered")

-- Counts are per tier, because the priority function now asks per tier. The
-- previous fake answered one number for every category -- exactly the
-- conflation the fix removes, and it would have hidden the fix entirely.
local engineerCounts = { 1, 0, 0 }
local engineerInFlight = { 0, 0, 0 }
local engineerCategoryName = {
    (categories.ENGINEER * categories.MOBILE).Name,
    (categories.ENGINEER * categories.MOBILE
        * (categories.TECH2 + categories.TECH3)).Name,
    (categories.ENGINEER * categories.MOBILE * categories.TECH3).Name,
}
local function EngineerTierOf(category)
    for tier, name in ipairs(engineerCategoryName) do
        if category.Name == name then
            return tier
        end
    end
    error("the priority function asked for an unexpected category: "
        .. tostring(category.Name))
end
-- held is every mobile engineer the army holds, the way Tech 1 counts them;
-- tech2 and tech3 are the engineers at those tiers, which are a subset of it.
local function SetEngineers(held, building, tech2, tech3, tech2Building)
    engineerCounts = { held, tech2 or 0, tech3 or 0 }
    engineerInFlight = { building or 0, tech2Building or 0, 0 }
end

local engineerBrain = {
    RedQueenContext = { FactionIndex = 2 },
    RedQueenModules = {
        Economy = { State = economy },
        Strategy = { ProductionDemand = demand },
        World = world,
    },
    GetCurrentUnits = function(_, category)
        return engineerCounts[EngineerTierOf(category)]
    end,
    GetListOfUnits = function(_, category)
        local tier = EngineerTierOf(category)
        local all = {}
        for index = 1, engineerCounts[tier] + engineerInFlight[tier] do
            all[index] = index
        end
        return all
    end,
}

-- A large shortfall from repeated losses stays below combat production.
demand.DesiredEngineers = 18
SetEngineers(12, 0)
local capped = engineerT1:PriorityFunction(engineerBrain)
assert(capped > 0, "a real shortfall must still ask for engineers, got " .. tostring(capped))
assert(capped <= constants.Policy.EngineerReplacementPriorityCeiling,
    "replacement must stay below combat production, got " .. tostring(capped))

-- Engineers already under construction count, so several factories cannot each
-- answer the same missing engineer.
SetEngineers(12, 6)
assert(engineerT1:PriorityFunction(engineerBrain) == 0,
    "engineers already being built must satisfy the shortfall")
-- Compared below the ceiling, or both readings clamp to it and the effect is
-- invisible. Held plus building stays at or above the recovery floor so the
-- exception is not what is being measured.
demand.DesiredEngineers = 8
SetEngineers(4, 0)
local uncommitted = engineerT1:PriorityFunction(engineerBrain)
SetEngineers(4, 2)
local partly = engineerT1:PriorityFunction(engineerBrain)
assert(partly > 0 and partly < uncommitted,
    "partial in-flight production must reduce the demand, got " .. tostring(partly)
        .. " against " .. tostring(uncommitted))
demand.DesiredEngineers = 18

-- Construction recovery is the exception: an army with almost no engineers
-- cannot rebuild anything, so that case outranks everything.
SetEngineers(1, 0)
local recovery = engineerT1:PriorityFunction(engineerBrain)
assert(recovery > constants.Policy.EngineerReplacementPriorityCeiling,
    "an army with almost no engineers must outrank combat production, got "
        .. tostring(recovery))
-- And it is a fact about the whole army, not about one tier. Read per tier it
-- would hold for every upper tier the moment it is empty -- which it always is
-- at first -- and lift the Tech 3 builder above everything the brain owns.
SetEngineers(3, 0, 0, 0)
local emptyUpperTier = engineerT3:PriorityFunction(engineerBrain)
assert(emptyUpperTier > 0, "an empty upper tier must still be wanted, got "
    .. tostring(emptyUpperTier))
assert(emptyUpperTier <= constants.Policy.EngineerReplacementPriorityCeiling,
    "an empty upper tier is not a construction emergency, got "
        .. tostring(emptyUpperTier))

-- The keystone. Twenty-five Tech 1 engineers against a target of eighteen is
-- the LandLarge match exactly: the Tech 1 ladder is rightly finished, and the
-- Tech 2 one must not be finished with it. Every Tech 2 fortification builder
-- declares T2EngineerBuilder, so a zero here is why four cells reached Tech 2
-- and ended on Tech 1 point defence, Tech 1 anti-air and no shield.
SetEngineers(25, 0, 0, 0)
assert(engineerT1:PriorityFunction(engineerBrain) == 0,
    "a roster already past target must stop building Tech 1 engineers")
assert(engineerT2:PriorityFunction(engineerBrain) > 0,
    "a wall of Tech 1 engineers must not switch off the Tech 2 ladder")

-- The floor is satisfied by the engineers it asked for, and then stops: a
-- roster already over target does not want eighteen of each tier on top of it.
SetEngineers(25, 0, constants.Policy.UpperTierEngineerFloor, 0)
assert(engineerT2:PriorityFunction(engineerBrain) == 0,
    "a satisfied floor on a full roster must stop asking")

-- In-flight engineers count at the upper tiers too, or every factory answers
-- the same missing Tech 2 engineer and the floor is built several times over.
SetEngineers(25, 0, 0, 0, constants.Policy.UpperTierEngineerFloor)
assert(engineerT2:PriorityFunction(engineerBrain) == 0,
    "Tech 2 engineers already being built must satisfy the floor")

-- But it is a floor and not a cap. An army genuinely below its engineer target
-- builds the missing engineers at the best tier it can, floor or no floor --
-- capping that was measured and cost a won game: cells building 7-9 Tech 2
-- engineers dropped to 3, and Sludge 31337 Seraphim turned from victory to
-- defeat.
demand.DesiredEngineers = 12
SetEngineers(9, 0, constants.Policy.UpperTierEngineerFloor, 0)
assert(engineerT2:PriorityFunction(engineerBrain) > 0,
    "a shortfall the army actually has must still be built at the better tier")
demand.DesiredEngineers = 18

-- The tiers keep their intended order relative to each other, which the shared
-- function previously flattened. Compared at equal shortfall and below the
-- ceiling, so the static bases are what separates them.
demand.DesiredEngineers = 8
SetEngineers(6, 0, 1, 1)
local tech1 = engineerT1:PriorityFunction(engineerBrain)
local tech2 = engineerT2:PriorityFunction(engineerBrain)
local tech3 = engineerT3:PriorityFunction(engineerBrain)
assert(tech3 > tech2 and tech2 > tech1,
    "the ladder must keep its order at equal shortfall, got "
        .. tostring(tech1) .. "/" .. tostring(tech2) .. "/" .. tostring(tech3))
demand.DesiredEngineers = nil

print("Red Queen support commander contracts passed")

-- A cap filled with Tech 1 engineers is a cap that never improves.
--
-- The target counted every mobile engineer regardless of tier, so twelve Tech 1
-- engineers satisfied a target of twelve forever and no Tech 2 engineer was
-- ever built -- however good the economy got, and however much more build power
-- the tier carries.

local tierCounts = { any = 0, t2 = 0, t3 = 0 }
local tierBrain = {
    RedQueenContext = { FactionIndex = 2 },
    RedQueenModules = {
        Economy = { State = economy },
        Strategy = { ProductionDemand = demand },
        World = world,
    },
    GetCurrentUnits = function(_, category)
        local name = category and category.Name or ""
        -- Tech 2 asks for TECH2+TECH3 together, so test for TECH2 first or the
        -- combined category is mistaken for the Tech 3 one.
        if string.find(name, "TECH2", 1, true) then return tierCounts.t2 end
        if string.find(name, "TECH3", 1, true) then return tierCounts.t3 end
        return tierCounts.any
    end,
    GetListOfUnits = function() return {} end,
}

demand.DesiredEngineers = 12
economy.MassIncome = 30

-- Twelve Tech 1 engineers and none above: the Tech 2 builder must still fire.
tierCounts = { any = 12, t2 = 0, t3 = 0 }
assert(engineerT2.BuilderConditions[1][1](tierBrain),
    "a full complement of Tech 1 engineers must not satisfy Tech 2 demand")

-- And once the Tech 2 complement is there, it stops.
tierCounts = { any = 24, t2 = 12, t3 = 0 }
assert(not engineerT2.BuilderConditions[1][1](tierBrain),
    "a full Tech 2 complement must stop Tech 2 production")

-- Tech 1 stops once a Tech 2 engineer exists and another is affordable, so the
-- ladder replaces rather than accumulating two full complements.
tierCounts = { any = 5, t2 = 1, t3 = 0 }
assert(not engineerT1.BuilderConditions[1][1](tierBrain),
    "Tech 1 must stop once the tier above it is running")

-- But never before the tier above can actually be produced, or neither ladder
-- builds and the army has no engineers at all.
tierCounts = { any = 5, t2 = 0, t3 = 0 }
assert(engineerT1.BuilderConditions[1][1](tierBrain),
    "Tech 1 must keep building while no Tech 2 engineer exists yet")

-- A poor economy keeps Tech 1 running even beside a Tech 2 engineer: stopping
-- it there would leave nothing affordable to build.
economy.MassIncome = 1
tierCounts = { any = 5, t2 = 1, t3 = 0 }
assert(engineerT1.BuilderConditions[1][1](tierBrain),
    "Tech 1 must keep building when Tech 2 is unaffordable")

economy.MassIncome = 30
demand.DesiredEngineers = nil

print("Red Queen engineer tier ladder contracts passed")
