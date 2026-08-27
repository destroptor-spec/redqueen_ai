local function IsActiveArmy(brain)
    if not brain or brain.Civilian then
        return false
    end

    local status = brain.Status
    return status ~= "Defeat" and status ~= "Recalled"
end
function CalculateArmyDeficit(enemyCount, alliedSideSize)
    return math.max(0, (enemyCount or 0) - (alliedSideSize or 0))
end

function CalculateIncomeMultiplier(enemyCount, alliedSideSize)
    return 1 + 0.10 * CalculateArmyDeficit(enemyCount, alliedSideSize)
end

function NormalizeVictoryCondition(rawVictory)
    if rawVictory == "demoralization" or rawVictory == "decapitation" then
        return "Assassination"
    end
    if rawVictory == "domination" then
        return "Supremacy"
    end
    if rawVictory == "eradication" then
        return "Annihilation"
    end
    return tostring(rawVictory or "Unknown")
end

---@class RedQueenMatchContext
---@field Army number
---@field AlliedArmies number[]
---@field EnemyArmies number[]
---@field AlliedSideSize number
---@field EnemyCount number
---@field ArmyDeficit number
---@field IncomeMultiplier number
---@field FactionIndex number
---@field VictoryCondition string
---@field CreatedTick number

---@param brain AIBrain
---@return RedQueenMatchContext
function Create(brain)
    local army = brain.Army or brain:GetArmyIndex()
    local alliedArmies = {}
    local enemyArmies = {}

    for armyIndex, otherBrain in pairs(ArmyBrains) do
        if IsActiveArmy(otherBrain) then
            if armyIndex == army or IsAlly(army, armyIndex) then
                table.insert(alliedArmies, armyIndex)
            elseif IsEnemy(army, armyIndex) then
                table.insert(enemyArmies, armyIndex)
            end
        end
    end

    table.sort(alliedArmies)
    table.sort(enemyArmies)

    local alliedSideSize = table.getn(alliedArmies)
    local enemyCount = table.getn(enemyArmies)
    local armyDeficit = CalculateArmyDeficit(enemyCount, alliedSideSize)

    return {
        Army = army,
        AlliedArmies = alliedArmies,
        EnemyArmies = enemyArmies,
        AlliedSideSize = alliedSideSize,
        EnemyCount = enemyCount,
        ArmyDeficit = armyDeficit,
        IncomeMultiplier = CalculateIncomeMultiplier(enemyCount, alliedSideSize),
        FactionIndex = brain:GetFactionIndex(),
        VictoryCondition = NormalizeVictoryCondition(ScenarioInfo.Options.Victory),
        CreatedTick = GetGameTick(),
    }
end
