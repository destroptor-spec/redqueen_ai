local Constants = import("/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua")

---@class RedQueenEconomyManager
EconomyManager = ClassSimple {
    __init = function(self, brain, context)
        self.Brain = brain
        self.Context = context
        self.State = {
            Mode = "Opening",
            MassIncome = 0,
            EnergyIncome = 0,
            MassTrend = 0,
            EnergyTrend = 0,
            MassStoredRatio = 0,
            EnergyStoredRatio = 0,
            MassRequested = 0,
            EnergyRequested = 0,
            StallRisk = false,
            Surplus = false,
            DesiredFactories = 1,
            GameTimeSeconds = 0,
        }
    end,

    Update = function(self)
        local brain = self.Brain
        local state = self.State

        state.MassIncome = brain:GetEconomyIncome("MASS") or 0
        state.EnergyIncome = brain:GetEconomyIncome("ENERGY") or 0
        state.MassTrend = brain:GetEconomyTrend("MASS") or 0
        state.EnergyTrend = brain:GetEconomyTrend("ENERGY") or 0
        state.MassStoredRatio = brain:GetEconomyStoredRatio("MASS") or 0
        state.EnergyStoredRatio = brain:GetEconomyStoredRatio("ENERGY") or 0
        state.MassRequested = brain:GetEconomyRequested("MASS") or 0
        state.EnergyRequested = brain:GetEconomyRequested("ENERGY") or 0
        state.GameTimeSeconds = GetGameTimeSeconds()

        state.StallRisk = (state.EnergyStoredRatio < 0.03 and state.EnergyTrend < 0)
            or (state.MassStoredRatio < 0.02 and state.MassTrend < 0)
        state.Surplus = state.MassStoredRatio > 0.70
            and state.EnergyStoredRatio > 0.80
            and state.MassTrend >= 0
            and state.EnergyTrend >= 0

        if state.StallRisk then
            state.Mode = "Recover"
        elseif state.GameTimeSeconds < Constants.Policy.OpeningDurationSeconds then
            state.Mode = "Opening"
        elseif state.Surplus then
            state.Mode = "ExpandProduction"
        else
            state.Mode = "Balanced"
        end

        local incomeFactories = math.floor(state.MassIncome / 8)
        state.DesiredFactories = math.max(1, math.min(24, 1 + incomeFactories + self.Context.ArmyDeficit))
    end,

    CanCommitAttack = function(self)
        -- Existing combat units should never be held back by an economic or
        -- elapsed-time gate. The combat manager still requires a viable wave.
        return true
    end,

    CanExpandProduction = function(self, factoryCount)
        local state = self.State
        return self.Context.ArmyDeficit > 0
            and state.Mode == "ExpandProduction"
            and state.MassIncome >= Constants.Policy.MinimumProductionMassIncome
            and factoryCount < state.DesiredFactories
    end,

    HasResourceSurplus = function(self)
        local state = self.State
        return state.GameTimeSeconds >= Constants.Policy.OpeningDurationSeconds
            and state.Surplus
    end,
}

function Create(brain, context)
    return EconomyManager(brain, context)
end
