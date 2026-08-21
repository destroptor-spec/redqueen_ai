local Logger = import("/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua")
local Constants = import("/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua")

local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function Score(value)
    return math.floor(Clamp(value, 0, 100) + 0.5)
end

local function PositionLayer(position)
    if GetSurfaceHeight(position[1], position[3]) - GetTerrainHeight(position[1], position[3]) > 0.5 then
        return "Water"
    end
    return "Land"
end

local function CanInterrupt(previous, objective, tick)
    if not previous or not previous.ExpiresTick or previous.ExpiresTick <= tick then
        return true
    end
    if objective.RequestedBy or objective.Type == "Defend" then
        return true
    end
    if previous.Type == "Stage" then
        return true
    end
    return objective.Priority >= previous.Priority + Constants.Policy.ObjectiveInterruptPriorityGap
end

local function CanAfford(state, massIncome, energyIncome)
    return not state.StallRisk
        and state.MassIncome >= massIncome
        and state.EnergyIncome >= energyIncome
end

local function BlueprintThreat(unit)
    local blueprint = unit:GetBlueprint()
    local defense = blueprint.Defense or {}
    return (defense.SurfaceThreatLevel or 0)
        + (defense.SubThreatLevel or 0)
        + (defense.AirThreatLevel or 0)
end

local function ArmyStatValue(brain, name)
    if not brain.GetArmyStat then
        return 0
    end
    local value = brain:GetArmyStat(name, 0)
    if type(value) == "table" then
        return value.Value or 0
    end
    return value or 0
end

