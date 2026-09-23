-- The engine's resource threat filter, measured without being changed.
--
-- `AIExecuteBuildStructure` places extractors with `optIgnoreThreatOver = 5` and
-- every other structure with the filter open. The probe asks the engine both
-- ways and returns the gated answer, so these contracts pin the two properties
-- that make the measurement worth anything: it must not decide with the open
-- result, and it must not touch a brain that is not Red Queen's -- the function
-- is global to every AI in the match.
local calls = {}
local environment = setmetatable({}, { __index = _G })

-- The native pieces the hook captures, as its defining file provides them.
environment.IsResource = function(buildingType)
    return buildingType == "T1Resource" or buildingType == "T2Resource"
end
environment.AIExecuteBuildStructure = function(aiBrain, builder, buildingType)
    table.insert(calls, { Brain = aiBrain, Type = buildingType })
    -- Native's own resource placement, which is what installs the probe's work.
    if environment.IsResource(buildingType) then
        return aiBrain:FindPlaceToBuild(buildingType, "ueb1103", {}, false, builder,
            "Enemy", 10, 10, 5)
    end
    return aiBrain:FindPlaceToBuild(buildingType, "ueb0101", {}, false, builder,
        nil, 10, 10)
end

setfenv(assert(loadfile("hook/lua/AI/aibuildstructures.lua")), environment)()

-- A brain whose deposits are all refused at the shipped limit and all offered
-- with the filter open: the exact case the probe exists to detect.
local function Brain(personality, offeredAtLimit)
    return {
        RedQueenLobbyPersonality = personality,
        FindPlaceToBuild = function(self, _, _, _, _, _, _, _, _, threatLimit)
            if threatLimit and threatLimit > 0 then
                return offeredAtLimit and { 10, 10, 0 } or nil
            end
            return { 10, 10, 0 }
        end,
    }
end

local brain = Brain(true, false)
for _ = 1, 3 do
    environment.AIExecuteBuildStructure(brain, {}, "T1Resource")
end
local counts = brain.RedQueenPlacement
assert(counts, "a Red Queen brain placing a resource must gain a placement probe")
assert(counts.Attempts == 3, "every resource placement must be counted, got "
    .. tostring(counts.Attempts))
assert(counts.Gated == 0, "none were offered at the shipped limit, got "
    .. tostring(counts.Gated))
assert(counts.Open == 3, "all three would be offered with the filter open, got "
    .. tostring(counts.Open))

-- The decision must still be native's gated one. Returning the counterfactual
-- would silently change behaviour and make the run incomparable to the payload
-- it is measured against.
assert(environment.AIExecuteBuildStructure(brain, {}, "T1Resource") == nil,
    "the probe must return the gated result, never the open one")

-- A non-resource structure carries no threat limit and must not be counted.
local before = counts.Attempts
environment.AIExecuteBuildStructure(brain, {}, "T1LandFactory")
assert(counts.Attempts == before,
    "a factory placement must not be counted as a deposit")

-- Every other AI in the match must be untouched.
local opponent = Brain(nil, false)
environment.AIExecuteBuildStructure(opponent, {}, "T1Resource")
assert(opponent.RedQueenPlacement == nil,
    "the probe must never be installed on a brain that is not Red Queen's")
assert(rawget(opponent, "RedQueenPlacementProbe") == nil,
    "and must leave no marker on it either")

-- Installing twice must not replace the probe with a wrapper around itself.
local wrapped = brain.FindPlaceToBuild
environment.AIExecuteBuildStructure(brain, {}, "T1Resource")
assert(brain.FindPlaceToBuild == wrapped,
    "the probe must install exactly once per brain")

print("Red Queen placement probe contracts passed")
