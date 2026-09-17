# Objectives: primary, secondary, and how force is split between them

Working document. Nothing below is measured unless it says so.

## Why the foundation changes

Red Queen holds exactly one objective. `Strategy.CurrentObjective` is a single
value, `CombatManager:Update` dispatches every layer against it, and
`SelectTaskForce` hands it `available - reserve` units — where the reserve is
`AttackReserveFraction` for an attack and **zero for anything defensive**.

A defence therefore does not borrow from an attack. It replaces it, and takes
everything. `CanInterrupt` exists because of that, and its own comment records
the cost:

> an army with the strength to cripple an enemy base was recalled repeatedly and
> killed only a few engineers ... the army walked back and forth and never
> landed a blow.

With one slot the only answers are *switch* or *don't switch*, and both are
wrong when two things need doing at once. The thing that loses that argument is
always pressure — and pressure is what keeps the opponent reacting instead of
expanding.

The supporting evidence is economic. Across the twelve-cell matrix, extractor
churn tracks the result better than any scouting figure:

| cell | profile | extractors | churn | result |
| --- | --- | --- | --- | --- |
| Fields of Isis 8675309 | LandLarge | 24 built / 24 lost | **1.00** | defeat |
| Fields of Isis 31337 | LandLarge | 21 / 14 | 0.67 | defeat |
| Syrtis Major 31337 | LandLarge | 33 / 15 | 0.45 | **victory** |
| Syrtis Major 8675309 | LandLarge | 22 / 5 | 0.23 | defeat |
| Sentry Point 31337 | LandSmall | 24 / 3 | **0.12** | victory |

Nothing in the objective system defends that economy, and nothing keeps pressure
on while it is defended.

## The two slots

**Primary — what we are doing to them.** Offensive intent. Defaults to the
enemy base as a standing fact and is never empty while an offensive force exists
and a reachable enemy base is known.

**Secondary — what we are protecting.** Defence, cover, escort, support. Sized
by what its trigger requires, released back to primary when the trigger clears.

The invariant: **a secondary trigger never empties the primary.** One exception,
below.

The split is by direction, not by urgency. Denying an enemy expansion is
pressure and belongs in primary even though it is economic; covering our own is
protection and belongs in secondary even though it is urgent.

## Primary objectives

Weights order selection **within the primary slot only**.

| weight | objective | status | trigger |
| --- | --- | --- | --- |
| 95 | `JointAttack` | exists | ally coordination; the launch window is time-critical |
| 90 | `Assault` | **referenced, never constructed** | committed push once production and force justify it |
| 85 | `Raid` | exists | best scored observed target |
| 75 | `Deny expansion` | **missing** | observed enemy engineer or extractor outside their base |
| 60 | `Pressure` | exists, needs the standing fact | the remembered enemy base; the floor, always available |

`Pressure` is what makes the invariant achievable: there is always a primary
available, because the enemy base is always a known place to be going.

## Secondary objectives

Weights order selection **within the secondary slot**, and set how much of the
force that slot may claim.

| weight | objective | status | trigger |
| --- | --- | --- | --- |
| 160 | `Commander emergency` | partial, inside `Defend`/`Critical` | ACU credibly threatened; the one trigger that may take the primary slot and suspend pressure |
| 140 | `Defend` (alert) | exists | qualifying cluster at a protected anchor |
| 120 | Ally ping | exists | explicit request, already escalating to 120 |
| 115 | `Cover expansion` | **missing** | our extractors or engineers under observed threat outside the base |
| 110 | `Defend` (local) | exists | `LocalDefenseThreat` near home |
| 82 | `Support` | exists | ally support request |
| 70 | `Secure expansion` | **missing** | escort for an unclaimed cluster with a safe route |
| 40 | `Investigate` | vestigial | a high-value area nothing has seen, or an unexplained loss |

`Cover expansion` sits above local defence deliberately: an extractor line being
eaten is a larger loss than a couple of raiders near the base, and churn of 1.00
says that is what actually happens.

A ping inherits its slot from its own type — an attack ping is primary intent,
a help request is secondary.

## Allocation

The secondary is sized by what its trigger requires, the shape the garrison
logic already uses when it compares prospective escort strength against site
threat.

