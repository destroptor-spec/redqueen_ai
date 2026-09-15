# Red Queen plays every map like a small map — 2026-09-07

## What was run

Two long team matches on Seton's Clutch (`SCMP_009`, 1024 / 20 km, 60% water,
24 mass clusters, 8 starts), seed 8675309, Red Queen as Aeon with **one** Red
Queen army among FAF's stock Adaptive brains:

| Layout | Contract | Result | Red Queen K/L | Opposing side |
| --- | --- | --- | --- | --- |
| 3v3 | `allies=3 enemies=3 income=1.00` | defeat, tick 10969 | 0.39 | 0.37 |
| 2v2v2 | `allies=2 enemies=4 income=1.20` | defeat, tick 22037 | 0.35 | 1.02 |

These are the first matches where Red Queen played *with* allies it does not
control. That is the question the symmetric 1v1 sentinels cannot ask, and it
exposed something the 1v1s never could.

## The finding: the economy does not scale with the map

Red Queen's mass income never exceeded **8** in either match. On the same map,
with 24 mass clusters available. For comparison, the same brain reaches 40 to 58
on the 512-size maps it has been tuned against.

The per-army production, with the timing caveat that matters:

**2v2v2** — Red Queen was defeated at tick 22037 and the match ended at 24931,
so every army had within 13% of the same time. This comparison is fair:

| Army | Side | Built | Lost | Killed | K/L |
| --- | --- | --- | --- | --- | --- |
| **Red Queen** | ally | **66k** | 69k | 24k | 0.35 |
| Mendez (stock) | ally | 195k | 207k | 34k | 0.17 |
| Squid (stock) | enemy | 313k | 36k | 169k | 4.64 |
| Damian (stock) | enemy | 351k | 60k | 127k | 2.12 |

Red Queen produced a third of what its own stock ally produced and a fifth of
the strongest opponent, on comparable time.

**3v3** — Red Queen died at tick 10969 and the match ran to 39111, so its allies
had 3.6x longer to accumulate. Its 28k against an ally's 704k is therefore
mostly survival time and **must not** be read as a 25x productivity gap. What
does stand is that it died at 28% of the match length with a peak mass income of
6.0.

## Cause: expansion is hard-blocked by the defence objective

`ProductionManager.lua:2052` refuses to start a forward base whenever the current
objective is `Defend` (or `Recover`, or `Stage`):

```lua
if objective.Type == "Recover"
    or objective.Type == "Stage"
    or objective.Type == "Defend"
then
    self:LogForwardBaseBlocked("objective-" .. string.lower(objective.Type))
    return
end
```

Both matches went to `Defend` early and stayed there — sample 8 of 22 in the
2v2v2, and it never left. The result:

| | forward bases started | established | blocked | dominant blocker |
| --- | --- | --- | --- | --- |
| 3v3 | 2 | **0** | 19 | `objective-defend` (6) |
| 2v2v2 | 1 | **0** | 37 | `objective-defend` (24) |

Zero forward bases established in either match, and the single largest reason is
its own defence objective.

On a 5 km map that coupling is reasonable: if the base is under threat, engineers
should not wander off. On a 20 km map it is fatal. The enemy is far away,
`Defend` is close to permanent once entered, and holding one base concedes most
of 24 mass clusters to opponents who expand freely.

Note this is a different failure from the forward-base problems investigated
before. Terrain is not the blocker, economy is barely the blocker — the AI's own
posture is.

## Second cause: there is no large-naval strategy

Seton's Clutch selects the **`Naval`** profile:

```
profile selected=Naval map=Naval size=20km water=0.60 allies=3 enemies=3
```

Identical doctrine to Sludge — 5 km, 93% water, 3 mass clusters. The profile
table tests `MapType` before size, so once a map is classified Naval or Mixed
its size is never consulted:

| Profile | Condition |
| --- | --- |
| `Naval` | `world.MapType == "Naval"` |
| `Mixed` | `world.MapType == "Mixed"` |
| `LandLarge` | `world.MapKilometers >= LargeMapKilometers` |
| `LandSmall` | `true` |

