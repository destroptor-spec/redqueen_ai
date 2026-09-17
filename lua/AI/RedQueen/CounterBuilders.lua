local EconomyBuildConditions = "/lua/editor/EconomyBuildConditions.lua"
local InstantBuildConditions = "/lua/editor/InstantBuildConditions.lua"
local MarkerBuildConditions = "/lua/editor/MarkerBuildConditions.lua"
local UnitCountBuildConditions = "/lua/editor/UnitCountBuildConditions.lua"
local Constants = import("/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua")
local Experimentals = import("/mods/TheRedQueen/lua/AI/RedQueen/Experimentals.lua")

-- Behaviour flags come from the match profile, chosen once at brain start from
-- the options the match presents. Absent a profile -- the pure Lua specs build
-- conditions directly -- every optional behaviour is on, so a contract
-- exercises the condition rather than the selection.
local function ProfileFlag(aiBrain, name)
    local profile = aiBrain.RedQueenProfile
    if not profile then
        return true
    end
    return profile:Flag(name)
end

local function GetDemand(aiBrain)
    local modules = aiBrain.RedQueenModules
    if not modules or not modules.Strategy or not modules.Economy then
        return nil, nil
    end
    return modules.Strategy.ProductionDemand, modules.Economy.State
end

local function StrategicPriority(aiBrain, focus)
    local demand = GetDemand(aiBrain)
    if not demand or not demand.FocusWeights then
        return 0
    end
    local weight = demand.FocusWeights[focus] or 0
    if weight < Constants.Policy.StrategicFocusMinimumScore then
        return 0
    end
    local priority = 700 + weight * 3
    if demand.PrimaryFocus == focus then
        priority = priority + 25
    end
    return math.min(1000, math.floor(priority))
end

local function Tech2Priority(self, aiBrain)
    local priority = StrategicPriority(aiBrain, "Tech2")
    local demand = GetDemand(aiBrain)
    if priority == 0 and demand and demand.TierPolicy then
        for _, domain in pairs({ "Land", "Air", "Naval" }) do
            if demand.TierPolicy[domain] and demand.TierPolicy[domain].Highest >= 2 then
                return 910
            end
        end
    end
    return priority
end

local function Tech3Priority(self, aiBrain)
    local priority = StrategicPriority(aiBrain, "Tech3")
    local demand = GetDemand(aiBrain)
    if priority == 0 and demand and demand.TierPolicy then
        for _, domain in pairs({ "Land", "Air", "Naval" }) do
            if demand.TierPolicy[domain] and demand.TierPolicy[domain].Highest >= 3 then
                return 920
            end
        end
    end
    return priority
end

-- Role separation has to live in the priority function, not in the static
-- Priority field: FAF's Builder:CalculatePriority *replaces* self.Priority with
-- whatever PriorityFunction returns, so seven builders sharing one function all
-- end up equal and the declared ordering never takes effect.
--
-- Expressed as a penalty rather than a bonus so the ordering survives
-- saturation. StrategicPriority caps at 1000, and at a high enough weight an
-- assault bonus would be clipped away and the roles would tie again.
-- Experimentals already in flight, counted by role. The engine reports work in
-- progress by blueprint, so the classification is what turns "an experimental is
-- being built" into "a game-ender is being built".
local function CountProjectsOfRole(aiBrain, role)
    if not aiBrain.GetListOfUnits then
        return 0
    end
    local constructors = aiBrain:GetListOfUnits(categories.CONSTRUCTION, false) or {}
    local count = 0
    for _, unit in pairs(constructors) do
        local destroyed = unit.BeenDestroyed and unit:BeenDestroyed()
        if not destroyed and unit.IsUnitState and unit:IsUnitState("Building") then
            local project = unit.UnitBeingBuilt
            local blueprint = project
                and not project.Dead
                and project.GetBlueprint
                and project:GetBlueprint()
            local identifier = blueprint
                and (blueprint.BlueprintId or blueprint.BlueprintID)
            if identifier and Experimentals.RoleForBlueprint(identifier) == role then
                count = count + 1
            end
        end
    end
    return count
end

local ExperimentalRolePenalty = {
    Assault = 0,
    Support = 6,
    Siege = 12,
    Economy = 18,
    Intel = 24,
}

-- Each project of a role already in flight lowers that role's rank by this
-- much -- more than the gap between role bands, so the next slot goes to a
-- different role.
--
-- It must be a penalty and never a veto. An earlier version blocked a role once
-- one project of it was in flight, but the count cannot distinguish Red Queen's
-- work from the engine's: FAF's own builders keep assault experimentals going
-- (one Cybran match had three under construction), so the veto fired on their
-- work and locked Red Queen's own builders out for the whole match. Both runs
-- built nothing and lost.
local ExperimentalRoleCrowdingPenalty = 30

local function ExperimentalPriority(self, aiBrain)
    local priority = StrategicPriority(aiBrain, "Experimental")
    if priority == 0 then
        return 0
    end
    -- `self` here is the global builder definition, so the template is read
    -- from the same place the builder builds from.
    local construction = self.BuilderData and self.BuilderData.Construction
    local structures = construction and construction.BuildStructures
    local template = structures and structures[1]
    local context = aiBrain.RedQueenContext
    local faction = context and context.FactionIndex
    local entry = template and faction and Experimentals.ForTemplate(faction, template)
    if not entry then
        return 0
    end
    local penalty = (ExperimentalRolePenalty[entry.Role] or 0)
        + CountProjectsOfRole(aiBrain, entry.Role) * ExperimentalRoleCrowdingPenalty
    return math.max(0, priority - penalty)
end

local function NukePriority(self, aiBrain)
    return StrategicPriority(aiBrain, "Nuke")
end

local function ShouldBuildGunships(aiBrain)
    local demand, economy = GetDemand(aiBrain)
    if not demand
        or economy.StallRisk
        or demand.Doctrine ~= "GunshipCounter"
    then
        return false
    end

    local gunships = aiBrain:GetCurrentUnits(
        categories.MOBILE * categories.AIR * categories.GROUNDATTACK
    )
    local combatUnits = aiBrain:GetCurrentUnits(
        categories.MOBILE * (categories.LAND + categories.AIR)
            - categories.ENGINEER
            - categories.COMMAND
            - categories.SCOUT
    )
    local desired = math.max(6, math.floor(combatUnits * demand.Gunships))
    return gunships < desired
end

