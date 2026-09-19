# What the combat telemetry found — 2026-09-19

Six cells at the telemetry tree: the four LandLarge losses, the remaining Sludge
loss, and Sentry Point 31337 as a win control. Every cell reports one brain
started, zero Red Queen Lua failures and zero scheduler failures, and every
outcome matches its baseline, so the observer is inert.

## Priority 1 does not survive its own falsifier

The report named the falsifier: *"if the losing mass is primarily in native
platoons, the directed-plan explanation is weakened."* Cumulative combat mass
lost, by controller:

| cell | directed | nativeLand | nativeAir | pool | unassigned | directed share |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Isis 8675309 | 7,857 | 14,526 | 11,810 | 920 | 3,240 | 20.5% |
| Isis 31337 | 11,826 | 17,718 | 10,890 | 1,085 | 270 | 28.3% |
| Syrtis 8675309 | 11,067 | 7,200 | 15,040 | 2,820 | 1,769 | 29.2% |
| Syrtis 31337 | 19,817 | 19,216 | 15,000 | 2,040 | 760 | 34.9% |
| **Sentry Point 31337 (win)** | 1,332 | 2,472 | 500 | 290 | 0 | **29.0%** |

Directed platoons carry 20-35% of the losses, and the **winning** control sits
at 29% — inside the same band. Directed share does not separate a win from a
loss. Native land and native air together carry 1.7x to 3.4x the directed loss
on every losing cell.

This measurement is only trustworthy because `unit.PlatoonHandle` still holds at
`OnUnitKilled`: native `Unit:OnKilled` calls `self.Brain:OnUnitKilled` before
anything clears it, and it is cleared later by `PlatoonDisband` and
`platoon-base.lua:516`. Had that not held, every loss would have landed in
`unassigned`.

## Air is a co-equal mass sink and was on nobody's list

`nativeAir` loses 10,890-15,040 mass per losing cell, comparable to or exceeding
`nativeLand`. The Aeon Tech 2 gunship `uaa0203` is built 47-59 times and lost 57
times on both Isis cells. No priority in the investigation report mentions air.

## Almost nothing survives

Built against lost against still held, by blueprint:

| cell | blueprint | built | lost | held |
| --- | --- | ---: | ---: | ---: |
| Syrtis 31337 | `xal0203` | 76 | 76 | 0 |
| Syrtis 31337 | `ual0201` | 43 | 43 | 0 |
| Syrtis 31337 | `ual0104` | 23 | 23 | 0 |
| Isis 8675309 | `ual0103` | 28 | 28 | 0 |
| Isis 8675309 | `xal0203` | 16 | 16 | 0 |

The force does not accumulate anywhere. This is attrition at the point of
production, not a production shortfall, and it reframes priority 3: the question
is not whether the factories produce enough but why none of it is retained.

`xal0203` -- the `T2AttackTank` the report flagged -- is 76 built and 76 lost on
Syrtis 31337. That is the single largest blueprint loss in the set.

Caveat: `lost` exceeds `built` for a few blueprints (`uaa0203`, 47 built against
57 lost on Isis 8675309). A mobile unit destroyed inside a factory that dies
mid-build is counted lost and never counted built. That is real, not a
miscount, but it means these columns are not an inventory equation.

## Factories are idle about half the time

Sample-sums of ready/building/upgrading/idle:

| cell | L1 | L2 | A1 |
| --- | --- | --- | --- |
| Isis 8675309 | 135/43/18/**63** | 81/26/18/**32** | 31/9/9/**11** |
| Syrtis 31337 | 139/34/24/**74** | 152/59/12/**73** | 110/28/7/**69** |

Roughly 40-63% of ready-factory samples are idle. That is the usable-capacity
question the report asked for, now measured.

## Directed platoons chase and never arrive

| cell | samples | median size | max | idle per unit | within 35 of target | median observed enemy | median own support |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Isis 8675309 | 106 | 3 | 4 | 0.01 | **2.8%** | 2.4 | 72.2 |
| Isis 31337 | 89 | 3 | 4 | 0.12 | 22.5% | 15.8 | 54.0 |
| Syrtis 8675309 | 104 | 3 | 4 | 0.04 | **1.9%** | 5.0 | 41.8 |
| Syrtis 31337 | 122 | 3 | 6 | 0.04 | **0.0%** | 2.4 | 44.8 |
| Sentry Point 31337 | 9 | 3 | 4 | 0.09 | 11.1% | 2.7 | 42.7 |

Median size three confirms the report's order-event finding against live
inventory. They are not stuck -- idle per unit is near zero and they move 72-76
map units a minute -- they simply never converge. The aim point changes between
consecutive samples **68.2%** of the time on Isis 8675309 and **40.5%** on
Syrtis 31337, and `ObjectiveAttack` issues `Stop()` and a fresh
`AggressiveMoveToLocation` on every change. Median observed enemy threat of
2.4-15.8 against own support of 41.8-72.2 says they spend that time away from
enemies.

So the directed plan *is* defective in the way the offline probe suggested --
no arrival handling, perpetual re-aim at a moving target -- but the force it
mishandles is a fifth to a third of what dies. Fixing it cannot by itself close
a 1.7x to 3.4x gap sitting in native platoons.

## Sludge 8675309 is the opposite failure

Total combat losses are 880 mass. `xsl0201` is built 13 times and lost **zero**
times; `xss0103` 8 built, 1 lost, 8 held. Naval factories are busy every sample
(15 ready-samples, 15 building) but the whole match produces roughly 33 combat
units. This cell does not lose its army. It never builds or commits one, which
is a separate investigation from everything above.

## Revised order

1. **Native platoon losses and air.** Two thirds to three quarters of the dying
   mass is outside the directed plan, and air alone rivals land. Neither was on
   the list. Establish what native land and air platoons are being sent at
   before touching the directed plan.
2. **Retention, not output.** Built equals lost for nearly every blueprint while
   40-63% of ready-factory samples sit idle. The force is produced and destroyed
   piecemeal.
3. **Directed arrival.** Real, mechanism now measured, but bounded to a fifth or
   a third of the losses. The specific defect is re-aim churn at 40-68% per
   sample with no arrival or convergence handling.
4. **Sludge separately**, as the report said, and for the opposite reason to the
   large maps.

## Gaps in the instrument

Against the report's three requirements: controller inventory, mass, idle and
losses are covered; per-controller plan and task are not. Per-platoon formation,
size, target, position, distance, local threat and support are covered;
departure and arrival transitions, retreat and retarget events, and per-platoon
losses are not. The defensive requirement against *arrived* force is not
implemented at all -- the existing `claim=` field reports claims only.

# Round two: what the native plans are, and the defence chain end to end

Same six cells, with loss and living mass attributed to the native task
(`PlatoonFormManager` writes `PlanName` and `BuilderName` onto the handle) and
with the defensive chain measured from requirement through to arrival. All six
clean, all outcomes unchanged.

## The two plans that only appear in the losses

Turnover is lost mass per unit of standing mass-sample: high means the force is
consumed as fast as it is made instead of accumulating.

| plan | lost across the 4 losses | held mass-samples | turnover | lost in the win |
| --- | ---: | ---: | ---: | ---: |
| `StateMachineAI` | 58,660 | 401,106 | 0.152 | 2,472 |
| `RedQueenDirected` | 50,567 | 214,506 | 0.242 | 1,332 |
| `GuardMarker` | 39,720 | 103,680 | **0.383** | **0** |
| `GunshipHuntAI` | 12,420 | 18,750 | **0.662** | **0** |
| `ArmyPool` | 6,865 | 302,794 | 0.024 | 290 |
| `AttackForceAI` | 0 | 4,840 | 0.000 | 0 |

`GuardMarker` and `GunshipHuntAI` together lose **52,140** mass across the four
losses -- more than the directed plan's 50,567 -- and lose **exactly nothing in
the winning cell**. They are the two fastest-turnover plans in the set.
`GunshipHuntAI` is consumed 4.4x faster per unit of standing force than
`StateMachineAI`.

`StateMachineAI` is the largest absolute loser everywhere, including the win,
at the second-lowest turnover. It is the workhorse, not the leak.

`AttackForceAI` holds 4,840 mass-samples and loses nothing at all. It exists and
never fights.

### What feeds `GunshipHuntAI`

There is **no directed air plan**. `Red Queen Directed Land Attack` exists;
nothing equivalent for air, so every air unit is handed to native plans.

`Red Queen T2 Air Dominance` (priority 930) and `Red Queen T2 Land Dominance`
(priority 930) are the same unconditional shape: `ShouldBuildDominantTier`
passes whenever the domain's highest tier equals that tier and there is no
stall. No cap, no target, no check that the previous batch survived. They
produce exactly the two blueprints with ~100% loss rates, `uaa0203` and
`xal0203`. `GunshipHuntAI` holds 18,750 mass-samples against 12,420 lost: the
gunship force never accumulates because it is consumed as fast as it is built.

## The defence chain: a claim is not protection, and the deficit is mostly phantom

Per-sample means.

| cell | required | available | claimed | deficit | sent | arrived | arrival rate |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Isis 8675309 | 72.9 | 30.2 | 10.3 | 63.4 | 1.8 | 0.1 | **6.8%** |
| Isis 31337 | 76.4 | 15.4 | 5.9 | 70.6 | 7.9 | 0.9 | 11.9% |
| Syrtis 8675309 | 242.4 | 55.7 | 40.2 | 221.1 | 0.6 | 0.2 | 25.0% |
| Syrtis 31337 | 87.7 | 20.9 | 9.7 | 78.2 | 4.1 | 0.1 | **1.2%** |
| Sludge 8675309 | 13.9 | 16.9 | 7.4 | 6.8 | 0.9 | 0.9 | 100.0% |
| **Sentry Point 31337 (win)** | 82.0 | **6.9** | 2.6 | 79.4 | 1.6 | 0.6 | 37.0% |

Two things fall out, and they point in opposite directions from the report's
reading.

**Arrival is genuinely broken.** Of the force claimed and ordered to a defensive
objective, 1.2% to 37% is actually standing there when sampled. The secondary
slot could report what it took; it could never report that almost none of it
got there.

**The deficit itself is not a claim-ceiling problem.** `available` -- the
eligible reserve, measured before anything is taken -- is 8% to 45% of the
requirement on every land cell. The ceiling is not holding force back and the
attack is not outbidding the defence; there is simply not enough claimable force
to meet the number. And the **winning** cell has the worst ratio in the set,
6.9 available against 82.0 required, or 8%. Deficit does not separate a win from
a loss any more than directed share did.

The structural reason: `ClaimForSecondary` draws only on `GatherAvailableUnits`,
which is the ArmyPool. Pool share of living combat mass:

| cell | pool share |
| --- | ---: |
| Isis 8675309 | 15.1% |
| Isis 31337 | 10.3% |
| Syrtis 8675309 | 47.7% |
| Syrtis 31337 | 16.0% |
| Sentry Point 31337 | 12.1% |

The defence can only ever bid for roughly a seventh of the army, because native
plans hold the rest. A requirement scaled to observed threat is being compared
against a reserve that structurally cannot match it.

## Revised reading

1. **`GuardMarker` and `GunshipHuntAI`.** Highest turnover, 52,140 mass across
   the four losses, zero in the win. Neither was on any priority list. For the
   air half the feeding mechanism is identified: an unconditional Tech 2
   dominance tap with no directed air plan to steer what it makes.
2. **Defensive arrival, not defensive allocation.** 1.2-37% of dispatched
   defenders are at their objective. The allocation shortfall is a measurement
   artefact of comparing a threat-scaled requirement against a pool holding a
   seventh of the army; it does not discriminate wins from losses.
3. **Directed arrival** stays where round one left it -- real, bounded to a
   fifth to a third of losses.
4. `AttackForceAI` never fighting and `StateMachineAI`'s low turnover both say
   the ordinary native land workhorse is not the problem.

## Instrument status

Requirement 1 is now complete: controller inventory, mass, idle, losses, **and
the plan or task each belongs to**. Requirement 3 is complete: requirement,
eligible reserve, claimed, deficit, dispatched and arrived, per defensive kind.
Requirement 2 still lacks departure and arrival transition events, retreat and
retarget events, and per-platoon losses.

# What is assigning `GuardMarker` and `GunshipHuntAI`

Read out of the installed archive (`~/.faforever/gamedata/lua.nx2`), not guessed.
Red Queen names neither plan anywhere: `grep -rn "GuardMarker\|GunshipHuntAI"
lua/ hook/` is empty. Both are native, and Red Queen's only contribution is the
mass that feeds them.

## `GunshipHuntAI` — the loop

`lua/AI/AIBuilders/AIAirAttackBuilders.lua`, template `GunshipAttack`:

| builder | priority | instances | conditions |
| --- | ---: | ---: | --- |
| `GunshipAttackT2Frequent` | 100 | 5 | pool has **4+** gunships; fewer than 1 Tech 3 air |
| `GunshipAttackT1Frequent` | 100 | 5 | pool has 2+ gunships; fewer than 1 Tech 2/3 air |
| `GunshipAttackT1Cap` | 100 | 5 | unit cap above 90% |

`lua/platoon.lua:2688` is the plan itself:

```lua
target = self:FindClosestUnit('Attack', 'Enemy', true,
    categories.EXPERIMENTAL * (categories.LAND + categories.NAVAL + categories.STRUCTURE))
if not target then
    target = self:FindClosestUnit('Attack', 'Enemy', true, categories.ALLUNITS - categories.WALL)
end
...
self:AggressiveMoveToLocation(tableCopy(target:GetPosition()))
...
WaitSeconds(17)
```

It flies at the **closest enemy unit of any category** with **no threat check of
any kind** -- no anti-air avoidance, no threshold, nothing -- and reassesses
every seventeen seconds. Mobile anti-air and static anti-air are as attractive
as an extractor.

The loop is closed by our own production. `Red Queen T2 Air Dominance` (priority
930) fires on `ShouldBuildDominantTier` alone: air's highest tier is 2 and there
is no stall. No cap, no target, no check that the previous batch survived. So:
build gunships unconditionally, four of them reach the pool, native forms up to
five hunt platoons, they fly into anti-air, they die, build more. Red Queen has
**no directed air plan**, so nothing interrupts it at any point.

That is the 0.662 turnover.

## `GuardMarker` — two different builders share the name

| builder | template | priority | instances | conditions | sends units to |
| --- | --- | ---: | ---: | --- | --- |
| `Mass Hunter Gunships` | `GunshipMassHunter` | 950 | 2 | **none -- all commented out** | random `Mass` markers |
| `Expansion Area Patrol` | `StartLocationAttack2` | 925 | 2 | game time < 300s | random `Expansion Area` markers |

The marker path does gate on threat (`MinThreatThreshold 50`,
`MaxThreatThreshold 140`), which the hunt path does not. `Mass Hunter Gunships`
runs all match with no conditions at all; the land patrol only forms in the
first five minutes.

One native oddity worth recording but not overstating: that builder sets
`MoveNext = 'GunshipHuntAI'` with the comment `--DUNCAN - was guardbase`.
`MoveNext` is a marker-selection mode -- `Random`, `Threat`, `Closest` or
`None` -- not a plan name. `platoon.lua:1103` assigns it into `MoveFirst` and
recurses, so from the second marker onward the selection mode is a string the
code does not recognise. The effect on target choice is not measured here.

**Limitation.** The telemetry attributes losses by plan, not by plan crossed with
blueprint, so the split of `GuardMarker`'s 39,720 mass between the air mass
hunters and the early land patrol is not established. The unconditional,
all-match half of it is the air one.

## The discriminator

| cell | gunships built | lost | still held | air tier | result |
| --- | ---: | ---: | ---: | --- | --- |
| Isis 8675309 | 47 | 57 | 6 | A2 | defeat |
| Isis 31337 | 28 | 28 | 0 | A3 | defeat |
| Syrtis 8675309 | 42 | 42 | 0 | A3 | defeat |
| Syrtis 31337 | 59 | 57 | 2 | A3 | defeat |
| **Sentry Point 31337** | **2** | **0** | 3 | A2 | **victory** |

The winning cell reaches air Tech 2 and simply never pours mass into the
pipeline -- two gunships, none lost. It is not that the win lacks the tier; it
is that it never runs the loop. Every losing cell builds 28 to 59 and loses
essentially all of them.

## Where a correction would go

The smallest lever that is ours is `Red Queen T2 Air Dominance`. It is our
builder, our priority, and it is what fills the pool that native drains into
anti-air. Native's `GunshipHuntAI` having no threat gate is not ours to fix and
hooking it is a much larger change than the evidence justifies yet.

Falsifier for that lever: if constraining gunship production simply moves the
mass into another unconditional tap -- `T2 Land Dominance` is the same shape at
the same priority -- with the same turnover, then the defect is the shape of the
dominance builders and not air specifically. Both taps are `ShouldBuildDominantTier`
at 930, and `xal0203` already dies at 76 built for 76 lost, so that is the
likelier reading and must be tested before treating this as an air problem.

Opportunity cost of constraining it: gunships are the only Red Queen answer to
an enemy that fields no anti-air, and the `GunshipCounter` doctrine holds for
30-38% of samples on these cells. A cap must not make the doctrine inert.
