local MarkerUtilities = import("/lua/sim/MarkerUtilities.lua")
local NavUtils = import("/lua/sim/NavUtils.lua")
local Constants = import("/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua")
local Logger = import("/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua")

local function DistanceSquared(a, b)
    local dx = a[1] - b[1]
    local dz = a[3] - b[3]
    return dx * dx + dz * dz
end

local function MapSize()
    local size = ScenarioInfo.size or { 512, 512 }
    return size[1], size[2]
end

local function ClassifyWater(width, height)
    local water = 0
    local samples = 0
    local divisions = 12

    for xStep = 1, divisions do
        for zStep = 1, divisions do
            local x = width * (xStep - 0.5) / divisions
            local z = height * (zStep - 0.5) / divisions
            if GetSurfaceHeight(x, z) - GetTerrainHeight(x, z) > 0.5 then
                water = water + 1
            end
            samples = samples + 1
        end
    end

    if samples == 0 then
        return 0
    end
    return water / samples
end

local function ClusterMassMarkers(markers, count, clusterRadius)
    local clusters = {}
    local radiusSquared = clusterRadius * clusterRadius

    for markerIndex = 1, count do
        local marker = markers[markerIndex]
        local position = marker.Position or marker.position
        if position then
            local selected = nil
            for _, cluster in pairs(clusters) do
                if DistanceSquared(position, cluster.Position) <= radiusSquared then
                    selected = cluster
                    break
                end
            end

            if selected then
                selected.Count = selected.Count + 1
                selected.Position[1] = selected.Position[1] + (position[1] - selected.Position[1]) / selected.Count
                selected.Position[2] = GetSurfaceHeight(selected.Position[1], selected.Position[3])
                selected.Position[3] = selected.Position[3] + (position[3] - selected.Position[3]) / selected.Count
                table.insert(selected.Markers, marker)
            else
                table.insert(clusters, {
                    Id = table.getn(clusters) + 1,
                    Count = 1,
                    Position = { position[1], position[2] or GetSurfaceHeight(position[1], position[3]), position[3] },
                    Markers = { marker },
                })
            end
        end
    end

    return clusters
end

---@class RedQueenWorldModel
-- What a player sitting in the lobby would know about where everyone spawned.
--
-- `TeamSpawn` is the host's choice. `fixed` puts everyone on a slot-determined
-- start and the `*_reveal` variants randomise but show the result, so in both
-- cases every player can see every start position and Red Queen may read them
-- directly. Plain `random`, `balanced` and `balanced_flex` do not: a player
-- knows the map's start locations but not who is standing on which, and
-- neither should we.
--
-- Absent means fixed. That is FAF's default and what a command-line skirmish
-- gets, so reading nothing must not silently blind the brain.
local RevealedSpawns = {
    fixed = true,
    random_reveal = true,
    balanced_reveal = true,
    balanced_reveal_mirrored = true,
    balanced_flex_reveal = true,
}

-- A start position's identity, stable across rebuilds.
local function StartKey(position)
    return string.format("%d:%d", position[1], position[3])
end

local function SpawnsRevealed()
    local options = ScenarioInfo and ScenarioInfo.Options
    local spawn = options and options.TeamSpawn
    if spawn == nil then
        return true
    end
    return RevealedSpawns[spawn] or false
end

