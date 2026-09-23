# Scope: resource access peaks under half the map and erodes

Scoped 2026-09-22 against the finalized `faf-strategy-engineering` skill,
specifically `references/economy.md`, which splits the problem into **claim**
("why does it stop") and **retain** ("why does it fall"), and warns that
"replacements repeatedly sent through the same lethal route turn an apparent
economic shortage into a factory-allocation problem."

## The measurement

Red Queen's extractors against the map's mass points, `mex=` in the periodic
state line, across the eighteen mirror cells (army 2 is Red Queen; the opponent
is stock Adaptive at the same faction, so faction balance cancels).

| Map | Points | Peak claim | Final claim |
| --- | --- | --- | --- |
| Fields of Isis | 44 | 21–23 (48–52%) | 11–20 (25–45%) |
| Syrtis Major | 48 | 23–31 (48–65%) | 5–28 (10–58%) |

Peaking near half is not itself a defect: on a symmetric 1v1 an even split *is*
the equilibrium. **The erosion is the defect.** Nine of eighteen cells finish
below 35% of the map, and four finish at 10–15% — having reached 48–56% first.
Red Queen claims its half and then cannot keep it.

Structure survival measured earlier sits at 58–86% for Red Queen against 69–81%
for the opponent, so the extractors are being destroyed, not never built. This
is the **retain** half of the economy problem, not the claim half.

## What is already wired, and what it reports

`EngineerSurvival.lua` refuses to send an engineer somewhere dangerous. It has
two producers of exclusion and one consumer:

| Call site | Records | On what |
| --- | --- | --- |
| `StrategyDirector.lua:453` | `engineer-lost` | an engineer actually died |
| `ProductionManager.lua:2807` | `engineer-withdrawn` | an engineer was recalled; **nothing died** |
| `hook/lua/AI/aiutilities.lua:28` | consumes via `RouteVerdict` | refuses the native move outright |

Each record writes a `EngineerLethalSiteRadius = 40` circle, live for
`EngineerLethalSiteMemorySeconds = 180`. `RouteVerdict` then refuses any
destination inside one (`recent-loss`), any route whose observed threat exceeds
`max(EngineerSurvivalThreatFloor = 8, escort * 0.60)` (`route-unsafe`), and any
commander destination past `CommanderLeashRadius = 120` (`commander-leash`).

Both refusal reasons appear in **147 of 147 recorded match logs**. Each appeared
exactly once per log, because the hook rate-limited the line to its first
occurrence. Nothing counted them. This is precisely the trap AGENTS.md records:
a mechanism that runs a full matrix leaving no figure behind.

## The hypothesis

The withdrawal producer is the part worth naming. A recall writes the same
40-radius, 180-second exclusion as a death, at the *engineer's* position, on a
threat reading alone — and the same threat test re-runs every pass, so sustained
pressure near an expansion refreshes the exclusion indefinitely without anything
ever dying there.

That closes a loop against the retain problem:

> an extractor is raided → the engineer near it is killed or withdrawn → its
> ground becomes a lethal site → `recent-loss` refuses the rebuild → the point
> stays lost → the raid succeeded permanently, at the cost of one raid.

Under this hypothesis Red Queen's guard converts *temporary* pressure into
*permanent* forfeiture, and does so hardest exactly where pressure is highest,
which is where the mass is worth contesting. The four cells that finish at
10–15% are the prediction.

**Competing hypothesis, which the same counters separate:** the guard barely
fires, engineers simply die, and the erosion is an ordinary defensive failure
with no policy loop behind it. UEF is the case for this one — it lost 984
engineers against 965 built, a survival rate of −2%.

The two are distinguished by one ratio: refusals per engineer lost. High
refusals with modest losses is the loop; low refusals with heavy losses is
ordinary defensive failure. Nothing on record can currently tell them apart.

## Instrumentation shipped with this scope

`engsurvival=U/R/L/D/W/S` in the periodic state line:

| Field | Meaning |
| --- | --- |
| `U` | cumulative `route-unsafe` refusals |
| `R` | cumulative `recent-loss` refusals |
| `L` | cumulative `commander-leash` refusals |
| `D` | sites recorded from a death |
| `W` | sites recorded from a withdrawal, where nothing died |
| `S` | live unexpired exclusion |