Size-based scoping exists **only for dry maps**. A 20 km 60%-water map with 24
mass clusters and a 5 km 93%-water map with 3 get the same plan, and the plan was
tuned on the small one.

`GetMaximumForwardBases` does scale with size — `floor(20 / 10)` gives 2 on this
map — but a cap of 2 is moot when 0 are ever established, and 2 would still be
modest for a map with 24 clusters.

## Third observation: opponent count is still unused

Both matches logged their opponent counts, `enemies=3` and `enemies=4`, and the
`2v2v2` correctly earned the outnumbered income multiplier of 1.20. No profile
condition reads either figure. Scoping by opponent number remains unimplemented,
as it was when it was first raised.

## What to fix, in order

1. **Let a defended base still expand.** The block should depend on whether the
   *threat* is near the candidate site or the engineer's route, not on the
   objective's name. `GetObservedRouteThreat` already exists for exactly this
   judgement.
2. **Scope by size on water maps too.** A `NavalLarge` profile, or better, make
   the size test independent of `MapType` so every profile is chosen by terrain
   *and* scale rather than terrain first.
3. **Raise the expansion ceiling for large maps** once 1 and 2 land, and measure
   against the 24-cluster reality rather than a per-10-km rule of thumb.

Each is independently measurable on this map, and the harness now supports it:
`FAF_LAYOUT=3v3` or `2v2v2` against `SCMP_009`.

## Caveat

One run per layout, on one seed, one faction. Earlier work in this project
established that a single seed on this harness can move mass kill/loss by ±0.7
through builder-list divergence alone, so these two results are a diagnosis
rather than a measurement: the mass income ceiling of 8, the zero forward bases
and the `objective-defend` counts are structural facts visible in one run, but
the K/L figures are not yet evidence about any change.


## Expansion and scale changes verified — 2026-09-07

`UpdateForwardBases` now allows `Defend` to reach the existing site selector.
`Recover` and `Stage`, active emergency defense alerts, affordability, cooldown,
and the map cap still reserve resources. Site eligibility uses observed threat
at the engineer's origin, route waypoints and destination; the origin is now
sampled explicitly because a navigation path need not contain it.

Scale is evaluated after terrain for every map. At 10 km and above the profiles
are `LandLarge`, `NavalLarge`, and `MixedLarge`, with completed-tier readiness
enabled. Naval production and shore torpedoes remain enabled on water maps.
Below 10 km, all existing behaviour flags are preserved. This extends the
large-land readiness policy to water maps; its balance value remains unproven.

Two concurrent Seton's cells used the verified development symlink, V8 slot
preferences, and no production tracing. Both selected `NavalLarge` and logged
the correct team contracts. Payload SHA-256:
`6825843b4e43906d1081ad3eab617bc8f8662e78f04ab16c94d08d4d8d7c3b53`.
The three edited runtime sources were also copied to `/tmp/rq-expansion-large-source/`.

| Layout | Seed | RQ / opponent faction | Starts / established | Peak sampled mass | RQ result |
| --- | --- | --- | --- | --- | --- |
| 3v3 | 8675309 | Aeon / Cybran | 3 / 1 | 6.6 | defeat, tick 11309 |
| 2v2v2 | 31337 | Cybran / Aeon | 1 / 0 | 5.4 | defeat, tick 12393 |

Logs and their manifests are `/tmp/rq-m-expansion-large-3v3.log` and
`/tmp/rq-m-expansion-large-2v2v2.log`. Each includes `JsonStats`; isolated test
processes were closed after Red Queen reached defeat.

The 3v3 log records `strategy objective=Defend`, then an emergency alert
clearing, followed by:

```text
forward base started name=RQFB_2_3 site=MassCluster4 tech=1 queued=6 routeThreat=3.3
forward base established name=RQFB_2_3 site=MassCluster4 tech=1
```

No intervening strategy change occurred. The earlier two starts failed through
manager loss and engineer loss. The 2v2v2 also started its base under `Defend`,
with route threat 7.8, but its engineer died after 395 simulation seconds and
the base never established. Neither run logged `objective-defend` as a blocker.
Engineer availability and real emergency alerts remain constraints; removal of
the posture veto alone does not demonstrate a scaled economy.

