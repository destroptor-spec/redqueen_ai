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
local function MergeExclusions(left, right)
    local exclusions = {}
    for name, excluded in pairs(left.Exclusions or {}) do
        exclusions[name] = excluded
    end
    for name, excluded in pairs(right.Exclusions or {}) do
        exclusions[name] = excluded
    end
    return exclusions
end
-- A composite also carries what it *requires*, not only what it excludes.
-- Without that, `MOBILE * LAND * TECH3 * DIRECTFIRE` tested identically to
-- `MOBILE * LAND * DIRECTFIRE`, so the garrison's Tech 3-only filter passed
-- its contract for years without the contract ever exercising the tech term.
local function MergeRequired(left, right)
    local required = {}
    for name in pairs(left.Required or {}) do required[name] = true end
    for name in pairs(right.Required or {}) do required[name] = true end
    if left.Name then required[left.Name] = true end
    if right.Name then required[right.Name] = true end
    return required
end
categoryMetatable.__mul = function(left, right)
    return setmetatable({
        Exclusions = MergeExclusions(left, right),
        Required = MergeRequired(left, right),
    }, categoryMetatable)
end
categoryMetatable.__sub = function(left, right)
    local exclusions = MergeExclusions(left, right)
    if right.Name then
        exclusions[right.Name] = true
    end
    local required = {}
    for name in pairs(left.Required or {}) do required[name] = true end
    if left.Name then required[left.Name] = true end
    return setmetatable({ Exclusions = exclusions, Required = required }, categoryMetatable)
end
categories = setmetatable({}, {
    __index = function(value, key)
        local category = setmetatable({ Name = key, Exclusions = {} }, categoryMetatable)
        rawset(value, key, category)
        return category
    end,
})

-- A composite expression (MOBILE minus the exclusions) carries no Name and
-- answers the "is this orderable" question. A single named category is a
-- membership test, and must answer from the unit rather than from IsCombat --
-- otherwise every combat unit tests positive for every category, and a
-- contract about one category would pass without exercising anything.
function EntityCategoryContains(category, unit)
    if category.Name then
        return (unit.Categories or {})[category.Name] == true
    end
    -- A unit that declares its categories is judged on them; one that only says
    -- IsCombat keeps the older, looser behaviour so existing fixtures stand.
    if unit.Categories then
        for name in pairs(category.Required or {}) do
            if not unit.Categories[name] then
                return false
            end
        end
        for name in pairs(category.Exclusions or {}) do
            if unit.Categories[name] then
                return false
            end
        end
        return true
    end
    return unit.IsCombat == true
        and not (unit.IsTransport and category.Exclusions.TRANSPORTFOCUS)
end

local currentTick = 100
local aggressiveOrders = {}
function GetGameTick() return currentTick end
function IssueClearCommands() end
function IssueMove() end
function IssuePatrol() end
function IssueAggressiveMove(units, position)
    table.insert(aggressiveOrders, { Units = units, Position = position })
end

local constants = {
    Policy = {
        MinimumAttackUnits = 3,
        MaximumTaskForceUnits = 60,
        AttackReserveFraction = 0.10,
        UnitOrderLifetimeTicks = 50,
        ForwardBaseSiteRadius = 60,
        ForwardBaseGarrisonSeconds = 60,
        GarrisonLossFraction = 0.5,
        GarrisonForceFraction = 0.15,
        GarrisonUndefendedMultiple = 2.0,
        GarrisonMinimumUnits = 2,
        GarrisonMaximumUnits = 8,
        CommitmentThreatRatio = 1.10,
        CommitmentThreatRadius = 60,
        RouteCoverageConfidenceForFull = 1.0,
        ScoutCoverageSatisfied = 0.50,
        ScoutOrderSeconds = 30,
        IntelLifetimeSeconds = 120,
        ScoutFallbackMinimumWeight = 3,
        CommitmentDiagnosticSeconds = 30,
    },
}
local logger = { Debug = function() end, Info = function() end }

function import(path)
    if path == "/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua" then
        return constants
    elseif path == "/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua" then
        return logger
    end
    error("unexpected import: " .. tostring(path))
end

dofile("lua/AI/RedQueen/CombatManager.lua")

local manager = Create({}, {}, {}, {})
local units = {}
for entityId = 10, 1, -1 do
    table.insert(units, { EntityId = entityId })
end

local pressure = manager:SelectTaskForce(units, false)
assert(table.getn(pressure) == 9, "offensive pressure must keep only a ten-percent reserve")
assert(pressure[1].EntityId == 1, "task-force selection must remain deterministic")

local smallWave = manager:SelectTaskForce({ units[1], units[2], units[3] }, false)
assert(table.getn(smallWave) == 3, "three available combat units must leave the pool as a wave")
assert(not manager:SelectTaskForce({ units[1], units[2] }, false), "undersized offensive waves must still wait for one more unit")

-- One experimental is a formed force on its own. The count minimum stops small
-- units being fed piecemeal; it must not strand the most expensive unit on the
-- field waiting for two escorts to idle in the same layer.
local colossus = { EntityId = 99, Categories = { EXPERIMENTAL = true } }
local loneExperimental = manager:SelectTaskForce({ colossus }, false)
assert(loneExperimental and table.getn(loneExperimental) == 1,
    "a single experimental must be able to form an offensive task force")
assert(not manager:SelectTaskForce({ units[1] }, false),
    "relaxing the minimum for experimentals must not relax it for ordinary units")
local escorted = manager:SelectTaskForce({ colossus, units[1] }, false)
assert(escorted and table.getn(escorted) == 2,
    "an experimental with an escort must commit both")

-- Tactical commitment gate. Feeding three-unit packets into a formed army is
-- what produced 998 land units built against 141 kills in match 27741743.
local observedThreat = 0
local gatedManager = Create({}, {}, {}, {
    Intel = { GetThreatNear = function() return observedThreat end },
})
local function ThreateningUnit(entityId, threat)
    return {
        EntityId = entityId,
        GetBlueprint = function()
            return { Defense = { SurfaceThreatLevel = threat } }
        end,
    }
end
local wave = {}
for entityId = 1, 10 do
    table.insert(wave, ThreateningUnit(entityId, 10))
end
local target = { Type = "Raid", Position = { 100, 0, 100 } }

observedThreat = 0
assert(
    gatedManager:SelectTaskForce(wave, false, target),
    "an undefended objective must be attacked immediately"
)

observedThreat = 500
assert(
    not gatedManager:SelectTaskForce(wave, false, target),
    "an offensive wave must not commit below the threat ratio"
)
assert(
    gatedManager:SelectTaskForce(wave, true, target),
    "a defensive response must never be gated on enemy threat"
)

observedThreat = 50
assert(
    gatedManager:SelectTaskForce(wave, false, target),
    "a wave that clears the threat ratio must commit"
)

-- Economy must never hold a unit back, only tactics.
local economyStarved = Create({}, {}, { State = { StallRisk = true, MassIncome = 0 } }, {
    Intel = { GetThreatNear = function() return 0 end },
})
assert(
    economyStarved:SelectTaskForce(wave, false, target),
    "a stalled economy must never hold existing combat units back"
)

-- A full task force always commits rather than hoarding past the cap.
local fullWave = {}
for entityId = 1, constants.Policy.MaximumTaskForceUnits + 20 do
    table.insert(fullWave, ThreateningUnit(entityId, 1))
end
observedThreat = 100000
assert(
    gatedManager:SelectTaskForce(fullWave, false, target),
    "a full task force must commit rather than hoard past the cap"
)

-- Selection is by contribution, with EntityId only breaking ties.
local mixedWave = {
    ThreateningUnit(1, 5),
    ThreateningUnit(2, 90),
    ThreateningUnit(3, 40),
}
observedThreat = 0
local ordered = gatedManager:SelectTaskForce(mixedWave, false, target)
assert(ordered[1].EntityId == 2, "the highest-contribution unit must lead the task force")
assert(ordered[2].EntityId == 3, "task forces must be ordered by contribution")

local tiedWave = { ThreateningUnit(7, 20), ThreateningUnit(4, 20), ThreateningUnit(9, 20) }
local tied = gatedManager:SelectTaskForce(tiedWave, false, target)
assert(tied[1].EntityId == 4, "equal contributions must fall back to a deterministic EntityId order")

