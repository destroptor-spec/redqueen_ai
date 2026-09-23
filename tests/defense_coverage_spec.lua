-- Whether a defence can reach the fighting, not whether it exists.
--
-- Observed while spectating: the point defences and anti-air that were built
-- sat beside the factories and shields, out of range of the attack until the
-- enemy had already arrived there. `FortificationBuilders` cannot see that --
-- it satisfies a tier's need with any allied structure of that tier anywhere
-- inside the base radius. These contracts pin the measurement that can.
local constants = {
    Policy = { FortificationMinimumRadius = 40 },
}

function import(path)
    if path == "/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua" then
        return constants
    end
    error("unexpected import: " .. tostring(path))
end

categories = setmetatable({}, {
    __index = function(value, key)
        local category = { Name = key }
        rawset(value, key, category)
        return category
    end,
})
-- Category algebra only has to be distinguishable, not faithful.
getmetatable(categories).__index = function(value, key)
    local category = setmetatable({ Name = key }, {
        __mul = function(a, b) return { Name = a.Name .. "*" .. b.Name } end,
    })
    rawset(value, key, category)
    return category
end

local environment = setmetatable({}, { __index = _G })
setfenv(assert(loadfile("lua/AI/RedQueen/DefenseCoverage.lua")), environment)()

local function Gun(x, z, range)
    return {
        GetPosition = function() return { x, 0, z } end,
        GetBlueprint = function()
            return {
                BlueprintId = "pd" .. tostring(range),
                Weapon = { { MaxRadius = range } },
            }
        end,
    }
end

-- A shield is a structure near the base with no weapon at all. It satisfies a
-- base-wide structure count while covering nothing, which is exactly the
-- confusion this measurement exists to remove.
local shield = {
    GetPosition = function() return { 0, 0, 0 } end,
    GetBlueprint = function() return { BlueprintId = "shield", Weapon = {} } end,
}

assert(environment.WeaponRange(shield) == 0, "a weaponless structure has no reach")
assert(environment.WeaponRange(Gun(0, 0, 26)) == 26, "reach is the longest weapon")
assert(environment.Covers(Gun(0, 0, 26), { 20, 0, 0 }), "a gun in range covers")
assert(not environment.Covers(Gun(0, 0, 26), { 40, 0, 0 }),
    "a gun out of range does not cover, however close to the base it stands")
assert(not environment.Covers(shield, { 1, 0, 0 }),
    "a weaponless structure never covers, at any distance")

-- Four guns at the base, an attack 150 away: the spectated case.
local defences = { Gun(0, 0, 26), Gun(10, 0, 10), Gun(-10, 0, 5), shield }
local brain = {
    GetListOfUnits = function(_, category)
        if category.Name == "STRUCTURE*DEFENSE" then return defences end
        return {}
    end,
}
local summary = environment.Summarise(brain, {
    Active = true, AnchorPosition = { 150, 0, 0 },
})
assert(summary.Total == 4, "every defence structure is held, got " .. summary.Total)
assert(summary.Covering == 0,
    "none of them can reach an attack 150 away, got " .. summary.Covering)
assert(math.floor(summary.Nearest) == 140,
    "and the nearest is 140 from the fighting, got " .. tostring(summary.Nearest))

-- The same guns against an attack close to the base. Two of the three reach it:
-- the long-ranged gun at the centre and the short one it happens to stand near.
-- The third has range 5 and is 23 away, which is the whole point -- reach is
-- per weapon, and a base-wide count cannot see it.
local near = environment.Summarise(brain, { Active = true, AnchorPosition = { 12, 0, 8 } })
assert(near.Covering == 2, "two guns reach a close attack, got " .. near.Covering)

-- An inactive alert has nothing to cover and must not be scored as failure.
local idle = environment.Summarise(brain, { Active = false, AnchorPosition = { 1, 0, 1 } })
assert(idle.Total == 4 and idle.Covering == 0 and idle.Nearest == 0,
    "an inactive alert reports holdings without a coverage verdict")

