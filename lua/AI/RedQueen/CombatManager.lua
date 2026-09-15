local Constants = import("/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua")
local Logger = import("/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua")

local function IsCombatUnit(unit)
    return unit
        and not unit.Dead
        and (not unit.BeenDestroyed or not unit:BeenDestroyed())
        and EntityCategoryContains(
            categories.MOBILE
                - categories.ENGINEER
                - categories.COMMAND
                - categories.SCOUT
                - categories.TRANSPORTFOCUS,
            unit
        )
end

-- One experimental is already a formed force. The count minimum exists to stop
-- small units being fed piecemeal into a waiting army, and a Galactic Colossus
-- at 27500 mass and 99999 hitpoints is not that: holding the most expensive
-- unit on the field until two escorts happen to be idle in the same layer is
-- how an endgame investment never arrives. The commitment threat gate further
-- down still decides whether the wave can win, so this relaxes the count
-- without relaxing the judgement.
local function ContainsExperimental(units)
    for _, unit in pairs(units) do
        if EntityCategoryContains(categories.EXPERIMENTAL, unit) then
            return true
        end
    end
    return false
end

-- Threat contribution of a single unit. A unit whose blueprint is unavailable
-- contributes nothing rather than raising: this runs inside a sort comparator,
-- where an error would abort the whole combat pass.
local function UnitThreat(unit)
    if not unit or not unit.GetBlueprint then
        return 0
    end
    local blueprint = unit:GetBlueprint() or {}
    local defense = blueprint.Defense or {}
    return (defense.SurfaceThreatLevel or 0)
        + (defense.SubThreatLevel or 0)
        + (defense.AirThreatLevel or 0)
end

-- Who may be sent to cover a forward base: any land gun, not only Tech 3.
--
-- Across a 21-cell matrix 40 forward bases were built by Tech 1 engineers and
-- 22 by Tech 2, against 10 by Tech 3. A Tech 3-only filter therefore had
-- nothing eligible to send for 86% of them, so the cover mechanism stood down
-- through the entire early and mid game -- which is when a base is most
-- exposed, and when only 21% of them ever established.
--
-- Named once because the sizing counts the force with the same rule that
-- decides who may go; two filters that drift apart would size a portion of a
-- pool it is not drawn from.
local GarrisonEligible = categories.MOBILE * categories.LAND * categories.DIRECTFIRE
    - categories.ENGINEER - categories.COMMAND - categories.SCOUT

local function UnitLayer(unit)
    local hash = unit:GetBlueprint().CategoriesHash or {}
    if hash.AIR then
        return "Air"
    end
    if hash.NAVAL then
        return "Water"
    end
    -- Hover and amphibious are separate engine navigation grids, not synonyms.
    -- Amphibious walks the seabed and is blocked past MaxWaterDepthAmphibious
    -- (25); hover crosses the surface at any depth. Routing a hover unit on the
    -- amphibious graph strands it: IssueObjective's path gate rejects the whole
    -- group. On Aeon and Seraphim that is the mainline army and every engineer.
    -- HOVER is tested first because a unit may carry both categories.
    if hash.HOVER then
        return "Hover"
    end
    if hash.AMPHIBIOUS then
        return "Amphibious"
    end
    return "Land"
end

-- Which task forces answer a given objective. Hover accompanies amphibious
-- everywhere amphibious appears: both cross the shoreline, but on different
-- engine graphs, so each must be dispatched and path-gated on its own layer.
local DefenseDispatchLayers = { "Water", "Land", "Amphibious", "Hover" }
local WaterDispatchLayers = { "Water", "Amphibious", "Hover" }
local LandDispatchLayers = { "Land", "Amphibious", "Hover" }

local function AvailableForOrder(unit, tick)
    return IsCombatUnit(unit)
        and (not unit.RedQueenOrderUntil or unit.RedQueenOrderUntil <= tick)
        and (not unit.RedQueenGarrisonUntil or unit.RedQueenGarrisonUntil <= tick)