```
required   = threat at the secondary objective * CommitmentThreatRatio
ceiling(w) = MinimumSecondaryCeiling + (w - 40)/(140 - 40)
                 * (MaximumSecondaryFraction - MinimumSecondaryCeiling)
secondary  = min(required / offensive threat, ceiling(weight))
primary    = remainder, never below MinimumPressureFraction
```

| constant | start | meaning |
| --- | --- | --- |
| `MinimumSecondaryCeiling` | 0.20 | what the lightest reaction may claim |
| `MaximumSecondaryFraction` | 0.60 | what the heaviest may claim, so no alert strips the attack |
| `MinimumPressureFraction` | 0.25 | what primary keeps whenever a reachable enemy base is known |

A commander emergency ignores all three. It is the only trigger that may.

If a secondary cannot be satisfied within its ceiling, that is **reported, not
taken from the primary**. A defence that cannot be answered without abandoning
the attack is a decision worth seeing in a log.

## Changing in flight

Reassignment is per unit, so adaptation is incremental rather than wholesale.

1. **Units carry their slot** — `RedQueenObjectiveSlot` beside the existing
   `RedQueenOrderUntil`, so a pass can move a portion without re-issuing
   everything.
2. **Hysteresis on movement.** A unit changes slot only when the imbalance
   exceeds a margin and its current order has run a minimum time. Without this
   the design reproduces the walk-back-and-forth failure at unit granularity
   instead of army granularity.
3. **Engaged units move last.** An arrived force is the most expensive to recall
   and the closest to producing something; reassign from the units furthest from
   their objective first.
4. **Release immediate, commitment gradual.** A cleared trigger returns its
   units at once; a new trigger fills over passes. The same asymmetry the scout
   ceiling probe needed, for the same reason: need is answered quickly,
   withdrawal is not.

## What has to be observable

None of this is judgeable from a win rate. The state line reports one
`objective=` today and needs both slots, the split, and whether the invariant
survived contact:

```
primary=Raid/0.71 secondary=Defend/0.29 pressure=held
```

`pressure=held` against `pressure=yielded` is the figure that says whether the
design did its job. `secondary=unmet` marks the case the design deliberately
accepts, and should be seen doing.

## Build order

1. ~~**The standing enemy-base fact**~~ — done. Gated on
   `ScenarioInfo.Options.TeamSpawn`: `fixed` and the three `*_reveal` variants
   are read directly, and an absent option means fixed, because that is FAF's
   default and what a command-line skirmish gets. Everything else is learned by
   observing an enemy **structure** within `EnemyBaseDiscoveryRadius` (60) of a
   start, and recorded in `WorldModel.ResolvedStarts`, which does not decay with
   the observation that produced it.

   The design changed twice during the build.

   First, the plan above said hidden spawns should leave `GetClosestEnemyStart`
   empty, but `CombatManager:ScoutCandidates` builds its scout destinations
   straight off `EnemyStarts` — so emptying that list would have stopped Red
   Queen scouting toward enemy starts exactly when she has the most to find out.
   The shipped version keeps **two tiers**: every start stays in the list as a
   place to look, and `Known` decides whether it is also a place to attack.

   Second, randomisation alone does not hide anything. It hides something only
   while the map has empty slots. If every start on the map has a player on it,
   then every start that is not ours and not an ally's holds an enemy, and that
   is a deduction any player makes without scouting. So candidates are now
   enumerated from FAF's `"Spawn"` marker cache — every `ARMY_n` marker on the
   map, each carrying `IsOccupied` — minus our own slot and our allies'. `Known`
   is then `revealed or AllSpawnsOccupied or resolved`. Under hidden spawns the
   army attribution is dropped and candidates are sorted by distance from home,
   which is both the useful scouting order and a way of not leaking the army
   index back out through list position.

   **A closed lobby slot reads as empty.** The sim is told nothing about closed
   slots: `ListArmies()` and `ScenarioInfo.ArmySetup` only ever contain armies
   that exist, and no closed-slot list reaches `ScenarioInfo`. So a map whose
   spare slots were closed at setup looks exactly like one whose spare slots
   were merely empty, `AllSpawnsOccupied` stays false, and Red Queen scouts a
   slot nobody could have joined. That is the conservative direction — she
   under-claims knowledge rather than over-claiming it — but a human who sat in
   that lobby would know better. Fixing it needs the lobby to pass the closed
   list into the scenario options, which is not ours to change.

   Verified by eighteen mutations against `tests/world_model_spec.lua` and
   `tests/strategy_director_spec.lua`, all caught. The map log line now carries
   `spawns=` (`revealed`, `hidden-full` or `hidden`) and `slots=occupied/total`.
   The hidden path has contract cover only: no matrix map uses randomised
   spawns, so it is untested in a live match.
