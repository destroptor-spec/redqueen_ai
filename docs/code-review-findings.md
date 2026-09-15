# Code review findings — uncommitted V9 work, 2026-09-14

Review of the uncommitted working tree on `ai/v8-execution-fixes` (28 modified
files, +7738/-273, plus 51 new files). Supersedes nothing: the nine findings in
`docs/review-fixes-verification.md` were already corrected and are **not**
repeated here. This pass looked for what remains.

Nothing here is match evidence. These are static findings; several change
production or forward-base behaviour and would therefore change what a matrix
measures, which is the argument for fixing them before the V9 matrix rather
than after.

**Verification status** is recorded per finding:

- `verified` — confirmed against the code, the installed FAF sources, or a
  blueprint, by re-deriving the failure rather than accepting the claim.
- `relayed` — reported by a reviewer, mechanism plausible and consistent with
  the surrounding code, but not independently re-derived.

## Status board

| # | Severity | File | Defect | Status | Fixed |
| --- | --- | --- | --- | --- | --- |
| 1 | high | `ProductionManager.lua:21,111,519,701` | Quantum Gateway counted as a Tech 3 Land factory | verified | [x] |
| 2 | high | `ProductionManager.lua:2232` | Forward-base exemption set is always empty | verified | [x] |
| 3 | high | `CombatManager.lua:236` | Garrison releases on any single loss once assignments expire | verified | [x] |
| 4 | high | `CombatManager.lua:420` | Air threat counted against a land-only escort | verified, seen live | [x] |
| 5 | high | `StrategyDirector.lua:591` | One frigate blinds the base's entire air defence | verified | [x] |
| 6 | high | `StrategyDirector.lua:87,1642` | On Mixed maps the fleet still never gets an objective | verified | [x] |
| 7 | medium | `StrategyDirector.lua:1647` | Water target selection asks for a route out of dry land | verified | [ ] |
| 8 | medium | `StrategyDirector.lua:171` | Air units credited only `SubThreatLevel` | verified | [x] step 1 of `threat-accounting-plan.md` |
| 9 | medium | `StrategyDirector.lua:635,696` | `Targets.Ground` rekeyed to `land + naval` | relayed | [ ] |
| 10 | medium | `ProductionManager.lua:2241` | `UpdateEngineerRetreat` ignores the engineer holds | verified | [ ] |
| 11 | medium | `CombatManager.lua:696` | Scout fallback only inspects `wanted[1]` | verified | [ ] |
| 12 | medium | `scripts/analyze-log.py:38` | Fixture base location invisible to the log attributor | verified | [ ] |
| 13 | medium | `ProductionManager.lua:2206` | Commander assist undone 5 s later | relayed | [ ] |
| 14 | low | `CombatManager.lua:575` | `ScoutSummary` stale on early return | verified | [ ] |
| 15 | low | `ProductionManager.lua:2377` | Claim released while a `Failed` record still owns it | relayed | [ ] |
| 16 | low | `CombatManager.lua:655` | Same-position scout candidates each consume a scout | relayed | [ ] |

## Fix verification — 2026-09-14

Findings 1, 2 and 3 are corrected. `./scripts/validate.sh` exits 0. Finding 3
was additionally proven in the running engine, because its failure is a timing
interaction a pure spec cannot reach: the lease lapsing underneath the loss
window.

### What changed

- **1** `FactoryLayer` and `UnitDomain` return `nil` for a factory with no
  combat domain, so a Quantum Gateway no longer counts as a Tech 3 Land factory
  in either the tier policy or the capacity targets.
- **2** The forward-base exemption reads `(demand.ForwardBasePlan or {}).Sites`
  — the field that actually exists — so engineers finishing an established site
  are no longer recalled.
- **3** `MaintainForwardGarrisons` renews the lease of existing holders each
  pass, up to `desired`, ordered by `EntityId` for determinism. Membership no
  longer lapses underneath the loss window.
- **4** `GetSiteThreat` now passes the `"Land"` layer, so the figure the escort
  is judged against excludes enemy air. `IntelManager:GetThreatNear` returns
  `Land + Naval` for any surface layer and only folds `Air` in when no layer is
  given, which `tests/intel_manager_spec.lua:116-119` already pins (no layer 17,
  `"Air"` 4, surface layers 13).
