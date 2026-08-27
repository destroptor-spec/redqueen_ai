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

    SelectTaskForce = function(self, units, defensive)
        local available = table.getn(units)
        local minimum = defensive and 2 or Constants.Policy.MinimumAttackUnits
        if available < minimum then
            return nil
        end

        table.sort(units, function(a, b)
            return (a.EntityId or 0) < (b.EntityId or 0)
        end)

        local reserve = defensive and 0 or math.floor(available * Constants.Policy.AttackReserveFraction)
        local count = math.min(Constants.Policy.MaximumTaskForceUnits, available - reserve)
        if count < minimum then
            return nil
        end

        local selected = {}
        for index = 1, count do
            selected[index] = units[index]
        end
        return selected
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
        local air = self:SelectTaskForce(groups.Air, defensive)
        if self:IssueObjective(air, airObjective, "Air") then
            ordered = ordered + table.getn(air)
        end

        local destinationLayer = objective.Layer
        local defenseLayers = objective.DefenseLayers
        if defenseLayers then
            if defenseLayers.Water and layerPositions.Water then
                local naval = self:SelectTaskForce(groups.Water, defensive)
                if self:IssueObjective(
                    naval,
                    ObjectiveAt(objective, layerPositions.Water),
                    "Water"
                ) then
                    ordered = ordered + table.getn(naval)
                end
            end
            if defenseLayers.Land and layerPositions.Land then
                local land = self:SelectTaskForce(groups.Land, defensive)
                if self:IssueObjective(
                    land,
                    ObjectiveAt(objective, layerPositions.Land),
                    "Land"
                ) then
                    ordered = ordered + table.getn(land)
                end
            end
            if defenseLayers.Amphibious and layerPositions.Amphibious then
                local amphibious = self:SelectTaskForce(groups.Amphibious, defensive)
                if self:IssueObjective(
                    amphibious,
                    ObjectiveAt(objective, layerPositions.Amphibious),
                    "Amphibious"
                ) then
                    ordered = ordered + table.getn(amphibious)
                end
            end
        elseif destinationLayer == "Water" then
            local naval = self:SelectTaskForce(groups.Water, defensive)
            if self:IssueObjective(naval, objective, "Water") then
                ordered = ordered + table.getn(naval)
            end
            local amphibious = self:SelectTaskForce(groups.Amphibious, defensive)
            if self:IssueObjective(amphibious, objective, "Amphibious") then
                ordered = ordered + table.getn(amphibious)
            end
        elseif destinationLayer ~= "Air" then
            local land = self:SelectTaskForce(groups.Land, defensive)
            if self:IssueObjective(land, objective, "Land") then
                ordered = ordered + table.getn(land)
            end
            local amphibious = self:SelectTaskForce(groups.Amphibious, defensive)
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
