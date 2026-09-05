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

local function UnitLayer(unit)
    local hash = unit:GetBlueprint().CategoriesHash or {}
    if hash.AIR then
        return "Air"
    end
    if hash.NAVAL then
        return "Water"
    end
    if hash.AMPHIBIOUS or hash.HOVER then
        return "Amphibious"
    end
    return "Land"
end

local function AvailableForOrder(unit, tick)
    return IsCombatUnit(unit)
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

        for _, site in pairs(sites) do
            local defenseCount = self.Brain:GetNumUnitsAroundPoint(
                categories.STRUCTURE * categories.DEFENSE * categories.DIRECTFIRE,
                site.Position,
                Constants.Policy.ForwardBaseSiteRadius,
                "Ally"
            )
            local desired = 4
            if defenseCount < 4 then
                desired = self.Brain:GetFactionIndex() == 1 and 6 or 10
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
                    and EntityCategoryContains(
                        categories.MOBILE * categories.LAND * categories.TECH3
                            * categories.DIRECTFIRE
                            - categories.ENGINEER - categories.COMMAND - categories.SCOUT,
                        unit
                    )
                then
                    table.insert(candidates, unit)
                end
            end
            table.sort(candidates, function(a, b)
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

            local selected = {}
            for index = 1, math.min(desired - assigned, table.getn(candidates)) do
                local unit = candidates[index]
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
        end
    end,

    GatherAvailableUnits = function(self)
        local pool = self.Brain:GetPlatoonUniquelyNamed("ArmyPool")
        if not pool then
            return { Land = {}, Amphibious = {}, Air = {}, Water = {} }
        end

        local tick = GetGameTick()
        local groups = { Land = {}, Amphibious = {}, Air = {}, Water = {} }
        for _, unit in pairs(pool:GetPlatoonUnits()) do
            if AvailableForOrder(unit, tick) then
                table.insert(groups[UnitLayer(unit)], unit)
            end
        end
        return groups
    end,

    -- Observed enemy threat at the destination. Only offensive commitment
    -- consults it; a defensive response is never gated.
    GetObjectiveThreat = function(self, objective)
        local intel = self.Strategy and self.Strategy.Intel
        if not intel or not intel.GetThreatNear or not objective.Position then
            return 0
        end
        return intel:GetThreatNear(
            objective.Position,
            Constants.Policy.CommitmentThreatRadius
        ) or 0
    end,

    SelectTaskForce = function(self, units, defensive, objective)
        local available = table.getn(units)
        local minimum = defensive and 2 or Constants.Policy.MinimumAttackUnits
        if available < minimum then
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
            local enemyThreat = self:GetObjectiveThreat(objective)
            local required = enemyThreat * Constants.Policy.CommitmentThreatRatio
            -- A full wave always commits. Hoarding past the task-force cap
            -- buys nothing, because the surplus cannot be ordered anyway.
            if count < Constants.Policy.MaximumTaskForceUnits and threat < required then
                self:LogCommitmentHeld(objective, count, threat, required)
                return nil
            end
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
            return false
        end

        IssueClearCommands(units)
        IssueAggressiveMove(units, objective.Position)
        local orderUntil = GetGameTick() + Constants.Policy.UnitOrderLifetimeTicks
        for _, unit in pairs(units) do
            unit.RedQueenOrderUntil = orderUntil
        end
        return true
    end,

    Update = function(self)
        self:MaintainForwardGarrisons()
        local objective = self.Strategy.CurrentObjective
        if not objective or objective.Type == "Recover" or objective.Type == "Stage" then
            return
        end
        if objective.LaunchTick and objective.LaunchTick > GetGameTick() then
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
        local air = self:SelectTaskForce(groups.Air, defensive, airObjective)
        if self:IssueObjective(air, airObjective, "Air") then
            ordered = ordered + table.getn(air)
        end

        local destinationLayer = objective.Layer
        local defenseLayers = objective.DefenseLayers
        if defenseLayers then
            if defenseLayers.Water and layerPositions.Water then
                local waterObjective = ObjectiveAt(objective, layerPositions.Water)
                local naval = self:SelectTaskForce(groups.Water, defensive, waterObjective)
                if self:IssueObjective(naval, waterObjective, "Water") then
                    ordered = ordered + table.getn(naval)
                end
            end
            if defenseLayers.Land and layerPositions.Land then
                local landObjective = ObjectiveAt(objective, layerPositions.Land)
                local land = self:SelectTaskForce(groups.Land, defensive, landObjective)
                if self:IssueObjective(land, landObjective, "Land") then
                    ordered = ordered + table.getn(land)
                end
            end
            if defenseLayers.Amphibious and layerPositions.Amphibious then
                local amphibiousObjective = ObjectiveAt(objective, layerPositions.Amphibious)
                local amphibious = self:SelectTaskForce(groups.Amphibious, defensive, amphibiousObjective)
                if self:IssueObjective(amphibious, amphibiousObjective, "Amphibious") then
                    ordered = ordered + table.getn(amphibious)
                end
            end
        elseif destinationLayer == "Water" then
            local naval = self:SelectTaskForce(groups.Water, defensive, objective)
            if self:IssueObjective(naval, objective, "Water") then
                ordered = ordered + table.getn(naval)
            end
            local amphibious = self:SelectTaskForce(groups.Amphibious, defensive, objective)
            if self:IssueObjective(amphibious, objective, "Amphibious") then
                ordered = ordered + table.getn(amphibious)
            end
        elseif destinationLayer ~= "Air" then
            local land = self:SelectTaskForce(groups.Land, defensive, objective)
            if self:IssueObjective(land, objective, "Land") then
                ordered = ordered + table.getn(land)
            end
            local amphibious = self:SelectTaskForce(groups.Amphibious, defensive, objective)
            if self:IssueObjective(amphibious, objective, "Amphibious") then
                ordered = ordered + table.getn(amphibious)
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
