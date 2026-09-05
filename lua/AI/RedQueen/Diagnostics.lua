local Constants = import("/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua")
local Logger = import("/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua")

---@class RedQueenDiagnostics
Diagnostics = ClassSimple {
    __init = function(self, brain, modules)
        self.Brain = brain
        self.Modules = modules
        self.StagnationMark = nil
        self.StagnationTick = nil
        self.LastStagnationLogTick = -100000
    end,

    -- Economic stagnation is invisible in a single state sample. Army 5 of
    -- match 27741743 reported exactly 21.8 mass four samples running and 27.9
    -- three samples before that, on a map with 33 mass clusters, and nothing in
    -- the log named it. This reports the plateau directly.
    -- Compares smoothed income, not the instantaneous sample. A single spike --
    -- a reclaim burst, or several extractors finishing together -- would
    -- otherwise latch the high-water mark and make a genuinely climbing economy
    -- read as stagnant for the rest of the match. The peak is reported so a
    -- real decline is distinguishable from a plateau.
    ReportEconomy = function(self, economy)
        local tick = GetGameTick()
        local income = economy.SmoothedMassIncome or economy.MassIncome or 0
        if not self.StagnationMark
            or income > self.StagnationMark * Constants.Policy.EconomyGrowthRatio
        then
            self.StagnationMark = income
            self.StagnationTick = tick
            return
        end

        local window = Constants.Policy.EconomyStagnationSeconds * 10
        if tick - (self.StagnationTick or tick) < window then
            return
        end
        if tick - self.LastStagnationLogTick < window then
            return
        end
        self.LastStagnationLogTick = tick
        Logger.Info(self.Brain, string.format(
            "economy %s mass=%.1f peak=%.1f since=%.0fs mode=%s",
            income < self.StagnationMark and "declining" or "stagnant",
            income,
            self.StagnationMark,
            (tick - self.StagnationTick) / 10,
            tostring(economy.Mode)
        ))
    end,

    Update = function(self)
        local modules = self.Modules
        local objective = modules.Strategy.CurrentObjective or {}
        local economy = modules.Economy.State
        local factoryCounts = modules.Production.Counts or { Total = 0, Land = 0, Air = 0, Naval = 0 }
        local observations = table.getsize(modules.Intel.Observations)
        local demand = modules.Strategy.ProductionDemand
        local losses = modules.Strategy.LandLossPressure or { Count = 0, Mass = 0 }
        local airLosses = modules.Strategy.AirLossPressure or { Count = 0, Mass = 0 }
        local airDrop = modules.Strategy.AirDropStatus
            and modules.Strategy.AirDropStatus.State
            or modules.Strategy.AirDropOpportunity and "Opportunity"
            or "None"
        local weights = demand.FocusWeights or {}
        local alert = demand.DefenseAlert or { Active = false }
        local momentum = modules.Strategy.CombatMomentum
            or { LostMass = 0, DestroyedMass = 0, Losing = false }
        local tiers = demand.TierPolicy or {}
        local forward = demand.ForwardBasePlan or { Active = false, Sites = {} }
        self:ReportEconomy(economy)

        Logger.Info(self.Brain, string.format(
            "state objective=%s eco=%s mass=%.1f energy=%.1f factories=%d/%d intel=%d doctrine=%s focus=%s weights=A=%d,T2=%d,T3=%d,X=%d,N=%d ready=%.2f slots=%d reason=%s landloss=%d/%.0f airloss=%d/%.0f airdrop=%s alert=%s/%.1f/%.2f momentum=%.0f/%.0f/%s tiers=L%d,A%d,N%d forward=%d/%s/%s",
            tostring(objective.Type or "none"),
            economy.Mode,
            economy.MassIncome,
            economy.EnergyIncome,
            factoryCounts.Total,
            factoryCounts.TargetTotal or economy.DesiredFactories,
            observations,
            demand.Doctrine,
            demand.PrimaryFocus or "Army",
            weights.Army or 0,
            weights.Tech2 or 0,
            weights.Tech3 or 0,
            weights.Experimental or 0,
            weights.Nuke or 0,
            demand.EconomicReadiness or 0,
            demand.MajorProjectSlots or 0,
            demand.FocusReason or "none",
            losses.Count,
            losses.Mass,
            airLosses.Count,
            airLosses.Mass,
            airDrop,
            alert.Active and "yes" or "no",
            alert.Threat or 0,
            alert.Ratio or 0,
            momentum.LostMass,
            momentum.DestroyedMass,
            momentum.Losing and "losing" or "stable",
            tiers.Land and tiers.Land.Highest or 1,
            tiers.Air and tiers.Air.Highest or 1,
            tiers.Naval and tiers.Naval.Highest or 1,
            table.getn(forward.Sites or {}),
            forward.Active and "building" or "idle",
            tostring(forward.BlockReason
                or modules.Production.LastForwardBaseBlockReason
                or "none")
        ))
    end,
}

function Create(brain, modules)
    return Diagnostics(brain, modules)
end
