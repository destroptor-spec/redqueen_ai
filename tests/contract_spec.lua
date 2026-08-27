dofile("lua/AI/RedQueen/MatchContext.lua")

local function AssertEqual(actual, expected, label)
    if math.abs(actual - expected) > 0.000001 then
        error(string.format("%s: expected %.4f, got %.4f", label, expected, actual))
    end
end

AssertEqual(CalculateArmyDeficit(1, 1), 0, "1v1 deficit")
AssertEqual(CalculateArmyDeficit(2, 1), 1, "1v2 deficit")
AssertEqual(CalculateArmyDeficit(3, 1), 2, "1v3 deficit")
AssertEqual(CalculateArmyDeficit(3, 2), 1, "2v3 deficit")
AssertEqual(CalculateArmyDeficit(1, 3), 0, "larger allied side")

AssertEqual(CalculateIncomeMultiplier(1, 1), 1.0, "1v1 multiplier")
AssertEqual(CalculateIncomeMultiplier(2, 1), 1.1, "1v2 multiplier")
AssertEqual(CalculateIncomeMultiplier(3, 1), 1.2, "1v3 multiplier")
AssertEqual(CalculateIncomeMultiplier(3, 2), 1.1, "2v3 multiplier")
AssertEqual(CalculateIncomeMultiplier(15, 1), 2.4, "uncapped 1v15 multiplier")

assert(NormalizeVictoryCondition("demoralization") == "Assassination", "demoralization must remain Assassination")
assert(NormalizeVictoryCondition("domination") == "Supremacy", "domination must remain Supremacy")
assert(NormalizeVictoryCondition("eradication") == "Annihilation", "eradication must remain distinguishable as Annihilation")

print("Red Queen formula contracts passed")
