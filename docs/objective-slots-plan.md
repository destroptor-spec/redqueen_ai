# Primary and secondary objectives

## The foundation problem

Red Queen holds exactly one objective. `Strategy.CurrentObjective` is a single
value, `CombatManager:Update` dispatches every layer against it, and
`SelectTaskForce` hands it `available - reserve` units — where the reserve is
`AttackReserveFraction` for an attack and **zero for anything defensive**.

So a defence does not borrow from an attack. It replaces it, and takes
everything.

`CanInterrupt` exists because of that, and its own comment records the cost:

> an army with the strength to cripple an enemy base was recalled repeatedly and
> killed only a few engineers, because `LocalDefenseThreat` is 25 — a couple of
> raiders at home — and any Defend used to preempt unconditionally. The
> objective then expired after `ObjectiveLifetimeTicks` and the attack resumed,
> so the army walked back and forth and never landed a blow.

That is not a bug in `CanInterrupt`. It is the single-slot design showing
through: with one objective the only available answers are *switch* or
*don't switch*, and both are wrong when two things need doing at once.

Pressure is the thing being dropped, and pressure is what keeps the opponent
reacting instead of expanding. Every mechanism that competes with it currently
wins by taking the whole army.

## Two slots

**Primary — sustained pressure.** Where the army is going, by default the
enemy base as a standing fact. It changes rarely: only a better attack target
displaces it. It is never empty while an offensive force exists and an enemy
base is known and reachable.

**Secondary — the reaction.** Defence, cover, escort, support, opportunity. It
changes often, is sized by what its trigger actually requires, and releases its
force back to primary when the trigger clears.

The invariant that makes this worth doing: **the primary slot is not emptied by
a secondary trigger.** Suppression continues while the reaction happens.

### Eligibility

| slot | objectives |
| --- | --- |
| primary | `Raid`, `JointAttack`, `Assault`, `Pressure` (the remembered enemy base) |
| secondary | `Defend` (alert and local), `Cover expansion`, `Deny expansion`, `Support`, ally ping, `Investigate` |
| either | `Commander emergency` — the one trigger allowed to take the primary slot and suspend pressure outright |

`Stage` and `Recover` are not objectives in this sense; they are the state where
no primary is possible.

## Allocation

Secondary is sized by **what its trigger requires**, not by what is available —
the shape the garrison logic already uses, comparing prospective escort strength
against site threat.

```
required      = threat at the secondary objective * CommitmentThreatRatio
secondaryWant = required / total offensive threat
secondary     = min(secondaryWant, MaximumSecondaryFraction)
primary       = remainder, never below MinimumPressureFraction
```

- `MaximumSecondaryFraction` — the ceiling on what a reaction may take, so no
  single alert can strip the attack. Start at 0.60.
- `MinimumPressureFraction` — the floor the primary keeps whenever a reachable
  enemy base is known. Start at 0.25.
- A commander emergency ignores both. It is the only trigger that may.

If the secondary cannot be satisfied within its ceiling, that is **reported**,
not silently taken from the primary. A defence that cannot be answered without
abandoning the attack is a decision worth seeing in a log.

## Changing in flight

Reassignment is per unit, not per army, so adaptation is incremental.

1. **Units carry their slot.** `RedQueenObjectiveSlot` alongside the existing
   `RedQueenOrderUntil`, so a pass can move a portion without re-issuing
   everything.
2. **Hysteresis on movement.** A unit does not change slot unless the imbalance
   exceeds a margin and its current order has run a minimum time. Without this
   the design reproduces the walk-back-and-forth failure at unit granularity
   instead of army granularity.
3. **Engaged units move last.** A force that has arrived is the most expensive
   to recall and the closest to producing something. Reassign from the units
   furthest from their objective first.
4. **Release is immediate, commitment is gradual.** When a secondary trigger
   clears, its units return to primary at once; when a trigger appears, the
   secondary fills over passes. The asymmetry is deliberate and matches the
   scout ceiling probe: need is answered quickly, withdrawal is not.

## What has to be observable

None of this can be judged from a win rate. The state line reports one
`objective=` today; it needs both slots and the split, or a matrix cannot
attribute anything:

```
primary=Raid/0.71 secondary=Defend/0.29 pressure=held
```

`pressure=held` versus `pressure=yielded` is the single figure that says whether
the invariant survived contact. Add `secondary=unmet` when the ceiling bound a
reaction, because that is the case the design deliberately accepts and should be
seen doing.

## Migration

1. `CurrentObjective` becomes an alias for the primary slot, so every existing
   consumer keeps working unchanged.
2. Add the secondary slot with an empty default. With no secondary, allocation
   gives everything to primary and behaviour is identical — a null change that
   can be measured as one.
3. Move `Defend` to the secondary slot. This is the behavioural change, and the
   prediction is specific: the walk-back-and-forth that `CanInterrupt` guards
   against should stop appearing, and `CanInterrupt` should reduce to a
   tie-break on primary replacement rather than a preemption rule.
4. Add the economic secondaries from `docs/objective-priorities.md` —
   `Cover expansion` first, since extractor churn reaches 1.00 on Fields of Isis.

Step 2 is the one to land alone: it should change nothing, and if it changes
anything the allocation is wrong before any policy question is reached.

## What this does not fix

Nothing here claims the large-map economy. It removes the reason pressure stops,
which is a precondition for judging the economic objectives rather than a
substitute for them. Extractor churn stays the figure to judge those by.