Counted inside `RouteVerdict` at each refusal rather than at the caller, so any
future consumer is counted too. The hook's private tally is gone; it now
rate-limits its line off the same counter it reports. `tests/diagnostics_spec.lua`
loads the real module and pins both the reported figures and that expiry drains
`S` while leaving `D` and `W` standing. `scripts/validate_mod.py` fails if any
refusal reason stops being counted or the field stops being reported.

**No decision behaviour changed.** One side effect is worth stating rather than
asserting neutrality loosely: `LiveSiteCount` prunes expired sites on every
diagnostics pass, where pruning was previously lazy inside `RecentlyLethal` and
stopped at its first match. This changes the table's size, not which positions
match — `RecentlyLethal` already skipped expired entries — so no refusal that
would have happened stops happening. The run that reads this is therefore
comparable to the control payload, and step 1 of the measurement plan checks
exactly that.

## Policy table for the change this is scoping

Filled out for the candidate the hypothesis points at, to be built **only if the
counters support it**.

| Item | Content |
| --- | --- |
| Goal and context | Retain claimed mass points under raiding pressure. Land maps, 1v1 mirror, Isis (44 points) and Syrtis (48 points), assassination. |
| Trigger | An extractor site inside a live lethal-site exclusion whose exclusion was written by a *withdrawal* rather than a death, or whose recorded threat has since lapsed. |
| Feasibility | The rebuild is an ordinary engineer job at a known site with a known cost; what is missing is permission, not build power or route. |
| Control and fallback | Escort scales the threat limit already (`escort * 0.60`); the fallback when no escort is available is the current refusal, unchanged. |
| Opportunity cost | Engineers and their mass, which is exactly what the guard exists to protect. Any relaxation must be paid for by retained income, measured as `mex=` final claim, not by refusal count falling. |
| Exit | Site claimed, or the threat that wrote the exclusion observed again, or the engineer lost — which re-arms the exclusion as a death, not a withdrawal. |
| Evidence | `engsurvival=` counters against `mex=` peak and final claim, per cell. |
| Falsifier | Withdrawals are a small fraction of sites, or refusals are rare against losses, or relaxing the guard raises engineer losses without raising final claim. Any of the three kills the loop hypothesis. |

## Candidate levers, in the order the evidence would justify them

1. **Do not let a withdrawal write an exclusion at all**, or expire it far
   faster than a death. A recall is a decision Red Queen made; a death is
   evidence it got wrong. Treating them identically is the part with no
   justification behind it.
2. **`EngineerSurvivalThreatFloor = 8`** is an admitted single-sample estimate —
   its own comment says "a route threat of 0.6 was harmless, while 70.5 killed
   the engineer that walked it. The floor is a first estimate between those."
   It gates every claim decision on the map.
3. **`EngineerLethalSiteRadius = 40` for 180 seconds**, which is a large fixed
   circle regardless of what was seen or how long ago.

Take these one at a time. `red-queen-lessons.md` records that engineer
replacement churn was previously attacked with a global headcount ceiling and
failed; the lesson is to fix the demonstrated unsafe path, not the population.
AGENTS.md records that bundling is acceptable only when each change is
separately observable, and these three are not.

## Measurement plan

1. Re-run the eighteen mirror cells on the instrumented payload. Behaviour is
   unchanged, so the outcomes must reproduce the control exactly — if they do
   not, the instrumentation is not neutral and nothing after this is readable.
2. Read `engsurvival=` against `mex=` peak and final. Decide between the loop
   and ordinary defensive failure before writing any policy change.
3. Only then build the first lever, and hold the other two.

---

# Results: the 18-cell instrumented matrix (2026-09-22)

Payload `d9d87346e487` (instrumentation only) against control `24c0b34595dc`.

## Neutrality

All 18 cells reproduce the control **exactly**: same state-sample count, same
peak claim, same final claim, and 40/40 byte-identical state lines on the cell
checked line by line. `analyze-log.py` reports 0 Red Queen Lua failures and 0
scheduler failures in all 18. The measurement is free.

