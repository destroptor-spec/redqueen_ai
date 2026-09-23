local Constants = import("/mods/TheRedQueen/lua/AI/RedQueen/Constants.lua")
local Logger = import("/mods/TheRedQueen/lua/AI/RedQueen/Logger.lua")
local Experimentals = import("/mods/TheRedQueen/lua/AI/RedQueen/Experimentals.lua")
local Observer = import("/mods/TheRedQueen/lua/AI/RedQueen/Observer.lua")
local CombatTelemetry = import("/mods/TheRedQueen/lua/AI/RedQueen/CombatTelemetry.lua")
local EngineerSurvival = import("/mods/TheRedQueen/lua/AI/RedQueen/EngineerSurvival.lua")
local DefenseCoverage = import("/mods/TheRedQueen/lua/AI/RedQueen/DefenseCoverage.lua")

---@class RedQueenDiagnostics
-- Whether the attack actually received force.
--
-- `Strategy.PressureHeld` says only that the primary slot holds an offensive
-- objective, which since the slots landed is nearly always true and so measures
-- nothing on its own. An attack sent no units while the defence was sent some
-- has yielded the pressure whatever the slot is labelled, and an army with
-- nothing to send is neither holding nor yielding.
function PressureState(strategy, slotDispatch)
    if not strategy.PressureHeld then
        return (slotDispatch.Secondary or 0) > 0 and "yielded" or "idle"
    end
    if (slotDispatch.Primary or 0) > 0 then
        return "held"
    end
    if (slotDispatch.Secondary or 0) > 0 then
        return "yielded"
    end
    return "idle"