2. ~~**The secondary slot, empty.**~~ — done, with ranked selection.

   Selection moved off the first-match if-chain onto `SelectionWeights`, and
   the weights were chosen to reproduce the chain's order **exactly**, so that
   moving selection onto weights did not move behaviour at the same time.
   `SelectionOrder` is derived from the weights at load, so the two cannot
   drift; the weights must stay distinct or the sort stops being total, and a
   contract pins that.

   The carried `Priority` is not the selection weight and never was. A ping
   escalates 80 → 120 and a coordinated attack inherits its ally's priority, so
   those numbers cross Support's fixed 82 — but the chain tested each kind in a
   fixed sequence, so they never ordered anything. Three cases now pin it: a
   ping at 80 still outranks Support at 82, an allied attack carrying 60 still
   outranks our own Raid at 75, and an alert outranks a local defence even
   though both produce `Type == "Defend"`.

   **Adopting the proposed ladder is therefore a separate, measurable change.**
   The three disagreements between the shipped weights and this document are
   recorded in the table below.

   | kind | shipped | proposed | effect of adopting |
   | --- | --- | --- | --- |
   | `LocalDefense` | 120 | 110 | ping rises above local defence |
   | `Ping` | 118 | 120 | as above |
   | `JointAttack` | 80 | 95 | joint attacks rise above `Support` |
   | `Offensive` | 75 | Raid 85 / Pressure 60 | must split; `Pressure` falls below `Support` |

   The slots are filled but the secondary is always empty, so the winning
   objective still commands the whole army exactly as before. What is new is
   that the army says which kind of thing it is doing, and the state line now
   carries `primary=<type>/<fraction> secondary=<type>/<fraction> pressure=held|yielded`.
   A secondary-intent objective holding the entire force is reported as
   `pressure=yielded` rather than counted as an objective held — so this step
   produces the baseline count of how often a defensive trigger takes the whole
   army today, which is the number step 3 has to improve.

   Ten mutations run against the contracts, all caught.

   ### The baseline this step exists to produce

   Fields of Isis (SCMP_015, 512 = 10 km), seed 31337, Red Queen Aeon against
   adaptive Cybran. Full match, 28:08 of game time, **defeat**.

   | measure | value |
   | --- | --- |
   | samples with pressure yielded | **18 / 28 (64.3%)** |
   | secondary slot contents | `Defend` in all 18 |
   | objective changes in 28 minutes | 6 |
   | objective changes **refused** | 9, every one `priority-gap` |
   | forward bases blocked by `defense-alert` | 13 |
   | alert samples with experimental weight zeroed | 16 |
   | mass built, Red Queen vs winner | 53k vs 197k |

   Two mechanisms, not one. A defence *takes* the army — that is the preemption
   `CanInterrupt` was written to limit. But once it has the army it also *keeps*
   it: `Raid` carries priority 75 and can never clear `Defend`'s 120 or 140 plus
   `ObjectiveInterruptPriorityGap` of 15, so every attempt to resume the attack
   is refused until the defensive objective simply expires. Nine refusals
   against six actual changes says the second mechanism is the larger one, and
   it is symmetric in the wrong direction: `CanInterrupt` protects a defence
   from an attack exactly as hard as it protects an attack from a defence.

   The defensive state is not only costing pressure. It blocked thirteen forward
   base attempts and zeroed the experimental weight in sixteen alert samples,
   while the winner out-built Red Queen roughly four to one. That is the
   extractor-churn story arriving through a different door.

   Step 3 has to move both numbers: the yielded share, and the refusal count.
