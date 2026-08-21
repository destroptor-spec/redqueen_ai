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

        self.EnemyStarts = {}
        for _, armyIndex in pairs(self.Context.EnemyArmies) do
            local enemyBrain = ArmyBrains[armyIndex]
            if enemyBrain then
                local x, z = enemyBrain:GetArmyStartPos()
                table.insert(self.EnemyStarts, {
                    Army = armyIndex,
                    Position = { x, GetSurfaceHeight(x, z), z },
                })
            end
        end

        Logger.Info(self.Brain, string.format(
            "map type=%s size=%dkm water=%.2f massClusters=%d",
            self.MapType,
            self.MapKilometers,
            self.WaterRatio,
            table.getn(self.MassClusters)
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

    GetClosestEnemyStart = function(self, origin, layer)
        local best = nil
        local bestDistance = nil
        for _, enemy in pairs(self.EnemyStarts) do
            local distance = DistanceSquared(origin, enemy.Position)
            if (not bestDistance or distance < bestDistance) and self:CanPath(layer or "Land", origin, enemy.Position) then
                best = enemy.Position
                bestDistance = distance
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

    GetObservedRouteThreat = function(self, origin, destination, intel, radius)
        local path = NavUtils.PathTo and NavUtils.PathTo("Land", origin, destination)
        if not path then
            if not self:CanPath("Land", origin, destination) then
                return nil
            end
            path = { origin, destination }
        end
        local maximum = 0
        for _, position in pairs(path) do
            maximum = math.max(maximum, intel:GetThreatNear(position, radius))
        end
        maximum = math.max(maximum, intel:GetThreatNear(destination, radius))
        return maximum
    end,

    SelectForwardBaseSite = function(self, origin, objective, intel, claimed, escortThreat)
        if not objective then
            return nil
        end
        local best = nil
        local bestScore = nil
        local minimumDistance = Constants.Policy.ForwardBaseMinimumDistance
        local safetyLimit = math.max(0, escortThreat * Constants.Policy.ForwardBaseSafetyRatio)

        for _, candidate in pairs(self.ForwardBaseCandidates) do
            if not claimed[candidate.Name] then
                local ownDistance = math.sqrt(DistanceSquared(origin, candidate.Position))
                local objectiveDistance = math.sqrt(DistanceSquared(objective, candidate.Position))
                if ownDistance >= minimumDistance and self:CanPath("Land", origin, candidate.Position) then
                    local routeThreat = self:GetObservedRouteThreat(
                        origin,
                        candidate.Position,
                        intel,
                        Constants.Policy.ForwardBaseSiteRadius
                    )
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
