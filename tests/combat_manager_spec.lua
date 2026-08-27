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
categoryMetatable.__mul = function(left, right)
    return setmetatable({ Exclusions = MergeExclusions(left, right) }, categoryMetatable)
end
categoryMetatable.__sub = function(left, right)
    local exclusions = MergeExclusions(left, right)
    if right.Name then
        exclusions[right.Name] = true
    end
    return setmetatable({ Exclusions = exclusions }, categoryMetatable)
end
categories = setmetatable({}, {
    __index = function(value, key)
        local category = setmetatable({ Name = key, Exclusions = {} }, categoryMetatable)
        rawset(value, key, category)
        return category
    end,
})

function EntityCategoryContains(category, unit)
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
    },
}
local logger = { Debug = function() end }

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
waterManager:Update()
assert(pathLayers.Amphibious, "water defense must test amphibious pathing")
assert(table.getn(aggressiveOrders) == 1, "water defense must dispatch available amphibious forces")
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
assert(assigned == 10, "non-UEF forward bases without sentries must reserve a larger T3 garrison")
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
for _, unit in pairs(garrisonUnits) do
    assert(not unit.RedQueenGarrisonSite, "emergency defense must release forward garrisons")
end

print("Red Queen combat manager contracts passed")