-- Integrate the actual intel calculation with dispatch: the objective's layer
-- describes the target, and must not substitute for the attacking wave layer.
local intelModule = setmetatable({}, { __index = _G })
setfenv(assert(loadfile("lua/AI/RedQueen/IntelManager.lua")), intelModule)()
local layerIntel = intelModule.Create({})
local defense = { Land = 100, Air = 0, Naval = 0 }
layerIntel.Observations = {
    { Position = target.Position, Confidence = 1, Threat = defense },
}
local dispatchUnits = {}
for _, layer in ipairs({ "Air", "Land", "Water", "Amphibious" }) do
    for index = 1, 3 do
        local hash = { [layer == "Water" and "NAVAL" or string.upper(layer)] = true }
        table.insert(dispatchUnits, {
            EntityId = table.getn(dispatchUnits) + 100,
            IsCombat = true,
            GetPosition = function() return { 0, 0, 0 } end,
            GetBlueprint = function()
                return { CategoriesHash = hash, Defense = { SurfaceThreatLevel = 1 } }
            end,
        })
    end
end
local dispatchPool = { GetPlatoonUnits = function() return dispatchUnits end }
local layerStrategy = { Intel = layerIntel, ProductionDemand = {}, CurrentObjective = target }
local layerManager = Create(
    { GetPlatoonUniquelyNamed = function() return dispatchPool end },
    { CanPath = function() return true end }, {}, layerStrategy
)
target.Layer = "Land"
local beforeDispatch = table.getn(aggressiveOrders)
layerManager:Update()
assert(table.getn(aggressiveOrders) == beforeDispatch + 1, "three bombers must raid ground-only point defense")
assert(aggressiveOrders[beforeDispatch + 1].Units[1].EntityId == 100, "only the air wave can clear ground defense")

defense.Land = 0
defense.Air = 100
for _, unit in ipairs(dispatchUnits) do unit.RedQueenOrderUntil = nil end
beforeDispatch = table.getn(aggressiveOrders)
layerManager:Update()
assert(table.getn(aggressiveOrders) == beforeDispatch + 2, "land and amphibious waves must ignore AA-only threat")
assert(not dispatchUnits[1].RedQueenOrderUntil, "bombers must wait against sufficient anti-air")
for _, unit in ipairs(dispatchUnits) do unit.RedQueenOrderUntil = nil end
target.Layer = "Water"
beforeDispatch = table.getn(aggressiveOrders)
layerManager:Update()
assert(table.getn(aggressiveOrders) == beforeDispatch + 2, "water and amphibious waves must ignore AA-only threat")
assert(dispatchUnits[7].RedQueenOrderUntil, "water dispatch must pass its wave layer into commitment")
assert(not dispatchUnits[4].RedQueenOrderUntil, "ordinary land units cannot join water dispatch")
for _, unit in ipairs(dispatchUnits) do unit.RedQueenOrderUntil = nil end
target.DefenseLayers = { Land = true, Water = true, Amphibious = true }
target.LayerPositions = { Land = target.Position, Water = target.Position, Amphibious = target.Position }
beforeDispatch = table.getn(aggressiveOrders)
layerManager:Update()
assert(table.getn(aggressiveOrders) == beforeDispatch + 3, "layer-specific destinations must also use each wave's threat layer")
-- A land objective leaves the fleet with no destination at all: Water is not
-- one of the land dispatch layers and a ship cannot sail to a land coordinate.
-- On a Mixed map the land layer always resolves first, so this was every ship
-- built, idle in the pool for the whole match while naval production ran on.
for _, unit in ipairs(dispatchUnits) do unit.RedQueenOrderUntil = nil end
target.DefenseLayers = nil
target.LayerPositions = nil
target.Layer = "Land"
beforeDispatch = table.getn(aggressiveOrders)
layerManager:Update()
local landOnlyWaves = table.getn(aggressiveOrders) - beforeDispatch
assert(not dispatchUnits[7].RedQueenOrderUntil,
    "a land objective on its own must leave the fleet unordered")

-- Given a water destination of its own, the fleet sails.
for _, unit in ipairs(dispatchUnits) do unit.RedQueenOrderUntil = nil end
target.LayerPositions = { Water = { 400, 0, 400 } }
beforeDispatch = table.getn(aggressiveOrders)
layerManager:Update()
assert(table.getn(aggressiveOrders) == beforeDispatch + landOnlyWaves + 1,
    "a water destination must add exactly one more wave for the fleet")
assert(dispatchUnits[7].RedQueenOrderUntil,
    "and the fleet must actually receive the order")

-- The ships must use their own destination for both threat and path checks.
-- Allied land/air attacks obey the same contract, including their launch tick.
local waterDestination = target.LayerPositions.Water
local originalObservations = layerIntel.Observations
local waterDefense = { Land = 0, Air = 0, Naval = 0 }
layerIntel.Observations = {
    { Position = target.Position, Confidence = 1, Threat = { Land = 500, Air = 100, Naval = 0 } },
    { Position = waterDestination, Confidence = 1, Threat = waterDefense },
}
local waterReachable = true
layerManager.World.CanPath = function(_, layer, origin, destination)
    if layer == "Water" then
        assert(origin[1] == 0 and origin[3] == 0, "the path must start from the selected ships")
        assert(destination == waterDestination, "ships must path to their water destination")
        return waterReachable
    end
    return true
end
target.Type = "JointAttack"
target.LaunchTick = currentTick + 1
for _, unit in ipairs(dispatchUnits) do unit.RedQueenOrderUntil = nil end
beforeDispatch = table.getn(aggressiveOrders)
layerManager:Update()
assert(table.getn(aggressiveOrders) == beforeDispatch,
    "fleet support must wait for the coordinated launch tick with the other forces")
target.LaunchTick = currentTick
for _, layer in ipairs({ "Land", "Air" }) do
    target.Layer = layer
    for _, unit in ipairs(dispatchUnits) do unit.RedQueenOrderUntil = nil end
    beforeDispatch = table.getn(aggressiveOrders)
    layerManager:Update()
    assert(table.getn(aggressiveOrders) == beforeDispatch + 1,
        "the fleet must judge threat at sea independently of the defended land target")
    local order = aggressiveOrders[beforeDispatch + 1]
    assert(order.Units[1] == dispatchUnits[7] and order.Position == waterDestination,
        "the coordinated attack must send the ships to their water destination")
end
for _, reason in ipairs({ "threat", "path" }) do
    waterDefense.Naval = reason == "threat" and 500 or 0
    waterReachable = reason ~= "path"
    for _, unit in ipairs(dispatchUnits) do unit.RedQueenOrderUntil = nil end
    beforeDispatch = table.getn(aggressiveOrders)
    layerManager:Update()
    assert(table.getn(aggressiveOrders) == beforeDispatch and not dispatchUnits[7].RedQueenOrderUntil,
        "a fleet destination must not bypass the " .. reason .. " gate")
end
layerIntel.Observations = originalObservations
layerManager.World.CanPath = function() return true end
target.Type = "Raid"
target.Layer = "Land"
target.LaunchTick = nil
target.LayerPositions = nil

-- The summary is zeroed before the early returns, not after them. A pass that
-- dispatches nothing must report nothing, rather than leaving the previous
-- pass's counts standing as though they were current -- the defect the cover
-- and scout summaries both carried, and the reason this figure exists at all.
for _, unit in ipairs(dispatchUnits) do unit.RedQueenOrderUntil = nil end
target.Layer = "Land"
target.LayerPositions = { Water = { 400, 0, 400 } }
layerManager:Update()
assert(layerManager.DispatchSummary.Water > 0,
    "the fleet must have been dispatched on the pass this test builds on")
local savedObjective = layerStrategy.CurrentObjective
layerStrategy.CurrentObjective = { Type = "Stage", Position = target.Position, Layer = "Land" }
layerManager:Update()
assert(layerManager.DispatchSummary.Water == 0 and layerManager.DispatchSummary.Land == 0,
    "a staging pass must report nothing dispatched, not the previous pass's counts")
layerStrategy.CurrentObjective = savedObjective
target.LayerPositions = nil

-- Keep the subsequent independent dispatch fixtures' order counts local.
aggressiveOrders = {}

