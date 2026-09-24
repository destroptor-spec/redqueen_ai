# Economic expansion — adopting the community playbook

## Aim

The human playbook, as endorsed: claim mass points to the limit of map control,
reclaim early, upgrade one extractor at a time once the military position is
stable, keep build power on factories rather than hoarding engineers, and build
more power than strictly needed. Evidence and sources:
`docs/economic-expansion-research.md`.

It is understood this will not work well out of the gate. Each step below is
therefore separately measurable, and the ordering exists so a step that fails
can be reverted without taking the others with it.

## The structural finding this plan is built on

**Red Queen's economy is broadly healthy. The deficit is conversion, not
income.** Two earlier drafts of this section claimed otherwise and both were
measurement errors; the corrections are recorded below because the wrong
diagnosis was acted on twice.

### What the corrected data says

Per Red Queen army, across 21 armies in the instrumented matrix:

| measure | value |
| --- | --- |
| peak extractors held, as a share of the map's mass points | **40%** |
| extractors built | 617 |
| extractors lost | 250 |
| **churn (lost / built)** | **41%** |
| large collapses (a fall of 3+ in one sample) | **~1 per army per match** |

Peak capture of 40% is at or above a fair share on almost every cell — 44-72%
on 1v1 maps where a fair share is 50%, 25-49% on 2v2 maps where it is 25%. The
exceptions are the two Seton's cells at 14-15% against a 17% fair share.

Churn of 41% is real: roughly two of every five extractors built are replacing
one that died, so expansion effort partly runs in place. But its association
with losing is weak — 56% wins below 0.40 churn against 38% above, on n=9 and
n=8. That is a hint, not a finding.

Against that, the conversion deficit is unambiguous: on all eight land 1v1
cells Red Queen produces fewer kills per mass than the stock AI it is fighting
(0.56-0.97, mean ~0.78), while reclaim is comparable (10.7% against 9.5%) and
waste negligible (0.4%).

### Correction 1: the "cannot hold" sawtooth was an artefact

An earlier draft reported that one Crossfire match contained **46 separate falls
of three or more extractors**, and concluded that Red Queen could claim but not
hold. That was wrong. A team match has *several* Red Queen armies each logging a
state line, and the `grep` behind that figure pooled them — so army 2's count
alternating with army 3's manufactured a sawtooth out of two healthy growth
curves. Filtered to one army the same match shows **0 such falls**.

### Correction 2: mean-held over peak-held is not a retention measure

The same draft proposed "retention" as mean held over peak held, and quoted 0.55
as evidence of attrition. A series growing from zero to its peak yields 0.5-0.7
by construction, so a healthy economy scores the same as a raided one. The
metric measured the shape of a growth curve, not loss. `summarize-matrix.py` now
reports churn instead, with both traps documented in the source so they are not
repeated.

### Correction 3: expansion is not capped by the forward-base limit

The first draft claimed the forward-base cap
(`min(MaximumForwardBases, floor(mapKm / 10))`, 2 on a 20 km map) was the
economic ceiling, from reading a mid-game sample as a plateau. Peak capture of
40% refutes it: extractors are not confined to base radii to anything like that
degree.

### What this means for the plan

The economy work below is **demoted, not abandoned**. Churn at 41% is worth
reducing and the Seton's cells are genuinely under-captured, but neither is the
main deficit, and no economy change can pay for a 0.78 exchange rate. Step 2b —
map control, which is the conversion problem — is now the primary line, with 2a
as a cheap experiment and 2c valuable on its own terms as an income sink where
expansion genuinely is denied.

## Step 1 — measurement (done)

`mex=held/total` is now in the state line, from `WorldModel.MassPointCount` and
`GetCurrentUnits(STRUCTURE * MASSEXTRACTION)`, contracted in
`tests/world_model_spec.lua` and `tests/diagnostics_spec.lua`.

Without it there was no way to tell an army that cannot expand from one that has
already taken everything within reach. Baseline figures across the matrix are
being collected now.

## Step 2 — hold what is claimed

Two candidate answers, and they are not exclusive.

**2a. Minimal static defence at claimed clusters (cheap, measurable now).**
A claimed cluster outside every base's defended radius currently has nothing.
The tiering work already defines what a bare foothold needs and it is the first
three entries of the Tier 1 package: `T1GroundDefense ×2, T1AADefense`. Placed
at a cluster rather than at a base, that is roughly 630 mass to protect
extractors producing 10+ mass/s.

