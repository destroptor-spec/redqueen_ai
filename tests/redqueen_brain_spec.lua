-- Exercise the actual startup logging with one Red Queen and a stock ally.
local context = {
    AlliedArmies = { 2, 3, 4 }, EnemyArmies = {}, IncomeMultiplier = 1.2,
}
local lines = {}
local stop = {}
function Class() return function(definition) return definition end end
function WaitTicks() end
function import(path)
    if string.find(path, "adaptive-ai.lua", 1, true) then return { AIBrain = {} } end
    if string.find(path, "MatchContext.lua", 1, true) then
        return { Create = function() return context end }
    end
    if string.find(path, "IncomeBonus.lua", 1, true) then
        return { ApplyToArmy = function() end, LogAppliedBonus = function() end }
    end
    if string.find(path, "Logger.lua", 1, true) then
        return { Info = function(_, line) table.insert(lines, line) end }
    end
    if string.find(path, "ScoutingConfig.lua", 1, true) then
        return { Create = function() error(stop) end }
    end
    return {}
end
ScenarioInfo = { Options = {} }
local environment = setmetatable({}, { __index = _G })
setfenv(assert(loadfile("lua/AI/RedQueenBrain.lua")), environment)()
local function army(index, multiplier)
    return {
        Name = "ARMY_" .. index, Status = "InProgress",
        RedQueenContext = multiplier and { IncomeMultiplier = multiplier },
        GetArmyStartPos = function() return 100, 200 end,
        GetFactionIndex = function() return 2 end,
    }
end
ArmyBrains = { [2] = army(2), [3] = army(3), [4] = army(4, 1.1) }
local ok, err = pcall(environment.AIBrain.RedQueenStartThread, ArmyBrains[2])
assert(not ok and err == stop, "startup must reach the end of match-contract logging")
assert(string.find(lines[1], "income=1.20", 1, true), "own established income must be reported")
assert(not string.find(lines[2], "income=", 1, true), "an unverified stock ally must not inherit our bonus")
assert(string.find(lines[3], "income=1.10", 1, true), "another Red Queen must use its own context")
print("Red Queen per-army income reporting contracts passed")