local fighter = {
    EntityId = 20,
    IsCombat = true,
    GetBlueprint = function() return { CategoriesHash = { AIR = true } } end,
}
local transport = {
    EntityId = 21,
    IsCombat = true,
    IsTransport = true,
    GetBlueprint = function()
        return { CategoriesHash = { AIR = true, TRANSPORTFOCUS = true } }
    end,
}
local wavePool = { GetPlatoonUnits = function() return { fighter, transport } end }
local waveBrain = { GetPlatoonUniquelyNamed = function() return wavePool end }
local waveManager = Create(waveBrain, {}, {}, {})
local gathered = waveManager:GatherAvailableUnits()
assert(table.getn(gathered.Air) == 1, "transports must not enter air combat waves")
assert(gathered.Air[1] == fighter, "armed air units must remain eligible for combat waves")
assert(not transport.RedQueenOrderUntil, "combat gathering must leave transports available to native plans")

-- Hover and amphibious are separate engine navigation graphs. Each layer is
-- dispatched and path-gated on its own graph, so each needs enough units to
-- clear the defensive minimum on its own.
local amphibiousUnits = {
    {
        EntityId = 30,
        IsCombat = true,
        GetPosition = function() return { 10, 0, 10 } end,
        GetBlueprint = function() return { CategoriesHash = { AMPHIBIOUS = true } } end,
    },
    {
        EntityId = 31,
        IsCombat = true,
        GetPosition = function() return { 12, 0, 12 } end,
        GetBlueprint = function() return { CategoriesHash = { HOVER = true } } end,
    },
    {
        EntityId = 32,
        IsCombat = true,
        GetPosition = function() return { 14, 0, 14 } end,
        GetBlueprint = function() return { CategoriesHash = { AMPHIBIOUS = true } } end,
    },
    {
        EntityId = 33,
        IsCombat = true,
        -- Carries both categories: hover must win, because the amphibious
        -- graph is blocked past MaxWaterDepthAmphibious and would strand it.
        GetBlueprint = function() return { CategoriesHash = { HOVER = true, AMPHIBIOUS = true } } end,
        GetPosition = function() return { 16, 0, 16 } end,
    },
}
local waterPool = { GetPlatoonUnits = function() return amphibiousUnits end }
local waterBrain = { GetPlatoonUniquelyNamed = function() return waterPool end }
local pathLayers = {}
local waterWorld = {
    CanPath = function(_, layer)
        pathLayers[layer] = true
        return true
    end,
}
local waterStrategy = {
    ProductionDemand = {
        DefenseAlert = { Active = false },
        ForwardBasePlan = { Sites = {} },
    },
    CurrentObjective = {
        Type = "Defend",
        Layer = "Water",
        Position = { 100, 5, 100 },
    },
}
local waterManager = Create(waterBrain, waterWorld, {}, waterStrategy)
local waterGathered = waterManager:GatherAvailableUnits()
assert(table.getn(waterGathered.Amphibious) == 2, "amphibious units must gather on the amphibious layer")
assert(table.getn(waterGathered.Hover) == 2, "hover units must gather on their own layer, not with amphibious")
assert(waterGathered.Hover[2] == amphibiousUnits[4], "a unit carrying both categories must route as hover")
waterManager:Update()
assert(pathLayers.Amphibious, "water defense must test amphibious pathing")
assert(pathLayers.Hover, "water defense must path-gate hover on the hover graph, not the amphibious one")
assert(table.getn(aggressiveOrders) == 2, "water defense must dispatch amphibious and hover as separate task forces")
assert(aggressiveOrders[1].Units[1] == amphibiousUnits[1], "amphibious dispatch must remain deterministic")
assert(amphibiousUnits[1].RedQueenOrderUntil == 150, "amphibious water defenders must receive an order lock")
assert(amphibiousUnits[2].RedQueenOrderUntil == 150, "hover water defenders must receive an order lock")

local landDefenders = {
    {
        EntityId = 40,
        IsCombat = true,
        GetPosition = function() return { 10, 0, 10 } end,
        GetBlueprint = function() return { CategoriesHash = { LAND = true } } end,
    },
    {
        EntityId = 41,
        IsCombat = true,
        GetPosition = function() return { 12, 0, 12 } end,
        GetBlueprint = function() return { CategoriesHash = { LAND = true } } end,
    },
}
local landDefensePosition = { 80, 0, 80 }
local landPool = { GetPlatoonUnits = function() return landDefenders end }
local landBrain = { GetPlatoonUniquelyNamed = function() return landPool end }
local landStrategy = {
    ProductionDemand = {
        DefenseAlert = { Active = false },
        ForwardBasePlan = { Sites = {} },
    },
    CurrentObjective = {
        Type = "Defend",
        Layer = "Land",
        Position = { 100, 5, 100 },
        DefenseLayers = { Land = true, Water = false, Amphibious = false, Air = false },
        LayerPositions = { Land = landDefensePosition },
    },
}
local ordersBeforeLandDefense = table.getn(aggressiveOrders)
local landManager = Create(landBrain, waterWorld, {}, landStrategy)
landManager:Update()
assert(table.getn(aggressiveOrders) == ordersBeforeLandDefense + 1, "land invasions must mobilize ordinary land defenders at water-adjacent anchors")
assert(aggressiveOrders[table.getn(aggressiveOrders)].Position == landDefensePosition, "land defense must use its layer-specific intercept position")

local garrisonUnits = {}
for entityId = 1, 12 do
    table.insert(garrisonUnits, {
        EntityId = entityId,
        IsCombat = true,
        IsTransport = entityId == 12,
        GetPosition = function() return { entityId, 0, 0 } end,
    })
end
local garrisonPool = { GetPlatoonUnits = function() return garrisonUnits end }
local garrisonSite = {
    Name = "RQFB_1_1",
    Position = { 100, 0, 100 },
    State = "Building",
}
local garrisonStrategy = {
    ProductionDemand = {
        DefenseAlert = { Active = false },
        ForwardBasePlan = {
            Sites = { garrisonSite },
        },
    },
}
local garrisonBrain = {
    GetPlatoonUniquelyNamed = function() return garrisonPool end,
    GetNumUnitsAroundPoint = function() return 0 end,
    GetFactionIndex = function() return 3 end,
}
local garrisonManager = Create(garrisonBrain, {}, {}, garrisonStrategy)
garrisonManager:MaintainForwardGarrisons()
local assigned = 0
for _, unit in pairs(garrisonUnits) do
    if unit.RedQueenGarrisonSite then assigned = assigned + 1 end
end
-- Cover is a portion of the force, not a fixed squad.
--
-- This asserted 10 of 12 units, from counts sized when only Tech 3 units were
-- eligible. Widening eligibility to the whole land army made that most of a
-- small army: measured across 21 cells, committing six or more units cost 0.30
-- mass kill/loss and 19.7 peak income against the same cells' baseline, while
-- committing fewer than six cost 0.11 and *gained* 4.1.
assert(assigned >= 2,
    "an undefended site must still be covered, got " .. assigned)
assert(assigned <= 6,
    "but cover must never take most of a twelve-unit army, got " .. assigned)
assert(not garrisonUnits[12].RedQueenGarrisonSite, "transports must not become forward-base garrisons")

garrisonSite.State = "Destroyed"
garrisonManager:MaintainForwardGarrisons()
for _, unit in pairs(garrisonUnits) do
    assert(not unit.RedQueenGarrisonSite, "destroyed forward bases must release their garrisons")
end

garrisonSite.State = "Established"
garrisonManager:MaintainForwardGarrisons()
garrisonStrategy.ProductionDemand.DefenseAlert.Active = true
garrisonManager:MaintainForwardGarrisons()
assert(garrisonManager.GarrisonSummary.Sites == 0 and garrisonManager.GarrisonSummary.Units == 0,
    "emergency release must reset reported cover")
for _, unit in pairs(garrisonUnits) do
    assert(not unit.RedQueenGarrisonSite, "emergency defense must release forward garrisons")
end

garrisonManager.GarrisonSummary = { Sites = 1, Units = 6 }
garrisonBrain.GetPlatoonUniquelyNamed = function() return nil end
garrisonManager:MaintainForwardGarrisons()
assert(garrisonManager.GarrisonSummary.Sites == 0 and garrisonManager.GarrisonSummary.Units == 0,
    "an absent pool must not leave stale cover statistics")

