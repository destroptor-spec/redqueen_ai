local Constants = import("/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua")

local function DistanceSquared(a, b)
    local dx = a[1] - b[1]
    local dz = a[3] - b[3]
    return dx * dx + dz * dz
end

local function AnchorPosition(anchor)
    return anchor and (anchor.Position or anchor)
end

-- Anchors are assigned geometrically, but co-located anchors must not be
-- separated by sub-metre noise: quantizing the distance keeps the comparison a
-- deterministic total order on (band, criticality, distance, index) while
-- letting a commander standing inside its own base outrank the base itself.
local function ClosestDistance(position, anchors)
    local tolerance = math.max(1, Constants.Policy.AnchorProximityTolerance)
    local bestBand = nil
    local bestDistance = nil
    local bestIndex = nil
    local bestCriticality = nil
    for index, anchor in pairs(anchors or {}) do
        local anchorPosition = AnchorPosition(anchor)
        local criticality = anchor.Criticality or 1
        local distance = math.sqrt(DistanceSquared(position, anchorPosition))
        local band = math.floor(distance / tolerance)
        if not bestDistance
            or band < bestBand
            or (band == bestBand and criticality > bestCriticality)
            or (band == bestBand
                and criticality == bestCriticality
                and distance < bestDistance)
            or (band == bestBand
                and criticality == bestCriticality
                and distance == bestDistance
                and index < bestIndex)
        then
            bestBand = band
            bestDistance = distance
            bestIndex = index
            bestCriticality = criticality
        end
    end
    return bestDistance or 1000000, bestIndex
end

local function UnitThreat(unit)
    local blueprint = unit:GetBlueprint()
    local defense = blueprint.Defense or {}
    return {
        Land = (defense.SurfaceThreatLevel or 0) + (defense.SubThreatLevel or 0),
        Air = defense.AirThreatLevel or 0,
        Naval = defense.SubThreatLevel or 0,
        Economy = defense.EconomyThreatLevel or 0,
    }
end

local function UnitRole(unit)
    local blueprint = unit:GetBlueprint()
    local hash = blueprint.CategoriesHash or {}
    local economy = blueprint.Economy or {}
    local tech = 1
    if hash.EXPERIMENTAL then
        tech = 4
    elseif hash.TECH3 then
        tech = 3
    elseif hash.TECH2 then
        tech = 2
    end
    return {
        Economy = hash.MASSEXTRACTION
            or hash.ENERGYPRODUCTION
            or hash.FACTORY
            or hash.ENGINEER
            or hash.ECONOMIC,
        Structure = hash.STRUCTURE or false,
        AntiAir = hash.ANTIAIR or false,
        Shield = hash.SHIELD or false,
        StaticDefense = hash.STRUCTURE and (
            hash.DEFENSE
            or hash.DIRECTFIRE
            or hash.INDIRECTFIRE
            or hash.ANTIAIR
            or hash.SHIELD
        ) or false,
        Artillery = hash.ARTILLERY or false,
        Experimental = hash.EXPERIMENTAL or false,
        Nuke = hash.STRUCTURE and hash.NUKE and not hash.ANTIMISSILE or false,
        StrategicDefense = hash.STRUCTURE and hash.TECH3 and hash.ANTIMISSILE or false,
        MobileCombat = hash.MOBILE
            and not hash.ENGINEER
            and not hash.COMMAND
            and not hash.SCOUT,
        MassValue = economy.BuildCostMass or 0,
        Tech = tech,
    }
end

local function UnitLayer(unit)
    local categoriesHash = unit:GetBlueprint().CategoriesHash or {}
    if categoriesHash.AIR then
        return "Air"
    end
    if categoriesHash.NAVAL then
        return "Water"
    end
    if categoriesHash.AMPHIBIOUS or categoriesHash.HOVER then
        return "Amphibious"
    end
    return "Land"
end

local function ObservationCombatThreat(observation)
    local threat = observation.Threat or {}
    return math.max(threat.Land or 0, threat.Naval or 0)
        + (threat.Air or 0)
end

local function GetVerifiedIntelBlip(unit, armyIndex)
    if not unit or unit.Dead then
        return nil
    end

    local blip = unit:GetBlip(armyIndex)
    if not blip then
        return nil
    end

    local seenNow = blip:IsSeenNow(armyIndex)
    local onOmni = blip:IsOnOmni(armyIndex)
    local activelyDetected = seenNow
        or onOmni
        or blip:IsOnRadar(armyIndex)
        or blip:IsOnSonar(armyIndex)
    local identified = seenNow or onOmni or blip:IsSeenEver(armyIndex)
    if activelyDetected and identified then
        return blip
    end
    return nil