-- Scouts, asked for the same way gunships and anti-air are: a share of the
-- army, with a floor of one so the picture never goes completely stale.
--
-- Until this existed `demand.Scouts` was computed, clamped, probed and written
-- into the state line, and nothing read it -- every builder here subtracts
-- categories.SCOUT, so every scout in every match came from FAF's own builders.
-- The isolation arms proved it: dispatch-only reproduced combined tick for tick
-- across eight cells, because the only difference between those arms was a
-- number nothing consumed.
local function ShouldBuildScouts(aiBrain)
    local demand, economy = GetDemand(aiBrain)
    if not demand or economy.StallRisk then
        return false
    end
    local scouts = aiBrain:GetCurrentUnits(categories.MOBILE * categories.SCOUT)
    local army = aiBrain:GetCurrentUnits(
        categories.MOBILE * (categories.LAND + categories.AIR)
            - categories.ENGINEER
            - categories.COMMAND
            - categories.SCOUT
    )
    local desired = math.max(1, math.floor(math.max(1, army) * (demand.Scouts or 0)))
    return scouts < desired
end

local function ShouldBuildAirDefense(aiBrain)
    local demand, economy = GetDemand(aiBrain)
    if not demand
        or economy.StallRisk
        or demand.Doctrine ~= "AirDefense"
    then
        return false
    end

    local fighters = aiBrain:GetCurrentUnits(
        categories.MOBILE * categories.AIR * categories.ANTIAIR
            - categories.BOMBER
            - categories.TRANSPORTFOCUS
    )
    local airCombat = aiBrain:GetCurrentUnits(
        categories.MOBILE * categories.AIR - categories.TRANSPORTFOCUS - categories.SCOUT
    )
    local desired = math.max(8, math.floor(math.max(1, airCombat) * demand.AntiAir))
    return fighters < desired
end

local function CanAffordTech(economy, massIncome, energyIncome)
    return not economy.StallRisk
        and economy.MassIncome >= massIncome
        and economy.EnergyIncome >= energyIncome
        and (economy.MassStoredRatio >= 0.10 or economy.MassTrend >= 0)
        and (economy.EnergyStoredRatio >= 0.15 or economy.EnergyTrend >= 0)
end

local function DomainIsRelevant(aiBrain, domain)
    local modules = aiBrain.RedQueenModules
    local mapType = modules and modules.World and modules.World.MapType or "Land"
    if domain == "Air" then
        return true
    end
    if domain == "Land" then
        return mapType ~= "Naval"
    end
    return mapType ~= "Land"
end

-- Shared with production suppression so fallback units remain buildable
-- whenever this domain's upgrade is ineligible.
function ShouldTechToT2(aiBrain, domain)
    local demand, economy = GetDemand(aiBrain)
    local tier = demand
        and demand.TierPolicy
        and demand.TierPolicy[domain]
        and demand.TierPolicy[domain].Highest
    return demand
        and DomainIsRelevant(aiBrain, domain)
        and not (demand.DefenseAlert and demand.DefenseAlert.Active)
        and demand.FocusWeights
        and (demand.FocusWeights.Tech2 >= Constants.Policy.StrategicFocusMinimumScore
            or (tier or 1) >= 2)
        and CanAffordTech(
            economy,
            Constants.Policy.Tech2MinimumMassIncome,
            Constants.Policy.Tech2MinimumEnergyIncome
        )
end

local function ShouldTechToT3(aiBrain, domain)
    local demand, economy = GetDemand(aiBrain)
    local tier = demand
        and demand.TierPolicy
        and demand.TierPolicy[domain]
        and demand.TierPolicy[domain].Highest
    return demand
        and DomainIsRelevant(aiBrain, domain)
        and not (demand.DefenseAlert and demand.DefenseAlert.Active)
        and demand.FocusWeights
        and (demand.FocusWeights.Tech3 >= Constants.Policy.StrategicFocusMinimumScore
            or (tier or 1) >= 3)
        and CanAffordTech(
            economy,
            Constants.Policy.Tech3MinimumMassIncome,
            Constants.Policy.Tech3MinimumEnergyIncome
        )
end

-- Energy is the one input Red Queen gates itself on but never produces.
--
-- CanAffordTech requires Tech3MinimumEnergyIncome (250 a tick, which is exactly
-- one Tech 3 generator) before any domain may tech to Tech 3. On Fields of Isis
-- the economy peaked at 212 and sat there: mass cleared its gate comfortably at
-- 16 against 10, so the brain was held one rung below Tech 3 for the whole match
-- and finished with three Tech 3 units against the opponent's forty-four. There
-- was no mechanism anywhere in the mod to build a power generator on purpose --
-- the tech gate was a wall with no ladder against it.
--
-- Only fires when energy is the sole thing missing: mass already satisfies the
-- same tier's gate, so this cannot pull engineers away from a genuine shortage.
local function EnergyBlocksTech(aiBrain, tier)
    local demand, economy = GetDemand(aiBrain)
    if not ProfileFlag(aiBrain, "TechEnergyLadder") then
        return false
    end
    if not demand or not economy or economy.StallRisk then
        return false
    end
    local massGate = tier >= 3
        and Constants.Policy.Tech3MinimumMassIncome
        or Constants.Policy.Tech2MinimumMassIncome
    local energyGate = tier >= 3
        and Constants.Policy.Tech3MinimumEnergyIncome
        or Constants.Policy.Tech2MinimumEnergyIncome
    return economy.MassIncome >= massGate
        and economy.EnergyIncome < energyGate
end

-- Tech 3 only. The Tech 2 gate (4 mass, 60 energy a tick) is an opening-economy
-- threshold, and diverting engineers to power there costs the expansion that
-- grows the economy in the first place: on Sludge it choked mass growth at 3.9
-- a tick where the untouched run reached 5.9, turning a victory into a defeat.
-- The Tech 3 gate is a late threshold a mature economy stalls against, which is
-- the case that has no other ladder against it.
-- Size the generator to the gap, not to the engineer.
--
-- A Tech 3 generator costs 57600 energy for 250 a tick; a Tech 2 costs 12000
-- for 50. Always reaching for the Tech 3 one spent five times what was needed
-- on Sentry Point, which was 47 short of the gate -- a single Tech 2 generator
-- -- and the over-investment turned a victory (K/L 1.43) into a defeat (0.67).
-- Only a deficit too large for a couple of Tech 2 generators justifies Tech 3.
local function EnergyDeficit(aiBrain)
    local _, economy = GetDemand(aiBrain)
    if not economy then
        return 0
    end
    return Constants.Policy.Tech3MinimumEnergyIncome - (economy.EnergyIncome or 0)