- **5** The defence-alert water view is now taken only when the fleet is the
  main body — `naval > land` **and** `naval >= air` — and the numerator is
  matched to it, so a water-layer comparison is judged on the surface contact
  rather than on the cluster total. `Severity` derives from `ratio`, so it
  follows automatically. The trace line now carries `defenseLayer=` and
  `facing=` so the decision is legible in a match log.

  Two failures were possible and both are closed: a token escort flipping the
  measurement to a denominator that cannot see air defence (the reported bug),
  and the mirror of it, where a sliver of naval contact would have hidden a
  genuine air raid behind a surface-only numerator. A residual remains and is
  commented at the call site: when a fleet really is the main body, its
  escorting air is still outside the comparison. Closing that needs the air
  accounting in `NavalDefenseThreat` fixed first, which is finding 8.
- **6** An offensive objective now carries `LayerPositions.Water`, resolved by
  `WorldModel:GetNavalApproach` from the army start to the objective's own
  target, and `CombatManager:IssueOrders` dispatches the fleet there when the
  objective's own layer is Land or Air. `GetNavalApproach` resolves both ends
  onto water and returns nil when the only route stays inside our own basin,
  so where no naval route exists the field is simply absent and dispatch is
  unchanged. Nothing is invented in `CombatManager`, which is the rule that
  cost match 27741743 its 1005 units.

  This reuses the `LayerPositions` mechanism the defensive path already had,
  rather than adding a second one. Note the fix deliberately does **not** change
  which layer leads: on a Mixed map the objective is still Land, because the
  land route is the one that reaches the target. The fleet simply stops being
  the only task force with nowhere to go.

### Runtime evidence for finding 3

Real-engine fixture on SCMP_018, seed 2071971, UEF against Cybran, launched
through `scripts/run-smoke.sh` with the fixture appended to `lua/simInit.lua`
in a hash-recorded overlay. It creates 20 real units, garrisons a site through
`CombatManager:MaintainForwardGarrisons`, and drives them across the lease
boundary using real movement orders and native loss callbacks.

```text
[RedQueenGarrisonFixture] retained tick=858 original-deadline=800 members=5 losses=1
[RedQueenGarrisonFixture] PASS lease-boundary-retained=5 single-loss-held=true
    half-loss-released=true survivors-freed=3
```

At tick 858 — 58 ticks past the original lease deadline of 800 — five members
were still held after one loss. Before the fix the cohort would have lapsed at
800 and the next pass would have read `held=0 losses=1` and withdrawn cover. A
genuine half-cohort loss still releases correctly, logging `units=3 losses=3`
rather than the old `units=0`.

`analyze-log.py` reported 0 Red Queen Lua failures and 0 scheduler failures
across 25 state samples. The three engine failures are native FAF code — two in
`gridpresence.lua`, one in `platoon.lua` — and none names Red Queen.

Two cautions for whoever reads this next:

- The first attempt at this fixture proved nothing. It budgeted
  `20 x WaitTicks(30) + 1` = 601 ticks against a 600-tick lease, a one-tick
  margin, and died on "original deadline not reached" before reaching a single
  assertion. It now waits on the deadline itself with a 50-tick margin.
- That throw was filed by `analyze-log.py` as an *unattributed engine failure,
  advisory, not gated*, because the traceback path is the overlay rather than a
  `theredqueen` path. A fixture that raises therefore looks clean to the
  analyzer; only the runner's own PASS-string check caught it. Compare
  finding 12, which is the same attribution gap.

One `escort-overwhelmed units=0 losses=1` still appears in the same run, at
`RQFB_2_3`. With leases now renewed this is consistent with the escort being
killed outright rather than lapsing, which is a true overwhelm — but it is
worth confirming that is what happened before closing finding 3 for good.

### Finding 6 regression

Both halves are covered, and each was confirmed load-bearing by reverting that
half alone and re-running:

- `tests/strategy_director_spec.lua` — a Mixed map **with** a working land route
  must still lead on Land and must hand the fleet `LayerPositions.Water`; with
  `GetNavalApproach` returning nil the field must stay absent. The existing
  cases only covered Mixed when land could *not* reach, which is exactly how the
  common case went unnoticed.
- `tests/combat_manager_spec.lua` — a Land objective on its own must leave the
  fleet unordered, and the same objective carrying a water destination must add
  exactly one more wave and actually order the ships.

### Finding 5 regression

`tests/strategy_director_spec.lua` adds two cases with a layer-aware
`GetOwnThreatNear` stub returning 400 on the land view and 0 on the water view,
which is what the real function reports for a base holding interceptors and AA:

- A cluster of `Naval=6, Air=300` must be measured on the `Land` layer and must
  raise no alert.
- A cluster of `Naval=200, Air=10` must still be measured on `Water` and must
  still alert.

The first assertion was confirmed load-bearing by restoring the old dominance
rule and numerator while leaving the spec in place — the spec fails — then
restoring the fix.

### Finding 4 regression

`tests/combat_manager_spec.lua` now drives `coverUnder` with a layer-aware
threat stub: a site with 900 air threat overhead and nothing on the ground must
still be covered, while 500 of ground threat must still release. The first
assertion was confirmed load-bearing by removing the `"Land"` argument and
re-running — the spec fails — then restoring it.

Runtime confirmation for finding 4 is still outstanding. It is not required for
the logic, which the spec covers, but the `escort-outmatched units=0 losses=0`
signature quoted below should disappear from ordinary play and that is worth
one match. Note the raw artifacts for the runs quoted in this document lived
under `/tmp` and did not survive a reboot; the figures here are the record.

### Finding 4 confirmed in ordinary play

The same run shows finding 4 three times, outside the fixture:

```text
forward base garrison released site=RQFB_2_1 reason=escort-outmatched units=0 losses=0 strength=0
forward base garrison released site=RQFB_2_3 reason=escort-outmatched units=0 losses=0 strength=15
forward base garrison released site=RQFB_2_3 reason=escort-outmatched units=0 losses=0 strength=0
```

Cover refused with no losses at all — the signature the file's own comment
records from an earlier matrix. Finding 4 remains open.

## High

### 1. Quantum Gateway counted as a Tech 3 Land factory

`ProductionManager.lua:21` (`FactoryLayer`), `:111` (`UnitDomain`), `:519`
(`CountFactories`), `:701` (`UpdateTierPolicy`).

Both domain helpers fall through to `"Land"` when a blueprint carries no
`AIR`/`NAVAL` category. `UEB0304_unit.bp`, extracted from `units.nx2`, lists:

```
BUILTBYTIER3COMMANDER, BUILTBYTIER3ENGINEER, DRAGBUILD, FACTORY, GATE,
PRODUCTSC1, RALLYPOINT, RECLAIMABLE, SELECTABLE, SHOWQUEUE, SIZE20,
SORTSTRATEGIC, STRUCTURE, TECH3, UEF, VISIBLETORECON
```

No `LAND`, `AIR` or `NAVAL`. `CountFactories` selects
`categories.STRUCTURE * categories.FACTORY`, so the gateway is included and
bucketed Land; `UpdateTierPolicy` then sets `Land.T3 += 1`, `Land.Highest = 3`
and, once complete, `Land.Ready = 3`.

This is live in the current diff: `CounterBuilders.lua:1067` is a
"Red Queen Quantum Gateway" builder and `ProductionManager.lua:428-435`
registers `RedQueenSupportCommanderBuilders`.

Two failures, both permanent:

- **Tier gate.** Lose the only real Tech 3 land factory while the gateway
  stands and `Land.Ready` remains 3, so every Tech 1 and Tech 2 Land *Mainline*
  builder is marked obsolete and set to priority 0. The gateway's buildable set
  is `BUILTBYQUANTUMGATE` (SACUs only), so land unit production stops and can
  never resume — nothing can lower the tier again.
- **Capacity gate.** With `targets.Land = 2`, one real land factory plus the
  gateway gives `counts.Land = 2`; land factory builders go to priority 0 and
  `SelectFactoryType` returns nil for Land, so the second land factory is never
  built.