The 3v3 uses the historical seed and faction pairing, whose earlier result was
2 starts, 0 established and peak sampled mass 6.0. This is structural execution
evidence, not a measured balance gain. The changed seed/faction in the second
cell makes it a variety check, not a paired comparison to the historical
2v2v2. No experimental volume A/B, release bump, or PR change was made.

Validation: `./scripts/validate.sh` and `git diff --check` passed. Tests cover
safe and unsafe expansion under `Defend`, preserved resource reservations,
origin/intermediate/destination threat, remote threats, every terrain on both
sides of the size boundary, and profile isolation using engine-style imports.
Both final log analyses report zero Red Queen Lua or scheduler failures, but
**the complete runtime logs are not clean**: invalid-manager-location failures
occurred 20 times in 3v3 and 41 times in 2v2v2, all after the first defeat.
The historical 3v3 also has this failure class (60 occurrences); the historical
2v2v2 has none. Unattributed FAF Lua failures total 6 and 9 in the new logs,
including the startup `GetBuildLocation` error present in both baselines.
These results validate the changed expansion path and profile loading, while
leaving post-defeat manager failures and the larger economic gap unresolved.

# Follow-up: why the unblocked expansions still fail — 2026-09-08

Removing the `Defend` veto worked. Expansion now starts under `Defend`, sites are
found, and `objective-defend` has disappeared as a blocker. But the economy did
not scale, and the reason is a second, independent defect.

## Sites are not the problem — a correction

An earlier note in this document suspected the land-only path test in
`SelectForwardBaseSite` (`CanPath("Land", ...)`) of starving expansion on a water
map. **That was wrong.** `no-safe-site` appears 0 or 1 times across all six
large-map logs; site selection is finding candidates.

The land-only query is still incorrect on its own terms — every engineer in the
game can cross water, `RULEUMT_AmphibiousFloating` for UEF and Cybran and
`RULEUMT_Hover` for Aeon and Seraphim, at all three tiers — so the right layer is
`Amphibious` or `Hover`, never `Land`. It is simply not what is binding here.

## What is binding: engineers die on routes assessed as safe

Paired against the historical baseline (Seton's Clutch, seed 8675309,
Aeon against Cybran), the 2v2v2 lifecycle reads:

| Base | Site | Route threat at dispatch | Outcome |
| --- | --- | --- | --- |
| `RQFB_2_1` | MassCluster7 | **0.0** | engineer lost after 180s |
| `RQFB_2_2` | MassCluster11 | 11.2 | engineer lost after 15s |
| `RQFB_2_3` | MassCluster2 | **0.0** | engineer lost after 90s |
| `RQFB_2_4` | DEFENSIVE_POINT_93 | 1.5 | established, later destroyed |

Every failure is `reason=engineer-lost`, and **two of the three were dispatched
on routes the AI scored as completely safe.** Across the four large-map runs only
25% to 33% of started bases ever establish.

## Root cause: zero threat and zero knowledge are the same number

`WorldModel:GetObservedRouteThreat` sums `intel:GetThreatNear` over the path.
`GetThreatNear` iterates `self.Observations` — units actually seen, with a
confidence that decays to nothing over `IntelLifetimeSeconds`. There is no
coverage term, so the function returns `0` for all three of:

1. observed, and genuinely clear,
2. never observed at all,
3. observed once, since expired.

`SelectForwardBaseSite` then treats `0` as maximally safe *and rewards it*:

```lua
local score = candidate.Value + progress * 0.35 - routeThreat * 12
if routeThreat and routeThreat <= safetyLimit then
```

A route through unobserved ground therefore always passes the safety test —
`0 <= anything` — and outscores a route that is observed and only mildly risky.
The check is at its most permissive exactly where the AI knows least, and it
filters out only the dangers it can already see. Since an expansion by
construction heads into unclaimed ground, that is precisely the case it fails.

### Why this bites on a large map specifically