end

local function ShouldBuildTechEnergy(aiBrain)
    return EnergyBlocksTech(aiBrain, 3)
end

local function ShouldBuildTechEnergyLarge(aiBrain)
    return EnergyBlocksTech(aiBrain, 3)
        and EnergyDeficit(aiBrain) > Constants.Policy.LargeEnergyDeficit
end

local function ShouldBuildTechEnergySmall(aiBrain)
    return EnergyBlocksTech(aiBrain, 3)
        and (EnergyDeficit(aiBrain) <= Constants.Policy.LargeEnergyDeficit
            -- Reaching the T3 energy gate must not require a T3 engineer.
            or aiBrain:GetCurrentUnits(categories.ENGINEER * categories.TECH3) == 0)
end

local function ShouldBuildDominantTier(aiBrain, domain, tier)
    local demand, economy = GetDemand(aiBrain)
    local policy = demand and demand.TierPolicy and demand.TierPolicy[domain]
    return policy
        and policy.Highest == tier
        and not economy.StallRisk
end

local function ShouldBuildT2Land(aiBrain)
    return ShouldBuildDominantTier(aiBrain, "Land", 2)
end

local function ShouldBuildT3Land(aiBrain)
    return ShouldBuildDominantTier(aiBrain, "Land", 3)
end

local function ShouldBuildT2Air(aiBrain)
    return ShouldBuildDominantTier(aiBrain, "Air", 2)
end

local function ShouldBuildT3Air(aiBrain)
    return ShouldBuildDominantTier(aiBrain, "Air", 3)
end

-- First-tier naval is the one dominance gap that terrain makes expensive.
--
-- On SCMP_037 (93% water) Red Queen held three to five naval factories and
-- produced six warships all match, while the opponent produced twenty-nine.
-- Its six were the most effective units on the field -- thirteen kills for
-- three losses -- so the shortfall was output, not quality. The tier-dominance
-- group only ever fired at Tech 2 and 3, and naval sat at Tech 1 for most of
-- the match, so nothing here contributed to naval output during the entire
-- early game. Gated on naval demand so dry maps are unaffected.
local function ShouldBuildT1Naval(aiBrain)
    local demand = GetDemand(aiBrain)
    return ProfileFlag(aiBrain, "NavalFirstTier")
        and demand
        and (demand.Naval or 0) >= Constants.Policy.NavalDominanceMinimumDemand
        and ShouldBuildDominantTier(aiBrain, "Naval", 1)
end

local function ShouldBuildT2Naval(aiBrain)
    return ShouldBuildDominantTier(aiBrain, "Naval", 2)
end

local function ShouldBuildT3Naval(aiBrain)
    return ShouldBuildDominantTier(aiBrain, "Naval", 3)
end

local function ShouldTechLandToT2(aiBrain)
    return ShouldTechToT2(aiBrain, "Land")
end

local function ShouldTechAirToT2(aiBrain)
    return ShouldTechToT2(aiBrain, "Air")
end

local function ShouldTechNavalToT2(aiBrain)
    return ShouldTechToT2(aiBrain, "Naval")
end

local function ShouldTechLandToT3(aiBrain)
    return ShouldTechToT3(aiBrain, "Land")
end

local function ShouldTechAirToT3(aiBrain)
    return ShouldTechToT3(aiBrain, "Air")
end

local function ShouldTechNavalToT3(aiBrain)
    return ShouldTechToT3(aiBrain, "Naval")
end

local function CountMajorProjectsBeingBuilt(aiBrain)
    if not aiBrain.GetListOfUnits then
        return 0
    end
    local constructors = aiBrain:GetListOfUnits(categories.CONSTRUCTION, false) or {}
    local category = categories.EXPERIMENTAL + categories.NUKE * categories.STRUCTURE
    local count = 0
    for _, unit in pairs(constructors) do
        local destroyed = unit.BeenDestroyed and unit:BeenDestroyed()
        if not destroyed and unit.IsUnitState and unit:IsUnitState("Building") then
            local project = unit.UnitBeingBuilt
            if project and not project.Dead and EntityCategoryContains(category, project) then
                count = count + 1
            end
        end
    end
    return count
end

local function HasMajorProjectSlot(aiBrain)
    local demand = GetDemand(aiBrain)
    return demand
        and demand.MajorProjectSlots > 0
        and CountMajorProjectsBeingBuilt(aiBrain) < demand.MajorProjectSlots
end

-- Whether the endgame economy will carry another experimental at all. Role and
-- reachability are asked separately, per candidate.
local function ExperimentalBudgetAllows(aiBrain)
    local demand, economy = GetDemand(aiBrain)
    if not demand
        or not demand.FocusWeights
        or demand.FocusWeights.Experimental < Constants.Policy.StrategicFocusMinimumScore
        or demand.DesiredExperimentals < 1
    then
        return false
    end
    if not CanAffordTech(
        economy,
        Constants.Policy.ExperimentalMinimumMassIncome,
        Constants.Policy.ExperimentalMinimumEnergyIncome
    ) then
        return false
    end
    return aiBrain:GetCurrentUnits(categories.EXPERIMENTAL) < demand.DesiredExperimentals
end

-- A support experimental cannot engage a ground target, so it is only worth its
-- mass beside a force of its own layer to escort.
local function HasEscortForce(aiBrain, entry)
    if entry.Escorts ~= "Water" then
        return false
    end
    local fleet = aiBrain:GetCurrentUnits(categories.NAVAL * categories.MOBILE)
    return fleet >= Constants.Policy.ExperimentalEscortMinimumFleet
end