Establishing this took three runs and was worth every one. The first instrumented
run diverged from the control at state sample 11, and the cause was **not** the
instrumentation — it was the orphan-demand deletion carried in the same tree.
`ProductionManager.GetFactoryTargets` reads `demand[domain]` by index over
`{ "Land", "Air", "Naval" }`; with Land and Air deleted nothing cleared the
`>= 0.10` relevance test, so every factory in the match was allocated to land and
no air factory was ever built. Reverted. See the correction in
`faction-composition.md`.

A control-payload re-run reproduced the original control 15/15, which is the
first direct evidence in this project that a match is reproducible **across
sessions and machine load**, not merely within a matrix.

## What the guard actually does

| | UEF | Aeon | Sera |
| --- | ---: | ---: | ---: |
| refusals per engineer death | 130 | 109 | 98 |
| withdrawal-written sites | 41 | 29 | 43 |
| claim retention at minute 28 | 0.69 | 0.79 | 0.65 |

Across all 18 cells: **99 refusals per engineer death** (range 48–150), and
**47% of all exclusion circles are written by withdrawals, where nothing died.**
`commander-leash` refusals are **zero in every cell** — that branch never fires.

## The claim curve has no recovery phase

Mean over all 18 cells, claim as a share of the map's mass points, against the
cumulative number of exclusion circles written:

| game minute | 5 | 10 | 15 | 20 | 25 | 35 | 45 | 60 | 94 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| claim share | 30% | **45%** | 43% | 38% | 36% | 37% | 34% | 28% | 25% |
| sites written | 0 | 9 | 29 | 49 | 70 | 105 | 143 | 210 | 399 |

Claim peaks at minute 10 at 45% and declines monotonically for the rest of the
match. The peak coincides exactly with the first exclusion being written. Red
Queen expands freely until first contact and then **never expands again** — it
has no mechanism that retakes ground, only one that stops going there.

## What this does and does not establish

Two of the three falsifiers in the scope table did not fire: refusals are not
rare against losses (99:1), and withdrawals are not a small fraction of sites
(47%). The guard is a large, real, and until now entirely invisible mechanism.

But **correlation does not support the loop**. Against claim retention at a
common 28-minute horizon, Spearman rho is −0.58 for engineer deaths, −0.53 for
the live exclusion, −0.36 for total refusals and only −0.18 for withdrawal
sites. Deaths predict lost claim better than guard activity does, which is what
ordinary defensive failure looks like.

This is collinear and cannot be resolved by more observation: pressure causes
deaths, exclusions and claim loss together. Only intervention separates them.

Note also that cross-cell comparison of *final* claim is confounded — cells were
observed for 28 to 95 game minutes, deterministically but unequally — so every
figure above is taken at a common horizon. The earlier per-faction retention
ordering in this document was an artifact of that unequal window and is
superseded by the table above.

## Next: lever 1, and what it predicts

Stop a withdrawal from writing an exclusion, or expire it far faster than a
death. This removes 47% of the exclusion footprint and nothing else, and a
withdrawal is Red Queen's own decision rather than evidence the ground killed
anything.

- If the loop is real, claim retention rises and engineer losses do not.
- If the guard is downstream of pressure, retention is unchanged and this
  falsifies the loop outright, leaving retention as a defensive problem.

Either outcome is worth the run, which is the point of doing it as one step.

---

# Lever 1: built, measured, falsified (2026-09-22)

Payload `cbf11975e7e8` against instrumented baseline `d9d87346e487`, same
eighteen cells, paired at each pair's common horizon.

**The change landed.** A precautionary recall no longer writes an exclusion:

| | baseline | lever 1 |
| --- | ---: | ---: |
| exclusion circles written | 187 | **102** (−45%) |
| `recent-loss` refusals | 5054 | **3289** (−35%) |

**The economy did not move.**

| | baseline | lever 1 |
| --- | ---: | ---: |
| mean claim retention | 0.663 | **0.657** |
| mean peak claim | 23.9 | 23.5 |
| mean final claim | 15.8 | 15.4 |
| mean engineer deaths | 74 | 80 |

Retention improved in 7 cells, worsened in 8, unchanged in 3 — the signature of
a chaotic deterministic simulation reshuffling outcomes around an unchanged
mean, not of a mechanism doing work.

