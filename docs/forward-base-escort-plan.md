# Forward-base escort — plan

## Why

Across the 21-cell matrix, forward bases start and do not finish:

| Case | Started | Established |
| --- | --- | --- |
| `crossfire-aeon-s1` | 14 | 3 |
| `crossfire-cybran-s2` | 9 | 2 |
| `setons-cybran-3v3` | 4 | **0** |
| `saltrock-aeon-2v2v2` | 2 | 0 |

A 21% establishment rate is the binding constraint on large maps. Route safety is
already handled — the transit re-check turns an engineer around when the route
sours, and `engineer-lost` fell to zero once it landed. What is missing is cover
at the destination: an engineer arrives alone and builds a factory, a radar and
several defences from a standing start, and anything that wanders past kills it
before the first point defence finishes.

Defences cannot hold a position that never gets built. So a portion of the
combat force escorts the engineer until the base can defend itself.

## Shape

An escort is a **reservation over existing units**, not a new unit type and not a
new platoon. Units are drawn from the same pool offensive waves use, marked
reserved, and excluded from offensive selection while they hold the site. That
keeps one source of truth for what the army has available.

State lives on the forward-base record, which already tracks
`Preparing → Building → Established / Failed`, so the escort's lifetime is the
base's lifetime and nothing has to be reconciled separately.

## Sizing: a portion, never a raid

`EscortFraction` (0.25) of currently available combat units, bounded by
`EscortMinimum` (2) and `EscortMaximum` (8), and scaled up by observed threat at
the site so a contested expansion is covered more heavily than a quiet one.

Two hard rules:

- **Never strip the home defence.** The escort is taken after
  `AttackReserveFraction` is honoured, and never from a layer that a live defence
  alert is drawing on.
- **Never send fewer than `EscortMinimum`.** Sending one unit into a threatened
  site repeats the piecemeal-feeding regression recorded at
  `CombatManager.lua:265` — match 27741743 built 998 land units, lost 1005 and
  killed 141 doing exactly that. If the escort cannot be formed at minimum
  strength, the expansion waits rather than going uncovered.

## Release conditions

Four outcomes, all of which must release the reservation. A held escort that is
no longer protecting anything is worse than no escort, because those units are
invisible to every other decision.

### 1. Base established — the base can defend itself

Released when the site holds the defences its own package specified, not a fixed
list. `ForwardBasePackage` differs by tech and **the Tech 1 package contains no
shield at all**, so a rule demanding "point defence and shields" would strand a
Tech 1 escort permanently.

Concretely: released when, within `ForwardBaseSiteRadius` of the site,

- completed `STRUCTURE * DEFENSE * DIRECTFIRE` ≥ `EscortReleaseDefenses` (2), and
- completed `STRUCTURE * SHIELD` ≥ 1 **if and only if** the queued package
  contained a shield.

Measured on *completed* structures. A queued or half-built point defence does not
shoot, and the readiness lesson from the tier policy applies here too: capability
is not the same as capacity.

### 2. Base destroyed or failed

Released the moment the record leaves `Building` for `Failed`/`Destroyed`, on any
cause — engineer lost, manager lost, route recalled, timed out. There is nothing
left to protect, and the units should be back in the pool on the same cycle.

### 3. Rapidly declining — heavy escort losses  *(implemented)*

Released when the escort is being destroyed faster than it is achieving anything:
escort losses within `EscortLossWindowSeconds` (60) exceed `EscortLossFraction`
(0.5) of the units committed.

This is a withdrawal, not a reinforcement trigger. Feeding more units into a
site that is killing them at that rate is the same mistake as piecemeal
offensive commitment, and the record is marked `escort-overwhelmed` so the
outcome is distinguishable in a log from a base that simply failed.

### 4. Site threat exceeds what the escort can answer  *(implemented)*

Released when observed enemy threat at the site exceeds escort strength by
`CommitmentThreatRatio` (1.10) — the same ratio the offensive commitment gate
already uses, so cover and attack judge strength the same way.

**Ordering matters, and got this wrong once.** Condition 4 must weigh the escort
that *would* go, not the one already standing there. Judged before selection,
strength is 0 on the first cycle, so any observed threat refuses cover outright
and a site covered while quiet is abandoned the moment anything appears. In game
that showed as 11 releases reading `units=0 losses=0` across one pair of
matches: cover happened only where there was nothing to cover against, and one
site had four units walk out and straight back. The strength test therefore sits
after candidate selection, on `held + prospect`, and the loss test stays before
it because it needs no candidates.

