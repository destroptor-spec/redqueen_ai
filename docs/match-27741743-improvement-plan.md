# Match 27741743 Improvement Plan

## Match Facts

Adaptive `the_drunken_beetles_dance.v0001`, 20km, water 0.51, 33 mass clusters.
Assassination (`demoralization`), unit cap 1000, `ShareUntilDeath`, three human
players against three Red Queen V8 brains (army 4 Aeon, army 5 UEF, army 6
Seraphim). Red Queen lost all three: army 4 at tick 27369 (~46 min), army 6 at
41489 (~69 min), army 5 at 43833 (~73 min).

V8 survived far longer than the V7 match 27692700 (18 and 28 minutes). The
scoreboard shows why that is not yet progress: Red Queen reached the late game
but could not convert it.

| Army | Faction | Mass in | Built | Lost | Killed | Mass K/L |
| --- | --- | --- | --- | --- | --- | --- |
| Wizzim (4) | Aeon | 437k | 287k | 278k | 35k | **0.13** |
| Mavor (5) | UEF | 755k | 519k | 505k | 156k | **0.31** |
| Oum-Uthinaa (6) | Seraphim | 1234k | 870k | 991k | 259k | **0.26** |
| Red Queen total | | 2426k | 1676k | 1774k | 450k | **0.25** |
| Human total | | 3735k | 3092k | 465k | 1443k | **3.10** |

Army 6 was economically competitive — 1.23M mass mined against the humans'
1.43M and 1.50M, peaking at 100 mass income, higher than any human sample. It
still traded at 0.26. **The late-game gap is conversion of mass into effect,
not mass income.** Two of the three brains also had a genuine economy problem,
and all three had broken build plumbing underneath.

Per-category build/lost/kill counts:

| Category | Red Queen | Humans |
| --- | --- | --- |
| Experimental | 4 / 8 / **0** | 5 / 0 / 7 |
| Tech 3 | 669 / 711 / 278 | 986 / 281 / 556 |
| Tech 1 | 925 / 702 / 133 | 637 / 208 / 524 |
| Land | 998 / 1005 / **141** | 620 / 225 / 806 |
| Structures | 812 / 530 / **58** | 772 / 68 / 292 |
| Engineers | 356 / **392** / 83 | 506 / 165 / 326 |
| Transports | 50 / 72 / **0** | 6 / 0 / 66 |

Red Queen built more Tech 1 than Tech 3 in a 73-minute match; the humans built
the inverse. Red Queen lost more engineers than it built. Its 4 experimentals
and 50 transports recorded no kills at all.

## Evidence

### 1. `StartForwardBase` crashes the production task, 52 times

```
warning: [RedQueen][ERROR][army=4] scheduler task 'production' failed:
  aibuildstructures.lua(220): Expected a game object. (Did you call with '.' instead of ':'?)
  [C]: in function `FindPlaceToBuild'
  aibuildstructures.lua(220): in function `AIExecuteBuildStructure'
  productionmanager.lua(1234): in function `StartForwardBase'