-- Exercise classification through Update, where the team objective enters.
for _, objectiveType in ipairs({ "Raid", "JointAttack", "Support", "Reinforce", "Defend" }) do
    for _, enemyStrength in ipairs({ 50, 500 }) do
        local offensive = objectiveType == "Raid" or objectiveType == "JointAttack"
        local strategy = { CurrentObjective = { Type = objectiveType, Layer = "Land", Position = { 100, 0, 100 } },
            Intel = { GetThreatNear = function() return enemyStrength end } }
        local current = Create({}, { CanPath = function() return true end }, {}, strategy)
        current.MaintainForwardGarrisons = function() end
        current.GatherAvailableUnits = function() return { Land = wave, Air = {}, Water = {}, Amphibious = {} } end
        for _, unit in ipairs(wave) do unit.GetPosition = function() return { 0, 0, 0 } end end
        local before = table.getn(aggressiveOrders)
        current:Update()
        local launched = table.getn(aggressiveOrders) > before
        assert(launched == (not offensive or enemyStrength == 50), objectiveType .. " has incorrect commitment classification")
    end
end

-- An Air objective must not silence every surface force. Each surface layer is
-- offered the same destination and path-gated on its own graph, so a hover army
-- can cross water that the land army cannot, and anything genuinely stranded is
-- reported as a hold rather than left idle in the pool.
local airFallbackUnits = {}
for entityId = 50, 55 do
    local hover = entityId >= 53
    table.insert(airFallbackUnits, {
        EntityId = entityId,
        IsCombat = true,
        GetPosition = function() return { 10, 0, 10 } end,
        GetBlueprint = function()
            return { CategoriesHash = hover and { HOVER = true } or { LAND = true } }
        end,
    })
end
local airFallbackPool = { GetPlatoonUnits = function() return airFallbackUnits end }
local airFallbackBrain = { GetPlatoonUniquelyNamed = function() return airFallbackPool end }
local airFallbackLayers = {}
local airFallbackWorld = {
    CanPath = function(_, layer)
        airFallbackLayers[layer] = true
        -- Open water: only hover crosses it.
        return layer == "Hover"
    end,
}
local airFallbackStrategy = {
    ProductionDemand = { DefenseAlert = { Active = false }, ForwardBasePlan = { Sites = {} } },
    CurrentObjective = { Type = "Pressure", Layer = "Air", Position = { 400, 0, 400 } },
    Intel = { GetThreatNear = function() return 0 end },
}
local ordersBeforeAirFallback = table.getn(aggressiveOrders)
local airFallbackManager = Create(airFallbackBrain, airFallbackWorld, {}, airFallbackStrategy)
airFallbackManager:Update()
assert(airFallbackLayers.Land, "an Air objective must still offer the land force a destination")
assert(airFallbackLayers.Hover, "an Air objective must still offer the hover force a destination")
assert(table.getn(aggressiveOrders) == ordersBeforeAirFallback + 1,
    "only the layer that can reach the objective may be dispatched")
assert(aggressiveOrders[table.getn(aggressiveOrders)].Units[1] == airFallbackUnits[4],
    "the hover force must be the one dispatched across water")
assert(not airFallbackUnits[1].RedQueenOrderUntil,
    "a land force with no route must be held, never marched into open water")

print("Red Queen combat manager contracts passed")

-- A forward base must be covered at the tech it is actually built at.
--
-- Across the 21-cell matrix 40 forward bases were started by Tech 1 engineers
-- and 22 by Tech 2, against 10 by Tech 3. The garrison filter demanded
-- MOBILE * LAND * TECH3 * DIRECTFIRE, so for 86% of bases it had nothing
-- eligible to send: cover existed and stood down through the whole early and
-- mid game, which is exactly when only 21% of bases ever established.
local function tieredUnit(entityId, tier, threat)
    return {
        EntityId = entityId,
        GetPosition = function() return { entityId, 0, 0 } end,
        GetBlueprint = function()
            return { Defense = { SurfaceThreatLevel = threat } }
        end,
        Categories = {
            MOBILE = true, LAND = true, DIRECTFIRE = true, [tier] = true,
        },
    }
end

local earlyUnits = {}
for entityId = 1, 6 do
    table.insert(earlyUnits, tieredUnit(entityId, "TECH1", 10))
end
local earlyPool = { GetPlatoonUnits = function() return earlyUnits end }
local earlySite = {
    Name = "RQFB_2_1",
    Position = { 100, 0, 100 },
    State = "Building",
    -- A Tech 1 foothold wants two guns and has no shield to build.
    TierPlan = { Tier = 1, MinimumDefenses = 2, MinimumAntiAir = 1, MinimumShields = 0 },
}
local earlyStrategy = {
    ProductionDemand = {
        DefenseAlert = { Active = false },
        ForwardBasePlan = { Sites = { earlySite } },
    },
}
local earlyBrain = {
    GetPlatoonUniquelyNamed = function() return earlyPool end,
    GetNumUnitsAroundPoint = function() return 0 end,
    GetFactionIndex = function() return 2 end,
}
local earlyManager = Create(earlyBrain, {}, {}, earlyStrategy)
earlyManager:MaintainForwardGarrisons()
local earlyAssigned = 0
for _, unit in pairs(earlyUnits) do
    if unit.RedQueenGarrisonSite == "RQFB_2_1" then earlyAssigned = earlyAssigned + 1 end
end
assert(earlyAssigned > 0,
    "a Tech 1 forward base must be covered by the Tech 1 army that built it")
assert(earlyAssigned <= 3,
    "cover must be a portion of a six-unit army, not the whole of it, got "
        .. earlyAssigned)

-- Heaviest gun first: widening below Tech 3 must not send a Tech 1 tank while a
-- Tech 3 one stands idle.
--
-- More candidates than slots, and the heavy gun is deliberately the *furthest*
-- away, so proximity alone would exclude it. That is what makes the ordering
-- observable rather than incidental.
local mixedUnits = { tieredUnit(1, "TECH3", 90) }
for entityId = 50, 54 do
    table.insert(mixedUnits, tieredUnit(entityId, "TECH1", 10))
end
local mixedSite = {
    Name = "RQFB_2_2",
    Position = { 100, 0, 100 },
    State = "Building",
    TierPlan = { Tier = 2, MinimumDefenses = 4, MinimumAntiAir = 2, MinimumShields = 1 },
}
local mixedManager = Create({
    GetPlatoonUniquelyNamed = function()
        return { GetPlatoonUnits = function() return mixedUnits end }
    end,
    -- Its own minimum is already met, so only the standing garrison is wanted
    -- and the slots are fewer than the candidates.
    GetNumUnitsAroundPoint = function() return 4 end,
    GetFactionIndex = function() return 2 end,
}, {}, {}, {
    ProductionDemand = {
        DefenseAlert = { Active = false },
        ForwardBasePlan = { Sites = { mixedSite } },
    },
})
mixedManager:MaintainForwardGarrisons()
local mixedAssigned = 0
for _, unit in pairs(mixedUnits) do
    if unit.RedQueenGarrisonSite then mixedAssigned = mixedAssigned + 1 end
end
assert(mixedAssigned < table.getn(mixedUnits),
    "a defended site must not absorb every unit, or ordering cannot be observed")
assert(mixedUnits[1].RedQueenGarrisonSite == "RQFB_2_2",
    "the heaviest gun must be taken even when it is the furthest away")

-- The site's own tier decides when it is defended. A Tech 1 foothold with two
-- guns up is covered; a Tech 3 position with two is not.
local function garrisonDemandAt(tierPlan, defensesPresent)
    local units = {}
    for entityId = 31, 45 do table.insert(units, tieredUnit(entityId, "TECH2", 40)) end
    local site = {
        Name = "RQFB_2_3", Position = { 100, 0, 100 },
        State = "Building", TierPlan = tierPlan,
    }
    local manager = Create({
        GetPlatoonUniquelyNamed = function()
            return { GetPlatoonUnits = function() return units end }
        end,
        GetNumUnitsAroundPoint = function() return defensesPresent end,
        GetFactionIndex = function() return 2 end,
    }, {}, {}, {
        ProductionDemand = {
            DefenseAlert = { Active = false },
            ForwardBasePlan = { Sites = { site } },
        },
    })
    manager:MaintainForwardGarrisons()
    local count = 0
    for _, unit in pairs(units) do
        if unit.RedQueenGarrisonSite then count = count + 1 end
    end
    return count
end