**This is the falsifier firing.** Removing 45% of the exclusion footprint is the
largest change that could be made to the guard short of deleting it, and it
bought nothing: engineer deaths rose slightly and claim retention did not move.
The withdrawal-written exclusion was redundant, but redundant is not the same as
costly. The loop hypothesis — that the guard converts temporary pressure into
permanent forfeiture — is dead.

**Not adopted.** Preserved as `withdrawal-no-exclusion.patch`; tree returned to
the instrumented baseline. The instrumentation itself stays: it is free, it is
contract-pinned, and it is what allowed this to be settled in one run instead of
argued about indefinitely.

## Where the evidence points now

Levers 2 and 3 (`EngineerSurvivalThreatFloor`, the 40/180 circle) are not worth
spending runs on. They are smaller versions of the change that just produced
nothing, and the guard has now been shown not to be the binding constraint.

What survives measurement is the shape of the claim curve: it peaks at minute 10
— first contact — and declines monotonically for the rest of every match, with
no recovery phase anywhere in eighteen cells. Retention correlates with engineer
deaths (rho −0.58) far more than with anything the guard does. Structure
survival is 58–86% for Red Queen against 69–81% for the opponent.

Red Queen takes its half of the map before the enemy arrives and then loses it
piece by piece, and nothing it does afterwards takes any of it back. That is a
defence-and-recapture problem, in the **retain** half of economy.md, and it is
where the next work belongs.

---

# Code investigation: is recapture even expressible? (2026-09-22)

Asked before spending another matrix on it. Answer: **recapture is fully
supported, it is entirely native, and Red Queen's guard can veto it.**

## Red Queen has no extractor code at all

There is no builder, template or job anywhere in `lua/AI/RedQueen/` that builds
a mass extractor. `WorldModel` reads the `Mass` markers only to count them for
`mex=`. Every extractor in every match is built by native FAF.

## Native builds them two ways, and a lost point needs no bookkeeping

`lua/AI/AIBuilders/AIEconomicBuilders.lua` defines a ladder of EngineerManager
builders keyed by **search radius**, priority falling as the radius grows:

| builder | priority |
| --- | ---: |
| `T1ResourceEngineer 40` | 1002 |
| `T1ResourceEngineer 150` | 1000 |
| `T1ResourceEngineer 250` | 970 |
| `T1ResourceEngineer 1000` | 850 |
| `T1ResourceEngineer 450` | 800 |

Radius 1000 covers any of these maps, so expanding to — or retaking — a distant
point is expressible, and at a priority above almost everything else an engineer
could be doing. Placement goes through `AIExecuteBuildStructure`, which for
resources calls the engine's `aiBrain:FindPlaceToBuild(..., 'Enemy', x, z, 5)`.

Separately, `AIUtils.EngLocalExtractorBuild` rebuilds any free mass point within
**25 units of wherever the engineer already is**, and reclaims wreckage and
repairs on the way. It is called from exactly one place, `ReclaimGridAI`, so it
is opportunistic: a side effect of an engineer travelling to reclaim something,
never a reason to go anywhere.

Critically, a destroyed extractor's marker becomes buildable again the moment it
dies — eligibility is just `aiBrain:CanBuildStructureAt('ueb1103', position)`.
**There is no "rebuild" state to implement. Recapture is ordinary expansion, and
native already wants to do it.**

## What Red Queen does to it

`hook/lua/AI/aiutilities.lua` returns false from `EngineerMoveWithSafePath`.
Both native callers respond identically:

```lua
else
    -- we can't move there, so remove it from our build queue
    table.remove(eng.EngineerBuildQueue, 1)
end
```

`lua/platoon.lua:3776` and `lua/aibrains/platoons/platoon-adaptive-engineer-task.lua:791`.
**A refusal does not defer the job or pick a safer one. It silently discards the
queued build.** Red Queen issues roughly 9,800 refusals per match. The extractor
builders are the highest-priority engineer work there is, so they are the jobs
most likely to be sitting at the head of a queue when it is discarded.

Red Queen's other engineer interventions are not in the way: `ApplyEngineerPolicy`
suppresses engineer-*producing factory* builders only and reported `0/45` —
never bound — in every cell of the matrix, and the `EngineerManager.AssignEngineerTask`
hook delays by 50 ticks rather than refusing.

## Correction: lever 1 did not falsify anything

I concluded above that the loop hypothesis was dead. That was wrong, and the
reason is visible in the counters:

| | baseline | lever 1 |
| --- | ---: | ---: |
| `recent-loss` refusals | 5054 | 3289 (**−35%**) |
| `route-unsafe` refusals | 4742 | 6503 (**+37%**) |
| **total refusals** | **9797** | **9792** (**−0%**) |

The two refusal paths are **substitutes**. `RecentlyLethal` is tested before the
threat limit, so removing an exclusion does not admit the request — it just
falls through to the threat test, which refuses it for the other reason. Lever 1
changed which string got logged and nothing else. Total refusals moved by five.

So lever 1 was never a test of the hypothesis: it did not change the quantity
the hypothesis is about. The claim retention result stands as a fact about that
payload, but it carries no evidence either way about whether refusals cap the
economy. **The loop hypothesis is untested, not falsified**, and the earlier
"Levers 2 and 3 are not worth spending runs on" was wrong for the same reason.

The only lever that can move total refusals is the one governing the threat
test — `EngineerSurvivalThreatFloor = 8`, whose own comment admits it is a first
estimate interpolated between two observations. That is the real experiment, and
it now has a specific prediction: refusals fall, discarded build jobs fall, and
claim retention rises — or it does not, and the guard is genuinely not binding.

---

# Guard off: the route guard is not the constraint (2026-09-22)

Payload `1f80dcd5aa3d` — `RouteVerdict` evaluates and counts every refusal it
would have made, then allows the move. Zero "engineer assignment refused" lines
in all 18 logs confirms the hook never refused. All 18 clean through
`analyze-log.py`.

| | baseline | guard off |
| --- | ---: | ---: |
| total refusals | 7960 | **300** (−96%) |
| `recent-loss` refusals | 4160 | 102 |
| engineer deaths | 69 | **123** (+78%) |
| **mean peak claim** | **23.7** | **23.6** |
| **mean final claim** | **15.8** | **15.2** |
| **mean claim retention** | **0.668** | **0.643** |

Retention better in 8 cells, worse in 10.

**This is the falsification lever 1 could not provide.** Refusals fell 96% — the
quantity the hypothesis is about actually moved this time — and the economy did
not: peak claim is identical to within 0.1 of a mass point, final claim and
retention are unchanged or marginally worse, and engineer deaths rose 78%.
Letting engineers walk anywhere costs most of the engineer corps and claims not
one additional mass point.

**The engineer route guard is not what caps Red Queen's economy.** Levers 2 and
3 are dead with it: there is nothing left to tune on a mechanism that can be
removed entirely without moving the outcome.

## The refusal count was never a count of lost opportunities

Counted refusals fell from 7960 to 300 while exclusion sites written nearly
doubled (135 → 264). With more sites on the map, `recent-loss` should fire more
often, not 40× less. The only consistent reading is that `RouteVerdict` was
being *called* far less often — that is, the baseline's ~8000 refusals were not
8000 distinct build opportunities denied, but a tight
assign → refuse → discard → reassign churn on a small number of engineers.

That revises the reading of the earlier matrix. The guard was not quietly
forfeiting thousands of mass points; it was spinning engineers that native kept
handing the same refused job back to. Expensive in engineer time, irrelevant to
claim.

## What this leaves

Peak claim is ~24 of 44–48 points — about half the map — and it is **the same
with the guard fully off**. Red Queen stops expanding at the halfway line
whether or not anything is stopping it, at minute 10, which is first contact.

The remaining suspect is native and engine-side. `AIExecuteBuildStructure` places
resource structures through
`aiBrain:FindPlaceToBuild(buildingType, whatToBuild, baseTemplate, relative, closeToBuilder, 'Enemy', x, z, 5)`
— a threat-filtered placement applied to resources specifically and to nothing
else. A filter that refuses contested ground would produce exactly this shape: a
map that splits at the contact line, expansion that stops there, and a peak that
arrives the minute the enemy does.

If that is the mechanism, Red Queen's problem was never claiming more ground. It
is holding the half it takes — which is where the claim curve pointed from the
start, and where the next work belongs.

**Not adopted.** The guard-off payload costs 78% more engineers for no economic
return; the tree returns to the instrumented baseline.

---

# Confirming the native resource threat filter (2026-09-22)