Both are implemented in `CombatManager:MaintainForwardGarrisons`, keyed on
`ProductionDemand.GarrisonLossPressure` (per-site, windowed by
`GarrisonLossWindowSeconds`) and on `GetSiteThreat`, which uses the same radius
and ratio as the offensive commitment gate. Losses win the tie so the reported
reason is deterministic, and a released site is not counted as covered.

## Reinforcement

Two triggers, both requiring the base to still be viable:

- **Under siege.** Observed enemy threat at the site exceeds own threat there,
  but by less than the withdrawal ratio. Top the escort back up to its sized
  strength, capped at `EscortMaximum`.
- **Declining.** Escort losses are accumulating but below the withdrawal
  fraction. Same top-up.

Reinforcement is bounded by the same "portion, never a raid" rules as the initial
escort, and is refused outright while a defence alert is active at the main base:
a forward base is not worth losing the base that builds them.

The distinction between reinforce and withdraw is deliberately a threshold on the
same two measurements, so there is no state where both apply.

## What this must not do

- Hold units after the base is gone, in any of the four outcomes.
- Count reserved units as available for offensive waves — that would let one unit
  be committed twice and silently weaken both decisions.
- Strip the home defence, or draw from a layer answering a live alert.
- Send an under-strength escort rather than waiting.

## Acceptance

Contracts, in `tests/production_manager_spec.lua` and
`tests/combat_manager_spec.lua`:

- A reserved unit is excluded from offensive task-force selection, and returns to
  availability on release.
- Each of the four release conditions fires, and each is reported with its own
  reason.
- Release on established requires *completed* defences, and requires a shield
  only when the package contained one — a Tech 1 base releases without a shield.
- An escort that cannot reach `EscortMinimum` defers the expansion instead of
  going out short-handed.
- Reinforcement tops up under siege, and withdrawal wins once losses cross the
  fraction — with no input where both fire.
- A live main-base defence alert refuses reinforcement.

Structural guards: escort sizing must consult available units and the reserve
fraction rather than a constant; release must not test a hardcoded structure
list; reserved units must be excluded at the point of selection rather than
filtered after.

Behavioural check on `SCMP_024` (Crossfire, 14 started / 3 established) and
`SCMP_009` 3v3 (4 / 0), judged on establishment rate rather than kill/loss —
one paired run is enough to move a 21% rate, and not enough to read a K/L
difference on this harness.

## Sequencing

1. Reservation and exclusion from offensive selection — nothing else works
   without it, and it is independently testable.
2. Sizing and dispatch on forward-base start.
3. The four release conditions.
4. Reinforcement.

Each step leaves the tree green and measurable on its own.

# Tiered forward-base packages — plan

## Two defects in the current package

**The factory is built before anything that shoots.** Every tier leads with
`T1LandFactory` then `T1Radar`, and only then defences. The Tech 1 package in
full is:

```
T1LandFactory, T1Radar, T1GroundDefense, T1GroundDefense, T1AADefense, T1AADefense
```

So an engineer arriving at a contested site spends its most exposed minutes
erecting a 240-mass factory and a radar, neither of which can defend it, and
reaches its first point defence last. That ordering is backwards for a site the
army does not yet control, and it is a plausible part of the 21% establishment
rate on its own.

**The order is not even guaranteed.** The queue loop is
`for _, buildingType in pairs(package)`. `pairs` gives no ordering contract —
`ipairs` does. Build order matters here, and simulation logic has to be
deterministic, so this must be `ipairs` regardless of what the order is changed
to.

## Principle: time to first defence

A forward base is only worth its engineer once something at the site shoots
back. So each tier **leads with the cheapest defence it can raise**, and adds its
heavier pieces behind that. Tech 1 point defence is 250 mass against a Tech 2's
540, so on a contested site two Tech 1 guns up early are worth more than one
Tech 2 gun up late — and they are what lets the escort go home sooner.

This is also why higher tiers keep Tech 1 pieces in the mix rather than
replacing them outright: the mix is a build-order decision about what is
shooting at minute one, not a quality judgement about the finished base.

## Tiers

Each tier is an ordered list, and each declares the **minimum viable set** that
marks it defensible — which is exactly what the escort release condition keys
on, so the two plans share one definition.

### Tier 1 — a foothold

Order: `T1GroundDefense ×2`, `T1AADefense ×1`, `T1LandFactory`, `T1Radar`,
`T1AADefense ×1`.

Minimum viable: **2 point defences, 1 anti-air.** No shield — Tech 1 has none,
and a release rule demanding one would strand a Tech 1 escort permanently.

### Tier 2 — a position that holds