WorldModel = ClassSimple {
    __init = function(self, brain, context)
        self.Brain = brain
        self.Context = context
        self.Width, self.Height = MapSize()
        self.MapKilometers = math.floor((self.Width / 51.2) + 0.5)
        self.WaterRatio = 0
        self.MapType = "Land"
        self.MassClusters = {}
        self.EnemyStarts = {}
        self.NavalApproaches = {}
        self.ForwardBaseCandidates = {}

        local startX, startZ = brain:GetArmyStartPos()
        self.StartPosition = { startX, GetSurfaceHeight(startX, startZ), startZ }
        self:Rebuild()
    end,

    Rebuild = function(self)
        self.WaterRatio = ClassifyWater(self.Width, self.Height)
        if self.WaterRatio >= 0.55 then
            self.MapType = "Naval"
        elseif self.WaterRatio >= 0.20 then
            self.MapType = "Mixed"
        else
            self.MapType = "Land"
        end

        local markers, count = MarkerUtilities.GetMarkersByType("Mass")
        local clusterRadius = math.max(40, math.min(120, self.Width / 10))
        self.MassClusters = ClusterMassMarkers(markers, count, clusterRadius)
        -- How many mass points the map has at all, kept because claiming an
        -- unclaimed one is the best economic action in the game: 36 mass for
        -- +2/s pays back in 18 seconds, against 225 for a Tech 2 upgrade. What
        -- an army holds against what exists is therefore the measure that says
        -- whether expansion is failing for lack of trying or lack of holding,
        -- and it was not previously recorded anywhere.
        self.MassPointCount = count

        -- Water destinations a fleet can actually be sent to.
        --
        -- An enemy start is where a commander spawns, i.e. dry land, so
        -- CanPath("Water", ...) to it fails by definition and the offensive
        -- layer used to fall through to Air. FAF generates "Naval Area" markers
        -- around every spawn and expansion from
        -- NavUtils.GetPositionsInRadius('Water', ...), keeping only positions
        -- that resolve to a real water label -- exactly the "water next to the
        -- enemy base" a fleet needs. AdaptiveBrain.OnBeginSession already calls
        -- GenerateNavalAreaMarkers before our first Rebuild, so they only need
        -- reading. Sorted by coordinate because the generator names them with
        -- an unpadded %00d, under which "Naval Area 9" sorts after "10".
        self.NavalApproaches = {}
        local navalMarkers, navalCount = MarkerUtilities.GetMarkersByType("Naval Area")
        for index = 1, navalCount do
            local marker = navalMarkers[index]
            local position = marker and (marker.Position or marker.position)
            if position then
                table.insert(self.NavalApproaches, {
                    Name = tostring(marker.Name or marker.name or "NavalArea" .. tostring(index)),
                    Position = { position[1], position[2] or 0, position[3] },
                })
            end
        end
        table.sort(self.NavalApproaches, function(a, b)
            if a.Position[1] ~= b.Position[1] then return a.Position[1] < b.Position[1] end
            if a.Position[3] ~= b.Position[3] then return a.Position[3] < b.Position[3] end
            return a.Name < b.Name
        end)

        self.ForwardBaseCandidates = {}
        for _, markerType in pairs({ "Defensive Point", "Expansion Area" }) do
            local candidates, candidateCount = MarkerUtilities.GetMarkersByType(markerType)
            for index = 1, candidateCount do
                local marker = candidates[index]
                local position = marker.Position or marker.position
                if position
                    and GetSurfaceHeight(position[1], position[3])
                        - GetTerrainHeight(position[1], position[3]) <= 0.5
                then
                    table.insert(self.ForwardBaseCandidates, {
                        Name = tostring(marker.Name or marker.name or markerType .. tostring(index)),
                        Type = markerType,
                        Position = { position[1], position[2] or 0, position[3] },
                        Value = markerType == "Defensive Point" and 120 or 100,
                    })
                end
            end
        end
        for _, cluster in pairs(self.MassClusters) do
            table.insert(self.ForwardBaseCandidates, {
                Name = "MassCluster" .. tostring(cluster.Id),
                Type = "Mass Cluster",
                Position = cluster.Position,
                Value = 80 + cluster.Count * 20,
            })
        end
        table.sort(self.ForwardBaseCandidates, function(a, b)
            return a.Name < b.Name
        end)

        -- Where the enemy is, in two tiers.
        --
        -- The positions are always kept: they are where an army can spawn, and
        -- something has to be scouted. What the lobby controls is whether we
        -- also know who is standing on each one. `Known` is that distinction,
        -- and it is what separates a place worth looking at from a place worth
        -- attacking.
        --
        -- Resolved starts survive every rebuild. Every intel record decays at
        -- IntelLifetimeSeconds; a base does not stop being there because
        -- nothing has looked at it lately.
        self.SpawnsRevealed = SpawnsRevealed()
        self.ResolvedStarts = self.ResolvedStarts or {}
        self.EnemyStarts = {}

        local candidates = {}
        for _, armyIndex in pairs(self.Context.EnemyArmies) do
            local enemyBrain = ArmyBrains[armyIndex]
            if enemyBrain then
                local x, z = enemyBrain:GetArmyStartPos()
                table.insert(candidates, {
                    Army = armyIndex,
                    Position = { x, GetSurfaceHeight(x, z), z },
                })
            end
        end

        if self.SpawnsRevealed then
            for _, candidate in ipairs(candidates) do
                table.insert(self.EnemyStarts, {
                    Army = candidate.Army,
                    Position = candidate.Position,
                    Known = true,
                })
            end
        else
            -- Which enemy holds which start is hidden, so the attribution is
            -- dropped. Sorting by distance from home is the useful scouting
            -- order and also destroys the positional correspondence a caller
            -- could otherwise read the army index back out of.
            local home = self.StartPosition
            table.sort(candidates, function(a, b)
                return DistanceSquared(home, a.Position) < DistanceSquared(home, b.Position)
            end)
            for _, candidate in ipairs(candidates) do
                table.insert(self.EnemyStarts, {
                    Position = candidate.Position,
                    Known = self.ResolvedStarts[StartKey(candidate.Position)] or false,
                })
            end
        end

        Logger.Info(self.Brain, string.format(
            "map type=%s size=%dkm water=%.2f massClusters=%d spawns=%s starts=%d",
            self.MapType,
            self.MapKilometers,
            self.WaterRatio,
            table.getn(self.MassClusters),
            self.SpawnsRevealed and "revealed" or "hidden",
            table.getn(self.EnemyStarts)
        ))
    end,

    Update = function(self)
        -- Static terrain and scenario markers do not need a full rebuild. This
        -- cadence exists for future dynamic map metadata and claim scoring.
        self.LastUpdateTick = GetGameTick()
    end,

    CanPath = function(self, layer, origin, destination)
        if layer == "Air" then
            return true
        end
        local ok = NavUtils.CanPathTo(layer, origin, destination)
        return ok == true
    end,

    -- Water nearest `position`, without any route test. Used to put both ends
    -- of a naval question onto the water layer before asking it.
    NearestNavalApproach = function(self, position)
        if not position then
            return nil
        end
        local best, bestDistance = nil, nil
        for _, candidate in ipairs(self.NavalApproaches or {}) do
            local distance = DistanceSquared(position, candidate.Position)
            if not bestDistance or distance < bestDistance then
                best = candidate.Position
                bestDistance = distance
            end
        end
        return best
    end,

    -- Nearest water position to `target` that our fleet can actually reach from
    -- `origin`. The destination must be on the target's side of the midpoint
    -- and closer to it than our source water. Reachability within our home basin
    -- alone is not an enemy approach; return nil so callers can change layers.
    --
    -- Both ends must be resolved onto water first. NavUtils.CanPathTo reports
    -- OriginUnpathable when the *origin* cell has no label on the layer, so
    -- asking it for a water route out of an army start -- dry land, where the
    -- commander spawns -- fails exactly as asking for a water route *to* one
    -- does. Testing only the destination leaves the same bug on the other end,
    -- which is what kept every offensive on SCMP_037 falling through to Air.
    GetNavalApproach = function(self, origin, target)
        if not origin or not target then
            return nil
        end
        local source = self:NearestNavalApproach(origin)
        if not source then
            return nil
        end
        local best, bestDistance = nil, nil
        local sourceDistance = DistanceSquared(target, source)
        for _, candidate in ipairs(self.NavalApproaches or {}) do
            local distance = DistanceSquared(target, candidate.Position)
            if distance < sourceDistance
                and distance < DistanceSquared(origin, candidate.Position)
                and (not bestDistance or distance < bestDistance)
            then
                if self:CanPath("Water", source, candidate.Position) then
                    best = candidate.Position
                    bestDistance = distance
                end
            end
        end
        return best
    end,

    -- Only bases we are entitled to know about. With revealed spawns that is
    -- all of them from the first tick; with hidden spawns it is the ones
    -- something of ours has actually seen.
    -- Learn which start the enemy is actually on when the lobby did not say.
    --
    -- A structure is the evidence: mobile units travel, buildings do not. The
    -- resolution is recorded permanently and separately from EnemyStarts,
    -- because the observation that produced it will decay and the base will
    -- not. With revealed spawns this does nothing -- everything is known
    -- already.
    ResolveEnemyBases = function(self, intel)
        if self.SpawnsRevealed or not intel or not intel.Observations then
            return 0
        end
        local radius = Constants.Policy.EnemyBaseDiscoveryRadius
        local resolved = 0
        for _, observation in pairs(intel.Observations) do
            local role = observation.Role
            if role and role.Structure and observation.Position then
                for _, enemy in ipairs(self.EnemyStarts) do
                    if not enemy.Known
                        and DistanceSquared(enemy.Position, observation.Position) <= radius * radius
                    then
                        enemy.Known = true
                        self.ResolvedStarts[StartKey(enemy.Position)] = true
                        resolved = resolved + 1
                        Logger.Info(self.Brain, string.format(
                            "enemy base resolved position=%.0f,%.0f",
                            enemy.Position[1], enemy.Position[3]))
                    end
                end
            end
        end
        return resolved
    end,

    GetClosestEnemyStart = function(self, origin, layer)
        local best = nil
        local bestDistance = nil
        for _, enemy in pairs(self.EnemyStarts) do
            if enemy.Known ~= false then
            local distance = DistanceSquared(origin, enemy.Position)
            if (not bestDistance or distance < bestDistance) and self:CanPath(layer or "Land", origin, enemy.Position) then
                best = enemy.Position
                bestDistance = distance
            end
            end
        end
        return best
    end,

    GetMaximumForwardBases = function(self)
        return math.max(1, math.min(
            Constants and Constants.Policy and Constants.Policy.MaximumForwardBases or 3,
            math.floor(self.MapKilometers
                / (Constants and Constants.Policy and Constants.Policy.ForwardBaseMapKilometersPerBase or 10))
        ))
    end,

    -- Observed threat along a route, and how much of that route the army can
    -- actually see. Returns `threat, coverage` where coverage is 0 for a route
    -- nobody has looked at and 1 for one fully in view.
    --
    -- Both halves are needed because they are not the same question. Threat is
    -- summed from observations, so an unscouted route reports 0 -- and a caller
    -- reading that as "clear" is most confident precisely where it knows least.
    -- Coverage is what lets the caller tell the two apart.
    --
    -- `layer` is the graph the traveller actually moves on. Every engineer in
    -- the game crosses water -- UEF and Cybran float, Aeon and Seraphim hover --
    -- so asking about "Land" describes none of them.
    GetObservedRouteThreat = function(self, origin, destination, intel, radius, layer)
        layer = layer or "Land"
        local path = NavUtils.PathTo and NavUtils.PathTo(layer, origin, destination)
        if not path then
            if not self:CanPath(layer, origin, destination) then
                return nil
            end
            path = { origin, destination }
        end
        -- NavUtils paths need not include the engineer's starting position.
        -- Leaving a threatened source must be checked as well as arriving.
        local maximum = intel:GetThreatNear(origin, radius)
        local samples = { origin, destination }
        for _, position in pairs(path) do
            maximum = math.max(maximum, intel:GetThreatNear(position, radius))
            table.insert(samples, position)
        end
        maximum = math.max(maximum, intel:GetThreatNear(destination, radius))

        -- Coverage is the mean over sampled points, so one watched corner of a
        -- long blind route cannot vouch for the rest of it.
        local coverage = 0
        local counted = 0
        local full = Constants.Policy.RouteCoverageConfidenceForFull
        for _, position in pairs(samples) do
            local known = intel.GetCoverageNear
                and intel:GetCoverageNear(position, radius)
                or nil
            if known == nil then
                -- An intel source that cannot report coverage must not be
                -- treated as blind, or every route would carry presumed risk.
                coverage = counted + 1
                counted = counted + 1
            else
                coverage = coverage + math.min(1, known / full)
                counted = counted + 1
            end
        end
        return maximum, counted > 0 and coverage / counted or 0
    end,

    SelectForwardBaseSite = function(self, origin, objective, intel, claimed, escortThreat, rebuildable, layer)
        if not objective then
            return nil
        end
        layer = layer or "Land"
        local best = nil
        local bestScore = nil
        local minimumDistance = Constants.Policy.ForwardBaseMinimumDistance
        local safetyLimit = math.max(0, escortThreat * Constants.Policy.ForwardBaseSafetyRatio)

        for _, candidate in pairs(self.ForwardBaseCandidates) do
            if not claimed[candidate.Name] then
                local ownDistance = math.sqrt(DistanceSquared(origin, candidate.Position))
                local objectiveDistance = math.sqrt(DistanceSquared(objective, candidate.Position))
                local rebuilding = rebuildable and rebuildable[candidate.Name]
                if (rebuilding or ownDistance >= minimumDistance)
                    and self:CanPath(layer, origin, candidate.Position)
                then
                    local routeThreat, coverage = self:GetObservedRouteThreat(
                        origin,
                        candidate.Position,
                        intel,
                        Constants.Policy.ForwardBaseSiteRadius,
                        layer
                    )
                    -- Coverage is recorded for diagnosis but does not gate the
                    -- route. Charging unknown ground a presumed threat was
                    -- measured on Seton's Clutch and cost expansion without
                    -- saving a single engineer: the losses happen at coverage
                    -- 1.00, well inside the safety limit, part-way through a
                    -- walk long enough for the assessment to go stale.
                    if routeThreat and routeThreat <= safetyLimit then
                        local progress = ownDistance - objectiveDistance
                        local score = candidate.Value + progress * 0.35 - routeThreat * 12
                        if not bestScore
                            or score > bestScore
                            or (score == bestScore and candidate.Name < best.Name)
                        then
                            best = {
                                Name = candidate.Name,
                                Type = candidate.Type,
                                Position = candidate.Position,
                                RouteThreat = routeThreat,
                                RouteCoverage = coverage or 0,
                                Layer = layer,
                                SafetyLimit = safetyLimit,
                                Score = score,
                            }
                            bestScore = score
                        end
                    end
                end
            end
        end
        return best
    end,

    GetDenialTarget = function(self, teamCoordinator)
        local best = nil
        local bestScore = nil

        for _, cluster in pairs(self.MassClusters) do
            if not teamCoordinator or not teamCoordinator:IsExpansionClaimedByOther(cluster.Id) then
                local ownDistance = math.sqrt(DistanceSquared(self.StartPosition, cluster.Position))
                local enemyDistance = self.Width + self.Height
                for _, enemy in pairs(self.EnemyStarts) do
                    enemyDistance = math.min(enemyDistance, math.sqrt(DistanceSquared(enemy.Position, cluster.Position)))
                end

                local score = cluster.Count * 200 - ownDistance - enemyDistance * 0.35
                if not bestScore or score > bestScore then
                    best = cluster
                    bestScore = score
                end
            end
        end

        return best
    end,
}

function Create(brain, context)
    return WorldModel(brain, context)
end