local footholdTier = { Tier = 1, MinimumDefenses = 2 }
local projectingTier = { Tier = 3, MinimumDefenses = 5 }
assert(garrisonDemandAt(footholdTier, 2) < garrisonDemandAt(footholdTier, 0),
    "a foothold that has met its own minimum needs less cover")
assert(garrisonDemandAt(projectingTier, 2) > garrisonDemandAt(footholdTier, 2),
    "two guns satisfies a foothold but not a Tech 3 position")

-- Cover is given up when it is being destroyed faster than it achieves
-- anything, and when what is at the site beats what would be sent. Both are
-- withdrawals: the answer to a site killing tanks at that rate is an
-- experimental, and feeding the rest of the force in after the first half is
-- the piecemeal-commitment mistake the offensive path already refuses.
local function coverUnder(pressure, siteThreat)
    local units = {}
    -- Twenty units, so the portion sized from the force leaves room to send
    -- more than the two already holding the site. With a six-unit army the
    -- portion is the two standing there and the prospective escort is empty,
    -- which is a real behaviour but not the one under test here.
    for entityId = 61, 80 do table.insert(units, tieredUnit(entityId, "TECH2", 40)) end
    -- Two are already holding the site, so a release has something to give up.
    units[1].RedQueenGarrisonSite = "RQFB_2_4"
    units[1].RedQueenGarrisonUntil = currentTick + 600
    units[2].RedQueenGarrisonSite = "RQFB_2_4"
    units[2].RedQueenGarrisonUntil = currentTick + 600
    local site = {
        Name = "RQFB_2_4", Position = { 100, 0, 100 }, State = "Building",
        TierPlan = { Tier = 2, MinimumDefenses = 4, MinimumAntiAir = 2, MinimumShields = 1 },
    }
    local manager = Create({
        GetPlatoonUniquelyNamed = function()
            return { GetPlatoonUnits = function() return units end }
        end,
        GetNumUnitsAroundPoint = function() return 0 end,
        GetFactionIndex = function() return 2 end,
    }, {}, {}, {
        Intel = {
            -- A number keeps the simple cases readable; a function receives the
            -- layer, so a case can distinguish what the escort can actually
            -- fight from what merely flies over the site.
            GetThreatNear = function(_, _, _, layer)
                if type(siteThreat) == "function" then return siteThreat(layer) end
                return siteThreat
            end,
        },
        ProductionDemand = {
            DefenseAlert = { Active = false },
            ForwardBasePlan = { Sites = { site } },
            GarrisonLossPressure = pressure,
        },
    })
    manager:MaintainForwardGarrisons()
    local count = 0
    for _, unit in pairs(units) do
        if unit.RedQueenGarrisonSite then count = count + 1 end
    end
    return count, site, manager, units
end

local quietCount, quietSite = coverUnder({}, 0)
assert(quietCount > 2, "a quiet site must be covered, got " .. quietCount)
assert(quietSite.GarrisonRelease == nil, "and must not be marked released")

-- Two held plus two lost is four committed; two losses is half of that.
local bleedingCount, bleedingSite = coverUnder({ RQFB_2_4 = { Count = 2, Mass = 800 } }, 0)
assert(bleedingCount == 0,
    "losing half of what was committed must release the cover, got " .. bleedingCount)
assert(bleedingSite.GarrisonRelease == "escort-overwhelmed",
    "and must say why, got " .. tostring(bleedingSite.GarrisonRelease))

