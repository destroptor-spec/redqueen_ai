-- Whether an engineer should be sent somewhere at all.
--
-- FAF's own `EngineerMoveWithSafePath` asks for a threat-constrained path and
-- then, when there is none, returns true anyway:
--
--     if result then
--         local path = NavUtils.PathToWithThreatThreshold(...)
--         if path then ... end
--         -- If there wasn't a *safe* path (but dest was pathable), then the
--         -- last move would have been to go there directly so don't bother
--         return true
--     end
--
-- The caller then issues the build order and the engineer walks into whatever
-- is there. Observed directly in a match as engineers travelling into the enemy
-- base; reproduced against the shipped native source in
-- /tmp/rq-engineer-observations/reproduce.lua. Each death then raises the
-- engineer target by `EngineerLossReplacementFactor`, which raises engineer
-- build priority above every combat builder at a shortfall of five -- so the
-- losses fund their own replacements and crowd out the early army. See
-- docs/engineer-survival-plan.md.
--
-- This module answers the question the native code declines to act on. It never
-- decides pathability or transports: native handles those, and refusing on an
-- absent route would break island expansion that transports serve perfectly
-- well. It refuses on *danger* only.
local Constants = import("/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua")

local function DistanceSquared(a, b)
    if not a or not b then
        return nil
    end
    local dx = (a[1] or 0) - (b[1] or 0)
    local dz = (a[3] or 0) - (b[3] or 0)
    return dx * dx + dz * dz
end

-- Hold native assignments until the return-home order reaches safety. No
-- timer may release an engineer halfway through a long retreat.
function IsRetreating(unit)
    local home = unit and unit.RedQueenRetreatPosition
    if not home then return false end
    local position = unit.GetPosition and unit:GetPosition()
    local distance = DistanceSquared(position, home)
    if unit.Dead or (distance and distance <= Constants.Policy.EngineerSurvivalHomeRadius
        * Constants.Policy.EngineerSurvivalHomeRadius)
    then
        unit.RedQueenRetreatPosition = nil
        return false
    end
    return true
end

-- The engine's five navigation layers, keyed by the blueprint motion type.
--
-- Canonical here so one table serves every consumer. Native engineer travel
-- hard-codes `'Amphibious'`, which is wrong for every Aeon and Seraphim
-- engineer: those are `RULEUMT_Hover`, and hover crosses deep water while
-- amphibious is blocked past `MaxWaterDepthAmphibious`. A route judged on the
-- wrong graph is a judgement about a journey the unit is not making.
MotionLayers = {
    RULEUMT_Hover = "Hover",
    RULEUMT_Amphibious = "Amphibious",
    RULEUMT_AmphibiousFloating = "Amphibious",
    RULEUMT_Air = "Air",
    RULEUMT_Water = "Water",
    RULEUMT_SurfacingSub = "Water",
}

function TravelLayer(unit)
    if not unit or not unit.GetBlueprint then
        return "Land"
    end
    local blueprint = unit:GetBlueprint() or {}
    local physics = blueprint.Physics or {}
    return MotionLayers[physics.MotionType] or "Land"
end

-- Where engineers have died, so the next one is not posted to the same spot.
--
-- Without this the replacement loop is self-sustaining: the site that killed an
-- engineer is still the nearest unclaimed resource, so the replacement is sent
-- to it, and the observed threat that justified refusing may have moved on and
-- come back. Entries expire, so a place that was dangerous once does not become
-- permanently forbidden.
-- Every refusal and every remembered site, counted by reason.
--
-- The guard fired in all 147 recorded match logs and the only trace either
-- reason left was a single rate-limited line saying it had happened at least
-- once. A refusal is an unclaimed mass point, so the count is an economic
-- figure, not a debug one: without it a matrix cannot tell a guard that saves
-- engineers from one that caps expansion. Reported as `engsurvival=` in the
-- periodic state line.
function CountEvent(brain, field, reason)
    if not brain or not reason then
        return
    end
    brain.RedQueenEngineerSurvival = brain.RedQueenEngineerSurvival or {}
    local counts = brain.RedQueenEngineerSurvival
    counts[field] = counts[field] or {}
    counts[field][reason] = (counts[field][reason] or 0) + 1
end

local function Count(brain, field, reason)
    local counts = brain and brain.RedQueenEngineerSurvival
    local bucket = counts and counts[field]
    return (bucket and bucket[reason]) or 0
end

-- Exported so the native hook rate-limits its log line off the same counter it
-- reports, rather than keeping a second private tally of the same events.
function EventCount(brain, field, reason)
    return Count(brain, field, reason)
end

-- Sites still inside their memory window, pruned as they are counted. This is
-- the live exclusion the expansion planner is working against; the cumulative
-- totals beside it cannot show whether it is growing or draining.
function LiveSiteCount(brain)
    local sites = brain and brain.RedQueenLethalSites
    if not sites then
        return 0
    end
    local cutoff = GetGameTick()
        - Constants.Policy.EngineerLethalSiteMemorySeconds * 10
    for index = table.getn(sites), 1, -1 do
        if sites[index].Tick < cutoff then
            table.remove(sites, index)
        end
    end
    return table.getn(sites)