Note the economics honestly: a T1 point defence costs 250 mass and the five
extractors it covers cost 180. Static defence costs more than the thing it
protects — it is justified only by the *income* it preserves, which is the
whole argument. One prevented raid pays for it in about a minute. A cluster
raided repeatedly is worth defending; one never touched is not, which argues for
placing defence reactively where losses have actually occurred rather than
everywhere.

Gate it on observed loss: Red Queen already tracks losses in windows, so a
cluster that has lost extractors recently is the one that earns a gun. That also
makes it self-limiting on a quiet map.

**2b. Army-based map control (the real answer, and the harder one).**
The drops coincide with defence alerts, which means enemy forces are reaching
economic ground unopposed. This is the conversion problem
(`docs/economic-expansion-research.md`) and it is not solved by economy work at
all. Kept on the table deliberately: if 2a raises `mex=` retention and outcomes
do not move, 2b is where the remaining loss lives.

Measurement for either: **churn** — extractors lost as a share of extractors
built, per army, currently 0.41 across the matrix and ranging from 0.08 to 0.71
by cell. Not peak capture, which is already healthy, and not mean-over-peak,
which measures a growth curve rather than a loss.

Contracts for 2a: a cluster with recent extractor losses is preferred over a
quiet one; a cluster inside an existing base's defended radius is skipped; the
queue contains point defence and anti-air only, no factory or radar; placement
is deterministic on ties.

## Step 2c — support commanders when expansion is denied

Endorsed as a late-game option: SACUs are viable when income is mid-to-high and
expansion is not available because of enemy pressure. The measurements support
that framing precisely, and it fills the gap Step 2a and 2b leave open — what to
spend income on while the map is contested.

**What already exists.** `RedQueenSupportCommanderBuilders` builds SACUs from a
Quantum Gateway at priority 900, capped at 6 alive, gated on economy efficiency
and not-low-mass; `Red Queen Quantum Gateway` at 910 builds the gate itself,
deliberately bypassing FAF's own gate (which requires already owning more than
one experimental — a threshold no Red Queen match had reached). The template
produces a plan-less support commander so it returns to the pool and is claimed
as build power.

**What it does, measured across 21 cells.** SACUs appear only where income
allows, which is the right shape:

| | cells | mean peak mass income |
| --- | --- | --- |
| built at least one SACU | 6 | **43.5** |
| built none | 15 | 18.0 |

The three highest-income cells built 7, 3 and 3. So the income half of the
condition is already honoured. What the builder does **not** know is the second
half — whether expansion is being denied.

**The change.** An `ExpansionDenied` signal, derived from data Red Queen already
has: forward-base attempts blocked by pressure (`defense-alert`, `route-unsafe`)
within a window, or extractor losses within a window above a threshold — the
same per-cluster loss accounting Step 2a needs. When income is above the
mid-game gate *and* expansion is denied, raise SACU priority (by priority, never
by definition — `Builders` is shared across armies) and let the cap breathe.

**RAS, and two corrections found while checking it.**

First, `RAS` is not an enhancement — it is an *enhancement preset*. The
blueprint carries both: `RAS` (a preset with `Enhancements = { "ResourceAllocation" }`,
a name and a description) and `ResourceAllocation` (the real enhancement, with
the cost and the production). Issuing `"RAS"` through `EnhanceAI` would match
nothing and silently do nothing — the same failure mode as the `T2AttackTank`
template that built nothing and logged nothing.

Second, and better: presets are **directly buildable**.
`Blueprints.lua:HandleUnitWithBuildPresets` registers each preset as its own
blueprint with id `<base>_<preset>` lowercased and cost equal to base plus
enhancement, so `ual0301_ras` is a single 6450-mass build from the gateway with
no post-build enhancement thread, no waiting on completion and no
partially-upgraded state. That is a one-line `PlatoonTemplate` entry.

Third, a faction gap that must be gated, verified against all four blueprints:

| SACU | `ResourceAllocation` | `RAS` preset | `Rambo` preset |
| --- | --- | --- | --- |
| `uel0301` UEF | yes | `uel0301_ras` | yes |
| `ual0301` Aeon | yes | `ual0301_ras` | yes |
| `url0301` Cybran | yes | `url0301_ras` | yes |
| `xsl0301` Seraphim | **no** | **none** | yes |

**Seraphim cannot do RAS at all** — no resource enhancement and no preset. So
the economic SACU is a three-faction option and Seraphim needs a different
answer under the same conditions: a combat preset, which every faction has
(`Rambo`, plus `AdvancedCombat`/`NanoCombat`/`Missile` for Seraphim
specifically). This is the same class of gap as `T3GroundDefense` being UEF-only
and `T3NavalDefense` Cybran-only, and it must be a faction-gated builder rather
than one template with a missing squad.

