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
