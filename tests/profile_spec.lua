function ClassSimple(definition)
    return setmetatable(definition, {
        __call = function(class, ...)
            local instance = setmetatable({}, { __index = class })
            instance:__init(...)
            return instance
        end,
    })
end

local constants = { Policy = { LargeMapKilometers = 10, ExampleShared = 42 } }
local logged = {}
local logger = { Info = function(_, message) table.insert(logged, message) end }

function import(path)
    if path == "/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua" then return constants end
    if path == "/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua" then return logger end
    error("unexpected import: " .. tostring(path))
end

local module = setmetatable({}, { __index = _G })
setfenv(assert(loadfile("lua/AI/RedQueen/Profile.lua")), module)()
local Create = module.Create

local brain = {}
local function Select(world, context)
    return Create(brain, context or { AlliedSideSize = 1, EnemyCount = 1 }, world)
end

-- Terrain behaviours survive the independent size selection.
local naval = Select({ MapType = "Naval", MapKilometers = 5, WaterRatio = 0.93 })
assert(naval.Name == "Naval", "a water-dominant map must select the naval profile")
assert(naval:Flag("NavalFirstTier"), "the naval profile must produce first-tier warships")
assert(naval:Flag("ShoreTorpedo"), "the naval profile must answer ships ashore")

local mixed = Select({ MapType = "Mixed", MapKilometers = 20, WaterRatio = 0.30 })
assert(mixed.Name == "MixedLarge", "a large mixed map must select its own scale")
assert(mixed:Flag("TierReadinessObsolescence"), "large mixed maps must use completed-tier readiness")
assert(mixed:Flag("NavalFirstTier"), "a mixed map must still contest the water")

-- Exercise both sides of the size boundary for every terrain, including
-- Seton's Clutch. Selecting another brain must not alter the small profiles.
for _, terrain in ipairs({ "Land", "Naval", "Mixed" }) do
    for _, size in ipairs({ 5, 9, 10, 20, 40 }) do
        local profile = Select({ MapType = terrain, MapKilometers = size, WaterRatio = 0.60 })
        local large = size >= constants.Policy.LargeMapKilometers
        local expected = terrain == "Land" and (large and "LandLarge" or "LandSmall")
            or terrain .. (large and "Large" or "")
        assert(profile.Name == expected, "terrain and size must both select the profile")
        assert(profile.Scale == (large and "Large" or "Small"), "scale must be explicit")
        assert(profile:Flag("TierReadinessObsolescence") == large,
            "completed-tier readiness must follow scale on every terrain")
        assert(profile:Flag("NavalFirstTier") == (terrain ~= "Land"), "scale must preserve naval production")
        assert(profile:Flag("ShoreTorpedo") == (terrain ~= "Land"), "scale must preserve shore torpedoes")
    end
end
assert(not naval:Flag("TierReadinessObsolescence"), "large profiles must not mutate earlier small profiles")

-- Dry maps split on room to expand.
local large = Select({ MapType = "Land", MapKilometers = 10, WaterRatio = 0.0 })
assert(large.Name == "LandLarge", "a 10 km dry map must select the large-land profile")
assert(large:Flag("TierReadinessObsolescence"),
    "the large-land profile carries the readiness behaviour under measurement")
assert(large:Flag("TechEnergyLadder"), "the large-land profile builds power to reach Tech 3")

local small = Select({ MapType = "Land", MapKilometers = 5, WaterRatio = 0.0 })
assert(small.Name == "LandSmall", "a 5 km dry map must select the small-land profile")
assert(not small:Flag("TierReadinessObsolescence"),
    "a small dry map is decided by army quality, so readiness must stay off")
assert(not small:Flag("NavalFirstTier"), "a dry map must not build warships")
assert(small:Flag("TechEnergyLadder"),
    "readiness off with the ladder on is the only configuration measured to win "
    .. "Sentry Point; turning the ladder off as well was worse")

-- Unassigned behaviour is off. A flag nobody put in a profile must not run.
assert(not small:Flag("SomeBehaviourNobodyAssigned"),
    "an unknown behaviour must default to off, never on")

-- Values fall back to shared policy, and a profile never writes to it.
assert(small:Value("ExampleShared") == 42, "unoverridden values must come from shared policy")
assert(constants.Policy.ExampleShared == 42,
    "selecting a profile must not mutate the shared policy table")

-- The choice is logged with the inputs that produced it, or it cannot be
-- checked against a match afterwards.
local last = logged[table.getn(logged)]
assert(string.find(last, "profile selected=LandSmall", 1, true), "the choice must be logged")
assert(string.find(last, "size=5km", 1, true), "the log must carry the map size")
assert(string.find(last, "water=0.00", 1, true), "the log must carry the water ratio")
assert(string.find(last, "enemies=1", 1, true), "the log must carry the opponent count")

print("Red Queen profile contracts passed")