It moved the refusal count to zero. The yielded share turned out not to be
measurable across the change, and the run that produced it showed why neither
number decides these matches yet.
3. ~~**Move `Defend` to secondary.**~~ — done. The prediction held, and the
   result says the objective system is no longer what is losing these matches.

   Same cell as the baseline: Fields of Isis, seed 31337, Red Queen Aeon.

   | measure | step 2 baseline | step 3 | comparable? |
   | --- | --- | --- | --- |
   | objective changes refused | 9 | **0** | yes |
   | primary slot empty | 18 of 28 samples | **never** | yes |
   | primary slot contents | `none` 18, `Raid` 6, `Pressure` 4 | `Raid` 31, `Pressure` 4 | yes |
   | both slots active at once | impossible | 25 samples | yes |
   | result | defeat, 28:08 | defeat, 35:14 | yes |
   | mass built, RQ vs winner | 53k vs 197k | 106k vs 351k | yes |
   | extractors held | 7 of 44 | 6 of 44 | yes |
   | pressure yielded share | 64.3% | 100% | **no — see below** |

   The prediction was right: `CanInterrupt` no longer preempts across slots, so
   every one of the nine refusals disappeared, and the primary slot is never
   empty again.

   **The pressure percentages are not comparable and must not be read as a
   regression.** The state line changed meaning between the runs. In step 2 the
   slot figures were allocation *fractions*, so `secondary=Defend/1.00` meant a
   defence held the whole allocation; in step 3 they are *dispatched unit
   counts*. The analyzer reads both, but 64.3% and 100% are measuring different
   things. Comparing them would need the baseline re-run under the new logging.

   **What the absolute figures do say is that the army is the problem, not the
   objectives.** `commitment held objective=Raid units=3 threat=15 required=68`
   is typical: Red Queen fields about three combat units, holds six of the
   map's forty-four mass points, and is out-built three to one. Splitting a
   three-unit army between two objectives cannot matter, and no objective policy
   will show a win-rate effect until that changes.

   One interaction to watch: forward bases blocked on `defense-alert` rose from
   13 to 25, and alert samples from 16 to 24. The economic cost of being under
   alert is now the larger drag, which is the argument for building the point
   defence that ends the alert.

   Single seed, single map, one run each. Ten mutations run against the
   contracts; nine caught, the tenth equivalent.
4. **`Cover expansion`**, reusing the garrison machinery that already covers
   forward bases. Judge it on extractor churn, not on win rate.
5. **`Deny expansion`**, the mirror, natural once anything outside the enemy
   base is by definition an expansion.

Ranked selection landed with step 2. Adding an objective now means giving it a
weight, not pasting it into a chain — but `Offensive` still covers `Raid` and
`Pressure` as one candidate, which holds only while nothing sits between them.
Step 4 or 5 forces that split.

## Known dead ends, recorded so they are not retried

- `Assault`, `Recover` and `Supremacy` are referenced but never constructed.
  One is not harmless: `demand.Artillery = objective.Type == "Assault" and 0.18
  or 0.10` can never take its high branch, so artillery demand is pinned at 0.10
  for every match.
- Scout **production sizing** was dead code; wiring it was a wash on record and
  cost K/L in eleven of twelve cells.
- Observer **sampling rate** was refuted arithmetically: every unit was already
  sampled 15 to 30 times per intel lifetime.
- Directed **dispatch** is already net-useful; removing it loses faster.

## What this does not fix

Nothing here claims the large-map economy. It removes the reason pressure stops,
which is a precondition for judging the economic objectives rather than a
substitute for them. Extractor churn stays the figure to judge those by, and
Fields of Isis remains 0W in every arm tested so far.


## The economy latch, and a correction

Three runs of the same cell — Fields of Isis, seed 31337, Red Queen Aeon. All
three are byte-identical to sample 9, because the seed is fixed and nothing
before the first defensive trigger differs.

### When map control is lost

| sample | extractors | engineers held/target | engineers lost | momentum | alert |
| --- | --- | --- | --- | --- | --- |
| 8 | **18 / 44** peak | 10 / 6 | 0 | stable | no |
| 9 | 16 | 13 / 7 | 1 | **losing** | no |
| 10 | 14 | 17 / 9 | 2 | losing | **yes** |

`momentum=losing` and the first engineer loss arrive one sample *before* the
alert, so the alert is a lagging signal. Extractors then fall to 6 and never
recover across the next twenty minutes.

### A wrong answer, recorded so it is not repeated

The first diagnosis was that `commander-emergency` latched the economy off. The
`Commander` anchor is the ACU's own position and the ACU stands in the main
base, so every attack on the base anchored there; in Assassination that zeroed
Tech3, Experimental, Nuke and every project slot. It held 21 of 35 samples.

