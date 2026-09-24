# Engineer survival and production priority

Status: investigation and isolated reproductions complete; production code is
unchanged. Engineer survival and factory allocation take priority over further
scouting work, following the user's observations of engineers entering hostile
territory, T2 factories producing T1 engineers, and repeated replacements
crowding out the early army.

## Evidence

The V9 combined matrix's final `JsonStats.units.engineer` records include:

| Cell | Engineers built | Engineers lost |
| --- | ---: | ---: |
| isis-aeon-s2 | 122 | 106 |
| sentry-aeon-s1 | 75 | 66 |
| sentry-aeon-s3 | 71 | 62 |
| syrtis-aeon-s2 | 180 | 152 |
| syrtis-aeon-s3 | 210 | 188 |

These establish substantial engineer turnover. They do not identify the factory
that produced each engineer, the order that exposed it, or the fraction of
factory time spent on replacements. Whole-match totals also do not establish
when the early army became vulnerable. Those links need assignment and factory
allocation diagnostics, or the specific observed replay.

Read-only reproductions are in
`/tmp/rq-engineer-observations/reproduce.lua`, using the actual Red Queen builder
definitions and literal native functions extracted from the installed
`lua.nx2`. Run from the repository with:

```bash
luajit /tmp/rq-engineer-observations/reproduce.lua
```

They establish three mechanisms:

1. Native `EngineerMoveWithSafePath` returns true when ordinary pathability is
   true but `PathToWithThreatThreshold` returns no safe path. Native
   `ProcessBuildCommand` can then issue the distant build order and wait for the
   engineer to arrive. This is a concrete path into the reported behavior, not
   proof that it issued every hostile order in the user's observed match.
2. Native `FactoryBuilderManager.BuilderParamCheck` checks build capability,
   which allows a T2 factory to build a T1 engineer. Red Queen's T1 engineer
   builder has no per-factory tier restriction; general obsolescence exempts
   the Utility role, which includes engineers and scouts. The T1/T2/T3 engineer
   builders also share the same dynamic priority function despite differing
   static priorities.
3. With one engineer held and six requested, the actual replacement priority
   is 950 for all three tiers, above Red Queen's T2 mainline priority of 930.
   It rises to 1000 for larger shortfalls. Recent engineer losses increase the
   desired count by 1.5 per loss, with the total target capped at 18. Native
   engineer suppression uses a separate surviving-count ceiling of at least
   45, so repeated deaths can keep replacement production active below it.

## Correction order

1. **Stop feeding hostile assignments.** Apply the survival decision to native
   construction/resource tasks as well as Red Queen forward bases. Reject a
   failed safe route instead of accepting a direct fallback. Assess the actual
   engineer movement layer and observed route/destination danger; retain safe
   home construction and expansion. Recheck active travel. A recall must cancel
   the native build queue, callbacks/threads and task ownership before sending
   the engineer back. Retain the failed location and reason so the next engineer
   is not immediately sent into the same loss. Audit reclaim, capture and
   engineer transfers separately: they need not use the construction helper.
2. **Enforce engineer tier at the producing factory.** A T2 factory must not
   select a T1 engineer; a T3 factory must not select T1/T2 engineers. Use the
   actual factory and produced blueprint, including captured factions. Keep
   surviving T1 factories able to produce T1 engineers. A global highest-tier
   switch would incorrectly disable that fallback.
3. **Protect combat production during replacement.** Bound concurrent engineer
   orders and reserve factory capacity for combat units when losses recur.
   Account for orders already committed instead of letting several factories
   react to the same shortfall. Retain a construction-recovery exception when
   the army has too few engineers to function. Losses should also trigger a
   destination/survival response; increasing replacement priority alone feeds
   the observed cycle.

Do not start by lowering `EngineerSuppressionMinimum`. Earlier matrices showed
that a lower surviving-count ceiling could prevent economic growth. The
reported issue includes repeated throughput into losses, which a headcount cap
cannot control by itself. Keep the measured ceiling separate from the new
allocation and survival rules.

## Verification before another balance run

- Reproduce a pathable destination with a rejected safe path, a route that
  becomes hostile in transit, and repeated assignment to a recently lethal site.
- Verify native ownership cancellation and ordinary non-Red Queen behavior.
- Exercise T1/T2/T3 factories against every engineer tier, mixed-tier bases,
  captured factories and recovery after higher-tier factory loss.
- Exercise simultaneous replacement requests under sustained losses, including
  a one-factory opening and an army recovering from very few engineers. Verify
  actual selected builds, not just a demand field or builder priority.
- Report assigned task/destination, rejected or recalled routes, engineer
  orders in flight, and factories producing engineers versus combat units.
  Counters must survive the gap between production and diagnostic cycles.
- Run the full contract gate. Runtime verification remains subject to the
  user's control of match launches; preserve attributable matrix payloads.

## Independent verification of the three mechanisms

`luajit /tmp/rq-engineer-observations/reproduce.lua` reproduces all three, and
the code claims check out against the shipped definitions:

- **Shared priority ignores tier.** `EngineerPriority` in `CounterBuilders.lua`
  is `math.min(1000, 850 + shortfall * 20)` and is the `PriorityFunction` for
  all three builders, so the static 870/860/850 never apply. Tabulated against
  the combat builders it displaces:

  | engineer shortfall | engineer priority | outranks |
  | ---: | ---: | --- |
  | 1 | 870 | — |
  | 4 | 930 | ties T2 Land Dominance (930) |
  | 5 | 950 | beats T3 Land Dominance (940), T2 Land Factory Tech (920) |
  | 8 | 1000 | beats everything |

  Because each loss adds 1.5 to the desired count, **four engineer deaths are
  enough to put engineer production above all combat production**, in every
  factory, at every tier. That is the observed "production is almost entirely
  engineers" with a number attached.

- **Utility exemption.** `ProductionManager.lua:117` classifies
  `ENGINEER or SCOUT` as `Utility`, and the obsolescence checks at `:711` and
  `:767` exempt that role — so nothing retires the T1 engineer builder when
  higher tiers exist.

- **Native travel and factory checks** behave as described.

### Why the headcount ceiling could not have fixed this

`EngineerSuppressionMinimum` (45) gates on *surviving* engineers. The loop here
is throughput: build, walk into hostile ground, die, raise the target by 1.5,
rebuild. Survivors stay well under 45 throughout, so the ceiling never engages.
The document's warning not to start there is right, and it also explains why the
earlier calibration work on that ceiling — which measured real harm at 18 and at
the target itself — never addressed this: it was regulating the wrong quantity.

## Observation 4: mid-game dormancy (not yet covered above)

Reported alongside the others: mid-game, every Red Queen army was largely
dormant — ACU doing nothing, idle Tech 1 engineers in the main base — where
pressure should be increasing as the army moves from Tech 2 to Tech 3.

One mechanism is already visible in the code: Red Queen excludes the commander
from every engineer pool it manages — `categories.ENGINEER - categories.COMMAND`
at `ProductionManager.lua:1724` and `:1770`, and the same exclusion in factory
assistance. The ACU is the strongest single source of build power on the field,
and after the opening Red Queen never asks it for anything; whatever it does is
left to FAF's native commander behaviour.

Idle Tech 1 engineers in the main base fit the same replacement loop: the target
is inflated by deaths rather than by work, so the army holds engineers it has no
task for. Both need their own diagnostics before a fix — assigned task per
engineer, and idle time per engineer tier — since neither is visible in the
current state line.

This observation is recorded, not diagnosed. The correction order above stands.