--- Gate for one FAF template key, resolved through the classification catalog.
--
-- The template key is the builder's static `BuildStructures` entry, so the gate
-- and the thing built can never disagree. A key this faction should not build --
-- Cybran and Seraphim `T4SeaExperimental1` resolve to a Tech 1 land factory, and
-- Aeon and Cybran `T4Artillery` to Tech 3 artillery -- is absent from the
-- catalog, so `ForTemplate` returns nil and the builder stays inert rather than
-- spending a Tech 3 engineer on the wrong unit.
local function ShouldBuildClassifiedExperimental(aiBrain, template)
    local context = aiBrain.RedQueenContext
    local faction = context and context.FactionIndex
    if not faction then
        return false
    end
    local entry = Experimentals.ForTemplate(faction, template)
    if not entry then
        return false
    end
    if not ExperimentalBudgetAllows(aiBrain) then
        return false
    end
    -- A resource generator is an economy multiplier rather than a weapon, and at
    -- 250200 mass it is only defensible once income would otherwise be idling.
    -- One is all the game allows to matter.
    if entry.Role == Experimentals.Roles.Economy then
        local _, economy = GetDemand(aiBrain)
        return economy ~= nil
            and economy.MassIncome >= Constants.Policy.ExperimentalUtilityMassIncome
            and aiBrain:GetCurrentUnits(categories.EXPERIMENTAL * categories.ECONOMIC) < 1
    end
    -- Permanent orbital observation, and the only experimental that answers an
    -- intel problem rather than a force one.
    if entry.Role == Experimentals.Roles.Intel then
        local _, economy = GetDemand(aiBrain)
        return economy ~= nil
            and economy.MassIncome >= Constants.Policy.ExperimentalUtilityMassIncome
    end
    local modules = aiBrain.RedQueenModules
    local world = modules and modules.World
    if not world then
        return false
    end
    -- The half that has historically gone wrong. Assault and mobile-siege
    -- experimentals are RULEUMT_Amphibious, so they must be asked about the
    -- Amphibious graph; air about Air; naval about Water. A structure has no
    -- layer and no route to satisfy.
    if not Experimentals.CanAct(world, entry, world.StartPosition) then
        return false
    end
    if entry.Role == Experimentals.Roles.Support then
        return HasEscortForce(aiBrain, entry)
    end
    return true
end

-- Engineers are established to a target, the way factories are, rather than to
-- a fixed floor. FAF's own rule is "fewer than four at this location", which
-- cannot tell a quiet base from one losing an engineer a minute.
--
-- The tier argument keeps the ladder honest: a Tech 3 engineer is worth
-- building only once Tech 3 exists, and the cheapest tier that can still be
-- produced should carry the replacements.
-- What counts toward the target at each tier.
--
-- A cap filled with Tech 1 engineers is a cap that never improves. Twelve of
-- them satisfy a target of twelve forever, so no Tech 2 engineer is ever built
-- however good the economy gets -- and a Tech 2 engineer carries several times
-- the build power, which is the whole reason to reach the tier. Each tier
-- therefore counts only engineers at that tier or above.
local function EngineersAtTier(aiBrain, tier)
    local category = categories.ENGINEER * categories.MOBILE
    if tier >= 3 then
        return aiBrain:GetCurrentUnits(category * categories.TECH3)
    end
    if tier >= 2 then
        return aiBrain:GetCurrentUnits(
            category * (categories.TECH2 + categories.TECH3))
    end
    return aiBrain:GetCurrentUnits(category)
end

local function ShouldBuildEngineer(aiBrain, tier)
    local demand, economy = GetDemand(aiBrain)
    if not demand or not economy then
        return false
    end
    local target = demand.DesiredEngineers or 0
    if target < 1 then
        return false
    end
    if EngineersAtTier(aiBrain, tier) >= target then
        return false
    end
    -- And the ladder replaces rather than accumulates: once a Tech 2 engineer
    -- exists and the economy can pay for another, Tech 1 stops. Without this
    -- the two tiers each fill the target and the army ends up with twice the
    -- engineers it asked for. Keyed on one already existing, so there is never
    -- a gap where the tier is unaffordable and neither ladder builds.
    if tier == 1
        and economy.MassIncome >= Constants.Policy.Tech2MinimumMassIncome
        and EngineersAtTier(aiBrain, 2) > 0
    then
        return false
    end
    -- Replacing engineers is pointless if the economy cannot pay for them, but
    -- the floor is deliberately the Tech gate for that tier and nothing
    -- stricter: an engineer shortage is itself what suppresses income, so
    -- waiting for income to recover first is the flatline this exists to stop.
    if tier >= 3 then
        return economy.MassIncome >= Constants.Policy.Tech3MinimumMassIncome
    end
    if tier >= 2 then
        return economy.MassIncome >= Constants.Policy.Tech2MinimumMassIncome
    end
    return true
end

local function ShouldBuildT1Engineer(aiBrain)
    return ShouldBuildEngineer(aiBrain, 1)
end

local function ShouldBuildT2Engineer(aiBrain)
    return ShouldBuildEngineer(aiBrain, 2)
end

local function ShouldBuildT3Engineer(aiBrain)
    return ShouldBuildEngineer(aiBrain, 3)
end

-- Priority rises with how far below target the army is, so a single missing
-- engineer is ordinary work and a collapse outranks almost everything.
-- Replacement priority, bounded so losses cannot spend the army.
--
-- This function is shared by the Tech 1, 2 and 3 engineer builders and used to
-- ignore the tier entirely, returning `min(1000, 850 + shortfall * 20)` for all
-- three -- so their static 870/860/850 never applied. Since each loss raises
-- the desired count by `EngineerLossReplacementFactor`, four engineer deaths
-- were enough to reach 930 and tie the Tech 2 mainline, five to pass Tech 3
-- Land Dominance at 940, and eight to reach 1000 and outrank everything. An
-- army that lost a handful of engineers therefore stopped building units, in
-- every factory, which is precisely the observed behaviour.
--
-- Three changes, all of them about *not* feeding that cycle:
--
--  * Engineers already under construction count against the shortfall, so
--    several factories cannot each react to the same missing engineer.
--  * The result is capped below combat production, so replacing losses never
--    outranks the army that prevents them.
--  * The builder's own static priority is the base again, so the tiers keep
--    their intended order relative to each other.
--
-- The cap lifts only in construction recovery -- an army down to almost no
-- engineers cannot rebuild anything, and that case has to win outright.
local function EngineerPriority(self, aiBrain)
    local demand = GetDemand(aiBrain)
    if not demand then
        return 0
    end
    local target = demand.DesiredEngineers or 0
    local engineerCategory = categories.ENGINEER * categories.MOBILE
    local held = aiBrain:GetCurrentUnits(engineerCategory)
    -- Completed units only come back from GetCurrentUnits, so ask for the list
    -- including those still being built to see what is already on the way.
    local building = 0
    if aiBrain.GetListOfUnits then
        local all = aiBrain:GetListOfUnits(engineerCategory, false, false)
        building = math.max(0, table.getn(all or {}) - held)
    end
    local shortfall = target - held - building
    if shortfall <= 0 then
        return 0
    end
    -- OriginalPriority is what FAF's Builder:Create copies from the
    -- definition, and is the honest base because our own policies mutate
    -- Priority at runtime. The definition's Priority is the fallback so the
    -- static order still holds before a builder instance exists.
    local base = self.OriginalPriority or self.Priority or 850
    local ceiling = Constants.Policy.EngineerReplacementPriorityCeiling
    if held + building < Constants.Policy.EngineerRecoveryFloor then
        ceiling = 1000
    end
    return math.min(ceiling, base + shortfall * 20)