Order: `T1GroundDefense ×2` (fast cover first), `T2GroundDefense ×2`,
`T1AADefense ×1`, `T2AADefense ×1`, `T2ShieldDefense`, `T1LandFactory`,
`T1Radar`, `T2GroundDefense ×1`, `T2MissileDefense`, `T2Artillery`.

Minimum viable: **2 Tech 2 point defences, mixed anti-air, 1 Tech 2 shield.**
The Tech 1 guns are deliberately kept: they are up while the Tech 2 pieces are
still building.

### Tier 3 — a position that projects

Order: `T1GroundDefense ×2`, `T2GroundDefense ×2`, `T2AADefense ×1`,
`T2ShieldDefense`, then the heavy tail — ground defence to the faction's best
available tier, `T3AADefense ×2`, a shield upgrade where the faction has one,
`T2StrategicMissile ×2`, `T2Artillery ×2`, `T3StrategicMissileDefense`.

Minimum viable: **at least one Tech 2 shield or better, and more than a handful
of Tech 2 or better point defences** — taken as 5.

## Faction availability, verified

The composition must not name a structure a faction cannot build, or the queue
silently drops entries:

- `T3GroundDefense` is **UEF only**. Other factions cap at `T2GroundDefense`,
  which the current code already guards with `FactionIndex == 1`.
- Cybran aliases `T3ShieldDefense` to its Tech 2 shield, so "one Tech 2 shield or
  better" is satisfiable for every faction but is not the same structure.
- `T2Artillery` has a **50 minimum radius** — a dead zone around the gun. It
  belongs in the heavy tail placed back from the threatened edge, never as
  early cover.

## Interaction with the escort

The escort release condition becomes: **the site holds its tier's minimum viable
set, complete.** That replaces the fixed "2 point defences plus a shield if the
package had one" in the section above, and is strictly better — the requirement
now comes from the same table that decides what gets built, so the two cannot
disagree.

Measured on completed structures, for the reason already given: a half-built gun
does not shoot.

## Acceptance

- Every tier's ordered list leads with a defence, not a factory or radar.
- The queue iterates with `ipairs`, and a contract asserts the first queued
  structure of each tier is a defence.
- Each tier's minimum viable set is satisfiable from its own list — no tier can
  demand something it never queues.
- Tier 1's minimum contains no shield.
- No tier names `T3GroundDefense` for a non-UEF faction.
- Escort release consults the tier's declared minimum rather than a literal
  structure list.

Behavioural check on the same two cells as the escort work, judged on
establishment rate and on time-to-first-defence, which the forward-base log line
should report alongside the existing route figures.

## Sequencing

Ahead of the escort work, not behind it: the escort's release condition depends
on the tier minimum, and defence-first ordering may move the establishment rate
on its own — which would tell us how much of the 21% is exposure and how much is
cover. Doing it first keeps those two effects separable.

## Open: what "established" should mean after defence-first ordering

`UpdateForwardBaseStatus` marks a site `Established` when a factory exists, and
fails it `no-factory` at `ForwardBaseEstablishSeconds` (15 minutes) otherwise.
That marker predates defence-first packages, which move `T1LandFactory` to
fourth in the Tier 1 order — so the marker now arrives later by design, and
`no-factory` became the leading failure cause on the first corrected cell
(2 of 4 losses, against 0 at baseline).

This matters beyond bookkeeping: a failed record is retired, and a retired
record gets no garrison — so a site holding two guns and an AA, which is
precisely what the tier calls defensible and what the escort release condition
keys on, is abandoned by cover at the timeout for not yet having a factory.

Options, none applied yet — the measurement in flight uses the same marker as
its baseline, so the comparison stays sound and the recorded rate is if anything
conservative:

1. Establish on the tier's declared minimum viable set, which is already the
   escort release definition, and let the factory follow. Needs care:
   `active.Factory` and `FactoryPresent` are consumed elsewhere, including by
   `RevalidateEstablishedForwardBases`.
2. Start the establishment clock at the first completed defence rather than at
   dispatch, so travel and early cover do not consume the window.
3. Raise the window, which treats the symptom and hides slow sites.

Prefer 1 with 2 as a fallback: the point of the tiering was that a defensible
position is worth holding before it is a productive one.

## Measured: cover sizing was the regression (2026-09-08)

Three full 21-cell matrices, same cells, against the pre-tiering baseline:

| payload | record | exp built | SACUs | established | mean K/L | mean peak mass |
| --- | --- | --- | --- | --- | --- | --- |
| baseline | 12W/9L | 9 | 27 | 28% | 1.25 | 28.0 |
| + engineer floor fix | 9W/12L | 2 | 22 | 25% | 1.08 | 24.2 |
| + endgame wealth | 8W/13L | 1 | 18 | 24% | 1.11 | 22.2 |

