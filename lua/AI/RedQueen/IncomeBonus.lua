local Buff = import("/lua/sim/Buff.lua")
local Logger = import("/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua")

local MaximumEngineArmyDeficit = 31
local BuffPrefix = "RedQueenIncome"

local function BuffNameForDeficit(deficit)
    return string.format("%s%02d", BuffPrefix, deficit)
end
for deficit = 1, MaximumEngineArmyDeficit do
    local name = BuffNameForDeficit(deficit)
    if not Buffs[name] then
        BuffBlueprint {
            Name = name,
            DisplayName = "The Red Queen army-deficit income",
            BuffType = "REDQUEENINCOME",
            Stacks = "REPLACE",
            Duration = -1,
            Affects = {
                EnergyProduction = {
                    Add = 0,
                    Mult = 1 + 0.10 * deficit,
                },
                MassProduction = {
                    Add = 0,
                    Mult = 1 + 0.10 * deficit,
                },
            },
        }
    end
end

local function RemoveKnownBuff(unit)
    if not unit or unit.Dead then
        return
    end

    local name = unit.RedQueenIncomeBuffName
    if name and Buff.HasBuff(unit, name) then
        Buff.RemoveBuff(unit, name, true)
    end
    unit.RedQueenIncomeBuffName = nil
end

function OnUnitGiven(newUnit)
    if not newUnit or newUnit.Dead then
        return
    end

    RemoveKnownBuff(newUnit)
    local newBrain = newUnit:GetAIBrain()
    if newBrain and newBrain.RedQueenContext then
        ApplyToUnit(newBrain, newUnit, newBrain.RedQueenContext.ArmyDeficit)
    end
end

---@param brain AIBrain
---@param unit Unit
---@param deficit number
function ApplyToUnit(brain, unit, deficit)
    if not unit or unit.Dead or deficit <= 0 then
        return
    end
    if unit:GetAIBrain() ~= brain then
        return
    end

    local name = BuffNameForDeficit(deficit)
    if unit.RedQueenIncomeBuffName ~= name then
        RemoveKnownBuff(unit)
        Buff.ApplyBuff(unit, name)
        unit.RedQueenIncomeBuffName = name
    end

    if not unit.RedQueenIncomeGivenCallback then
        unit:AddOnGivenCallback(OnUnitGiven)
        unit.RedQueenIncomeGivenCallback = true
    end
end

---@param brain AIBrain
---@param context RedQueenMatchContext
function ApplyToArmy(brain, context)
    if context.ArmyDeficit <= 0 then
        return
    end

    local units = brain:GetListOfUnits(categories.ALLUNITS, false)
    for _, unit in pairs(units) do
        ApplyToUnit(brain, unit, context.ArmyDeficit)
    end
end

---@param brain AIBrain
---@param context RedQueenMatchContext
function SweepArmy(brain, context)
    ApplyToArmy(brain, context)
end

---@param brain AIBrain
---@param unit Unit
function OnUnitCreated(brain, unit)
    local context = brain.RedQueenContext
    if context then
        ApplyToUnit(brain, unit, context.ArmyDeficit)
    end
end

---@param brain AIBrain
---@param context RedQueenMatchContext
function LogAppliedBonus(brain, context)
    Logger.Info(brain, string.format(
        "income contract allies=%d enemies=%d deficit=%d income=%.2f",
        context.AlliedSideSize,
        context.EnemyCount,
        context.ArmyDeficit,
        context.IncomeMultiplier
    ))
end