end

-- A directed platoon is only worth forming when there is somewhere to send it.
-- Without this the plan forms platoons that gather and then stand still, which
-- is worse than leaving the units to native.
local function HasDirectionTarget(aiBrain)
    local modules = aiBrain.RedQueenModules
    local strategy = modules and modules.Strategy
    local objective = strategy and strategy.PrimaryObjective
    if not objective or not objective.Position
        or objective.Type == "Stage" or objective.Type == "Recover"
    then
        return false
    end
    -- And reachable on foot from home, or these units are better left to
    -- native: a land platoon formed against a target across water walks into
    -- the sea instead of defending the base it was standing in.
    local world = modules.World
    if world and world.CanPath and world.StartPosition
        and not world:CanPath("Land", world.StartPosition, objective.Position)
    then
        return false
    end
    return true
end

local function ShouldBuildNuke(aiBrain)
    local demand, economy = GetDemand(aiBrain)
    if not demand
        or not demand.FocusWeights
        or demand.FocusWeights.Nuke < Constants.Policy.StrategicFocusMinimumScore
        or demand.DesiredNukes < 1
    then
        return false
    end

    return CanAffordTech(
        economy,
        Constants.Policy.NukeMinimumMassIncome,
        Constants.Policy.NukeMinimumEnergyIncome
    ) and aiBrain:GetCurrentUnits(categories.NUKE * categories.STRUCTURE) < demand.DesiredNukes
end

BuilderGroup {
    BuilderGroupName = "RedQueenTechUpgradeBuilders",
    BuildersType = "PlatoonFormBuilder",

    Builder {
        BuilderName = "Red Queen T1 Land Factory Tech",
        PlatoonTemplate = "T1LandFactoryUpgrade",
        Priority = 910,
        PriorityFunction = Tech2Priority,
        InstanceCount = 1,
        FormRadius = 10000,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldTechLandToT2, {} },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.FACTORY * categories.LAND * categories.TECH1 } },
            { UnitCountBuildConditions, "HaveLessThanUnitsInCategoryBeingUpgraded", { 1, categories.FACTORY * categories.TECH1 } },
        },
    },
    Builder {
        BuilderName = "Red Queen T1 Air Factory Tech",
        PlatoonTemplate = "T1AirFactoryUpgrade",
        Priority = 905,
        PriorityFunction = Tech2Priority,
        InstanceCount = 1,
        FormRadius = 10000,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldTechAirToT2, {} },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.FACTORY * categories.AIR * categories.TECH1 } },
            { UnitCountBuildConditions, "HaveLessThanUnitsInCategoryBeingUpgraded", { 1, categories.FACTORY * categories.TECH1 } },
        },
    },
    Builder {
        BuilderName = "Red Queen T1 Naval Factory Tech",
        PlatoonTemplate = "T1SeaFactoryUpgrade",
        Priority = 900,
        PriorityFunction = Tech2Priority,
        InstanceCount = 1,
        FormRadius = 10000,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldTechNavalToT2, {} },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.FACTORY * categories.NAVAL * categories.TECH1 } },
            { UnitCountBuildConditions, "HaveLessThanUnitsInCategoryBeingUpgraded", { 1, categories.FACTORY * categories.TECH1 } },
        },
    },

    Builder {
        BuilderName = "Red Queen T2 Land Factory Tech",
        PlatoonTemplate = "T2LandFactoryUpgrade",
        Priority = 920,
        PriorityFunction = Tech3Priority,
        InstanceCount = 1,
        FormRadius = 10000,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldTechLandToT3, {} },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.FACTORY * categories.LAND * categories.TECH2 } },
            { UnitCountBuildConditions, "HaveLessThanUnitsInCategoryBeingUpgraded", { 1, categories.FACTORY * categories.TECH2 } },
        },
    },
    Builder {
        BuilderName = "Red Queen T2 Air Factory Tech",
        PlatoonTemplate = "T2AirFactoryUpgrade",
        Priority = 915,
        PriorityFunction = Tech3Priority,
        InstanceCount = 1,
        FormRadius = 10000,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldTechAirToT3, {} },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.FACTORY * categories.AIR * categories.TECH2 } },
            { UnitCountBuildConditions, "HaveLessThanUnitsInCategoryBeingUpgraded", { 1, categories.FACTORY * categories.TECH2 } },
        },
    },
    Builder {
        BuilderName = "Red Queen T2 Naval Factory Tech",
        PlatoonTemplate = "T2SeaFactoryUpgrade",
        Priority = 910,
        PriorityFunction = Tech3Priority,
        InstanceCount = 1,
        FormRadius = 10000,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldTechNavalToT3, {} },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.FACTORY * categories.NAVAL * categories.TECH2 } },
            { UnitCountBuildConditions, "HaveLessThanUnitsInCategoryBeingUpgraded", { 1, categories.FACTORY * categories.TECH2 } },
        },
    },
}

BuilderGroup {
    BuilderGroupName = "RedQueenTierDominanceBuilders",
    BuildersType = "FactoryBuilder",

    Builder {
        BuilderName = "Red Queen T3 Land Dominance",
        PlatoonTemplate = "T3LandBot",
        Priority = 940,
        BuilderType = "Land",
        BuilderConditions = {
            { ShouldBuildT3Land, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.65, 0.90 } },
        },
    },
    Builder {
        BuilderName = "Red Queen T2 Land Dominance",
        PlatoonTemplate = "T2AttackTank",
        Priority = 930,
        BuilderType = "Land",
        BuilderConditions = {
            { ShouldBuildT2Land, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.65, 0.90 } },
        },
    },
    Builder {
        BuilderName = "Red Queen T3 Air Dominance",
        PlatoonTemplate = "T3AirGunship",
        Priority = 940,
        BuilderType = "Air",
        BuilderConditions = {
            { ShouldBuildT3Air, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.65, 0.90 } },
        },
    },
    Builder {
        BuilderName = "Red Queen T2 Air Dominance",
        PlatoonTemplate = "T2AirGunship",
        Priority = 930,
        BuilderType = "Air",
        BuilderConditions = {
            { ShouldBuildT2Air, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.65, 0.90 } },
        },
    },
    Builder {
        BuilderName = "Red Queen T3 Naval Dominance",
        PlatoonTemplate = "T3SeaBattleship",
        Priority = 940,
        BuilderType = "Sea",
        BuilderConditions = {
            { ShouldBuildT3Naval, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.65, 0.90 } },
        },
    },
    Builder {
        BuilderName = "Red Queen T1 Naval Dominance",
        PlatoonTemplate = "T1SeaFrigate",
        Priority = 920,
        BuilderType = "Sea",
        BuilderConditions = {
            { ShouldBuildT1Naval, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.65, 0.90 } },
        },
    },
    Builder {
        BuilderName = "Red Queen T2 Naval Dominance",
        PlatoonTemplate = "T2SeaDestroyer",
        Priority = 930,
        BuilderType = "Sea",
        BuilderConditions = {
            { ShouldBuildT2Naval, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.65, 0.90 } },
        },
    },
}

