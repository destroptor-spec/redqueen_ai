ModPath = "/mods/TheRedQueen"
Version = "V9"
PersonalityKey = "redqueen"
LogPrefix = "[RedQueen]"

Ticks = {
    IncomeSweep = 100,
    Economy = 10,
    Intel = 20,
    World = 300,
    Strategy = 40,
    Production = 50,
    Combat = 30,
    Team = 100,
    Ping = 20,
}

-- Economy income policy values are expressed in resources per game tick, the
-- unit returned by GetEconomyIncome. Divide a mass-per-second figure by ten.
Policy = {
    -- How near a start an observed enemy structure must be to resolve it as
    -- that enemy's base. Only consulted when the lobby hid the spawns.
    EnemyBaseDiscoveryRadius = 60,
    -- How close a start marker must be to a friendly spawn to count as that
    -- army's own. Absorbs any rounding between GetArmyStartPos and the marker,
    -- and sits far below the distance between two starts on any map.
    FriendlySpawnMatchRadius = 12,
    ObservationRadius = 48,
    ObserversPerUpdate = 16,
    IntelLifetimeSeconds = 180,
    FreshCombatIntelSeconds = 30,
    ArmyClusterMinimumRadius = 45,
    ArmyClusterMaximumRadius = 90,
    ArmyClusterMapDivisor = 12,
    ArmyApproachDistance = 10,
    ArmyClosingThreatFraction = 0.25,
    PingLifetimeSeconds = 90,
    ExpansionClaimSeconds = 180,
    AttackProposalSeconds = 60,
    ResourceTransferCooldownSeconds = 45,
    ResourceSurplusRatio = 0.85,
    AllyDistressRatio = 0.25,
    ResourceTransferFraction = 0.10,
    OpeningDurationSeconds = 240,
    -- Per tick, like every income figure here: 0.8 is 8 mass per second, about
    -- four Tech 1 extractors. Written as 8 this read as the per-second figure
    -- and gated production expansion behind 80 mass per second, which no early
    -- economy reaches, so Red Queen's own expansion never ran.
    MinimumProductionMassIncome = 0.8,
    -- One factory per 8 mass per second. A Tech 1 factory building continuously
    -- draws roughly 5 to 10, so the target tracks what the economy can actually
    -- feed instead of throttling it.
    MassIncomePerFactory = 0.8,
    MinimumAttackUnits = 3,
    MaximumTaskForceUnits = 60,
    AttackReserveFraction = 0.10,
    -- Offensive commitment is tactical, never economic. A wave must carry this
    -- multiple of the observed enemy threat at its destination before it goes.
    CommitmentThreatRatio = 1.10,
    -- How the army divides between what we are doing to them and what we are
    -- protecting. The ceiling rises with the secondary objective's weight, so
    -- the lightest reaction may claim a fifth of the army and the heaviest may
    -- claim three fifths -- never all of it, because an alert that strips the
    -- attack is the failure this split exists to remove.
    -- How much health the commander must have lost before an alert anchored on
    -- it counts as an emergency. Proximity is not danger: the ACU stands in the
    -- main base, so every attack on the base anchors there.
    -- What survives of tier and project investment while the base is threatened.
    -- A poor army keeps the floor; wealth lifts it, and so does being out-teched.
    -- Upgrading the extractors at the spawn is the cheapest income available to
    -- an army that cannot take more ground: no new territory to hold, no
    -- escort, no route. One at a time, because upgrading several takes them all
    -- offline at once and stalls the mass that pays for the next.
    -- When upgrading is affordable rather than a trade.
    --
    -- A new Tech 1 extractor is 36 mass for +2/s, an eighteen-second payback;
    -- a Tech 2 upgrade is roughly 900 for +4/s. While there are points left to
    -- claim, breadth is strictly the better buy, and an upgrade started early
    -- takes the engineers that would have claimed them -- measured: the opening
    -- reached 15 extractors by the eighth sample instead of 18, and 5 by the
    -- third instead of 10. So upgrade only when the economy can fund it without
    -- compromise, or when the map is being lost and breadth is no longer on
    -- offer.
    CoreExtractorUpgradeMinimumMassIncome = 10,
    CoreExtractorDeclineFraction = 0.75,
    -- Whether Red Queen takes combat units off native platoon formation.
    --
    -- It does command the army once this is on -- owned minus pooled falls to
    -- zero and dispatch rises sharply -- and it still loses, because removing
    -- native's formations removed the only thing organising the army and put
    -- nothing in its place. On land maps Red Queen then accumulates 150 to 250
    -- units and feeds them in as individual aggressive-moves: 250 owned, 42
    -- commandable, 231 under stale orders, K/L 0.32.
    --
    -- Measured directly. Five cells run with this on and off, everything else
    -- identical: Sentry Point seed 31337 and Sludge seed 2071971 are victories
    -- with it off and defeats with it on; the other three lose either way.
    --
    -- Off until there is something to form waves with. The census it feeds
    -- stays on regardless -- that is pure observation and cost nothing.
    -- A wave gathers before it commits, and commits as one.
    --
    -- Measured: with 250 units owned and a 30-second order hold, each pass saw
    -- only the four to thirteen units whose holds had just expired and sent
    -- them at the objective alone, so 231 units were strung along the path
    -- arriving in small groups into a defended position.
    --
    -- The rally hold is short so a gathering wave is re-examined often; the
    -- committed hold is the ordinary order lifetime, because a wave in motion
    -- is left alone.
    -- How often a directed platoon re-reads the objective. Matched to the
    -- cadence FAF's own HuntAI uses, which re-targets every seventeen seconds.
    -- Narration to in-game chat, so a spectator can see what Red Queen is
    -- doing without reading a log afterwards. SyncAIChat only appends to the
    -- Sync table the UI drains: no simulation state and no random draw.
    NarrateToChat = true,
    NarrationIntervalSeconds = 8,
    PlatoonDirectionSeconds = 15,
    WaveRallyHoldTicks = 50,
    -- A wave that has lost this share of its strength has done its work or
    -- failed, and is dissolved so the survivors can join the next one.
    WaveSpentFraction = 0.34,
    FormationOwnership = false,
    CoreExtractorRadius = 45,
    CoreExtractorUpgradeEngineers = 4,
    CoreExtractorAssistSeconds = 30,
    BaseDangerMinimumTierRetention = 0.35,
    OuttechedTierRelief = 0.75,
    CommanderEmergencyHealthFraction = 0.75,
    MinimumSecondaryCeiling = 0.20,
    MaximumSecondaryFraction = 0.60,
    MinimumPressureFraction = 0.25,
    CommitmentThreatRadius = 60,
    CommitmentDiagnosticSeconds = 30,
    -- Scouting. Coverage at or above this counts as seen, so the army stops
    -- sending scouts to places it can already watch and moves on to the ones it
    -- cannot -- adaptive by construction rather than a fixed patrol.
    ScoutCoverageSatisfied = 0.50,
    -- How long a scout keeps its assignment before it is reconsidered. Short,
    -- because the value of a scouting order decays as the picture changes.
    ScoutOrderSeconds = 30,
    -- Scout production, as a share of the army. The floor keeps a trickle
    -- coming so the picture never goes completely stale; the ceiling is what an
    -- army that can see nothing it cares about will spend. Both are shares of
    -- production and neither is a hard limit on looking -- the fraction moves
    -- with coverage every cycle.
    -- Only a target this important justifies sending an ordinary combat unit
    -- to look when no scout is free. The objective destination carries weight
    -- 3, enemy starts 2, mass clusters 1 -- so this buys eyes on the number the
    -- commitment gate reads and nothing more speculative.
    ScoutFallbackMinimumWeight = 3,
    ScoutFractionMinimum = 0.05,
    ScoutFractionMaximum = 0.18,
    -- Blind share says how much the army cannot see. It cannot say whether
    -- another scout would change that. On a 10 km map coverage decays faster
    -- than any affordable number of scouts can refresh it, so a rule keyed on
    -- blindness alone pins production at its ceiling for the whole match: eight
    -- LandLarge cells measured 55-67% blind with the requested fraction never
    -- returning to its floor, against 15-31% and a floor of 0.05 on 5 km maps,
    -- while Syrtis issued 86 to 175 scout orders and blind did not move.
    --
    -- These bound a probe on the ceiling: it steps down while scouts are alive
    -- and blindness is not improving, and is released to the maximum the moment
    -- either stops being true. Scouts dying is a reason to keep paying, because
    -- the shortfall is replacement rather than saturation.
    ScoutSaturationWindowSeconds = 30,
    ScoutSaturationImprovement = 0.05,
    ScoutSaturationStep = 0.02,
    UnitOrderLifetimeTicks = 300,
    ObjectiveLifetimeTicks = 300,
    ObjectiveInterruptPriorityGap = 15,
    FactoryCheckCooldownSeconds = 30,
    -- How long an engineer given a factory build order is protected from being
    -- reassigned to assist or to a forward base. Long enough to walk to the
    -- site and lay the foundation.
    ProductionBuildHoldSeconds = 60,
    FactoryCapDiagnosticSeconds = 60,
    MaximumManagedBases = 8,
    FactoryAssistMassPerEngineer = 1.0,
    MaximumFactoryAssistants = 6,
    FactoryAssistSeconds = 30,
    EmergencyDefenseCooldownSeconds = 5,
    EmergencyDefenseEngineerHoldSeconds = 10,
    EmergencyDefenseLogCooldownSeconds = 30,
    EmergencyDefenseRadius = 60,
    -- Artillery is sited away from the threat, not beside it. T2 artillery has
    -- a 50 minimum radius and a 115 maximum: that minimum is a dead zone around
    -- the gun itself, so pushing the gun back from the threatened edge widens
    -- what it covers rather than blinding it. A 25 offset puts attackers from
    -- roughly 30 to 90 out inside the band, which is where a besieging army or
    -- a bombarding fleet actually sits.
    ShoreArtilleryRearOffset = 25,
    ShoreArtilleryRadius = 90,
    ShoreArtilleryMinimumMassIncome = 1.5,
    -- Torpedo launchers are water-only structures: FAF gives them
    -- BuildOnLayerCaps LAYER_Land = false and a 1.5 minimum water depth. The
    -- anchor itself is usually dry, so a water cell near it has to be found
    -- before one can be sited at all. Probed at fixed radii so the result is
    -- deterministic.
    ShoreTorpedoMinimumDepth = 2.0,
    ShoreTorpedoProbeRadius = 48,
    ShoreTorpedoRadius = 60,
    -- Torpedo launchers answer ships we have actually seen. A Tech 1 frigate
    -- carries SurfaceThreatLevel 6 and a Tech 2 destroyer 14 to 23, and
    -- observation confidence decays to zero as a contact goes stale, so this
    -- is "at least one frigate currently observed" -- not a faded blip, and
    -- never an inference from surface threat near a water anchor.
    TorpedoMinimumObservedNavalThreat = 6,
    -- Naval demand is terrain-derived: 0.55 on a Naval map, 0.30 on Mixed,
    -- 0.05 on Land. Gating first-tier naval production at 0.30 covers every map
    -- with meaningful water and leaves dry maps untouched.
    NavalDominanceMinimumDemand = 0.30,
    -- Above this shortfall a Tech 3 generator (250 a tick for 57600 energy) is
    -- worth it; below it, Tech 2 generators (50 a tick for 12000) close the gap
    -- far more cheaply. Three Tech 2 generators cover 150.
    LargeEnergyDeficit = 150,
    -- Holding lower-tier production alive through an upgrade is a volume
    -- strategy, and volume only pays where there is room and time to use it.
    -- Measured Aeon vs Cybran at equal income: on 5 km Sentry Point it turned a
    -- victory (K/L 0.96) into a defeat (0.67), while on 10 km maps it helped --
    -- Fields of Isis 0.27 to 0.41 with Tech 3 units going from 3 to 20, and
    -- Syrtis Major 0.55 to 0.84. Small maps are decided by army quality before
    -- the extra volume can be brought to bear.
    -- Where a dry map stops being decided before volume can be brought to
    -- bear. Sentry Point at 5 km is settled by army quality; Fields of Isis and
    -- Syrtis Major at 10 km run long enough for production and tech to matter.
    LargeMapKilometers = 10,
    EconomyStagnationSeconds = 180,
    EconomyGrowthRatio = 1.05,
    -- Per diagnostic sample. Over the 180s stagnation window this lets a
    -- transient income spike fade rather than define the baseline forever.
    EconomyMarkDecay = 0.97,
    LandLossWindowSeconds = 120,
    LandLossCountThreshold = 8,
    LandLossMassThreshold = 450,
    AirLossWindowSeconds = 120,
    -- Engineers are infrastructure, not casualties to absorb. Losing them
    -- stalls expansion, economy and production at once, so their loss is
    -- tracked in its own window and answered by building more.
    EngineerLossWindowSeconds = 120,
    AirLossCountThreshold = 8,
    AirLossMassThreshold = 450,
    GunshipRecoverySeconds = 120,
    CounterDoctrineSeconds = 180,
    GunshipAirThreatRatio = 0.40,
    AirDropTargetRadius = 45,
    AirDropMaximumAirThreat = 6,
    AirDropRequestCooldownSeconds = 90,
    AirDropDiagnosticSeconds = 30,
    MaximumAirDropTransports = 2,
    -- Airdrop allowance plus a ferry reserve. A first calibration against an
    -- observed fleet of 30 that produced no kills; the transport budget
    -- diagnostic reports when it engages so it can be tuned from evidence.
    MaximumTransports = 10,
    Tech2MinimumMassIncome = 4,
    Tech2MinimumEnergyIncome = 60,
    Tech3MinimumMassIncome = 10,
    Tech3MinimumEnergyIncome = 250,
    ExperimentalMinimumMassIncome = 22,
    ExperimentalMinimumEnergyIncome = 800,
    -- Late-game experimental volume is a *flow*, not a stock: one or two should
    -- always be in production once the economy carries them.
    --
    -- A stock target is the wrong brake in both directions. It over-commits
    -- while the count is low -- three concurrent projects at 20000 to 48000 mass
    -- each, started exactly when the AI is under pressure, cost Aeon all three
    -- of its measured comparisons -- and then stops production entirely once the
    -- count is met. Concurrency is the brake instead, and nothing caps how many
    -- may be owned over a match.
    --
    -- The second slot is what lets a game-ender or a utility experimental be
    -- built alongside the on-grid force rather than behind it, so it opens only
    -- when income can carry two at once.
    ExperimentalConcurrentMaximum = 2,
    ExperimentalSecondProjectMassIncome = 40,
    -- A Paragon is 250200 mass and a Novax 32000: worth starting only when the
    -- economy would otherwise be idling, well past the combat gate of 22.
    ExperimentalUtilityMassIncome = 45,
    -- A carrier that cannot engage a ground target is only worth its mass next
    -- to a force it can escort; below this it is a 12000-mass idle asset.
    ExperimentalEscortMinimumFleet = 4,
    NukeMinimumMassIncome = 30,
    NukeMinimumEnergyIncome = 1200,
    LocalDefenseThreat = 25,
    MassiveArmyThreat = 40,
    MassiveArmyThreatRatio = 1.25,
    CommanderEmergencyThreat = 20,
    CommanderEmergencyThreatRatio = 0.75,
    CommanderEmergencyDistance = 100,
    CommanderAssassinationCriticality = 3.00,
    CommanderAnnihilationCriticality = 2.00,
    CommanderSupremacyCriticality = 1.50,
    MainBaseCriticality = 1.40,
    ExpansionCriticality = 1.00,
    NavalBaseCriticality = 1.00,
    ForwardBaseCriticality = 1.15,
    AnchorProximityTolerance = 16,
    PressureEscalationThreat = 30,
    CombatMomentumWindowSeconds = 120,
    CombatMomentumLossRatio = 1.25,
    CombatMomentumMassDifference = 300,
    DefenseAlertHoldSeconds = 30,
    ForwardBaseMinimumDistance = 80,
    ForwardBaseSiteRadius = 60,
    ForwardBaseSafetyRatio = 0.60,
    ForwardBaseCooldownSeconds = 120,
    ForwardBaseMapKilometersPerBase = 10,
    MaximumForwardBases = 3,
    -- Summed observation confidence at which a sampled point counts as fully
    -- known. One fresh sighting is enough, and confidence decays with age, so
    -- stale intel yields partial coverage.
    --
    -- Coverage is measured and reported but deliberately does NOT gate route
    -- safety. Charging an uncovered route a presumed threat was tried and
    -- measured on Seton's Clutch: it cost the 2v2v2 a start and dropped peak
    -- mass income from 11.5 to 6.7 while establishing no more bases, and the
    -- 3v3 was insensitive to it. The engineers that die are not dying blind --
    -- they are lost at coverage 1.00 on routes assessed safe by a wide margin,
    -- 75 to 175 seconds into the walk. The problem is a stale assessment, not
    -- an absent one, so braking on uncertainty only expands less for the same
    -- losses. See docs/large-map-expansion-investigation.md.
    RouteCoverageConfidenceForFull = 1.0,
    -- Engineer establishment, treated like factory capacity rather than left
    -- to a fixed floor. FAF's own rule is a static "four at this location",
    -- which cannot tell a quiet base from one bleeding engineers.
    --
    -- Target = a base need that scales with the production it has to feed,
    -- plus the expansion in flight, plus a replacement buffer while losses are
    -- recent. The buffer is what stops a flatline: an engineer lost is an
    -- engineer queued, and while losses keep arriving the AI deliberately
    -- overbuilds so the next one costs it no tempo.
    EngineersPerFactory = 0.75,
    EngineersMinimum = 2,
    -- What the opening actually needs, as distinct from what the factories do.
    --
    -- The structural target is derived from factory count, so the first factory
    -- asks for 0.75 of an engineer and the opening ran on two or three. But the
    -- opening's job is claiming mass points, and every point is an engineer
    -- trip: the first factory completing is the cue to build ten to fifteen
    -- engineers and spread them across the map. Red Queen peaked at 18 of 44
    -- points and never reached more.
    EngineersExpansionFloor = 12,
    -- While fewer than this share of the map's points are held, there is still
    -- breadth worth claiming and the floor applies.
    ExpansionClaimedShare = 0.5,
    EngineersMaximum = 18,
    -- Where native engineer production is *cut*, which is not the same number
    -- as the target Red Queen builds toward.
    --
    -- Conflating the two strangled the economy. `DesiredEngineers` is derived
    -- from factory count, and holding native production to it made engineers
    -- the binding constraint on building factories -- a loop that locks an army
    -- at its opening size. Measured on Crossfire Canal across two factions and
    -- two seeds: engineers tracked the target exactly (3/3, 9/8, 12/12) where
    -- the same cells previously ran 15-33, and the army finished with 6
    -- factories instead of 26 and a peak mass income of 89-128 instead of
    -- 309-347. Both cells lost by more than the harness's divergence band.
    --
    -- So the target stays a floor for Red Queen's own builders, and suppression
    -- gets its own ceiling that scales with what there is to feed: natives run
    -- freely through the opening and are trimmed only once they are wasteful.
    -- At the 26-factory economy above this cuts at 39 rather than the observed
    -- 101 runaway, which is what the policy was introduced to stop.
    EngineerSuppressionPerFactory = 1.5,
    -- Below this many engineers nothing is ever cut, whatever the factory
    -- count. Reusing the target's own maximum (18) as the floor put the cut
    -- exactly where armies naturally sit early, when factories are few and the
    -- per-factory term is small -- and the strangulation came straight back.
    -- Sentry Point held exactly 18 engineers against a natural 53, and its
    -- income fell from 32.2 to 7.3 and its factories from 16 to 9; Seton's
    -- Cybran bound the same way and turned a victory into a defeat, its
    -- experimental weight never crossing the threshold once income dropped.
    --
    -- Native engineer counts measured across ten baseline cells: 24, 35, 44,
    -- 51, 53, 55, 56, 63, 66, 101. Every one of those is an army that was not
    -- in trouble for having them, and only the last is the runaway this policy
    -- exists to cut. So the floor sits above the pack and below the outlier:
    -- nothing binds at ordinary counts, and 101 is still halved.
    EngineerSuppressionMinimum = 45,
    EngineersPerForwardBase = 2,
    -- Replacements queued per engineer lost in the window. Above 1 the AI
    -- overbuilds while under pressure, which is the point.
    EngineerLossReplacementFactor = 1.5,
    -- A route is re-judged this often while an engineer walks to a site, and a
    -- recall needs the danger to exceed the limit by this much -- a walk of 75
    -- to 175 seconds against a 180-second intel lifetime cannot be authorised
    -- once and left, but neither should it thrash on noise.
    ForwardBaseRouteRecheckSeconds = 20,
    ForwardBaseRecallThreatRatio = 1.5,
    ForwardBaseMinimumMassIncome = 4,
    ForwardBaseMinimumEnergyIncome = 40,
    ForwardBaseGarrisonSeconds = 60,
    -- Engineer survival. Native engineer travel accepts a destination whose
    -- threat-constrained path failed, so Red Queen judges the danger itself.
    --
    -- The floor is what makes the test usable by a lone engineer: scaling only
    -- with nearby friendly strength yields a limit of zero on an unescorted
    -- walk, refusing a destination because a scout was seen near it. Observed
    -- scale: a route threat of 0.6 was harmless; 70.5 killed the engineer that
    -- walked it. A first estimate between those, to be calibrated.
    EngineerSurvivalThreatFloor = 8,
    -- Anything this close to our own start is home construction and is never
    -- refused, so an army under attack can still repair and rebuild itself.
    EngineerSurvivalHomeRadius = 80,
    -- Where an engineer died, remembered so the replacement is not posted to
    -- the same spot. Expires, because a place dangerous once is not dangerous
    -- forever, and a permanent exclusion would concede map control.
    EngineerLethalSiteMemorySeconds = 180,
    EngineerLethalSiteRadius = 40,
    -- The commander is leashed harder than an engineer, and on distance rather
    -- than observed threat: it is the asset that ends the game, and unobserved
    -- ground is exactly where it dies. Observed wandering alone to the centre of
    -- the map, which no threat reading would have refused because nothing had
    -- been seen there yet. Generous enough to build a nearby expansion, far
    -- short of the middle of a 10 km map.
    CommanderLeashRadius = 120,
    -- How long the commander holds an assist order before it is reconsidered.
    CommanderAssistSeconds = 45,
    -- Where engineer replacement stops outranking the army.
    --
    -- Below the Tech 2 mainline at 930 and the Tech 2 factory tech builder at
    -- 920, so replacing losses never silences combat production. The shared
    -- replacement function previously reached 930 after four engineer deaths
    -- and 1000 after eight, in every factory at every tier.
    EngineerReplacementPriorityCeiling = 910,
    -- Except in construction recovery: an army with almost no engineers cannot
    -- rebuild anything at all, so that case lifts the cap outright.
    EngineerRecoveryFloor = 3,
    -- When cover is given up rather than reinforced. Losses are counted in
    -- their own window so a site that killed an escort ten minutes ago is not
    -- held against the next attempt, and the fraction is of everything
    -- committed there -- so losing half of what was sent is a withdrawal, not
    -- an invitation to send the other half after it.
    GarrisonLossWindowSeconds = 60,
    GarrisonLossFraction = 0.5,
    -- Cover is a portion of the force, and the portion is the whole point.
    --
    -- The counts these replace (4, or 6/10 at an undefended site) were sized
    -- when only Tech 3 units were eligible, so they drew from a small pool.
    -- Widening eligibility to the whole land army left them in place, and on a
    -- small army ten units is most of it. Measured across 21 cells: where cover
    -- committed six or more units, mass kill/loss fell by 0.30 and peak income
    -- by 19.7 against the same cells' baseline; below six units the same
    -- figures were -0.11 and +4.1. The heaviest cell committed 14 and lost 0.74
    -- kill/loss and 35 income.
    --
    -- The fraction is of the whole eligible force rather than of what happens
    -- to be idle, so committing units to one site does not shrink the next
    -- site's entitlement; the budget caps every site together, so three sites
    -- cannot each take a quarter of the army; and the minimum is a floor on
    -- what may be *sent*, because one unit walking into a contested site is the
    -- piecemeal-commitment mistake the offensive path already refuses.
    -- A defended site keeps a standing portion; one still below its tier
    -- minimum may draw twice that, which is when cover is worth its cost. The
    -- product is the absolute cap on all cover at once, so the army never has
    -- more than 30% of its guns standing on forward bases.
    GarrisonForceFraction = 0.15,
    GarrisonUndefendedMultiple = 2.0,
    GarrisonMinimumUnits = 2,
    GarrisonMaximumUnits = 8,
    ForwardBaseDiagnosticSeconds = 60,
    ForwardBaseRecordRetentionSeconds = 300,
    -- A remote site must be reached before it can be built. Six minutes retired
    -- bases that were alive and defending; this is the absolute deadline, and a
    -- lost engineer or manager still fails immediately.
    ForwardBaseEstablishSeconds = 900,
    -- A base keeps this many engineers before any may be taken for a forward
    -- base, so sourcing one never strips a base of the engineers it needs.
    ForwardBaseSourceMinimumEngineers = 2,
    StrategicFocusMinimumScore = 35,
    StrategicFocusSwitchMargin = 15,
    StrategicFocusDwellSeconds = 90,
    DefenseAlertEndgameTaxPerSeverity = 0.20,
    DefenseAlertMinimumEndgameRetention = 0.35,
    -- Wealth relief on the endgame tax. Winning is the objective, and an army
    -- rich enough to fund a project *and* its defence must never be priced out
    -- of committing -- Crossfire Canal sat on 66 mass income and 3340 energy
    -- with a fully developed Tech 3 economy, saw alert ratios above 1000, and
    -- so held an experimental weight of 20 against a threshold of 35 for the
    -- whole match. It converted that economy into 101 engineers and lost on
    -- attrition instead.
    --
    -- Relief is a multiple of the endgame mass gate, deliberately economic and
    -- never elapsed time: at the gate the severity tax applies in full, and at
    -- this multiple of it the tax is lifted entirely.
    EndgameWealthMultiple = 2.5,
    IncomeSmoothingWeight = 0.25,
    StrategicSecondProjectReadiness = 0.80,
    StrategicSecondProjectArmyMaximum = 70,
    StrategicHighValueThreshold = 80,
    StrategicFortificationThreshold = 40,
}