## The engine signature, authoritative

From `engine/Sim/CAiBrain.lua` in FAForever/fa:

```lua
---- It is considered if `structureName` can be built at this location and,
---- If `optIgnoreThreatOver` is above 0.0, the anti-surface threat influence
---- (calculated using ring=0) is less than `optIgnoreThreatOver`.
----
---- If the builder type is one of `TemplateBuilderTypeResources` ... distance is
---- calculated between `startingLocation` and all nearby deposits (mass points,
---- unless the structure blueprint has the `"HYDROCARBON"` category) are queried
---- and no points in the template are used.
----@param optIgnoreAlliance? AllianceType # defaults to `nil`
----@param optIgnoreThreatOver? integer # defaults to 0 (accept all)
function CAiBrain:FindPlaceToBuild(type, structureName, buildingTypes, relative,
    builder, optIgnoreAlliance, optOverridePosX, optOverridePosZ, optIgnoreThreatOver)
```

The trailing `5` in the resource call **is a threat threshold**, and the default
is 0, meaning accept all. `aibuildstructures.lua:219` is the only call in the
entire codebase that sets it:

```lua
if IsResource(buildingType) then
    location = aiBrain:FindPlaceToBuild(buildingType, whatToBuild, baseTemplate,
        relative, closeToBuilder, 'Enemy', relativeTo[1], relativeTo[3], 5)
else
    location = aiBrain:FindPlaceToBuild(buildingType, whatToBuild, baseTemplate,
        relative, closeToBuilder, nil, relativeTo[1], relativeTo[3])
end
```

Every other structure in the game — factories, defences, power, shields — is
placed with the filter off. **Mass extractors alone are refused on contested
ground, by the engine, at a threshold of 5.** And for resource builder types the
engine ignores the base template entirely and queries the mass deposits directly,
so this filter is the only spatial gate deciding which deposit is offered.

## It is the live path

`platoon-adaptive-engineer-task.lua:645` sets
`buildFunction = AIBuildStructures.AIExecuteBuildStructure` on the default
branch and then iterates `cons.BuildStructures`, which for every
`T1ResourceEngineer *` builder is `{'T1Resource'}`. So the filtered call is the
one our matches take.

The only mex path that bypasses it is `EngLocalExtractorBuild`, which is
opportunistic within 25 units and called solely from `ReclaimGridAI`.
(`whatToBuildM` at line 364 of the adaptive task is a dead local; there is no
second builder-driven path.)

## What is established, and what is not

Established:

- the filter exists, is uniquely applied to resources, and is on the live path;
- Red Queen's own guard is **not** the ceiling — removing it entirely moved
  refusals −96% and peak claim 23.7 → 23.6;
- peak claim is ~50% of the map on both maps and arrives at minute 10, first
  contact.

Not established: that the anti-surface threat at the unclaimed deposits actually
exceeds 5 in these matches. The engine's ring-0 threat influence is a different
measure from the `GetThreatNear` values Red Queen's own policy is scaled
against, so the two thresholds cannot be compared by eye, and no log line
reports either quantity at a deposit.

That is one measurement, and it has a sharp form: `AIExecuteBuildStructure` is
ordinary Lua in `lua/AI/aibuildstructures.lua`, so it is hookable under the
existing rule (hook the file that defines the symbol). Passing
`optIgnoreThreatOver = 0` for resources on Red Queen brains only — the same
value every other structure in the game already uses — predicts peak claim rises
above ~24 if the filter binds, and does not move if it does not.

One interaction to control for: Red Queen's route guard would then refuse the
walk to a contested deposit and discard the job, so a clean first run should
relax both, establishing whether the ceiling is removable at all before tuning
either.

---

# The threat filter refuses nothing (2026-09-22)

Payload `acc05419c5d5`. The probe asks the engine for a resource location twice
— once at the shipped `optIgnoreThreatOver = 5`, once at 0 — and returns the
gated answer, so native receives exactly what it would have received.

**Neutrality:** all 18 cells reproduce the baseline exactly on sample count,
peak claim and final claim. 0 Red Queen Lua failures, 0 scheduler failures.

**Result:** across 18 cells, **171702 resource placement attempts**, and in
**941 of 941 samples `attempts == offered-at-5 == offered-at-0`.** Not one
deposit, in any cell, at any minute, was refused by the threat filter.

