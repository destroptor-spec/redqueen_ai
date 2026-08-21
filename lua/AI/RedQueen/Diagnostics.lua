local Logger = import("/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua")

---@class RedQueenDiagnostics
Diagnostics = ClassSimple {
    __init = function(self, brain, modules)
        self.Brain = brain
        self.Modules = modules
    end,

    Update = function(self)
        local modules = self.Modules
        local objective = modules.Strategy.CurrentObjective or {}
        local economy = modules.Economy.State
        local factoryCounts = modules.Production.Counts or { Total = 0, Land = 0, Air = 0, Naval = 0 }
        local observations = table.getsize(modules.Intel.Observations)
        local demand = modules.Strategy.ProductionDemand
        local losses = modules.Strategy.LandLossPressure or { Count = 0, Mass = 0 }
        local airDrop = modules.Strategy.AirDropOpportunity and "yes" or "no"
        local weights = demand.FocusWeights or {}
        local alert = demand.DefenseAlert or { Active = false }
        local momentum = modules.Strategy.CombatMomentum
            or { LostMass = 0, DestroyedMass = 0, Losing = false }
        local tiers = demand.TierPolicy or {}
        local forward = demand.ForwardBasePlan or { Active = false, Sites = {} }

        Logger.Info(self.Brain, string.format(
            "state objective=%s eco=%s mass=%.1f energy=%.1f factories=%d/%d intel=%d doctrine=%s focus=%s weights=A=%d,T2=%d,T3=%d,X=%d,N=%d ready=%.2f slots=%d reason=%s landloss=%d/%.0f airdrop=%s alert=%s/%.1f/%.2f momentum=%.0f/%.0f/%s tiers=L%d,A%d,N%d forward=%d/%s",
            tostring(objective.Type or "none"),
            economy.Mode,
            economy.MassIncome,
            economy.EnergyIncome,
            factoryCounts.Total,
            economy.DesiredFactories,
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
            forward.Active and "building" or "idle"
        ))
    end,
}

function Create(brain, modules)
    return Diagnostics(brain, modules)
end
