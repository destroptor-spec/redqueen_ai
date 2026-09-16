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

   The design changed once during the build. The plan above said hidden spawns
   should leave `GetClosestEnemyStart` empty, but `CombatManager:ScoutCandidates`
   builds its scout destinations straight off `EnemyStarts` — so emptying that
   list would have stopped Red Queen scouting toward enemy starts exactly when
   she has the most to find out. The shipped version keeps **two tiers**: every
   start stays in the list as a place to look, and `Known` decides whether it is
   also a place to attack. Under hidden spawns the army attribution is dropped
   and the candidates are sorted by distance from home, which is both the useful
   scouting order and a way of not leaking the army index back out through list
   position.

   Verified by eleven mutations against `tests/world_model_spec.lua` and
   `tests/strategy_director_spec.lua`, all caught. A smoke run on SCMP_007
   records `spawns=revealed starts=5` with five brains and no errors. The hidden
   path has contract cover only: no matrix map uses hidden spawns, so it is
   untested in a live match.
2. **The secondary slot, empty.** Allocation gives everything to primary and
   behaviour is identical. Land this alone: a measurable no-op proves the split
   before any policy question is reached, and if it changes anything the
   allocation is wrong and that is cheap to find out.
3. **Move `Defend` to secondary.** The behavioural change, with a specific
   prediction: the walk-back-and-forth stops appearing and `CanInterrupt`
   reduces to a tie-break on primary replacement rather than a preemption rule.
4. **`Cover expansion`**, reusing the garrison machinery that already covers
   forward bases. Judge it on extractor churn, not on win rate.
5. **`Deny expansion`**, the mirror, natural once anything outside the enemy
   base is by definition an expansion.

Ranked selection must land with step 2, because objectives are currently chosen
by a first-match if-chain in code order — adding to it orders them by where they
were pasted, not by weight.

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