The observation *count* is not the problem — Seton's runs carry 153 to 248
observations against 104 to 150 on Sludge. The problem is density. Seton's is
1024 units across against Sludge's 256, so roughly sixty times the area for a
comparable number of observations. With `ForwardBaseSiteRadius = 60`, most sample
circles along a long route enclose nothing at all, and the route scores 0.

Worse, `IntelLifetimeSeconds` is 180 and the observed engineer walks took 90 to
180 seconds. **Travel time is the same order as the entire intel lifetime**, so
even a well-informed assessment at dispatch has substantially decayed before the
engineer arrives. The AI is not just blind about where it is going; it is
reasoning from a picture that expires in transit.

This also explains why removing the posture veto changed structure without
changing outcome. The `Defend` veto was crudely doing a job the threat check
cannot do: keeping engineers at home while the map was dangerous.

## Directions, in rough order of value

1. **Make unknown distinguishable from safe.** `GetObservedRouteThreat` should
   report coverage alongside threat, and an uncovered route should carry a
   presumed risk rather than a zero. Anything else leaves the scoring inverted.
2. **Stop rewarding ignorance in the score.** While coverage is poor, bias
   toward nearer sites instead of toward the objective, so a blind expansion is
   at least a cheap one.
3. **Re-check in transit.** A single assessment cannot survive a 180-second walk
   against a 180-second intel lifetime; the engineer should be recallable when
   the picture changes.
4. **Fix the layer while in here** — `Amphibious` or `Hover` per the engineer's
   motion type, never `Land`. Not binding on Seton's, but wrong everywhere.

## Secondary: the affordability gates are circular on a large map

Roughly half the remaining denials are economic — 17 of 36 in the paired 2v2v2,
8 of 22 in the 3v3 — from `low-mass-storage`, `low-mass-income`,
`negative-mass-trend` and `stall-risk`. On a large map expansion *is* the income
source, so gating it on income is self-defeating in a way it is not on a 5 km
map where income grows without expanding. The new `profile.Scale` field is the
natural place to scope those floors, but this is worth less than the engineer
survival problem above and should follow it.

## Caveat

One paired run per layout, plus a repeat that reproduced the 3v3 exactly
(3 started, 1 established, peak sampled mass 6.6, identical blocker counts), so
determinism holds. The lifecycle and route-threat figures are structural facts
readable from a single run; the mass kill/loss figures are not yet evidence about
any change.

## Measured: the layer was the real fix, presumed risk was not

Three arms on Seton's Clutch, seed 8675309, Aeon against Cybran, one paired run
each:

| Arm | 2v2v2 started/est | peak mass | 3v3 started/est | peak mass |
| --- | --- | --- | --- | --- |
| Land pathing, no presumed risk | 4 / 1 | 12.7 | 3 / 1 | 6.6 |
| Engineer layer + presumed risk 30 | 2 / 0 | **6.7** | 3 / 1 | 6.0 |
| Engineer layer, presumed risk off | 3 / 0 | **11.5** | 3 / 1 | 6.6 |

**Presumed route risk is rejected.** It cost the 2v2v2 a start and dropped peak
mass income from 11.5 to 6.7 while establishing no more bases, and the 3v3 was
insensitive to all three arms. Charging unknown ground a presumed threat brakes
expansion without saving anything, so it has been removed from the gate and the
score. `scripts/validate_mod.py` now fails if it is reinstated without reading
this section.

**The engineer's own navigation layer is kept, and it was the change that
mattered.** Every engineer crosses water — UEF and Cybran are
`RULEUMT_AmphibiousFloating`, Aeon and Seraphim `RULEUMT_Hover`, at every tier —
so `CanPath("Land", ...)` described none of them. With the correct graph the
sampled route is the route the engineer actually walks, and observed route threat
went from `0.0, 0.0, 11.2` to `5.2, 6.5, 4.6, 1.9, 8.2`. The assessment is now
about the real journey.

That also corrects the diagnosis above. The zeroes were not purely a coverage
defect: pathing on a graph the engineer does not use produced a degenerate
sample, and fixing the graph produced real numbers without any presumed risk at
all.

### What still kills the engineers