FAF does not make this mistake: `FactoryBuilderManager:AddFactory` tests
`categories.LAND` first and routes the gateway to its `'Gate'` builder list,
which the tier and engineer policies (both iterating `{ "Land", "Air", "Sea" }`)
never touch.

A matrix run with this live would misattribute any land-production result.

### 2. Forward-base exemption set is always empty

`ProductionManager.lua:2232`.

```lua
for _, record in pairs((self.ForwardBasePlan or {}).Records or {}) do
```

`self.ForwardBasePlan` is never assigned anywhere in the repo — the plan lives
at `self.Strategy.ProductionDemand.ForwardBasePlan` (assigned line 2550) — and
its key is `Sites`, not `Records` (every other reader uses `plan.Sites`). The
expression is therefore always `{}`, and `claimed` only ever contains
`self.ForwardBaseActive.Engineer`.

A site becomes Established when its factory appears and `ForwardBaseActive` is
cleared (lines 2292, 2336), but the engineer is still working through the rest
of the package — for a Tech 3 site that is 3x ground defence, 2x Tech 3 AA, the
shield, the missile defence and both artillery pieces. The site is by
construction far from home and contested, so on the next pass the engineer is
unclaimed, and `ReleaseEngineer` wipes `EngineerBuildQueue`, issues
`IssueClearCommands` and walks it home. The base keeps only what was finished
before the factory, while `CombatManager` still garrisons it against a
`MinimumDefenses` figure that can now never be met.

Compounds with finding 10.

### 3. Garrison releases on any single loss once assignments expire

`CombatManager.lua:236`.

```lua
local sent = table.getn(held) + losses.Count
if losses.Count > 0
    and losses.Count >= math.max(1, sent * Constants.Policy.GarrisonLossFraction)
```

`held` counts only units *currently* assigned. Garrison membership expires on a
60 s timer (`RedQueenGarrisonUntil = tick + ForwardBaseGarrisonSeconds * 10`,
line 334) and is refreshed **only for newly selected units** — existing holders
are never renewed and are cleared by the cleanup at lines 160-169.
`ForwardBaseGarrisonSeconds = 60` and `GarrisonLossWindowSeconds = 60` are
equal, so the moment assignments lapse `held = {}` and the test collapses to
`losses.Count >= 1`.

Four tanks cover a site at t=0; one dies at t=50 s; the survivors expire at
t=60 s; the next pass computes `held=0, losses=1`, so `1 >= max(1, 0.5)` fires
`release = "escort-overwhelmed"`, and
`ipairs((release or understrength) and {} or prospect)` selects nobody. A site
losing at least one garrison unit per 60 s is never covered again.

The release logs `units=0 losses=1`. The comment at line ~290 records that
`units=0 losses=0` releases were already measured in game and fixed; this is
the surviving half of the same defect.

### 4. Air threat counted against a land-only escort

`CombatManager.lua:420`.

`GetSiteThreat` calls `intel:GetThreatNear(position, radius)` with no layer, so
`IntelManager.lua:265-271` takes `elseif not layer then relevant = relevant +
threat.Air`. The sibling `GetObjectiveThreat` (line 401) does pass a layer.

Escorts come from `GarrisonEligible = categories.MOBILE * categories.LAND *
categories.DIRECTFIRE`, whose `UnitThreat` is surface threat with essentially no
anti-air. Enemy gunships loitering within `CommitmentThreatRadius = 60` alone
satisfy `enemy > prospectiveStrength * CommitmentThreatRatio`, firing
`release = "escort-outmatched"` and refusing land cover at any site under an
air corridor with zero enemy ground presence.

### 5. One frigate blinds the base's entire air defence

`StrategyDirector.lua:591`.

```lua
local defenseLayer = (cluster.Naval or 0) > (cluster.Land or 0) and "Water" or "Land"
...
local ownThreat = self:GetOwnThreatNear(anchorPosition, ..., defenseLayer, cluster.Position)
local ratio = cluster.Threat / math.max(1, ownThreat)
```

The layer choice compares Naval against Land and ignores Air entirely, but the
numerator `cluster.Threat` includes Air.

