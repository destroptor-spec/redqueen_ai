local Lifecycle = import("/mods/TheRedQueen/lua/AI/RedQueen/BaseLifecycle.lua")
local AdaptiveBrain = import("/lua/aibrains/adaptive-ai.lua").AIBrain

local CombatManager = import("/mods/TheRedQueen/lua/AI/RedQueen/CombatManager.lua")
local Constants = import("/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua")
local Diagnostics = import("/mods/TheRedQueen/lua/AI/RedQueen/Diagnostics.lua")
local EconomyManager = import("/mods/TheRedQueen/lua/AI/RedQueen/EconomyManager.lua")
local IncomeBonus = import("/mods/TheRedQueen/lua/AI/RedQueen/IncomeBonus.lua")
local IntelManager = import("/mods/TheRedQueen/lua/AI/RedQueen/IntelManager.lua")
local Logger = import("/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua")
local MatchContext = import("/mods/TheRedQueen/lua/AI/RedQueen/MatchContext.lua")
local PingManager = import("/mods/TheRedQueen/lua/AI/RedQueen/PingManager.lua")
local ProductionManager = import("/mods/TheRedQueen/lua/AI/RedQueen/ProductionManager.lua")
local Profile = import("/mods/TheRedQueen/lua/AI/RedQueen/Profile.lua")
local ProductionTrace = import("/mods/TheRedQueen/lua/AI/RedQueen/ProductionTrace.lua")
local Scheduler = import("/mods/TheRedQueen/lua/AI/RedQueen/Scheduler.lua")
local ScoutingConfig = import("/mods/TheRedQueen/lua/AI/RedQueen/ScoutingConfig.lua")
local StrategyDirector = import("/mods/TheRedQueen/lua/AI/RedQueen/StrategyDirector.lua")
local TeamCoordinator = import("/mods/TheRedQueen/lua/AI/RedQueen/TeamCoordinator.lua")
local WorldModel = import("/mods/TheRedQueen/lua/AI/RedQueen/WorldModel.lua")

