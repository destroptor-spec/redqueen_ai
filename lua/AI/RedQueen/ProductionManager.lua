local AIBuildStructures = import("/lua/AI/aibuildstructures.lua")
local AIAddBuilderTable = import("/lua/AI/AIAddBuilderTable.lua")
local BaseTemplates = import("/lua/basetemplates.lua")
local BuildingTemplates = import("/lua/buildingtemplates.lua")
local Constants = import("/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua")
local Logger = import("/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua")

import("/mods/TheRedQueen/lua/AI/RedQueen/CounterBuilders.lua")
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
    if hash.TRANSPORTFOCUS then return "Transport" end
    if hash.SHIELD or hash.COUNTERINTELLIGENCE then return "Shield" end
    if hash.INDIRECTFIRE or hash.ARTILLERY or hash.TACTICALMISSILEPLATFORM then
        return "Artillery"
    end
    if hash.AIR and hash.ANTIAIR and not hash.BOMBER then return "AirDefense" end
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
        if current.RedQueenTierDisabled then
            local changed = current.Priority ~= 0
            current.Priority = 0
            return changed
        end
        return current.RedQueenOriginalCalculatePriority(current, manager)
    end
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
            category = category * categories.TRANSPORTFOCUS
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

    IsObsoleteProfile = function(self, profile)
        if not profile or profile.Role == "Utility" then
            return false
        end
        local highest = (self.TierPolicy[profile.Domain] or {}).Highest or 1
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

    SelectFactoryType = function(self, counts)
        if self.World.WaterRatio >= 0.20 and counts.Naval < math.max(1, math.floor(counts.Total * self.Strategy.ProductionDemand.Naval)) then
            return "T1SeaFactory"
        end
        if counts.Air < math.max(1, math.floor(counts.Total * self.Strategy.ProductionDemand.Air)) then
            return "T1AirFactory"
        end
        return "T1LandFactory"
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

    TryExpandFactoryCapacity = function(self, counts)
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

        local buildingType = self:SelectFactoryType(counts)
        local blueprintId = FindBuildingId(buildingTemplate, buildingType)
        if not blueprintId then
            return
        end

        local builder = self:FindIdleBuilder(blueprintId)
        if not builder then
            return
        end

        local started = AIBuildStructures.AIExecuteBuildStructure(
            self.Brain,
            builder,
            buildingType,
            false,
            false,
            buildingTemplate,
            baseTemplate
        )
        if started then
            self.LastFactoryRequestTick = tick
            Logger.Info(self.Brain, string.format(
                "production expansion type=%s factories=%d desired=%d deficit=%d",
                buildingType,
                counts.Total,
                self.Economy.State.DesiredFactories,
                self.Context.ArmyDeficit
            ))
        end
    end,

    FindForwardEngineer = function(self)
        local pool = self.Brain:GetPlatoonUniquelyNamed("ArmyPool")
        if not pool then
            return nil
        end
        local engineers = {}
        for _, unit in pairs(pool:GetPlatoonUnits()) do
            if IsAvailable(unit)
                and EntityCategoryContains(categories.ENGINEER - categories.COMMAND, unit)
            then
                table.insert(engineers, unit)
            end
        end
        table.sort(engineers, function(a, b)
            local aTech = UnitTech(a)
            local bTech = UnitTech(b)
            if aTech ~= bTech then
                return aTech > bTech
            end
            return (a.EntityId or 0) < (b.EntityId or 0)
        end)
        return engineers[1]
    end,

    CanStartForwardBase = function(self, engineer)
        local alert = self.Strategy.ProductionDemand.DefenseAlert
        local state = self.Economy.State
        if not engineer
            or not engineer.BuilderManagerData
            or not engineer.BuilderManagerData.EngineerManager
            or (alert and alert.Active)
            or state.StallRisk
            or state.MassTrend < 0
            or state.EnergyTrend < 0
            or state.MassStoredRatio < 0.10
            or state.EnergyStoredRatio < 0.10
        then
            return false
        end

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
        return state.MassIncome >= mass and state.EnergyIncome >= energy
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
        elseif not IsAlive(active.Engineer)
            or GetGameTick() - active.StartTick
                >= Constants.Policy.ForwardBaseCooldownSeconds * 30
        then
            active.State = "Failed"
            self.ForwardBaseActive = nil
            Logger.Info(self.Brain, string.format(
                "forward base failed name=%s site=%s",
                active.Name,
                active.SiteName
            ))
        end
    end,

    CountViableForwardBases = function(self)
        local count = 0
        for _, base in pairs(self.ForwardBases) do
            if base.State == "Building" or base.State == "Established" then
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

        local movedTemplate = AIBuildStructures.AIBuildBaseTemplateFromLocation(
            baseTemplate,
            site.Position
        )
        local tech = UnitTech(engineer)
        local package = self:ForwardBasePackage(tech)
        self.ForwardBaseSequence = self.ForwardBaseSequence + 1
        local baseName = string.format(
            "RQFB_%d_%d",
            self.Brain:GetArmyIndex(),
            self.ForwardBaseSequence
        )
        local constructionData = {
            ExpansionRadius = Constants.Policy.ForwardBaseSiteRadius,
            NearMarkerType = site.Type,
            BuildStructures = package,
        }
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
            Queued = 0,
            Registered = false,
        }
        table.insert(self.ForwardBases, record)
        self.ForwardBaseClaims[site.Name] = true

        for _, buildingType in pairs(package) do
            if AIBuildStructures.AIExecuteBuildStructure(
                self.Brain,
                engineer,
                buildingType,
                false,
                false,
                buildingTemplate,
                movedTemplate,
                site.Position
            ) then
                record.Queued = record.Queued + 1
            end
        end
        if record.Queued == 0 then
            self.ForwardBaseClaims[site.Name] = nil
            table.remove(self.ForwardBases, table.getn(self.ForwardBases))
            Logger.Warning(self.Brain, string.format(
                "forward base aborted name=%s site=%s reason=no-structures-queued",
                baseName,
                site.Name
            ))
            return false
        end
        self.LastForwardBaseTick = GetGameTick()

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
        local plan = {
            Active = self.ForwardBaseActive ~= nil,
            Sites = self.ForwardBases,
        }
        self.Strategy.ProductionDemand.ForwardBasePlan = plan
        if self.ForwardBaseActive
            or self:CountViableForwardBases() >= self.World:GetMaximumForwardBases()
            or GetGameTick() - self.LastForwardBaseTick
                < Constants.Policy.ForwardBaseCooldownSeconds * 10
        then
            return
        end

        local objective = self.Strategy.CurrentObjective
        if not objective
            or not objective.Position
            or objective.Type == "Recover"
            or objective.Type == "Stage"
            or objective.Type == "Defend"
        then
            return
        end
        local engineer = self:FindForwardEngineer()
        if not self:CanStartForwardBase(engineer) then
            return
        end
        local engineerPosition = engineer:GetPosition()
        if not engineerPosition then
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
            self:StartForwardBase(engineer, site)
            self.Strategy.ProductionDemand.ForwardBasePlan.Active = self.ForwardBaseActive ~= nil
        end
    end,

    Update = function(self)
        self:RegisterCounterBuilders()
        local factories, counts = self:CountFactories()
        self:UpdateTierPolicy(factories)
        self:ApplyTierPolicy()
        self:TryExpandFactoryCapacity(counts)
        self:UpdateForwardBases()
        self.Counts = counts
    end,
}

function Create(brain, context, world, economy, intel, strategy)
    return ProductionManager(brain, context, world, economy, intel, strategy)
end