Thirty gunships and fighters (`Air ~ 300`) plus one frigate (`Naval = 6`,
`Land = 0`) close on the main base, which holds 25 ASFs and a ring of Tech 2 AA.
`6 > 0` selects `"Water"`, so `NavalDefenseThreat` credits AIR units only
`SubThreatLevel` (line 171 — zero for ASFs) and the AA towers zero, because
their `FireTargetLayerCapsTable.Land` is `"Air"`, which contains no `"Water"`.
`ownThreat = 0`, ratio ~306 clears both `MassiveArmyThreat` and
`MassiveArmyThreatRatio`, so a `massive` alert raises, `PrimaryFocus` is forced
to Army and every task force is recalled — against an attack the base was
already built to stop.

Same root cause as finding 8.

### 6. On Mixed maps the fleet still never gets an objective

`StrategyDirector.lua:87` and `:1642-1651`.

`OffensiveLayers.Mixed = { "Land", "Water" }` and the selection loop `break`s on
the first layer that resolves. Any observed enemy structure a land route reaches
yields `preferredLayer = "Land"`, so the objective carries `Layer = "Land"`.
`CombatManager:IssueOrders` then takes the final `else` branch and iterates
`LandDispatchLayers = { "Land", "Amphibious", "Hover" }` (line 766), so
`groups.Water` is never passed to `DispatchLayer`. Meanwhile `demand.Naval`
keeps producing ships, which accumulate in the ArmyPool unordered for the whole
match.

The comment at lines 1640-1641 states this was fixed — "on a Mixed map it only
ever offered Land, so the fleet was never given an objective at all" — but the
fix only takes effect when the Land layer yields nothing.

Naval production on a Mixed map is pure waste until this is corrected, so any
matrix cell on such a map measures a handicap rather than the brain.

## Medium

### 7. Water target selection asks for a route out of dry land

`StrategyDirector.lua:1647`.

```lua
if candidate and self.World:CanPath(layer, start, candidate.Position) then
```

`start` is the army start position — dry land. `WorldModel.lua:233-238`
documents the consequence verbatim:

> `NavUtils.CanPathTo` reports `OriginUnpathable` when the *origin* cell has no
> label on the layer, so asking it for a water route out of an army start — dry
> land, where the commander spawns — fails exactly as asking for a water route
> *to* one does. Testing only the destination leaves the same bug on the other
> end.

The comment at lines 1636-1641 recognised the destination half of this and
fixed it; the call at 1647 reintroduces the origin half. `known` can therefore
never be set for the Water layer, so a scored `Raid` on a naval target is
unreachable and the fleet falls through to a generic `Pressure` at a naval
approach waypoint. Related: `docs/naval-weakness-investigation.md`.

### 8. Air units credited only `SubThreatLevel`

**Scoped in `docs/threat-accounting-plan.md`.** This and the residual left at
the `defenseLayer` call site when finding 5 was fixed are one defect: the
numerator of every defence decision is split by arm and the denominator is not.
The plan carries the engine evidence, the three-test design, the blast radius
across the six `GetOwnThreatNear` callers, and the sequencing.

`StrategyDirector.lua:171` — `if hash.AIR then return defense.SubThreatLevel or 0 end`.

Gunships and bombers, the standard air answer to surface ships, count as zero
own-threat against a naval cluster. A destroyer group approaching a coastal
anchor while the army holds 20 Tech 2 gunships yields `ownThreat ~ 0` and a
permanent maximum-severity alert for as long as any ship is observed.

### 9. `Targets.Ground` rekeyed to `land + naval`

`StrategyDirector.lua:635,696-697`. *(relayed)*

`surfaceThreat = land + naval` means a purely naval attack orders up to 12 point
defences. The file's own comment at lines 707-710 states that point defence
reaches 26 (T1) or 50 (T2) while a destroyer bombards from 60 to 80 — so the
structures ordered cannot reach what triggered them, while consuming the
emergency-engineer roster and the cooldown slot that `UpdateShoreTorpedo` needs.

### 10. `UpdateEngineerRetreat` ignores the engineer holds

`ProductionManager.lua:2241`.

