local Constants = import("/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua")
local Logger = import("/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua")
local Experimentals = import("/mods/TheRedQueen/lua/AI/RedQueen/Experimentals.lua")

---@class RedQueenDiagnostics
Diagnostics = ClassSimple {
    __init = function(self, brain, modules)
        self.Brain = brain
        self.Modules = modules
        self.StagnationMark = nil
        self.StagnationGrowthMark = nil
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
        -- Nothing meaningful to say about a plateau before the opening is over,
        -- and the opening is exactly when a commander clearing rocks produces
        -- the largest and least representative income of the match.
        if (economy.GameTimeSeconds or 0) < Constants.Policy.OpeningDurationSeconds then
            self.StagnationMark = nil
            self.StagnationGrowthMark = nil
            self.StagnationTick = nil
            return
        end
        -- The mark decays toward current income. Reclaim is counted as income,
        -- so an opening burst of rock clearing spikes it by an order of
        -- magnitude for a moment -- one run reported "declining mass=3.0
        -- peak=48.9" a minute into a perfectly healthy start. Smoothing alone
        -- damps the spike but an all-time high-water mark still keeps it
        -- forever, so let it fade instead.
        self.StagnationMark = math.max(
            income,
            (self.StagnationMark or income) * Constants.Policy.EconomyMarkDecay
        )
        -- Decay only changes the reported peak. Growth must exceed an actual
        -- income sample, otherwise decay alone restarts the window on plateaus.
        if not self.StagnationGrowthMark
            or income > self.StagnationGrowthMark * Constants.Policy.EconomyGrowthRatio
        then
            self.StagnationGrowthMark = income
            self.StagnationTick = tick
            return
        end
        -- A decline establishes a lower reference without delaying its report.
        -- Recovery can then count as growth even below a past reclaim spike.
        self.StagnationGrowthMark = math.min(self.StagnationGrowthMark, income)

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

        -- What Red Queen's own classification would field right now, so its
        -- endgame decisions are attributable.
        --
        -- FAF's native builders also produce experimentals, and the engine's
        -- end-of-match stats cannot tell them apart from ours: a match reported
        -- one Monkeylord built while Red Queen's own experimental weight never
        -- reached its threshold, and `slots` stood at 5 purely from work already
        -- in flight. Without this field a run cannot answer whether the
        -- classification chose anything at all.
        local choice = "none"
        local context = self.Brain.RedQueenContext
        local faction = context and context.FactionIndex
        local world = self.Modules.World
        if faction and world then
            local entry = Experimentals.SelectForRole(
                    world, faction, Experimentals.Roles.Assault, world.StartPosition)
                or Experimentals.SelectForRole(
                    world, faction, Experimentals.Roles.Siege, world.StartPosition)
            if entry then
                choice = entry.Role .. ":" .. entry.Blueprint
            end
        end
        local owned = self.Brain.GetCurrentUnits
            and self.Brain:GetCurrentUnits(categories.EXPERIMENTAL)
            or 0
        -- Engineers held against the target, and how many were lost recently.
        -- An engineer shortfall suppresses income and production at once, so
        -- the three numbers together are what make a flatline diagnosable.
        local engineers = self.Brain.GetCurrentUnits
            and self.Brain:GetCurrentUnits(categories.ENGINEER * categories.MOBILE)
            or 0

        Logger.Info(self.Brain, string.format(
            "state objective=%s eco=%s mass=%.1f energy=%.1f factories=%d/%d intel=%d doctrine=%s focus=%s weights=A=%d,T2=%d,T3=%d,X=%d,N=%d ready=%.2f slots=%d reason=%s landloss=%d/%.0f airloss=%d/%.0f airdrop=%s alert=%s/%.1f/%.2f momentum=%.0f/%.0f/%s tiers=L%d,A%d,N%d forward=%d/%s/%s exp=%s/%d/%d eng=%d/%d/%d cover=%d/%d engpolicy=%d/%d mex=%d/%d scout=%d/%d/%d scoutorders=%d/%d scouts=%d scoutfraction=%.3f",
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
                or "none"),
            choice,
            owned,
            demand.DesiredExperimentals or 0,
            engineers,
            demand.DesiredEngineers or 0,
            (demand.EngineerLossPressure or {}).Count or 0,
            -- Forward-base cover, and where native engineer production is being
            -- cut. Both were previously inferable only indirectly: a garrison
            -- filter that stood down for 86% of bases and a suppression ceiling
            -- that pinned the army to 3 engineers each survived a full matrix
            -- because neither appeared in a log.
            (modules.Combat and modules.Combat.GarrisonSummary or {}).Sites or 0,
            (modules.Combat and modules.Combat.GarrisonSummary or {}).Units or 0,
            (modules.Production.EngineerPolicy or {}).Suppressed or 0,
            (modules.Production.EngineerPolicy or {}).Ceiling or 0,
            -- Extractors held against mass points on the map. The cheapest
            -- economy in the game is an unclaimed point, so this is the figure
            -- that says whether there is room to expand into.
            self.Brain.GetCurrentUnits
                and self.Brain:GetCurrentUnits(
                    categories.STRUCTURE * categories.MASSEXTRACTION)
                or 0,
            world and world.MassPointCount or 0,
            -- Positions the army wants observed, how many it cannot see, and
            -- how many scouts it dispatched this pass. Red Queen's intel comes
            -- only from sampling its own units, so "blind" here is the share of
            -- what it cares about that nothing is looking at -- the figure the
            -- commitment gate silently depends on.
            (modules.Combat and modules.Combat.ScoutSummary or {}).Targets or 0,
            (modules.Combat and modules.Combat.ScoutSummary or {}).Blind or 0,
            (modules.Combat and modules.Combat.ScoutSummary or {}).Sent or 0,
            -- Cumulative orders, split by actual scout versus combat fallback.
            -- Sent above is only the latest combat pass, not a match total.
            (modules.Combat and modules.Combat.ScoutSummary or {}).ScoutOrders or 0,
            (modules.Combat and modules.Combat.ScoutSummary or {}).FallbackOrders or 0,
            self.Brain.GetCurrentUnits
                and self.Brain:GetCurrentUnits(categories.MOBILE * categories.SCOUT)
                or 0,
            demand.Scouts or 0
        ))
    end,
}

function Create(brain, modules)
    return Diagnostics(brain, modules)
end