That was fixed — the veto now requires the commander to actually be losing
health — and the fix was validated end to end on the same cell. **It changed
nothing.**

| measure | before | after |
| --- | --- | --- |
| `commander-emergency` samples | 21 | **7** |
| samples with any T2 weight | 1 | 1 |
| samples with any experimental weight | 0 | 0 |
| extractors, peak → final | 18 → 6 | 18 → **2** |
| result | defeat, 35:14 | defeat, 42:41 |

The veto was real and the fix is correct on its own terms — proximity is not
danger — but it was never the binding constraint. It zeroed values that were
already zero.

### The actual latch

`baseDanger` is `localThreat >= LocalDefenseThreat`, which is 25: a couple of
raiders within 100 of the base. It gates the *computation* of `experimental` and
`nuke`, upstream of everything else.

```
local baseDanger = localThreat >= Constants.Policy.LocalDefenseThreat
local tech2 = 0
if not baseDanger and forces.MissingT2Coverage > 0 and CanAfford(...) then
...
if not baseDanger and nukeOpportunity and ...
```

So the severity-and-wealth tax in the alert branch — written to stop exactly
this failure, after a binary veto held one army at zero experimental weight for
all thirty of its alert samples — **cannot fire**. It multiplies
`weights.Experimental` by a retention factor, and `weights.Experimental` is
already zero whenever an enemy is near the base. The relief mechanism is dead
code in precisely the case it was built for.

The measurements isolate it from affordability:

- 30 of 43 samples could afford Tech 2 (mass ≥ 4, energy ≥ 60). T2 weight was
  zero in **all thirty**.
- 9 samples could afford Tech 3 (mass ≥ 10, energy ≥ 250). T3 weight was zero in
  all nine — though here `MissingT3Coverage` reaching zero is a legitimate
  reason, since tier policy did reach `L3,A3`.
- Experimental weight was zero in **all 43 samples**, while the match ended on
  mass 27.8, energy 828 and `tiers=L3,A3,N1`.

`Tech 3 is deliberately not gated on baseDanger` is already a comment in this
file, added after a match that built 925 Tech 1 units against 669 Tech 3. The
same lesson was never applied to `experimental` or `nuke`.

### What this means for consolidation

Defending remaining extractors, power-to-mass conversion, mass storage
adjacency, extractor upgrades and SACUs are all investment under pressure —
which is the state `baseDanger` forbids. None of them exist yet either:

| capability | status |
| --- | --- |
| mass fabricators | absent |
| mass storage / adjacency | absent |
| energy storage | absent |
| extractor upgrades T1→T2→T3 | absent (factory upgrades exist) |
| SACUs | one build condition, capped at six |
| `Cover expansion` | missing |

So the order is: make investment legal under pressure, then give it something to
buy.


## Investment under pressure: four builds, one cell

Fields of Isis, seed 31337, Red Queen Aeon against adaptive Cybran. One match
per build, so survival time is not a reliable discriminator — the same seed
produced 15 to 42 minutes across these four. The investment rate is a direct
measure of the mechanism and is reliable.

| build | samples | samples with T2 weight | extractors, final | ended |
| --- | --- | --- | --- | --- |
| slots (step 3) | 35 | 1 (2%) | 6 / 44 | defeat, 35 min |
| commander veto fixed | 43 | 1 (2%) | 2 / 44 | defeat, 42 min |
| `baseDanger` ungated | 16 | 3 (18%) | 7 / 44 | defeat, **15 min** |
| `baseDanger` throttled | 31 | **10 (32%)** | 7 / 44 | defeat, 30 min |

Ungating outright was the worst outcome: tier spending competed with army
production while the army was being overrun and the match ended in fifteen
minutes. The throttle keeps the investment and recovers the survival time.

Under an active alert the throttled Tech 2 weight lands at 37 to 43 against a
threshold of 35 — the out-teched relief is what carries it over the line, and
without that relief a poor raided army keeps only the 0.35 floor and stays on
army. Tier policy reached `L2` in 24 of 31 samples, having never left `L1` under
the veto.

**What it did not fix.** Extractors follow the same curve in every build: peak
18 at sample 8, collapse to 5-7 by sample 18, flat thereafter. Red Queen was
out-built 91k to 242k. Permission to invest was necessary and is not
sufficient, because there is still nothing to spend it on:

| capability | status |
| --- | --- |
| mass fabricators | absent |
| mass storage / adjacency | absent |
| energy storage | absent |
| extractor upgrades T1→T2→T3 | absent |
| SACUs | one build condition, capped at six |
| `Cover expansion` | missing |

The experimental throttle is still untested: `X` weight was zero in all four
builds, because the experimental gate also needs `T3Factories > 0` and no run
reached Tech 3.


## The opening engineer floor: the first economic gain measured

Same cell throughout — Fields of Isis, seed 31337, Red Queen Aeon. One match per
build.

| build | peak extractors | final extractors | RQ mass built | opponent | ended |
| --- | --- | --- | --- | --- | --- |
| slots (step 3) | 18 | 6 | 106k | 351k | defeat, 35 min |
| tier throttle | 18 | 7 | 91k | 242k | defeat, 30 min |
| breadth-first gate | 18 | 6 | 97k | 220k | defeat, 29 min |
| **opening engineer floor** | **22** | **13** | **234k** | 426k | defeat, 41 min |

Peak extractors had been exactly 18 in every build ever measured. The floor is
the first change to move it, and the holding is the larger gain: 13 points at
the end against 6, and 2.4 times the mass built.

The engineer target reads `1/12, 3/12, 6/12, 10/12, 12/12` through the opening —
the twelve engineers a player builds as the first factory completes — where it
had read 2 or 3.

**It did not convert.** The opponent still out-built 426k to 234k, and the
exchange rate got worse rather than better: K/L fell from 1.09 to 0.40, with
151k lost against 61k killed. More economy, spent worse. Whether that is the
economy competing with army production or simply a longer life in a lost
position is not answerable from one match.

Two things in flight and unmeasured: the engineer tier ladder, where a cap
filled with Tech 1 engineers meant no Tech 2 engineer was ever built, and the
consolidation capabilities, which still do not exist.


## Re-measured on a clean loop

The opening-floor result was taken in a run with 177 failed production passes
(`ipairs` over a multi-return call). Re-run with that fixed and the engineer
tier ladder added, on the same cell:

| measure | pre-floor builds | opening floor (broken loop) | clean loop + tier ladder |
| --- | --- | --- | --- |
| scheduler failures | 0 | **177** | **0** |
| opening curve to sample 8 | 3 5 10 11 11 14 17 18 | 3 5 9 12 18 20 22 | 3 5 9 12 18 20 **22** |
| peak extractors | 18 | 22 | **22** |
| final extractors | 6 | 13 | 12 |

**The gain holds.** The opening curve is reproduced exactly on a clean loop, so
the engineer floor really does take peak extractors from 18 to 22 and the
earlier figure was not an artifact of the broken passes.

**The tier ladder fires, weakly.** Tech 2 engineers peak at 3 and appear in 13
of 36 samples, against a structural zero before — the builder could never fire
while Tech 1 engineers filled the cap. But Tech 1 peaks at 28, far above the
target of 12 to 18, so most build power is still the cheap tier and the
transition happens late.

**The problem has moved.** Red Queen built 184k and lost 145k to kill 46k: a
K/L of 0.31 against the opponent's 3.06. Two consecutive builds now show the
same shape — more economy, spent worse. The economy work is succeeding at
economy and failing at winning, and the next question is not how to earn more
mass but why the army that mass buys dies three to one.


## Step E: where the army actually is

Fields of Isis, seed 31337. The run ended on the identical tick as the one
before it (21293), so the instrumentation is provably inert — pure observation,
no behavioural change.

```
Army census: peak owned=57, peak pooled=23, peak available=7
  units Red Queen cannot command (owned-pooled): mean 20.2, peak 45
```

Trajectory of `owned/pooled/available`:

```
13/8/0   15/4/3   15/4/4   25/8/2   28/8/5   46/13/6   41/5/3   57/17/5   46/16/0
```

**Red Queen commands between 8 and 12 per cent of its own army.** At the peak it
owned 57 combat units, 17 were in the ArmyPool, and 5 were available to order.

Two separate losses, not one:

- **Native platoon formation holds the majority.** Owned minus pooled averages
  20 units and peaks at 45. These are never visible to the objective system at
  all, so every mechanism built for slots, allocation and dispatch is steering a
  minority of the force.