With the layer corrected and coverage measured, the remaining losses are not
blind:

| Coverage | Observed threat | Safety limit | Outcome |
| --- | --- | --- | --- |
| **1.00** | 5.2 | 15.5 | engineer lost at 75s |
| 0.71 | 6.5 | 74.0 | engineer lost at 175s |
| 0.85 | 4.6 | 35.6 | manager lost at 30s |

Fully observed routes, assessed safe by a wide margin, and the engineer dies
part-way through a walk of 75 to 175 seconds. `IntelLifetimeSeconds` is 180, so
**the assessment is the same age as the journey**. This is staleness, not
ignorance, and it is why braking on uncertainty changed nothing: the picture at
dispatch was right, and then the walk outlived it.

Coverage is still measured and reported on the chosen site, and
`forward base started` now logs `layer`, `coverage`, `effective` and the
`limit` it cleared — the escort strength the gate turns on was previously
invisible, which is why a dispatch at threat 0.0 could not be told from a
dispatch into the dark.

### Next, on this evidence

Re-check the route in transit and recall the engineer when the picture changes.
Nothing else addresses a 175-second walk against a 180-second intel lifetime,
and both cheaper alternatives have now been tried and measured: removing the
posture veto let expansion start, and presumed risk made it start less.

# Transit re-checking and engineer establishment — 2026-09-08

## Transit re-checking works, with a textbook case

A route authorised once cannot carry the journey: observed walks ran 75 to 175
seconds while `IntelLifetimeSeconds` is 180. `ForwardBaseRecallReason` now
re-judges the route every 20 seconds from where the engineer *is*, on the layer
it travels, with a 1.5x margin over the dispatch limit so a committed engineer is
not turned around by noise. A recall clears the engineer's queued structures —
that is what releases it back to its engineer manager — and sends it home.

The 3v3 caught exactly the failure this was built for:

```
forward base started name=RQFB_2_1 site=MassCluster4 tech=1 queued=6
    layer=Hover routeThreat=0.6 coverage=0.25 effective=0.6 limit=15.1
forward base failed  name=RQFB_2_1 site=MassCluster4 reason=route-unsafe
    queued=6 elapsed=225s routeThreat=0.6 nowThreat=70.5 limit=66.4
```

Dispatched at route threat **0.6** and recalled 225 seconds later at **70.5**.
The assessment was not wrong when it was made; the walk outlived it. Before
this, that engineer walked into the 70.5 and the base failed as
`engineer-lost` — which is what happened three times in four in the paired
2v2v2 and twice in three in the 3v3.

**`engineer-lost` is now 0 in both runs.**

## Engineers are established to a target

Losing engineers stalls expansion, economy and production together, and
`RecordUnitLoss` used to discard them outright, so nothing could answer it. They
now have their own loss window — deliberately separate from land loss, which
drives doctrine — and a target:

    DesiredEngineers = production to feed + expansion in flight + replacements

with replacements at 1.5x every engineer lost inside the window, so the army
deliberately runs a surplus while it is bleeding rather than after. The buffer
decays as losses age out, nothing has to cancel it, and the total is bounded at
18 so a sustained bleed cannot spend the whole economy on builders.

The tier gate is deliberately the Tech floor for that tier and nothing stricter.
Waiting for income to recover before replacing engineers is the flatline this
exists to prevent: the shortfall is what suppresses the income.

Observed, as `eng=held/target/recentLosses`:

```
1/2/0  3/2/0  5/2/0  7/4/0  9/3/0  9/5/1  9/9/4  11/9/3
7/13/6  10/14/7  9/12/5  7/18/9  10/12/5  6/16/8
```

The target tracks losses immediately and saturates at the cap under a sustained
bleed. It also exposes something no previous run could show: **9 to 14 engineers
lost inside a two-minute window**, with held sitting at 6 to 12 against a target
of 13 to 18. The demand signal is right and production cannot keep pace — the
army wants engineers faster than it can build them.

## Outcomes, honestly

| Layout | K/L | Opponent |
| --- | --- | --- |
| 2v2v2 | 0.35 | 0.65 |
| 3v3 | 0.39 | 1.19 |

