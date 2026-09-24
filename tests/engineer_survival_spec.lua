-- Whether an engineer is sent somewhere at all.
--
-- Native `EngineerMoveWithSafePath` returns true after its threat-constrained
-- path fails, so the caller issues the build order and the engineer walks into
-- whatever is there. These contracts pin the decision that refuses it, and
-- equally the cases that must NOT be refused: an army that cannot build at home
-- under pressure is worse off than one that loses engineers.
local constants = {
    Policy = {
        EngineerSurvivalThreatFloor = 8,
        EngineerSurvivalHomeRadius = 80,
        EngineerLethalSiteMemorySeconds = 180,
        EngineerLethalSiteRadius = 40,
        ForwardBaseSiteRadius = 60,
        ForwardBaseSafetyRatio = 0.60,
        CommanderLeashRadius = 120,
    },
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

function EntityCategoryContains(category, unit)
    return (unit.Categories or {})[category.Name] == true
end

currentTick = 0
function GetGameTick()
    return currentTick
end

-- The module exports globals, as FAF's import() returns the file environment
-- and discards a returned table. Loaded the way the engine loads it.
local survival = setmetatable({}, { __index = _G })
setfenv(assert(loadfile("lua/AI/RedQueen/EngineerSurvival.lua")), survival)()

local function engineer(motionType)
    return {
        GetPosition = function() return { 0, 0, 0 } end,
        GetBlueprint = function()
            return { Physics = { MotionType = motionType or "RULEUMT_Amphibious" } }
        end,
    }
end

local function brainWith(routeThreat, ownThreat, layerSeen)
    return {
        RedQueenModules = {
            World = {
                StartPosition = { 0, 0, 0 },
                GetObservedRouteThreat = function(_, _, _, _, _, layer)
                    if layerSeen then layerSeen.Layer = layer end
                    return routeThreat
                end,
            },
            Intel = {},
            Strategy = {
                GetOwnThreatNear = function() return ownThreat or 0 end,
            },
        },
    }
end

-- The engineer's own graph decides the route, not native's hard-coded
-- 'Amphibious'. Every Aeon and Seraphim engineer is RULEUMT_Hover, and hover
-- crosses deep water where amphibious is blocked -- so judging a hover
-- engineer's walk on the amphibious graph assesses a journey it is not making.
local seen = {}
survival.RouteVerdict(brainWith(0, 0, seen), engineer("RULEUMT_Hover"), { 500, 0, 500 })
assert(seen.Layer == "Hover",
    "a hover engineer's route must be judged on the hover graph, got " .. tostring(seen.Layer))
survival.RouteVerdict(brainWith(0, 0, seen), engineer("RULEUMT_AmphibiousFloating"), { 500, 0, 500 })
assert(seen.Layer == "Amphibious",
    "and an amphibious engineer on the amphibious graph, got " .. tostring(seen.Layer))

-- A quiet distant destination is allowed.
local ok, reason = survival.RouteVerdict(brainWith(0, 0), engineer(), { 500, 0, 500 })
assert(ok and reason == "safe", "a quiet route must be allowed, got " .. tostring(reason))

-- A dangerous one is refused. This is the observed behaviour being repaired.
ok, reason = survival.RouteVerdict(brainWith(70.5, 0), engineer(), { 500, 0, 500 })
assert(not ok and reason == "route-unsafe",
    "a hostile route must be refused, got " .. tostring(ok) .. "/" .. tostring(reason))

-- Trivial threat must not refuse an unescorted engineer. Scaling only with
-- nearby friendly strength gives a limit of zero on a lone walk, which would
-- abandon expansion because a scout was seen; 0.6 was measured harmless.
ok, reason = survival.RouteVerdict(brainWith(0.6, 0), engineer(), { 500, 0, 500 })
assert(ok, "a trivial sighting must not refuse the assignment, got " .. tostring(reason))

-- Escort raises the tolerance above the floor, so a covered advance proceeds
-- into threat that a lone engineer would refuse.
ok = survival.RouteVerdict(brainWith(30, 0), engineer(), { 500, 0, 500 })
assert(not ok, "an unescorted engineer must refuse a threat of 30")
ok, reason = survival.RouteVerdict(brainWith(30, 100), engineer(), { 500, 0, 500 })
assert(ok, "the same route with escort must be allowed, got " .. tostring(reason))

-- Home construction is never refused, whatever the threat. An army under
-- attack has to be able to repair and rebuild itself.
ok, reason = survival.RouteVerdict(brainWith(9999, 0), engineer(), { 10, 0, 10 })
assert(ok and reason == "home",
    "home construction must never be refused, got " .. tostring(reason))

-- An unassessable route is native's business: it may still get there by
-- transport, and refusing would break island expansion that works today.
ok, reason = survival.RouteVerdict(brainWith(nil, 0), engineer(), { 500, 0, 500 })
assert(ok and reason == "unassessed",
    "an absent route must be left to native transport handling, got " .. tostring(reason))

-- Missing modules must never stop an army building.
ok, reason = survival.RouteVerdict({}, engineer(), { 500, 0, 500 })
assert(ok and reason == "unassessed", "an unwired brain must not be blocked")
assert(select(1, survival.RouteVerdict(nil, nil, nil)), "absent inputs must allow")

-- Where an engineer died is remembered, so the replacement is not posted to the
-- same spot: that is the loop this work exists to break.
local remembering = brainWith(0, 0)
survival.RememberLethalSite(remembering, { 500, 0, 500 }, "engineer-lost")
ok, reason = survival.RouteVerdict(remembering, engineer(), { 500, 0, 500 })
assert(not ok and reason == "recent-loss",
    "a site that just killed an engineer must be refused, got " .. tostring(reason))

-- Nearby counts as the same site; far away does not.
ok = survival.RouteVerdict(remembering, engineer(), { 520, 0, 500 })
assert(not ok, "the refusal must cover the area around the loss, not one point")
ok = survival.RouteVerdict(remembering, engineer(), { 800, 0, 800 })
assert(ok, "an unrelated destination must not inherit the refusal")

-- And it expires. A place dangerous once is not dangerous forever, and a
-- permanent exclusion would concede map control.
currentTick = constants.Policy.EngineerLethalSiteMemorySeconds * 10 + 1
ok, reason = survival.RouteVerdict(remembering, engineer(), { 500, 0, 500 })
assert(ok, "a stale loss must stop refusing the site, got " .. tostring(reason))
currentTick = 0

-- The commander is leashed on distance, not on what has been seen. It was
-- observed wandering alone to the centre of the map, which no threat reading
-- would have refused: nothing had arrived there yet.
local function commander()
    local unit = engineer("RULEUMT_Amphibious")
    unit.Categories = { COMMAND = true, MOBILE = true, ENGINEER = true }
    return unit
end
local function tank()
    local unit = engineer("RULEUMT_Amphibious")
    unit.Categories = { MOBILE = true, ENGINEER = true }
    return unit
end

-- A quiet distant destination is fine for an engineer and refused for the ACU.
ok, reason = survival.RouteVerdict(brainWith(0, 0), tank(), { 500, 0, 500 })
assert(ok, "an engineer may walk to quiet distant ground")
ok, reason = survival.RouteVerdict(brainWith(0, 0), commander(), { 500, 0, 500 })
assert(not ok and reason == "commander-leash",
    "the commander must be refused on distance alone, got " .. tostring(reason))

-- Inside the leash it works normally, including under real threat, because
-- that is its own base and defence has its own response.
ok, reason = survival.RouteVerdict(brainWith(0, 0), commander(), { 100, 0, 0 })
assert(ok, "the commander must still build inside its leash, got " .. tostring(reason))

print("Red Queen engineer survival contracts passed")
