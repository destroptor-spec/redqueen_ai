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
3. **Move `Defend` to secondary.** The behavioural change, with a specific
   prediction: the walk-back-and-forth stops appearing and `CanInterrupt`
   reduces to a tie-break on primary replacement rather than a preemption rule.
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