```

All 52 failures are this one call. `AIExecuteBuildStructure` forwards its
`closeToBuilder` argument into `aiBrain:FindPlaceToBuild` as the builder-unit
slot. Every FAF caller passes a unit or `nil` there —
`ScenarioPlatoonAI.lua:1416` passes `builder`, `aiutilities.lua:3524` and
`platoon-adaptive-engineer-task.lua:615` pass `eng`, `ScenarioPlatoonAI.lua:1413`
passes `nil`. All three Red Queen call sites
(`ProductionManager.lua:896`, `:951`, `:1234`) pass Lua `false`, which is a
boolean, not userdata, so the engine rejects it.

Consequences, all confirmed in the log:

- **Zero forward bases in 73 minutes.** No `forward base started`,
  `established`, `failed`, `aborted`, or `registration failed` line exists.
  The 188 `forward base blocked` lines are all pre-flight gates.
- **Leaked records.** The crash happens after `table.insert(self.ForwardBases,
  record)`, so a `Preparing` record survives every failure. The diagnostic
  field `forward=%d` is `table.getn(forward.Sites)`: it climbs to `forward=18`
  for army 5 and `forward=19` for army 6. 18 + 19 + 15 = the 52 crashes.
- **Permanently claimed sites.** `self.ForwardBaseClaims[site.Name] = true` is
  set before the crash and never released, which is why `no-safe-site` becomes
  the dominant block reason late (22 occurrences).
- **No cooldown.** `self.LastForwardBaseTick` is only assigned after the build
  loop completes, so the crash path never throttles and retries every
  production tick that clears the gates.
- **`CountViableForwardBases` counts only `Building` and `Established`**, so
  the map cap never engaged against the leak.

### 2. The factory-capacity policy silently disables economy and defense

`ApplyFactoryCapacityPolicy` (`ProductionManager.lua:360`) sets
`builder:SetPriority(0)` on any FAF builder whose *factory* domain has met its
target. `BuilderConstructionDomains` classifies a builder by scanning
`BuildStructures` for the substring `Factory` — but it disables the **whole
builder**, not the factory entry.

FAF's 40 factory-containing builders split cleanly in two. All 20 **pure**
factory builders live in `AIFactoryConstructionBuilders.lua` and
`AINavalBuilders.lua`, and each builds exactly one structure —
`{'T1LandFactory'}`, `{'T1AirFactory'}`, `{'T1SeaFactory'}`. Capping those is
precisely what a factory cap is for.

The other 20 are mixed, and 13 of those are live in a normal match (the 7
inert ones are `PreBuiltBase`-gated and this lobby had `PrebuiltUnits Off`).
Every live one creates an expansion or naval base, with a factory as one late
line item:

- `AIExpansionBuilders.lua` (11 builders, e.g. `T2VacantExpansiongAreaEngineer`):
  `ExpansionBase = true`, `NearMarkerType = 'Expansion Area'`,
  `BuildStructures = {'T1GroundDefense', 'T1Radar', 'T2AADefense',
  'T2GroundDefense', 'T2StrategicMissile', 'T2GroundDefense', 'T1LandFactory',
  'T2ShieldDefense'}` — FAF's own comment on that block reads *"move fac to
  end"*.
- `AINavalBuilders.lua` (2 builders): `{'T1SeaFactory', 'T1AADefense',
  'T1Sonar', 'T1NavalDefense'}` — naval base creation and its defense.

So once the land factory target is met — target 3–8 against an actual 13–16,
so effectively always — Red Queen switches off the builders whose real job is
**taking and holding ground**. This is self-reinforcing: no expansions means
mass income never grows, and `DesiredFactories = 1 + floor(MassIncome / 8)`
keeps the target low, which keeps the builders disabled.

Mutating `BuildStructures` to gate the factory entry alone is not available.
`Builder:Create` copies only `Priority`, `OriginalPriority`, `Brain` and
`BuilderName` onto the per-army instance; `GetBuilderData` re-reads
`Builders[BuilderName].BuilderData` from the global table on every call, so
that table is shared by all six armies in the match and by FAF itself.
`Priority` is per-instance, which is why the existing `SetPriority(0)`
mechanism is correctly scoped — it is simply pointed at the wrong builders.

The log matches exactly. Mass income per state sample:

- Army 5 flatlines and repeats identical values — `27.9, 27.9, 27.9`, then
  `29.1, 29.1, 29.1`, then `21.8, 21.8, 21.8, 21.8`. No growth for the last
  third of its life on a 33-cluster map.
- Army 4 peaks at 30.9 and decays.
- Red Queen mined 2.43M mass in total against the humans' 3.73M.

And the defense side matches too: **14 of 19 defense alerts are
`anchor=NavalBase`**, four are `anchor=Expansion`, and only one is
`anchor=Commander`. Three alerts report `friendly=0.0` — no defensive strength
whatsoever at the threatened point, with ratios of 206.65, 80.10 and 110.36.
Red Queen built 812 structures for 58 kills; the humans built 772 for 292. The
structures were built, but not at the expansions and naval bases that kept
falling.

### 3. Red Queen's own factory expansion never ran once

`CanExpandProduction` (`EconomyManager.lua:67`) requires
`self.Context.ArmyDeficit > 0`. The log opens with
`income contract allies=3 enemies=3 deficit=0` for all three brains, so in any
balanced match the gate is permanently closed. There is no
`production expansion type=` line in the entire log.

Every one of the 13–16 factories in the log therefore came from FAF's native
builders, against a Red Queen target of 3–8 (`factories=13/3`, `14/3`, `15/4`,
`16/8`). The V7 fix for this is present in code but inert: Red Queen's own
expansion is switched off, and its cap on the native path is the blunt
instrument described in finding 2.

### 4. The defense-alert veto makes late-game investment impossible

`UpdateFocusWeights` (`StrategyDirector.lua:738`) applies an unconditional
override:

```lua
if defenseAlert.Active then
    weights.Army = 100
    weights.Experimental = 0
    weights.Nuke = 0
    demand.MajorProjectSlots = 0
    demand.DesiredExperimentals = 0
    demand.DesiredNukes = 0
