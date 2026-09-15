local AIBuildStructures = import("/lua/AI/aibuildstructures.lua")
local AIAddBuilderTable = import("/lua/AI/AIAddBuilderTable.lua")
local BaseTemplates = import("/lua/basetemplates.lua")
local BuildingTemplates = import("/lua/buildingtemplates.lua")
local Constants = import("/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua")
local EngineerSurvival = import("/mods/TheRedQueen/lua/AI/RedQueen/EngineerSurvival.lua")
local Logger = import("/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua")

local CounterBuilders = import("/mods/TheRedQueen/lua/AI/RedQueen/CounterBuilders.lua")
import("/mods/TheRedQueen/lua/AI/RedQueen/FortificationBuilders.lua")

local function FindBuildingId(buildingTemplate, buildingType)
    for _, entry in pairs(buildingTemplate) do
        if entry[1] == buildingType then
            return entry[2]
        end
    end
    return nil
end

local function FactoryLayer(factory)
    local hash = factory:GetBlueprint().CategoriesHash or {}
    if hash.LAND then
        return "Land"
    end
    if hash.AIR then
        return "Air"
    end
    if hash.NAVAL then
        return "Naval"
    end
    -- Quantum Gateways are FACTORY/TECH3 but have no combat domain. They
    -- produce SACUs through FAF's Gate list, not land mainline units.
    return nil
end

local function IsAlive(unit)
    return unit
        and not unit.Dead
        and (not unit.BeenDestroyed or not unit:BeenDestroyed())
end

local function IsAvailable(unit)
    return IsAlive(unit) and unit:IsIdleState()
end

local function IsOwnedByBrain(unit, brain)
    return IsAlive(unit)
        and unit.GetArmy
        and brain.GetArmyIndex
        and unit:GetArmy() == brain:GetArmyIndex()
end

local function UnitTech(unit)
    local hash = unit:GetBlueprint().CategoriesHash or {}
    if hash.TECH3 then return 3 end
    if hash.TECH2 then return 2 end
    return 1
end

local function HasExpansionBase(brain, baseName)
    if brain.HasPlatoonList then
        local locations = brain.PBM and brain.PBM.Locations or {}
        for _, location in pairs(locations) do
            if location.LocationType == baseName then
                return true
            end
        end
        return false
    end
    return brain.BuilderManagers and brain.BuilderManagers[baseName] ~= nil
end

-- FAF's AIExecuteBuildStructure forwards its `closeToBuilder` argument straight
-- into aiBrain:FindPlaceToBuild, whose matching parameter is a game object.
-- Every FAF caller passes a unit or nil there. Lua `false` is a boolean, so the
-- engine rejects it with "Expected a game object" and the error propagates out
-- of the scheduler task. nil keeps the identical falsy control flow inside
-- AIExecuteBuildStructure while satisfying the engine. The pcall contains any
-- remaining engine rejection so one unbuildable site cannot abort the whole
-- production pass.
local function ExecuteBuildStructure(brain, builder, buildingType, buildingTemplate, baseTemplate, coordinateMode, reference)
    assert(coordinateMode == "relative" or coordinateMode == "absolute")
    local before = table.getn(builder.EngineerBuildQueue or {})
    local completed, result = pcall(
        AIBuildStructures.AIExecuteBuildStructure,
        brain,
        builder,
        buildingType,
        nil,
        coordinateMode == "relative",
        buildingTemplate,
        baseTemplate,
        reference
    )
    if not completed then
        return false, tostring(result)
    end
    local requestedEntry
    local blueprintId = FindBuildingId(buildingTemplate, buildingType)
    for index = before + 1, table.getn(builder.EngineerBuildQueue or {}) do
        local entry = builder.EngineerBuildQueue[index]
        if entry[1] == blueprintId then requestedEntry = entry; break end
    end
    return result and true or false, nil, requestedEntry
end

local FactionNames = { "UEF", "Aeon", "Cybran", "Seraphim", "Nomads" }

local function UnitTier(hash)
    if hash.TECH3 then return 3 end
    if hash.TECH2 then return 2 end
    return 1
end

local function UnitDomain(hash)
    if hash.AIR then return "Air" end
    if hash.NAVAL then return "Naval" end
    return "Land"
end

local function UnitRole(hash)
    if hash.ENGINEER or hash.SCOUT then return "Utility" end
    if hash.TRANSPORTFOCUS and not hash.GROUNDATTACK then return "Transport" end
    if hash.SHIELD or hash.COUNTERINTELLIGENCE then return "Shield" end
    if hash.INDIRECTFIRE or hash.ARTILLERY or hash.TACTICALMISSILEPLATFORM then
        return "Artillery"
    end
    if (hash.AIR or hash.LAND) and hash.ANTIAIR and not hash.BOMBER then return "AirDefense" end
    if hash.AIR and hash.ANTINAVY then return "Torpedo" end
    if hash.AIR and hash.GROUNDATTACK then return "GroundAttack" end
    return "Mainline"
end

-- The navigation graph a unit actually travels on.
--
-- Every engineer in the game crosses water: UEF and Cybran are
-- RULEUMT_AmphibiousFloating and Aeon and Seraphim are RULEUMT_Hover, at all
-- three tiers. So "Land" describes none of them, and the hover and amphibious
-- grids genuinely differ -- hover treats deep water as passable while
-- amphibious stops at depth 25 -- which is the same distinction that once left
-- a whole hover army without orders.
local MotionLayers = {
    RULEUMT_Hover = "Hover",
    RULEUMT_Amphibious = "Amphibious",
    RULEUMT_AmphibiousFloating = "Amphibious",
    RULEUMT_Air = "Air",
    RULEUMT_Water = "Water",
    RULEUMT_SurfacingSub = "Water",
}

-- Cancel native ownership of an engineer and send it home.
--
-- Both recall paths use this one implementation: the native build queue, the
-- callbacks and threads that would re-issue the order, and platoon ownership
-- all have to go before the move, or the engineer turns around and walks back.
-- `resume` schedules the native re-poll that hands the engineer back to FAF's
-- own work. A retreat wants it: the hook defers that poll until the unit is
-- home, and native picks it up from there. A caller that is about to issue its
-- own order does not -- the poll lands fifty ticks later and replaces it.
local function ReleaseEngineer(engineer, home, resume)
    if resume == nil then
        resume = true
    end
    return pcall(function()
        if home then
            engineer.RedQueenRetreatPosition = { home[1], home[2], home[3] }
        end
        engineer.EngineerBuildQueue = {}
        for _, field in ipairs({ "ProcessBuild", "NotBuildingThread", "ForkedEngineerTask" }) do
            if engineer[field] then
                KillThread(engineer[field])
                engineer[field] = nil
            end
        end
        engineer.ProcessBuildDone = nil
        local platoon = engineer.PlatoonHandle
        if platoon and not platoon.ArmyPool then
            platoon:PlatoonDisband()
        end
        -- Disband calls TaskFinished/DelayAssign and may create a new native
        -- assignment thread. Cancel that thread too before issuing the move.
        if engineer.ForkedEngineerTask then
            KillThread(engineer.ForkedEngineerTask)
            engineer.ForkedEngineerTask = nil
        end
        engineer.PlatoonHandle = nil
        IssueClearCommands({ engineer })
        if home then
            IssueMove({ engineer }, home)
        end
        local manager = engineer.BuilderManagerData and engineer.BuilderManagerData.EngineerManager
        if resume and manager and manager.DelayAssign then
            -- The hook defers this poll until arrival, then restores native work.
            manager:DelayAssign(engineer, 50)
        end
    end)
end

local function UnitTravelLayer(unit)
    if not unit or not unit.GetBlueprint then
        return "Land"
    end
    local blueprint = unit:GetBlueprint() or {}
    local physics = blueprint.Physics or {}
    return MotionLayers[physics.MotionType] or "Land"
end

local function BuilderProfile(builder, factionName)
    if builder.RedQueenUnitProfile then
        return builder.RedQueenUnitProfile
    end
    if not builder.GetPlatoonTemplate or not PlatoonTemplates or not __blueprints then
        return nil
    end
    local template = PlatoonTemplates[builder:GetPlatoonTemplate()]
    local squads = template and template.FactionSquads and template.FactionSquads[factionName]
    local blueprintId = squads and squads[1] and squads[1][1]
    local blueprint = blueprintId and __blueprints[blueprintId]
    local hash = blueprint and blueprint.CategoriesHash
    if not hash or not hash.MOBILE then
        return nil
    end
    return {
        BlueprintId = blueprintId,
        Tier = UnitTier(hash),
        Domain = UnitDomain(hash),
        Role = UnitRole(hash),
        -- Carried separately because UnitRole lumps engineers with scouts, and
        -- engineer establishment is governed on its own terms.
        Engineer = (hash.ENGINEER and not hash.COMMAND) or false,
    }
end

local function GuardBuilderPriority(builder)
    if builder.RedQueenOriginalCalculatePriority or not builder.CalculatePriority then
        return
    end
    builder.RedQueenOriginalCalculatePriority = builder.CalculatePriority
    builder.CalculatePriority = function(current, manager)
        -- RedQueenRetired is set once at teardown and never cleared: a retired
        -- builder must not be revived by FAF's own priority recalculation.
        if current.RedQueenRetired
            or current.RedQueenTierDisabled
            or current.RedQueenCapacityDisabled
            or current.RedQueenEngineerDisabled
        then
            local changed = current.Priority ~= 0
            current.Priority = 0
            return changed
        end
        return current.RedQueenOriginalCalculatePriority(current, manager)
    end
end

local function DistanceSquared(a, b)
    local dx = a[1] - b[1]
    local dz = a[3] - b[3]
    return dx * dx + dz * dz
end

-- Returns the factory domains a builder can construct, and whether the builder
-- is a *pure* factory builder.
--
-- FAF ships two very different kinds of builder that both mention a factory.
-- The 20 pure ones (AIFactoryConstructionBuilders, AINavalBuilders) build
-- exactly one structure: a factory. The 13 mixed ones (AIExpansionBuilders and
-- two naval entries) create a whole expansion or naval base -- point defence,
-- radar, anti-air, shields, tactical missiles -- with a factory as one late
-- line item. Capping the mixed ones on factory count alone stops the AI taking
-- and holding ground, which is what happened in match 27741743.
-- How many batteries the economy can justify right now.
--
-- Artillery is a supplement, not a first response. It is the most expensive
-- thing in the defensive vocabulary -- roughly 1900 mass against 250 for a
-- Tech 1 point defence -- and its 50 minimum radius means a closing army walks
-- inside it. Building it early is how a controlled Sentry Point victory
-- (K/L 1.43) became a defeat (1.00) with eight batteries on a dry map. So the
-- appetite starts at zero and opens up only as the economy reaches the tiers
-- that define the late game, reusing the same income thresholds that already
-- gate Tech 3, experimentals and nukes.
-- A factory under construction is already its finished unit as far as the
-- engine is concerned: a Tech 3 upgrade exists as a Tech 3 factory the instant
-- it starts, and reports Tech 3 categories for the whole time it is building.
local function IsFactoryComplete(factory)
    if not factory.GetFractionComplete then
        return true
    end
    return factory:GetFractionComplete() >= 1
end

local function ShoreArtilleryAllowance(massIncome)
    local policy = Constants.Policy
    if massIncome >= policy.NukeMinimumMassIncome then
        return 4
    elseif massIncome >= policy.ExperimentalMinimumMassIncome then
        return 2
    elseif massIncome >= policy.Tech3MinimumMassIncome then
        return 1
    end
    return 0
end

local function BuilderConstructionDomains(builder)
    local cached = builder.RedQueenFactoryDomains
    if cached ~= nil then
        return cached or nil, builder.RedQueenFactoryPure
    end
    local structures = builder.RedQueenConstructionTypes
    if not structures and Builders and builder.BuilderName then
        local definition = Builders[builder.BuilderName]
        local construction = definition
            and definition.BuilderData
            and definition.BuilderData.Construction
        structures = construction and construction.BuildStructures
    end
    if not structures then
        builder.RedQueenFactoryDomains = false
        builder.RedQueenFactoryPure = false
        return nil, false
    end

    local domains = {}
    local found = false
    local total = 0
    local factories = 0
    for _, structureType in pairs(structures) do
        total = total + 1
        if string.find(structureType, "Factory") then
            factories = factories + 1
            if string.find(structureType, "Air") then
                domains.Air = true
                found = true
            elseif string.find(structureType, "Sea") or string.find(structureType, "Naval") then
                domains.Naval = true
                found = true
            elseif string.find(structureType, "Land") then
                domains.Land = true
                found = true
            end
        end
    end
    local pure = found and factories == total
    builder.RedQueenFactoryDomains = found and domains or false
    builder.RedQueenFactoryPure = pure
    return found and domains or nil, pure