---@class RedQueenStrategyDirector
StrategyDirector = ClassSimple {
    __init = function(self, brain, context, world, intel, economy, team, pings)
        self.Brain = brain
        self.Context = context
        self.World = world
        self.Intel = intel
        self.Economy = economy
        self.Team = team
        self.Pings = pings
        self.CurrentObjective = nil
        self.RecentLandLosses = {}
        self.LandLossPressure = { Count = 0, Mass = 0 }
        self.CounterDoctrineUntilTick = 0
        self.LastAirDropRequestTick = -100000
        self.AirDropOpportunity = nil
        self.CombatMomentumSamples = {}
        self.CombatMomentum = { LostMass = 0, DestroyedMass = 0, Losing = false }
        self.DefenseAlert = { Active = false }
        self.ProductionDemand = {
            Land = 0.55,
            Air = 0.30,
            Naval = 0.15,
            AntiAir = 0.15,
            Scouts = 0.08,
            Artillery = 0.12,
            Gunships = 0.18,
            Doctrine = "Balanced",
            FocusWeights = {
                Army = 50,
                Tech2 = 0,
                Tech3 = 0,
                Experimental = 0,
                Nuke = 0,
            },
            PrimaryFocus = "Army",
            EconomicReadiness = 0,
            MajorProjectSlots = 0,
            DesiredExperimentals = 0,
            DesiredNukes = 0,
            FocusReason = "field-pressure",
            DefenseAlert = self.DefenseAlert,
            TierPolicy = {},
            ForwardBasePlan = { Active = false },
        }
    end,

    RecordUnitLoss = function(self, unit)
        if not unit then
            return
        end

        local blueprint = unit:GetBlueprint()
        local hash = blueprint.CategoriesHash or {}
        if not hash.MOBILE
            or not (hash.LAND or hash.AMPHIBIOUS or hash.HOVER)
            or hash.ENGINEER
            or hash.COMMAND
            or hash.SCOUT
        then
            return
        end

        local economy = blueprint.Economy or {}
        table.insert(self.RecentLandLosses, {
            Tick = GetGameTick(),
            Mass = economy.BuildCostMass or 1,
        })
    end,

    UpdateLandLossPressure = function(self)
        local cutoff = GetGameTick() - Constants.Policy.LandLossWindowSeconds * 10
        local count = 0
        local mass = 0

        for index = table.getn(self.RecentLandLosses), 1, -1 do
            local loss = self.RecentLandLosses[index]
            if loss.Tick < cutoff then
                table.remove(self.RecentLandLosses, index)
            else
                count = count + 1
                mass = mass + loss.Mass
            end
        end

        self.LandLossPressure = { Count = count, Mass = mass }
        return self.LandLossPressure
    end,

    UpdateCombatMomentum = function(self)
        local tick = GetGameTick()
        local sample = {
            Tick = tick,
            Lost = ArmyStatValue(self.Brain, "Units_MassValue_Lost"),
            Destroyed = ArmyStatValue(self.Brain, "Enemies_MassValue_Destroyed"),
        }
        table.insert(self.CombatMomentumSamples, sample)

        local cutoff = tick - Constants.Policy.CombatMomentumWindowSeconds * 10
        while table.getn(self.CombatMomentumSamples) > 1
            and self.CombatMomentumSamples[2].Tick <= cutoff
        do
            table.remove(self.CombatMomentumSamples, 1)
        end

        local first = self.CombatMomentumSamples[1] or sample
        local lost = math.max(0, sample.Lost - first.Lost)
        local destroyed = math.max(0, sample.Destroyed - first.Destroyed)
        local losing = lost >= destroyed * Constants.Policy.CombatMomentumLossRatio
            and lost - destroyed >= Constants.Policy.CombatMomentumMassDifference
        self.CombatMomentum = {
            LostMass = lost,
            DestroyedMass = destroyed,
            Losing = losing,
        }
        return self.CombatMomentum
    end,

    GetProtectedAnchors = function(self)
        local anchors = { self.World.StartPosition }
        local managers = self.Brain.BuilderManagers or {}
        local locationTypes = {}
        for locationType, _ in pairs(managers) do
            table.insert(locationTypes, locationType)
        end
        table.sort(locationTypes)

        for _, locationType in pairs(locationTypes) do
            local manager = managers[locationType]
            local engineerManager = manager and manager.EngineerManager
            local position = engineerManager
                and engineerManager.GetLocationCoords
                and engineerManager:GetLocationCoords()
            if position then
                table.insert(anchors, position)
            end
        end

        if self.Brain.GetListOfUnits and categories and categories.COMMAND then
            local commanders = self.Brain:GetListOfUnits(categories.COMMAND, false) or {}
            table.sort(commanders, function(a, b)
                return (a.EntityId or 0) < (b.EntityId or 0)
            end)
            for _, commander in pairs(commanders) do
                if commander and not commander.Dead then
                    local position = commander:GetPosition()
                    if position then
                        table.insert(anchors, position)
                    end
                end
            end
        end
        return anchors
    end,

    GetOwnThreatNear = function(self, position, radius)
        if not self.Brain.GetUnitsAroundPoint then
            return 0
        end
        local category = categories.MOBILE * (categories.LAND + categories.AIR + categories.NAVAL)
            - categories.ENGINEER
            - categories.COMMAND
            - categories.SCOUT
            + categories.STRUCTURE * categories.DEFENSE
        local units = self.Brain:GetUnitsAroundPoint(category, position, radius, "Ally") or {}
        local threat = 0
        for _, unit in pairs(units) do
            if unit and not unit.Dead then
                threat = threat + BlueprintThreat(unit)
            end
        end
        return threat
    end,

    UpdateDefenseAlert = function(self)
        local tick = GetGameTick()
        local previous = self.DefenseAlert or { Active = false }
        local momentum = self:UpdateCombatMomentum()
        local anchors = self:GetProtectedAnchors()
        local clusters = self.Intel.GetObservedArmyClusters
            and self.Intel:GetObservedArmyClusters(anchors, self.World.Width)
            or {}
        local alert = { Active = false }

        for _, cluster in pairs(clusters) do
            local anchor = anchors[cluster.AnchorIndex or 1] or self.World.StartPosition
            local ownThreat = self:GetOwnThreatNear(anchor, math.max(60, self.World.Width / 12))
            local ratio = cluster.Threat / math.max(1, ownThreat)
            local massive = cluster.Threat >= Constants.Policy.MassiveArmyThreat
                and ratio >= Constants.Policy.MassiveArmyThreatRatio
            local pressure = cluster.Threat >= Constants.Policy.PressureEscalationThreat
                and ratio >= 1
                and cluster.Approaching
                and momentum.Losing

            if massive or pressure then
                local candidate = {
                    Active = true,
                    Position = cluster.Position,
                    AnchorPosition = anchor,
                    Threat = cluster.Threat,
                    Surface = cluster.Surface,
                    Air = cluster.Air,
                    FriendlyThreat = ownThreat,
                    Ratio = ratio,
                    Count = cluster.Count,
                    Approaching = cluster.Approaching,
                    DistanceToAnchor = cluster.DistanceToAnchor,
                    FirstEntityId = cluster.FirstEntityId,
                    Losing = momentum.Losing,
                    LostMass = momentum.LostMass,
                    DestroyedMass = momentum.DestroyedMass,
                    Severity = math.max(1, ratio),
                    Targets = {
                        Ground = math.max(4, math.min(12, math.ceil(cluster.Surface / 12))),
                        AntiAir = math.max(2, math.min(8, math.ceil(cluster.Air / 10))),
                        Shields = (ratio >= 2 or cluster.DistanceToAnchor <= 60) and 2 or 1,
                        StrategicMissileDefense = 1,
                        TacticalMissiles = cluster.Surface > 0 and 2 or 0,
                    },
                    CreatedTick = previous.Active and previous.CreatedTick or tick,
                    ExpiresTick = tick + Constants.Policy.DefenseAlertHoldSeconds * 10,
                }
                if not alert.Active
                    or candidate.Ratio > alert.Ratio
                    or (
                        candidate.Ratio == alert.Ratio
                        and candidate.DistanceToAnchor < alert.DistanceToAnchor
                    )
                    or (
                        candidate.Ratio == alert.Ratio
                        and candidate.DistanceToAnchor == alert.DistanceToAnchor
                        and candidate.Threat > alert.Threat
                    )
                    or (
                        candidate.Ratio == alert.Ratio
                        and candidate.DistanceToAnchor == alert.DistanceToAnchor
                        and candidate.Threat == alert.Threat
                        and candidate.FirstEntityId < alert.FirstEntityId
                    )
                then
                    alert = candidate
                end
            end
        end

        if not alert.Active and previous.Active and previous.ExpiresTick > tick then
            alert = previous
        end

        if alert.Active and not previous.Active then
            Logger.Info(self.Brain, string.format(
                "defense alert started threat=%.1f friendly=%.1f ratio=%.2f approaching=%s losses=%.0f/%.0f",
                alert.Threat,
                alert.FriendlyThreat,
                alert.Ratio,
                alert.Approaching and "yes" or "no",
                alert.LostMass,
                alert.DestroyedMass
            ))
        elseif previous.Active and not alert.Active then
            Logger.Info(self.Brain, "defense alert cleared")
        end

        self.DefenseAlert = alert
        self.ProductionDemand.DefenseAlert = alert
        return alert
    end,

    SetObjective = function(self, objective)
        local previous = self.CurrentObjective
        local tick = GetGameTick()

        if previous and objective and previous.Type == objective.Type and previous.ExpiresTick > tick then
            objective.CreatedTick = previous.CreatedTick
            objective.ExpiresTick = previous.ExpiresTick
        elseif previous and objective and not CanInterrupt(previous, objective, tick) then
            return previous
        else
            objective.ExpiresTick = objective.ExpiresTick or tick + Constants.Policy.ObjectiveLifetimeTicks
        end

        self.CurrentObjective = objective
        if objective and (not previous or previous.Type ~= objective.Type) then
            Logger.Info(self.Brain, string.format(
                "strategy objective=%s priority=%d layer=%s",
                objective.Type,
                objective.Priority,
                objective.Layer
            ))
        end
        return objective
    end,

    GetEconomicReadiness = function(self)
        local state = self.Economy.State
        if state.StallRisk then
            return 0
        end

        local function Headroom(income, requested)
            if income <= 0 then
                return 0
            end
            return Clamp((income - math.max(0, requested or 0)) / income, 0, 1)
        end

        local massHeadroom = Headroom(state.MassIncome, state.MassRequested)
        local energyHeadroom = Headroom(state.EnergyIncome, state.EnergyRequested)
        local storage = math.min(
            Clamp(state.MassStoredRatio / 0.25, 0, 1),
            Clamp(state.EnergyStoredRatio / 0.35, 0, 1)
        )
        local trend = 0
        if state.MassTrend >= 0 then
            trend = trend + 0.5
        end
        if state.EnergyTrend >= 0 then
            trend = trend + 0.5
        end

        local readiness = massHeadroom * 0.35
            + energyHeadroom * 0.25
            + storage * 0.25
            + trend * 0.15
        local capacity = math.min(
            Clamp(state.MassIncome / Constants.Policy.Tech2MinimumMassIncome, 0, 1),
            Clamp(state.EnergyIncome / Constants.Policy.Tech2MinimumEnergyIncome, 0, 1)
        )
        readiness = readiness * capacity
        if state.Surplus then
            readiness = math.max(readiness, 0.85 * capacity)
        end
        return Clamp(readiness, 0, 1)
    end,

    GetOwnForces = function(self)
        local result = {
            T2Factories = 0,
            T3Factories = 0,
            T3Engineers = 0,
            MissingT2Coverage = 2,
            MissingT3Coverage = 2,
            Experimentals = 0,
            Nukes = 0,
        }
        if not self.Brain.GetCurrentUnits or not categories then
            return result
        end

        local function Count(category)
            return self.Brain:GetCurrentUnits(category) or 0
        end

        local t2OrT3 = categories.TECH2 + categories.TECH3
        local landT2 = Count(categories.FACTORY * categories.LAND * t2OrT3)
        local airT2 = Count(categories.FACTORY * categories.AIR * t2OrT3)
        local navalT2 = Count(categories.FACTORY * categories.NAVAL * t2OrT3)
        local landT3 = Count(categories.FACTORY * categories.LAND * categories.TECH3)
        local airT3 = Count(categories.FACTORY * categories.AIR * categories.TECH3)
        local navalT3 = Count(categories.FACTORY * categories.NAVAL * categories.TECH3)

        result.T2Factories = landT2 + airT2 + navalT2
        result.T3Factories = landT3 + airT3 + navalT3
        result.T3Engineers = Count(categories.ENGINEER * categories.TECH3)
        result.Experimentals = Count(categories.EXPERIMENTAL)
        result.Nukes = Count(categories.NUKE * categories.STRUCTURE)

        local relevant = 0
        local t2Coverage = 0
        local t3Coverage = 0
        if self.World.MapType ~= "Naval" then
            relevant = relevant + 1
            if landT2 > 0 then t2Coverage = t2Coverage + 1 end
            if landT3 > 0 then t3Coverage = t3Coverage + 1 end
        end
        relevant = relevant + 1
        if airT2 > 0 then t2Coverage = t2Coverage + 1 end
        if airT3 > 0 then t3Coverage = t3Coverage + 1 end
        if self.World.MapType ~= "Land" then
            relevant = relevant + 1
            if navalT2 > 0 then t2Coverage = t2Coverage + 1 end
            if navalT3 > 0 then t3Coverage = t3Coverage + 1 end
        end
        result.MissingT2Coverage = relevant - t2Coverage
        result.MissingT3Coverage = relevant - t3Coverage
        return result
    end,

    SelectPrimaryFocus = function(self, weights)
        local order = { "Army", "Tech2", "Tech3", "Experimental", "Nuke" }
        local best = "Army"
        for index = 1, table.getn(order) do
            local focus = order[index]
            if weights[focus] > weights[best] then
                best = focus
            end
        end

        local current = self.ProductionDemand.PrimaryFocus or "Army"
        local currentScore = weights[current] or 0
        if currentScore < Constants.Policy.StrategicFocusMinimumScore
            or weights[best] >= currentScore + Constants.Policy.StrategicFocusSwitchMargin
        then
            return best
        end
        return current
    end,

    UpdateStrategicFocus = function(self, objective, loss, surfaceThreat, airThreat)
        local demand = self.ProductionDemand
        local state = self.Economy.State
        local readiness = self:GetEconomicReadiness()
        local forces = self:GetOwnForces()
        local picture = self.Intel.GetStrategicPicture
            and self.Intel:GetStrategicPicture(self.World.StartPosition, self.World)
            or {
                EnemyTech = self.Intel.HighestObservedTech or 1,
                Fortification = 0,
                Experimentals = 0,
                Nukes = 0,
                StrategicDefense = 0,
                HasHighValueTarget = false,
                HasReachableTarget = false,
                HasUnreachableTarget = false,
                Fortified = false,
            }
        local localThreat = self.Intel:GetThreatNear(
            self.World.StartPosition,
            math.max(100, self.World.Width / 12)
        )
        local baseDanger = localThreat >= Constants.Policy.LocalDefenseThreat
        local lossPressure = loss.Count >= Constants.Policy.LandLossCountThreshold
            or loss.Mass >= Constants.Policy.LandLossMassThreshold
        local offensive = objective.Type == "Raid"
            or objective.Type == "Pressure"
            or objective.Type == "Assault"
            or objective.Type == "Supremacy"
            or objective.Type == "JointAttack"

        local army = 50
        if localThreat > 0 then
            army = army + math.min(35, localThreat)
        end
        if lossPressure then
            army = army + 20
        end
        if offensive then
            army = army + 10
        end
        if picture.Experimentals > 0 or picture.Nukes > 0 then
            army = army + 15
        end

        local tech2 = 0
        if not baseDanger
            and forces.MissingT2Coverage > 0
            and CanAfford(
                state,
                Constants.Policy.Tech2MinimumMassIncome,
                Constants.Policy.Tech2MinimumEnergyIncome
            )
        then
            tech2 = 20 + readiness * 30 + math.min(15, forces.MissingT2Coverage * 5)
            if picture.EnemyTech >= 2 then tech2 = tech2 + 25 end
            if demand.Doctrine ~= "Balanced" and forces.T2Factories == 0 then tech2 = tech2 + 15 end
            if lossPressure then tech2 = tech2 - 10 end
        end

        local tech3 = 0
        if not baseDanger
            and forces.T2Factories > 0
            and forces.MissingT3Coverage > 0
            and CanAfford(
                state,
                Constants.Policy.Tech3MinimumMassIncome,
                Constants.Policy.Tech3MinimumEnergyIncome
            )
        then
            tech3 = 15 + readiness * 35 + math.min(15, forces.MissingT3Coverage * 5)
            if picture.EnemyTech >= 3 then tech3 = tech3 + 25 end
            if picture.Fortified or picture.Experimentals > 0 then tech3 = tech3 + 15 end
            if demand.Doctrine ~= "Balanced" and forces.T3Factories == 0 then tech3 = tech3 + 10 end
            if lossPressure then tech3 = tech3 - 10 end
        end

        local experimental = 0
        if not baseDanger
            and forces.T3Factories > 0
            and forces.T3Engineers > 0
            and CanAfford(
                state,
                Constants.Policy.ExperimentalMinimumMassIncome,
                Constants.Policy.ExperimentalMinimumEnergyIncome
            )
        then
            experimental = 10 + readiness * 30
            if picture.Fortified then experimental = experimental + 25 end
            if lossPressure then experimental = experimental + 20 end
            if picture.Experimentals > 0 then experimental = experimental + 15 end
            if picture.HasReachableTarget then experimental = experimental + 10 end
            if airThreat > math.max(10, surfaceThreat * 0.75) then
                experimental = experimental - 25
            end
        end

        local nuke = 0
        local nukeOpportunity = picture.HasHighValueTarget
            and (picture.Fortified
                or picture.HasUnreachableTarget
                or picture.Experimentals > 0
                or picture.Nukes > 0)
        if not baseDanger
            and nukeOpportunity
            and picture.StrategicDefense < 0.5
            and forces.T3Factories > 0
            and forces.T3Engineers > 0
            and CanAfford(
                state,
                Constants.Policy.NukeMinimumMassIncome,
                Constants.Policy.NukeMinimumEnergyIncome
            )
        then
            nuke = 10 + readiness * 30
            if picture.Fortified then nuke = nuke + 30 end
            if picture.HasUnreachableTarget then nuke = nuke + 15 end
            if picture.Experimentals > 0 or picture.Nukes > 0 then nuke = nuke + 15 end
        end

        local weights = {
            Army = Score(army),
            Tech2 = Score(tech2),
            Tech3 = Score(tech3),
            Experimental = Score(experimental),
            Nuke = Score(nuke),
        }
        demand.FocusWeights = weights
        demand.EconomicReadiness = readiness
        demand.PrimaryFocus = self:SelectPrimaryFocus(weights)

        local bestEndgame = math.max(weights.Experimental, weights.Nuke)
        demand.MajorProjectSlots = 0
        if bestEndgame >= Constants.Policy.StrategicFocusMinimumScore then
            demand.MajorProjectSlots = 1
            if readiness >= Constants.Policy.StrategicSecondProjectReadiness
                and weights.Army < Constants.Policy.StrategicSecondProjectArmyMaximum
            then
                demand.MajorProjectSlots = 2
            end
        end
        demand.DesiredExperimentals = weights.Experimental >= Constants.Policy.StrategicFocusMinimumScore
            and (weights.Experimental >= 75 and demand.MajorProjectSlots or 1)
            or 0
        demand.DesiredNukes = weights.Nuke >= Constants.Policy.StrategicFocusMinimumScore
            and (weights.Nuke >= 75 and demand.MajorProjectSlots or 1)
            or 0

        local defenseAlert = self.DefenseAlert or { Active = false }
        if defenseAlert.Active then
            weights.Army = 100
            weights.Experimental = 0
            weights.Nuke = 0
            demand.PrimaryFocus = "Army"
            demand.MajorProjectSlots = 0
            demand.DesiredExperimentals = 0
            demand.DesiredNukes = 0
            demand.FocusReason = "defense-pressure"
        elseif baseDanger then
            demand.FocusReason = "base-danger"
        elseif demand.PrimaryFocus == "Tech2" or demand.PrimaryFocus == "Tech3" then
            local enemyDriven = demand.PrimaryFocus == "Tech3"
                and picture.EnemyTech >= 3
                or demand.PrimaryFocus == "Tech2"
                    and picture.EnemyTech >= 2
            demand.FocusReason = enemyDriven and "enemy-tech" or "economy-ready"
        elseif demand.PrimaryFocus == "Experimental" then
            demand.FocusReason = picture.Fortified and "reachable-fortification" or "breakthrough"
        elseif demand.PrimaryFocus == "Nuke" then
            demand.FocusReason = picture.HasUnreachableTarget and "unreachable-value" or "strategic-siege"
        elseif lossPressure then
            demand.FocusReason = "combat-losses"
        else
            demand.FocusReason = "field-pressure"
        end
    end,

    UpdateDemand = function(self, objective)
        local threat = self.Intel.Threat
        local demand = self.ProductionDemand
        demand.Scouts = table.getsize(self.Intel.Observations) == 0 and 0.15 or 0.07
        demand.Artillery = objective.Type == "Assault" and 0.18 or 0.10
        demand.Gunships = 0.18
        demand.Doctrine = "Balanced"

        if self.World.MapType == "Naval" then
            demand.Land = 0.15
            demand.Air = 0.30
            demand.Naval = 0.55
        elseif self.World.MapType == "Mixed" then
            demand.Land = 0.40
            demand.Air = 0.30
            demand.Naval = 0.30
        else
            demand.Land = 0.60
            demand.Air = 0.35
            demand.Naval = 0.05
        end

        local surfaceThreat = (threat.Land or 0) + (threat.Naval or 0)
        local airThreat = threat.Air or 0
        demand.AntiAir = math.max(0.10, math.min(0.45, airThreat / math.max(1, surfaceThreat + airThreat)))

        local loss = self:UpdateLandLossPressure()
        local lossesDemandCounter = loss.Count >= Constants.Policy.LandLossCountThreshold
            or loss.Mass >= Constants.Policy.LandLossMassThreshold
        local airDefenseIsExposed = airThreat <= math.max(
            Constants.Policy.AirDropMaximumAirThreat,
            surfaceThreat * Constants.Policy.GunshipAirThreatRatio
        )
        local tick = GetGameTick()

        if lossesDemandCounter and airDefenseIsExposed then
            self.CounterDoctrineUntilTick = tick + Constants.Policy.CounterDoctrineSeconds * 10
        end

        if tick < self.CounterDoctrineUntilTick
            and airThreat <= math.max(12, surfaceThreat * 0.65)
        then
            demand.Doctrine = "GunshipCounter"
            demand.Gunships = 0.55
            demand.Air = math.max(demand.Air, 0.50)
        elseif airThreat > 10 and airThreat > surfaceThreat * 0.75 then
            demand.Doctrine = "AirDefense"
            demand.AntiAir = 0.45
            demand.Air = math.max(demand.Air, 0.45)
        end

        self:UpdateStrategicFocus(objective, loss, surfaceThreat, airThreat)
    end,

    UpdateAirDropOpportunity = function(self, start)
        self.AirDropOpportunity = nil
        if (self.DefenseAlert and self.DefenseAlert.Active)
            or not self.Intel.GetBestExposedEconomyTarget
        then
            return nil
        end

        local opportunity = self.Intel:GetBestExposedEconomyTarget(start)
        self.AirDropOpportunity = opportunity
        if not opportunity then
            return nil
        end

        local tick = GetGameTick()
        local cooldown = Constants.Policy.AirDropRequestCooldownSeconds * 10
        local transports = 0
        if self.Brain.GetCurrentUnits and categories and categories.TRANSPORTFOCUS then
            transports = self.Brain:GetCurrentUnits(categories.TRANSPORTFOCUS)
        end

        if transports < Constants.Policy.MaximumAirDropTransports
            and not self.Brain.TransportRequested
            and tick - self.LastAirDropRequestTick >= cooldown
        then
            self.Brain.TransportRequested = true
            self.LastAirDropRequestTick = tick
            Logger.Info(self.Brain, string.format(
                "airdrop opportunity target=%d aa=%.1f surface=%.1f transports=%d",
                opportunity.EntityId,
                opportunity.AirDefense,
                opportunity.SurfaceThreat,
                transports
            ))
        end

        return opportunity
    end,

    Update = function(self)
        local start = self.World.StartPosition
        local localThreat = self.Intel:GetThreatNear(start, math.max(100, self.World.Width / 12))
        local defenseAlert = self:UpdateDefenseAlert()
        local airDrop = self:UpdateAirDropOpportunity(start)
        local objective = nil

        if defenseAlert.Active then
            objective = {
                Type = "Defend",
                Position = defenseAlert.AnchorPosition,
                ThreatPosition = defenseAlert.Position,
                Layer = PositionLayer(defenseAlert.AnchorPosition),
                Priority = 140,
                CreatedTick = GetGameTick(),
            }
        elseif localThreat >= Constants.Policy.LocalDefenseThreat then
            objective = {
                Type = "Defend",
                Position = start,
                Layer = "Land",
                Priority = 120,
                CreatedTick = GetGameTick(),
            }
        end

        local ping = self.Pings:GetBestRequest()
        if not objective and ping then
            objective = {
                Type = ping.Type,
                Position = ping.Position,
                Layer = PositionLayer(ping.Position),
                Priority = ping.Priority,
                CreatedTick = ping.CreatedTick,
                RequestedBy = ping.OwnerArmy,
            }
        end

        local support = self.Team:GetSupportRequest(start)
        if not objective and support then
            objective = {
                Type = "Support",
                Position = support.Position,
                Layer = PositionLayer(support.Position),
                Priority = 82,
                CreatedTick = GetGameTick(),
                RequestedBy = support.Army,
            }
        end

        local alliedAttack = self.Team:GetCoordinatedAttack()
        if not objective and alliedAttack then
            objective = {
                Type = "JointAttack",
                Position = alliedAttack.Position,
                Layer = alliedAttack.Layer,
                Priority = alliedAttack.Priority + 5,
                CreatedTick = GetGameTick(),
                LaunchTick = alliedAttack.LaunchTick,
            }
        end

        if not objective then
            local preferredLayer = self.World.MapType == "Naval" and "Water" or "Land"
            local known = self.Intel:GetBestKnownTarget(start, preferredLayer)
            if known
                and preferredLayer ~= "Air"
                and not self.World:CanPath(preferredLayer, start, known.Position)
            then
                known = nil
            end

            if known then
                objective = {
                    Type = "Raid",
                    Position = known.Position,
                    Layer = preferredLayer,
                    Priority = 75,
                    CreatedTick = GetGameTick(),
                }
            else
                local position = self.World:GetClosestEnemyStart(start, preferredLayer)
                if not position and preferredLayer ~= "Air" then
                    preferredLayer = "Air"
                    position = self.World:GetClosestEnemyStart(start, "Air")
                end
                if position then
                    objective = {
                        Type = "Pressure",
                        Position = position,
                        Layer = preferredLayer,
                        Priority = 60,
                        CreatedTick = GetGameTick(),
                    }
                end
            end
        end

        if not objective then
            objective = {
                Type = "Stage",
                Position = start,
                Layer = "Land",
                Priority = 0,
                CreatedTick = GetGameTick(),
            }
        end

        if airDrop
            and objective
            and objective.Type ~= "Stage"
            and objective.Type ~= "Defend"
        then
            objective.AirPosition = airDrop.Position
            objective.AirDropTarget = airDrop.EntityId
        end

        objective = self:SetObjective(objective)
        self:UpdateDemand(objective)

        if objective.Type == "Assault"
            or objective.Type == "Raid"
            or objective.Type == "Supremacy"
            or objective.Type == "Pressure"
        then
            self.Team:PublishAttack(objective)
        end
    end,
}

function Create(brain, context, world, intel, economy, team, pings)
    return StrategyDirector(brain, context, world, intel, economy, team, pings)
end