```

`baseDanger` separately gates `tech3`, `experimental` and `nuke` to zero at
source. Measured over the 188 state samples:

- **30 samples have `alert=yes`. Exactly 0 of them have `X > 0`.** The veto is
  absolute.
- 160 of 188 samples have `X=0`; 169 have `N=0`; 173 have `T3=0`.
- 160 of 188 have `slots=0` (`MajorProjectSlots`).

Army 6 shows the failure directly. Sampled at 41–67 mass income and 3500–4400
energy — comfortably past `ExperimentalMinimumMassIncome = 22` — its
experimental weight flips with the alert flag on a several-second cycle:

```
Defend  mass=48.2  X=0   alert=yes
Joint   mass=53.6  X=27  alert=no
Joint   mass=59.1  X=76  alert=no
Defend  mass=57.5  X=0   alert=yes
Joint   mass=41.3  X=57  alert=no
Defend  mass=48.8  X=0   alert=yes
Joint   mass=59.7  X=56  alert=no
Defend  mass=50.7  X=0   alert=yes
Joint   mass=55.3  X=66  alert=no
```

An experimental takes minutes to build. `DesiredExperimentals` is a unit-count
target, so dropping it to 0 every few seconds does not "pause new starts" as
the V7 plan intended — it withdraws the target from a project already under
way, then re-asserts it. Nothing finishes. Army 6 spent its last nine
consecutive samples pinned to `objective=Defend` while mass income collapsed
from 100.3 to 14.7, and never built an experimental.

Army 5 fails the same test for the other reason: it sat at exactly
`mass=21.8`, one tick under the 22 threshold, so `X` alternated `51 → 0 → 31`
with its income noise.

Result across the match: 4 experimentals, 0 experimental kills.

### 5. Combat commits in 3-unit packets

`CombatManager.Update` runs on `Ticks.Combat = 30`, i.e. every 3 seconds.
`SelectTaskForce` requires only `MinimumAttackUnits = 3` (2 when defensive),
sorts candidates by `EntityId`, and `IssueObjective` does
`IssueClearCommands` + `IssueAggressiveMove` with
`UnitOrderLifetimeTicks = 300` (30 seconds), after which the survivors return
to the pool.

There is no threat comparison anywhere in the path.
`EconomyManager.CanCommitAttack` was deliberately hard-wired to `return true`
with the comment "Existing combat units should never be held back", and
`SelectTaskForce` counts units, never their combined threat, and never weighs
them against the enemy strength at the destination. Sorting by `EntityId` means
the same oldest survivors are re-dispatched first while newly produced units
queue behind them.

This is the mechanism behind the headline number: 998 land units built, 1005
lost, 141 kills. Red Queen feeds a continuous trickle into formed enemy
armies. `momentum=.../losing` appears in the large majority of samples, with
readings as bad as `momentum=227394/52528/losing` — a 4.3:1 adverse exchange.

### 6. Airdrop machinery churns and delivers nothing

391 transport-related lines, 168 `airdrop state=TransportActive
reason=transport-in-use`, 58 `Ready`, 33 `Expired reason=target-lost`, 19
`Abandoned reason=defense-alert`, 3 `Requested`. Outcome: 50 transports built,
72 lost, **0 kills**, no successful drop.

### 7. Diagnostics and hygiene gaps

- **The analyzer collapses repeat failures.** `analyze-log.py` de-duplicates by
  exact line text, so 52 identical production crashes were reported as
  `Potential failures: 4`. A crash recurring 52 times is a different signal
  from one that fires once.
- **The contract gate cannot see this class of defect.** `./scripts/validate.sh`
  passes all 11 suites against the build that crashed 52 times. The stub at
  `tests/production_manager_spec.lua:35` accepts any argument list and returns
  `true`, so it can neither type-check the `closeToBuilder` argument nor
  reproduce an engine error. Every FAF boundary call needs at least one
  contract that throws.
- **`UpdateEmergencyDefense` is silent when it defers.** It returns at
  `HasManagedEmergencyDefense(alert)` with no log, so across 19 defense alerts
  the log cannot say whether the fortification builders ever ran. There is no
  `emergency defense` line of any kind in the log.
- **76 invalid manager locations**: 42 for `Large Expansion Area 1`, 34 for
  `Large Expansion Area 2`, against `adaptive production registered
  base=Large Expansion Area N`. Red Queen registers counter-builders at
  locations FAF's managers then reject.
- **One post-defeat engine failure**: `platoon.lua(1555): attempt to call
  method 'GetLocationCoords' (a nil value)`.
- **Doctrine thrash**: 19 `gunship counter abandoned`, with `doctrine`
  oscillating `Balanced → AirDefense → GunshipCounter → Balanced` throughout.
  Every flip rewrites production demand.
- **Tier regression unhandled**: army 6 ends at `tiers=L3,A1,N1` and army 5 at
  `L1,A1,N1`. `UpdateTierPolicy` only describes the highest *surviving*
  factory, so when the T2/T3 air and naval factories die, `ApplyTierPolicy`
  re-enables T1 mainline production at minute 65. This is how 925 T1 units get
  built in a 73-minute match.

## Implementation Plan

Ordered by blast radius. Findings 1–3 are plumbing defects that make the rest
unmeasurable; do them first.

### Priority 1 — Fix the build-structure calls and the forward-base leak

1. Pass the builder unit (not `false`) as `closeToBuilder` at all three
   `AIExecuteBuildStructure` call sites, matching FAF's own caller. Add a
   structural check in `validate_mod.py` that rejects a boolean literal in that
   argument position.
2. Wrap the per-structure build loop in `StartForwardBase` so a single engine
   rejection cannot abort the production task, and record the reason.
3. Make the record and the site claim transactional: insert the record and
   claim the site only once at least one structure is queued, and release both
   on every failure path including an engine error.
4. Set `LastForwardBaseTick` on *attempt*, not on success, so a failing site
   cannot be retried every tick.
5. Count `Preparing` and `Failed` records against a bounded retention window so
   `ForwardBases` cannot grow without limit, and have
   `CountViableForwardBases` include in-flight attempts.

Acceptance: a contract reproduces an engine error thrown from
`AIExecuteBuildStructure` and proves the production task survives, the record
and claim are released, and the cooldown advances. A smoke log shows
`forward base started` or a bounded, non-repeating failure reason.

### Priority 2 — Make the factory cap surgical

1. Gate factory construction per structure entry, not per builder. Where a
   FAF builder mixes factories with economy or defense structures, leave the
   builder enabled and suppress only the factory items — or, if the builder
   cannot be edited safely, exempt mixed builders from the cap entirely and
   cap through Red Queen's own expansion path instead.
2. Never allow the cap to reduce mass extractor, power, or defensive structure
   priority. Add an explicit protected-category list.
3. Decouple `DesiredFactories` from `ArmyDeficit` for the *cap*, and remove
   `ArmyDeficit > 0` from `CanExpandProduction` so Red Queen's own factory
   expansion runs in balanced matches. Keep the deficit bonus as an income
   handicap only.
4. Log the cap decision at a bounded cadence: which domains are at target,
   which builders were disabled, and how many were skipped as mixed.

Acceptance: contracts prove a mixed economy/defense builder is never
priority-zeroed by the factory cap, that a balanced match (`deficit=0`) can
still expand factories, and that mass extractor builders are exempt. A smoke
log contains `production expansion type=` lines.

### Priority 3 — Let the late game happen under pressure

1. Replace the binary `defenseAlert.Active` veto with a graded one. Scale
   experimental and nuke weight by alert severity and criticality rather than
   zeroing it, and keep the absolute veto only for a credible ACU attack in
   Assassination.
2. Never reduce `DesiredExperimentals` or `DesiredNukes` below the number of
   projects already under construction. A pause must gate *starts*, which is
   what the V7 plan specified; the current code withdraws the target from
   live projects.
3. Add hysteresis so weights cannot flip on a several-second cycle: require a
   minimum dwell time before an endgame focus is dropped, and reuse the
   existing `StrategicFocusSwitchMargin` for downward transitions too.
4. Reconsider the income thresholds against observed play. Army 5 spent its
   late game one unit of income below `ExperimentalMinimumMassIncome = 22`.
   Evaluate the gate on a smoothed income and on stored mass, not a single
   instantaneous sample.
5. Remove the `baseDanger` hard gate on `tech3` — losing T3 access under
   pressure is what produced 925 T1 units — and add an explicit rule against
   mass-producing T1 mainline when observed enemy tech is 3.
6. Give the tier policy an ambition target: when a domain has regressed below a
   tier it previously held, prioritise rebuilding that factory tier over
   producing at the surviving lower tier.

Acceptance: contracts prove an active non-ACU defense alert reduces but does
not zero experimental weight, that a project under construction is never
targeted away, that a focus cannot flip inside the dwell window, and that T1
mainline is suppressed against observed T3. A repeat match log shows `X > 0`
coexisting with `alert=yes`, and at least one experimental completed.

### Priority 4 — Stop feeding

1. Add a threat-based commitment gate to `SelectTaskForce`: compare the
   candidate task force's combined threat against observed enemy threat at the
   destination, and refuse to commit below a configured ratio.
2. Raise the effective attack minimum from a unit count to a threat floor, and
   stage units at a rally point until the floor is met instead of dispatching
   3-unit packets every 3 seconds.
3. Select task forces by contribution — highest threat, matched layer, tier
   coherence — rather than by `EntityId`, so new production joins the wave
   instead of queueing behind survivors.
4. Keep the existing rule that units are never held back by an *economic*
   gate, but let a *tactical* gate hold them: `CanCommitAttack` returning
   unconditional `true` is the mechanism that turns production into a trickle.
5. Re-evaluate the airdrop path. It produced 168 diagnostic lines, 50
   transports, 72 losses and zero kills. Either give it a hard success
   criterion and a strict budget, or disable it until forward bases work.

Acceptance: contracts prove no commitment below the threat ratio, deterministic
contribution-ordered selection, and staging behaviour. A repeat match log shows
mass K/L above 1.0 and land losses below land kills.

### Priority 5 — Diagnostics

1. `analyze-log.py` must report failure *counts* per distinct message, not a
   de-duplicated list. 52 occurrences of one crash must not read as 1.
2. Fail the gate on any `[RedQueen][ERROR] scheduler task` line, with the
   count and the named Red Queen function from the traceback.
3. Log `emergency defense deferred manager=<locationType>` when
   `HasManagedEmergencyDefense` returns true, so deferral is distinguishable
   from inaction.
4. Log the mass-income and factory-target trend, so economic stagnation
   (`21.8, 21.8, 21.8, 21.8`) is visible without post-processing.
5. Resolve the `Large Expansion Area 1/2` registration mismatch, and add the
   invalid-location count to the gate rather than reporting it as advisory.
6. Extract and summarise the end-of-game `JsonStats` block in the analyzer.
   Per-army built/lost/killed mass and per-category counts turned this match
   from anecdote into measurement; it should not require manual parsing.
7. Harden the FAF boundary stubs. Every stub standing in for an engine or FAF
   call must assert the argument contract it is imitating and must have a
   variant that raises, so a signature defect and a scheduler-abort path are
   both reachable from `./scripts/validate.sh`.

Acceptance: `./scripts/validate.sh` passes; the analyzer fails this match's log
on the production crash count; a rerun reports per-army K/L directly.

## Verification

`./scripts/validate.sh` for every change, a verified `mods/TheRedQueen`
symlink, and the command-line smoke plus log analysis. The smoke proves
initialization and scheduler safety only.

The behavioral acceptance tests remain full-length matches: a repeat
Assassination match on a comparable large mixed map, and a separate
Annihilation match. The single metric to watch is mass K/L — 0.25 in this
match against 3.10 for the humans. Experimentals completed and forward bases
established are the two secondary metrics that were flatly zero here.

## Execution Status — 2026-09-05

All five priorities are implemented. `./scripts/validate.sh` passes all 11
contract suites and the structural checks.

### Priority 1 — build-structure calls and forward-base leak

- All three `AIExecuteBuildStructure` calls now go through a single
  `ExecuteBuildStructure` wrapper that passes `nil` for the game-object
  argument and contains engine rejections in a `pcall`.
- `StartForwardBase` is transactional: the record is inserted and the site
  claimed only once at least one structure is queued, and the base name is
  consumed only on success.
- `LastForwardBaseTick` advances on the attempt, so a refused site cannot be
  retried on the next production pass.
- `PruneForwardBaseRecords` drops terminal records after
  `ForwardBaseRecordRetentionSeconds` and releases their claims;
  `CountViableForwardBases` counts in-flight attempts against the map cap.
- `validate_mod.py` fails the build if `AIExecuteBuildStructure` is reached
  outside the wrapper.

### Priority 2 — surgical factory cap

- `BuilderConstructionDomains` now reports whether a builder is *pure*. Only
  pure factory builders are capped on factory count. A mixed builder — every
  live one creates an expansion or naval base — stays enabled while the map
  still has unclaimed base slots (`CountManagedBases` against
  `GetBaseAppetite`), and is capped once it does not.
- `CanExpandProduction` no longer requires `ArmyDeficit > 0`, and
  `DesiredFactories` no longer adds the deficit, which double-counted a
  handicap already paid out in `IncomeBonus`.
- A bounded `factory cap L/A/N bases=n/m mixed=k` diagnostic reports the
  decision, including how many mixed builders were exempted.

### Priority 3 — late-game investment under pressure

- The defence-alert veto is graded. Only a credible commander attack in
  Assassination vetoes absolutely (`FocusReason = "commander-emergency"`);
  every other alert scales experimental and nuclear weight by
  `1 - (Severity - 1) * DefenseAlertEndgameTaxPerSeverity`, floored at
  `DefenseAlertMinimumEndgameRetention`.
- `DesiredExperimentals` and `DesiredNukes` are never reduced below the number
  of projects already under construction, through any veto including the
  commander emergency.
- `SelectPrimaryFocus` will not abandon an endgame focus for army or tier
  production inside `StrategicFocusDwellSeconds`. Trading one endgame focus for
  the other stays free.
- `CanAfford` judges on the better of instantaneous and smoothed income, so a
  single dipped sample cannot cancel a multi-minute decision.
- `baseDanger` no longer zeroes Tech 3, and `ShouldSuppressLowTierMainline`
  stops Tech 1 mainline production when a domain has been reduced to Tech 1
  while the enemy is observed at Tech 3 — but only while the Tech 2 upgrade is
  affordable, and never for specialist roles.

### Priority 4 — tactical commitment

- `SelectTaskForce` selects by threat contribution, with `EntityId` breaking
  ties only, so new production joins a wave instead of queueing behind
  survivors.
- Offensive commitment requires the task force's combined threat to reach
  `CommitmentThreatRatio` of the observed enemy threat at the destination. A
  full task force always commits. Defensive responses are never gated, and no
  economic or elapsed-time condition can hold a unit back.
- Held commitments are reported as `commitment held objective=... units=...
  threat=... required=...`.

### Priority 5 — diagnostics

- `analyze-log.py` reports occurrence counts per distinct failure, names the
  Red Queen function from each traceback, gates on scheduler failures and
  invalid manager locations, summarises the end-of-game `JsonStats` scoreboard,
  and reports how many alert samples retained a non-zero experimental weight.
- `RedQueenRetireBuilders` retires every `Red Queen ` builder on teardown.
  FAF's `GetHighestBuilder` skips any builder below priority 1 before
  evaluating its conditions, so this removes the source of the 76 invalid
  manager location warnings — all of which named the two locations army 4 had
  registered, and all of which appeared after its defeat.
- `UpdateEmergencyDefense` logs `emergency defense deferred` when it hands the
  anchor to registered fortification builders, so deferral is distinguishable
  from inaction.
- `Diagnostics:ReportEconomy` reports an income plateau directly.
- The `AIExecuteBuildStructure` stub in `production_manager_spec.lua` now
  asserts its argument contract and can raise, so both the signature defect and
  the scheduler-abort path are reachable from the gate.

### Verification

- `./scripts/validate.sh`: 11 suites and structural checks pass. The two new
  behavioural contracts were mutation-tested — reverting the mixed-builder
  exemption and the commitment gate each fails its suite.
- Development symlink restored: `mods/TheRedQueen` had become a real directory
  copy, which AGENTS.md forbids reading runtime results from. It was
  byte-identical to this checkout, so the V8 analysis above still stands, but
  it has been replaced with a symlink resolving to this repository.
- Five-brain command-line smoke on `SCMP_007`: 5 brains started, zero engine
  Lua failures, zero scheduler failures, zero invalid manager locations, zero
  gated failures. The new paths ran — `factory cap L1/1 A0/1 N0/0 bases=1/8
  mixed=8` shows eight base-creating builders exempted at the moment the land
  target was met, and `commitment held` fired twice.

The smoke proves initialization, scheduler safety, and that the new decision
paths execute. It does not reach the late game. The behavioural acceptance
tests remain a repeat full-length Assassination match on a comparable large
mixed map and a separate Annihilation match. The metrics to read from the
analyzer are mass K/L (0.25 in this match against 3.10 for the humans),
experimentals completed, forward bases established, and the alert-sample line
that read 0/30 here.

## Verification Match — 2026-09-05

A 40-minute seven-brain mirror match on `the_drunken_beetles_dance.v0001`, the
same map as 27741743, run from the development symlink. Army 6 won; the other
six were defeated, so every teardown path was exercised six times.

### Directly comparable results

| Metric | 27741743 (V8) | Verification |
| --- | --- | --- |
| Red Queen scheduler failures | 52 | **0** |
| Red Queen Lua failures | 0 | 0 |
| Invalid manager locations | 76 | **10** |
| Forward bases started / established | 0 / 0 | **7 / 2** |
| Alert samples keeping endgame investment | **0 / 30** | **14 / 33** |
| Experimentals built by the strongest brain | 1 | **2** |

All nine engine Lua failures in the verification match are FAF's own
(`platoon.lua:1555` and `aibrains/adaptive-ai.lua:498`, both dereferencing a
torn-down `EngineerManager`); none carries a Red Queen traceback frame.

The winning brain's late-game samples, every one under an active defence alert:

```
mass=58.8 energy=3475  A=100 X=63 N=72  slots=1
mass=57.3 energy=3475  A=100 X=43 N=50  slots=3
mass=75.4 energy=4675  A=100 X=30 N=0   slots=3
```

Under V8 every one of those would have read `X=0,N=0,slots=0`. Army production
still dominates, which is correct under an alert, but tier and major-project
investment now continue alongside it.

### What this match cannot show

It is a mirror. Every loss for one brain is a kill for another, so aggregate
mass K/L is pinned near 1.0 by construction and the winner's 3.62 says only
that it beat its clones. **Trade efficiency — the headline 0.25 against the
humans' 3.10 — is not measured here and remains open.** It requires a match
against humans or a non-Red-Queen AI.

The counts above are immune to that confound: they are absolute, and zero
scheduler failures is zero regardless of opponent.

### Findings that need work

1. **Invalid manager locations are reduced, not solved.** All ten name
   `ARMY_1`, a location three *surviving* brains had registered builders at and
   then lost in combat. `RedQueenRetireBuilders` covers brain death, not base
   loss during play: once FAF nulls `BuilderManagers[loc].EngineerManager` the
   still-running manager thread keeps evaluating those builders, and Red Queen
   no longer holds a handle to reach them. The fix is to retain the manager
   reference at registration so the builders can be retired when the brain-table
   entry loses its managers. FAF's own builders at the same location raise the
   same warning, so this is a shared surface rather than a purely Red Queen
   defect.
2. **The forward-base bottleneck is engineer availability, not the crash.**
   82 `no-idle-engineer` and 50 `engineer-without-manager` against 230 total
   blocks. `FindForwardEngineer` requires `unit:IsIdleState()`, and engineers in
   a working AI are almost never idle. The crash was masking this in V8, where
   the same shape appears (60 + 27). Reserving an engineer rather than waiting
   for one to fall idle is the highest-value follow-up.
3. **Route threat predicts forward-base failure.** Army 6's two established
   bases both had `routeThreat=0.0`; its one failure had `routeThreat=11.9`.
   The safety ratio is doing real work and the signal is worth strengthening.
4. **Transports peaked at 47 on one brain** before the budget existed, worse
   than the 30 first observed. `MaximumTransports = 10` is implemented and
   contract-covered but has not yet run in a match.
5. **Economy stagnation reporting was latching onto spikes.** Army 6 read
   "stagnant" while climbing 7.8 → 9.4 → 10.1, because a transient 14.1 sample
   had set the high-water mark. It now compares smoothed income and reports the
   peak, distinguishing a decline from a plateau.

### Changes made during verification

- Forward-base failure now reports `engineer-lost`, `manager-lost` or
  `no-factory`, and a base whose engineer and manager both survive is no longer
  retired at six minutes. Note `RQFB_6_2` established *inside* the old six-minute
  window, so the longer deadline is a margin for remote sites, not a proven fix.
- `MajorProjectSlots` takes the sum of in-flight projects rather than the
  maximum, so an experimental and a nuclear launcher no longer share one slot.
- Transport budget added.
- The analyzer attributes post-defeat failures on traceback frames only. It
  previously matched the `[RedQueen]` log prefix, so any engine failure logged
  next to Red Queen output was blamed on this mod.
- Post-defeat failures in FAF code are reported as advisory rather than gated.
  `platoon.lua:1555` fires once per defeat in any match; gating on it would keep
  the gate permanently red and bury a genuine Red Queen leak.

The gate still exits non-zero on this log, correctly, because of finding 1.
