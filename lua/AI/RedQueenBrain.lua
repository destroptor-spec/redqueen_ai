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
local Scheduler = import("/mods/TheRedQueen/lua/AI/RedQueen/Scheduler.lua")
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

        local modules = {}
        modules.World = WorldModel.Create(self, context)
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
    end,

    OnUnitKilled = function(self, unit, instigator, damageType, overkillRatio)
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

        if self.RedQueenScheduler then
            self.RedQueenScheduler:Stop()
        end
        if self.RedQueenModules and self.RedQueenModules.Team then
            self.RedQueenModules.Team:Destroy()
        end
    end,

    OnVictory = function(self)
        self:RedQueenCleanup()
        AdaptiveBrain.OnVictory(self)
    end,

    OnDraw = function(self)
        self:RedQueenCleanup()
        AdaptiveBrain.OnDraw(self)
    end,

    OnDefeat = function(self)
        self:RedQueenCleanup()
        AdaptiveBrain.OnDefeat(self)
    end,

    OnDestroy = function(self)
        self:RedQueenCleanup()
        AdaptiveBrain.OnDestroy(self)
    end,
}
