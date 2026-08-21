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
categoryMetatable.__mul = function() return setmetatable({}, categoryMetatable) end
categoryMetatable.__sub = function() return setmetatable({}, categoryMetatable) end
categories = setmetatable({}, {
    __index = function(value, key)
        local category = setmetatable({}, categoryMetatable)
        rawset(value, key, category)
        return category
    end,
})

function EntityCategoryContains(_, unit)
    return unit.IsCombat == true
end

local currentTick = 100
function GetGameTick() return currentTick end
function IssueClearCommands() end
function IssueMove() end
function IssuePatrol() end

local constants = {
    Policy = {
        MinimumAttackUnits = 3,
        MaximumTaskForceUnits = 60,
        AttackReserveFraction = 0.10,
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

local garrisonUnits = {}
for entityId = 1, 12 do
    table.insert(garrisonUnits, {
        EntityId = entityId,
        IsCombat = true,
        GetPosition = function() return { entityId, 0, 0 } end,
    })
end
local garrisonPool = { GetPlatoonUnits = function() return garrisonUnits end }
local garrisonStrategy = {
    ProductionDemand = {
        DefenseAlert = { Active = false },
        ForwardBasePlan = {
            Sites = {
                { Name = "RQFB_1_1", Position = { 100, 0, 100 }, State = "Building" },
            },
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

garrisonStrategy.ProductionDemand.DefenseAlert.Active = true
garrisonManager:MaintainForwardGarrisons()
for _, unit in pairs(garrisonUnits) do
    assert(not unit.RedQueenGarrisonSite, "emergency defense must release forward garrisons")
end

print("Red Queen combat manager contracts passed")
