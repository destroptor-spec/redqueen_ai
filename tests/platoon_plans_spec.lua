local logged = {}
function import(path)
    if path == "/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua" then
        return { Info = function(_, message) table.insert(logged, message) end }
    elseif path == "/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua" then
        return { Policy = { PlatoonDirectionSeconds = 15 } }
    end
    error("unexpected import: " .. tostring(path))
end

local plans = setmetatable({}, { __index = _G })
setfenv(assert(loadfile("lua/AI/RedQueen/PlatoonPlans.lua")), plans)()

-- Where a directed platoon is sent.
--
-- Read off the brain rather than passed in, because a platoon outlives the pass
-- that formed it and the objective changes underneath it. Measured: Red Queen's
-- own dispatch ordered units two or three times in a whole match while native's
-- platoon AI did the fighting, so the objective never reached the army.
local brain = { RedQueenModules = { Strategy = {} } }
assert(not plans.DirectionTarget(brain), "no objective is no destination")
assert(not plans.DirectionTarget({}), "a brain without Red Queen modules must not crash")
assert(not plans.DirectionTarget(nil), "nor a missing brain")

brain.RedQueenModules.Strategy.PrimaryObjective = { Type = "Raid", Position = { 900, 0, 800 } }
local position, kind = plans.DirectionTarget(brain)
assert(position and position[1] == 900 and kind == "Raid",
    "an offensive primary objective is the destination")

-- The secondary slot is not a destination for a formed attack platoon: sending
-- it home is the recall this design exists to stop.
brain.RedQueenModules.Strategy.SecondaryObjective = { Type = "Defend", Position = { 0, 0, 0 } }
position = plans.DirectionTarget(brain)
assert(position[1] == 900, "a defence must not redirect a formed attack platoon")

for _, idle in ipairs({ "Stage", "Recover" }) do
    brain.RedQueenModules.Strategy.PrimaryObjective = { Type = idle, Position = { 5, 0, 5 } }
    assert(not plans.DirectionTarget(brain),
        idle .. " is not somewhere to send a platoon")
end

brain.RedQueenModules.Strategy.PrimaryObjective = { Type = "Raid" }
assert(not plans.DirectionTarget(brain), "an objective without a position is no destination")

-- Reachable, or it is not a destination.
--
-- The old dispatcher gated every order on CanPath and the first version of this
-- plan did not, so on a water map it took the land units native was using and
-- aimed them across an ocean. Three naval cells flipped to defeat on a
-- land-only builder.
brain.RedQueenModules.Strategy.PrimaryObjective = { Type = "Raid", Position = { 900, 0, 800 } }
local reachable = true
brain.RedQueenModules.World = {
    StartPosition = { 0, 0, 0 },
    CanPath = function(_, layer, origin, destination)
        assert(layer and origin and destination, "the route test needs all three")
        return reachable
    end,
}
assert(plans.DirectionTarget(brain, { 0, 0, 0 }, "Land"),
    "a reachable objective is still a destination")
reachable = false
assert(not plans.DirectionTarget(brain, { 0, 0, 0 }, "Land"),
    "an objective the platoon cannot walk to is not a destination")
assert(plans.DirectionTarget(brain),
    "without a platoon position there is no route to test, and the objective stands")
brain.RedQueenModules.World = nil

-- A target that drifts slightly is the same target. Re-issuing orders every
-- cycle would clear commands mid-fight, which is what a formation must not do.
assert(plans.DirectionKey({ 900, 0, 800 }) == plans.DirectionKey({ 903, 0, 802 }),
    "a target drifting a few metres must not re-aim the platoon")
assert(plans.DirectionKey({ 900, 0, 800 }) ~= plans.DirectionKey({ 960, 0, 800 }),
    "a genuinely different target must re-aim it")
assert(not plans.DirectionKey(nil), "no position is no key")

print("Red Queen platoon plan contracts passed")