BuilderGroup {
    BuilderGroupName = "RedQueenEngineerBuilders",
    BuildersType = "FactoryBuilder",

    Builder {
        BuilderName = "Red Queen Engineer T3",
        PlatoonTemplate = "T3BuildEngineer",
        Priority = 870,
        PriorityFunction = EngineerPriority,
        BuilderType = "Land",
        BuilderConditions = {
            { ShouldBuildT3Engineer, {} },
            { InstantBuildConditions, "BrainNotLowMassMode", {} },
            { UnitCountBuildConditions, "UnitCapCheckLess", { 0.9 } },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.FACTORY * categories.LAND * categories.TECH3 } },
        },
    },
    Builder {
        BuilderName = "Red Queen Engineer T2",
        PlatoonTemplate = "T2BuildEngineer",
        Priority = 860,
        PriorityFunction = EngineerPriority,
        BuilderType = "Land",
        BuilderConditions = {
            { ShouldBuildT2Engineer, {} },
            { InstantBuildConditions, "BrainNotLowMassMode", {} },
            { UnitCountBuildConditions, "UnitCapCheckLess", { 0.9 } },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.FACTORY * categories.LAND * categories.TECH2 } },
        },
    },
    Builder {
        BuilderName = "Red Queen Engineer T1",
        PlatoonTemplate = "T1BuildEngineer",
        Priority = 850,
        PriorityFunction = EngineerPriority,
        BuilderType = "Land",
        BuilderConditions = {
            { ShouldBuildT1Engineer, {} },
            { InstantBuildConditions, "BrainNotLowMassMode", {} },
            { UnitCountBuildConditions, "UnitCapCheckLess", { 0.9 } },
        },
    },
}