Unchanged, and in line with every arm measured on this map — 0.35 to 0.43 across
six payloads now. The 2v2v2 started no forward base at all this run, which is
divergence rather than a regression.

So both mechanisms are verified to *work*, and neither has yet moved a result.
What they have done is make the real constraint legible: engineers die on this
map far faster than they are replaced, and the recall saves the engineer without
yet buying the expansion.

## What the numbers now point at

The engineer target saturating at 18 while only 6 to 12 are held says the
bottleneck has moved from *deciding* to *producing*. Two candidates, in order:

1. **Land factory throughput.** The engineer builders are gated on
   `BrainNotLowMassMode` and a unit-cap check, and the target is not being met,
   so either factories are busy with combat units or mass is the binding
   constraint. The state line now carries everything needed to tell those apart.
2. **Why engineers die at all.** 9 to 14 losses per window on a 20 km map is not
   a route problem — the recall handles the route. It suggests engineers working
   outside defended ground with no escort, which is a different question from
   the one this work answered.

## The engineer ceiling strangled the economy (measured, then fixed)

The first two cells of the follow-up matrix regressed hard, and the cause was a
change made *for* large maps rather than anything about them.

`ApplyEngineerPolicy` suppressed FAF's native engineer builders once the army
held `DesiredEngineers`. But `DesiredEngineers` is derived from factory count
(`EngineersPerFactory = 0.75`), and engineers are what build factories — so the
policy closed a loop that locks an army at its opening size: few engineers →
few factories → a lower target → fewer engineers.

Two cells, different factions and seeds, same mechanism. Engineers held against
target over the match:

| Cell | Before | After |
| --- | --- | --- |
| `crossfire-aeon-s1` | 5, 15, 20, 22, 29, 33 (target 2-18) | 3/3, 3/3, 3/4, 7/6, 12/12 |
| `crossfire-cybran-s2` | 5, 9, 16, 18, 21, 24 | 3/2, 3/3, 6/3, 8/6 |

After the change engineers tracked the target *exactly*, which is the signature
of a ceiling rather than a preference. Downstream:

| | `crossfire-aeon-s1` | `crossfire-cybran-s2` |
| --- | --- | --- |
| Peak engineers held | 101 → 14 | 31 → 9 |
| Peak factories | 26 → 8 | 13 → 7 |
| Peak mass income | 66.1 → 8.6 | 21.6 → 6.4 |
| Forward bases started/established | 14/3 → 2/0 | 9/2 → 4/0 |
| Mass K/L | 0.92 → 0.39 | 0.35 → 0.42 |

The `no-idle-engineer` blocker went from 4 occurrences to 36, so the expansion
failures on those cells were a symptom rather than the disease.

Note what kill/loss did: it halved on the Aeon cell and *rose* on the Cybran one
(0.35 → 0.42) while that army's economy fell by two thirds. A K/L reading alone
would have called this cell neutral-to-better. What is left of an army after a
starved economy trades reasonably per unit; there is simply far less of it. So
the outcome column is not a sufficient gate on a change that touches
production — the economy figures are the ones that move first.

The cleanest single discriminator is the share of state samples where held
engineers sat at or below target: 1% and 12% before, 57% and 30% after. Held
never exceeding target is what a ceiling looks like from outside, and
`summarize-matrix.py` now reports it per cell for exactly that reason.

(Figures come from the periodic state line's own `mass=` income field. An
earlier draft of this section quoted 347.5 → 128.5, from a `grep 'mass='` that
also matched unrelated fields elsewhere in the log — the same artefact class
that has produced wrong figures here before. Read economy numbers through the
summarizer, not through a bare grep.)

**Fix.** The target stays a floor for Red Queen's own engineer builders;
suppression gets its own ceiling, `max(EngineersMaximum, feeding * 1.5)`, where
`feeding` counts planned factory capacity as well as built. So natives run
freely through the opening, the ceiling rises before the factories stand, and
the 101-engineer runaway the policy was written for is still cut — at 39 on that
economy instead of at 18.

### Why it took a whole matrix to see

