local AIBuildStructures = import("/lua/AI/aibuildstructures.lua")
local AIAddBuilderTable = import("/lua/AI/AIAddBuilderTable.lua")
local BaseTemplates = import("/lua/basetemplates.lua")
local BuildingTemplates = import("/lua/buildingtemplates.lua")
local Constants = import("/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua")
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
    if hash.AIR then
        return "Air"
    end
    if hash.NAVAL then
        return "Naval"
    end
    return "Land"
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
local function ExecuteBuildStructure(brain, builder, buildingType, buildingTemplate, baseTemplate, reference)
    local completed, result = pcall(
        AIBuildStructures.AIExecuteBuildStructure,
        brain,
        builder,
        buildingType,
        nil,
        false,
        buildingTemplate,
        baseTemplate,
        reference
    )
    if not completed then
        return false, tostring(result)
    end
    return result and true or false, nil
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
                and not self.CounterBuildersRegistered[locationType]
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
                self.CounterBuildersRegistered[locationType] = true
                Logger.Info(self.Brain, string.format(
                    "adaptive production registered base=%s",
                    tostring(locationType)
                ))
            end
        end
    end,

    CountFactories = function(self)
        local factories = self.Brain:GetListOfUnits(categories.STRUCTURE * categories.FACTORY, false)
        local counts = { Total = 0, Land = 0, Air = 0, Naval = 0 }
        for _, factory in pairs(factories) do
            if factory and not factory.Dead then
                local layer = FactoryLayer(factory)
                counts.Total = counts.Total + 1
                counts[layer] = counts[layer] + 1
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
        local policy = {
            Land = { Highest = 1, T1 = 0, T2 = 0, T3 = 0 },
            Air = { Highest = 1, T1 = 0, T2 = 0, T3 = 0 },
            Naval = { Highest = 1, T1 = 0, T2 = 0, T3 = 0 },
        }
        for _, factory in pairs(factories) do
            if factory and not factory.Dead then
                local hash = factory:GetBlueprint().CategoriesHash or {}
                local domain = UnitDomain(hash)
                local tier = UnitTier(hash)
                local domainPolicy = policy[domain]
                domainPolicy["T" .. tostring(tier)] = domainPolicy["T" .. tostring(tier)] + 1
                domainPolicy.Highest = math.max(domainPolicy.Highest, tier)
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

        local highest = (self.TierPolicy[profile.Domain] or {}).Highest or 1
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

    FindIdleBuilder = function(self, blueprintId)
        local pool = self.Brain:GetPlatoonUniquelyNamed("ArmyPool")
        if not pool then
            return nil
        end

        local builders = {}
        for _, unit in pairs(pool:GetPlatoonUnits()) do
            if unit and EntityCategoryContains(categories.ENGINEER - categories.COMMAND, unit) then
                table.insert(builders, unit)
            end
        end
        table.sort(builders, function(a, b)
            return (a.EntityId or 0) < (b.EntityId or 0)
        end)

        for _, builder in pairs(builders) do
            if IsAvailable(builder) and builder:CanBuild(blueprintId) then
                return builder
            end
        end
        return nil
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
            if UnitTech(engineer) == 1
                and IsAvailable(engineer)
                and not engineer.RedQueenEmergencyDefenseUntil
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
            movedTemplate
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
        if tick - self.LastFactoryRequestTick < cooldown
            or not self.Economy:CanExpandProduction(counts.Total)
        then
            return
        end

        local faction = self.Context.FactionIndex
        local buildingTemplate = BuildingTemplates.BuildingTemplates[faction]
        local baseTemplate = BaseTemplates.BaseTemplates[faction]
        if not buildingTemplate or not baseTemplate then
            return
        end

        local buildingType = self:SelectFactoryType(counts, targets)
        if not buildingType then
            return
        end
        local blueprintId = FindBuildingId(buildingTemplate, buildingType)
        if not blueprintId then
            return
        end

        local builder = self:FindIdleBuilder(blueprintId)
        if not builder then
            return
        end

        local started, buildError = ExecuteBuildStructure(
            self.Brain,
            builder,
            buildingType,
            buildingTemplate,
            baseTemplate
        )
        if buildError then
            Logger.Error(self.Brain, string.format(
                "production expansion failed type=%s error=%s",
                buildingType,
                buildError
            ))
        end
        if started then
            self.LastFactoryRequestTick = tick
            Logger.Info(self.Brain, string.format(
                "production expansion type=%s factories=%d desired=%d deficit=%d",
                buildingType,
                counts.Total,
                targets.Total or self.Economy.State.DesiredFactories,
                self.Context.ArmyDeficit
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
    ForwardEngineerCandidates = function(self)
        local candidates = {}
        local seen = {}
        local tick = GetGameTick()

        local function Consider(unit)
            if not IsAlive(unit) or seen[unit.EntityId] then
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

    ForwardBasePackage = function(self, tech)
        if tech >= 3 then
            local groundType = self.Context.FactionIndex == 1 and "T3GroundDefense" or "T2GroundDefense"
            local groundCount = self.Context.FactionIndex == 1 and 4 or 6
            local package = { "T1LandFactory", "T1Radar" }
            for _ = 1, groundCount do table.insert(package, groundType) end
            for _ = 1, 3 do table.insert(package, "T3AADefense") end
            table.insert(package, "T3ShieldDefense")
            table.insert(package, "T2StrategicMissile")
            table.insert(package, "T2StrategicMissile")
            table.insert(package, "T2Artillery")
            table.insert(package, "T2Artillery")
            table.insert(package, "T3StrategicMissileDefense")
            return package
        elseif tech >= 2 then
            return {
                "T1LandFactory",
                "T1Radar",
                "T2GroundDefense", "T2GroundDefense", "T2GroundDefense", "T2GroundDefense",
                "T2AADefense", "T2AADefense",
                "T2ShieldDefense",
                "T2StrategicMissile",
                "T2MissileDefense",
                "T2Artillery",
            }
        end
        return {
            "T1LandFactory",
            "T1Radar",
            "T1GroundDefense", "T1GroundDefense",
            "T1AADefense", "T1AADefense",
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
                    self.ForwardBaseClaims[base.SiteName] = nil
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
            if engineerLost or managerLost or timedOut then
                local reason = engineerLost and "engineer-lost"
                    or managerLost and "manager-lost"
                    or "no-factory"
                active.State = "Failed"
                active.FailedTick = GetGameTick()
                active.Failure = reason
                self.ForwardBaseActive = nil
                Logger.Info(self.Brain, string.format(
                    "forward base failed name=%s site=%s reason=%s queued=%d elapsed=%.0fs routeThreat=%.1f",
                    active.Name,
                    active.SiteName,
                    reason,
                    active.Queued or 0,
                    elapsed / 10,
                    active.RouteThreat or 0
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
        local liveSites = {}
        local expiredSites = {}
        for _, base in pairs(self.ForwardBases) do
            local terminalTick = base.FailedTick or base.DestroyedTick
            if not terminalTick or tick - terminalTick < retention then
                table.insert(retained, base)
                if base.SiteName and (base.State == "Preparing"
                    or base.State == "Building" or base.State == "Established")
                then
                    liveSites[base.SiteName] = true
                end
            elseif base.SiteName then
                expiredSites[base.SiteName] = true
            end
        end
        -- A replacement can own the same marker as an expired attempt.
        -- Resolve all retained owners before releasing any shared claim.
        for siteName, _ in pairs(expiredSites) do
            if not liveSites[siteName] then
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
        local package = self:ForwardBasePackage(tech)
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
        local buildError = nil
        for _, buildingType in pairs(package) do
            local started, failure = ExecuteBuildStructure(
                self.Brain,
                engineer,
                buildingType,
                buildingTemplate,
                movedTemplate,
                site.Position
            )
            if started then
                queued = queued + 1
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
            Engineer = engineer,
            Tech = tech,
            StartTick = GetGameTick(),
            State = "Preparing",
            Queued = queued,
            Registered = false,
        }
        table.insert(self.ForwardBases, record)
        self.ForwardBaseClaims[site.Name] = true

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
            "forward base started name=%s site=%s tech=%d queued=%d routeThreat=%.1f",
            baseName,
            site.Name,
            tech,
            record.Queued,
            site.RouteThreat
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
            or objective.Type == "Defend"
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
        local site = self.World:SelectForwardBaseSite(
            engineerPosition,
            objective.Position,
            self.Intel,
            self.ForwardBaseClaims,
            escortThreat,
            self:GetRebuildableForwardBaseSites()
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
        self:TryExpandFactoryCapacity(counts, targets)
        -- One ArmyPool walk per pass, shared by both engineer consumers.
        local unassigned, unassignedByEntityId = self:GetUnassignedEngineers()
        self:UpdateEmergencyDefense(unassigned)
        self:UpdateFactoryAssistance(factories, unassigned, unassignedByEntityId)
        self:UpdateForwardBases()
        self.Counts = counts
    end,
}

function Create(brain, context, world, economy, intel, strategy)
    return ProductionManager(brain, context, world, economy, intel, strategy)
end