The loop tests only `IsAlive`, `not claimed`, `GetPosition` and
`not EngineerSurvival.IsRetreating`. It never checks
`RedQueenEmergencyDefenseUntil` or `RedQueenProductionBuildUntil`, which are set
at lines 1415, 1532, 1649 and 1723 and honoured at 1208-1220 (assist
candidates) and 1774-1780 (forward engineer candidates).

An engineer dispatched by `UpdateEmergencyDefense` to build point defence at a
threatened anchor is recalled by a later stage of the *same* `Update` pass,
because the anchor threat that raised the alert is what trips the retreat test.
The defence is never built, `LastEmergencyDefenseTick` holds the cooldown, and
the cycle repeats for every alert outside `EngineerSurvivalHomeRadius`.

### 11. Scout fallback only inspects `wanted[1]`

`CombatManager.lua:696`.

`GetScoutTargets` sorts coverage ascending first, weight only as a tiebreak
(`IntelManager.lua:349-355`). Candidate weights are objective 3, enemy start 2,
mass cluster 1 (`CombatManager.lua:548/555/562`) and
`ScoutFallbackMinimumWeight = 3`, so only the objective can pass the gate — but
the gate reads `wanted[1]`, which is normally a never-observed enemy start at
coverage 0.00. The fallback silently never fires, so `GetObjectiveThreat` keeps
returning 0 and the commitment gate judges waves against zero threat, the exact
failure the fallback exists to prevent.

Fix shape: take the first entry that *meets* the weight bar, not the first
entry.

### 12. Fixture base location invisible to the log attributor

`scripts/analyze-log.py:38`.

```python
# The only location names this mod registers; see ProductionManager `RQFB_%d_%d`.
RED_QUEEN_OWNED_LOCATION = re.compile(r"(?i)\bRQFB_\d+_\d+\b")
```

That comment is no longer true. `LifecycleFixture.lua:8` registers a real
BuilderManager location named `RQFB_LIFECYCLE_TEST` (line 12,
`brain:AddBuilderManagers`). The Lua side uses a five-character `RQFB_` prefix
test (`BaseLifecycle.lua:80`, `StrategyDirector.lua:522`) and handles both; only
the Python is stricter.

In a sentinel-47 run the fixture deliberately destroys managers and nils
`brain.BuilderManagers[location]` (lines 26-29) — precisely what produces
`*AI WARNING: ... Invalid location - RQFB_LIFECYCLE_TEST`. Attribution fails at
line 160; the fallback only attributes if a mod path frame appears within the
next 12 lines, and engine `*AI WARNING` lines usually carry no Lua traceback. So
the warning is filed as advisory in the one run designed to stress base
lifecycle. `validate_mod.py` does not cross-check the analyzer regex against the
name producers.

### 13. Commander assist undone 5 s later

`ProductionManager.lua:2206`. *(relayed)*

`ReleaseEngineer(commander, nil)` passes no home, so `RedQueenRetreatPosition`
is never set, `EngineerSurvival.IsRetreating` stays false and the
`hook/lua/sim/EngineerManager.lua` deferral does nothing. `ReleaseEngineer`'s
trailing `manager:DelayAssign(engineer, 50)` then re-tasks the ACU natively
after 5 s, discarding the `IssueGuard`, while
`commander.RedQueenAssistUntil = tick + CommanderAssistSeconds * 10` (450 ticks)
makes every later pass report it as assisting. The ACU assists for roughly 5 of
every 45 seconds and the state line claims the whole time.

## Low

### 14. `ScoutSummary` stale on early return

`CombatManager.lua:575`. `MaintainForwardGarrisons` sets
`self.GarrisonSummary = { Sites = 0, Units = 0 }` *before* its early return
(line 129); `MaintainScouts` returns at 575 but only writes
`self.ScoutSummary = summary` at 613. This is the unfixed sibling of the
"emergency cover reporting" correction in `docs/review-fixes-verification.md`.
When `ArmyPool` is absent the previous pass's `Sent`/`Blind`/`Targets` stand as
if current, and those figures feed the periodic state line
(`Diagnostics.lua:132`, `scout=` / `scoutorders=`) that a matrix reads.

### 15. Claim released while a `Failed` record still owns it

