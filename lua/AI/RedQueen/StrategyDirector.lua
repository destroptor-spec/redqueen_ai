local Logger = import("/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua")
local Constants = import("/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua")
local EngineerSurvival = import("/mods/TheRedQueen/lua/AI/RedQueen/EngineerSurvival.lua")

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

-- Fixed compass offsets, so probing terrain never depends on iteration order.
local ProbeDirections = {
    { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
    { 0.7071, 0.7071 }, { 0.7071, -0.7071 },
    { -0.7071, 0.7071 }, { -0.7071, -0.7071 },
}

-- Nearest water deep enough to found a torpedo launcher, biased toward the
-- threat so the battery ends up on the approach rather than behind the base.
-- Returns nil for a genuinely inland anchor, which is what gates the whole
-- torpedo response: those structures cannot be placed on land at all.
local function NearestWaterPosition(anchorPosition, threatPosition)
    if not anchorPosition then
        return nil
    end
    local depth = Constants.Policy.ShoreTorpedoMinimumDepth
    local limit = Constants.Policy.ShoreTorpedoProbeRadius
    local radius = 8
    while radius <= limit do
        local best, bestScore = nil, nil
        for _, direction in ipairs(ProbeDirections) do
            local x = anchorPosition[1] + direction[1] * radius
            local z = anchorPosition[3] + direction[2] * radius
            local surface = GetSurfaceHeight(x, z)
            if surface - GetTerrainHeight(x, z) >= depth then
                local candidate = { x, surface, z }
                -- Prefer the candidate nearest the threat; fall back to a
                -- stable coordinate order so the choice never drifts.
                local score = 0
                if threatPosition then
                    local sx = candidate[1] - threatPosition[1]
                    local sz = candidate[3] - threatPosition[3]
                    score = sx * sx + sz * sz
                end
                if not bestScore
                    or score < bestScore
                    or (score == bestScore and (x < best[1] or (x == best[1] and z < best[3])))
                then
                    best, bestScore = candidate, score
                end
            end
        end
        if best then
            return best
        end
        radius = radius + 8
    end
    return nil
end

local function PositionForLayer(layer, anchorPosition, threatPosition)
    if threatPosition and PositionLayer(threatPosition) == layer then
        return threatPosition
    end
    if anchorPosition and PositionLayer(anchorPosition) == layer then
        return anchorPosition
    end
    return nil
end

-- Surface layers worth trying for an offensive, most appropriate first. Hover
-- is deliberately absent: the combat manager already dispatches the hover task
-- force alongside land and naval and path-gates it on the hover graph, so hover
-- reaches what those layers cannot without an objective being sited for a force
-- that only two of the four factions field.
local OffensiveLayers = {
    Naval = { "Water", "Land" },
    Mixed = { "Land", "Water" },
    Land = { "Land" },
}

-- Objectives that are attacks. An attack in contact is worth protecting from a
-- marginal defensive reading; staging and recovery are not.
local OffensiveObjectives = {
    Pressure = true,
    Raid = true,
    JointAttack = true,
}

local function CanInterrupt(self, previous, objective, tick)
    if not previous or not previous.ExpiresTick or previous.ExpiresTick <= tick then
        return true
    end
    if objective.RequestedBy then
        return true
    end
    if objective.Type == "Defend" then
        -- A real defence always preempts: an observed cluster threatening an
        -- anchor, which is where `Critical` comes from.
        if objective.Critical then
            return true
        end
        -- The weak local-threat defence must not abandon an attack that has
        -- already arrived. Observed: an army with the strength to cripple an
        -- enemy base was recalled repeatedly and killed only a few engineers,
        -- because `LocalDefenseThreat` is 25 -- a couple of raiders at home --
        -- and any Defend used to preempt unconditionally. The objective then
        -- expired after `ObjectiveLifetimeTicks` and the attack resumed, so the
        -- army walked back and forth and never landed a blow.
        --
        -- Judged on our own strength at the destination, so the hold ends by
        -- itself as that force dies or withdraws, and an attack that never
        -- arrived is not protected at all.
        if OffensiveObjectives[previous.Type] and previous.Position then
            local committed = 0
            if self and self.GetOwnThreatNear then
                committed = self:GetOwnThreatNear(
                    previous.Position,
                    Constants.Policy.CommitmentThreatRadius
                ) or 0
            end
            if committed > 0 then
                return false
            end
        end
        return true
    end
    if previous.Type == "Stage" then
        return true
    end
    return objective.Priority >= previous.Priority + Constants.Policy.ObjectiveInterruptPriorityGap
end

-- Affordability is judged on the better of the instantaneous and the smoothed
-- income, so a rising economy is not held back by smoothing lag and a single
-- dipped sample cannot cancel a multi-minute investment decision.
local function CanAfford(state, massIncome, energyIncome)
    local mass = math.max(state.MassIncome, state.SmoothedMassIncome or 0)
    local energy = math.max(state.EnergyIncome, state.SmoothedEnergyIncome or 0)
    return not state.StallRisk
        and mass >= massIncome
        and energy >= energyIncome
end

local function BlueprintThreat(unit)
    local blueprint = unit:GetBlueprint()
    local defense = blueprint.Defense or {}
    return (defense.SurfaceThreatLevel or 0)
        + (defense.SubThreatLevel or 0)
        + (defense.AirThreatLevel or 0)
end

-- Can any weapon on this blueprint strike a target standing on `targetLayer`,
-- fired from `firingLayer`? `ranged` additionally requires the target to be
-- inside the weapon's reach, which is the right question for something that
-- shoots from where it stands and the wrong one for something that flies to
-- the fight.
local function CanStrike(blueprint, firingLayer, targetLayer, distanceSquared, ranged)
    for _, weapon in ipairs(blueprint.Weapon or {}) do
        local caps = weapon.FireTargetLayerCapsTable or {}
        local allowed = caps[firingLayer] or ""
        if string.find(allowed, targetLayer, 1, true) then
            if not ranged then
                return true
            end
            local range = weapon.MaxRadius or 0
            if distanceSquared <= range * range then
                return true
            end
        end
    end
    return false
end

-- The defenders any threat comparison is measured against. One definition, so
-- the scalar and the per-arm readings can never drift apart.
local function DefendersNear(brain, position, radius)
    if not brain.GetUnitsAroundPoint then
        return {}
    end
    local category = categories.MOBILE * (categories.LAND + categories.AIR + categories.NAVAL)
        - categories.ENGINEER
        - categories.COMMAND
        - categories.SCOUT
        + categories.STRUCTURE * categories.DEFENSE
    return brain:GetUnitsAroundPoint(category, position, radius, "Ally") or {}
end

-- What this unit can do to a surface contact standing at `target`, which sits
-- on `contactLayer`. Surface damage is the arm that has a reach constraint: a
-- gun that cannot depress to the water, or that stands out of range, is not
-- defending against a fleet.
local function SurfaceDefenseThreat(unit, target, contactLayer)
    local blueprint = unit:GetBlueprint()
    local hash = blueprint.CategoriesHash or {}
    local defense = blueprint.Defense or {}
    local antiShip = (defense.SurfaceThreatLevel or 0) + (defense.SubThreatLevel or 0)
    if hash.NAVAL then
        -- A ship already stands on the water and moves to engage; against a
        -- land contact it still has to be able to shell the shore.
        if contactLayer == "Water" then
            return antiShip
        end
        return CanStrike(blueprint, "Water", contactLayer, 0, false) and antiShip or 0
    end
    if hash.AIR then
        -- Aircraft fire from the Air layer, which is the only key their caps
        -- reliably carry, and they fly to the fight -- so weapon reach from
        -- wherever the unit happens to be now is not the question.
        --
        -- Reading SubThreatLevel alone scored every gunship and bomber zero
        -- and counted torpedo bombers only, which is how 20 gunships could sit
        -- over a destroyer group while the anchor measured friendly=0 and
        -- raised a maximum-severity alert. A UEF T2 gunship carries
        -- SurfaceThreatLevel 5 with caps "Air|Land|Water|Seabed"; an
        -- interceptor passes the same caps test on its blueprint but carries no
        -- surface or sub damage at all, so the sum keeps it out on its own
        -- rather than needing a category exception.
        return CanStrike(blueprint, "Air", contactLayer, 0, false) and antiShip or 0
    end
    local position = unit.GetPosition and unit:GetPosition()
    if not target or not position then return 0 end
    local dx, dz = target[1] - position[1], target[3] - position[3]
    local layer = PositionLayer(position)
    return CanStrike(blueprint, layer, contactLayer, dx * dx + dz * dz, true) and antiShip or 0
end

-- Land forces only defend a naval contact when a weapon can actually reach
-- its water position. Ships and naval aircraft can move to engage it.
local function NavalDefenseThreat(unit, target)
    return SurfaceDefenseThreat(unit, target, "Water")
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
        self.RecentAirLosses = {}
        self.RecentEngineerLosses = {}
        self.EngineerLossPressure = { Count = 0, Mass = 0 }
        self.RecentGarrisonLosses = {}
        self.GarrisonLossPressure = {}
        self.AirLossPressure = { Count = 0, Mass = 0 }
        self.CumulativeAirLosses = { Count = 0, Mass = 0 }
        self.CounterDoctrineUntilTick = 0
        self.GunshipRecoveryUntilTick = 0
        self.GunshipAirLossBaseline = nil
        self.LastAirDropRequestTick = -100000
        self.AirDropOpportunity = nil
        self.AirDropStatus = nil
        self.LastAirDropStatusTick = -100000
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
            DesiredEngineers = Constants.Policy.EngineersMinimum,
            EngineerLossPressure = { Count = 0, Mass = 0 },
            GarrisonLossPressure = {},
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
        local economy = blueprint.Economy or {}

        -- A unit lost while covering a forward base is recorded against that
        -- site as well as its layer. Cover has to be able to tell "this site is
        -- killing what I send" from ordinary attrition, and only the dying unit
        -- knows which site it was holding. Recorded before any category filter
        -- so the attribution cannot be lost to one.
        if unit.RedQueenGarrisonSite then
            table.insert(self.RecentGarrisonLosses, {
                Tick = GetGameTick(),
                Mass = economy.BuildCostMass or 1,
                Site = unit.RedQueenGarrisonSite,
            })
        end

        -- An engineer death is not a combat casualty and must not inflate land
        -- loss pressure, but it is the most expensive kind of loss to ignore:
        -- it stalls expansion, economy and production together. Tracked in its
        -- own window so production can answer it directly.
        if hash.MOBILE and hash.ENGINEER and not hash.COMMAND then
            table.insert(self.RecentEngineerLosses, {
                Tick = GetGameTick(),
                Mass = economy.BuildCostMass or 1,
            })
            -- Remember the ground that killed it. Without this the replacement
            -- is posted straight back to the same place, which is the loop the
            -- survival work exists to break.
            if unit.GetPosition then
                EngineerSurvival.RememberLethalSite(
                    self.Brain, unit:GetPosition(), "engineer-lost")
            end
            return
        end

        if not hash.MOBILE
            or hash.ENGINEER
            or hash.COMMAND
            or hash.SCOUT
            or hash.TRANSPORTFOCUS
        then
            return
        end

        local loss = { Tick = GetGameTick(), Mass = economy.BuildCostMass or 1 }
        if hash.LAND or hash.AMPHIBIOUS or hash.HOVER then
            table.insert(self.RecentLandLosses, loss)
        elseif hash.AIR then
            table.insert(self.RecentAirLosses, loss)
            self.CumulativeAirLosses.Count = self.CumulativeAirLosses.Count + 1
            self.CumulativeAirLosses.Mass = self.CumulativeAirLosses.Mass + loss.Mass
        end
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

    -- How many engineers this army should have, on the same footing as factory
    -- capacity rather than a fixed floor.
    --
    -- Three terms. The base need scales with the production it has to keep fed,
    -- because an idle factory and an unbuilt extractor cost the same either
    -- way. The expansion term is the engineers the forward-base plan actually
    -- needs, so "I am expanding" is a stated requirement rather than a hope.
    -- The replacement buffer is the one that stops a flatline: while losses
    -- are still inside the window every engineer lost is queued again, times a
    -- factor above one, so the army deliberately runs a surplus exactly while
    -- it is bleeding and can afford the next loss without stalling.
    --
    -- The buffer decays on its own as losses age out of the window, so a quiet
    -- stretch returns the target to its structural need without anything
    -- having to cancel it.
    UpdateEngineerDemand = function(self)
        local demand = self.ProductionDemand
        local pressure = self:UpdateEngineerLossPressure()
        local production = self.Modules and self.Modules.Production
        local counts = production and production.Counts or nil
        local factories = counts and counts.Total or 0
        local economy = self.Economy and self.Economy.State or {}

        -- Fall back to planned capacity before any factory exists, so the
        -- opening still asks for the engineers that will build it.
        local feeding = math.max(factories, economy.DesiredFactories or 0)
        local base = feeding * Constants.Policy.EngineersPerFactory

        local plan = demand.ForwardBasePlan or {}
        local expanding = plan.Active and 1 or 0
        local expansion = expanding * Constants.Policy.EngineersPerForwardBase

        local replacements = pressure.Count
            * Constants.Policy.EngineerLossReplacementFactor

        demand.EngineerLossPressure = pressure
        demand.DesiredEngineers = math.max(
            Constants.Policy.EngineersMinimum,
            math.min(
                Constants.Policy.EngineersMaximum,
                math.ceil(base + expansion + replacements)
            )
        )
        return demand.DesiredEngineers
    end,

    UpdateEngineerLossPressure = function(self)
        local cutoff = GetGameTick() - Constants.Policy.EngineerLossWindowSeconds * 10
        local count = 0
        local mass = 0

        for index = table.getn(self.RecentEngineerLosses), 1, -1 do
            local loss = self.RecentEngineerLosses[index]
            if loss.Tick < cutoff then
                table.remove(self.RecentEngineerLosses, index)
            else
                count = count + 1
                mass = mass + loss.Mass
            end
        end

        self.EngineerLossPressure = { Count = count, Mass = mass }
        return self.EngineerLossPressure
    end,

    -- Garrison losses within the window, per site.
    UpdateGarrisonLossPressure = function(self)
        local cutoff = GetGameTick() - Constants.Policy.GarrisonLossWindowSeconds * 10
        local pressure = {}

        for index = table.getn(self.RecentGarrisonLosses), 1, -1 do
            local loss = self.RecentGarrisonLosses[index]
            if loss.Tick < cutoff then
                table.remove(self.RecentGarrisonLosses, index)
            else
                local site = pressure[loss.Site] or { Count = 0, Mass = 0 }
                site.Count = site.Count + 1
                site.Mass = site.Mass + loss.Mass
                pressure[loss.Site] = site
            end
        end

        self.GarrisonLossPressure = pressure
        self.ProductionDemand.GarrisonLossPressure = pressure
        return pressure
    end,

    UpdateAirLossPressure = function(self)
        local cutoff = GetGameTick() - Constants.Policy.AirLossWindowSeconds * 10
        local count = 0
        local mass = 0

        for index = table.getn(self.RecentAirLosses), 1, -1 do
            local loss = self.RecentAirLosses[index]
            if loss.Tick < cutoff then
                table.remove(self.RecentAirLosses, index)
            else
                count = count + 1
                mass = mass + loss.Mass
            end
        end

        self.AirLossPressure = { Count = count, Mass = mass }
        return self.AirLossPressure
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

    GetAnchorCriticality = function(self, kind)
        if kind == "Commander" then
            if self.Context.VictoryCondition == "Assassination" then
                return Constants.Policy.CommanderAssassinationCriticality
            elseif self.Context.VictoryCondition == "Annihilation" then
                return Constants.Policy.CommanderAnnihilationCriticality
            end
            return Constants.Policy.CommanderSupremacyCriticality
        elseif kind == "MainBase" then
            return Constants.Policy.MainBaseCriticality
        elseif kind == "ForwardBase" then
            return Constants.Policy.ForwardBaseCriticality
        elseif kind == "NavalBase" then
            return Constants.Policy.NavalBaseCriticality
        end
        return Constants.Policy.ExpansionCriticality
    end,

    MakeAnchor = function(self, position, kind, locationType)
        return {
            Position = position,
            Kind = kind,
            Layer = PositionLayer(position),
            LocationType = locationType,
            Criticality = self:GetAnchorCriticality(kind),
        }
    end,

    GetProtectedAnchors = function(self)
        local anchors = {
            self:MakeAnchor(self.World.StartPosition, "MainBase", "MAIN"),
        }
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
                local kind = "Expansion"
                if locationType == "MAIN" then
                    kind = "MainBase"
                elseif string.sub(locationType, 1, 5) == "RQFB_" then
                    kind = "ForwardBase"
                elseif PositionLayer(position) == "Water" then
                    kind = "NavalBase"
                end
                table.insert(anchors, self:MakeAnchor(position, kind, locationType))
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
                        table.insert(anchors, self:MakeAnchor(
                            position,
                            "Commander",
                            commander.BuilderManagerData
                                and commander.BuilderManagerData.LocationType
                        ))
                    end
                end
            end
        end
        return anchors
    end,

    GetOwnThreatNear = function(self, position, radius, layer, target)
        local threat = 0
        for _, unit in pairs(DefendersNear(self.Brain, position, radius)) do
            if unit and not unit.Dead then
                threat = threat + (layer == "Water" and NavalDefenseThreat(unit, target) or BlueprintThreat(unit))
            end
        end
        return threat
    end,

    -- Friendly threat near `position`, split by the arm that can answer it.
    --
    -- Every cluster already reports Land, Naval and Air separately while this
    -- reading was a single sum, so an AA tower counted as an answer to a tank
    -- and a point defence counted as an answer to a bomber. Splitting the
    -- denominator the same way the numerator is split is what lets each arm be
    -- judged against the defence that can actually reach it. See
    -- docs/threat-accounting-plan.md; this has no caller yet.
    --
    -- Anti-air carries no reach test. AirThreatLevel is already the engine's
    -- own statement that the unit answers aircraft, and an aircraft comes to
    -- it; a tower that has to be flown over is still defending.
    GetOwnThreatByArm = function(self, position, radius, target)
        local contactLayer = target and PositionLayer(target) or "Land"
        local arms = { Surface = 0, Air = 0 }
        for _, unit in pairs(DefendersNear(self.Brain, position, radius)) do
            if unit and not unit.Dead then
                local defense = unit:GetBlueprint().Defense or {}
                arms.Air = arms.Air + (defense.AirThreatLevel or 0)
                arms.Surface = arms.Surface + SurfaceDefenseThreat(unit, target, contactLayer)
            end
        end
        return arms
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
        if self.Trace and table.getn(clusters) == 0 then
            self.Trace:Safe(self.Trace.Observe, "defense", "clusters", "rejected", "reason=no-observed-cluster")
        end

        for _, cluster in pairs(clusters) do
            local anchor = anchors[cluster.AnchorIndex or 1] or self.World.StartPosition
            local anchorPosition = anchor.Position or anchor
            local anchorKind = anchor.Kind or "Base"
            local anchorLayer = anchor.Layer or PositionLayer(anchorPosition)
            local criticality = anchor.Criticality or 1
            -- Judge each arm against the defence that can actually answer it,
            -- and the combined force against the whole of it. A single
            -- undifferentiated sum could not: an AA tower counted as an answer
            -- to a tank, a point defence as an answer to a bomber, and on the
            -- water view the sum collapsed to nothing at all, so one frigate
            -- escorting an air raid erased a base's entire air defence.
            -- See docs/threat-accounting-plan.md.
            --
            -- Three tests rather than two, deliberately. Per-arm gating alone
            -- stops a combined-arms push registering at all, because 30 of land
            -- beside 30 of air clears no single arm's magnitude floor. A total
            -- magnitude gate alone lets a six-mass frigate with nothing to
            -- answer it raise a massive alert, which is the defect finding 5
            -- closed. The combined row catches the first; keeping a magnitude
            -- floor on each arm keeps the second out.
            local radius = math.max(60, self.World.Width / 12)
            local own = self:GetOwnThreatByArm(anchorPosition, radius, cluster.Position)
            local ownThreat = own.Surface + own.Air
            -- Back-filled the same way the role sizing below back-fills it.
            local surfaceContact = (cluster.Land or 0) + (cluster.Naval or 0)
            if cluster.Land == nil and cluster.Naval == nil then
                surfaceContact = cluster.Surface or 0
            end
            local arms = {
                {
                    Name = "surface",
                    Contact = surfaceContact,
                    Ratio = surfaceContact / math.max(1, own.Surface),
                },
                {
                    Name = "air",
                    Contact = cluster.Air or 0,
                    Ratio = (cluster.Air or 0) / math.max(1, own.Air),
                },
                {
                    Name = "combined",
                    Contact = cluster.Threat or 0,
                    Ratio = (cluster.Threat or 0) / math.max(1, ownThreat),
                },
            }
            -- The strongest arm clearing both its magnitude floor and the ratio
            -- asked of it. Severity follows the arm that actually qualified and
            -- never a louder one that did not: a token air force over an anchor
            -- with no anti-air produces an enormous ratio, and must not be what
            -- sets the severity of a land attack.
            local function Qualifying(threshold, floor)
                local best = nil
                for _, arm in ipairs(arms) do
                    if arm.Contact >= threshold
                        and arm.Ratio >= floor
                        and (not best or arm.Ratio > best.Ratio)
                    then
                        best = arm
                    end
                end
                return best
            end

            local massiveArm = Qualifying(
                Constants.Policy.MassiveArmyThreat,
                Constants.Policy.MassiveArmyThreatRatio
            )
            local pressureArm = Qualifying(Constants.Policy.PressureEscalationThreat, 1)
            local commanderArm = anchorKind == "Commander"
                and Qualifying(
                    Constants.Policy.CommanderEmergencyThreat,
                    Constants.Policy.CommanderEmergencyThreatRatio
                )
                or nil

            local massive = massiveArm ~= nil
            local pressure = pressureArm ~= nil
                and cluster.Approaching
                and momentum.Losing
            local commanderEmergency = commanderArm ~= nil
                and (cluster.Approaching
                    or cluster.DistanceToAnchor <= Constants.Policy.CommanderEmergencyDistance)

            local qualified = nil
            if massive then qualified = massiveArm end
            if pressure and (not qualified or pressureArm.Ratio > qualified.Ratio) then
                qualified = pressureArm
            end
            if commanderEmergency and (not qualified or commanderArm.Ratio > qualified.Ratio) then
                qualified = commanderArm
            end
            local qualifiedArm = qualified and qualified.Name or "none"
            local ratio = qualified and qualified.Ratio
                or math.max(arms[1].Ratio, arms[2].Ratio, arms[3].Ratio)
            local facing = qualified and qualified.Contact or (cluster.Threat or 0)

            if self.Trace then
                local reason = (massive or pressure or commanderEmergency) and "qualified"
                    or ratio < 1 and "strength-ratio" or not cluster.Approaching and "approach" or "threat-threshold"
                self.Trace:Safe(self.Trace.Observe, "defense", cluster.FirstEntityId or "unknown", reason,
                    string.format("reason=%s anchor=%s anchorLayer=%s arm=%s land=%.1f naval=%.1f air=%.1f threat=%.1f facing=%.1f friendly=%.1f surface=%.1f antiair=%.1f ratio=%.2f approaching=%s",
                        reason, anchorKind, anchorLayer, qualifiedArm, cluster.Land or 0, cluster.Naval or 0, cluster.Air or 0,
                        cluster.Threat, facing, ownThreat, own.Surface, own.Air, ratio, tostring(cluster.Approaching)))
            end
            if massive or pressure or commanderEmergency then
                local land = cluster.Land
                local naval = cluster.Naval
                if land == nil and naval == nil then
                    if anchorLayer == "Water" then
                        land = 0
                        naval = cluster.Surface or 0
                    else
                        land = cluster.Surface or 0
                        naval = 0
                    end
                end
                land = land or 0
                naval = naval or 0
                local air = cluster.Air or 0
                local surface = cluster.Surface or 0
                -- Derived from the normalised figures above, not from
                -- cluster.Surface: that field is raw, so a cluster reporting
                -- only Land/Naval leaves it zero and every role keyed on it
                -- would silently evaluate to nothing.
                local surfaceThreat = land + naval
                -- Torpedo defences answer ships we have actually seen.
                --
                -- cluster.Naval is only ever set from layer-bucketed
                -- observations, and observation confidence decays to zero as a
                -- contact goes stale, so a non-nil value means scouts or units
                -- are seeing ships now. The back-fill above deliberately treats
                -- unclassified surface threat near a water anchor as naval --
                -- fine for choosing which task force defends, but not for
                -- committing mass to structures that shoot nothing else. An
                -- unscouted contact must build no torpedo launchers.
                local observedNaval = cluster.Naval or 0
                local navalObserved =
                    observedNaval >= Constants.Policy.TorpedoMinimumObservedNavalThreat
                -- Water within reach of the anchor, biased toward the threat.
                -- Torpedo launchers are water-only structures, so this is both
                -- the gate on whether they can be built at all and the position
                -- they are built at. An inland anchor yields nil and raises no
                -- torpedo target, which keeps the build path off dry land.
                local waterPosition = navalObserved
                    and NearestWaterPosition(anchorPosition, cluster.Position)
                    or nil
                -- With no observed surface threat the anchor's own layer decides
                -- how its defenders should be organized.
                local primaryLayer
                if land <= 0 and naval <= 0 then
                    primaryLayer = anchorLayer == "Water" and "Water" or "Land"
                else
                    primaryLayer = land >= naval and "Land" or "Water"
                end
                local candidate = {
                    Active = true,
                    Position = cluster.Position,
                    AnchorPosition = anchorPosition,
                    AnchorKind = anchorKind,
                    AnchorLayer = anchorLayer,
                    AnchorLocationType = anchor.LocationType,
                    Criticality = criticality,
                    PrimaryLayer = primaryLayer,
                    Threat = cluster.Threat,
                    Land = land,
                    Naval = naval,
                    Surface = surface,
                    Air = air,
                    FriendlyThreat = ownThreat,
                    FriendlySurface = own.Surface,
                    FriendlyAir = own.Air,
                    QualifiedArm = qualifiedArm,
                    Ratio = ratio,
                    Count = cluster.Count,
                    Approaching = cluster.Approaching,
                    DistanceToAnchor = cluster.DistanceToAnchor,
                    FirstEntityId = cluster.FirstEntityId,
                    Losing = momentum.Losing,
                    LostMass = momentum.LostMass,
                    DestroyedMass = momentum.DestroyedMass,
                    Severity = math.max(1, ratio) * criticality,
                    Targets = {
                        -- Point defence and tactical missiles both engage ships
                        -- as well as ground, so they answer the whole surface
                        -- threat. Keying them on `land` alone meant a fleet
                        -- shelling the base produced a target of zero and no
                        -- defence was built at all. On a land map `naval` is 0,
                        -- so these are unchanged there.
                        Ground = surfaceThreat > 0
                            and math.max(4, math.min(12, math.ceil(surfaceThreat / 12))) or 0,
                        AntiAir = air > 0 and math.max(2, math.min(8, math.ceil(air / 10))) or 0,
                        Shields = (ratio >= 2 or cluster.DistanceToAnchor <= 60) and 2 or 1,
                        StrategicMissileDefense = 1,
                        TacticalMissiles = surfaceThreat > 0 and 2 or 0,
                        -- Artillery covers the standoff band nothing else can:
                        -- point defence reaches 26 (T1) or 50 (T2) and torpedo
                        -- launchers 50 to 60, while a destroyer bombards from
                        -- 60 to 80. T2 artillery reaches 115. Its 50 minimum is
                        -- a dead zone around the gun, not around the base, so
                        -- placement is offset away from the threat axis --
                        -- see ProductionManager:ShoreArtilleryPosition.
                        --
                        -- What the threat would justify. Whether any of it is
                        -- affordable is decided in production: artillery is a
                        -- late supplement, never a first response, so
                        -- UpdateShoreArtillery holds it behind the anchor's
                        -- primary point defence and an economic ladder. Keying
                        -- it here on surface threat alone once put eight
                        -- batteries on a 0%-water map and turned a controlled
                        -- Sentry Point win (K/L 1.43) into a defeat (1.00).
                        Artillery = surfaceThreat > 0
                            and math.max(1, math.min(4, math.ceil(surfaceThreat / 25))) or 0,
                        -- Only ships, and only from water. A larger divisor
                        -- than point defence because a launcher is individually
                        -- stronger against the one thing it shoots at, and
                        -- costs more than a Tech 2 point defence to build.
                        Torpedo = (navalObserved and waterPosition)
                            and math.max(2, math.min(8, math.ceil(observedNaval / 14))) or 0,
                    },
                    -- Where an anti-navy structure can be founded, and the
                    -- observed naval threat that justified looking. Both are
                    -- nil/zero unless ships were actually seen: the probe only
                    -- runs for an observed contact, so this is never a claim
                    -- about terrain on its own.
                    WaterPosition = waterPosition,
                    ObservedNaval = observedNaval,
                    CreatedTick = previous.Active and previous.CreatedTick or tick,
                    ExpiresTick = tick + Constants.Policy.DefenseAlertHoldSeconds * 10,
                }
                if not alert.Active
                    or candidate.Severity > alert.Severity
                    or (
                        candidate.Severity == alert.Severity
                        and candidate.DistanceToAnchor < alert.DistanceToAnchor
                    )
                    or (
                        candidate.Severity == alert.Severity
                        and candidate.DistanceToAnchor == alert.DistanceToAnchor
                        and candidate.Threat > alert.Threat
                    )
                    or (
                        candidate.Severity == alert.Severity
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
                "defense alert started anchor=%s layer=%s threat=%.1f friendly=%.1f ratio=%.2f approaching=%s losses=%.0f/%.0f",
                tostring(alert.AnchorKind),
                tostring(alert.PrimaryLayer),
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
        elseif previous and objective and not CanInterrupt(self, previous, objective, tick) then
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

    -- How far this army's income sits above the endgame gate, as 0 at the gate
    -- and 1 at `EndgameWealthMultiple` times it.
    --
    -- Distinct from readiness, and the distinction is the whole point.
    -- Readiness is *headroom* -- income minus what is already requested -- so
    -- an army that spends what it earns reads as unready however rich it is.
    -- Measured across the matrix, armies on 30-70 mass income held an
    -- experimental weight of 10-20 against a threshold of 35 and crossed it in
    -- 1 to 5 samples out of 45 to 98, building 2 experimentals across 21 full
    -- matches. The one cell that crossed 13 times was the one that built
    -- anything. Committing only when income is idle means never committing.
    --
    -- Keyed on income and never on elapsed time: relief is earned, not waited
    -- for.
    GetEconomicWealth = function(self)
        local state = self.Economy.State or {}
        local gate = Constants.Policy.ExperimentalMinimumMassIncome
        local multiple = Constants.Policy.EndgameWealthMultiple
        return Clamp(
            ((state.MassIncome or 0) / gate - 1) / math.max(0.01, multiple - 1),
            0,
            1
        )
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
            ExperimentalsUnderConstruction = 0,
            NukesUnderConstruction = 0,
        }
        if not self.Brain.GetCurrentUnits or not categories then
            return result
        end

        local function Count(category)
            return self.Brain:GetCurrentUnits(category) or 0
        end

        -- Incomplete units only. GetCurrentUnits counts finished ones too, and
        -- a finished experimental must not keep asserting demand forever.
        local function CountUnderConstruction(category)
            if not self.Brain.GetListOfUnits then
                return 0
            end
            local units = self.Brain:GetListOfUnits(category, false, false) or {}
            local count = 0
            for _, unit in pairs(units) do
                if unit.GetFractionComplete and unit:GetFractionComplete() < 1 then
                    count = count + 1
                end
            end
            return count
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
        result.ExperimentalsUnderConstruction = CountUnderConstruction(categories.EXPERIMENTAL)
        result.NukesUnderConstruction = CountUnderConstruction(
            categories.NUKE * categories.STRUCTURE
        )

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

        local demand = self.ProductionDemand
        local current = demand.PrimaryFocus or "Army"
        local currentScore = weights[current] or 0

        -- Downward hysteresis. An experimental or a nuclear launcher takes
        -- minutes to build, so an endgame focus must hold for a dwell period
        -- before it is abandoned for army or tier production. Without it the
        -- focus tracked every several-second swing in alert state and no
        -- project ever finished. Trading one endgame focus for the other is a
        -- genuine strategic re-evaluation, not flapping, so it stays free.
        local function IsEndgame(focus)
            return focus == "Experimental" or focus == "Nuke"
        end
        if IsEndgame(current) and not IsEndgame(best) then
            local since = GetGameTick() - (demand.PrimaryFocusTick or 0)
            if currentScore > 0
                and since < Constants.Policy.StrategicFocusDwellSeconds * 10
            then
                return current
            end
        end

        if currentScore < Constants.Policy.StrategicFocusMinimumScore
            or weights[best] >= currentScore + Constants.Policy.StrategicFocusSwitchMargin
        then
            if best ~= current then
                demand.PrimaryFocusTick = GetGameTick()
            end
            return best
        end
        return current
    end,

    UpdateStrategicFocus = function(self, objective, loss, surfaceThreat, airThreat)
        local demand = self.ProductionDemand
        local state = self.Economy.State
        local readiness = self:GetEconomicReadiness()
        -- A rich army commits whether or not its income is idle; see
        -- GetEconomicWealth for what this measures and why readiness cannot.
        local wealth = self:GetEconomicWealth()
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

        -- Tech 3 is deliberately not gated on baseDanger. Local threat is the
        -- normal condition of a contested midgame, and vetoing tier investment
        -- whenever it appears is what left match 27741743 building 925 Tech 1
        -- units against 669 Tech 3 across 73 minutes.
        local tech3 = 0
        if forces.T2Factories > 0
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
            experimental = 10 + readiness * 30 + wealth * 30
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
            nuke = 10 + readiness * 30 + wealth * 30
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
        -- Nuclear siege keeps the readiness-derived allowance it was measured
        -- with. The experimental branch below raises the shared concurrency, and
        -- letting that silently raise the nuke target too would change a
        -- behaviour nothing here has measured.
        local nukeProjectSlots = demand.MajorProjectSlots

        -- Experimental volume is a flow, not a stock: keep one or two in
        -- production continuously once the economy carries them.
        --
        -- The old expression was a stock target tied to the concurrency slots,
        -- and it could only ever be 1 -- the second slot needed army weight
        -- below 70, which never happened in twenty recorded matches. Replacing
        -- it with a bigger stock target was worse, not better: it started three
        -- projects at once while the count was low, and Aeon lost all three of
        -- its measured comparisons.
        --
        -- So the concurrency budget is the only brake, and the owned count is
        -- added into the target rather than capping it -- owning four is not a
        -- reason to stop building.
        demand.DesiredExperimentals = 0
        if weights.Experimental >= Constants.Policy.StrategicFocusMinimumScore then
            local concurrent = 1
            if (state.MassIncome or 0) >= Constants.Policy.ExperimentalSecondProjectMassIncome then
                concurrent = Constants.Policy.ExperimentalConcurrentMaximum
            end
            demand.MajorProjectSlots = math.max(demand.MajorProjectSlots, concurrent)
            demand.DesiredExperimentals = (forces.Experimentals or 0) + concurrent
        end
        demand.DesiredNukes = weights.Nuke >= Constants.Policy.StrategicFocusMinimumScore
            and (weights.Nuke >= 75 and nukeProjectSlots or 1)
            or 0

        local defenseAlert = self.DefenseAlert or { Active = false }
        if defenseAlert.Active then
            -- Only a credible attack on the commander in Assassination is an
            -- absolute veto: losing the ACU ends the match, so nothing else is
            -- worth starting. Every other alert taxes endgame investment in
            -- proportion to how badly the anchor is outmatched, rather than
            -- zeroing it. The old binary veto held army 6 of match 27741743 at
            -- zero experimental weight for all thirty of its alert samples
            -- while it sat on 41-67 mass income, so it finished no project at
            -- all across a 69-minute game.
            local commanderEmergency = defenseAlert.AnchorKind == "Commander"
                and self.Context.VictoryCondition == "Assassination"
            weights.Army = 100
            demand.PrimaryFocus = "Army"
            if commanderEmergency then
                weights.Tech3 = 0
                weights.Experimental = 0
                weights.Nuke = 0
                demand.MajorProjectSlots = 0
                demand.DesiredExperimentals = 0
                demand.DesiredNukes = 0
                demand.FocusReason = "commander-emergency"
            else
                local severityRetention = math.max(
                    Constants.Policy.DefenseAlertMinimumEndgameRetention,
                    1 - (math.max(1, defenseAlert.Severity or 1) - 1)
                        * Constants.Policy.DefenseAlertEndgameTaxPerSeverity
                )
                -- Wealth lifts the tax. An army whose income is far above the
                -- endgame gate can fund a project and its defence at the same
                -- time, so severity alone must not price it out of the game it
                -- is trying to win. Crossfire Canal held weight 20 against a
                -- threshold of 35 while sitting on 66 mass income, and spent
                -- that economy on 101 engineers instead.
                --
                -- Keyed on economy and never on elapsed time, so relief has to
                -- be earned rather than waited for.
                local wealth = self:GetEconomicWealth()
                local retention = severityRetention
                    + (1 - severityRetention) * wealth
                weights.Experimental = Score(weights.Experimental * retention)
                weights.Nuke = Score(weights.Nuke * retention)
                -- A poor army under attack still runs one project at a time; a
                -- rich one keeps its normal concurrency, because holding it to
                -- one is what made a developed economy unable to close a game.
                local pressuredSlots = 1 + math.floor(
                    wealth * (Constants.Policy.ExperimentalConcurrentMaximum - 1)
                )
                demand.MajorProjectSlots = math.min(
                    demand.MajorProjectSlots,
                    math.max(weights.Experimental, weights.Nuke)
                        >= Constants.Policy.StrategicFocusMinimumScore
                        and pressuredSlots
                        or 0
                )
                demand.DesiredExperimentals = weights.Experimental
                    >= Constants.Policy.StrategicFocusMinimumScore
                    and math.min(demand.DesiredExperimentals,
                        (forces.Experimentals or 0) + pressuredSlots)
                    or 0
                demand.DesiredNukes = weights.Nuke
                    >= Constants.Policy.StrategicFocusMinimumScore
                    and math.min(demand.DesiredNukes, pressuredSlots)
                    or 0
                demand.WealthRetention = retention
                demand.FocusReason = wealth >= 1 and "defense-pressure-funded"
                    or "defense-pressure"
            end
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

        -- A pause gates new starts, never work already under way. Withdrawing
        -- the target from a half-built experimental strands its engineers and
        -- wastes everything already spent, which is how match 27741743 built
        -- four experimentals in 73 minutes while flipping the target between
        -- zero and two every few seconds.
        demand.DesiredExperimentals = math.max(
            demand.DesiredExperimentals,
            forces.ExperimentalsUnderConstruction or 0
        )
        demand.DesiredNukes = math.max(
            demand.DesiredNukes,
            forces.NukesUnderConstruction or 0
        )
        -- Slots are a concurrency budget, so work in flight consumes one each.
        -- Taking the maximum rather than the sum would leave an experimental
        -- and a nuclear launcher sharing a single slot.
        demand.MajorProjectSlots = math.max(
            demand.MajorProjectSlots,
            (forces.ExperimentalsUnderConstruction or 0)
                + (forces.NukesUnderConstruction or 0)
        )
    end,

    UpdateDemand = function(self, objective)
        local threat = self.Intel.Threat
        local demand = self.ProductionDemand
        local previousDoctrine = demand.Doctrine
        -- Scout production follows how much of what matters is unseen, not
        -- whether any observation exists at all.
        --
        -- The old rule asked for 15% while the army had seen nothing and 7%
        -- forever after, so a single sighting anywhere on the map counted as
        -- being informed. Coverage is what the commitment gate actually depends
        -- on: a wave judged against an unobserved destination is judged against
        -- a threat of zero. So the fraction scales with the share of positions
        -- the army cares about and cannot see, and falls away on its own once
        -- it can see them.
        local blindShare = 0
        if self.Modules and self.Modules.Combat then
            local summary = self.Modules.Combat.ScoutSummary
            if summary and (summary.Targets or 0) > 0 then
                blindShare = (summary.Blind or 0) / summary.Targets
            end
        end
        local scouting = self.Brain.RedQueenScouting
        if scouting and not scouting.AdaptiveProduction then
            -- The dispatch-only arm restores the exact pre-scouting rule.
            demand.Scouts = table.getsize(self.Intel.Observations) == 0 and 0.15 or 0.07
        else
            demand.Scouts = Clamp(
                Constants.Policy.ScoutFractionMinimum
                    + blindShare
                        * (Constants.Policy.ScoutFractionMaximum
                            - Constants.Policy.ScoutFractionMinimum),
                Constants.Policy.ScoutFractionMinimum,
                Constants.Policy.ScoutFractionMaximum
            )
        end
        demand.ScoutBlindShare = blindShare
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
        -- Prunes the reported air-loss window; the gunship decision below uses
        -- its own baseline so that losses predating the doctrine never count.
        self:UpdateAirLossPressure()
        self:UpdateGarrisonLossPressure()
        self:UpdateEngineerDemand()
        local lossesDemandCounter = loss.Count >= Constants.Policy.LandLossCountThreshold
            or loss.Mass >= Constants.Policy.LandLossMassThreshold
        local airDefenseIsExposed = airThreat <= math.max(
            Constants.Policy.AirDropMaximumAirThreat,
            surfaceThreat * Constants.Policy.GunshipAirThreatRatio
        )
        local tick = GetGameTick()

        local gunshipLoss = { Count = 0, Mass = 0 }
        if previousDoctrine == "GunshipCounter" and self.GunshipAirLossBaseline then
            gunshipLoss.Count = self.CumulativeAirLosses.Count
                - self.GunshipAirLossBaseline.Count
            gunshipLoss.Mass = self.CumulativeAirLosses.Mass
                - self.GunshipAirLossBaseline.Mass
        end
        local gunshipFailure = previousDoctrine == "GunshipCounter"
            and (gunshipLoss.Count >= Constants.Policy.AirLossCountThreshold
                or gunshipLoss.Mass >= Constants.Policy.AirLossMassThreshold)
        if gunshipFailure and tick >= self.GunshipRecoveryUntilTick then
            self.GunshipRecoveryUntilTick = tick
                + Constants.Policy.GunshipRecoverySeconds * 10
            self.CounterDoctrineUntilTick = 0
            Logger.Info(self.Brain, string.format(
                "gunship counter abandoned airloss=%d/%.0f",
                gunshipLoss.Count,
                gunshipLoss.Mass
            ))
        end

        if lossesDemandCounter
            and airDefenseIsExposed
            and tick >= self.GunshipRecoveryUntilTick
        then
            self.CounterDoctrineUntilTick = tick + Constants.Policy.CounterDoctrineSeconds * 10
        end

        if tick < self.GunshipRecoveryUntilTick then
            if airThreat > 10 and airThreat > surfaceThreat * 0.75 then
                demand.Doctrine = "AirDefense"
                demand.AntiAir = 0.45
                demand.Air = math.max(demand.Air, 0.45)
            end
        elseif tick < self.CounterDoctrineUntilTick
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

        if demand.Doctrine == "GunshipCounter" then
            -- The baseline is re-snapshot once its window expires, so the
            -- thresholds mean "this many losses inside AirLossWindowSeconds
            -- while the doctrine is active" rather than "this many ever".
            local baseline = self.GunshipAirLossBaseline
            if previousDoctrine ~= "GunshipCounter"
                or not baseline
                or tick - baseline.Tick >= Constants.Policy.AirLossWindowSeconds * 10
            then
                self.GunshipAirLossBaseline = {
                    Count = self.CumulativeAirLosses.Count,
                    Mass = self.CumulativeAirLosses.Mass,
                    Tick = tick,
                }
            end
        else
            self.GunshipAirLossBaseline = nil
        end

        self:UpdateStrategicFocus(objective, loss, surfaceThreat, airThreat)
    end,

    SetAirDropStatus = function(self, state, opportunity, transports, reason)
        local tick = GetGameTick()
        local previous = self.AirDropStatus
        local target = opportunity and opportunity.EntityId
            or previous and previous.Target
        local changed = not previous
            or previous.State ~= state
            or previous.Target ~= target
        self.AirDropStatus = {
            State = state,
            Target = target,
            Transports = transports or 0,
            Reason = reason,
            UpdatedTick = tick,
        }
        if changed or tick - self.LastAirDropStatusTick
            >= Constants.Policy.AirDropDiagnosticSeconds * 10
        then
            self.LastAirDropStatusTick = tick
            Logger.Info(self.Brain, string.format(
                "airdrop state=%s target=%s transports=%d reason=%s",
                state,
                tostring(target or "none"),
                transports or 0,
                tostring(reason or "none")
            ))
        end
    end,

    UpdateAirDropOpportunity = function(self, start)
        self.AirDropOpportunity = nil
        if self.DefenseAlert and self.DefenseAlert.Active then
            if self.AirDropStatus and self.AirDropStatus.State ~= "Abandoned" then
                self:SetAirDropStatus("Abandoned", nil, 0, "defense-alert")
            end
            return nil
        end
        if not self.Intel.GetBestExposedEconomyTarget then
            self:SetAirDropStatus("Unavailable", nil, 0, "no-intel-provider")
            return nil
        end

        local opportunity = self.Intel:GetBestExposedEconomyTarget(start)
        self.AirDropOpportunity = opportunity
        if not opportunity then
            if self.AirDropStatus
                and self.AirDropStatus.State ~= "Expired"
                and self.AirDropStatus.State ~= "Unavailable"
            then
                self:SetAirDropStatus("Expired", nil, 0, "target-lost")
            end
            return nil
        end

        local tick = GetGameTick()
        local cooldown = Constants.Policy.AirDropRequestCooldownSeconds * 10
        local transports = 0
        if self.Brain.GetCurrentUnits and categories and categories.TRANSPORTFOCUS then
            transports = self.Brain:GetCurrentUnits(categories.TRANSPORTFOCUS)
        end

        local activeTransports = 0
        if transports > 0 and self.Brain.GetListOfUnits then
            local transportUnits = self.Brain:GetListOfUnits(categories.TRANSPORTFOCUS, false) or {}
            for _, transport in pairs(transportUnits) do
                if transport and not transport.Dead
                    and (transport.InUse
                        or (transport.IsIdleState and not transport:IsIdleState()))
                then
                    activeTransports = activeTransports + 1
                end
            end
        end

        if transports < Constants.Policy.MaximumAirDropTransports
            and not self.Brain.TransportRequested
            and tick - self.LastAirDropRequestTick >= cooldown
        then
            self.Brain.TransportRequested = true
            self.LastAirDropRequestTick = tick
            self:SetAirDropStatus("Requested", opportunity, transports, "transport-capacity")
        elseif activeTransports > 0 then
            self:SetAirDropStatus("TransportActive", opportunity, transports, "transport-in-use")
        elseif transports > 0 then
            self:SetAirDropStatus("Ready", opportunity, transports, "transport-available")
        elseif not self.AirDropStatus
            or self.AirDropStatus.Target ~= opportunity.EntityId
            or self.AirDropStatus.State == "Expired"
            or self.AirDropStatus.State == "Abandoned"
            or self.AirDropStatus.State == "Unavailable"
        then
            self:SetAirDropStatus("Opportunity", opportunity, transports, "awaiting-request")
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
            local landPosition = PositionForLayer(
                "Land",
                defenseAlert.AnchorPosition,
                defenseAlert.Position
            )
            local waterPosition = PositionForLayer(
                "Water",
                defenseAlert.AnchorPosition,
                defenseAlert.Position
            )
            -- Held positions for layers the enemy is not currently attacking on.
            local landAnchor = PositionForLayer("Land", defenseAlert.AnchorPosition)
            local waterAnchor = PositionForLayer("Water", defenseAlert.AnchorPosition)
            objective = {
                Type = "Defend",
                Position = defenseAlert.AnchorPosition,
                ThreatPosition = defenseAlert.Position,
                Layer = defenseAlert.PrimaryLayer,
                -- Observed enemy layers decide where each of our task forces
                -- intercepts, never whether it defends at all: a layer with a
                -- reachable destination always receives an order, falling back
                -- to the threatened anchor. Otherwise a single-layer attack
                -- leaves whole task forces idle in the ArmyPool.
                DefenseLayers = {
                    Land = landPosition ~= nil,
                    Water = waterPosition ~= nil,
                    Amphibious = true,
                    -- Hover is a distinct navigation graph from amphibious, so
                    -- it needs its own entry or the hover task force -- on Aeon
                    -- and Seraphim, the mainline army -- is never dispatched.
                    Hover = true,
                    Air = true,
                },
                LayerPositions = {
                    Land = defenseAlert.Land > 0 and landPosition
                        or landAnchor
                        or landPosition,
                    Water = defenseAlert.Naval > 0 and waterPosition
                        or waterAnchor
                        or waterPosition,
                    Amphibious = defenseAlert.AnchorPosition,
                    -- Hover reaches the water threat itself where amphibious
                    -- would be stopped by depth; fall back to the anchor.
                    Hover = defenseAlert.Naval > 0 and waterPosition
                        or defenseAlert.AnchorPosition,
                    Air = defenseAlert.Air > 0
                        and defenseAlert.Position
                        or defenseAlert.AnchorPosition,
                },
                AnchorKind = defenseAlert.AnchorKind,
                AnchorLocationType = defenseAlert.AnchorLocationType,
                Priority = 140,
                -- An observed cluster threatening an anchor preempts anything,
                -- including an attack in contact. The local-threat fallback
                -- below deliberately does not.
                Critical = true,
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
            -- Try the surface layers this map actually supports, in order, and
            -- fall back to Air only when no surface force can reach anything.
            --
            -- Choosing the layer from MapType alone had two failures. On a
            -- Naval map it asked GetClosestEnemyStart for a water route to an
            -- enemy start -- dry land, where a commander spawns -- which can
            -- never succeed, so every offensive became `layer=Air`; and on a
            -- Mixed map it only ever offered Land, so the fleet was never
            -- given an objective at all.
            local layers = OffensiveLayers[self.World.MapType] or OffensiveLayers.Land
            local preferredLayer, known, position = nil, nil, nil

            for _, layer in ipairs(layers) do
                local candidate = self.Intel:GetBestKnownTarget(start, layer)
                if candidate and self.World:CanPath(layer, start, candidate.Position) then
                    preferredLayer, known = layer, candidate
                    break
                end
            end

            if not known then
                for _, layer in ipairs(layers) do
                    local candidate
                    if layer == "Water" then
                        -- A fleet cannot sail to a land coordinate. Aim at the
                        -- water beside the enemy instead; the enemy start is
                        -- resolved on the Air layer because that is pure
                        -- geometry rather than a route claim.
                        local enemyStart = self.World:GetClosestEnemyStart(start, "Air")
                        candidate = enemyStart
                            and self.World:GetNavalApproach(start, enemyStart)
                    else
                        candidate = self.World:GetClosestEnemyStart(start, layer)
                    end
                    if candidate then
                        preferredLayer, position = layer, candidate
                        break
                    end
                end
            end

            if not known and not position then
                preferredLayer = "Air"
                position = self.World:GetClosestEnemyStart(start, "Air")
            end

            -- A Land or Air objective dispatches Land, Amphibious and Hover
            -- and never the fleet, because a ship cannot sail to a land
            -- coordinate. On a Mixed map the Land layer resolves first, so the
            -- objective is always Land and every ship built sits in the
            -- ArmyPool for the whole match while naval production keeps
            -- running. Give the fleet the water beside the same target.
            --
            -- GetNavalApproach resolves both ends onto water and returns nil
            -- when the only route it can find stays inside our own basin, so
            -- this never invents a destination: with no reachable water the
            -- field is absent and the fleet is dispatched exactly as before.
            local function OffensiveWaterPosition(target)
                if not target or preferredLayer == "Water" then
                    return nil
                end
                if not self.World.GetNavalApproach then
                    return nil
                end
                return self.World:GetNavalApproach(start, target)
            end

            if known then
                objective = {
                    Type = "Raid",
                    Position = known.Position,
                    Layer = preferredLayer,
                    Priority = 75,
                    CreatedTick = GetGameTick(),
                    LayerPositions = {
                        Water = OffensiveWaterPosition(known.Position),
                    },
                }
            elseif position then
                objective = {
                    Type = "Pressure",
                    Position = position,
                    Layer = preferredLayer,
                    Priority = 60,
                    CreatedTick = GetGameTick(),
                    LayerPositions = {
                        Water = OffensiveWaterPosition(position),
                    },
                }
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