-- A reservation is renewed while its member continues holding the site. Walk
-- the real combat cadence through the original 60-second deadline with a loss
-- still in the 60-second pressure window: five survivors must not become zero.
do
    local savedTick = currentTick
    local originalClear, originalInfo = IssueClearCommands, logger.Info
    local orders, messages = 0, {}
    IssueClearCommands = function() orders = orders + 1 end
    logger.Info = function(_, message) table.insert(messages, message) end
    local pressure = {}
    local count, site, watcher, poolUnits = coverUnder(pressure, 0)
    assert(count == 6, "the timing regression needs six assigned members")
    local firstDeadline = poolUnits[1].RedQueenGarrisonUntil
    local initialOrders = orders
    -- No spare units can mask the loss by immediately replacing it.
    for _, unit in ipairs(poolUnits) do
        if not unit.RedQueenGarrisonSite then unit.RedQueenOrderUntil = savedTick + 100000 end
    end
    local function LoseMember()
        for index, unit in ipairs(poolUnits) do
            if unit.RedQueenGarrisonSite == site.Name then
                table.remove(poolUnits, index).Dead = true
                return
            end
        end
        error("the regression must lose an assigned garrison member")
    end
    for elapsed = 30, 600, 30 do
        currentTick = savedTick + elapsed
        if elapsed == 570 then
            LoseMember()
            pressure[site.Name] = { Count = 1, Mass = 400 }
        end
        watcher:MaintainForwardGarrisons()
    end
    assert(currentTick >= firstDeadline, "the regression must cross the original lease expiry")
    assert(not site.GarrisonRelease and watcher.GarrisonSummary.Units == 5,
        "one recent loss must not release five survivors at the original assignment deadline")
    assert(orders == initialOrders,
        "renewing a held garrison must not clear or reissue its patrol orders")
    for _, unit in ipairs(poolUnits) do
        if unit.RedQueenGarrisonSite == site.Name then
            assert(unit.RedQueenGarrisonUntil > currentTick,
                "every retained survivor must keep a live reservation")
        end
    end
    assert(#watcher:GatherAvailableUnits().Land == 0,
        "renewed survivors must remain excluded from offensive selection")

    -- Three of the original six lost inside one window really is half. The
    -- timer fix must preserve both the withdrawal and its survivor count.
    LoseMember()
    LoseMember()
    pressure[site.Name] = { Count = 3, Mass = 1200 }
    currentTick = currentTick + 30
    watcher:MaintainForwardGarrisons()
    assert(site.GarrisonRelease == "escort-overwhelmed" and watcher.GarrisonSummary.Units == 0,
        "genuine half-cohort losses must still release the surviving members")
    assert(#messages == 1 and string.find(messages[1], "units=3 losses=3", 1, true),
        "the release log must report real survivors and losses")
    assert(#watcher:GatherAvailableUnits().Land == 3,
        "a real release must return its survivors to offensive availability")

    -- Renewal must not reserve yesterday's larger share forever when the
    -- army shrinks. Excess members retain only their existing lease.
    currentTick = savedTick
    local _, _, smaller, smallerPool = coverUnder({}, 0)
    local spare = 0
    for index = #smallerPool, 1, -1 do
        local unit = smallerPool[index]
        if not unit.RedQueenGarrisonSite then
            spare = spare + 1
            if spare > 4 then
                table.remove(smallerPool, index)
            else
                unit.RedQueenOrderUntil = savedTick + 100000
            end
        end
    end
    assert(#smallerPool == 10, "the reduced army must have six members and four unavailable spares")
    for elapsed = 30, 600, 30 do
        currentTick = savedTick + elapsed
        smaller:MaintainForwardGarrisons()
    end
    assert(smaller.GarrisonSummary.Units == 3 and #smaller:GatherAvailableUnits().Land == 3,
        "only the currently budgeted share may be renewed indefinitely")
    currentTick = savedTick
    IssueClearCommands, logger.Info = originalClear, originalInfo
end

-- Losses on a *different* site must not release this one.
local elsewhereCount = coverUnder({ RQFB_9_9 = { Count = 5, Mass = 2000 } }, 0)
assert(elsewhereCount > 2,
    "another site's losses must not release this cover, got " .. elsewhereCount)

-- Strength is the escort that *would* go: two held plus four candidates at 40
-- threat each is 240, so the site is answerable up to 240 * 1.10 and not past
-- it.
local evenCount = coverUnder({}, 240)
assert(evenCount > 2, "cover that can answer the site must still go, got " .. evenCount)
local outmatchedCount, outmatchedSite = coverUnder({}, 500)
assert(outmatchedCount == 0,
    "cover must not be sent into a site it cannot answer, got " .. outmatchedCount)
assert(outmatchedSite.GarrisonRelease == "escort-outmatched",
    "and must say why, got " .. tostring(outmatchedSite.GarrisonRelease))

-- Enemy air overhead is not the escort's problem. Garrison units are
-- MOBILE * LAND * DIRECTFIRE and their UnitThreat is effectively surface
-- threat, so measuring the site without a layer weighs a gunship wing against
-- a tank's gun and refuses land cover where no enemy ground force exists. One
-- match logged three releases reading `escort-outmatched units=0 losses=0`.
local function airOverhead(layer)
    -- What a layer-less call would have returned, versus what the land layer
    -- actually holds: nothing on the ground at all.
    if layer == nil then return 900 end
    if layer == "Air" then return 900 end
    return 0
end
local airCount, airSite = coverUnder({}, airOverhead)
assert(airCount > 2,
    "enemy air must not refuse land cover at a site with no ground threat, got " .. airCount)
assert(not airSite.GarrisonRelease,
    "and must not release the escort, got " .. tostring(airSite.GarrisonRelease))

-- The same site with a real ground force still releases, so the layer fix
-- narrows the measurement rather than disabling the judgement.
local groundCount, groundSite = coverUnder({}, function(layer)
    if layer == "Air" then return 0 end
    return 500
end)
assert(groundCount == 0,
    "ground threat the escort cannot answer must still refuse cover, got " .. groundCount)
assert(groundSite.GarrisonRelease == "escort-outmatched",
    "and must say why, got " .. tostring(groundSite.GarrisonRelease))

-- The defect this ordering exists for. Judging strength before selection made
-- it 0 on the first cycle, so *any* observed threat refused cover and a site
-- covered while quiet was abandoned as soon as anything appeared: 11 releases
-- in one pair of matches read `units=0 losses=0`. A site with nothing yet
-- holding it and a threat its candidates can answer must be covered.
local firstCycleUnits = {}
for entityId = 71, 76 do table.insert(firstCycleUnits, tieredUnit(entityId, "TECH2", 40)) end
local firstCycleSite = {
    Name = "RQFB_2_5", Position = { 100, 0, 100 }, State = "Building",
    TierPlan = { Tier = 2, MinimumDefenses = 4, MinimumAntiAir = 2, MinimumShields = 1 },
}
local firstCycleManager = Create({
    GetPlatoonUniquelyNamed = function()
        return { GetPlatoonUnits = function() return firstCycleUnits end }
    end,
    GetNumUnitsAroundPoint = function() return 0 end,
    GetFactionIndex = function() return 2 end,
}, {}, {}, {
    Intel = { GetThreatNear = function() return 60 end },
    ProductionDemand = {
        DefenseAlert = { Active = false },
        ForwardBasePlan = { Sites = { firstCycleSite } },
        GarrisonLossPressure = {},
    },
})
firstCycleManager:MaintainForwardGarrisons()
local firstCycleCount = 0
for _, unit in pairs(firstCycleUnits) do
    if unit.RedQueenGarrisonSite then firstCycleCount = firstCycleCount + 1 end
end
assert(firstCycleCount > 0,
    "an uncovered site under answerable threat must still be covered, got "
        .. firstCycleCount)
assert(firstCycleSite.GarrisonRelease == nil,
    "and must not be released for having no escort yet, got "
        .. tostring(firstCycleSite.GarrisonRelease))

-- Both conditions at once resolve to one outcome, deterministically the one
-- already costing units.
local _, bothSite = coverUnder({ RQFB_2_4 = { Count = 2, Mass = 800 } }, 200)
assert(bothSite.GarrisonRelease == "escort-overwhelmed",
    "losses must win the tie so the reason is deterministic, got "
        .. tostring(bothSite.GarrisonRelease))

-- Cover has to be visible in a match log. The commitment line is Debug and so
-- absent from every behavioural run, which is how a filter that stood down for
-- 86% of forward bases survived a full matrix unnoticed.
local _, _, quietManager = coverUnder({}, 0)
assert(quietManager.GarrisonSummary and quietManager.GarrisonSummary.Sites == 1,
    "a covered site must be reported")
assert(quietManager.GarrisonSummary.Units > 0, "along with what was committed")
local _, _, releasedManager = coverUnder({ RQFB_2_4 = { Count = 2, Mass = 800 } }, 0)
assert(releasedManager.GarrisonSummary.Sites == 0,
    "and a released site must not be reported as covered")

-- Sizing details, each of which a mutation showed was otherwise unprotected.
local function engineerUnit(entityId)
    return {
        EntityId = entityId,
        GetPosition = function() return { entityId, 0, 0 } end,
        GetBlueprint = function() return { Defense = { SurfaceThreatLevel = 5 } } end,
        Categories = { MOBILE = true, LAND = true, ENGINEER = true, TECH1 = true },
    }
end

local function coverWith(unitList, siteList)
    local manager = Create({
        GetPlatoonUniquelyNamed = function()
            return { GetPlatoonUnits = function() return unitList end }
        end,
        GetNumUnitsAroundPoint = function() return 0 end,
        GetFactionIndex = function() return 2 end,
    }, {}, {}, {
        Intel = { GetThreatNear = function() return 0 end },
        ProductionDemand = {
            DefenseAlert = { Active = false },
            ForwardBasePlan = { Sites = siteList },
            GarrisonLossPressure = {},
        },
    })
    manager:MaintainForwardGarrisons()
    local perSite = {}
    local total = 0
    for _, unit in pairs(unitList) do
        if unit.RedQueenGarrisonSite then
            perSite[unit.RedQueenGarrisonSite] = (perSite[unit.RedQueenGarrisonSite] or 0) + 1
            total = total + 1
        end
    end
    return total, perSite
end

local function buildingSite(name)
    return {
        Name = name, Position = { 100, 0, 100 }, State = "Building",
        TierPlan = { Tier = 1, MinimumDefenses = 2, MinimumAntiAir = 1, MinimumShields = 0 },
    }
end

-- One budget across every site. Sized per site instead, three sites would each
-- take their own portion of the army and the fraction would cap nothing.
local manyUnits = {}
for entityId = 200, 219 do table.insert(manyUnits, tieredUnit(entityId, "TECH2", 40)) end
local oneSiteTotal = coverWith(manyUnits, { buildingSite("RQFB_3_1") })
for _, unit in pairs(manyUnits) do unit.RedQueenGarrisonSite = nil; unit.RedQueenGarrisonUntil = nil end
local threeSiteTotal, threeSitePerSite = coverWith(manyUnits,
    { buildingSite("RQFB_3_1"), buildingSite("RQFB_3_2"), buildingSite("RQFB_3_3") })
assert(threeSiteTotal <= oneSiteTotal,
    "three sites must not draw more cover in total than one, got "
        .. threeSiteTotal .. " against " .. oneSiteTotal)
assert(threeSiteTotal <= 8,
    "and the whole army must not end up on forward bases, got " .. threeSiteTotal)
local sitesCovered = 0
for _ in pairs(threeSitePerSite) do sitesCovered = sitesCovered + 1 end
assert(sitesCovered < 3,
    "a spent budget must leave later sites uncovered rather than overdrawing, got "
        .. sitesCovered .. " sites")
for _, unit in pairs(manyUnits) do unit.RedQueenGarrisonSite = nil; unit.RedQueenGarrisonUntil = nil end

-- The portion is of the *eligible* force. Counting every unit in the pool would
-- size cover from engineers and scouts that can never be sent.
-- Six guns among thirty engineers: sized on the guns the portion is two, and
-- sized on the whole pool it is the cap. The gun count has to be high enough
-- that over-counting can actually send more of them, or the candidate pool
-- hides the difference.
local mostlyEngineers = {}
for entityId = 300, 305 do table.insert(mostlyEngineers, tieredUnit(entityId, "TECH2", 40)) end
for entityId = 310, 339 do table.insert(mostlyEngineers, engineerUnit(entityId)) end
local engineerHeavyTotal = coverWith(mostlyEngineers, { buildingSite("RQFB_4_1") })
assert(engineerHeavyTotal <= 3,
    "cover must be sized from the guns, not from the engineers standing beside them, got "
        .. engineerHeavyTotal)
assert(engineerHeavyTotal >= 2, "and the site must still be covered at all")
for _, unit in pairs(mostlyEngineers) do unit.RedQueenGarrisonSite = nil end

-- And an escort below the minimum is not sent at all: one unit walking into a
-- contested site is the piecemeal commitment the offensive path refuses.
local loneUnit = { tieredUnit(400, "TECH2", 40) }
local loneTotal = coverWith(loneUnit, { buildingSite("RQFB_5_1") })
assert(loneTotal == 0,
    "a single available unit must wait rather than go out alone, got " .. loneTotal)

-- Scouting: the army looks where it is ignorant, and stops when it can see.
--
-- Red Queen's intel comes only from sampling its own mobile units, so nothing
-- ever observed an enemy base before a wave attacked it -- and the commitment
-- gate then judged that wave against a threat of 0.
-- A real IntelManager with only its coverage source replaced, so the ranking
-- under test is the shipped one rather than a restatement of it.
local function scoutIntel(coverageByX)
    local instance = intelModule.Create({ GetArmyIndex = function() return 1 end }, {})
    instance.GetCoverageNear = function(_, position)
        return coverageByX[position[1]] or 0
    end
    return instance
end

local scoutingConfig = setmetatable({}, { __index = _G })
setfenv(assert(loadfile("lua/AI/RedQueen/ScoutingConfig.lua")), scoutingConfig)()

local function scoutRun(coverageByX, scoutCount, objectivePosition, mode, clusters)
    local scouts = {}
    for index = 1, scoutCount do
        local unit = tieredUnit(500 + index, "TECH1", 1)
        unit.Categories = { MOBILE = true, AIR = true, SCOUT = true }
        table.insert(scouts, unit)
    end
    local manager = Create({
        RedQueenScouting = scoutingConfig.Create({ RedQueenScoutingMode = mode }),
        GetPlatoonUniquelyNamed = function()
            return { GetPlatoonUnits = function() return scouts end }
        end,
        GetNumUnitsAroundPoint = function() return 0 end,
        GetFactionIndex = function() return 2 end,
    }, {
        EnemyStarts = { { Army = 3, Position = { 900, 0, 900 } } },
        MassClusters = clusters or { { Id = 1, Position = { 500, 0, 500 } } },
        CanPath = function() return true end,
    }, {}, {
        CurrentObjective = objectivePosition
            and { Type = "Pressure", Position = objectivePosition } or nil,
        Intel = scoutIntel(coverageByX),
        ProductionDemand = {
            DefenseAlert = { Active = false },
            ForwardBasePlan = { Sites = {} },
            GarrisonLossPressure = {},
        },
    })
    manager:MaintainScouts()
    local assigned = {}
    for _, unit in pairs(scouts) do
        if unit.RedQueenScoutTarget then table.insert(assigned, unit.RedQueenScoutTarget) end
    end
    return assigned, manager.ScoutSummary, manager
end

-- Nothing observed anywhere: the objective is the first thing looked at,
-- because that is the number the commitment gate reads.
local blindAssigned, blindSummary = scoutRun({}, 3, { 800, 0, 800 })
assert(blindSummary.Targets == 3, "objective, enemy start and cluster must all be candidates")
assert(blindSummary.Blind == 3, "and all three must count as unseen")
assert(blindAssigned[1] == "objective",
    "the objective destination must be scouted first, got " .. tostring(blindAssigned[1]))

-- A Pressure objective aimed at an enemy start shares that start's own position
-- table: GetClosestEnemyStart returns `enemy.Position` and the objective is
-- built from it. They are two candidates standing on one coordinate, and
-- reserving by candidate identity sent a scout to each while the mass cluster
-- -- a genuinely unobserved place -- got none.
local sharedAssigned, sharedSummary = scoutRun({}, 3, { 900, 0, 900 })
assert(sharedSummary.Targets == 3, "the coincident candidates are still both candidates")
assert(table.getn(sharedAssigned) == 2,
    "two candidates on one coordinate must consume one scout, got " .. table.getn(sharedAssigned))
local sawObjective, sawCluster, sawStart = false, false, false
for _, name in ipairs(sharedAssigned) do
    if name == "objective" then sawObjective = true end
    if name == "cluster-1" then sawCluster = true end
    if name == "start-3" then sawStart = true end
end
assert(sawObjective, "the more important of the coincident candidates must be the one kept")
assert(not sawStart, "and the duplicate coordinate must not be scouted twice")
assert(sawCluster,
    "the scout freed by the duplicate must reach the target nothing is looking at")

-- Both axes decide whether two candidates coincide. Mirrored maps routinely put
-- distinct places on a shared X or Z, so collapsing on one axis would silently
-- strand a target that nothing is looking at -- the very failure above, caused
-- by the fix for it.
-- One cluster shares the enemy start's X, the other shares its Z, so a key
-- built from either axis alone collapses a pair that does not coincide.
local axisAssigned = scoutRun({}, 4, { 800, 0, 800 }, nil, {
    { Id = 1, Position = { 900, 0, 100 } },
    { Id = 2, Position = { 100, 0, 900 } },
})
assert(table.getn(axisAssigned) == 4,
    "four places on four coordinates must take four scouts, got " .. table.getn(axisAssigned))
assert(blindSummary.Sent == 3, "every idle scout must be given somewhere to look")

-- Everything already observed: no scout is sent anywhere.
local seenAssigned, seenSummary = scoutRun({ [800] = 1, [900] = 1, [500] = 1 }, 3, { 800, 0, 800 })
assert(seenSummary.Blind == 0, "well-observed positions must not count as blind")
assert(seenSummary.Sent == 0,
    "an army that can already see must not send scouts, sent " .. tostring(seenSummary.Sent))
assert(table.getn(seenAssigned) == 0, "and no scout may be assigned")

-- More blind targets than scouts: the scarce scouts go to the least-known
-- places rather than being spread thin or idling.
local fewAssigned, fewSummary = scoutRun({}, 1, { 800, 0, 800 })
assert(fewSummary.Sent == 1 and fewAssigned[1] == "objective",
    "one scout must go to the most important unknown, got " .. tostring(fewAssigned[1]))

-- Production-only still supplies coverage to the director, including updates
-- as positions become visible, but issues neither clears nor moves.
local scoutingCommands = 0
local oldClear, oldMove = IssueClearCommands, IssueMove
IssueClearCommands = function() scoutingCommands = scoutingCommands + 1 end
IssueMove = function() scoutingCommands = scoutingCommands + 1 end
local productionCoverage = {}
local productionAssigned, productionSummary, productionManager = scoutRun(
    productionCoverage, 3, { 800, 0, 800 }, "production-only")
assert(#productionAssigned == 0 and productionSummary.Sent == 0 and scoutingCommands == 0,
    "production-only must leave native scouts and their orders untouched")
assert(productionSummary.Targets == 3 and productionSummary.Blind == 3,
    "turning off dispatch must not turn off the coverage used by adaptive production")
productionCoverage[800] = 1
productionManager:MaintainScouts()
assert(productionManager.ScoutSummary.Blind == 2 and scoutingCommands == 0,
    "coverage must keep updating without sending scouts")
IssueClearCommands, IssueMove = oldClear, oldMove

local dispatchAssigned, dispatchSummary, dispatchManager = scoutRun(
    {}, 3, { 800, 0, 800 }, "dispatch-only")
assert(#dispatchAssigned == 3 and dispatchAssigned[1] == "objective",
    "dispatch-only must preserve the directed scouting orders")
assert(dispatchSummary.ScoutOrders == 3 and dispatchSummary.FallbackOrders == 0,
    "dedicated scout orders must be counted separately")
dispatchManager:MaintainScouts()
assert(dispatchManager.ScoutSummary.Sent == 0
    and dispatchManager.ScoutSummary.ScoutOrders == 3,
    "a quiet combat pass must retain orders issued between diagnostic samples")

-- No scout free is the normal case: FAF's own ScoutForm templates carry
-- plan = ScoutingAI and claim scouts out of the pool, measured as sent=0 for a
-- whole match with 12-20 of 26 targets unobserved. One ordinary unit then goes
-- to look at the objective, and only the objective.
local function fallbackRun(coverageByX, objectivePosition, tankCount, mode)
    local tanks = {}
    for index = 1, tankCount do
        table.insert(tanks, tieredUnit(600 + index, "TECH2", 40))
    end
    local manager = Create({
        RedQueenScouting = scoutingConfig.Create({ RedQueenScoutingMode = mode }),
        GetPlatoonUniquelyNamed = function()
            return { GetPlatoonUnits = function() return tanks end }
        end,
        GetNumUnitsAroundPoint = function() return 0 end,
        GetFactionIndex = function() return 2 end,
    }, {
        EnemyStarts = { { Army = 3, Position = { 900, 0, 900 } } },
        MassClusters = { { Id = 1, Position = { 500, 0, 500 } } },
        CanPath = function() return true end,
    }, {}, {
        CurrentObjective = objectivePosition
            and { Type = "Pressure", Position = objectivePosition } or nil,
        Intel = scoutIntel(coverageByX),
        ProductionDemand = {
            DefenseAlert = { Active = false },
            ForwardBasePlan = { Sites = {} },
            GarrisonLossPressure = {},
        },
    })
    manager:MaintainScouts()
    local looking = 0
    for _, unit in pairs(tanks) do
        if unit.RedQueenScoutTarget then looking = looking + 1 end
    end
    return looking, manager.ScoutSummary, tanks, manager
end

local looking, fallbackSummary, fallbackTanks, fallbackManager = fallbackRun({}, { 800, 0, 800 }, 6)
assert(fallbackSummary.Idle == 0, "a tank is not a scout and must not be counted as one")
assert(looking == 1,
    "exactly one ordinary unit may be sent to see the objective, got " .. looking)
assert(fallbackTanks[1].RedQueenScoutTarget == "objective",
    "and it must be sent to the objective, got " .. tostring(fallbackTanks[1].RedQueenScoutTarget))
assert(fallbackSummary.FallbackOrders == 1 and fallbackSummary.ScoutOrders == 0,
    "combat fallback orders must not be recorded as dedicated scout orders")

-- The objective is rarely the least-covered target, which is what the fallback
-- used to require. Targets sort by coverage ascending with weight only as a
-- tiebreak, so a never-observed enemy start (weight 2) heads the list while the
-- objective (weight 3, the only candidate that meets the bar) sits behind its
-- own partial coverage. Reading the head alone failed the weight test and sent
-- nobody, leaving the commitment gate judging waves against a threat of zero.
-- The case above passes all-zero coverage, so the objective tiebreaks to the
-- head and cannot show this.
local partial, partialSummary, partialTanks = fallbackRun({ [800] = 0.30 }, { 800, 0, 800 }, 6)
assert(partial == 1,
    "a partly observed objective must still get the fallback, got " .. partial)
assert(partialTanks[1].RedQueenScoutTarget == "objective",
    "and the unit must go to the objective, not to whatever is least covered, got "
        .. tostring(partialTanks[1].RedQueenScoutTarget))
assert(partialSummary.FallbackOrders == 1, "and it must be recorded as a fallback order")

-- The weight bar still gates. With the objective already well observed it drops
-- out of the wanted list entirely, and nothing left is worth diverting a gun
-- for: an enemy start and a mass cluster are scouting work, not commitment work.
local unworthy = fallbackRun({ [800] = 0.90 }, { 800, 0, 800 }, 6)
assert(unworthy == 0,
    "no ordinary unit may be diverted when nothing meets the weight bar, got " .. unworthy)

-- A pass that could not look must report that it did not look. The cover
-- summary carried this defect and was fixed; the scout summary kept it, and
-- these figures feed the state line a matrix reads -- so a pass with no pool
-- reported the previous pass's coverage as its own. The order totals are match
-- cumulative and a quiet pass has not undone them, so they must survive.
local _, _, _, staleManager = fallbackRun({}, { 800, 0, 800 }, 6)
staleManager.ScoutSummary = {
    Targets = 26, Blind = 12, Sent = 3, Idle = 4,
    ScoutOrders = 11, FallbackOrders = 4,
}
staleManager.Brain.GetPlatoonUniquelyNamed = function() return nil end
staleManager:MaintainScouts()
local quiet = staleManager.ScoutSummary
assert(quiet.Targets == 0 and quiet.Blind == 0 and quiet.Sent == 0 and quiet.Idle == 0,
    "an absent pool must not leave stale scouting statistics")
assert(quiet.ScoutOrders == 11 and quiet.FallbackOrders == 4,
    "but the match's cumulative order totals must survive a pass that measured nothing")

local savedScoutTick = currentTick
for pass = 1, 6 do
    currentTick = savedScoutTick + pass * 30
    fallbackManager:MaintainScouts()
end
assert(fallbackManager.ScoutSummary.FallbackOrders == 1,
    "six combat passes must retain one fallback reservation, not divert six tanks")
fallbackManager.Strategy.CurrentObjective.Position = { 850, 0, 850 }
fallbackManager:MaintainScouts()
assert(fallbackManager.ScoutSummary.FallbackOrders == 1,
    "moving the objective cannot bypass the global one-fallback limit")
currentTick = savedScoutTick + constants.Policy.ScoutOrderSeconds * 10
fallbackManager:MaintainScouts()
assert(fallbackManager.ScoutSummary.FallbackOrders == 2,
    "an expired reservation may be renewed")
currentTick = savedScoutTick

scoutingCommands = 0
IssueClearCommands = function() scoutingCommands = scoutingCommands + 1 end
IssueMove = function() scoutingCommands = scoutingCommands + 1 end
local productionLooking, productionFallbackSummary = fallbackRun(
    {}, { 800, 0, 800 }, 6, "production-only")
assert(productionLooking == 0 and scoutingCommands == 0
    and productionFallbackSummary.FallbackOrders == 0,
    "production-only must also disable the ordinary combat-unit fallback")
assert(productionFallbackSummary.Blind == 3,
    "coverage must still be measured when native platoons own every scout")
IssueClearCommands, IssueMove = oldClear, oldMove
local dispatchLooking = fallbackRun({}, { 800, 0, 800 }, 6, "dispatch-only")
assert(dispatchLooking == 1, "dispatch-only must retain the combat-unit fallback")

-- With the objective already observed, the remaining blind targets are enemy
-- starts and clusters, which do not justify diverting a combat unit.
local quietLooking = fallbackRun({ [800] = 1 }, { 800, 0, 800 }, 6)
assert(quietLooking == 0,
    "a seen objective must not divert combat units to speculative targets, got "
        .. quietLooking)

-- With a scout available, the scout goes and no combat unit is diverted: the
-- fallback is a last resort, not an addition.
local mixedPool = { tieredUnit(700, "TECH2", 40), tieredUnit(701, "TECH2", 40) }
local realScout = tieredUnit(702, "TECH1", 1)
realScout.Categories = { MOBILE = true, AIR = true, SCOUT = true }
table.insert(mixedPool, realScout)
local mixedManager = Create({
    GetPlatoonUniquelyNamed = function()
        return { GetPlatoonUnits = function() return mixedPool end }
    end,
    GetNumUnitsAroundPoint = function() return 0 end,
    GetFactionIndex = function() return 2 end,
}, {
    EnemyStarts = { { Army = 3, Position = { 900, 0, 900 } } },
    MassClusters = { { Id = 1, Position = { 500, 0, 500 } } },
    CanPath = function() return true end,
}, {}, {
    CurrentObjective = { Type = "Pressure", Position = { 800, 0, 800 } },
    Intel = scoutIntel({}),
    ProductionDemand = {
        DefenseAlert = { Active = false },
        ForwardBasePlan = { Sites = {} },
        GarrisonLossPressure = {},
    },
})
mixedManager:MaintainScouts()
assert(realScout.RedQueenScoutTarget == "objective",
    "the scout must take the objective, got " .. tostring(realScout.RedQueenScoutTarget))
assert(not mixedPool[1].RedQueenScoutTarget and not mixedPool[2].RedQueenScoutTarget,
    "and no combat unit may be diverted while a scout is doing the looking")

for pass = 1, 6 do
    currentTick = savedScoutTick + pass * 30
    mixedManager:MaintainScouts()
end
assert(mixedManager.ScoutSummary.FallbackOrders == 0
    and mixedManager.ScoutSummary.ScoutOrders == 1,
    "a dedicated scout en route must prevent redundant scouting and combat diversion")
table.remove(mixedPool, 3)
mixedManager:MaintainScouts()
assert(mixedManager.ScoutSummary.FallbackOrders == 0,
    "a scout claimed from the pool retains its destination reservation")
realScout.Dead = true
mixedManager:MaintainScouts()
assert(mixedManager.ScoutSummary.FallbackOrders == 1,
    "a dead scout must release its reservation for a replacement")
currentTick = savedScoutTick

-- And with no objective at all there is nothing worth that price.
local noObjectiveLooking = fallbackRun({}, nil, 6)
assert(noObjectiveLooking == 0,
    "without an objective no combat unit may be diverted, got " .. noObjectiveLooking)

print("Red Queen scouting contracts passed")

print("Red Queen forward-base cover contracts passed")