end

function Summary(brain)
    return {
        RefusedUnsafe = Count(brain, "Refused", "route-unsafe"),
        RefusedRecentLoss = Count(brain, "Refused", "recent-loss"),
        RefusedLeash = Count(brain, "Refused", "commander-leash"),
        SitesLost = Count(brain, "Sites", "engineer-lost"),
        SitesWithdrawn = Count(brain, "Sites", "engineer-withdrawn"),
        LiveSites = LiveSiteCount(brain),
    }
end

function RememberLethalSite(brain, position, reason)
    if not brain or not position then
        return
    end
    brain.RedQueenLethalSites = brain.RedQueenLethalSites or {}
    local recorded = reason or "engineer-lost"
    table.insert(brain.RedQueenLethalSites, {
        Position = { position[1], position[2], position[3] },
        Reason = recorded,
        Tick = GetGameTick(),
    })
    CountEvent(brain, "Sites", recorded)
end

function RecentlyLethal(brain, position)
    local sites = brain and brain.RedQueenLethalSites
    if not sites or not position then
        return nil
    end
    local cutoff = GetGameTick()
        - Constants.Policy.EngineerLethalSiteMemorySeconds * 10
    local radiusSquared = Constants.Policy.EngineerLethalSiteRadius
        * Constants.Policy.EngineerLethalSiteRadius
    -- Reverse order so expiry can prune in place while scanning.
    for index = table.getn(sites), 1, -1 do
        local site = sites[index]
        if site.Tick < cutoff then
            table.remove(sites, index)
        else
            local distance = DistanceSquared(position, site.Position)
            if distance and distance <= radiusSquared then
                return site.Reason
            end
        end
    end
    return nil
end

-- Should this engineer be sent to this destination?
--
-- Returns true to allow, or false with a reason. Allows whenever it cannot
-- judge: an absent module, an unassessable route or a missing policy value must
-- never stop an army from building at home.
function RouteVerdict(brain, unit, destination)
    if not brain or not unit or not destination then
        return true, "unassessed"
    end
    local modules = brain.RedQueenModules
    local world = modules and modules.World
    local intel = modules and modules.Intel
    local strategy = modules and modules.Strategy
    if not world or not intel or not world.GetObservedRouteThreat then
        return true, "unassessed"
    end
    if not unit.GetPosition then
        return true, "unassessed"
    end
    local position = unit:GetPosition()

    -- Home construction is never refused. An engineer building inside its own
    -- base is not the behaviour under repair, and a defence alert at home would
    -- otherwise stop the army repairing itself exactly when it must.
    local home = world.StartPosition
    local homeDistance = DistanceSquared(destination, home)
    if homeDistance
        and homeDistance <= Constants.Policy.EngineerSurvivalHomeRadius
            * Constants.Policy.EngineerSurvivalHomeRadius
    then
        return true, "home"
    end

    -- The commander is leashed on distance, not on what has been seen. Its
    -- loss ends the match in Assassination and cripples any other victory
    -- condition, and the ground it was observed wandering to -- the centre of
    -- the map, alone -- read as harmless right up until something arrived.
    if EntityCategoryContains
        and categories
        and EntityCategoryContains(categories.COMMAND, unit)
    then
        local leash = Constants.Policy.CommanderLeashRadius
        if homeDistance and leash and homeDistance > leash * leash then
            CountEvent(brain, "Refused", "commander-leash")
            return false, "commander-leash"
        end
    end

    local lethal = RecentlyLethal(brain, destination)
    if lethal then
        CountEvent(brain, "Refused", "recent-loss")
        return false, "recent-loss"
    end

    local layer = TravelLayer(unit)
    local threat = world:GetObservedRouteThreat(
        position,
        destination,
        intel,
        Constants.Policy.ForwardBaseSiteRadius,
        layer
    )
    -- No assessable route on this unit's own graph is native's business, not
    -- ours: it may still get there by transport.
    if threat == nil then
        return true, "unassessed"
    end

    local escort = 0
    if strategy and strategy.GetOwnThreatNear then
        escort = strategy:GetOwnThreatNear(
            destination,
            Constants.Policy.ForwardBaseSiteRadius
        ) or 0
    end
    -- The floor is what makes this usable by a lone engineer. Scaling purely
    -- with nearby friendly strength gives a limit of zero for an unescorted
    -- walk, which would refuse a destination because a scout was seen near it.
    -- Measured scale: a route threat of 0.6 was harmless, while 70.5 killed the
    -- engineer that walked it. The floor is a first estimate between those.
    local limit = math.max(
        Constants.Policy.EngineerSurvivalThreatFloor,
        escort * Constants.Policy.ForwardBaseSafetyRatio
    )
    if threat > limit then
        CountEvent(brain, "Refused", "route-unsafe")
        return false, "route-unsafe"
    end
    return true, "safe"
end