| | mass | gain | payback |
| --- | --- | --- | --- |
| SACU | 1950 | build power + a tough combat unit | — |
| + `ResourceAllocation` | 4500 | +10 mass/s, +1000 energy/s | 645 s on mass alone |

Counting the energy at what a T3 generator would cost for 1000 e/s (~1296
mass), the effective payback is about 515 s. That is **worse than a T2 extractor
upgrade (225 s) and far worse than a new T1 extractor (18 s)** — so RAS is never
the best economy available. It is the best economy available *when the better
options need ground you cannot hold*, which is exactly the stated condition, and
it is unraidable: Red Queen's extractor retention is 0.55, an RAS SACU's is
whatever its own survival is.

Applying it needs no new engine interaction and, given the preset finding, no
enhancement thread either — the preset blueprint id in a platoon template is
enough. `EnhanceAI` (`platoon.lua:418`, taking
`PlatoonData.Enhancement = { "ResourceAllocation" }`) remains the fallback for
enhancing a SACU that already exists.

**Contracts.** SACU priority rises only when income is above the gate *and*
expansion is denied, and neither alone is enough; the economic preset is offered
only to the three factions that have it, with Seraphim taking a combat preset
instead; and a structural check asserts every preset blueprint id the mod names
exists in the game's own data, so a renamed or absent preset fails the build
rather than producing an empty template. `scripts/check-experimental-catalog.py`
already does exactly this job for experimentals and is the model.

**Measurement.** SACUs fielded, and mass income under sustained pressure, on
the high-income cells (`crossfire-aeon-s1`, `crossfire-cybran-s2`,
`saltrock-aeon-2v2v2`) where the condition can actually be met. Not win rate —
n is far too small there.

## Step 3 — upgrade discipline

The natives already have 58 upgrade builders. The community rule they do not
express is *when*: upgrade one at a time, and only while the military position
is stable. Red Queen already knows both things — it has a defence-alert state
and a loss-pressure window — so this is a priority modulation, not new
construction: suppress economy upgrades by priority while an alert is active or
losses are accumulating, and allow them otherwise.

Note the arithmetic disagrees with the community on one point: T1→T2 pays back
in 225 s and T2→T3 in 383 s, but a *new* T1 extractor pays back in 18. So
upgrades should never compete with unclaimed points — claim first, upgrade with
what is left.

There is a sharper reason to be careful here given the retention finding: an
upgrading extractor runs at negative mass and represents 900 mass standing on
ground Red Queen demonstrably struggles to hold. Upgrade discipline should key
on whether *that cluster* has been losing extractors, not only on the global
alert state.

## Step 4 — hydrocarbons, then T3 storage adjacency

Hydrocarbon is 0.625 energy/s per mass against a T1 generator's 0.267 — 2.3×,
and there are only ever a handful on a map. Prefer them where they exist.

Storage adjacency pays back in 89 s around a T3 extractor, 267 s around a T2 and
800 s around a T1 — so it is worth doing only on T3, and only once T3
extractors exist in numbers, which on this matrix they mostly do not. Last, and
skippable.

## What stays with the natives

Reclaim (already 10.7% of income against opponents' 9.5%), mass fabricators
(worse than upgrades and power-hungry, on both community consensus and the
arithmetic), and general power generation. Red Queen modulates priority; it does
not need its own builders for these.

## Risks

- **Far-flung extractors die, and that is partly fine.** At 36 mass an extractor
  that runs for 30 seconds has paid for itself, so losing the occasional one is
  not the problem — losing a third of them 46 times in a match is, because the
  income never compounds. The distinction that keeps this coherent with the
  cover work: a *building* placed once at a repeatedly-raided cluster is a fair
  trade, a *tank* held there permanently is not, and cover sizing already caps
  the latter at a portion of the force.
- **Engineer diversion.** Claiming competes with factory assist and forward
  bases for the same pool. Bounded by concurrency, and the engineer accounting
  already reports held against target.
- **It may not help.** The land conversion deficit (~0.78 kills per mass against
  the stock AI) means economy is spent at a worse exchange rate than the
  opponent's, and the retention finding says the same thing from the other side.
  If retention improves and outcomes do not, that is informative rather than a
  failure, and it points at 2b — army-based map control — as the remaining work.
- **Static defence is a mass sink if placed everywhere.** 630 mass per cluster
  across a dozen clusters is a factory's worth of army. Reactive placement, gated
  on measured loss at that cluster, is what keeps it honest.
