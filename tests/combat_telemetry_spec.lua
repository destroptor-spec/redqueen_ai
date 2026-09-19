local logged = {}
function import(path)
    assert(string.find(path, "Logger.lua", 1, true))
    return { Info = function(_, line) table.insert(logged, line) end }
end
categories = { ALLUNITS = {} }
function GetGameTick() return 1200 end
local telemetry = setmetatable({}, { __index = _G })
setfenv(assert(loadfile("lua/AI/RedQueen/CombatTelemetry.lua")), telemetry)()
local pool, native = {}, {}
local directed = {
    RedQueenDirected = true, RedQueenDirectedId = 1, RedQueenDirectionBorn = 300,
    RedQueenDirectionPosition = { 100, 0, 100 },
    GetPlatoonPosition = function() return { 100, 0, 100 } end,
}
local function Unit(id, hash, mass, platoon, idle)
    return {
        PlatoonHandle = platoon,
        GetBlueprint = function()
            return { BlueprintId = id, CategoriesHash = hash, Economy = { BuildCostMass = mass } }
        end,
        IsIdleState = function() return idle end,
        IsUnitState = function() return false end,
    }
end
local tank = { MOBILE = true, LAND = true, TECH2 = true }
local units = {
    Unit("tank", tank, 180, directed, false),
    Unit("tank", tank, 180, pool, true),
    Unit("jet", { MOBILE = true, AIR = true }, 100, native, false),
    Unit("ship", { MOBILE = true, NAVAL = true }, 200, native, false),
    Unit("tank", tank, 180, native, false),
    Unit("tank", tank, 180, nil, true),
    Unit("engineer", { MOBILE = true, ENGINEER = true }, 50, directed, true),
    Unit("transport", { MOBILE = true, AIR = true, TRANSPORTFOCUS = true }, 200, native, true),
    Unit("factory", { STRUCTURE = true, FACTORY = true, LAND = true, TECH1 = true }, 240, nil, true),
    Unit("gate", { STRUCTURE = true, FACTORY = true, TECH3 = true }, 1000, nil, true),
}
local brain = {
    GetPlatoonUniquelyNamed = function() return pool end,
    GetListOfUnits = function(_, category)
        assert(category == categories.ALLUNITS, "only our own unit list is collected")
        return units
    end,
}
telemetry.Record(brain, units[1], "built")
telemetry.Record(brain, units[7], "built")
local dead = Unit("tank", tank, 180, directed)
dead.Dead = true
table.insert(units, dead)
telemetry.Record(brain, dead, "lost")
telemetry.Record(brain, dead, "lost")
telemetry.Record(brain, units[1], "built")
assert(brain.RedQueenCombatTelemetry.RepeatedDeaths == 1,
    "repeated native death notifications must not inflate unit losses")
local facts = telemetry.Collect(brain)
assert(facts.Controllers.directed.Count == 1 and facts.Controllers.directed.Lost == 180,
    "count living inventory separately from cumulative dead-unit value")
assert(facts.Controllers.pool.Idle == 1 and facts.Controllers.unassigned.Count == 1,
    "unassigned units must not silently become pool or native units")
assert(facts.Controllers.nativeLand.Count == 1 and facts.Controllers.nativeAir.Count == 1
    and facts.Controllers.nativeNaval.Count == 1, "native controller domains must remain distinct")
assert(facts.Factories.L1.Ready == 1 and facts.Factories.L1.Idle == 1,
    "only combat factory domains count; a gate must not supply combat capacity")
assert(brain.RedQueenCombatTelemetry.Blueprints.engineer == nil, "engineers are outside combat output")
local modules = {
    Intel = { GetThreatNear = function() return 30 end },
    Strategy = { GetOwnThreatNear = function() return 10 end },
}
local summary = telemetry.Report(brain, modules)
assert(string.find(summary, "directed:1/180/0/180", 1, true))
assert(string.find(logged[1], "tank:1/1/4", 1, true), "report completions, losses and inventory separately")
assert(string.find(logged[2], "distance=0 observed=30.0 support=10.0", 1, true))
-- Reporting twice must never increment event counters or change unit ownership.
telemetry.Report(brain, modules)
assert(brain.RedQueenCombatTelemetry.Blueprints.tank.Built == 1)
assert(units[1].PlatoonHandle == directed and units[2].PlatoonHandle == pool)
-- Bound detail volume without hiding that a larger army was only sampled.
for id = 2, 15 do
    local p = { RedQueenDirected = true, RedQueenDirectedId = id, RedQueenDirectionBorn = 0,
        GetPlatoonPosition = directed.GetPlatoonPosition }
    table.insert(units, Unit("tank", tank, 180, p, true))
end
logged = {}
summary = telemetry.Report(brain, modules)
assert(#logged == 13 and string.find(summary, "combatdetail=12/15", 1, true),
    "detail cap must be enforced and disclosed")
assert(string.find(summary, "combatunkeyed=0", 1, true), "nothing is unkeyed in the normal case")

-- An observer must never be able to take the brain down.
--
-- A directed platoon with no id cannot be a table key, and indexing with nil
-- raises "table index is nil" -- which would kill the diagnostics pass every
-- game minute, the way a constructor probing MapSize once killed the brain
-- outright for a whole match. ObjectiveAttack sets the id and the flag
-- together, so neither case below is reachable today; both are one refactor
-- away, and no contract can catch it after the fact because specs supply their
-- own environment.
local unkeyed = { RedQueenDirected = true, GetPlatoonPosition = directed.GetPlatoonPosition }
units = { Unit("tank", tank, 180, unkeyed, false) }
logged = {}
summary = telemetry.Report(brain, modules)
assert(string.find(summary, "combatunkeyed=1", 1, true),
    "a directed platoon with no id is counted and disclosed, not a crash: " .. summary)
assert(string.find(summary, "directed:1/180/0/", 1, true),
    "it still counts toward its controller's inventory")
assert(table.getn(logged) == 1, "with no keyed group there is only the production line")

-- Likewise a missing birth tick reports the -1 sentinel rather than doing
-- arithmetic on nil.
local ageless = { RedQueenDirected = true, RedQueenDirectedId = 99,
    GetPlatoonPosition = directed.GetPlatoonPosition }
units = { Unit("tank", tank, 180, ageless, false) }
logged = {}
telemetry.Report(brain, modules)
assert(string.find(logged[2], "age=-1", 1, true),
    "an unknown birth tick reports the sentinel: " .. tostring(logged[2]))
print("Red Queen combat telemetry contracts passed")