end

-- Scouts need their own availability test: `IsCombatUnit` excludes
-- `categories.SCOUT` by definition, which is right for a task force and wrong
-- for the units whose whole job is to go and look.
local function AvailableScout(unit, tick)
    return unit
        and not unit.Dead
        and (not unit.BeenDestroyed or not unit:BeenDestroyed())
        and EntityCategoryContains(categories.MOBILE * categories.SCOUT, unit)
        and (not unit.RedQueenOrderUntil or unit.RedQueenOrderUntil <= tick)
        and (not unit.RedQueenGarrisonUntil or unit.RedQueenGarrisonUntil <= tick)
end

local function ObjectiveAt(objective, position)
    return {
        Type = objective.Type,
        Position = position,
        Layer = objective.Layer,
        Priority = objective.Priority,
    }
end

---@class RedQueenCombatManager
CombatManager = ClassSimple {
    __init = function(self, brain, world, economy, strategy)
        self.Brain = brain
        self.World = world
        self.Economy = economy
        self.Strategy = strategy
        self.OrderSequence = 0
    end,

    MaintainForwardGarrisons = function(self)
        self.GarrisonSummary = { Sites = 0, Units = 0 }
        local pool = self.Brain:GetPlatoonUniquelyNamed("ArmyPool")
        if not pool then
            return
        end
        local tick = GetGameTick()
        local units = pool:GetPlatoonUnits()
        local demand = self.Strategy.ProductionDemand
        local alert = demand.DefenseAlert
        if alert and alert.Active then
            for _, unit in pairs(units) do
                unit.RedQueenGarrisonSite = nil
                unit.RedQueenGarrisonUntil = nil
            end
            return
        end

        local plan = demand.ForwardBasePlan or {}
        local sites = {}
        local validSites = {}
        for _, site in pairs(plan.Sites or {}) do
            if site.State == "Building" or site.State == "Established" then
                table.insert(sites, site)
                validSites[site.Name] = true
            end
        end
        table.sort(sites, function(a, b)
            return a.Name < b.Name
        end)

        for _, unit in pairs(units) do
            if unit.RedQueenGarrisonSite
                and (not validSites[unit.RedQueenGarrisonSite]
                    or not unit.RedQueenGarrisonUntil
                    or unit.RedQueenGarrisonUntil <= tick)
            then
                unit.RedQueenGarrisonSite = nil
                unit.RedQueenGarrisonUntil = nil
            end
        end

        local pressure = demand.GarrisonLossPressure or {}
        local covered = 0
        local committed = 0
        local force = 0
        for _, unit in pairs(units) do
            if EntityCategoryContains(GarrisonEligible, unit) then
                force = force + 1
            end
        end
        -- One budget for every site together, at the most any site is allowed
        -- to draw. Sized per site instead, three sites could each take their
        -- own portion and the fraction would cap nothing.
        local budget = math.max(
            Constants.Policy.GarrisonMinimumUnits,
            math.floor(force
                * Constants.Policy.GarrisonForceFraction
                * Constants.Policy.GarrisonUndefendedMultiple)
        )

        for _, site in pairs(sites) do
            local defenseCount = self.Brain:GetNumUnitsAroundPoint(
                categories.STRUCTURE * categories.DEFENSE * categories.DIRECTFIRE,
                site.Position,
                Constants.Policy.ForwardBaseSiteRadius,
                "Ally"
            )
            -- How defensible the site is by its own tier's standard, not by a
            -- flat count. A Tech 1 foothold wants two guns and has no shield to
            -- build; a Tech 3 position wants five. Taking the threshold from the
            -- tier plan means what gets built and what counts as covered come
            -- from one place.
            local tier = site.TierPlan or {}
            local defended = tier.MinimumDefenses or 4
            local share = force * Constants.Policy.GarrisonForceFraction
            if defenseCount < defended then
                share = share * Constants.Policy.GarrisonUndefendedMultiple
            end
            local desired = math.max(
                Constants.Policy.GarrisonMinimumUnits,
                math.min(
                    Constants.Policy.GarrisonMaximumUnits,
                    math.floor(share)
                )
            )
            desired = math.min(desired, budget)

            -- Two ways cover has to be given up, both measured on the site
            -- rather than on the army.
            --
            -- Losses first: an escort being destroyed faster than it achieves
            -- anything is the piecemeal-feeding mistake with extra steps, and
            -- the answer to a site that kills tanks at that rate is an
            -- experimental, not more tanks. Then strength: if what is observed
            -- at the site beats what would be sent, sending it loses the units
            -- and the site both. Judged by the ratio the offensive commitment
            -- gate already uses, so cover and attack weigh strength alike.
            local held = {}
            local strength = 0
            for _, unit in pairs(units) do
                if unit.RedQueenGarrisonSite == site.Name then
                    table.insert(held, unit)
                    strength = strength + UnitThreat(unit)
                end
            end
            local losses = pressure[site.Name] or { Count = 0, Mass = 0 }
            local sent = table.getn(held) + losses.Count
            local release = nil
            if losses.Count > 0
                and losses.Count
                    >= math.max(1, sent * Constants.Policy.GarrisonLossFraction)
            then
                release = "escort-overwhelmed"
            end
            local assigned = 0
            local candidates = {}
            for _, unit in pairs(units) do
                if unit.RedQueenGarrisonSite == site.Name
                    and unit.RedQueenGarrisonUntil
                    and unit.RedQueenGarrisonUntil > tick
                then
                    assigned = assigned + 1
                elseif not unit.RedQueenGarrisonSite
                    and AvailableForOrder(unit, tick)
                    and EntityCategoryContains(GarrisonEligible, unit)
                then
                    table.insert(candidates, unit)
                end
            end
            -- Heaviest gun first, then nearest, then entity id. Widening the
            -- filter below Tech 3 must not mean sending a Tech 1 tank while a
            -- Tech 3 one stands idle.
            table.sort(candidates, function(a, b)
                local aThreat = UnitThreat(a)
                local bThreat = UnitThreat(b)
                if aThreat ~= bThreat then
                    return aThreat > bThreat
                end
                local aPosition = a:GetPosition()
                local bPosition = b:GetPosition()
                local adx = aPosition[1] - site.Position[1]
                local adz = aPosition[3] - site.Position[3]
                local bdx = bPosition[1] - site.Position[1]
                local bdz = bPosition[3] - site.Position[3]
                local aDistance = adx * adx + adz * adz
                local bDistance = bdx * bdx + bdz * bdz
                if aDistance ~= bDistance then
                    return aDistance < bDistance
                end
                return (a.EntityId or 0) < (b.EntityId or 0)
            end)

            -- Whether the cover can answer the site is a question about the
            -- escort that would go, not the one already standing there. Asking
            -- it before selection meant strength was 0 on the first cycle, so
            -- any observed threat at all refused cover outright -- and a site
            -- that had been covered while quiet was abandoned the moment
            -- anything appeared. Measured in game as 11 releases reading
            -- `units=0 losses=0`: cover happened only where there was nothing
            -- to cover against.
            local prospect = {}
            local prospectiveStrength = strength
            for index = 1, math.min(desired - assigned, table.getn(candidates)) do
                local unit = candidates[index]
                table.insert(prospect, unit)
                prospectiveStrength = prospectiveStrength + UnitThreat(unit)
            end
            if not release then
                local enemy = self:GetSiteThreat(site)
                if enemy > 0
                    and enemy
                        > prospectiveStrength * Constants.Policy.CommitmentThreatRatio
                then
                    release = "escort-outmatched"
                end
            end
            if release then
                for _, unit in pairs(held) do
                    unit.RedQueenGarrisonSite = nil
                    unit.RedQueenGarrisonUntil = nil
                end
                if site.GarrisonRelease ~= release then
                    site.GarrisonRelease = release
                    Logger.Info(self.Brain, string.format(
                        "forward base garrison released site=%s reason=%s units=%d"
                            .. " losses=%d strength=%.0f",
                        site.Name,
                        release,
                        table.getn(held),
                        losses.Count,
                        prospectiveStrength
                    ))
                end
            else
                site.GarrisonRelease = nil
                -- Renew retained members without replacing their patrol orders.
                -- Otherwise all original leases expire together and a single
                -- recent casualty is compared against zero surviving members.
                -- Surplus reservations still age out when the site's desired
                -- share or the army-wide budget shrinks.
                table.sort(held, function(a, b)
                    return (a.EntityId or 0) < (b.EntityId or 0)
                end)
                for index = 1, math.min(desired, table.getn(held)) do
                    held[index].RedQueenGarrisonUntil = tick
                        + Constants.Policy.ForwardBaseGarrisonSeconds * 10
                end
            end

            -- An escort below the minimum is not sent at all: the site waits
            -- rather than feeding units in one at a time.
            local understrength = assigned + table.getn(prospect)
                < Constants.Policy.GarrisonMinimumUnits
            local selected = {}
            for _, unit in ipairs((release or understrength) and {} or prospect) do
                unit.RedQueenGarrisonSite = site.Name
                unit.RedQueenGarrisonUntil = tick
                    + Constants.Policy.ForwardBaseGarrisonSeconds * 10
                table.insert(selected, unit)
            end
            if table.getn(selected) > 0 then
                IssueClearCommands(selected)
                IssueMove(selected, site.Position)
                IssuePatrol(selected, {
                    site.Position[1] + 16,
                    site.Position[2],
                    site.Position[3],
                })
                IssuePatrol(selected, {
                    site.Position[1] - 16,
                    site.Position[2],
                    site.Position[3],
                })
                Logger.Debug(self.Brain, string.format(
                    "forward base garrison site=%s units=%d desired=%d",
                    site.Name,
                    table.getn(selected),
                    desired
                ))
            end
            -- A released site holds nothing, whatever it held when the pass
            -- began: `assigned` was counted before the release cleared it.
            local standing = release and 0 or (assigned + table.getn(selected))
            budget = math.max(0, budget - standing)
            if standing > 0 then
                covered = covered + 1
                committed = committed + standing
            end
        end

        -- Reported so a match log can show whether cover happened at all. The
        -- commitment line above is Debug and therefore absent from every
        -- behavioural run, which is how a garrison filter that stood down for
        -- 86% of bases survived a full matrix unnoticed.
        self.GarrisonSummary = { Sites = covered, Units = committed }
    end,

    DispatchLayer = function(self, groups, layer, objective, defensive)
        local force = self:SelectTaskForce(groups[layer] or {}, defensive, objective, layer)
        if self:IssueObjective(force, objective, layer) then
            return table.getn(force)
        end
        return 0
    end,

    GatherAvailableUnits = function(self)
        local pool = self.Brain:GetPlatoonUniquelyNamed("ArmyPool")
        if not pool then
            return { Land = {}, Amphibious = {}, Hover = {}, Air = {}, Water = {} }
        end

        local tick = GetGameTick()
        local groups = { Land = {}, Amphibious = {}, Hover = {}, Air = {}, Water = {} }
        for _, unit in pairs(pool:GetPlatoonUnits()) do
            if AvailableForOrder(unit, tick) then
                table.insert(groups[UnitLayer(unit)], unit)
            end
        end
        return groups
    end,

    -- Observed enemy threat at the destination. Only offensive commitment
    -- consults it; a defensive response is never gated.
    GetObjectiveThreat = function(self, objective, layer)
        local intel = self.Strategy and self.Strategy.Intel
        if not intel or not intel.GetThreatNear or not objective.Position then
            return 0
        end
        return intel:GetThreatNear(
            objective.Position,
            Constants.Policy.CommitmentThreatRadius,
            layer
        ) or 0
    end,

    -- Observed enemy threat at a forward-base site, on the same radius the
    -- offensive commitment gate uses so the two judgements are comparable.
    --
    -- Measured on the escort's own layer, which is what makes the two figures
    -- comparable in the first place. Every garrison unit is `GarrisonEligible`
    -- -- MOBILE * LAND * DIRECTFIRE -- and `UnitThreat` for such a unit is
    -- effectively SurfaceThreatLevel alone. Asking for the threat without a
    -- layer folds the enemy's air threat into the numerator, so a gunship wing
    -- is weighed against a tank's gun: the site reads `escort-outmatched` and
    -- land cover is refused where there is no enemy ground force at all. One
    -- match logged three such releases reading `units=0 losses=0`. Air over a
    -- forward base is the package's AA answer, not the escort's.
    GetSiteThreat = function(self, site)
        local intel = self.Strategy and self.Strategy.Intel
        if not intel or not intel.GetThreatNear or not site.Position then
            return 0
        end
        return intel:GetThreatNear(
            site.Position,
            Constants.Policy.CommitmentThreatRadius,
            "Land"
        ) or 0
    end,

    TraceDecision = function(self, objective, layer, state, reason, available, strength, enemy)
        if self.Trace then
            local kind = objective and objective.Type or "none"
            self.Trace:Safe(self.Trace.Observe, "commitment", kind .. ":" .. tostring(layer) .. ((reason == "dispatched" or reason == "unavailable-path") and ":dispatch" or ":gate"), state .. ":" .. reason,
                string.format("objective=%s layer=%s decision=%s reason=%s available=%d strength=%.1f enemy=%.1f",
                    kind, tostring(layer), state, reason, available or 0, strength or 0, enemy or 0))
        end
    end,

    SelectTaskForce = function(self, units, defensive, objective, layer)
        local available = table.getn(units)
        self:TraceDecision(objective, layer, "evaluated", "selection", available)
        local minimum = defensive and 2 or Constants.Policy.MinimumAttackUnits
        if ContainsExperimental(units) then
            minimum = 1
        end
        if available < minimum then
            self:TraceDecision(objective, layer, "held", "insufficient-units", available)
            return nil
        end

        -- Highest contribution first, EntityId only to break ties. Sorting by
        -- EntityId alone re-sent the same oldest survivors every pass and left
        -- fresh production queued behind them.
        table.sort(units, function(a, b)
            local aThreat = UnitThreat(a)
            local bThreat = UnitThreat(b)
            if aThreat ~= bThreat then
                return aThreat > bThreat
            end
            return (a.EntityId or 0) < (b.EntityId or 0)
        end)

        local reserve = defensive and 0 or math.floor(available * Constants.Policy.AttackReserveFraction)
        local count = math.min(Constants.Policy.MaximumTaskForceUnits, available - reserve)
        if count < minimum then
            self:TraceDecision(objective, layer, "held", "reserve", available)
            return nil
        end

        local selected = {}
        local threat = 0
        for index = 1, count do
            selected[index] = units[index]
            threat = threat + UnitThreat(units[index])
        end

        -- Tactical commitment gate. Economy and match time never hold a unit
        -- back, but an offensive wave that cannot beat what is waiting for it
        -- is fed piecemeal into a formed army: match 27741743 built 998 land
        -- units, lost 1005 and killed 141. Units held here simply stay in the
        -- pool near base and join the next, larger wave.
        if not defensive and objective then
            local enemyThreat = self:GetObjectiveThreat(objective, layer)
            local required = enemyThreat * Constants.Policy.CommitmentThreatRatio
            -- A full wave always commits. Hoarding past the task-force cap
            -- buys nothing, because the surplus cannot be ordered anyway.
            if count < Constants.Policy.MaximumTaskForceUnits and threat < required then
                self:TraceDecision(objective, layer, "held", "strength", available, threat, enemyThreat)
                self:LogCommitmentHeld(objective, count, threat, required)
                return nil
            end
            self:TraceDecision(objective, layer, count >= Constants.Policy.MaximumTaskForceUnits and "bypassed" or "passed",
                count >= Constants.Policy.MaximumTaskForceUnits and "full-wave" or "strength", available, threat, enemyThreat)
        else
            self:TraceDecision(objective, layer, "bypassed", "defensive", available, threat)
        end
        return selected
    end,

    LogCommitmentHeld = function(self, objective, count, threat, required)
        local tick = GetGameTick()
        if tick - (self.LastCommitmentLogTick or -100000)
            < Constants.Policy.CommitmentDiagnosticSeconds * 10
        then
            return
        end
        self.LastCommitmentLogTick = tick
        Logger.Info(self.Brain, string.format(
            "commitment held objective=%s units=%d threat=%.0f required=%.0f",
            tostring(objective.Type),
            count,
            threat,
            required
        ))
    end,

    IssueObjective = function(self, units, objective, layer)
        if not units or table.getn(units) == 0 or not objective.Position then
            return false
        end

        local origin = units[1]:GetPosition()
        if layer ~= "Air" and not self.World:CanPath(layer, origin, objective.Position) then
            self:TraceDecision(objective, layer, "held", "unavailable-path", table.getn(units))
            return false
        end

        self:TraceDecision(objective, layer, "passed", "dispatched", table.getn(units))
        IssueClearCommands(units)
        IssueAggressiveMove(units, objective.Position)
        local orderUntil = GetGameTick() + Constants.Policy.UnitOrderLifetimeTicks
        for _, unit in pairs(units) do
            unit.RedQueenOrderUntil = orderUntil
        end
        return true
    end,

    -- Positions worth knowing about, and the scouts sent to see them.
    --
    -- Deliberately not a patrol route: targets are ranked by how little is
    -- known, so the army looks where it is ignorant and stops looking once it
    -- can see. The objective's own destination carries the most weight because
    -- that is the number the commitment gate reads -- a wave that attacks an
    -- unobserved position is judged against a threat of 0.
    ScoutCandidates = function(self, objective)
        local world = self.World or {}
        local candidates = {}
        if objective and objective.Position then
            table.insert(candidates, {
                Name = "objective",
                Position = objective.Position,
                Weight = 3,
            })
        end
        for _, enemy in pairs(world.EnemyStarts or {}) do
            table.insert(candidates, {
                Name = "start-" .. tostring(enemy.Army),
                Position = enemy.Position,
                Weight = 2,
            })
        end
        for _, cluster in pairs(world.MassClusters or {}) do
            table.insert(candidates, {
                Name = "cluster-" .. tostring(cluster.Id),
                Position = cluster.Position,
                Weight = 1,
            })
        end
        return candidates
    end,

    MaintainScouts = function(self)
        -- Capability-checked rather than assumed: this runs inside the combat
        -- cycle, where a raise would abort the whole pass.
        local pool = self.Brain.GetPlatoonUniquelyNamed
            and self.Brain:GetPlatoonUniquelyNamed("ArmyPool")
            or nil
        local intel = self.Strategy and self.Strategy.Intel
        if not pool or not pool.GetPlatoonUnits or not intel or not intel.GetScoutTargets then
            return
        end
        local tick = GetGameTick()
        local units = pool:GetPlatoonUnits()
        local targets = intel:GetScoutTargets(
            self:ScoutCandidates(self.Strategy.CurrentObjective))

        -- A target already well observed needs nobody sent to it.
        local wanted = {}
        for _, target in ipairs(targets) do
            if target.Coverage < Constants.Policy.ScoutCoverageSatisfied then
                table.insert(wanted, target)
            end
        end

        local idle = {}
        for _, unit in pairs(units) do
            if AvailableScout(unit, tick) then
                table.insert(idle, unit)
            end
        end
        table.sort(idle, function(a, b)
            return (a.EntityId or 0) < (b.EntityId or 0)
        end)

        -- Coverage feeds adaptive production, even when directed dispatch is
        -- disabled. Keep measuring in the production-only arm. Totals survive
        -- quiet passes so the slower diagnostic cycle cannot miss dispatches.
        local previous = self.ScoutSummary or {}
        local summary = {
            Targets = table.getn(targets),
            Blind = table.getn(wanted),
            Sent = 0,
            Idle = table.getn(idle),
            ScoutOrders = previous.ScoutOrders or 0,
            FallbackOrders = previous.FallbackOrders or 0,
        }
        self.ScoutSummary = summary
        local scouting = self.Brain.RedQueenScouting
        if scouting and not scouting.DirectedDispatch then
            return
        end

        local sent = 0
        -- Keep reservations independently of ArmyPool: native platoons may
        -- claim a travelling scout between passes. A combat fallback is a
        -- single outstanding assignment, not a fresh allowance every pass.
        self.ScoutAssignments = self.ScoutAssignments or {}
        local assigned = {}
        local fallbackActive = false
        for unit, assignment in pairs(self.ScoutAssignments) do
            if unit.Dead or (unit.BeenDestroyed and unit:BeenDestroyed())
                or assignment.Until <= tick
            then
                self.ScoutAssignments[unit] = nil
            else
                fallbackActive = fallbackActive or assignment.Fallback
                for _, target in ipairs(wanted) do
                    local position = assignment.Position
                    if position[1] == target.Position[1] and position[3] == target.Position[3] then
                        assigned[target] = true
                    end
                end
            end
        end
        local unassigned = {}
        for _, target in ipairs(wanted) do
            if not assigned[target] then table.insert(unassigned, target) end
        end
        local function Reserve(unit, target, fallback)
            unit.RedQueenScoutTarget = target.Name
            unit.RedQueenOrderUntil = tick + Constants.Policy.ScoutOrderSeconds * 10
            self.ScoutAssignments[unit] = {
                Position = { target.Position[1], target.Position[2], target.Position[3] },
                Until = unit.RedQueenOrderUntil,
                Fallback = fallback,
            }
            assigned[target] = true
        end
        for index = 1, math.min(table.getn(idle), table.getn(unassigned)) do
            local unit = idle[index]
            local target = unassigned[index]
            -- Air scouts reach anything; a land or naval scout must be able to
            -- path there or the order strands it at a shoreline.
            local layer = UnitLayer(unit)
            local reachable = layer == "Air"
                or not self.World.CanPath
                or self.World:CanPath(layer, unit:GetPosition(), target.Position)
            if reachable then
                Reserve(unit, target, false)
                IssueClearCommands({ unit })
                IssueMove({ unit }, target.Position)
                sent = sent + 1
                summary.ScoutOrders = summary.ScoutOrders + 1
            end
        end

        -- Nobody to send is the common case, and it is not an accident: FAF's
        -- own `T1AirScoutForm` and `T1LandScoutForm` templates carry
        -- `plan = ScoutingAI`, so native platoons claim scouts out of the pool
        -- before this pass ever sees them. Measured as `sent=0` for a whole
        -- match while 26 targets stood and 12-20 of them were unobserved.
        --
        -- Native scouting is doing real work there and is not worth fighting
        -- for its units. What it does not do is answer the one question the
        -- commitment gate depends on: what is at *this* destination. So when no
        -- scout is free, one ordinary unit is sent to look at the most
        -- important blind target and nothing else -- bounded at a single unit,
        -- because diverting a portion of the force is what cover already
        -- learned to cap.
        if sent == 0 and not fallbackActive and wanted[1] and not assigned[wanted[1]] then
            local eyes = nil
            for _, unit in pairs(units) do
                if AvailableForOrder(unit, tick)
                    and EntityCategoryContains(GarrisonEligible, unit)
                    and (not eyes or (unit.EntityId or 0) < (eyes.EntityId or 0))
                then
                    eyes = unit
                end
            end
            local target = wanted[1]
            if eyes and (target.Weight or 0) >= Constants.Policy.ScoutFallbackMinimumWeight then
                local layer = UnitLayer(eyes)
                if layer == "Air"
                    or not self.World.CanPath
                    or self.World:CanPath(layer, eyes:GetPosition(), target.Position)
                then
                    Reserve(eyes, target, true)
                    IssueClearCommands({ eyes })
                    IssueMove({ eyes }, target.Position)
                    sent = sent + 1
                    summary.FallbackOrders = summary.FallbackOrders + 1
                end
            end
        end

        summary.Sent = sent
    end,

    Update = function(self)
        self:MaintainForwardGarrisons()
        self:MaintainScouts()
        local objective = self.Strategy.CurrentObjective
        if not objective or objective.Type == "Recover" or objective.Type == "Stage" then
            self:TraceDecision(objective, "all", "held", "staging")
            return
        end
        if objective.LaunchTick and objective.LaunchTick > GetGameTick() then
            self:TraceDecision(objective, "all", "held", "launch-coordination")
            return
        end
        local defensive = objective.Type == "Defend"
            or objective.Type == "Support"
            or objective.Type == "Reinforce"
            or objective.Type == "Investigate"
        local groups = self:GatherAvailableUnits()
        local ordered = 0

        local layerPositions = objective.LayerPositions or {}
        local airPosition = objective.AirPosition or layerPositions.Air
        local airObjective = airPosition
            and ObjectiveAt(objective, airPosition)
            or objective
        if objective.AirPosition then airObjective.Type = "AirRaid" end
        local air = self:SelectTaskForce(groups.Air, defensive, airObjective, "Air")
        if self:IssueObjective(air, airObjective, "Air") then
            ordered = ordered + table.getn(air)
        end

        local destinationLayer = objective.Layer
        local defenseLayers = objective.DefenseLayers
        if defenseLayers then
            for _, layer in ipairs(DefenseDispatchLayers) do
                if defenseLayers[layer] and layerPositions[layer] then
                    ordered = ordered + self:DispatchLayer(
                        groups, layer, ObjectiveAt(objective, layerPositions[layer]), defensive)
                end
            end
        elseif destinationLayer == "Water" then
            for _, layer in ipairs(WaterDispatchLayers) do
                ordered = ordered + self:DispatchLayer(groups, layer, objective, defensive)
            end
        else
            -- Land, Air, or unset. An Air objective still offers the surface
            -- groups a destination: IssueObjective's path gate rejects any
            -- layer that cannot reach it and records the hold, which is far
            -- better than leaving every surface task force idle in the pool.
            -- No alternative destination is invented for them -- feeding
            -- packets at somewhere they can reach is what cost match 27741743
            -- 1005 units for 141 kills.
            for _, layer in ipairs(LandDispatchLayers) do
                ordered = ordered + self:DispatchLayer(groups, layer, objective, defensive)
            end
            -- The fleet is not in LandDispatchLayers and cannot sail to a land
            -- coordinate, so without a destination of its own it receives no
            -- order at all -- on a Mixed map that is every ship built, idle for
            -- the whole match. The director supplies this only where a naval
            -- route actually exists, so nothing is invented here.
            if layerPositions.Water then
                ordered = ordered + self:DispatchLayer(
                    groups, "Water", ObjectiveAt(objective, layerPositions.Water), defensive)
            end
        end

        if ordered > 0 then
            self.OrderSequence = self.OrderSequence + 1
            Logger.Debug(self.Brain, string.format("combat order=%d objective=%s units=%d", self.OrderSequence, objective.Type, ordered))
        end
    end,
}

function Create(brain, world, economy, strategy)
    return CombatManager(brain, world, economy, strategy)
end