BuilderGroup {
    BuilderGroupName = "RedQueenEndgameBuilders",
    BuildersType = "EngineerBuilder",

    Builder {
        BuilderName = "Red Queen Assault Experimental Land",
        PlatoonTemplate = "T3EngineerBuilder",
        Priority = 930,
        PriorityFunction = ExperimentalPriority,
        InstanceCount = 1,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldBuildClassifiedExperimental, { "T4LandExperimental1" } },
            { HasMajorProjectSlot, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyCombined", { 0.85, 1.0 } },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.ENGINEER * categories.TECH3 } },
        },
        BuilderData = {
            Construction = {
                BuildClose = false,
                BaseTemplate = "ExpansionBaseTemplates",
                NearMarkerType = "Rally Point",
                BuildStructures = { "T4LandExperimental1" },
                Location = "LocationType",
            },
        },
    },
    Builder {
        BuilderName = "Red Queen Assault Experimental Megabot",
        PlatoonTemplate = "T3EngineerBuilder",
        Priority = 929,
        PriorityFunction = ExperimentalPriority,
        InstanceCount = 1,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldBuildClassifiedExperimental, { "T4LandExperimental3" } },
            { HasMajorProjectSlot, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyCombined", { 0.85, 1.0 } },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.ENGINEER * categories.TECH3 } },
        },
        BuilderData = {
            Construction = {
                BuildClose = false,
                BaseTemplate = "ExpansionBaseTemplates",
                NearMarkerType = "Rally Point",
                BuildStructures = { "T4LandExperimental3" },
                Location = "LocationType",
            },
        },
    },
    Builder {
        BuilderName = "Red Queen Assault Experimental Air",
        PlatoonTemplate = "T3EngineerBuilder",
        Priority = 928,
        PriorityFunction = ExperimentalPriority,
        InstanceCount = 1,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldBuildClassifiedExperimental, { "T4AirExperimental1" } },
            { HasMajorProjectSlot, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyCombined", { 0.85, 1.0 } },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.ENGINEER * categories.TECH3 } },
        },
        BuilderData = {
            Construction = {
                BuildClose = false,
                BaseTemplate = "ExpansionBaseTemplates",
                NearMarkerType = "Rally Point",
                BuildStructures = { "T4AirExperimental1" },
                Location = "LocationType",
            },
        },
    },
    Builder {
        BuilderName = "Red Queen Assault Experimental Naval",
        PlatoonTemplate = "T3EngineerBuilder",
        Priority = 927,
        PriorityFunction = ExperimentalPriority,
        InstanceCount = 1,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldBuildClassifiedExperimental, { "T4SeaExperimental1" } },
            { HasMajorProjectSlot, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyCombined", { 0.85, 1.0 } },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.ENGINEER * categories.TECH3 } },
            { MarkerBuildConditions, "MarkerLessThanDistance", { "Naval Area", 400 } },
        },
        BuilderData = {
            Construction = {
                BuildClose = false,
                BaseTemplate = "ExpansionBaseTemplates",
                NearMarkerType = "Naval Area",
                BuildStructures = { "T4SeaExperimental1" },
                Location = "LocationType",
            },
        },
    },
    Builder {
        BuilderName = "Red Queen Siege Experimental Mobile",
        PlatoonTemplate = "T3EngineerBuilder",
        Priority = 926,
        PriorityFunction = ExperimentalPriority,
        InstanceCount = 1,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldBuildClassifiedExperimental, { "T4LandExperimental2" } },
            { HasMajorProjectSlot, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyCombined", { 0.85, 1.0 } },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.ENGINEER * categories.TECH3 } },
        },
        BuilderData = {
            Construction = {
                BuildClose = false,
                BaseTemplate = "ExpansionBaseTemplates",
                NearMarkerType = "Rally Point",
                BuildStructures = { "T4LandExperimental2" },
                Location = "LocationType",
            },
        },
    },
    Builder {
        BuilderName = "Red Queen Siege Experimental Artillery",
        PlatoonTemplate = "T3EngineerBuilder",
        Priority = 925,
        PriorityFunction = ExperimentalPriority,
        InstanceCount = 1,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldBuildClassifiedExperimental, { "T4Artillery" } },
            { HasMajorProjectSlot, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyCombined", { 0.85, 1.0 } },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.ENGINEER * categories.TECH3 } },
        },
        BuilderData = {
            Construction = {
                BuildClose = false,
                BaseTemplate = "ExpansionBaseTemplates",
                NearMarkerType = "Rally Point",
                BuildStructures = { "T4Artillery" },
                Location = "LocationType",
            },
        },
    },
    Builder {
        BuilderName = "Red Queen Utility Experimental Economy",
        PlatoonTemplate = "T3EngineerBuilder",
        Priority = 923,
        PriorityFunction = ExperimentalPriority,
        InstanceCount = 1,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldBuildClassifiedExperimental, { "T4EconExperimental" } },
            { HasMajorProjectSlot, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyCombined", { 0.85, 1.0 } },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.ENGINEER * categories.TECH3 } },
        },
        BuilderData = {
            Construction = {
                BuildClose = false,
                BaseTemplate = "ExpansionBaseTemplates",
                NearMarkerType = "Rally Point",
                BuildStructures = { "T4EconExperimental" },
                Location = "LocationType",
            },
        },
    },
    Builder {
        BuilderName = "Red Queen Utility Experimental Satellite",
        PlatoonTemplate = "T3EngineerBuilder",
        Priority = 922,
        PriorityFunction = ExperimentalPriority,
        InstanceCount = 1,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldBuildClassifiedExperimental, { "T4SatelliteExperimental" } },
            { HasMajorProjectSlot, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyCombined", { 0.85, 1.0 } },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.ENGINEER * categories.TECH3 } },
        },
        BuilderData = {
            Construction = {
                BuildClose = false,
                BaseTemplate = "ExpansionBaseTemplates",
                NearMarkerType = "Rally Point",
                BuildStructures = { "T4SatelliteExperimental" },
                Location = "LocationType",
            },
        },
    },
    Builder {
        BuilderName = "Red Queen Siege Experimental Rapid Artillery",
        PlatoonTemplate = "T3EngineerBuilder",
        Priority = 924,
        PriorityFunction = ExperimentalPriority,
        InstanceCount = 1,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldBuildClassifiedExperimental, { "T3RapidArtillery" } },
            { HasMajorProjectSlot, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyCombined", { 0.85, 1.0 } },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.ENGINEER * categories.TECH3 } },
        },
        BuilderData = {
            Construction = {
                BuildClose = false,
                BaseTemplate = "ExpansionBaseTemplates",
                NearMarkerType = "Rally Point",
                BuildStructures = { "T3RapidArtillery" },
                Location = "LocationType",
            },
        },
    },
    -- FAF gates the Quantum Gateway behind already owning more than one
    -- experimental (T3 Gate Engineer, AIFactoryConstructionBuilders), which no
    -- Red Queen match has ever reached: it built zero support commanders across
    -- match 27741743 and its verification run while the two strongest humans
    -- built 43 and 37. This gates on the tier and power that actually pay for a
    -- gateway instead.
    Builder {
        BuilderName = "Red Queen Quantum Gateway",
        PlatoonTemplate = "T3EngineerBuilder",
        Priority = 910,
        InstanceCount = 1,
        BuilderType = "Any",
        BuilderConditions = {
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyCombined", { 0.85, 1.0 } },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.ENGINEER * categories.TECH3 } },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 1, categories.ENERGYPRODUCTION * categories.TECH3 } },
            { UnitCountBuildConditions, "HaveLessThanUnitsWithCategory", { 1, categories.GATE * categories.STRUCTURE } },
            { UnitCountBuildConditions, "UnitCapCheckLess", { 0.8 } },
        },
        BuilderData = {
            Construction = {
                BuildClose = true,
                BuildStructures = { "T3QuantumGate" },
                Location = "LocationType",
            },
        },
    },
    Builder {
        BuilderName = "Red Queen Strategic Missile",
        PlatoonTemplate = "T3EngineerBuilder",
        Priority = 940,
        PriorityFunction = NukePriority,
        InstanceCount = 1,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldBuildNuke, {} },
            { HasMajorProjectSlot, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyCombined", { 0.85, 1.0 } },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.ENGINEER * categories.TECH3 } },
        },
        BuilderData = {
            Construction = {
                BuildClose = true,
                BuildStructures = { "T3StrategicMissile" },
                Location = "LocationType",
            },
        },
    },
}

BuilderGroup {
    BuilderGroupName = "RedQueenEnergyBuilders",
    BuildersType = "EngineerBuilder",

    -- Highest generator the available engineers can actually raise. Ordered so
    -- the best one wins the sort; each is gated on its own engineer tier.
    Builder {
        BuilderName = "Red Queen Tech Energy T3",
        PlatoonTemplate = "T3EngineerBuilder",
        Priority = 955,
        InstanceCount = 2,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldBuildTechEnergyLarge, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.ENGINEER * categories.TECH3 } },
        },
        BuilderData = {
            Construction = {
                BuildClose = true,
                BuildStructures = { "T3EnergyProduction" },
                Location = "LocationType",
            },
        },
    },
    Builder {
        BuilderName = "Red Queen Tech Energy T2",
        PlatoonTemplate = "T2EngineerBuilder",
        Priority = 954,
        InstanceCount = 2,
        BuilderType = "Any",
        BuilderConditions = {
            { ShouldBuildTechEnergySmall, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { UnitCountBuildConditions, "HaveGreaterThanUnitsWithCategory", { 0, categories.ENGINEER * categories.TECH2 } },
        },
        BuilderData = {
            Construction = {
                BuildClose = true,
                BuildStructures = { "T2EnergyProduction" },
                Location = "LocationType",
            },
        },
    },
}

