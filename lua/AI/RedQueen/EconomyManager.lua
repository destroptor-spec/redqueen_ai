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
            -- Smoothed income exists so a strategic threshold is crossed by a
            -- trend rather than by a single sample. Army 5 in match 27741743
            -- sat at 21.8 mass against a 22.0 experimental gate and flickered
            -- its whole late game away on that one unit of noise.
            SmoothedMassIncome = 0,
            SmoothedEnergyIncome = 0,
        }
        self.SmoothingSeeded = false
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

        if not self.SmoothingSeeded then
            self.SmoothingSeeded = true
            state.SmoothedMassIncome = state.MassIncome
            state.SmoothedEnergyIncome = state.EnergyIncome
        else
            local weight = Constants.Policy.IncomeSmoothingWeight
            state.SmoothedMassIncome = state.SmoothedMassIncome
                + (state.MassIncome - state.SmoothedMassIncome) * weight
            state.SmoothedEnergyIncome = state.SmoothedEnergyIncome
                + (state.EnergyIncome - state.SmoothedEnergyIncome) * weight
        end

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

        -- Income alone sets the factory target. ArmyDeficit is already paid out
        -- as an income handicap in IncomeBonus, so counting it again here
        -- inflated the target twice for an outnumbered brain and, because the
        -- same number is the production cap, made the cap unpredictable.
        local incomeFactories = math.floor(state.MassIncome / 8)
        state.DesiredFactories = math.max(1, math.min(24, 1 + incomeFactories))
    end,

    CanCommitAttack = function(self)
        -- Existing combat units should never be held back by an economic or
        -- elapsed-time gate. The combat manager still requires a viable wave.
        return true
    end,

    -- Deliberately not gated on ArmyDeficit. A balanced match reports a deficit
    -- of zero, so that gate left Red Queen's own factory expansion switched off
    -- for the entire match and handed every factory decision to the native
    -- builders -- which is how match 27741743 reached 16 factories against a
    -- target of 8 without logging a single expansion of its own.
    CanExpandProduction = function(self, factoryCount)
        local state = self.State
        return state.Mode == "ExpandProduction"
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