`ProductionManager.lua:2377`. *(relayed)* `liveSites` covers only
Preparing/Building/Established, so a retained terminal record that deliberately
keeps its claim ("structures are already queued at the site, so a second base
must not target it") loses it as soon as an unrelated older record for the same
site ages out, letting a third attempt queue a second package onto half-built
structures.

### 16. Same-position scout candidates each consume a scout

`CombatManager.lua:655`. *(relayed, lower confidence)* Carried-over reservations
are de-duplicated by coordinate (lines 633-638), but in-pass `Reserve` keys by
target table identity, so two candidates at identical coordinates each take a
scout. Requires the `Pressure` objective's position to alias an enemy start's;
that aliasing was not confirmed end to end.

## Verified clean

Checked by execution, not by reading:

```text
./scripts/validate.sh                                         # exit 0
python3 scripts/check-hook-targets.py ~/.faforever/gamedata/lua.nx2
python3 scripts/check-native-engineer-recall.py ~/.faforever/gamedata/lua.nx2
python3 scripts/check-native-placement.py ~/.faforever/gamedata/lua.nx2
```

Both safety nets were deliberately broken to confirm they fire, and the tree
restored afterwards:

- A planted module with a top-level `return { ... }` tripped the export contract
  in `validate_mod.py` and the gate exited 1.
- Planting the historical `EngineerMoveWithSafePath` capture in
  `hook/lua/platoon.lua` tripped `check-hook-targets.py`, which named the exact
  misplacement; the capture count moved 7 to 8 and back to 7.

Also confirmed clean across the diff:

- No `%` arithmetic operator, no top-level `return {` module export, no tabs,
  no wall-clock time or unseeded `math.random`. `table.getn` is correct idiom
  for this dialect and is not a finding.
- **Economy units.** Every `...MassIncome` / `...EnergyIncome` constant is
  per-tick and every consumer compares against `GetEconomyIncome` /
  `GetEconomyTrend` output. The repo's known ten-fold bug class is absent.
- **Builder mutation boundary.** Only per-instance `Priority` / `SetPriority`
  writes; no writes to shared builder definitions, `BuilderData` or
  `BuildStructures`.
- **Information contract.** Enemy data only through `GetVerifiedIntelBlip`
  (requires actively detected *and* identified), a bounded rotating observer
  set, and `ObserveUnit` receives the blip rather than the unit. The enemy brain
  is touched only for `GetArmyStartPos`, which is explicitly permitted.
- **Team layout determinism.** Both callers `table.sort(names)` before
  `ProximityTeams`, so the single-linkage seed really is the lexicographically
  first army.
- **Sentinel mapping 42-50** matches `AGENTS.md` exactly through
  `run-smoke.sh` into `hook/lua/aibrains/index.lua` (49 is `TeamMatch(2, 3)`,
  50 is `TeamMatch(3, 2)`).
- **ProductionTrace is bounded.** Off by default, 64-caps with disclosed
  overflow, and `Entities` records are freed on `destroyed`, `unknown` and
  `cleanup` paths.
- Loss-window prunes and the gunship doctrine's before/after ordering; the
  experimental alert clamp (cannot drop the owned count); weight clamping and
  two-sided focus hysteresis; tick-versus-second constants; the 1175 and 1229
  loop bounds; per-domain-only suppression; and the `ExecuteBuildStructure`
  signature change against all five call sites.

## Notes on the review itself

Three full fan-outs failed on API rate limits before one completed, so any
earlier "no findings" result from this effort was an infrastructure failure and
not a clean bill. Everything above comes from the completed pass.

Two claims were discarded rather than reported: a suspected nil index at
`wanted[1]` in `CombatManager` (guarded at line 686) and a suspected `Entities`
leak in `ProductionTrace` (refuted by the `destroyed` / `unknown` / `cleanup`
terminal paths).

`StrategyDirector.lua` dead code worth noting but carrying no failure: the
`land == nil and naval == nil` back-fill at lines 616-626 and the
`cluster.Naval == nil` guard at line 592 are unreachable, because
`IntelManager:GetObservedArmyClusters` always initialises `Land`, `Naval`,
`Surface` and `Air` to 0.