---@class RedQueenAIBrain : AIBrainAdaptive
AIBrain = Class(AdaptiveBrain) {
    OnCreateAI = function(self, planName)
        -- Brain selection has already used the lobby key. Present the maintained
        -- lower-level builder framework with the personality it understands.
        self.RedQueenLobbyPersonality = ScenarioInfo.ArmySetup[self.Name].AIPersonality
        ScenarioInfo.ArmySetup[self.Name].AIPersonality = "adaptive"

        AdaptiveBrain.OnCreateAI(self, planName)

        self.RedQueenStarted = false
        self.RedQueenCleaned = false
        self.RedQueenPendingPings = {}
        self.RedQueenDebug = false
    end,

    AddBuilderManagers = function(self, position, radius, location, useCenter)
        local old = self.BuilderManagers and self.BuilderManagers[location]
        if old then Lifecycle.Retire(self, location, old) end
        AdaptiveBrain.AddBuilderManagers(self, position, radius, location, useCenter)
        Lifecycle.Register(self, location, self.BuilderManagers[location])
    end,

    OnUnitStartBuild = function(self, builder, built)
        AdaptiveBrain.OnUnitStartBuild(self, builder, built)
        local trace = self.RedQueenModules and self.RedQueenModules.ProductionTrace
        if trace then trace:Safe(trace.UnitStarted, builder, built) end
    end,

    OnBeginSession = function(self)
        AdaptiveBrain.OnBeginSession(self)
        self:ForkThread(self.RedQueenStartThread)
    end,

    RedQueenStartThread = function(self)
        -- Initial armies, props, marker caches, and the FAF navigation mesh must
        -- exist before directors inspect the world.
        WaitTicks(2)
        if self.Status ~= "InProgress" or self.RedQueenStarted then
            return
        end

        local context = MatchContext.Create(self)
        self.RedQueenContext = context
        IncomeBonus.ApplyToArmy(self, context)
        IncomeBonus.LogAppliedBonus(self, context)
        for _, army in ipairs(context.AlliedArmies) do
            local other = ArmyBrains[army]
            local x, z = other:GetArmyStartPos()
            local income = other.RedQueenContext and string.format(" income=%.2f",
                other.RedQueenContext.IncomeMultiplier) or ""
            Logger.Info(self, string.format("match-contract army=%d name=%s faction=%d side=ally start=%.1f,%.1f%s",
                army, other.Name, other:GetFactionIndex(), x, z, income))
        end
        for _, army in ipairs(context.EnemyArmies) do
            local other = ArmyBrains[army]
            local x, z = other:GetArmyStartPos()
            Logger.Info(self, string.format("match-contract army=%d name=%s faction=%d side=enemy start=%.1f,%.1f",
                army, other.Name, other:GetFactionIndex(), x, z))
        end

        local scouting = ScoutingConfig.Create(ScenarioInfo.Options)
        self.RedQueenScouting = scouting
        Logger.Info(self, string.format(
            "scouting mode=%s production=%s dispatch=%s",
            scouting.Mode,
            scouting.AdaptiveProduction and "adaptive" or "binary",
            scouting.DirectedDispatch and "on" or "off"
        ))

        local modules = {}
        modules.World = WorldModel.Create(self, context)
        -- Chosen once, from a finished world model, before any director reads a
        -- behaviour flag. Exposed on the brain as well as the module table so
        -- builder conditions, which only receive aiBrain, can reach it.
        modules.Profile = Profile.Create(self, context, modules.World)
        self.RedQueenProfile = modules.Profile
        modules.Intel = IntelManager.Create(self)
        modules.Economy = EconomyManager.Create(self, context)
        modules.Team = TeamCoordinator.Create(self, context)
        modules.Pings = PingManager.Create(self)
        modules.Strategy = StrategyDirector.Create(
            self,
            context,
            modules.World,
            modules.Intel,
            modules.Economy,
            modules.Team,
            modules.Pings
        )
        modules.Production = ProductionManager.Create(
            self,
            context,
            modules.World,
            modules.Economy,
            modules.Intel,
            modules.Strategy
        )
        modules.Combat = CombatManager.Create(self, modules.World, modules.Economy, modules.Strategy)
        modules.Diagnostics = Diagnostics.Create(self, modules)
        self.RedQueenModules = modules
        -- The director reads sibling modules -- built factory counts for the
        -- engineer target, the scouting summary for scout production -- through
        -- `self.Modules`, and nothing ever gave it the table. Both readers
        -- silently took their absent-module fallback: the engineer target saw
        -- zero built factories for the whole match, and scout production sat at
        -- its floor while the army could see nothing.
        --
        -- Assigned by reference after construction, so modules created below
        -- this line are visible too. Per-brain, so no army shares another's.
        --
        -- Specs did not catch it because they inject `director.Modules`
        -- directly; the structural guard in validate_mod.py checks this wiring.
        modules.Strategy.Modules = modules
        modules.ProductionTrace = ProductionTrace.Create(self, modules)
        modules.Production.Trace = modules.ProductionTrace
        modules.Combat.Trace = modules.ProductionTrace
        modules.Strategy.Trace = modules.ProductionTrace
        modules.Intel.Trace = modules.ProductionTrace
        if ScenarioInfo.Options.RedQueenDefenseFixture and self:GetArmyIndex() == 2 then
            ForkThread(import("/mods/TheRedQueen/lua/AI/RedQueen/DefenseFixture.lua").Run, self)
        end
        if ScenarioInfo.Options.RedQueenLifecycleFixture and self:GetArmyIndex() == 2 then
            ForkThread(import("/mods/TheRedQueen/lua/AI/RedQueen/LifecycleFixture.lua").Run, self)
        end

        for _, ping in pairs(self.RedQueenPendingPings) do
            modules.Pings:Handle(ping)
        end
        self.RedQueenPendingPings = {}

        local scheduler = Scheduler.Create(self)
        scheduler:Add("economy", Constants.Ticks.Economy, 1, function()
            modules.Economy:Update()
        end)
        scheduler:Add("intel", Constants.Ticks.Intel, 4, function()
            modules.Intel:Update()
        end)
        scheduler:Add("pings", Constants.Ticks.Ping, 6, function()
            modules.Pings:Update()
        end)
        scheduler:Add("team", Constants.Ticks.Team, 10, function()
            modules.Team:Update(modules.Economy, modules.Intel, modules.World)
        end)
        scheduler:Add("strategy", Constants.Ticks.Strategy, 14, function()
            modules.Strategy:Update()
        end)
        scheduler:Add("production", Constants.Ticks.Production, 20, function()
            modules.Production:Update()
            if modules.ProductionTrace then modules.ProductionTrace:Update() end
        end)
        scheduler:Add("combat", Constants.Ticks.Combat, 26, function()
            modules.Combat:Update()
        end)
        scheduler:Add("world", Constants.Ticks.World, 30, function()
            modules.World:Update()
        end)
        scheduler:Add("income", Constants.Ticks.IncomeSweep, 35, function()
            IncomeBonus.SweepArmy(self, context)
        end)
        scheduler:Add("diagnostics", 600, 100, function()
            modules.Diagnostics:Update()
        end)
        self.RedQueenScheduler = scheduler
        self.RedQueenStarted = true
        scheduler:Start()

        Logger.Info(self, string.format(
            "started version=%s faction=%d victory=%s",
            Constants.Version,
            context.FactionIndex,
            context.VictoryCondition
        ))
    end,

    OnUnitStopBeingBuilt = function(self, unit, builder, layer)
        AdaptiveBrain.OnUnitStopBeingBuilt(self, unit, builder, layer)
        IncomeBonus.OnUnitCreated(self, unit)
        local trace = self.RedQueenModules and self.RedQueenModules.ProductionTrace
        if trace then trace:Safe(trace.UnitCompleted, unit, builder) end
    end,

    OnUnitKilled = function(self, unit, instigator, damageType, overkillRatio)
        local trace = self.RedQueenModules and self.RedQueenModules.ProductionTrace
        if trace then trace:Safe(trace.UnitLost, unit) end
        AdaptiveBrain.OnUnitKilled(self, unit, instigator, damageType, overkillRatio)
        if self.RedQueenModules and self.RedQueenModules.Strategy then
            self.RedQueenModules.Strategy:RecordUnitLoss(unit)
        end
    end,

    DoAIPing = function(self, pingData)
        if self.RedQueenModules and self.RedQueenModules.Pings then
            self.RedQueenModules.Pings:Handle(pingData)
        else
            table.insert(self.RedQueenPendingPings, pingData)
        end
    end,

    RedQueenCleanup = function(self)
        if self.RedQueenCleaned then
            return
        end
        self.RedQueenCleaned = true
        if self.RedQueenDistressThread then
            KillThread(self.RedQueenDistressThread)
            self.RedQueenDistressThread = nil
        end
        self:RedQueenRetireBuilders()
        local trace = self.RedQueenModules and self.RedQueenModules.ProductionTrace
        if trace then trace:Safe(trace.Observe, "lifecycle", "brain", "brain-cleanup", "") end
        if self.RedQueenModules and self.RedQueenModules.ProductionTrace then
            self.RedQueenModules.ProductionTrace:Destroy()
        end

        if self.RedQueenScheduler then
            self.RedQueenScheduler:Stop()
        end
        if self.RedQueenModules and self.RedQueenModules.Team then
            self.RedQueenModules.Team:Destroy()
        end
        self:RedQueenRetireBuilders()
    end,

    RedQueenRetireBuilders = function(self)
        Lifecycle.Cleanup(self)
    end,

    OnVictory = function(self)
        Logger.Info(self, "lifecycle game-result result=victory tick=" .. tostring(GetGameTick()))
        self:RedQueenCleanup()
        AdaptiveBrain.OnVictory(self)
    end,

    OnDraw = function(self)
        Logger.Info(self, "lifecycle game-result result=draw tick=" .. tostring(GetGameTick()))
        self:RedQueenCleanup()
        AdaptiveBrain.OnDraw(self)
    end,

    OnDefeat = function(self)
        Logger.Info(self, "lifecycle game-result result=defeat tick=" .. tostring(GetGameTick()))
        self:RedQueenCleanup()
        AdaptiveBrain.OnDefeat(self)
    end,

    OnDestroy = function(self)
        self:RedQueenCleanup()
        AdaptiveBrain.OnDestroy(self)
    end,
}