end

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
        -- First, so a spectator's view of the match survives a failure in the
        -- state line's formatting -- which carries fifty fields and has raised
        -- before.
        Observer.Report(self.Brain, modules)
        local combatTelemetry = CombatTelemetry.Report(self.Brain, modules)
        local objective = modules.Strategy.CurrentObjective or {}
        -- The two slots, and whether pressure survived whatever else happened.
        -- A win rate cannot tell a defence that cost nothing from one that
        -- emptied the attack, so the split is reported even while the secondary
        -- slot is always empty: `pressure=yielded` is then a count of exactly
        -- how often a defensive trigger takes the whole army today.
        local strategy = modules.Strategy
        local allocation = strategy.ObjectiveAllocation or {}
        local primary = strategy.PrimaryObjective
        local secondary = strategy.SecondaryObjective
        local combat = modules.Combat or {}
        local slotDispatch = combat.SlotDispatch or {}
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

        -- Defaults to "none" for a domain no builder has evaluated yet, so the
        -- field is present from the first sample rather than appearing later.
        local coverage = DefenseCoverage.Report(self.Brain, alert, world)
        local cover, mexLoss, span = coverage.Cover, coverage.Loss, coverage.Span
        local placement = self.Brain.RedQueenPlacement
            or { Attempts = 0, Gated = 0, Open = 0 }
        local survival = EngineerSurvival.Summary(self.Brain)
        local gate = self.Brain.RedQueenTechGate or {}
        gate = {
            Land2 = gate.Land2 or "none", Land3 = gate.Land3 or "none",
            Air2 = gate.Air2 or "none", Air3 = gate.Air3 or "none",
            Naval2 = gate.Naval2 or "none", Naval3 = gate.Naval3 or "none",
        }

        Logger.Info(self.Brain, string.format(
            "state objective=%s primary=%s/%d secondary=%s/%d pressure=%s claim=%.0f/%.0f%s eco=%s mass=%.1f energy=%.1f factories=%d/%d intel=%d doctrine=%s focus=%s weights=A=%d,T2=%d,T3=%d,X=%d,N=%d ready=%.2f slots=%d reason=%s landloss=%d/%.0f airloss=%d/%.0f airdrop=%s alert=%s/%.1f/%.2f/%s/%.0f/%.0f momentum=%.0f/%.0f/%s tiers=L%d,A%d,N%d forward=%d/%s/%s exp=%s/%d/%d eng=%d/%d/%d engtier=%d/%d/%d cover=%d/%d engpolicy=%d/%d mex=%d/%d defcover=%d/%d/%.0f mexloss=%d/%d basespan=%d/%d/%d mexplace=%d/%d/%d engsurvival=%d/%d/%d/%d/%d/%d scout=%d/%d/%d scoutorders=%d/%d scouts=%d scoutfraction=%.3f/%.3f dispatch=L%d,A%d,W%d,M%d,H%d army=%d/%d/%d held=%d/%d/%d directed=%d/%d assist=%d/%d/%d acuassist=%d mexgate=%s/%d techgate=L%s/%s,A%s/%s,N%s/%s",
            tostring(objective.Type or "none"),
            primary and tostring(primary.Type) or "none",
            slotDispatch.Primary or 0,
            secondary and tostring(secondary.Type) or "none",
            slotDispatch.Secondary or 0,
            PressureState(strategy, slotDispatch),
            combat.SecondaryClaimedThreat or 0,
            combat.SecondaryRequiredThreat or 0,
            combat.SecondaryUnmet and "/unmet" or "",
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
            -- Which arm qualified, and the defence each arm actually has.
            -- Alert counts alone cannot say whether a change in them came from
            -- the surface reading, the air reading or the combined one.
            alert.QualifiedArm or "none",
            alert.FriendlySurface or 0,
            alert.FriendlyAir or 0,
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
            -- Split by tier, because a cap filled with Tech 1 engineers used to
            -- mean no Tech 2 engineer was ever built and the total could not
            -- show it.
            self.Brain.GetCurrentUnits and self.Brain:GetCurrentUnits(
                categories.ENGINEER * categories.MOBILE * categories.TECH1) or 0,
            self.Brain.GetCurrentUnits and self.Brain:GetCurrentUnits(
                categories.ENGINEER * categories.MOBILE * categories.TECH2) or 0,
            self.Brain.GetCurrentUnits and self.Brain:GetCurrentUnits(
                categories.ENGINEER * categories.MOBILE * categories.TECH3) or 0,
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
            -- Defences held, defences that can actually reach the alert, and
            -- the distance from the nearest one to it. A base with ten guns
            -- whose nearest is two hundred away from the fighting is not short
            -- of guns, and a count alone cannot tell those apart.
            cover.Total,
            cover.Covering,
            cover.Nearest,
            -- Extractors lost, and how many had any friendly weapon in range of
            -- them when they died.
            mexLoss.Lost,
            mexLoss.Defended,
            -- Registered bases, and extractors inside versus outside every base
            -- radius. Ground outside them is not under-defended: no
            -- fortification builder can be offered it at all.
            span.Bases,
            span.Inside,
            span.Outside,
            -- Native resource placement, and what it would have found with the
            -- engine's threat filter open: attempts / offered at the shipped
            -- limit of 5 / offered at 0. Extractors are the only structure the
            -- engine refuses on contested ground, and for resource builders it
            -- queries the deposits directly, so this is the gate that decides
            -- which point is on offer. The third figure is a counterfactual --
            -- the gated result is the one returned -- so a gap between the last
            -- two is the filter binding, measured without changing a decision.
            placement.Attempts,
            placement.Gated,
            placement.Open,
            -- Why an engineer did not go somewhere, and how much ground is
            -- currently closed to it: refusals by reason (unsafe route, a site
            -- that recently killed one, commander leash), sites recorded from a
            -- loss, sites recorded from a precautionary withdrawal, and the
            -- live unexpired exclusion.
            --
            -- The guard fired in every one of 147 recorded matches and left
            -- exactly two lines saying so. It is the only mechanism standing
            -- between an engineer and an unclaimed mass point, and `mex=` above
            -- peaks under half the map, so these two figures have to be read
            -- together: a refusal that saves an engineer and a refusal that
            -- forfeits the expansion are the same event until they are counted.
            -- Withdrawals are separated from losses because a withdrawal writes
            -- the same exclusion without anything having died.
            survival.RefusedUnsafe,
            survival.RefusedRecentLoss,
            survival.RefusedLeash,
            survival.SitesLost,
            survival.SitesWithdrawn,
            survival.LiveSites,
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
            demand.Scouts or 0,
            -- The ceiling the request is clamped to. Blindness alone cannot say
            -- whether another scout would help, so the ceiling is probed down
            -- while the spend buys nothing; without it in the log a matrix sees
            -- the fraction move and cannot say which half moved it.
            demand.ScoutCeiling or 0,
            -- Units ordered per layer on the last combat pass. The fleet is the
            -- reason this is here: a naval force with no destination receives no
            -- order at all, and an alert count cannot show that -- W staying 0
            -- through a match on a map with water is the symptom.
            (modules.Combat and modules.Combat.DispatchSummary or {}).Land or 0,
            (modules.Combat and modules.Combat.DispatchSummary or {}).Air or 0,
            (modules.Combat and modules.Combat.DispatchSummary or {}).Water or 0,
            (modules.Combat and modules.Combat.DispatchSummary or {}).Amphibious or 0,
            (modules.Combat and modules.Combat.DispatchSummary or {}).Hover or 0
        ,
            -- owned / pooled / available: the gap between the first two is what
            -- native platoon formation holds and Red Queen cannot command.
            (modules.Combat and modules.Combat.PoolCensus or {}).Owned or 0,
            (modules.Combat and modules.Combat.PoolCensus or {}).Pooled or 0,
            (modules.Combat and modules.Combat.PoolCensus or {}).Available or 0,
            (modules.Combat and modules.Combat.PoolCensus or {}).OrderHeld or 0,
            (modules.Combat and modules.Combat.PoolCensus or {}).GarrisonHeld or 0,
            (modules.Combat and modules.Combat.PoolCensus or {}).WaveHeld or 0,
            -- Platoons formed under a Red Queen plan, and how many times one
            -- has been aimed. Zero of the first means the builder never won a
            -- formation; zero of the second means the plan never read an
            -- objective worth pursuing.
            self.Brain.RedQueenDirectedPlatoons or 0,
            self.Brain.RedQueenPlatoonAims or 0,
            (modules.Production.AssistSummary or {}).Active or 0,
            (modules.Production.AssistSummary or {}).Assigned or 0,
            (modules.Production.AssistSummary or {}).Released or 0,
            modules.Production.CommanderAssists or 0,
            (modules.Production.CoreUpgrade or {}).State or "none",
            self.Brain.RedQueenExtractorBlocks or 0,
            -- Which gate is actually holding each domain's tier ladder down,
            -- Tech 2 then Tech 3. Four different refusals -- alert, focus,
            -- mass, energy -- produce the identical outcome of a tier that
            -- does not rise, and land Tech 3 was reached in none of the twelve
            -- logged matches with nothing in the log to say which one shut it.
            -- Without this, each candidate repair reads as "no outcome change"
            -- while the other three still hold the ladder down.
            gate.Land2, gate.Land3,
            gate.Air2, gate.Air3,
            gate.Naval2, gate.Naval3) .. combatTelemetry)
    end,
}

function Create(brain, modules)
    return Diagnostics(brain, modules)
end