end

---@class RedQueenIntelManager
IntelManager = ClassSimple {
    __init = function(self, brain)
        self.Brain = brain
        self.Observations = {}
        self.ObserverCursor = 1
        self.Threat = { Land = 0, Air = 0, Naval = 0, Economy = 0 }
        self.HighestObservedTech = 1
    end,

    ObserveUnit = function(self, unit, tick)
        if not unit or unit.Dead then
            return
        end

        local entityId = unit.EntityId
        if not entityId and unit.GetEntityId then
            entityId = unit:GetEntityId()
        end
        local position = unit:GetPosition()
        if not entityId or not position then
            return
        end

        local previous = self.Observations[entityId]
        self.Observations[entityId] = {
            EntityId = entityId,
            BlueprintId = unit:GetBlueprint().BlueprintId,
            Position = { position[1], position[2], position[3] },
            Layer = UnitLayer(unit),
            Threat = UnitThreat(unit),
            Role = UnitRole(unit),
            LastSeenTick = tick,
            Confidence = 1,
            PreviousPosition = previous and previous.Position or nil,
            PreviousSeenTick = previous and previous.LastSeenTick or nil,
        }
    end,

    Update = function(self)
        local tick = GetGameTick()
        local armyIndex = self.Brain:GetArmyIndex()
        local observerCategory = categories.MOBILE * (categories.LAND + categories.AIR + categories.NAVAL)
        local observers = self.Brain:GetListOfUnits(observerCategory, false)
        local observerCount = table.getn(observers)

        if observerCount > 0 then
            local sampleCount = math.min(Constants.Policy.ObserversPerUpdate, observerCount)
            for sample = 1, sampleCount do
                if self.ObserverCursor > observerCount then
                    self.ObserverCursor = 1
                end
                local observer = observers[self.ObserverCursor]
                self.ObserverCursor = self.ObserverCursor + 1

                if observer and not observer.Dead then
                    local enemies = self.Brain:GetUnitsAroundPoint(
                        categories.ALLUNITS,
                        observer:GetPosition(),
                        Constants.Policy.ObservationRadius,
                        "Enemy"
                    )
                    for _, enemy in pairs(enemies) do
                        local blip = GetVerifiedIntelBlip(enemy, armyIndex)
                        if blip then
                            self:ObserveUnit(blip, tick)
                        end
                    end
                end
            end
        end

        local lifetimeTicks = Constants.Policy.IntelLifetimeSeconds * 10
        local threat = { Land = 0, Air = 0, Naval = 0, Economy = 0 }
        local highestObservedTech = 1
        for entityId, observation in pairs(self.Observations) do
            local age = tick - observation.LastSeenTick
            if age > lifetimeTicks then
                self.Observations[entityId] = nil
            else
                observation.Confidence = math.max(0, 1 - age / lifetimeTicks)
                threat.Land = threat.Land + observation.Threat.Land * observation.Confidence
                threat.Air = threat.Air + observation.Threat.Air * observation.Confidence
                threat.Naval = threat.Naval + observation.Threat.Naval * observation.Confidence
                threat.Economy = threat.Economy + observation.Threat.Economy * observation.Confidence
                highestObservedTech = math.max(
                    highestObservedTech,
                    (observation.Role and observation.Role.Tech) or 1
                )
            end
        end
        self.Threat = threat
        self.HighestObservedTech = highestObservedTech
    end,

    GetThreatNear = function(self, position, radius, layer)
        local radiusSquared = radius * radius
        local total = 0
        for _, observation in pairs(self.Observations) do
            if DistanceSquared(position, observation.Position) <= radiusSquared then
                local threat = observation.Threat
                local relevant = threat.Land + threat.Naval
                if layer == "Air" then
                    relevant = threat.Air
                elseif not layer then
                    relevant = relevant + threat.Air
                end
                total = total + relevant * observation.Confidence
            end
        end
        return total
    end,

    GetThreatBreakdownNear = function(self, position, radius)
        local radiusSquared = radius * radius
        local result = { Surface = 0, Air = 0, Economy = 0 }
        for _, observation in pairs(self.Observations) do
            if DistanceSquared(position, observation.Position) <= radiusSquared then
                local confidence = observation.Confidence or 0
                result.Surface = result.Surface
                    + (observation.Threat.Land + observation.Threat.Naval) * confidence
                result.Air = result.Air + observation.Threat.Air * confidence
                result.Economy = result.Economy + observation.Threat.Economy * confidence
            end
        end
        return result
    end,

    GetObservedArmyClusters = function(self, anchors, worldWidth)
        local tick = GetGameTick()
        local freshTicks = Constants.Policy.FreshCombatIntelSeconds * 10
        local radius = math.max(
            Constants.Policy.ArmyClusterMinimumRadius,
            math.min(
                Constants.Policy.ArmyClusterMaximumRadius,
                (worldWidth or 512) / Constants.Policy.ArmyClusterMapDivisor
            )
        )
        local radiusSquared = radius * radius
        local contacts = {}

        for _, observation in pairs(self.Observations) do
            local role = observation.Role or {}
            local totalThreat = ObservationCombatThreat(observation)
            if role.MobileCombat
                and observation.Position
                and tick - observation.LastSeenTick <= freshTicks
                and (observation.Confidence or 0) >= 0.5
                and totalThreat > 0
            then
                table.insert(contacts, observation)
            end
        end

        table.sort(contacts, function(a, b)
            return (a.EntityId or 0) < (b.EntityId or 0)
        end)

        local clusters = {}
        for _, observation in pairs(contacts) do
            local selected = nil
            for _, cluster in pairs(clusters) do
                if DistanceSquared(observation.Position, cluster.Position) <= radiusSquared then
                    selected = cluster
                    break
                end
            end

            if not selected then
                selected = {
                    FirstEntityId = observation.EntityId,
                    Position = {
                        observation.Position[1],
                        observation.Position[2],
                        observation.Position[3],
                    },
                    Count = 0,
                    Land = 0,
                    Naval = 0,
                    Surface = 0,
                    Air = 0,
                    Threat = 0,
                    ClosingThreat = 0,
                }
                table.insert(clusters, selected)
            end

            selected.Count = selected.Count + 1
            selected.Position[1] = selected.Position[1]
                + (observation.Position[1] - selected.Position[1]) / selected.Count
            selected.Position[2] = selected.Position[2]
                + (observation.Position[2] - selected.Position[2]) / selected.Count
            selected.Position[3] = selected.Position[3]
                + (observation.Position[3] - selected.Position[3]) / selected.Count

            local confidence = observation.Confidence or 0
            local movementThreat = ObservationCombatThreat(observation) * confidence
            local land = 0
            local naval = 0
            local air = 0
            if observation.Layer == "Air" then
                air = movementThreat
            elseif observation.Layer == "Water" then
                naval = movementThreat
            else
                land = movementThreat
            end
            local surface = land + naval
            local contactThreat = surface + air
            selected.Land = selected.Land + land
            selected.Naval = selected.Naval + naval
            selected.Surface = selected.Surface + surface
            selected.Air = selected.Air + air
            selected.Threat = selected.Threat + contactThreat

            if observation.PreviousPosition then
                local previousDistance = ClosestDistance(observation.PreviousPosition, anchors)
                local currentDistance = ClosestDistance(observation.Position, anchors)
                if previousDistance - currentDistance >= Constants.Policy.ArmyApproachDistance then
                    selected.ClosingThreat = selected.ClosingThreat + contactThreat
                end
            end
        end

        for _, cluster in pairs(clusters) do
            cluster.DistanceToAnchor, cluster.AnchorIndex = ClosestDistance(cluster.Position, anchors)
            cluster.Approaching = cluster.ClosingThreat
                >= cluster.Threat * Constants.Policy.ArmyClosingThreatFraction
        end

        table.sort(clusters, function(a, b)
            if a.Threat == b.Threat then
                return a.FirstEntityId < b.FirstEntityId
            end
            return a.Threat > b.Threat
        end)
        return clusters
    end,

    GetStrategicPicture = function(self, origin, world)
        local picture = {
            EnemyTech = self.HighestObservedTech or 1,
            ObservedConfidence = 0,
            EconomyValue = 0,
            ReachableValue = 0,
            UnreachableValue = 0,
            Fortification = 0,
            Shields = 0,
            Artillery = 0,
            Experimentals = 0,
            Nukes = 0,
            StrategicDefense = 0,
            HasHighValueTarget = false,
            HasReachableTarget = false,
            HasUnreachableTarget = false,
            Fortified = false,
        }

        for _, observation in pairs(self.Observations) do
            local confidence = observation.Confidence or 0
            local role = observation.Role or {}
            local threat = observation.Threat or {}
            local value = ((threat.Economy or 0) * 4 + (role.MassValue or 0) * 0.10) * confidence
            picture.ObservedConfidence = picture.ObservedConfidence + confidence
            picture.EconomyValue = picture.EconomyValue + value

            if role.Shield then
                picture.Shields = picture.Shields + confidence
                picture.Fortification = picture.Fortification + 12 * confidence
            end
            if role.Artillery then
                picture.Artillery = picture.Artillery + confidence
                picture.Fortification = picture.Fortification + 8 * confidence
            end
            if role.StaticDefense then
                picture.Fortification = picture.Fortification
                    + ((threat.Land or 0) + (threat.Air or 0) + (threat.Naval or 0)) * confidence
            end
            if role.Experimental then
                picture.Experimentals = picture.Experimentals + confidence
            end
            if role.Nuke then
                picture.Nukes = picture.Nukes + confidence
            end
            if role.StrategicDefense then
                picture.StrategicDefense = picture.StrategicDefense + confidence
            end

            if value > 0 and world and world.CanPath then
                local layer = observation.Layer == "Water" and "Water" or "Land"
                if world:CanPath(layer, origin, observation.Position) then
                    picture.ReachableValue = picture.ReachableValue + value
                else
                    picture.UnreachableValue = picture.UnreachableValue + value
                end
            end
        end

        picture.HasHighValueTarget = picture.EconomyValue >= Constants.Policy.StrategicHighValueThreshold
        picture.HasReachableTarget = picture.ReachableValue >= Constants.Policy.StrategicHighValueThreshold
        picture.HasUnreachableTarget = picture.UnreachableValue >= Constants.Policy.StrategicHighValueThreshold
        picture.Fortified = picture.Fortification >= Constants.Policy.StrategicFortificationThreshold
        return picture
    end,

    GetBestKnownTarget = function(self, origin, layer)
        local best = nil
        local bestScore = nil
        for _, observation in pairs(self.Observations) do
            if layer == "Air" or observation.Layer == layer or layer == "Amphibious" then
                local distance = math.sqrt(DistanceSquared(origin, observation.Position))
                local role = observation.Role or {}
                local economicValue = observation.Threat.Economy * 4
                    + (role.Economy and 80 or 0)
                    + math.min(100, (role.MassValue or 0) * 0.10)
                local combatThreat = observation.Threat.Land
                    + observation.Threat.Air
                    + observation.Threat.Naval
                local score = observation.Confidence * (100 + economicValue)
                    - combatThreat * 0.75
                    - distance * 0.05
                if not bestScore
                    or score > bestScore
                    or (score == bestScore and observation.EntityId < best.EntityId)
                then
                    best = observation
                    bestScore = score
                end
            end
        end
        return best
    end,

    GetBestExposedEconomyTarget = function(self, origin)
        local best = nil
        local bestScore = nil
        local radius = Constants.Policy.AirDropTargetRadius

        for _, observation in pairs(self.Observations) do
            local role = observation.Role or {}
            if role.Economy and observation.Confidence >= 0.25 then
                local nearby = self:GetThreatBreakdownNear(observation.Position, radius)
                if nearby.Air <= Constants.Policy.AirDropMaximumAirThreat then
                    local distance = math.sqrt(DistanceSquared(origin, observation.Position))
                    local value = observation.Threat.Economy * 6
                        + math.min(150, (role.MassValue or 0) * 0.15)
                    local score = observation.Confidence * (120 + value)
                        - nearby.Surface * 1.5
                        - nearby.Air * 12
                        - distance * 0.04
                    if not bestScore
                        or score > bestScore
                        or (score == bestScore and observation.EntityId < best.EntityId)
                    then
                        best = {
                            EntityId = observation.EntityId,
                            Position = observation.Position,
                            AirDefense = nearby.Air,
                            SurfaceThreat = nearby.Surface,
                            Score = score,
                        }
                        bestScore = score
                    end
                end
            end
        end

        return best
    end,
}

function Create(brain)
    return IntelManager(brain)
end