The policy left no trace in any log. It was inferable only by noticing that held
engineers tracked the target exactly, across two cells, by eye. The same was
true of forward-base cover, which stood down for 86% of bases behind a Tech 3
filter and logged at Debug — invisible in every behavioural run.

Both now report in the state line (`cover=sites/units`, `engpolicy=suppressed/ceiling`),
with contracts asserting they do. A mechanism that cannot be seen in a match log
cannot be attributed when a matrix moves, and bundling four changes into one run
is only survivable if each one is separately observable.

## Second pass: the ceiling's *floor* was the same defect one step up

Raising the cut from the target to `max(EngineersMaximum, factories * 1.5)`
fixed the severe case and left a milder one, because `EngineersMaximum` is 18 —
the cap on the *target*, reused as the floor of the ceiling. Few factories early
means the per-factory term is small, so 18 became the operative cut on every map
during exactly the phase that decides the game.

Ten cells of the partial run, against their baseline twins:

| cell | result | mass K/L | peak mass | factories | established |
| --- | --- | --- | --- | --- | --- |
| `crossfire-aeon-s1` | defeat → **victory** | 0.92 → 0.99 | 66 → 71 | 26 → 21 | 3/14 → 3/15 |
| `crossfire-cybran-s2` | defeat → defeat | 0.35 → 0.60 | 22 → 44 | 13 → 28 | 2/9 → **4/7** |
| `setons-aeon-3v3` | defeat → defeat | 0.21 → 0.21 | 46 → 48 | 12 → 12 | 0/3 → 1/4 |
| `setons-cybran-3v3` | **victory → defeat** | 1.46 → 0.30 | 70 → **48** | 19 → 22 | 0/4 → 1/7 |
| `saltrock-aeon-2v2v2` | victory → victory | 1.87 → **2.56** | 22 → 62 | 12 → 20 | 0/2 → 2/4 |
| `crashsite-aeon-2v2` | victory → victory | 0.81 → 0.80 | 40 → 42 | 17 → 24 | 1/4 → 3/8 |
| `saltrock-cybran-2v2v2` | victory → victory | 1.23 → **1.75** | 33 → 55 | 13 → 15 | 2/5 → 1/3 |
| `sludge-aeon-s1` | victory → victory | 1.46 → 1.46 | — | — | — |
| `sentry-uef-s1` | **victory → defeat** | 1.44 → 0.34 | 32 → **7.3** | 16 → 9 | 1/2 → 0/0 |

Both regressions are the cells where the cut bound, and only those. Sentry Point
held **exactly 18** engineers against a natural 53, with `held <= target` in 59%
of samples and 126 builders suppressed. Seton's Cybran bound the same way, and
the chain to the loss is traceable end to end: income 70 → 48, so experimental
weight peaked at 41 against a threshold of 35 (baseline reached 86 and 90), so
0 experimentals where baseline fielded 6, so a won game lost.

(Later measurement inverted this reading: across the fourth matrix, cells where
the cut fired averaged +6.0 peak mass against baseline while cells where it
never fired averaged -8.1. The floor calibration below stands on the mechanism
traces -- engineers pinned at exactly 18, income 32.2 to 7.3 -- and not on these
per-cell aggregates. See the correction in docs/forward-base-escort-plan.md.)

Everywhere the cut did *not* bind, the payload improved: peak income rose in six
of seven multi-army cells, factories rose, and establishment went from 8/39
(21%) to 15/44 (34%).

`sludge-aeon-s1` came back byte-identical to baseline — a 5 km map that ends
before any of this engages, and a useful null.

**Calibration, now grounded.** Native engineer counts across ten baseline cells:
24, 35, 44, 51, 53, 55, 56, 63, 66, 101. Every one but the last is an army that
was not in trouble for having them. `EngineerSuppressionMinimum = 45` sits above
the pack and below the outlier, so nothing binds at ordinary counts and the 101
runaway is still halved. A structural guard in `validate_mod.py` fails the build
if that floor drops back into the measured range — Lua specs stub `Constants`
and cannot see the shipped number, which is why the first two calibrations
shipped green.