```
isis-424242-uef      attempts 15210  gated 15210  open 15210   divergent samples 0
syrtis-424242-uef    attempts 22935  gated 22935  open 22935   divergent samples 0
```

**The engine's resource threat filter is not the ceiling.** The hypothesis is
falsified, and cheaply — one behaviour-neutral run rather than an intervention.

Two further things follow from `gated == attempts`:

1. Native *always* finds somewhere to put an extractor. Placement never once
   came back empty. The supply of offered deposits is not the constraint.
2. It found one five to twenty-three thousand times per match while the army
   held about 24 extractors. That is the same churn the refusal counters showed:
   a deposit is offered, a job is queued, the job does not become an extractor,
   and the cycle repeats.

## Both gates on "where may an engineer build" are now negative

| gate | test | result |
| --- | --- | --- |
| Red Queen's route guard | removed entirely, refusals −96% | peak claim 23.7 → 23.6 |
| engine's resource threat filter | counterfactual measured | refused 0 of 171702 |

Neither decides where Red Queen may claim. What remains is completion: jobs are
created in abundance and do not finish. The guard-off run says what happens when
engineers are allowed to act on them — deaths rose 78% and claim did not move,
so the engineers reach contested ground and die on it.

That is the same statement the claim curve made at the start, now with the
alternatives eliminated: claim peaks at minute 10 because that is when the enemy
arrives, and declines forever after because Red Queen cannot hold ground it has
taken. **The economic ceiling is a military one.** Nothing in the extractor,
routing or placement path will move it, and three payloads have now confirmed
that from three directions.

The remaining untested economic finding is unrelated to claim: `ExpandProduction`
is reached in 33 of 941 samples (3.5%), so Red Queen's own factory expansion is
effectively never active and native builders make nearly every factory decision.
That gate has never been measured.

---

# Independent review: two corrections, both verified (2026-09-22)

An independent pass over the same 18 placement-probe logs
(`/tmp/rq-holding-review/findings.md`) raised two corrections to what I wrote
above. I checked both against the logs myself rather than accepting them.

## Correction 1: the factory-attribution claim was wrong

I wrote that `ExpandProduction` at 3.5% of samples meant "Red Queen's own factory
expansion is effectively never active and native builders make nearly every
factory decision." That does not follow and is contradicted by the logs.

There are **81 `production expansion type=` lines** across the 18 logs
(`ProductionManager.lua:1880`), and that line is written only inside
`if started then` — these are *accepted* Red Queen expansion requests, e.g.

```
production expansion type=T1LandFactory factories=12 desired=21 deficit=0 engineer=1048581 idle=no building=no
```

Two independent errors on my part: a mode occupying 3.5% of *minute samples*
does not bound the time spent in it, because production passes run far more
often than the state line samples; and time-in-mode is not attribution of built
factories in any case. Establishing native ownership would require attributing
completed factory entities to their requests. Not done, and not claimed.

## Correction 2: removing the opening timer unlocks nothing observable

Verified independently. Pairing each in-opening `watch` line with its state line
across all 18 cells:

| condition inside the 240s opening | samples |
| --- | ---: |
| paired samples | 72 |
| storage half of `Surplus` (>0.70 mass, >0.80 energy) | 18 |
| **storage AND income AND spare capacity, simultaneously** | **0** |

The 18 storage-passing samples are all at `t=9` — the spawn, when storage begins
full — with mass income 0.1 against a `MinimumProductionMassIncome` of 0.8. The
binding condition is `Surplus`, not the timer. Minute sampling can miss shorter
opportunities, so this is a negative result on the recorded samples, not a proof
that none exists.

## The holding hypothesis, verified and quantified

The review's code reading is correct, and the structure is sharper than
"coverage is not checked". `FortificationBuilders.NeedsDefense`:

```lua
local position, radius = GetLocation(aiBrain, locationType)   -- base manager coords
if not alert or not alert.Active or not position
    or DistanceSquared(position, alert.AnchorPosition) > math.max(40, radius) ^ 2 then
    return false
end
return aiBrain:GetNumUnitsAroundPoint(category, position, math.max(40, radius), "Ally") < target
```

