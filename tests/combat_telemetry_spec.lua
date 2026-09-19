local logged = {}
function import(path)
    assert(string.find(path, "Logger.lua", 1, true))
    return { Info = function(_, line) table.insert(logged, line) end }
end
categories = { ALLUNITS = {} }
function GetGameTick() return 1200 end
local telemetry = setmetatable({}, { __index = _G })
setfenv(assert(loadfile("lua/AI/RedQueen/CombatTelemetry.lua")), telemetry)()
local pool, native = {}, { PlanName = "AttackForceAI" }
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
-- Two units ordered to defend the same place: one has arrived, one has not.
units[2].RedQueenSentTo = { 100, 0, 100 }
units[2].RedQueenSentKind = "Defend"
units[2].GetPosition = function() return { 100, 0, 100 } end
units[5].RedQueenSentTo = { 100, 0, 100 }
units[5].RedQueenSentKind = "Defend"
units[5].GetPosition = function() return { 900, 0, 900 } end
local modules = {
    Intel = { GetThreatNear = function() return 30 end },
    Strategy = { GetOwnThreatNear = function() return 10 end },
    Combat = { SecondaryRequiredThreat = 120, SecondaryClaimedThreat = 80,
        SecondaryAvailableThreat = 900 },
}
local summary = telemetry.Report(brain, modules)
assert(string.find(summary, "directed:1/180/0/180", 1, true))
assert(string.find(logged[1], "tank:1/1/4", 1, true), "report completions, losses and inventory separately")
assert(string.find(logged[4], "distance=0 observed=30.0 support=10.0", 1, true))

-- The defensive chain end to end.
--
-- The secondary slot reported required against claimed, which is an order and
-- not protection. A shortfall could not be told apart from force that was taken
-- and never arrived, nor from a reserve too small to claim from.
assert(string.find(logged[3], "combat-defence", 1, true), "the defence line follows the plan line")
assert(string.find(logged[3], "required=120 available=900 claimed=80 deficit=40", 1, true),
    "required, the reserve it could draw on, what was taken and what is missing: " .. logged[3])
assert(string.find(logged[3], "sent=2 arrived=1 arrivedmass=180", 1, true),
    "a claimed order is not protection until it is standing there: " .. logged[3])
assert(string.find(logged[3], "Defend:2/1/360/180", 1, true),
    "each defensive kind reports sent, arrived and their mass: " .. logged[3])
assert(string.find(summary, "combatdefence=120/900/80/2/1", 1, true),
    "the periodic state carries the same chain: " .. summary)

-- Concentration: the heaviest own combat mass in one box, over the total.
--
-- The one figure that separated the winning cell from the losing ones was how
-- many places the army was in, not how much of it there was. Peak army, income,
-- tech and map share all failed to discriminate.
local concentrationRestore = units
local function Placed(id, mass, x, z)
    local u = Unit(id, tank, mass, native, false)
    u.GetPosition = function() return { x, 0, z } end
    return u
end
-- Three tanks in one box, one far away: 540 of 720 concentrated.
units = { Placed("tank", 180, 10, 10), Placed("tank", 180, 40, 40),
          Placed("tank", 180, 60, 60), Placed("tank", 180, 4000, 4000) }
logged = {}
summary = telemetry.Report(brain, modules)
assert(string.find(summary, "combatconc=540/720/", 1, true),
    "the heaviest box against the whole army: " .. summary)

-- The same four units, all together: fully concentrated.
units = { Placed("tank", 180, 10, 10), Placed("tank", 180, 20, 20),
          Placed("tank", 180, 30, 30), Placed("tank", 180, 40, 40) }
summary = telemetry.Report(brain, modules)
assert(string.find(summary, "combatconc=720/720/1", 1, true),
    "an army in one place reports one occupied cell and total concentration: " .. summary)

-- And spread one per box: concentration collapses to a single unit.
units = { Placed("tank", 180, 0, 0), Placed("tank", 180, 500, 0),
          Placed("tank", 180, 0, 500), Placed("tank", 180, 500, 500) }
summary = telemetry.Report(brain, modules)
assert(string.find(summary, "combatconc=180/720/4", 1, true),
    "four separated units concentrate nothing: " .. summary)
-- Put the shared fixture back; the assertions below read it.
units = concentrationRestore
logged = {}
summary = telemetry.Report(brain, modules)

-- What a platoon was told to do, not just who owns it.
--
-- Controller alone said two thirds of the dying mass was outside our directed
-- plan and could not say what the rest was sent at. PlatoonFormManager writes
-- PlanName and BuilderName onto the handle, so this is the native task read
-- back rather than inferred.
assert(string.find(logged[2], "combat-plans", 1, true), "the plan line follows production")
assert(string.find(logged[2], "AttackForceAI:3/480/0/0", 1, true),
    "native units are attributed to their own plan: " .. logged[2])
assert(string.find(logged[2], "RedQueenDirected:1/180/1/180", 1, true),
    "our directed platoon is named, and its dead are counted against it: " .. logged[2])
assert(string.find(logged[2], "ArmyPool:1/180/0/0", 1, true),
    "the pool is a task of its own, not an unnamed plan: " .. logged[2])
assert(string.find(logged[2], "unassigned:1/180/0/0", 1, true),
    "a unit in no platoon must not be folded into a named plan: " .. logged[2])
assert(string.find(logged[2], "shown=", 1, true) and string.find(logged[2], "/4 plans=", 1, true),
    "the plan line discloses how many tasks it is showing: " .. logged[2])

-- A platoon with neither name is "unknown" rather than a nil key.
local restore = units
units = { Unit("tank", tank, 180, { }, false) }
logged = {}
telemetry.Report(brain, modules)
assert(string.find(logged[2], "unknown:1/180/0/0", 1, true),
    "a platoon with no plan or builder name is named, not dropped: " .. logged[2])
units = restore
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
-- Production, plans and defence, then twelve capped detail lines.
assert(#logged == 15 and string.find(summary, "combatdetail=12/15", 1, true),
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
assert(table.getn(logged) == 3, "with no keyed group only the production, plan and defence lines")

-- Likewise a missing birth tick reports the -1 sentinel rather than doing
-- arithmetic on nil.
local ageless = { RedQueenDirected = true, RedQueenDirectedId = 99,
    GetPlatoonPosition = directed.GetPlatoonPosition }
units = { Unit("tank", tank, 180, ageless, false) }
logged = {}
telemetry.Report(brain, modules)
assert(string.find(logged[4], "age=-1", 1, true),
    "an unknown birth tick reports the sentinel: " .. tostring(logged[4]))
print("Red Queen combat telemetry contracts passed")