end

---@class RedQueenProductionManager
ProductionManager = ClassSimple {
    __init = function(self, brain, context, world, economy, intel, strategy)
        self.Brain = brain
        self.Context = context
        self.World = world
        self.Economy = economy
        self.Intel = intel
        self.Strategy = strategy
        self.LastFactoryRequestTick = -100000
        self.FactoryAssistants = {}
        self.LastEmergencyDefenseTick = -100000
        self.LastShoreArtilleryTick = -100000
        self.LastShoreTorpedoTick = -100000
        self.LastEmergencyDefenseLogTick = -100000
        self.CounterBuildersRegistered = {}
        self.RoleAvailability = {}
        self.TierPolicy = {
            Land = { Highest = 1 },
            Air = { Highest = 1 },
            Naval = { Highest = 1 },
        }
        self.LastTierSummary = ""
        self.ForwardBases = {}
        self.ForwardBaseClaims = {}
        self.ForwardBaseActive = nil
        self.LastForwardBaseTick = -100000
        self.ForwardBaseSequence = 0
        self.LastForwardBaseBlockReason = nil
        self.LastForwardBaseBlockLogTick = -100000
        self.LastFactoryCapSummary = ""
        self.LastFactoryCapLogTick = -100000
    end,

    RegisterCounterBuilders = function(self)
        -- FAF's adaptive plan initializes MAIN after a short delay. Registering
        -- even one custom factory builder before that happens makes its
        -- FactoryManager:HasBuilderList() guard succeed, so the native base
        -- template is skipped and the starting commander remains idle. Some
        -- scenarios pre-populate AIBase and manager lists can be populated by
        -- other extensions. BaseSettings is written only after FAF finishes
        -- installing the complete native base template.
        local armySetup = ScenarioInfo
            and ScenarioInfo.ArmySetup
            and ScenarioInfo.ArmySetup[self.Brain.Name]
        if not armySetup or not armySetup.AIBase then
            return
        end

        local managers = self.Brain.BuilderManagers
        if not managers then
            return
        end

        local locationTypes = {}
        for locationType, _ in pairs(managers) do
            table.insert(locationTypes, locationType)
        end
        table.sort(locationTypes)

        for _, locationType in pairs(locationTypes) do
            local manager = managers[locationType]
            if manager
                and manager.FactoryManager
                and manager.BaseSettings
                and self.CounterBuildersRegistered[locationType] ~= manager
            then
                local handles = manager.BuilderHandles or {}
                if not handles.RedQueenTierDominanceBuilders then
                    AIAddBuilderTable.AddGlobalBuilderGroup(
                        self.Brain,
                        locationType,
                        "RedQueenTierDominanceBuilders"
                    )
                    manager.FactoryManager:SortBuilderList("Land")
                    manager.FactoryManager:SortBuilderList("Air")
                    manager.FactoryManager:SortBuilderList("Sea")
                end

                handles = manager.BuilderHandles or handles
                if not handles.RedQueenCounterFactoryBuilders then
                    AIAddBuilderTable.AddGlobalBuilderGroup(
                        self.Brain,
                        locationType,
                        "RedQueenCounterFactoryBuilders"
                    )
                    manager.FactoryManager:SortBuilderList("Air")
                end

                -- "Gate" is a first-class factory type in FAF's
                -- FactoryBuilderManager, which calls SetupNewFactory(unit, "Gate")
                -- for a Quantum Gateway, so support commander production sorts
                -- alongside the land, air and sea lists.
                handles = manager.BuilderHandles or handles
                if not handles.RedQueenSupportCommanderBuilders then
                    AIAddBuilderTable.AddGlobalBuilderGroup(
                        self.Brain,
                        locationType,
                        "RedQueenSupportCommanderBuilders"
                    )
                    manager.FactoryManager:SortBuilderList("Gate")
                end

                handles = manager.BuilderHandles or handles
                if manager.PlatoonFormManager
                    and not handles.RedQueenTechUpgradeBuilders
                then
                    AIAddBuilderTable.AddGlobalBuilderGroup(
                        self.Brain,
                        locationType,
                        "RedQueenTechUpgradeBuilders"
                    )
                    manager.PlatoonFormManager:SortBuilderList("Any")
                end

                handles = manager.BuilderHandles or handles
                if manager.EngineerManager
                    and not handles.RedQueenEndgameBuilders
                then
                    AIAddBuilderTable.AddGlobalBuilderGroup(
                        self.Brain,
                        locationType,
                        "RedQueenEndgameBuilders"
                    )
                    manager.EngineerManager:SortBuilderList("Any")
                end

                handles = manager.BuilderHandles or handles
                if manager.FactoryManager
                    and not handles.RedQueenEngineerBuilders
                then
                    AIAddBuilderTable.AddGlobalBuilderGroup(
                        self.Brain,
                        locationType,
                        "RedQueenEngineerBuilders"
                    )
                    manager.FactoryManager:SortBuilderList("Land")
                end

                handles = manager.BuilderHandles or handles
                if manager.EngineerManager
                    and not handles.RedQueenEnergyBuilders
                then
                    AIAddBuilderTable.AddGlobalBuilderGroup(
                        self.Brain,
                        locationType,
                        "RedQueenEnergyBuilders"
                    )
                    manager.EngineerManager:SortBuilderList("Any")
                end

                handles = manager.BuilderHandles or handles
                if manager.EngineerManager
                    and not handles.RedQueenEmergencyFortificationBuilders
                then
                    AIAddBuilderTable.AddGlobalBuilderGroup(
                        self.Brain,
                        locationType,
                        "RedQueenEmergencyFortificationBuilders"
                    )
                    manager.EngineerManager:SortBuilderList("Any")
                end
                self.CounterBuildersRegistered[locationType] = manager
                Logger.Info(self.Brain, string.format(
                    "adaptive production registered base=%s",
                    tostring(locationType)
                ))
            end
        end
    end,

    -- Behaviour flags come from the match profile. Absent a profile -- the pure
    -- Lua specs build managers directly -- every optional behaviour is on, so a
    -- contract exercises the code rather than the selection.
    ProfileFlag = function(self, name)
        local profile = self.Brain and self.Brain.RedQueenProfile
        if not profile then
            return true
        end
        return profile:Flag(name)
    end,

    CountFactories = function(self)
        local factories = self.Brain:GetListOfUnits(categories.STRUCTURE * categories.FACTORY, false)
        local counts = { Total = 0, Land = 0, Air = 0, Naval = 0 }
        for _, factory in pairs(factories) do
            if factory and not factory.Dead then
                local layer = FactoryLayer(factory)
                if layer then
                    -- Total feeds the same combat capacity budget as the
                    -- domain targets; a gateway cannot satisfy either.
                    counts.Total = counts.Total + 1
                    counts[layer] = counts[layer] + 1
                end
            end
        end
        return factories, counts
    end,

    GetFactoryTargets = function(self, counts)
        local demand = self.Strategy.ProductionDemand or {}
        local order = { "Land", "Air", "Naval" }
        local targets = { Land = 0, Air = 0, Naval = 0 }
        local relevant = {}
        -- Relevance is demand-only. Deriving it from the current factory count
        -- would let a single stray factory make its domain permanently
        -- relevant, ratcheting the sustainable total up and never back down.
        for _, domain in pairs(order) do
            if (demand[domain] or 0) >= 0.10 then
                targets[domain] = 1
                table.insert(relevant, domain)
            end
        end
        if table.getn(relevant) == 0 then
            relevant = { "Land" }
            targets.Land = 1
        end

        local desired = math.max(
            self.Economy.State.DesiredFactories or 1,
            table.getn(relevant)
        )
        local remaining = desired - table.getn(relevant)
        while remaining > 0 do
            local selected = relevant[1]
            local selectedNeed = -1000000
            for _, domain in pairs(relevant) do
                local need = (demand[domain] or 0) * desired - targets[domain]
                if need > selectedNeed then
                    selected = domain
                    selectedNeed = need
                end
            end
            targets[selected] = targets[selected] + 1
            remaining = remaining - 1
        end
        targets.Total = desired
        return targets
    end,

    -- How many managed base locations this map is worth. One main base plus one
    -- per expansion-capable marker the world model found, bounded so a
    -- marker-rich map cannot ask for an unbounded number of locations.
    GetBaseAppetite = function(self)
        local candidates = table.getn(
            (self.World and self.World.ForwardBaseCandidates) or {}
        )
        return math.max(1, math.min(
            Constants.Policy.MaximumManagedBases,
            1 + candidates
        ))
    end,

    CountManagedBases = function(self)
        local count = 0
        for _, manager in pairs(self.Brain.BuilderManagers or {}) do
            if manager and manager.EngineerManager then
                count = count + 1
            end
        end
        return count
    end,

    ApplyFactoryCapacityPolicy = function(self, counts)
        local targets = self:GetFactoryTargets(counts)
        counts.TargetTotal = targets.Total
        local managers = self.Brain.BuilderManagers or {}
        local locationTypes = {}
        for locationType, _ in pairs(managers) do
            table.insert(locationTypes, locationType)
        end
        table.sort(locationTypes)

        -- Mixed builders create bases, so they answer to the map's base
        -- appetite rather than to the factory target.
        local managedBases = self:CountManagedBases()
        local baseAppetite = self:GetBaseAppetite()
        local expansionSlotsRemaining = managedBases < baseAppetite
        local mixedSkipped = 0

        for _, locationType in pairs(locationTypes) do
            local engineerManager = managers[locationType].EngineerManager
            if engineerManager and engineerManager.BuilderData then
                for builderType, data in pairs(engineerManager.BuilderData) do
                    local changed = false
                    for _, builder in pairs(data.Builders or {}) do
                        local domains, pure = BuilderConstructionDomains(builder)
                        if domains then
                            local needed = false
                            for domain, _ in pairs(domains) do
                                if (counts[domain] or 0) < (targets[domain] or 0) then
                                    needed = true
                                end
                            end
                            -- A mixed builder's factory is incidental to the
                            -- base it creates. It stays enabled while the map
                            -- still has unclaimed base slots, however many
                            -- factories its domain already holds.
                            if not pure and expansionSlotsRemaining and not needed then
                                needed = true
                                mixedSkipped = mixedSkipped + 1
                            end
                            local disabled = not needed
                            if disabled and not builder.RedQueenCapacityDisabled then
                                GuardBuilderPriority(builder)
                                builder.RedQueenCapacityDisabled = true
                                builder.RedQueenCapacityPriority = builder.Priority
                                if builder.SetPriority then
                                    builder:SetPriority(0)
                                else
                                    builder.Priority = 0
                                end
                                changed = true
                            elseif not disabled and builder.RedQueenCapacityDisabled then
                                builder.RedQueenCapacityDisabled = false
                                local priority = builder.RedQueenCapacityPriority
                                    or builder.OriginalPriority
                                    or 1
                                if builder.SetPriority then
                                    builder:SetPriority(priority)
                                else
                                    builder.Priority = priority
                                end
                                changed = true
                            end
                        end
                    end
                    if changed and engineerManager.SortBuilderList then
                        engineerManager:SortBuilderList(builderType)
                    end
                end
            end
        end

        local summary = string.format(
            "L%d/%d A%d/%d N%d/%d bases=%d/%d mixed=%d",
            counts.Land or 0, targets.Land or 0,
            counts.Air or 0, targets.Air or 0,
            counts.Naval or 0, targets.Naval or 0,
            managedBases, baseAppetite, mixedSkipped
        )
        local tick = GetGameTick()
        if summary ~= self.LastFactoryCapSummary
            and tick - self.LastFactoryCapLogTick
                >= Constants.Policy.FactoryCapDiagnosticSeconds * 10
        then
            self.LastFactoryCapSummary = summary
            self.LastFactoryCapLogTick = tick
            Logger.Info(self.Brain, "factory cap " .. summary)
        end
        return targets
    end,

    UpdateTierPolicy = function(self, factories)
        -- Highest is the capability ceiling and must not dip while a factory
        -- upgrades: the engine consumes the old factory the instant the upgrade
        -- starts, so a domain whose only factory is upgrading would briefly
        -- report a lower tier and the exact-match dominance gates would thrash
        -- between tiers. Ready is the same figure counting only finished
        -- factories, and is what may obsolete lower-tier production.
        local policy = {
            Land = { Highest = 1, Ready = 1, T1 = 0, T2 = 0, T3 = 0 },
            Air = { Highest = 1, Ready = 1, T1 = 0, T2 = 0, T3 = 0 },
            Naval = { Highest = 1, Ready = 1, T1 = 0, T2 = 0, T3 = 0 },
        }
        for _, factory in pairs(factories) do
            if factory and not factory.Dead then
                local domain = FactoryLayer(factory)
                local domainPolicy = policy[domain]
                if domainPolicy then
                    local tier = UnitTech(factory)
                    -- Unfinished factories still count toward capacity, so planning
                    -- does not order a duplicate of something already building.
                    domainPolicy["T" .. tostring(tier)] = domainPolicy["T" .. tostring(tier)] + 1
                    domainPolicy.Highest = math.max(domainPolicy.Highest, tier)
                    -- Only a completed factory may obsolete lower-tier production.
                    -- A Tech 3 upgrade cannot build anything for the roughly 219
                    -- simulation seconds it takes to finish; on Fields of Isis
                    -- counting it as ready suppressed every lower-tier combat
                    -- builder for that whole window.
                    if IsFactoryComplete(factory) then
                        domainPolicy.Ready = math.max(domainPolicy.Ready, tier)
                    end
                end
            end
        end
        self.TierPolicy = policy
        self.Strategy.ProductionDemand.TierPolicy = policy

        -- Counted once per pass and cached: IsObsoleteProfile runs per builder.
        local previousTransports = self.TransportCount or 0
        self.TransportCount = self.Brain.GetCurrentUnits
            and self.Brain:GetCurrentUnits(categories.TRANSPORTFOCUS - categories.GROUNDATTACK)
            or 0
        local capped = self.TransportCount >= Constants.Policy.MaximumTransports
        if capped ~= (previousTransports >= Constants.Policy.MaximumTransports) then
            Logger.Info(self.Brain, string.format(
                "transport budget %s count=%d cap=%d",
                capped and "reached" or "released",
                self.TransportCount,
                Constants.Policy.MaximumTransports
            ))
        end

        local summary = string.format(
            "L%d/A%d/N%d",
            policy.Land.Highest,
            policy.Air.Highest,
            policy.Naval.Highest
        )
        if summary ~= self.LastTierSummary then
            self.LastTierSummary = summary
            Logger.Info(self.Brain, "tier policy " .. summary)
        end
        return policy
    end,

    HasRoleAtTier = function(self, domain, role, tier)
        if role == "Mainline" then
            return true
        end
        if role == "Utility" then
            return false
        end
        local key = domain .. ":" .. role .. ":" .. tostring(tier)
        if self.RoleAvailability[key] ~= nil then
            return self.RoleAvailability[key]
        end
        if not EntityCategoryGetUnitList then
            return false
        end

        local factionCategory = categories[string.upper(FactionNames[self.Context.FactionIndex] or "UEF")]
        local domainCategory = domain == "Air" and categories.AIR
            or domain == "Naval" and categories.NAVAL
            or categories.LAND
        local category = categories.MOBILE * domainCategory * categories["TECH" .. tostring(tier)]
            * factionCategory
        if role == "Transport" then
            category = category * categories.TRANSPORTFOCUS - categories.GROUNDATTACK
        elseif role == "Shield" then
            category = category * (categories.SHIELD + categories.COUNTERINTELLIGENCE)
        elseif role == "Artillery" then
            category = category * (categories.INDIRECTFIRE + categories.ARTILLERY)
        elseif role == "AirDefense" then
            category = category * categories.ANTIAIR - categories.BOMBER
        elseif role == "Torpedo" then
            category = category * categories.ANTINAVY
        elseif role == "GroundAttack" then
            category = category * categories.GROUNDATTACK
        end
        local units = EntityCategoryGetUnitList(category) or {}
        local available = table.getn(units) > 0
        self.RoleAvailability[key] = available
        return available
    end,

    -- Tech 1 mainline production against an observed Tech 3 enemy is mass
    -- thrown away. UpdateTierPolicy only ever describes the highest *surviving*
    -- factory, so a domain whose Tech 2 and Tech 3 factories have been killed
    -- silently reverts to Tech 1 mainline -- which is how match 27741743 built
    -- 925 Tech 1 units across 73 minutes while ending at tiers L3,A1,N1.
    -- Suppressing the obsolete mainline leaves the surviving factory free to
    -- take an upgrade instead. Gated on that domain's upgrade eligibility, so a
    -- brain unable to upgrade retains fallback production, and scoped to Mainline
    -- so specialist Tech 1 roles such as scouts and mobile anti-air survive.
    ShouldSuppressLowTierMainline = function(self, profile, highest)
        if profile.Role ~= "Mainline" or profile.Tier > 1 or highest > 1 then
            return false
        end
        if (self.Intel.HighestObservedTech or 1) < 3 then
            return false
        end
        return CounterBuilders.ShouldTechToT2(self.Brain, profile.Domain) or false
    end,

    IsObsoleteProfile = function(self, profile)
        if not profile or profile.Role == "Utility" then
            return false
        end

        -- Transports are excluded from combat waves and from forward-base
        -- garrisons, so a surplus does nothing but sit still. Match 27741743
        -- built 50 across three brains for zero kills, and a mirror match had
        -- one brain holding 30 by minute 24. Cap the fleet and let FAF's own
        -- transport plans work within it.
        if profile.Role == "Transport"
            and (self.TransportCount or 0) >= Constants.Policy.MaximumTransports
        then
            return true
        end

        -- Obsolescence source is scoped to the map.
        --
        -- Ready holds lower-tier production alive through an upgrade, because a
        -- tier that exists only as an unfinished factory cannot replace what it
        -- would retire. That is a volume strategy and it needs room to pay off:
        -- on large maps it lifted Fields of Isis from K/L 0.27 to 0.41 (Tech 3
        -- units 3 to 20) and Syrtis Major from 0.55 to 0.84, but on 5 km Sentry
        -- Point the diluted army lost a won game, 0.96 down to 0.67.
        local domainPolicy = self.TierPolicy[profile.Domain] or {}
        local highest
        if self:ProfileFlag("TierReadinessObsolescence") then
            highest = domainPolicy.Ready or domainPolicy.Highest or 1
        else
            highest = domainPolicy.Highest or 1
        end
        if self:ShouldSuppressLowTierMainline(profile, highest) then
            return true
        end
        if profile.Tier >= highest then
            return false
        end
        if profile.Role == "Mainline" then
            return true
        end
        for tier = profile.Tier + 1, highest do
            if self:HasRoleAtTier(profile.Domain, profile.Role, tier) then
                return true
            end
        end
        return false
    end,

    -- Hold engineer production to the army's own target.
    --
    -- FAF's engineer rule is per *location* -- "fewer than four here" -- so it
    -- scales with base count rather than with need. Crossfire Canal ran 21
    -- managed bases and reached 101 engineers against a target of 18, then
    -- converted a 66-mass economy and a full Tech 3 tier into units that do not
    -- fight, traded evenly, and lost on attrition. Red Queen's own builders
    -- already stop at the target; this stops the native ones too, which is the
    -- only way a global target can bind.
    --
    -- Suppression is by priority and never by definition, and it reverses the
    -- moment losses lift the target above what is held -- so a bleeding army
    -- resumes building immediately.
    --
    -- What it must not do is cut at the target itself. `DesiredEngineers` is
    -- derived from factory count, so holding native production to it made
    -- engineers the constraint on building factories, and the army stayed at
    -- its opening size: two Crossfire cells ran 3 engineers where they had run
    -- 15-20, and finished on 6 factories instead of 26. The ceiling therefore
    -- scales with what there is to feed and sits above the target, so the
    -- policy trims a runaway without capping growth.
    ApplyEngineerPolicy = function(self, counts)
        local demand = self.Strategy and self.Strategy.ProductionDemand
        local target = demand and demand.DesiredEngineers or 0
        if target < 1 then
            return
        end
        local held = self.Brain.GetCurrentUnits
            and self.Brain:GetCurrentUnits(categories.ENGINEER * categories.MOBILE)
            or 0
        -- Planned capacity as well as built, so the ceiling rises before the
        -- factories exist rather than after -- otherwise it is the same loop
        -- one step removed.
        local economy = self.Economy and self.Economy.State or {}
        local factories = (counts or self.Counts or {}).Total or 0
        local feeding = math.max(factories, economy.DesiredFactories or 0)
        local ceiling = math.max(
            Constants.Policy.EngineerSuppressionMinimum,
            math.ceil(feeding * Constants.Policy.EngineerSuppressionPerFactory)
        )
        local surplus = held >= ceiling
        local factionName = FactionNames[self.Context.FactionIndex] or "UEF"
        local managers = self.Brain.BuilderManagers or {}
        local locationTypes = {}
        for locationType, _ in pairs(managers) do
            table.insert(locationTypes, locationType)
        end
        table.sort(locationTypes)

        local suppressed = 0
        for _, locationType in pairs(locationTypes) do
            local factoryManager = managers[locationType].FactoryManager
            if factoryManager and factoryManager.BuilderData then
                for _, builderType in pairs({ "Land", "Air", "Sea" }) do
                    local data = factoryManager.BuilderData[builderType]
                    local changed = false
                    if data and data.Builders then
                        for _, builder in pairs(data.Builders) do
                            local profile = BuilderProfile(builder, factionName)
                            if profile and profile.Engineer then
                                if surplus and not builder.RedQueenEngineerDisabled then
                                    GuardBuilderPriority(builder)
                                    builder.RedQueenEngineerDisabled = true
                                    builder.RedQueenEngineerPriority = builder.Priority
                                    if builder.SetPriority then
                                        builder:SetPriority(0)
                                    else
                                        builder.Priority = 0
                                    end
                                    changed = true
                                elseif not surplus and builder.RedQueenEngineerDisabled then
                                    builder.RedQueenEngineerDisabled = false
                                    local priority = builder.RedQueenEngineerPriority
                                        or builder.OriginalPriority
                                        or 1
                                    if builder.SetPriority then
                                        builder:SetPriority(priority)
                                    else
                                        builder.Priority = priority
                                    end
                                    changed = true
                                end
                                if builder.RedQueenEngineerDisabled then
                                    suppressed = suppressed + 1
                                end
                            end
                        end
                    end
                    if changed and factoryManager.SortBuilderList then
                        factoryManager:SortBuilderList(builderType)
                    end
                end
            end
        end
        -- Reported so a log can show whether the ceiling bound at all. The
        -- previous version was inferable only by noticing that held tracked
        -- the target exactly, which is how it went unnoticed for a full matrix.
        local previous = self.EngineerPolicy or {}
        self.EngineerPolicy = {
            Held = held,
            Target = target,
            Ceiling = ceiling,
            Suppressed = suppressed,
        }
        if (previous.Suppressed or 0) > 0 ~= (suppressed > 0) then
            Logger.Info(self.Brain, string.format(
                "engineer policy %s held=%d target=%d ceiling=%d builders=%d",
                suppressed > 0 and "suppressing" or "released",
                held,
                target,
                ceiling,
                suppressed
            ))
        end
        return self.EngineerPolicy
    end,

    ApplyTierPolicy = function(self)
        local factionName = FactionNames[self.Context.FactionIndex] or "UEF"
        local managers = self.Brain.BuilderManagers or {}
        local locationTypes = {}
        for locationType, _ in pairs(managers) do
            table.insert(locationTypes, locationType)
        end
        table.sort(locationTypes)

        for _, locationType in pairs(locationTypes) do
            local factoryManager = managers[locationType].FactoryManager
            if factoryManager and factoryManager.BuilderData then
                for _, builderType in pairs({ "Land", "Air", "Sea" }) do
                    local data = factoryManager.BuilderData[builderType]
                    local changed = false
                    if data and data.Builders then
                        for _, builder in pairs(data.Builders) do
                            local profile = BuilderProfile(builder, factionName)
                            local obsolete = self:IsObsoleteProfile(profile)
                            if obsolete and not builder.RedQueenTierDisabled then
                                GuardBuilderPriority(builder)
                                builder.RedQueenTierDisabled = true
                                builder.RedQueenTierPriority = builder.Priority
                                if builder.SetPriority then
                                    builder:SetPriority(0)
                                else
                                    builder.Priority = 0
                                end
                                changed = true
                            elseif not obsolete and builder.RedQueenTierDisabled then
                                builder.RedQueenTierDisabled = false
                                local priority = builder.RedQueenTierPriority or builder.OriginalPriority or 1
                                if builder.SetPriority then
                                    builder:SetPriority(priority)
                                else
                                    builder.Priority = priority
                                end
                                changed = true
                            end
                        end
                    end
                    if changed and factoryManager.SortBuilderList then
                        factoryManager:SortBuilderList(builderType)
                    end
                end
            end
        end
    end,

    -- ApplyFactoryCapacityPolicy owns the per-domain allocation. Red Queen's own
    -- expansion must consume the same targets rather than re-deriving a second,
    -- divergent mix, so it can never build into a domain the policy has capped.
    SelectFactoryType = function(self, counts, targets)
        local buildingTypes = {
            Land = "T1LandFactory",
            Air = "T1AirFactory",
            Naval = "T1SeaFactory",
        }
        local selected = nil
        local selectedDeficit = 0
        for _, domain in pairs({ "Land", "Air", "Naval" }) do
            local deficit = (targets[domain] or 0) - (counts[domain] or 0)
            if domain == "Naval" and self.World.WaterRatio < 0.20 then
                deficit = 0
            end
            if deficit > selectedDeficit then
                selected = domain
                selectedDeficit = deficit
            end
        end
        return selected and buildingTypes[selected] or nil
    end,

    -- Factory expansion draws from base managers for the same reason forward
    -- bases do: EngineerManager:AddUnit claims every new engineer, so ArmyPool
    -- holds one or two in transit. Searching only the pool meant four Red Queen
    -- subsystems contended for a single engineer, and several of them issue
    -- IssueClearCommands, so a queued factory was repeatedly cancelled -- the
    -- Red Queen versus stock Adaptive rematch logged four expansion requests
    -- against one factory.
    FindIdleBuilder = function(self, blueprintId)
        -- Prefer an idle engineer, but do not require one. An instrumented run
        -- found all four engineers reporting idle=no building=no for every
        -- sample, so a strict idle requirement finds nobody and expansion never
        -- fires. Orders given to a busy engineer are often re-tasked away by
        -- FAF's manager, but enough survive to matter: the run that allowed
        -- them reached two factories where the run before it never left one.
        -- The sort below does the preferring.
        local candidates = self:ForwardEngineerCandidates(function(unit)
            return unit.CanBuild and unit:CanBuild(blueprintId)
        end)
        table.sort(candidates, function(a, b)
            -- An idle engineer costs nothing to take; beyond that prefer the
            -- lowest tier, so a Tech 3 engineer is left for work that needs it.
            if a.Idle ~= b.Idle then return a.Idle end
            if a.Tech ~= b.Tech then return a.Tech < b.Tech end
            return (a.Unit.EntityId or 0) < (b.Unit.EntityId or 0)
        end)
        local selected = candidates[1]
        return selected and selected.Unit or nil
    end,

    GetUnassignedEngineers = function(self)
        local pool = self.Brain:GetPlatoonUniquelyNamed("ArmyPool")
        local units = pool and pool:GetPlatoonUnits() or {}
        local engineers = {}
        local byEntityId = {}
        for _, unit in pairs(units) do
            local blueprint = IsAlive(unit) and unit.GetBlueprint and unit:GetBlueprint() or {}
            local hash = blueprint.CategoriesHash or {}
            if IsAlive(unit)
                and (hash.ENGINEER or unit.IsEngineer)
                and not (hash.COMMAND or unit.IsCommander)
            then
                table.insert(engineers, unit)
                byEntityId[unit.EntityId] = true
            end
        end
        table.sort(engineers, function(a, b)
            return (a.EntityId or 0) < (b.EntityId or 0)
        end)
        return engineers, byEntityId
    end,

    ReleaseFactoryAssistants = function(self, reason, unassignedByEntityId)
        local released = {}
        if not unassignedByEntityId then
            local _, byEntityId = self:GetUnassignedEngineers()
            unassignedByEntityId = byEntityId
        end
        for _, record in pairs(self.FactoryAssistants) do
            if IsAlive(record.Engineer)
                and unassignedByEntityId[record.Engineer.EntityId]
            then
                table.insert(released, record.Engineer)
            end
            if record.Engineer then
                record.Engineer.RedQueenFactoryAssistUntil = nil
                record.Engineer.RedQueenFactoryAssistTarget = nil
            end
        end
        self.FactoryAssistants = {}
        if table.getn(released) > 0 and IssueClearCommands then
            IssueClearCommands(released)
            Logger.Info(self.Brain, string.format(
                "factory assistants released count=%d reason=%s",
                table.getn(released),
                tostring(reason)
            ))
        end
    end,

    UpdateFactoryAssistance = function(self, factories, unassigned, unassignedByEntityId)
        if not unassigned then
            unassigned, unassignedByEntityId = self:GetUnassignedEngineers()
        end
        local alert = self.Strategy.ProductionDemand.DefenseAlert
        local state = self.Economy.State
        if state.StallRisk or (alert and alert.Active) then
            self:ReleaseFactoryAssistants(
                alert and alert.Active and "defense" or "stall",
                unassignedByEntityId
            )
            return
        end

        local tick = GetGameTick()
        local active = {}
        local kept = {}
        local expired = {}
        for entityId, record in pairs(self.FactoryAssistants) do
            if IsAlive(record.Engineer)
                and IsAlive(record.Factory)
                and record.ExpiresTick > tick
                and unassignedByEntityId[record.Engineer.EntityId]
            then
                kept[entityId] = record
                table.insert(active, record.Engineer)
            elseif record.Engineer then
                if IsAlive(record.Engineer)
                    and unassignedByEntityId[record.Engineer.EntityId]
                then
                    table.insert(expired, record.Engineer)
                end
                record.Engineer.RedQueenFactoryAssistUntil = nil
                record.Engineer.RedQueenFactoryAssistTarget = nil
            end
        end
        self.FactoryAssistants = kept
        if table.getn(expired) > 0 and IssueClearCommands then
            IssueClearCommands(expired)
        end

        local desired = math.min(
            Constants.Policy.MaximumFactoryAssistants,
            math.floor((state.MassIncome or 0) / Constants.Policy.FactoryAssistMassPerEngineer)
        )
        if table.getn(active) > desired then
            table.sort(active, function(a, b)
                return (a.EntityId or 0) < (b.EntityId or 0)
            end)
            local excess = {}
            for index = table.getn(active), desired + 1, -1 do
                local engineer = active[index]
                self.FactoryAssistants[engineer.EntityId] = nil
                engineer.RedQueenFactoryAssistUntil = nil
                engineer.RedQueenFactoryAssistTarget = nil
                table.insert(excess, engineer)
                table.remove(active, index)
            end
            if table.getn(excess) > 0 and IssueClearCommands then
                IssueClearCommands(excess)
            end
        end
        if desired <= table.getn(active) or desired <= 0 then
            return
        end

        local targets = {}
        for _, factory in pairs(factories) do
            if IsAlive(factory) then table.insert(targets, factory) end
        end
        table.sort(targets, function(a, b)
            local aActive = a.IsUnitState and a:IsUnitState("Building") or false
            local bActive = b.IsUnitState and b:IsUnitState("Building") or false
            if aActive ~= bActive then return aActive end
            local aTech = UnitTech(a)
            local bTech = UnitTech(b)
            if aTech ~= bTech then return aTech > bTech end
            return (a.EntityId or 0) < (b.EntityId or 0)
        end)
        if table.getn(targets) == 0 then return end

        local candidates = {}
        for _, engineer in pairs(unassigned) do
            if engineer.RedQueenEmergencyDefenseUntil
                and engineer.RedQueenEmergencyDefenseUntil <= tick
            then
                engineer.RedQueenEmergencyDefenseUntil = nil
            end
            -- Building a factory outranks assisting one. IssueGuard would
            -- replace the build order TryExpandFactoryCapacity queued earlier in
            -- this same pass.
            if UnitTech(engineer) == 1
                and IsAvailable(engineer)
                and not engineer.RedQueenEmergencyDefenseUntil
                and not (engineer.RedQueenProductionBuildUntil
                    and engineer.RedQueenProductionBuildUntil > tick)
                and not self.FactoryAssistants[engineer.EntityId]
            then
                table.insert(candidates, engineer)
            end
        end

        local assigned = 0
        local needed = desired - table.getn(active)
        for index = 1, math.min(needed, table.getn(candidates)) do
            local engineer = candidates[index]
            local targetCount = table.getn(targets)
            local targetIndex = index - math.floor((index - 1) / targetCount) * targetCount
            local factory = targets[targetIndex]
            if IssueGuard then IssueGuard({ engineer }, factory) end
            local expiresTick = tick + Constants.Policy.FactoryAssistSeconds * 10
            engineer.RedQueenFactoryAssistUntil = expiresTick
            engineer.RedQueenFactoryAssistTarget = factory.EntityId
            self.FactoryAssistants[engineer.EntityId] = {
                Engineer = engineer,
                Factory = factory,
                ExpiresTick = expiresTick,
            }
            assigned = assigned + 1
        end
        if assigned > 0 then
            Logger.Info(self.Brain, string.format(
                "factory assistants assigned count=%d total=%d target=%d",
                assigned,
                table.getn(active) + assigned,
                desired
            ))
        end
    end,

    FindEmergencyDefenseEngineer = function(self, anchorPosition, blueprintId, engineers)
        local candidates = {}
        for _, engineer in pairs(engineers or {}) do
            if IsAvailable(engineer)
                and engineer.CanBuild
                and engineer:CanBuild(blueprintId)
            then
                table.insert(candidates, engineer)
            end
        end
        table.sort(candidates, function(a, b)
            local aTech = UnitTech(a)
            local bTech = UnitTech(b)
            if aTech ~= bTech then return aTech < bTech end
            local aPosition = a:GetPosition()
            local bPosition = b:GetPosition()
            local aDistance = DistanceSquared(aPosition, anchorPosition)
            local bDistance = DistanceSquared(bPosition, anchorPosition)
            if aDistance ~= bDistance then return aDistance < bDistance end
            return (a.EntityId or 0) < (b.EntityId or 0)
        end)
        return candidates[1]
    end,

    HasManagedEmergencyDefense = function(self, alert)
        local managers = self.Brain.BuilderManagers or {}
        for locationType, manager in pairs(managers) do
            local engineerManager = manager and manager.EngineerManager
            if engineerManager and self.CounterBuildersRegistered[locationType] then
                if alert.AnchorLocationType == locationType then
                    return true
                end
                local position = engineerManager.GetLocationCoords
                    and engineerManager:GetLocationCoords()
                if position then
                    local radius = math.max(40, engineerManager.Radius or 100)
                    if DistanceSquared(position, alert.AnchorPosition) <= radius * radius then
                        return true
                    end
                end
            end
        end
        return false
    end,

    -- Where a shore battery goes: offset from the anchor directly away from the
    -- threat. T2 artillery's 50 minimum radius is a dead zone around the gun,
    -- so a gun dropped on the threatened edge cannot hit what it is defending
    -- against, while the same gun set back covers the whole approach. Falls
    -- back to the anchor itself when the threat position is unusable.
    ShoreArtilleryPosition = function(self, alert)
        local anchor = alert.AnchorPosition
        local threat = alert.Position
        if not anchor then return nil end
        if not threat then return anchor end
        local dx = anchor[1] - threat[1]
        local dz = anchor[3] - threat[3]
        local length = math.sqrt(dx * dx + dz * dz)
        if length < 1 then return anchor end
        local offset = Constants.Policy.ShoreArtilleryRearOffset
        return {
            anchor[1] + dx / length * offset,
            anchor[2],
            anchor[3] + dz / length * offset,
        }
    end,

    -- Static anti-navy. Like artillery, no fortification builder can produce
    -- these, so this path is not covered by the managed-anchor deferral.
    --
    -- Torpedo launchers are water-only (BuildOnLayerCaps LAYER_Land = false,
    -- 1.5 minimum water depth), so BuildClose from a base whose coords are on
    -- land cannot site one. The strategy director already located a water cell
    -- near the threatened anchor; build there, absolutely.
    UpdateShoreTorpedo = function(self, engineers)
        local alert = self.Strategy.ProductionDemand.DefenseAlert
        local tick = GetGameTick()
        if not alert or not alert.Active then return end
        if not self:ProfileFlag("ShoreTorpedo") then return end
        local target = alert.Targets and alert.Targets.Torpedo or 0
        local position = alert.WaterPosition
        if target <= 0 or not position or not self.Brain.GetNumUnitsAroundPoint then return end
        -- As with artillery: a walking anchor cannot hold a structure quota.
        if alert.AnchorKind == "Commander" then return end
        if tick - self.LastShoreTorpedoTick
            < Constants.Policy.EmergencyDefenseCooldownSeconds * 10
        then
            return
        end
        -- Count around the ANCHOR, not the build position. The water position
        -- is re-probed each alert and biased toward the current cluster, so it
        -- drifts as the enemy fleet moves; counting around it lets previously
        -- built launchers fall outside the window and the quota never fills.
        -- On SCMP_037 that logged `current=0 target=2` six times at one anchor
        -- while launchers were standing. The radius has to cover the whole
        -- probe area, or the same drift reappears at its edge.
        local countRadius = math.max(
            Constants.Policy.ShoreTorpedoRadius,
            Constants.Policy.ShoreTorpedoProbeRadius + 20
        )
        local current = self.Brain:GetNumUnitsAroundPoint(
            categories.STRUCTURE * categories.DEFENSE * categories.ANTINAVY,
            alert.AnchorPosition,
            countRadius,
            "Ally"
        ) or 0
        if current >= target then return end

        local faction = self.Context.FactionIndex
        local buildingTemplate = BuildingTemplates.BuildingTemplates[faction]
        local baseTemplate = BaseTemplates.ExpansionBaseTemplates[faction]
            or BaseTemplates.BaseTemplates[faction]
        if not buildingTemplate or not baseTemplate then return end
        local movedTemplate = AIBuildStructures.AIBuildBaseTemplateFromLocation(
            baseTemplate,
            position
        )
        -- T3NavalDefense exists only for Cybran. Offering it to anyone else
        -- makes AIExecuteBuildStructure blacklist the type in AntiSpamList,
        -- which is module state shared by every army in the Lua state, so a
        -- Cybran ally would lose the type too.
        local types = faction == 3
            and { "T3NavalDefense", "T2NavalDefense", "T1NavalDefense" }
            or { "T2NavalDefense", "T1NavalDefense" }
        engineers = engineers or self:GetUnassignedEngineers()
        local selectedEngineer, selectedType = nil, nil
        for _, buildingType in pairs(types) do
            local blueprintId = FindBuildingId(buildingTemplate, buildingType)
            if blueprintId then
                selectedEngineer = self:FindEmergencyDefenseEngineer(
                    position,
                    blueprintId,
                    engineers
                )
                if selectedEngineer then
                    selectedType = buildingType
                    break
                end
            end
        end
        if not selectedEngineer then return end

        local started, buildError = ExecuteBuildStructure(
            self.Brain,
            selectedEngineer,
            selectedType,
            buildingTemplate,
            movedTemplate,
            "absolute"
        )
        if buildError then
            Logger.Error(self.Brain, string.format(
                "shore torpedo build failed anchor=%s type=%s error=%s",
                tostring(alert.AnchorKind),
                selectedType,
                buildError
            ))
        end
        if started then
            self.LastShoreTorpedoTick = tick
            selectedEngineer.RedQueenEmergencyDefenseUntil = tick
                + Constants.Policy.EmergencyDefenseEngineerHoldSeconds * 10
            Logger.Info(self.Brain, string.format(
                "shore torpedo queued anchor=%s type=%s engineer=%d current=%d target=%d",
                tostring(alert.AnchorKind),
                selectedType,
                selectedEngineer.EntityId or 0,
                current,
                target
            ))
        end
    end,

    -- Artillery is deliberately not part of the fortification builder group and
    -- is therefore not covered by the managed-anchor deferral in
    -- UpdateEmergencyDefense: no registered builder can produce it, so
    -- deferring to them would mean never building it at all.
    UpdateShoreArtillery = function(self, engineers)
        local alert = self.Strategy.ProductionDemand.DefenseAlert
        local tick = GetGameTick()
        if not alert or not alert.Active or not alert.AnchorPosition then return end
        if not self:ProfileFlag("ShoreArtillery") then return end
        local target = alert.Targets and alert.Targets.Artillery or 0
        if target <= 0 or not self.Brain.GetNumUnitsAroundPoint then return end
        -- A commander anchor walks. Counting existing batteries within a radius
        -- of a moving point never sees what was already built there, so the
        -- quota never fills and the order is reissued every cooldown -- nine
        -- pieces on SCMP_037, roughly a third of all production. Static
        -- structures only follow static anchors.
        if alert.AnchorKind == "Commander" then return end
        if tick - self.LastShoreArtilleryTick
            < Constants.Policy.EmergencyDefenseCooldownSeconds * 10
        then
            return
        end
        -- A siege gun is an investment, not an interception. Never start one
        -- while the economy cannot carry it, and never more than the current
        -- stage of the game justifies.
        local state = self.Economy.State
        if state.StallRisk then return end
        local allowance = ShoreArtilleryAllowance(state.MassIncome or 0)
        if allowance <= 0 then return end
        target = math.min(target, allowance)

        -- Supplemental, not preferred: the anchor's primary point defence must
        -- already be standing. Point defence is cheaper, fires from zero range
        -- and answers the attackers artillery cannot reach, so it is always the
        -- first call on the same engineers and the same mass.
        -- Half the point-defence target, not all of it. Targets.Ground is an
        -- aspirational emergency figure with a floor of four, and an expansion
        -- rarely reaches it, so demanding the full count turned "supplemental"
        -- into "never": Syrtis Major cleared every economic rung at 32 mass a
        -- tick across five static-anchor alerts and still built nothing. Half
        -- means the defensive line is established, which is the actual
        -- condition for a supplement to make sense.
        local groundTarget = alert.Targets.Ground or 0
        if groundTarget > 0 then
            local ground = self.Brain:GetNumUnitsAroundPoint(
                categories.STRUCTURE * categories.DEFENSE * categories.DIRECTFIRE,
                alert.AnchorPosition,
                Constants.Policy.EmergencyDefenseRadius,
                "Ally"
            ) or 0
            if ground < math.ceil(groundTarget / 2) then return end
        end
        -- Count from the ANCHOR, not the build position. The battery is sited
        -- by offsetting away from the observed threat, so as the enemy moves
        -- the build point swings around the base and a count taken there loses
        -- sight of batteries already standing -- Syrtis Major logged
        -- `current=0` six times while building them. The anchor is fixed, and
        -- the radius already exceeds the offset, so it sees the whole ring.
        local position = self:ShoreArtilleryPosition(alert)
        if not position then return end
        local current = self.Brain:GetNumUnitsAroundPoint(
            categories.STRUCTURE * categories.ARTILLERY,
            alert.AnchorPosition,
            Constants.Policy.ShoreArtilleryRadius,
            "Ally"
        ) or 0
        if current >= target then return end

        local faction = self.Context.FactionIndex
        local buildingTemplate = BuildingTemplates.BuildingTemplates[faction]
        local baseTemplate = BaseTemplates.ExpansionBaseTemplates[faction]
            or BaseTemplates.BaseTemplates[faction]
        if not buildingTemplate or not baseTemplate then return end
        local movedTemplate = AIBuildStructures.AIBuildBaseTemplateFromLocation(
            baseTemplate,
            position
        )
        engineers = engineers or self:GetUnassignedEngineers()
        local blueprintId = FindBuildingId(buildingTemplate, "T2Artillery")
        if not blueprintId then return end
        local selectedEngineer = self:FindEmergencyDefenseEngineer(
            position,
            blueprintId,
            engineers
        )
        if not selectedEngineer then return end

        local started, buildError = ExecuteBuildStructure(
            self.Brain,
            selectedEngineer,
            "T2Artillery",
            buildingTemplate,
            movedTemplate,
            "absolute"
        )
        if buildError then
            Logger.Error(self.Brain, string.format(
                "shore artillery build failed anchor=%s error=%s",
                tostring(alert.AnchorKind),
                buildError
            ))
        end
        if started then
            self.LastShoreArtilleryTick = tick
            selectedEngineer.RedQueenEmergencyDefenseUntil = tick
                + Constants.Policy.EmergencyDefenseEngineerHoldSeconds * 10
            Logger.Info(self.Brain, string.format(
                "shore artillery queued anchor=%s engineer=%d current=%d target=%d offset=%d",
                tostring(alert.AnchorKind),
                selectedEngineer.EntityId or 0,
                current,
                target,
                Constants.Policy.ShoreArtilleryRearOffset
            ))
        end
    end,

    UpdateEmergencyDefense = function(self, engineers)
        local alert = self.Strategy.ProductionDemand.DefenseAlert
        local tick = GetGameTick()
        if not alert or not alert.Active or not alert.AnchorPosition then return end
        if self:HasManagedEmergencyDefense(alert) then
            -- Deferral is a decision, not inaction: the registered fortification
            -- builders own this anchor. Match 27741743 logged nothing at all
            -- here across nineteen defence alerts, so the log could not say
            -- whether defences were being built or silently skipped.
            if tick - self.LastEmergencyDefenseLogTick
                >= Constants.Policy.EmergencyDefenseLogCooldownSeconds * 10
            then
                self.LastEmergencyDefenseLogTick = tick
                Logger.Info(self.Brain, string.format(
                    "emergency defense deferred anchor=%s manager=%s",
                    tostring(alert.AnchorKind),
                    tostring(alert.AnchorLocationType or "nearby")
                ))
            end
            return
        end
        if tick - self.LastEmergencyDefenseTick
            < Constants.Policy.EmergencyDefenseCooldownSeconds * 10
        then
            return
        end

        local target = alert.Targets and alert.Targets.Ground or 0
        if target <= 0 or not self.Brain.GetNumUnitsAroundPoint then return end
        local current = self.Brain:GetNumUnitsAroundPoint(
            categories.STRUCTURE * categories.DEFENSE * categories.DIRECTFIRE,
            alert.AnchorPosition,
            Constants.Policy.EmergencyDefenseRadius,
            "Ally"
        ) or 0
        if current >= target then return end

        -- Assistants are already released by UpdateFactoryAssistance for any
        -- active alert, so no release is needed here.
        local faction = self.Context.FactionIndex
        local buildingTemplate = BuildingTemplates.BuildingTemplates[faction]
        local baseTemplate = BaseTemplates.ExpansionBaseTemplates[faction]
            or BaseTemplates.BaseTemplates[faction]
        if not buildingTemplate or not baseTemplate then return end
        local movedTemplate = AIBuildStructures.AIBuildBaseTemplateFromLocation(
            baseTemplate,
            alert.AnchorPosition
        )
        local types = faction == 1
            and { "T3GroundDefense", "T2GroundDefense", "T1GroundDefense" }
            or { "T2GroundDefense", "T1GroundDefense" }
        -- One roster for every candidate type; only the per-type CanBuild check
        -- differs, so rescanning the ArmyPool per type is wasted work.
        engineers = engineers or self:GetUnassignedEngineers()
        local selectedEngineer = nil
        local selectedType = nil
        for _, buildingType in pairs(types) do
            local blueprintId = FindBuildingId(buildingTemplate, buildingType)
            if blueprintId then
                selectedEngineer = self:FindEmergencyDefenseEngineer(
                    alert.AnchorPosition,
                    blueprintId,
                    engineers
                )
                if selectedEngineer then
                    selectedType = buildingType
                    break
                end
            end
        end

        if not selectedEngineer then
            if tick - self.LastEmergencyDefenseLogTick
                >= Constants.Policy.EmergencyDefenseLogCooldownSeconds * 10
            then
                self.LastEmergencyDefenseLogTick = tick
                Logger.Info(self.Brain, string.format(
                    "emergency defense blocked anchor=%s reason=no-engineer current=%d target=%d",
                    tostring(alert.AnchorKind),
                    current,
                    target
                ))
            end
            return
        end

        local started, buildError = ExecuteBuildStructure(
            self.Brain,
            selectedEngineer,
            selectedType,
            buildingTemplate,
            movedTemplate,
            "absolute"
        )
        if buildError then
            Logger.Error(self.Brain, string.format(
                "emergency defense build failed anchor=%s type=%s error=%s",
                tostring(alert.AnchorKind),
                selectedType,
                buildError
            ))
        end
        if started then
            self.LastEmergencyDefenseTick = tick
            selectedEngineer.RedQueenEmergencyDefenseUntil = tick
                + Constants.Policy.EmergencyDefenseEngineerHoldSeconds * 10
            Logger.Info(self.Brain, string.format(
                "emergency defense queued anchor=%s type=%s engineer=%d current=%d target=%d",
                tostring(alert.AnchorKind),
                selectedType,
                selectedEngineer.EntityId or 0,
                current,
                target
            ))
        end
    end,

    TryExpandFactoryCapacity = function(self, counts, targets)
        targets = targets or self:GetFactoryTargets(counts)
        local tick = GetGameTick()
        local cooldown = Constants.Policy.FactoryCheckCooldownSeconds * 10
        if tick - self.LastFactoryRequestTick < cooldown then
            if self.Trace then self.Trace:Safe(self.Trace.ExpansionBlocked, "cooldown") end
            return
        end
        if not self.Economy:CanExpandProduction(counts.Total) then
            if self.Trace then self.Trace:Safe(self.Trace.ExpansionBlocked, "economy") end
            return
        end

        local faction = self.Context.FactionIndex
        local buildingTemplate = BuildingTemplates.BuildingTemplates[faction]
        local baseTemplate = BaseTemplates.BaseTemplates[faction]
        if not buildingTemplate or not baseTemplate then
            if self.Trace then self.Trace:Safe(self.Trace.ExpansionBlocked, "template") end
            return
        end

        local buildingType = self:SelectFactoryType(counts, targets)
        if not buildingType then
            if self.Trace then self.Trace:Safe(self.Trace.ExpansionBlocked, "domain-target-met") end
            return
        end
        local blueprintId = FindBuildingId(buildingTemplate, buildingType)
        if not blueprintId then
            if self.Trace then self.Trace:Safe(self.Trace.ExpansionBlocked, "blueprint") end
            return
        end

        local builder = self:FindIdleBuilder(blueprintId)
        if not builder then
            if self.Trace then self.Trace:Safe(self.Trace.ExpansionBlocked, "no-candidate") end
            return
        end

        local started, buildError, entry = ExecuteBuildStructure(
            self.Brain,
            builder,
            buildingType,
            buildingTemplate,
            baseTemplate,
            "relative"
        )
        if self.Trace then self.Trace:Safe(self.Trace.ExpansionAttempt, builder, buildingType, started, entry) end
        if buildError then
            Logger.Error(self.Brain, string.format(
                "production expansion failed type=%s error=%s",
                buildingType,
                buildError
            ))
        end
        if started then
            self.LastFactoryRequestTick = tick
            -- Hold the builder against its own factory. UpdateFactoryAssistance
            -- runs later in the same pass and issues a guard order, which
            -- replaces the build order this just queued -- with one engineer in
            -- the pool that meant five expansion requests produced no factory
            -- at all in the Red Queen versus stock Adaptive rematch.
            builder.RedQueenProductionBuildUntil = tick
                + Constants.Policy.ProductionBuildHoldSeconds * 10
            -- The builder identity and state are logged because three separate
            -- fixes to the factory target, to order clobbering and to engineer
            -- sourcing all failed to raise the factory count above one. Naming
            -- the engineer shows whether the same one is re-selected every
            -- cooldown and has its half-built factory replaced.
            Logger.Info(self.Brain, string.format(
                "production expansion type=%s factories=%d desired=%d deficit=%d engineer=%s idle=%s building=%s",
                buildingType,
                counts.Total,
                targets.Total or self.Economy.State.DesiredFactories,
                self.Context.ArmyDeficit,
                tostring(builder.EntityId),
                (builder.IsIdleState and builder:IsIdleState()) and "yes" or "no",
                (builder.IsUnitState and builder:IsUnitState("Building")) and "yes" or "no"
            ))
        end
    end,

    -- Engineers are almost never in ArmyPool. EngineerManager:AddUnit claims
    -- every newly built engineer for a base the moment it finishes, so the pool
    -- holds one or two units in transit -- which is why match 27741743 and its
    -- verification run blocked on no-idle-engineer 82 times while wanting six
    -- factory assistants and finding one.
    --
    -- Base managers are the real supply, and taking an engineer from one is
    -- FAF's own expansion flow: AINewExpansionBase already performs the
    -- RemoveUnit/AddUnit handoff to the new base. A manager keeps a retention
    -- floor so a base is never stripped of the engineers it needs to work.
    --
    -- Support commanders carry the ENGINEER category, so once one reaches a
    -- manager it is selected here like any other engineer, with the highest
    -- build power available.
    ForwardEngineerCandidates = function(self, accept)
        local candidates = {}
        local seen = {}
        local tick = GetGameTick()

        local function Consider(unit)
            if not IsAlive(unit) or seen[unit.EntityId] or EngineerSurvival.IsRetreating(unit) then
                return
            end
            if not EntityCategoryContains(categories.ENGINEER - categories.COMMAND, unit) then
                return
            end
            -- AINewExpansionBase dereferences the engineer's manager, and an
            -- engineer without one cannot hand itself over to the new base.
            if not unit.BuilderManagerData or not unit.BuilderManagerData.EngineerManager then
                return
            end
            if unit.RedQueenEmergencyDefenseUntil
                and unit.RedQueenEmergencyDefenseUntil > tick
            then
                return
            end
            if unit.RedQueenProductionBuildUntil
                and unit.RedQueenProductionBuildUntil > tick
            then
                return
            end
            if accept and not accept(unit) then
                return
            end
            seen[unit.EntityId] = true
            table.insert(candidates, {
                Unit = unit,
                Idle = (unit.IsIdleState and unit:IsIdleState()) and true or false,
                Tech = UnitTech(unit),
            })
        end

        local pool = self.Brain:GetPlatoonUniquelyNamed("ArmyPool")
        for _, unit in pairs(pool and pool:GetPlatoonUnits() or {}) do
            Consider(unit)
        end

        local managers = self.Brain.BuilderManagers or {}
        local locationTypes = {}
        for locationType, _ in pairs(managers) do
            table.insert(locationTypes, locationType)
        end
        table.sort(locationTypes)
        local floor = Constants.Policy.ForwardBaseSourceMinimumEngineers
        for _, locationType in pairs(locationTypes) do
            local engineerManager = managers[locationType].EngineerManager
            if engineerManager and engineerManager.GetUnits then
                local units = engineerManager:GetUnits(
                    "Engineers",
                    categories.ENGINEER - categories.COMMAND
                ) or {}
                -- Only one engineer is ever taken, so the floor decides whether
                -- this base can spare one at all, not which one. Capping by
                -- position instead would hide an idle engineer behind busy ones.
                if table.getn(units) > floor then
                    for _, unit in pairs(units) do
                        Consider(unit)
                    end
                end
            end
        end
        return candidates
    end,

    FindForwardEngineer = function(self)
        local candidates = self:ForwardEngineerCandidates()
        table.sort(candidates, function(a, b)
            -- An idle engineer costs nothing to take. Beyond that the highest
            -- tier wins, because the forward-base package scales with it.
            if a.Idle ~= b.Idle then return a.Idle end
            if a.Tech ~= b.Tech then return a.Tech > b.Tech end
            return (a.Unit.EntityId or 0) < (b.Unit.EntityId or 0)
        end)
        local selected = candidates[1]
        return selected and selected.Unit or nil
    end,

    GetForwardBaseBlockReason = function(self, engineer)
        local alert = self.Strategy.ProductionDemand.DefenseAlert
        local state = self.Economy.State
        if not engineer then return "no-idle-engineer" end
        if not engineer.BuilderManagerData
            or not engineer.BuilderManagerData.EngineerManager
        then return "engineer-without-manager" end
        if alert and alert.Active then return "defense-alert" end
        if state.StallRisk then return "stall-risk" end
        if state.MassTrend < 0 then return "negative-mass-trend" end
        if state.EnergyTrend < 0 then return "negative-energy-trend" end
        if state.MassStoredRatio < 0.10 then return "low-mass-storage" end
        if state.EnergyStoredRatio < 0.10 then return "low-energy-storage" end

        local tech = UnitTech(engineer)
        local mass = Constants.Policy.ForwardBaseMinimumMassIncome
        local energy = Constants.Policy.ForwardBaseMinimumEnergyIncome
        if tech >= 3 then
            mass = math.max(mass, Constants.Policy.Tech3MinimumMassIncome)
            energy = math.max(energy, Constants.Policy.Tech3MinimumEnergyIncome)
        elseif tech >= 2 then
            mass = math.max(mass, Constants.Policy.Tech2MinimumMassIncome)
            energy = math.max(energy, Constants.Policy.Tech2MinimumEnergyIncome)
        end
        if state.MassIncome < mass then return "low-mass-income" end
        if state.EnergyIncome < energy then return "low-energy-income" end
        return nil
    end,

    LogForwardBaseBlocked = function(self, reason)
        local tick = GetGameTick()
        self.LastForwardBaseBlockReason = reason
        local plan = self.Strategy.ProductionDemand.ForwardBasePlan
        if plan then
            plan.BlockReason = reason
        end
        if tick - self.LastForwardBaseBlockLogTick
            < Constants.Policy.ForwardBaseDiagnosticSeconds * 10
        then
            return
        end
        self.LastForwardBaseBlockLogTick = tick
        Logger.Info(self.Brain, "forward base blocked reason=" .. tostring(reason))
    end,

    -- What a forward base builds, in the order it builds it.
    --
    -- Order is the design lever, not an afterthought. Every tier previously led
    -- with T1LandFactory and T1Radar, so an engineer arriving at a contested
    -- site spent its most exposed minutes erecting a 240-mass factory and a
    -- radar -- neither of which shoots -- and reached its first gun last. Across
    -- the 21-cell matrix only 21% of started bases ever established.
    --
    -- So every tier now leads with the cheapest defence it can raise. Tech 1
    -- point defence is 250 mass against a Tech 2's 540, so two Tech 1 guns up
    -- early are worth more on a contested site than one Tech 2 gun up late.
    -- That is also why the higher tiers keep Tech 1 pieces in the mix rather
    -- than replacing them: it is a decision about what is shooting at minute
    -- one, not a judgement about the finished base.
    --
    -- Each tier also declares the minimum set that marks it defensible, which
    -- is what an escort's release condition keys on -- so what gets built and
    -- what counts as safe come from the same place and cannot disagree.
    ForwardBasePackage = function(self, tech)
        return self:ForwardBaseTier(tech).Package
    end,

    -- Verified faction gaps that a package must not name, or the queue silently
    -- drops the entry: T3GroundDefense is UEF only, and Cybran aliases
    -- T3ShieldDefense to its Tech 2 shield.
    ForwardBaseTier = function(self, tech)
        local faction = self.Context.FactionIndex
        local bestGround = faction == 1 and "T3GroundDefense" or "T2GroundDefense"

        if tech >= 3 then
            local package = {
                -- Fast cover first.
                "T1GroundDefense", "T1GroundDefense",
                "T2GroundDefense", "T2GroundDefense",
                "T2AADefense",
                "T2ShieldDefense",
                -- Then the heavy tail. T2Artillery has a 50 minimum radius --
                -- a dead zone around the gun -- so it belongs here, set back
                -- from the threatened edge, never as early cover.
                "T1LandFactory",
                "T1Radar",
            }
            for _ = 1, 3 do table.insert(package, bestGround) end
            for _ = 1, 2 do table.insert(package, "T3AADefense") end
            table.insert(package, "T3ShieldDefense")
            table.insert(package, "T2StrategicMissile")
            table.insert(package, "T2StrategicMissile")
            table.insert(package, "T2Artillery")
            table.insert(package, "T2Artillery")
            table.insert(package, "T3StrategicMissileDefense")
            return {
                Tier = 3,
                Package = package,
                -- At least one Tech 2 shield or better, and more than a handful
                -- of Tech 2 or better point defences.
                MinimumDefenses = 5,
                MinimumAntiAir = 2,
                MinimumShields = 1,
            }
        end

        if tech >= 2 then
            return {
                Tier = 2,
                Package = {
                    "T1GroundDefense", "T1GroundDefense",
                    "T2GroundDefense", "T2GroundDefense",
                    "T1AADefense",
                    "T2AADefense",
                    "T2ShieldDefense",
                    "T1LandFactory",
                    "T1Radar",
                    "T2GroundDefense",
                    "T2MissileDefense",
                    "T2Artillery",
                },
                MinimumDefenses = 4,
                MinimumAntiAir = 2,
                MinimumShields = 1,
            }
        end

        return {
            Tier = 1,
            Package = {
                "T1GroundDefense", "T1GroundDefense",
                "T1AADefense",
                "T1LandFactory",
                "T1Radar",
                "T1AADefense",
            },
            MinimumDefenses = 2,
            MinimumAntiAir = 1,
            -- Tech 1 has no shield at all, so requiring one here would leave a
            -- Tech 1 base permanently short of its own minimum.
            MinimumShields = 0,
        }
    end,

    FindForwardBaseFactory = function(self, base)
        if IsOwnedByBrain(base.Factory, self.Brain) then
            return base.Factory
        end
        if not self.Brain.GetUnitsAroundPoint then
            return nil
        end

        local factories = self.Brain:GetUnitsAroundPoint(
            categories.STRUCTURE * categories.FACTORY,
            base.Position,
            Constants.Policy.ForwardBaseSiteRadius,
            "Ally"
        ) or {}
        local available = {}
        for _, factory in pairs(factories) do
            if IsOwnedByBrain(factory, self.Brain) then
                table.insert(available, factory)
            end
        end
        table.sort(available, function(a, b)
            local aPosition = a:GetPosition()
            local bPosition = b:GetPosition()
            local adx = aPosition[1] - base.Position[1]
            local adz = aPosition[3] - base.Position[3]
            local bdx = bPosition[1] - base.Position[1]
            local bdz = bPosition[3] - base.Position[3]
            local aDistance = adx * adx + adz * adz
            local bDistance = bdx * bdx + bdz * bdz
            if aDistance ~= bDistance then
                return aDistance < bDistance
            end
            return (a.EntityId or 0) < (b.EntityId or 0)
        end)
        return available[1]
    end,

    GetRebuildableForwardBaseSites = function(self)
        local sites = {}
        for _, base in pairs(self.ForwardBases) do
            if base.State == "Destroyed" and base.SiteName then
                sites[base.SiteName] = true
            end
        end
        return sites
    end,

    RevalidateEstablishedForwardBases = function(self)
        local tick = GetGameTick()
        for _, base in pairs(self.ForwardBases) do
            if base.State == "Established" then
                local managerPresent = HasExpansionBase(self.Brain, base.Name)
                local factory = self:FindForwardBaseFactory(base)
                base.ManagerPresent = managerPresent
                base.FactoryPresent = factory ~= nil
                if managerPresent and factory then
                    base.Factory = factory
                else
                    base.State = "Destroyed"
                    base.DestroyedTick = tick
                    if self.ForwardBaseClaims[base.SiteName] == base then
                        self.ForwardBaseClaims[base.SiteName] = nil
                    end
                    Logger.Info(self.Brain, string.format(
                        "forward base destroyed name=%s site=%s manager=%s factory=%s",
                        base.Name,
                        base.SiteName,
                        managerPresent and "yes" or "no",
                        factory and "yes" or "no"
                    ))
                end
            end
        end
    end,

    -- Re-judge the route an engineer is still walking, and say why it should
    -- turn back.
    --
    -- A single assessment at dispatch cannot carry the journey. Observed walks
    -- ran 75 to 175 seconds while IntelLifetimeSeconds is 180, so the picture
    -- that authorised the trip is roughly as old as the trip itself -- and the
    -- engineers that died were dispatched on routes at coverage 1.00 and well
    -- inside the safety limit. The assessment was not wrong, it just stopped
    -- being true.
    --
    -- Judged from where the engineer is now, not from where it set out, and
    -- with a margin over the dispatch limit so ordinary noise does not turn a
    -- committed engineer around.
    ForwardBaseRecallReason = function(self, record)
        if not record or not record.Position then
            return nil
        end
        local tick = GetGameTick()
        local interval = Constants.Policy.ForwardBaseRouteRecheckSeconds * 10
        if record.RouteCheckedTick and tick - record.RouteCheckedTick < interval then
            return nil
        end
        record.RouteCheckedTick = tick

        local engineer = record.Engineer
        if not engineer or not engineer.GetPosition then
            return nil
        end
        local position = engineer:GetPosition()
        if not position then
            return nil
        end

        local layer = record.Layer or "Land"
        local threat, coverage = self.World:GetObservedRouteThreat(
            position,
            record.Position,
            self.Intel,
            Constants.Policy.ForwardBaseSiteRadius,
            layer
        )
        -- A route that has ceased to exist on the engineer's own graph is not a
        -- judgement call.
        if threat == nil then
            return "route-lost"
        end
        local escort = self.Strategy:GetOwnThreatNear(
            position,
            Constants.Policy.ForwardBaseSiteRadius
        )
        local limit = math.max(0, escort * Constants.Policy.ForwardBaseSafetyRatio)
            * Constants.Policy.ForwardBaseRecallThreatRatio
        record.RouteCoverage = coverage
        record.LastRouteThreat = threat
        record.LastRouteLimit = limit
        if threat > limit then
            return "route-unsafe"
        end
        return nil
    end,

    -- Native construction owns a Lua queue and unit threads as well as engine
    -- orders. Cancel them before disbanding the build task, whose callbacks and
    -- AI thread could otherwise retry the abandoned destination after recall.
    RecallForwardBaseEngineer = function(self, record)
        local engineer = record and record.Engineer
        if not engineer or not IsAlive(engineer) then
            return false
        end
        return ReleaseEngineer(engineer, self.World and self.World.StartPosition)
    end,

    -- Keep the commander home, and put it to work while it is there.
    --
    -- Red Queen excludes the commander from every engineer pool it manages, so
    -- after the opening it never asked the strongest source of build power on
    -- the field for anything -- observed as an idle ACU through the early and
    -- mid game, and as an Aeon commander wandering alone to the centre of the
    -- map. Native `CDRReturnHome` only exists on the improved commander
    -- behaviour, which is attached by FAF's own initial-ACU builder groups, so
    -- whether it applies at all depends on the base template in play.
    --
    -- Two jobs, in order: bring it back if it has strayed, then assist a
    -- factory if it is idle at home. Defence keeps priority -- a commander
    -- alert already drives its own response and must not be overridden here.
    UpdateCommanderTasking = function(self)
        if not self.Brain.GetListOfUnits then
            return nil
        end
        local commanders = self.Brain:GetListOfUnits(categories.COMMAND, false)
        local commander = nil
        for _, unit in pairs(commanders or {}) do
            if IsAlive(unit) then
                commander = unit
                break
            end
        end
        if not commander or not commander.GetPosition then
            return nil
        end
        local alert = self.Strategy.ProductionDemand.DefenseAlert
        if alert and alert.Active then
            return "defense"
        end

        local home = self.World and self.World.StartPosition
        local position = commander:GetPosition()
        local leash = Constants.Policy.CommanderLeashRadius
        if home and DistanceSquared(position, home) > leash * leash then
            -- Ownership first: the build queue and the callbacks that would
            -- re-issue the order have to go, or it turns straight around.
            ReleaseEngineer(commander, home)
            Logger.Info(self.Brain, "commander recalled beyond leash")
            return "recalled"
        end

        -- Idle at home is the case worth fixing: the commander is build power
        -- standing still. Assisting is deliberately conditional on being idle,
        -- so a commander that native has usefully tasked is left alone.
        local tick = GetGameTick()
        if commander.RedQueenAssistUntil and commander.RedQueenAssistUntil > tick then
            return "assisting"
        end
        if commander.IsIdleState and not commander:IsIdleState() then
            return "busy"
        end
        local factories = self.Brain:GetListOfUnits(
            categories.STRUCTURE * categories.FACTORY, false)
        local target = nil
        local bestDistance = nil
        for _, factory in pairs(factories or {}) do
            if IsAlive(factory) and factory.GetPosition then
                local distance = DistanceSquared(position, factory:GetPosition())
                if distance and (not bestDistance or distance < bestDistance
                    or (distance == bestDistance
                        and (factory.EntityId or 0) < (target.EntityId or 0)))
                then
                    target, bestDistance = factory, distance
                end
            end
        end
        if not target then
            return "no-factory"
        end
        -- Release native ownership before ordering the assist. Clearing engine
        -- orders while a build queue and its callbacks survive leaves them to
        -- re-issue the order, which is how the commander walked off again.
        -- No native re-poll: this caller issues its own order immediately and
        -- holds the commander for CommanderAssistSeconds. Scheduling the poll
        -- re-tasked the ACU about five seconds later -- AssignEngineerTask
        -- re-platoons it, and a bare IssueGuard does not set UnitBeingAssist,
        -- which is the only thing that would have made native leave it alone.
        -- RedQueenAssistUntil then reported it as assisting for the remaining
        -- forty, so the state line claimed a commander that had walked off.
        -- It is not retreating either, so the EngineerManager hook's deferral
        -- never applied: that defers on RedQueenRetreatPosition, which only a
        -- caller passing `home` sets.
        ReleaseEngineer(commander, nil, false)
        if IssueGuard then IssueGuard({ commander }, target) end
        commander.RedQueenAssistUntil = tick
            + Constants.Policy.CommanderAssistSeconds * 10
        self.CommanderAssists = (self.CommanderAssists or 0) + 1
        return "assist"
    end,

    HasCurrentForwardBaseWork = function(self, record)
        if not record or (record.State ~= "Preparing"
            and record.State ~= "Building" and record.State ~= "Established")
        then
            return false
        end
        local engineer = record.Engineer
        if not IsAlive(engineer) then
            return false
        end
        local base = self.Brain.BuilderManagers and self.Brain.BuilderManagers[record.Name]
        local assignment = engineer.BuilderManagerData
        if not base or not base.EngineerManager or not assignment
            or assignment.EngineerManager ~= base.EngineerManager
        then
            return false
        end
        -- FAF removes completed entries in place. Match the current task by
        -- identity so a new job cannot inherit immunity, even if it reuses the
        -- queue table, blueprint, coordinates or native base manager.
        local current = engineer.EngineerBuildQueue and engineer.EngineerBuildQueue[1]
        return current ~= nil and record.BuildQueueEntries ~= nil
            and record.BuildQueueEntries[current] == true
    end,

    -- Pull an engineer out of danger it is already standing in.
    --
    -- The forward-base path re-checks its own routes, but nothing watched the
    -- engineers native builders send to extractors and expansions -- which is
    -- how they were observed walking into the enemy base. The survival veto
    -- stops new assignments; this ends the ones already under way.
    --
    -- Judged on where the engineer *is*, not where it was going: the position is
    -- known for certain, and standing in fire is the condition that matters
    -- whatever the errand was.
    UpdateEngineerRetreat = function(self)
        if not self.Brain.GetListOfUnits or not self.Intel or not self.Intel.GetThreatNear then
            return 0
        end
        local home = self.World and self.World.StartPosition
        local homeRadius = Constants.Policy.EngineerSurvivalHomeRadius
        local radius = Constants.Policy.ForwardBaseSiteRadius
        local claimed = {}
        local demand = self.Strategy and self.Strategy.ProductionDemand or {}
        -- The active slot clears as soon as the first factory establishes the
        -- base; the published site still owns the rest of its build package.
        for _, record in pairs((demand.ForwardBasePlan or {}).Sites or {}) do
            if self:HasCurrentForwardBaseWork(record) then
                claimed[record.Engineer] = true
            end
        end
        if self:HasCurrentForwardBaseWork(self.ForwardBaseActive) then
            claimed[self.ForwardBaseActive.Engineer] = true
        end

        -- An engineer under an active hold was sent somewhere by an earlier
        -- stage of this very pass, and the hold is how that stage says so.
        -- UpdateEmergencyDefense dispatches to a threatened anchor, and the
        -- threat that raised the alert is exactly what trips the test below --
        -- so without this the point defence is never built, the cooldown holds
        -- the next attempt, and the cycle repeats for every alert outside the
        -- home radius. Every other consumer already honours these holds; this
        -- loop was the one that did not.
        --
        -- Skipped outright rather than recalled-but-remembered: marking the
        -- anchor as a lethal site is what the route verdict reads, so it would
        -- refuse the next engineer sent to defend the very place under attack.
        -- Both holds are bounded, so an engineer that is genuinely stuck is
        -- reconsidered as soon as its hold lapses.
        local tick = GetGameTick()
        local function Held(engineer)
            return (engineer.RedQueenEmergencyDefenseUntil
                    and engineer.RedQueenEmergencyDefenseUntil > tick)
                or (engineer.RedQueenProductionBuildUntil
                    and engineer.RedQueenProductionBuildUntil > tick)
        end

        local engineers = self.Brain:GetListOfUnits(
            categories.MOBILE * categories.ENGINEER - categories.COMMAND, false)
        local recalled = 0
        for _, engineer in pairs(engineers or {}) do
            if IsAlive(engineer) and not claimed[engineer] and engineer.GetPosition
                and not Held(engineer)
                and not EngineerSurvival.IsRetreating(engineer)
            then
                local position = engineer:GetPosition()
                local away = not home
                    or DistanceSquared(position, home) > homeRadius * homeRadius
                if away then
                    local threat = self.Intel:GetThreatNear(position, radius) or 0
                    local escort = 0
                    if self.Strategy and self.Strategy.GetOwnThreatNear then
                        escort = self.Strategy:GetOwnThreatNear(position, radius) or 0
                    end
                    local limit = math.max(
                        Constants.Policy.EngineerSurvivalThreatFloor,
                        escort * Constants.Policy.ForwardBaseSafetyRatio
                    )
                    if threat > limit then
                        EngineerSurvival.RememberLethalSite(
                            self.Brain, position, "engineer-withdrawn")
                        if ReleaseEngineer(engineer, home) then
                            recalled = recalled + 1
                        end
                    end
                end
            end
        end
        if recalled > 0 then
            Logger.Info(self.Brain, string.format(
                "engineer retreat recalled=%d", recalled))
        end
        self.EngineerRetreats = (self.EngineerRetreats or 0) + recalled
        return recalled
    end,

    UpdateForwardBaseStatus = function(self)
        self:RevalidateEstablishedForwardBases()
        local active = self.ForwardBaseActive
        if not active then
            return
        end
        local factory = self:FindForwardBaseFactory(active)
        if factory then
            active.State = "Established"
            active.EstablishedTick = GetGameTick()
            active.Factory = factory
            active.FactoryPresent = true
            active.ManagerPresent = HasExpansionBase(self.Brain, active.Name)
            self.ForwardBaseActive = nil
            Logger.Info(self.Brain, string.format(
                "forward base established name=%s site=%s tech=%d",
                active.Name,
                active.SiteName,
                active.Tech
            ))
        else
            -- Separate the two failure modes. A dead engineer means the route
            -- was not actually safe; a timeout means the package was queued but
            -- never produced a factory. They call for different fixes, and
            -- "failed" alone cannot tell them apart.
            -- A base whose engineer is alive and whose expansion manager still
            -- exists is simply still being built: the engineer has to travel to
            -- a remote site before it can lay a factory. The old window was
            -- ForwardBaseCooldownSeconds * 30, six minutes, which retired bases
            -- that were alive and fighting -- RQFB_6_1 kept answering defence
            -- alerts as an anchor for over twelve minutes after being recorded
            -- as failed, and a retired record gets no garrison.
            local engineerLost = not IsAlive(active.Engineer)
            local managerLost = not HasExpansionBase(self.Brain, active.Name)
            local elapsed = GetGameTick() - active.StartTick
            local timedOut = elapsed
                >= Constants.Policy.ForwardBaseEstablishSeconds * 10
            -- Only worth asking while the engineer is still alive and the base
            -- has not already failed for another reason.
            local recall = nil
            if not engineerLost and not managerLost and not timedOut then
                recall = self:ForwardBaseRecallReason(active)
            end
            if engineerLost or managerLost or timedOut or recall then
                local reason = engineerLost and "engineer-lost"
                    or managerLost and "manager-lost"
                    or recall
                    or "no-factory"
                if recall then
                    if not self:RecallForwardBaseEngineer(active) then
                        Logger.Warning(self.Brain, "forward base recall failed name=" .. active.Name)
                        return
                    end
                end
                active.State = "Failed"
                active.FailedTick = GetGameTick()
                active.Failure = reason
                self.ForwardBaseActive = nil
                Logger.Info(self.Brain, string.format(
                    "forward base failed name=%s site=%s reason=%s queued=%d"
                        .. " elapsed=%.0fs routeThreat=%.1f nowThreat=%.1f limit=%.1f",
                    active.Name,
                    active.SiteName,
                    reason,
                    active.Queued or 0,
                    elapsed / 10,
                    active.RouteThreat or 0,
                    active.LastRouteThreat or active.RouteThreat or 0,
                    active.LastRouteLimit or 0
                ))
            end
        end
    end,

    -- Terminal records are kept only long enough for GetRebuildableForwardBaseSites
    -- to offer the site back at close range. Beyond that they are dropped, so a
    -- long match cannot accumulate records or stale claims without bound.
    PruneForwardBaseRecords = function(self)
        local tick = GetGameTick()
        local retention = Constants.Policy.ForwardBaseRecordRetentionSeconds * 10
        local retained = {}
        local retainedRecords = {}
        for _, base in pairs(self.ForwardBases) do
            local terminalTick = base.FailedTick or base.DestroyedTick
            if not terminalTick or tick - terminalTick < retention then
                table.insert(retained, base)
                retainedRecords[base] = true
            end
        end
        -- A claim lives exactly as long as the record holding it, which is the
        -- only reading that matches how claims are actually given up: a
        -- destroyed base releases its own claim immediately, while a failed
        -- registration keeps its claim on purpose, because its structures are
        -- still queued at the marker.
        --
        -- Keying the release on site name instead meant any older attempt at
        -- the same marker could drop a live owner's claim as it aged out --
        -- so a failed record lost the site before its own retention ran, and a
        -- third attempt could queue a second package onto the half-built one.
        for siteName, owner in pairs(self.ForwardBaseClaims) do
            if not retainedRecords[owner] then
                self.ForwardBaseClaims[siteName] = nil
            end
        end
        self.ForwardBases = retained
    end,

    CountViableForwardBases = function(self)
        local count = 0
        for _, base in pairs(self.ForwardBases) do
            -- Preparing counts too: an attempt in flight has already queued
            -- structures and claimed its site, so it occupies a map slot.
            if base.State == "Preparing"
                or base.State == "Building"
                or base.State == "Established"
            then
                count = count + 1
            end
        end
        return count
    end,

    StartForwardBase = function(self, engineer, site)
        local faction = self.Context.FactionIndex
        local buildingTemplate = BuildingTemplates.BuildingTemplates[faction]
        local baseTemplate = BaseTemplates.ExpansionBaseTemplates[faction]
        if not buildingTemplate or not baseTemplate then
            return false
        end

        -- Throttle from the attempt, not from success. A site the engine
        -- refuses must not be retried on the very next production pass.
        self.LastForwardBaseTick = GetGameTick()

        local movedTemplate = AIBuildStructures.AIBuildBaseTemplateFromLocation(
            baseTemplate,
            site.Position
        )
        local tech = UnitTech(engineer)
        local tier = self:ForwardBaseTier(tech)
        local package = tier.Package
        local baseName = string.format(
            "RQFB_%d_%d",
            self.Brain:GetArmyIndex(),
            self.ForwardBaseSequence + 1
        )
        local constructionData = {
            ExpansionRadius = Constants.Policy.ForwardBaseSiteRadius,
            NearMarkerType = site.Type,
            BuildStructures = package,
        }

        -- Nothing is recorded and no site is claimed until at least one
        -- structure is actually queued, so a failed attempt leaves no leaked
        -- record and no permanently claimed site behind.
        local queued = 0
        local buildQueueEntries = {}
        local buildError = nil
        -- ipairs, not pairs: the package is an ordered build plan and `pairs`
        -- gives no ordering contract, while simulation logic has to be
        -- deterministic.
        for _, buildingType in ipairs(package) do
            local started, failure, entry = ExecuteBuildStructure(
                self.Brain,
                engineer,
                buildingType,
                buildingTemplate,
                movedTemplate,
                "absolute",
                site.Position
            )
            if started then
                queued = queued + 1
                if entry then buildQueueEntries[entry] = true end
            elseif failure then
                buildError = buildError or failure
            end
        end
        if queued == 0 then
            Logger.Warning(self.Brain, string.format(
                "forward base aborted site=%s reason=%s error=%s",
                site.Name,
                buildError and "engine-rejected" or "no-structures-queued",
                tostring(buildError)
            ))
            return false
        end
        if buildError then
            Logger.Warning(self.Brain, string.format(
                "forward base partial site=%s queued=%d error=%s",
                site.Name,
                queued,
                buildError
            ))
        end

        self.ForwardBaseSequence = self.ForwardBaseSequence + 1
        local record = {
            Name = baseName,
            SiteName = site.Name,
            Type = site.Type,
            Position = site.Position,
            RouteThreat = site.RouteThreat,
            Layer = site.Layer or "Land",
            -- The tier's own minimum is what marks the base defensible, so it
            -- travels with the record rather than being re-derived by whoever
            -- asks.
            TierPlan = tier,
            Engineer = engineer,
            Tech = tech,
            StartTick = GetGameTick(),
            State = "Preparing",
            Queued = queued,
            BuildQueueEntries = buildQueueEntries,
            Registered = false,
        }
        table.insert(self.ForwardBases, record)
        self.ForwardBaseClaims[site.Name] = record

        local registrationCompleted, registrationError = pcall(
            AIBuildStructures.AINewExpansionBase,
            self.Brain,
            baseName,
            site.Position,
            engineer,
            constructionData
        )
        record.Registered = HasExpansionBase(self.Brain, baseName)
        if not registrationCompleted or not record.Registered then
            record.State = "Failed"
            record.Failure = "ExpansionRegistration"
            -- The claim is kept: structures are already queued at the site, so
            -- a second base must not target it. PruneForwardBaseRecords
            -- releases it once the record ages out.
            record.FailedTick = GetGameTick()
            Logger.Error(self.Brain, string.format(
                "forward base registration failed name=%s site=%s queued=%d error=%s",
                baseName,
                site.Name,
                record.Queued,
                registrationCompleted and "manager-missing" or tostring(registrationError)
            ))
            return false
        end

        record.State = "Building"
        self.ForwardBaseActive = record
        Logger.Info(self.Brain, string.format(
            "forward base started name=%s site=%s tech=%d queued=%d layer=%s"
                .. " routeThreat=%.1f coverage=%.2f effective=%.1f limit=%.1f"
                .. " first=%s needs=%dpd/%daa/%dsh",
            baseName,
            site.Name,
            tech,
            record.Queued,
            tostring(site.Layer or "Land"),
            site.RouteThreat or 0,
            site.RouteCoverage or 0,
            site.EffectiveThreat or site.RouteThreat or 0,
            site.SafetyLimit or 0,
            tostring(package[1] or "none"),
            tier.MinimumDefenses or 0,
            tier.MinimumAntiAir or 0,
            tier.MinimumShields or 0
        ))
        return true
    end,

    UpdateForwardBases = function(self)
        self:UpdateForwardBaseStatus()
        self:PruneForwardBaseRecords()
        local plan = {
            Active = self.ForwardBaseActive ~= nil,
            Sites = self.ForwardBases,
        }
        self.Strategy.ProductionDemand.ForwardBasePlan = plan
        if self.ForwardBaseActive then
            self:LogForwardBaseBlocked("construction-active")
            return
        end
        if self:CountViableForwardBases() >= self.World:GetMaximumForwardBases() then
            self:LogForwardBaseBlocked("map-cap")
            return
        end
        if GetGameTick() - self.LastForwardBaseTick
            < Constants.Policy.ForwardBaseCooldownSeconds * 10
        then
            self:LogForwardBaseBlocked("cooldown")
            return
        end

        local objective = self.Strategy.CurrentObjective
        if not objective
            or not objective.Position
        then
            self:LogForwardBaseBlocked("no-objective")
            return
        end
        if objective.Type == "Recover"
            or objective.Type == "Stage"
        then
            self:LogForwardBaseBlocked("objective-" .. string.lower(objective.Type))
            return
        end
        local engineer = self:FindForwardEngineer()
        local blockReason = self:GetForwardBaseBlockReason(engineer)
        if blockReason then
            self:LogForwardBaseBlocked(blockReason)
            return
        end
        local engineerPosition = engineer:GetPosition()
        if not engineerPosition then
            self:LogForwardBaseBlocked("engineer-without-position")
            return
        end
        local escortThreat = self.Strategy:GetOwnThreatNear(
            engineerPosition,
            Constants.Policy.ForwardBaseSiteRadius
        )
        -- Defend may persist while distant parts of a large map are safe.
        -- SelectForwardBaseSite checks observed route and destination threat;
        -- the objective supplies direction, not permission to expand.
        local site = self.World:SelectForwardBaseSite(
            engineerPosition,
            objective.Position,
            self.Intel,
            self.ForwardBaseClaims,
            escortThreat,
            self:GetRebuildableForwardBaseSites(),
            UnitTravelLayer(engineer)
        )
        if site then
            local started = self:StartForwardBase(engineer, site)
            self.Strategy.ProductionDemand.ForwardBasePlan.Active = self.ForwardBaseActive ~= nil
            if started then
                self.LastForwardBaseBlockReason = nil
                plan.BlockReason = nil
            else
                self:LogForwardBaseBlocked("start-failed")
            end
        else
            self:LogForwardBaseBlocked("no-safe-site")
        end
    end,

    Update = function(self)
        self:RegisterCounterBuilders()
        local factories, counts = self:CountFactories()
        local targets = self:ApplyFactoryCapacityPolicy(counts)
        self:UpdateTierPolicy(factories)
        self:ApplyTierPolicy()
        self:ApplyEngineerPolicy(counts)
        self:TryExpandFactoryCapacity(counts, targets)
        -- One ArmyPool walk per pass, shared by both engineer consumers.
        local unassigned, unassignedByEntityId = self:GetUnassignedEngineers()
        self:UpdateEmergencyDefense(unassigned)
        self:UpdateShoreArtillery(unassigned)
        self:UpdateShoreTorpedo(unassigned)
        self:UpdateFactoryAssistance(factories, unassigned, unassignedByEntityId)
        self:UpdateForwardBases()
        self:UpdateEngineerRetreat()
        self:UpdateCommanderTasking()
        self.Counts = counts
    end,
}

function Create(brain, context, world, economy, intel, strategy)
    return ProductionManager(brain, context, world, economy, intel, strategy)
end