The win/loss swing alone is not significant (sign test p = 0.22). I read the
five measures moving together as corroboration, and that was wrong -- they are
not independent. See the correction at the end of this section: 91% of the
kill/loss swing came from two cells, and excluding them the mean delta across
the other nineteen was -0.025. The cover finding below survives because it was
tested directly, not because the aggregates pointed at it.

It was not the engineer policy: the economy fell in cells where the cut never
fired (`setons-aeon-3v3` 46 → 14 peak mass, `sweepwing-uef-s1` 27 → 10). It was
not package size either — the baseline already queued 12 structures at tech 2
and 17 at tech 3, so defence-first reordering changed the order, not the cost.

It was **cover**, sorted by how much of it each cell committed:

| peak cover | cells | mean ΔK/L | mean Δpeak mass |
| --- | --- | --- | --- |
| 6 or more units | 7 | **-0.30** | **-19.7** |
| fewer than 6 | 14 | -0.11 | **+4.1** |

The heaviest cell committed 14 units and lost 0.74 kill/loss and 35.3 income.
The cause is a mismatch I introduced: widening eligibility from Tech 3 to the
whole land army while leaving the counts (4, or 6/10 undefended) that had been
sized for a Tech 3-only pool. On a twelve-unit army, ten units is not a
garrison.

**Fix, and it is the sizing this plan specified from the start.** A portion of
the eligible force — `GarrisonForceFraction` 0.15, doubled at a site still below
its tier minimum — bounded to [2, 8] units, with the product of fraction and
multiple acting as one budget across all sites so three sites cannot each take a
share. Below the minimum nothing is sent at all: the site waits rather than
feeding units in one at a time.

Guarded structurally, because a Lua spec stubs `Constants` and cannot see the
shipped fraction: `validate_mod.py` fails if fraction times multiple exceeds
0.35 of the army.

### Correction: the aggregates did not show a regression

A fourth matrix, with the sizing fix, closed the loop:

| payload | record | exp | SACUs | established | mean K/L | mean peak mass |
| --- | --- | --- | --- | --- | --- | --- |
| baseline | 12W/9L | 9 | 27 | 28% | 1.25 | 28.0 |
| + engineer floor | 9W/12L | 2 | 22 | 25% | 1.08 | 24.2 |
| + endgame wealth | 8W/13L | 1 | 18 | 24% | 1.11 | 22.2 |
| + cover sizing | 8W/13L | 3 | 17 | **29%** | 1.00 | 25.3 |

Establishment recovered above baseline, which is what the tiering and cover work
was for. But the kill/loss column is not the broad decline it looks like:

| contribution to the -5.21 total K/L swing | |
| --- | --- |
| `sludge-seraphim-s2` (4.15 → 0.48) | 70% |
| `sludge-cybran-s1` (3.34 → 2.28) | 20% |
| **those two cells together** | **91%** |
| mean delta across the other nineteen | **-0.025** |

And `sludge-seraphim-s2`'s own sibling on the same map, same payload, went the
other way: `sludge-seraphim-s1` 2.54 → 4.05, +1.51. A 5 km map that resolves in
ten minutes swings hard on small divergences.

Two hypotheses were tested against this run and **falsified**:

- *Cover drives the losses.* The cells that flipped to defeat here mostly
  committed little or no cover: `saltrock-cybran` 0 units, `sentry-aeon-s1` 0,
  `sludge-seraphim-s2` 2, `syrtis-aeon-s3` 2.
- *The engineer cut drains the economy.* Inverted, in fact. Cells where the cut
  fired averaged **+6.0** peak mass and +1.2 engineers against baseline; cells
  where it never fired averaged **-8.1** and -13.1.

So on this harness, 21 single-seed cells cannot resolve a three-win difference,
and a mean of a heavy-tailed per-cell ratio is not a safe summary either.
Resolving a change this size needs several seeds per cell, not more cells.

What the four runs did establish are four defects with mechanisms confirmed end
to end -- engineer strangulation at two calibrations, cover over-commitment,
strength judged before selection, and the readiness gate on endgame commitment.
Those are the results worth keeping.

The endgame wealth term is kept but is close to inert at these incomes — it
raised threshold crossings from 36 to 41 across 818 samples, because full wealth
needs about 55 mass income and the matrix median peak was 22-28. That is the
real finding for endgame commitment: **income is the constraint, not the gate.**
