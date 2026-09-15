function ClassSimple(definition)
    return setmetatable(definition, {
        __call = function(class, ...)
            local instance = setmetatable({}, { __index = class })
            instance:__init(...)
            return instance
        end,
    })
end

local constants = {
    Policy = {
        EconomyStagnationSeconds = 180,
        EconomyGrowthRatio = 1.05,
        EconomyMarkDecay = 0.97,
        OpeningDurationSeconds = 240,
    },
}

local logged = {}
local logger = {
    Info = function(_, message) table.insert(logged, message) end,
    Debug = function() end,
    Warning = function() end,
    Error = function() end,
}

-- FAF extends the standard library; table.getsize has no LuaJIT equivalent.
function table.getsize(value)
    if type(value) ~= "table" then
        return 0
    end
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    return count
end

-- Category expressions are opaque handles in the engine. Composites carry a
-- composed name so a contract can key on one; without a __mul the state line's
-- own `ENGINEER * MOBILE` lookup would raise.
local categoryMetatable = {}
categoryMetatable.__mul = function(left, right)
    return setmetatable(
        { Name = "(" .. tostring(left.Name) .. "*" .. tostring(right.Name) .. ")" },
        categoryMetatable
    )
end
categories = setmetatable({}, {
    __index = function(value, key)
        local category = setmetatable({ Name = key }, categoryMetatable)
        rawset(value, key, category)
        return category
    end,
})

-- Loaded the way the engine's import() does -- environment as module, return
-- value discarded -- so this contract cannot pass against an export style the
-- engine would reject.
local function importModule(path)
    local environment = setmetatable({}, { __index = _G })
    setfenv(assert(loadfile(path)), environment)()
    return environment
end
local experimentals = importModule("lua/AI/RedQueen/Experimentals.lua")

function import(path)
    if path == "/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua" then
        return constants
    elseif path == "/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua" then
        return logger
    elseif path == "/mods/TheRedQueen/lua/AI/RedQueen/Experimentals.lua" then
        return experimentals
    end
    error("unexpected import: " .. tostring(path))
end

local currentTick = 0
function GetGameTick() return currentTick end

dofile("lua/AI/RedQueen/Diagnostics.lua")

local diagnostics = Create({}, {})

local function Sample(seconds, income)
    currentTick = seconds * 10
    diagnostics:ReportEconomy({
        GameTimeSeconds = seconds,
        SmoothedMassIncome = income,
        Mode = "Balanced",
    })
end

-- Reclaim counts as income, so a commander clearing rocks produces the largest
-- and least representative reading of the match. One run reported
-- "declining mass=3.0 peak=48.9" a minute into a healthy start.
Sample(60, 48.9)
Sample(120, 3.0)
Sample(180, 3.2)
Sample(239, 3.4)
assert(table.getn(logged) == 0, "the opening must never be reported as stagnant or declining")
assert(diagnostics.StagnationMark == nil, "the opening must not leave a high-water mark behind")
assert(diagnostics.StagnationGrowthMark == nil, "the opening must not establish a growth reference")

-- After the opening a genuine plateau is reported.
Sample(300, 20.0)
Sample(360, 20.1)
Sample(420, 20.2)
Sample(480, 20.2)
Sample(540, 20.3)
Sample(600, 20.3)
assert(table.getn(logged) == 1, "a sustained plateau must be reported once")
assert(string.find(logged[1], "stagnant"), "a plateau is stagnation, not decline: " .. logged[1])

-- A genuine decline is named differently, because it is worse news.
logged = {}
diagnostics = Create({}, {})
Sample(660, 20.4)
Sample(720, 8.0)
Sample(780, 8.0)
Sample(840, 8.0)
Sample(900, 8.0)
assert(table.getn(logged) == 1, "a sustained fall must be reported")
assert(string.find(logged[1], "declining"), "a falling economy must not read as a plateau: " .. logged[1])

-- A transient spike must fade rather than define the baseline forever. Without
-- the decay a single burst keeps every later sample below the mark for good.
logged = {}
diagnostics = Create({}, {})
Sample(1000, 200.0)
local marked = diagnostics.StagnationMark
for seconds = 1060, 3000, 60 do
    Sample(seconds, 30.0)