-- Extractor losses, with whether anything could have shot the attacker.
--
-- The recording itself must make NO engine call. It runs on the unit-destruction
-- path, and the first version asked the brain for its defence structures there:
-- that perturbed the simulation, reproducibly, in one cell of eighteen. A brain
-- whose GetListOfUnits raises proves the call is gone.
local tripwire = {
    GetListOfUnits = function()
        error("RecordExtractorLoss must not query the brain on the destruction path")
    end,
}
environment.RecordExtractorLoss(tripwire, { 1, 0, 1 })
assert(tripwire.RedQueenExtractorLosses.Lost == 1,
    "the loss is still counted without touching the engine")

environment.RecordExtractorLoss(brain, { 200, 0, 200 })
environment.RecordExtractorLoss(brain, { 5, 0, 5 })
-- Unresolved until the next state line, which is where the defence list is
-- fetched anyway.
assert(environment.LossSummary(brain).Defended == 0,
    "coverage of a loss is not answered on the destruction path")
local report = environment.Report(brain, { Active = false })
assert(report.Loss.Lost == 2, "both losses counted, got " .. report.Loss.Lost)
assert(report.Loss.Defended == 1,
    "only the one inside a gun's reach was defended, got " .. report.Loss.Defended)
-- Resolving twice must not count the same loss again.
local again = environment.Report(brain, { Active = false })
assert(again.Loss.Defended == 1,
    "a resolved loss is not re-counted, got " .. again.Loss.Defended)

-- Report is the single entry point, so the module's engine queries per state
-- line stay fixed no matter how many extractors died in between.
local queries = 0
local counting = {
    GetListOfUnits = function(_, category)
        queries = queries + 1
        if category.Name == "STRUCTURE*DEFENSE" then return defences end
        return {}
    end,
}
for _ = 1, 5 do environment.RecordExtractorLoss(counting, { 5, 0, 5 }) end
environment.Report(counting, { Active = false })
assert(queries == 1,
    "one query per state line regardless of losses, got " .. queries)

-- Fortifiable span: deposits outside every base manager cannot be offered a
-- fortification builder at all, so they are unreachable rather than
-- under-defended.
--
-- Measured from the map's mass markers, never from a unit query:
-- GetListOfUnits(STRUCTURE * MASSEXTRACTION) perturbs the simulation, bisected
-- over five matches on one cell. The same call for STRUCTURE * DEFENSE is
-- clean. A brain whose GetListOfUnits raises when asked for anything but
-- defences proves the extractor query is gone.
local world = {
    MassClusters = {
        { Markers = { { Position = { 0, 0, 0 } }, { Position = { 30, 0, 0 } } } },
        { Markers = { { position = { 400, 0, 400 } } } },   -- lowercase, as markers come
    },
}
local spanBrain = {
    BuilderManagers = {
        MAIN = { EngineerManager = {
            Radius = 100,
            GetLocationCoords = function() return { 0, 0, 0 } end,
        } },
    },
    GetListOfUnits = function(_, category)
        if category.Name ~= "STRUCTURE*DEFENSE" then
            error("BaseSpan must not query units; it reads the map's markers")
        end
        return {}
    end,
}
local span = environment.BaseSpan(spanBrain, world)
assert(span.Bases == 1, "one registered base, got " .. span.Bases)
assert(span.Inside == 2 and span.Outside == 1,
    "two deposits inside the base radius and one beyond every base, got "
        .. span.Inside .. "/" .. span.Outside)

-- No world model yet (the brain is built before the map is read): report the
-- bases and no verdict, rather than raising inside a diagnostic.
local early = environment.BaseSpan(spanBrain, nil)
assert(early.Bases == 1 and early.Inside == 0 and early.Outside == 0,
    "an absent world model yields bases without a span")

-- And the whole report still makes exactly one unit query.
local reportQueries = 0
local reportBrain = {
    BuilderManagers = spanBrain.BuilderManagers,
    GetListOfUnits = function(_, category)
        reportQueries = reportQueries + 1
        if category.Name ~= "STRUCTURE*DEFENSE" then
            error("Report must query defences and nothing else")
        end
        return defences
    end,
}
environment.Report(reportBrain, { Active = false }, world)
assert(reportQueries == 1,
    "one unit query per state line, got " .. reportQueries)

print("Red Queen defence coverage contracts passed")
