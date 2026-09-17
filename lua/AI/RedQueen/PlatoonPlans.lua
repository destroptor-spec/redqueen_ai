local Logger = import("/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua")
local Constants = import("/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua")
local Narrator = import("/mods/TheRedQueen/lua/AI/RedQueen/Narrator.lua")

-- Where Red Queen wants this platoon to go.
--
-- The strategy layer already computes intent -- a primary slot holding a Raid
-- or Pressure at a position -- and until now discarded it. Measured across
-- twelve cells, Red Queen's own dispatch ordered units on two or three passes
-- in an entire match while FAF's platoon AI did the fighting, so the objective
-- system was decorative.
--
-- Read off the brain rather than passed in, because a platoon outlives the pass
-- that formed it and the objective will change underneath it.
function DirectionTarget(brain, origin, layer)
    local modules = brain and brain.RedQueenModules
    local strategy = modules and modules.Strategy
    if not strategy then
        return nil
    end
    -- The primary slot only. A defence is answered by the units the secondary
    -- claims, and sending a formed attack platoon home is the recall this whole
    -- design exists to stop.
    local objective = strategy.PrimaryObjective
    if not objective or not objective.Position then
        return nil
    end
    if objective.Type == "Stage" or objective.Type == "Recover" then
        return nil
    end
    -- Reachable, or it is not a destination.
    --
    -- The old dispatcher gated every order on CanPath and this plan did not,
    -- so on a water map it took the land units native was using sensibly and
    -- aimed them at an objective across an ocean. Three naval cells flipped to
    -- defeat on a land-only builder, which is how that showed up at all.
    local world = modules.World
    if origin and world and world.CanPath
        and not world:CanPath(layer or "Land", origin, objective.Position)
    then
        return nil
    end
    return objective.Position, objective.Type
end

-- A position's identity, so a platoon re-aims when the objective moves and is
-- left alone when it has not. Rounded: a target drifting by a metre is the same
-- target, and re-issuing orders every cycle would clear commands mid-fight.
function DirectionKey(position)
    if not position then
        return nil
    end
    return string.format("%d:%d",
        math.floor(position[1] / 8), math.floor(position[3] / 8))
end

-- Direct a native-formed platoon at that objective.
--
-- Native forms this platoon and supplies every movement helper used here;
-- ForkAIThread passes the platoon as `self`, so a plan in a mod file has the
-- whole Platoon interface. This says only where to go, which is the one thing
-- native has no opinion about.
function ObjectiveAttack(self)
    local brain = self:GetBrain()
    self:Stop()
    if not self:GatherUnits() then
        return
    end

    brain.RedQueenDirectedPlatoons = (brain.RedQueenDirectedPlatoons or 0) + 1
    local pursuing = nil
    while brain:PlatoonExists(self) do
        local position, kind = DirectionTarget(brain, self:GetPlatoonPosition(), "Land")
        local key = DirectionKey(position)
        if key and key ~= pursuing then
            pursuing = key
            self:Stop()
            self:AggressiveMoveToLocation(position)
            brain.RedQueenPlatoonAims = (brain.RedQueenPlatoonAims or 0) + 1
            Narrator.Announce(brain, "platoon", string.format(
                "Sending %d units to %s",
                table.getn(self:GetPlatoonUnits()), tostring(kind)))
            Logger.Info(brain, string.format(
                "platoon directed objective=%s position=%.0f,%.0f units=%d",
                tostring(kind), position[1], position[3],
                table.getn(self:GetPlatoonUnits())))
        end
        WaitSeconds(Constants.Policy.PlatoonDirectionSeconds)
    end
end