end
assert(
    diagnostics.StagnationMark < marked,
    "a transient spike must decay out of the high-water mark"
)

-- Growth resets the window, so a climbing economy is never reported.
logged = {}
diagnostics = Create({}, {})
local income = 10.0
for seconds = 3060, 4200, 60 do
    income = income * 1.20
    Sample(seconds, income)
end
assert(table.getn(logged) == 0, "a climbing economy must never be reported as stagnant")

-- Run every real diagnostic sample for twenty minutes after the opening.
-- Skipping samples hides the interaction between decay and window resets.
logged = {}
diagnostics = Create({}, {})
for seconds = 300, 1500, 60 do
    Sample(seconds, 20.0)
    local expectedReports = math.floor((seconds - 300) / 180)
    assert(table.getn(logged) == expectedReports,
        "constant income must report every full stagnation window at " .. tostring(seconds))
    assert(diagnostics.StagnationTick == 3000, "decay cannot move the last actual growth tick")
end
assert(table.getn(logged) == 6, "twenty minutes of constant income must produce six reports")
for _, message in ipairs(logged) do
    assert(string.find(message, "stagnant"), "flat income must not be labelled declining")
end

-- Small gains accumulate against the last real growth sample, rather than
-- being ignored because each individual gain is below five percent.
logged = {}
diagnostics = Create({}, {})
local gradualIncome = 20.0
for seconds = 300, 1500, 60 do
    Sample(seconds, gradualIncome)
    gradualIncome = gradualIncome * 1.02
end
assert(table.getn(logged) == 0, "sustained cumulative growth must keep resetting the window")

-- Losing income is not growth; recovering from that loss is. The old peak
-- can remain above a healthy recovery without suppressing genuine progress.
logged = {}
diagnostics = Create({}, {})
Sample(300, 200.0)
Sample(360, 20.0)
assert(diagnostics.StagnationTick == 3000, "a decline must not reset the window")
Sample(420, 22.0)
assert(diagnostics.StagnationTick == 4200, "recovery below a past spike must count as actual growth")
assert(diagnostics.StagnationMark > 22, "the reported peak must still decay independently")
Sample(480, 22.0)
Sample(540, 22.0)
assert(table.getn(logged) == 0, "actual growth starts a complete new observation window")
Sample(600, 22.0)
assert(table.getn(logged) == 1, "a post-recovery plateau must report after the full window")


-- The state line reports which experimental the classification would field.
--
-- This is the only contract that drives Update, and it earns its scaffolding:
-- string.format raises when the argument count does not match the format, so
-- appending a field without its argument is a runtime error in every match and
-- a syntax check cannot see it.
local reachable = { Amphibious = true, Air = true, Water = true }
local modules = {
    Strategy = {
        CurrentObjective = { Type = "Pressure" },
        ProductionDemand = {
            Doctrine = "Balanced",
            Scouts = 0.128,
            FocusWeights = { Army = 60, Tech2 = 0, Tech3 = 0, Experimental = 71, Nuke = 0 },
            PrimaryFocus = "Army",
            MajorProjectSlots = 1,
            DesiredExperimentals = 3,
            DesiredEngineers = 7,
            EngineerLossPressure = { Count = 2, Mass = 104 },
            EconomicReadiness = 0.5,
            DefenseAlert = {
                Active = true, Threat = 210, Ratio = 2.5,
                QualifiedArm = "surface", FriendlySurface = 84, FriendlyAir = 400,
            },
            TierPolicy = {
                Land = { Highest = 3 }, Air = { Highest = 3 }, Naval = { Highest = 1 },
            },
            ForwardBasePlan = { Active = false, Sites = {} },
            FocusReason = "none",
        },
        LandLossPressure = { Count = 0, Mass = 0 },
        AirLossPressure = { Count = 0, Mass = 0 },
        CombatMomentum = { LostMass = 0, DestroyedMass = 0, Losing = false },
    },
    Economy = { State = { Mode = "Balanced", MassIncome = 29.5, EnergyIncome = 1339.6,
                          GameTimeSeconds = 900, SmoothedMassIncome = 29.5,
                          DesiredFactories = 10 } },
    Production = {
        Counts = { Total = 12, Land = 6, Air = 4, Naval = 2, TargetTotal = 12 },
        EngineerPolicy = { Held = 20, Target = 7, Ceiling = 18, Suppressed = 3 },
    },
    Combat = {
        GarrisonSummary = { Sites = 2, Units = 9 },
        ScoutSummary = { Targets = 10, Blind = 6, Sent = 0, ScoutOrders = 11, FallbackOrders = 4 },
        DispatchSummary = { Land = 12, Air = 3, Water = 0, Amphibious = 2, Hover = 1 },
    },
    Intel = { Observations = {} },
    World = {
        StartPosition = { 10, 0, 10 },
        MassPointCount = 24,
        GetClosestEnemyStart = function(_, origin, layer)
            return reachable[layer] and { 90, 0, 90 } or nil
        end,
    },
}
local brain = {
    RedQueenContext = { FactionIndex = 2 },
    GetCurrentUnits = function() return 1 end,
}

