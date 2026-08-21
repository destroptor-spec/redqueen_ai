Buffs = {}

function BuffBlueprint(definition)
    Buffs[definition.Name] = definition
end

local mockBuff = {
    HasBuff = function()
        return false
    end,
    RemoveBuff = function()
    end,
    ApplyBuff = function()
    end,
}

local mockLogger = {
    Info = function()
    end,
}

function import(path)
    if path == "/lua/sim/Buff.lua" then
        return mockBuff
    end
    if path == "/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua" then
        return mockLogger
    end
    error("unexpected import: " .. tostring(path))
end

dofile("lua/AI/RedQueen/IncomeBonus.lua")

local first = Buffs.RedQueenIncome01
local second = Buffs.RedQueenIncome02
local extreme = Buffs.RedQueenIncome31

assert(first, "missing one-deficit buff")
assert(second, "missing two-deficit buff")
assert(extreme, "missing maximum engine-army deficit buff")
assert(first.Stacks == "REPLACE", "income buffs must replace rather than stack")
assert(first.Affects.MassProduction.Mult == 1.1, "one-deficit mass multiplier")
assert(first.Affects.EnergyProduction.Mult == 1.1, "one-deficit energy multiplier")
assert(second.Affects.MassProduction.Mult == 1.2, "two-deficit mass multiplier")
assert(extreme.Affects.MassProduction.Mult == 4.1, "income formula must remain uncapped")
assert(first.Affects.BuildRate == nil, "income buff must not affect build rate")
assert(first.Affects.VisionRadius == nil, "income buff must not affect vision")
assert(first.Affects.OmniRadius == nil, "income buff must not grant omni")

print("Red Queen income buff contracts passed")
