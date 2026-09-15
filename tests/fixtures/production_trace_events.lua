-- Emit the real producer's callback and snapshot format for the Python reader.
function ClassSimple(definition)
    return setmetatable(definition, { __call = function(class, ...)
        local instance = setmetatable({}, { __index = class })
        instance:__init(...)
        return instance
    end })
end
local tick = 0
function GetGameTick() return tick end
function import(path)
    assert(path == "/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua")
    return { Info = function(_, message)
        print("info: [RedQueen][INFO][army=2] " .. message)
    end }
end
categories = { ENGINEER = 4, COMMAND = 1, FACTORY = 8, STRUCTURE = 2 }
ScenarioInfo = { name = "callback-format", Options = { RedQueenProductionTrace = true } }
local module = setmetatable({}, { __index = _G })
setfenv(assert(loadfile("lua/AI/RedQueen/ProductionTrace.lua")), module)()
local function engineer()
    return {
        EntityId = 10,
        GetBlueprint = function()
            return { BlueprintId = "uel0105", CategoriesHash = { ENGINEER = true } }
        end,
    }
end
local unit = engineer()
local trace = module.Create({ GetArmyIndex = function() return 2 end, GetListOfUnits = function(_, category)
    return category == 3 and { unit } or {}
end }, {
    Production = { GetFactoryTargets = function() return {} end },
    Economy = { State = { MassIncome = 10, EnergyIncome = 90 } },
})
tick = 100
trace:UnitCompleted(unit)
trace:Sample()
tick = 200
trace:UnitLost(unit)
unit = engineer()
tick = 800
trace:UnitCompleted(unit)
trace:Sample()
trace:UnitCompleted({ EntityId = 20, GetBlueprint = function()
    return { BlueprintId = "ueb0101", CategoriesHash = { FACTORY = true } }
end })