logged = {}
local reporter = Create(brain, modules)
reporter:Update()
local state = logged[table.getn(logged)]
assert(state, "Update must log a state line")
assert(string.find(state, "exp=Assault:ual0401/1/3", 1, true),
    "the state line must name the classified choice, owned count and fleet target: " .. state)

-- Engineers held, wanted, and recently lost. A shortfall suppresses income and
-- production together, so a flatline is only diagnosable if all three are
-- reported side by side.
assert(string.find(state, "eng=1/7/2", 1, true),
    "the state line must report engineers held, target and recent losses: " .. state)

-- Forward-base cover and the engineer suppression ceiling. Both mechanisms ran
-- for a full 21-cell matrix without appearing in any log: cover stood down for
-- 86% of bases behind a Tech 3 filter, and suppression pinned two armies to 3
-- engineers. Neither was visible in an outcome, only in a mechanism figure.
assert(string.find(state, "cover=2/9", 1, true),
    "the state line must report sites covered and units committed: " .. state)
assert(string.find(state, "engpolicy=3/18", 1, true),
    "and the engineer builders suppressed against the ceiling that cut them: " .. state)

-- Extractors held against mass points on the map. An unclaimed point is 36 mass
-- for +2/s -- an 18-second payback, against 225 seconds for a Tech 2 upgrade --
-- so this is the figure that says whether there is cheap economy left to take.
assert(string.find(state, "mex=1/24", 1, true),
    "the state line must report extractors held against the map's mass points: " .. state)
assert(string.find(state, "scout=10/6/0 scoutorders=11/4 scouts=1 scoutfraction=0.128", 1, true),
    "scouting must report coverage, cumulative orders, held scouts and requested fraction: " .. state)

-- Which arm qualified, and what each arm actually has defending it. Alert counts
-- alone cannot say whether a change came from the surface reading, the air
-- reading or the combined one, and severity is taxed off the ratio -- so a
-- matrix reading only "alerts raised" cannot attribute an endgame swing.
assert(string.find(state, "alert=yes/210.0/2.50/surface/84/400", 1, true),
    "the alert must report the qualifying arm and the defence each arm holds: " .. state)

-- Units ordered per layer. The fleet is why this exists: a naval force with no
-- destination receives no order at all, and no outcome figure shows it. W
-- staying 0 across a match on a map with water is the symptom.
assert(string.find(state, "dispatch=L12,A3,W0,M2,H1", 1, true),
    "the state line must report units dispatched per layer: " .. state)

-- With no surface route the amphibious Colossus is out and the air CZAR is the
-- reachable assault choice, which is exactly the distinction the layer gating
-- exists to make.
reachable.Amphibious = false
logged = {}
reporter:Update()
assert(string.find(logged[table.getn(logged)], "exp=Assault:uaa0310/1/3", 1, true),
    "losing the amphibious route must fall through to the reachable air choice")

-- No route at all leaves only the siege piece, which needs none.
reachable.Air = false
reachable.Water = false
logged = {}
reporter:Update()
assert(string.find(logged[table.getn(logged)], "exp=Siege:xab2307/1/3", 1, true),
    "with nothing reachable the static siege experimental is the remaining option")

print("Red Queen diagnostics contracts passed")