Both the trigger and the count are **base-centric**. A defence is built only
when the alert is anchored inside a base manager's radius, and the need is
satisfied by any allied structure of that tier anywhere in the same circle —
regardless of which approach it covers.

Measured across the 18 cells:

| | value |
| --- | ---: |
| mean peak base locations | **4.1** |
| mean peak extractors held | **23.7** |
| final bases | 1–4 of 8 |

Roughly four fortifiable locations against twenty-four claimed points. Ground
outside a base manager's radius cannot receive a fortification builder at all —
`GetLocation` returns nil for any location that is not a registered base — so
most of what Red Queen claims is structurally undefendable, independently of any
quantity or coverage question.

That is consistent with every result above: the claim curve peaks at first
contact and declines monotonically, both build-permission gates are negative,
and the ground being lost is ground nothing was ever able to defend.

## Agreed next measurements

1. **Holding**, first: for a threatened resource group, record attack direction,
   completed and in-progress defences, actual weapon coverage, and retained
   extractors. Quantity and coverage are separate treatments and must not be
   bundled — and neither may be bundled with storage or factory changes, which
   is what made the earlier raised-defence experiment unreadable.
2. **Factory eligibility**, separately: per-production-update counterfactual,
   current gate versus timer removed, recording surplus, minimum income, desired
   capacity, domain target, cooldown and builder availability individually,
   followed by attributed completions.

---

# Measurement 1: defence coverage (2026-09-23)

Payload `592e88deaadc`, 18 cells run one at a time (the machine's swap was
exhausted; a match killed mid-run yields nothing). All 18 clean through
`analyze-log.py`. Data preserved in `docs/balance/data/`.

## The guns exist and cannot reach the fighting

Over **632 alert samples across 17 baseline-identical cells**:

| | |
| --- | ---: |
| mean defence structures held | **27.0** |
| mean able to reach the alert | **6.69** |
| alert samples with **zero** coverage | **225 of 632 (36%)** |
| median distance, nearest gun to the alert | 13 |
| extractors lost | 505 |
| **lost with any friendly weapon in range** | **146 (28.9%)** |

**71% of extractors died with nothing able to shoot whatever killed them**, and
in more than a third of alert samples not one of about twenty-seven defence
structures could reach the alert.

This is the spectated observation as a figure, and it is not a quantity problem:
an army holding 27 guns is not short of guns. `NeedsDefense` satisfies a tier's
need with any allied structure of that tier anywhere inside the base radius, and
`BuildClose` puts it next to whatever is already there — so the demand is met
while the approach is uncovered.

The median nearest-gun distance of 13 alongside a mean coverage of 6.69 of 27
says the distribution is bimodal: alerts at the base are covered, alerts
anywhere else are not.

## A third of claimed ground cannot be fortified at all

| mean per cell | |
| --- | ---: |
| peak extractors inside a base radius | 18.2 |
| peak extractors outside every base | **11.1** |

About 38% of what Red Queen holds lies beyond every registered base manager,
where `FortificationBuilders.GetLocation` returns nil and no fortification
builder can be offered the job at all. On Syrtis it is roughly half (15 in / 15
out) against a quarter on Isis — and Syrtis is where retention is worst.

So the holding problem is **three** treatments, not two, and the largest is the
one nothing currently measures:

1. ground outside every base, which is unreachable rather than under-defended;
2. ground inside a base but outside any gun's reach;
3. gun count — the only one the present demand actually controls.

## Limitation: the payload is not fully neutral

Seventeen of eighteen cells reproduce the baseline exactly. `syrtis-424242-uef`
matches for 32 samples and then diverges, and a re-run on the same payload
reproduced that divergence **68/68 samples identically** — so it is a
deterministic consequence of the change, not run-to-run variation. The
simulation's determinism holds; the measurement's neutrality does not.

That cell is excluded from every figure above. The cause is unidentified. The
candidates are `DefenseCoverage`'s calls into engine state — `GetListOfUnits`
inside a unit-destroyed callback, and `pcall(GetLocationCoords)` in `BaseSpan`.
One of them is not the pure query it was taken to be, and that must be resolved
before this module ships alongside anything that changes a decision.

## Next

Measurement 2 — the per-production-update factory eligibility counterfactual —
remains unbuilt and deliberately unbundled from this.