- **Red Queen locks most of what is left.** Pooled minus available is typically
  two thirds of the pool — units inside `RedQueenOrderUntil` or
  `RedQueenGarrisonUntil` holds.

Only the first was predicted. The second matters for sequencing: taking
ownership of production hands Red Queen more units, and on this evidence it
would park most of them. Whatever fixes ownership has to be measured against
`available`, not `pooled`.

This also explains the dispatch record without any further theory. `33 of 36
samples dispatched nothing` and `commitment held ... units=3` are what a pool of
five available units looks like against a commitment gate that asks for a wave.


## Step A: taking ownership of production

Fields of Isis, seed 31337, against the census run as baseline.

| measure | before A | after A |
| --- | --- | --- |
| units Red Queen cannot command (owned−pooled) | mean **20.2**, peak 45 | mean **−1.6**, peak 0 |
| peak available to order | 7 | **12** |
| samples that dispatched anything | 3 of 36 | **18 of 33** |
| Red Queen K/L | **0.31** | **1.43** |
| opponent K/L | 3.06 | **0.66** |
| mass built, RQ vs opponent | 184k vs 302k | 203k vs 293k |
| result | defeat, 35 min | defeat, 33 min |

The gap is gone: native platoon formation no longer holds any of the army.
Dispatch went from three samples to eighteen, and the exchange rate inverted —
Red Queen now trades better than the opponent it is losing to, having traded at
a tenth of its rate two runs ago.

**The parking worry was unfounded, and the audit is what shows it.** Order holds
rose to a mean of 20.6 and a peak of 40, which looks alarming until it is read
against dispatch: an order hold means a unit is *executing an order*, and
dispatch rose by the same factor. Garrison holds — the genuinely parked state —
average 0.6. Red Queen is commanding its army, not sitting on it. Splitting the
two holds is the only reason that is answerable.

**Still lost.** The opponent out-built 293k to 203k and won on economy while
losing the exchange. Winning the fight and losing the match is a different
problem from the one this step fixed, and it is the one C and D exist for.


## The full matrix, and what it says

Twelve cells, the recorded variety matrix, zero scheduler failures.

**3W/9L against a 7W/5L baseline.** Naval held at 3W/2L; every land profile
collapsed — LandSmall 2W/1L to 0W/3L, LandLarge 2W/2L to 0W/4L.

### Attribution

Five cells flipped from victory to defeat. The five were re-run with formation
ownership disabled and nothing else changed:

| cell | ownership on | ownership off |
| --- | --- | --- |
| Sentry Point 31337 Aeon | defeat | **victory** |
| Sludge 2071971 Aeon | defeat | **victory** |
| Sentry Point 2071971 UEF | defeat | defeat |
| Fields of Isis 8675309 | defeat | defeat |
| Syrtis Major 8675309 | defeat | defeat |

So taking ownership of production costs two cells, and the other three were
already lost by earlier work in this session. The honest split is roughly
7W/5L → 5W/7L from everything before ownership, and 5W/7L → 3W/9L from
ownership itself.

### Why ownership loses

It does what it claimed: owned minus pooled falls to zero, dispatch rises from
3 samples in 36 to 18 in 33, and in one cell the exchange rate inverted. What it
also did was remove the only thing organising the army.

| cell | owned | commandable | order-held | K/L | result |
| --- | --- | --- | --- | --- | --- |
| Sentry Point 2071971 | 250 | 42 | mean 87, peak 231 | 0.32 | defeat |
| Syrtis Major 8675309 | 163 | 30 | mean 47, peak 135 | 0.39 | defeat |
| Sludge 31337 (won) | 21 | 17 | mean 0.8 | 3.66 | victory |

On land Red Queen accumulates 150 to 250 units and issues them individual
aggressive-moves in whatever batches clear the commitment gate, so they arrive
strung out and die without trading. Native platoons fought as formations.
Naval is untouched because those armies stay at about twenty units.

`Constants.Policy.FormationOwnership` is therefore **off**. The code and its
census stay: the census is pure observation, and the premise — that Red Queen
commands eight to twelve per cent of its own army — is still true and still the
thing to fix. It needs C first. A and C are one change, not two.

### The other three regressions are unattributed

Sentry Point 2071971 UEF, Fields of Isis 8675309 and Syrtis Major 8675309 lose
with ownership off as well, so something landed earlier in this session that
cost them. That has not been bisected.