BuilderGroup {
    BuilderGroupName = "RedQueenCounterFactoryBuilders",
    BuildersType = "FactoryBuilder",

    -- Air first: a scout that ignores terrain covers far more of a large map
    -- per unit of time, which is the whole point of asking for one.
    Builder {
        BuilderName = "Red Queen Air Scout",
        PlatoonTemplate = "T1AirScout",
        Priority = 930,
        BuilderType = "Air",
        BuilderConditions = {
            { ShouldBuildScouts, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.70, 0.95 } },
        },
    },
    Builder {
        BuilderName = "Red Queen Land Scout",
        PlatoonTemplate = "T1LandScout",
        Priority = 920,
        BuilderType = "Land",
        BuilderConditions = {
            { ShouldBuildScouts, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.70, 0.95 } },
        },
    },

    Builder {
        BuilderName = "Red Queen T3 Gunship Counter",
        PlatoonTemplate = "T3AirGunship",
        Priority = 975,
        BuilderType = "Air",
        BuilderConditions = {
            { ShouldBuildGunships, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.70, 0.95 } },
            { UnitCountBuildConditions, "LocationFactoriesBuildingLess", { "LocationType", 3, categories.AIR * categories.GROUNDATTACK } },
        },
    },
    Builder {
        BuilderName = "Red Queen T2 Gunship Counter",
        PlatoonTemplate = "T2AirGunship",
        Priority = 965,
        BuilderType = "Air",
        BuilderConditions = {
            { ShouldBuildGunships, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.70, 0.95 } },
            { UnitCountBuildConditions, "LocationFactoriesBuildingLess", { "LocationType", 3, categories.AIR * categories.GROUNDATTACK } },
        },
    },
    Builder {
        BuilderName = "Red Queen T1 Gunship Counter",
        PlatoonTemplate = "T1Gunship",
        Priority = 955,
        BuilderType = "Air",
        BuilderConditions = {
            { ShouldBuildGunships, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.70, 0.95 } },
            { UnitCountBuildConditions, "LocationFactoriesBuildingLess", { "LocationType", 3, categories.AIR * categories.GROUNDATTACK } },
        },
    },

    Builder {
        BuilderName = "Red Queen T3 Fighter Counter",
        PlatoonTemplate = "T3AirFighter",
        Priority = 980,
        BuilderType = "Air",
        BuilderConditions = {
            { ShouldBuildAirDefense, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.70, 0.95 } },
            { UnitCountBuildConditions, "LocationFactoriesBuildingLess", { "LocationType", 3, categories.AIR * categories.ANTIAIR - categories.BOMBER } },
        },
    },
    Builder {
        BuilderName = "Red Queen T2 Fighter-Bomber Counter",
        PlatoonTemplate = "T2FighterBomber",
        Priority = 970,
        BuilderType = "Air",
        BuilderConditions = {
            { ShouldBuildAirDefense, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.70, 0.95 } },
            { UnitCountBuildConditions, "LocationFactoriesBuildingLess", { "LocationType", 3, categories.AIR * categories.ANTIAIR - categories.BOMBER } },
        },
    },
    Builder {
        BuilderName = "Red Queen T1 Fighter Counter",
        PlatoonTemplate = "T1AirFighter",
        Priority = 960,
        BuilderType = "Air",
        BuilderConditions = {
            { ShouldBuildAirDefense, {} },
            { InstantBuildConditions, "BrainNotLowPowerMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.70, 0.95 } },
            { UnitCountBuildConditions, "LocationFactoriesBuildingLess", { "LocationType", 3, categories.AIR * categories.ANTIAIR - categories.BOMBER } },
        },
    },
}

-- FAF's own T3 Sub Commander builder names PlatoonTemplate 'T3LandSubCommander',
-- which is not a registered template -- only 'T3LandSubCommander1' exists, and
-- that one is a three-unit HuntAI combat platoon. A support commander produced
-- through it would never reach an engineer manager. This template produces a
-- single support commander with no plan, so it returns to the pool, is claimed
-- by a base manager like any other engineer, and becomes available to forward
-- base construction with the highest build power on the field.
-- Land units formed into a platoon that Red Queen aims.
--
-- Deliberately the same shape as the native attack templates -- mobile land,
-- no engineers, no experimentals -- so it competes for the same units on the
-- same terms. What differs is the plan: native's LandAttack runs AttackForceAI
-- or HuntAI, which pick their own targets, and this one runs a plan that reads
-- the objective.
PlatoonTemplate {
    Name = "RedQueenDirectedLand",
    -- PlatoonFormManager builds { Name, Plan, unpack(GlobalSquads) } and hands
    -- that to CanFormPlatoon, so a template without a Plan produces one whose
    -- second element is nil and forms nothing -- silently, with no warning.
    -- The plan named here is started and then stopped immediately, because
    -- PlatoonAIFunction calls StopAI before forking ours; it only has to exist.
    Plan = "AttackForceAI",
    GlobalSquads = {
        {
            categories.MOBILE * categories.LAND
                - categories.EXPERIMENTAL
                - categories.ENGINEER
                - categories.COMMAND
                - categories.SCOUT,
            3, 40, "attack", "GrowthFormation",
        },
    },
}

BuilderGroup {
    BuilderGroupName = "RedQueenDirectedBuilders",
    BuildersType = "PlatoonFormBuilder",

    Builder {
        BuilderName = "Red Queen Directed Land Attack",
        PlatoonTemplate = "RedQueenDirectedLand",
        -- Above native's own land attack builders, so the units form here
        -- rather than there. Additive: native keeps forming everything else,
        -- and suppressing it outright cost four cells.
        Priority = 700,
        InstanceCount = 2,
        FormRadius = 10000,
        BuilderType = "Any",
        PlatoonAIFunction = {
            "/mods/TheRedQueen/lua/AI/RedQueen/PlatoonPlans.lua",
            "ObjectiveAttack",
        },
        BuilderConditions = {
            { HasDirectionTarget, {} },
        },
    },
}

PlatoonTemplate {
    Name = "RedQueenSupportCommander",
    FactionSquads = {
        UEF = { { "uel0301", 1, 1, "support", "None" } },
        Aeon = { { "ual0301", 1, 1, "support", "None" } },
        Cybran = { { "url0301", 1, 1, "support", "None" } },
        Seraphim = { { "xsl0301", 1, 1, "support", "None" } },
    },
}

BuilderGroup {
    BuilderGroupName = "RedQueenSupportCommanderBuilders",
    BuildersType = "FactoryBuilder",

    Builder {
        BuilderName = "Red Queen Support Commander",
        PlatoonTemplate = "RedQueenSupportCommander",
        Priority = 900,
        BuilderConditions = {
            { InstantBuildConditions, "BrainNotLowMassMode", {} },
            { EconomyBuildConditions, "GreaterThanEconEfficiencyOverTime", { 0.9, 1.1 } },
            { UnitCountBuildConditions, "UnitCapCheckLess", { 0.8 } },
            { UnitCountBuildConditions, "HaveLessThanUnitsWithCategory", { 6, categories.SUBCOMMANDER } },
        },
        BuilderType = "Gate",
    },
}
