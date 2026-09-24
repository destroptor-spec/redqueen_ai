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

# Why small maps are won and large maps are lost

## The army is split across more places on a large map

Distinct aim points are the rounded target positions the directed plan actually
pursued, so this is where the army was sent, not where it could have gone.

| cell | size | distinct aim points | max spread | result |
| --- | --- | ---: | ---: | --- |
| Sentry Point 31337 | 5 km | **3** | **101** | victory |
| Syrtis Major 31337 | 10 km | 7 | 231 | defeat |
| Syrtis Major 8675309 | 10 km | 12 | 288 | defeat |
| Fields of Isis 31337 | 10 km | 13 | 345 | defeat |
| Fields of Isis 8675309 | 10 km | **19** | **358** | defeat |

Median platoon size is three in every one of these cells. On Sentry Point that
army has three places to be and they are within 101 of each other. On Fields of
Isis the same three-unit platoons are spread across nineteen destinations up to
358 apart. Nothing in the terrain concentrates them, and nothing in the code
does either.

This is the same figure the win/loss discriminator asked for. Peak army, income,
tech and map share do not separate wins from losses; the winning cell is worst
on nearly all of them. Dispersion does.

## Red Queen has no model of a land approach

`WorldModel` models `NavalApproaches` -- and only naval. There is no land
corridor, choke, front or approach concept anywhere in the brain:

```
$ grep -rn "Approach\|Corridor\|Choke\|Lane" lua/AI/RedQueen/WorldModel.lua
  ... NavalApproaches only
$ grep -rn "Approach\|Corridor\|Choke" lua/AI/RedQueen/Profile.lua
  (nothing)
```

And the entire difference between a 5 km map and a 20 km map is **one boolean**:

```lua
self.Scale = "Small"
if world.MapKilometers >= Constants.Policy.LargeMapKilometers then
    self.Scale = "Large"
    self.Name = self.Name == "LandSmall" and "LandLarge" or self.Name .. "Large"
    self.Flags.TierReadinessObsolescence = true
end
```

`TierReadinessObsolescence` is about when to retire low-tier production. Nothing
about the number of ways in, force distribution, reinforcement travel time, how
many places must be held at once, or concentration.

So on a small map the terrain concentrates the force for free and Red Queen
wins. On a large map nothing concentrates it, and the brain has no
representation that would let it notice. `maps.md` in the strategy skill asks
for exactly the missing primitive -- *"number, width and connectivity of viable
approaches"* and *"path distance and estimated travel time to each contested
site"* -- and lists what it changes: *"force concentration, flanks, congestion,
reserve placement, and whether a single defensive position matters."*

A suggestive corroboration, not proof: the one domain where Red Queen **does**
model approaches is naval, and Sludge is 4 wins from 5. Size and approach
modelling are confounded there -- Sludge is also 5 km -- so this cannot carry
weight on its own. The land side is clean: no approach model, and every large
land cell is lost.

## The measurement that would justify building one

Concentration: per sample, the largest own combat mass within one engagement
radius of a single own cluster, over total own combat mass. If the winning cell
sits near 1 and the losing cells near 0.2, then committing piecemeal is the
disease, the approach model is the missing primitive, and the fix belongs in
`CombatManager`'s commitment gate rather than in any builder.

If concentration is similar across wins and losses, this hypothesis is wrong and
the collapse after parity is something else -- reinforcement access or retreat
paths next.

# Concentration: hypothesis falsified

Concentration is own combat mass inside the heaviest axis-aligned box of side
100, over total own combat mass. Prediction stated before the run: near 1 in the
win, near 0.2 in the losses.

| cell | size | mean | late-match | occupied cells | result |
| --- | --- | ---: | ---: | ---: | --- |
| Sentry Point 31337 | 5 km | **0.63** | 0.63 | 6.3 | victory |
| Sludge 8675309 | 5 km | **0.99** | 1.00 | 3.4 | **defeat** |
| Fields of Isis 8675309 | 10 km | 0.58 | 0.55 | 9.1 | defeat |
| Fields of Isis 31337 | 10 km | 0.66 | 0.54 | 7.4 | defeat |
| Syrtis Major 8675309 | 10 km | 0.60 | 0.58 | 8.2 | defeat |
| Syrtis Major 31337 | 10 km | 0.54 | 0.50 | 9.5 | defeat |

**The prediction was wrong.** The winning cell sits inside the losing range, and
the most concentrated army in the set -- Sludge at 0.99 -- loses. Occupied cells
differ slightly (6.3 against 7.4-9.5) but nothing like the 3-against-19 the
directed aim points suggested.

The measure is biased *toward* small maps -- a 100-side box is about 15% of a
5 km map's area against 4% of a 10 km map's -- and the small map still scores no
higher. That strengthens the falsification rather than weakening it.

The 3-against-19 dispersion figure was a **directed-plan artefact**. Directed
platoons are a fifth to a third of the force; the whole army does not behave
that way. That risk was stated before the run and it is what happened.

Syrtis Major 8675309's 70,250 peak combat mass is one CZAR (`uaa0310`, ~42,000
mass), so its denominator is not comparable to its siblings. Its concentration
of 0.60 is mid-range either way.

# The discriminator is the exchange rate

Engine end-of-match `JsonStats`, army 2:

| cell | mass built | mass lost | mass killed | **kill/loss** | result |
| --- | ---: | ---: | ---: | ---: | --- |
| Sentry Point 31337 | 50,591 | 10,160 | 11,407 | **1.12** | victory |
| Sludge 8675309 | 21,734 | 9,478 | 3,091 | 0.33 | defeat |
| Fields of Isis 8675309 | 253,415 | 104,714 | 44,290 | 0.42 | defeat |
| Syrtis Major 31337 | 254,665 | 127,240 | 68,758 | 0.54 | defeat |
| Syrtis Major 8675309 | 286,027 | 138,015 | 81,396 | 0.59 | defeat |
| Fields of Isis 31337 | 198,265 | 81,143 | 54,087 | 0.67 | defeat |

Clean separation, no overlap: the win is the only cell above 1.0. And it is not
volume -- the losing cells build four to five times as much mass and trade it
away at roughly two to one against.

Everything else measured this session fails to discriminate: map share (~50%
everywhere), income, peak army, tech tier, directed share of losses, defensive
deficit, and now concentration. On several of them the winning cell is the
worst in the set.

# What the exchange rate is made of

Units completed by role, from the blueprint archive:

| role | Sentry Point (win) | Isis 8675309 | Syrtis 31337 |
| --- | ---: | ---: | ---: |
| direct-fire | 68.6% | 51.7% | 52.4% |
| **fighter** | **21.4%** | 3.9% | 7.4% |
| **gunship** | **2.9%** | **22.9%** | **19.9%** |
| artillery | 5.7% | 13.7% | 3.4% |
| mobile AA | 0% | 0.5% | 8.4% |
| shield | 0% | 6.8% | 7.8% |

The win builds fighters and almost no gunships, seven to one. The losses invert
it, four to six gunships per fighter, and those gunships die at essentially
100%: 47 built against 57 lost, 59 against 57.

So a fifth to a quarter of all unit output on the losing cells goes into the
pipeline already documented above -- `Red Queen T2 Air Dominance` firing on tier
availability alone, filling a pool that native `GunshipAttackT2Frequent` drains
into `GunshipHuntAI`, which attacks the closest enemy unit of any category with
no threat check whatsoever.

**This revises an earlier judgement in this document.** The gunship pipeline was
called "a leak, not the disease" on the grounds that leaks had not changed an
outcome before. That was too quick. It is a fifth of production at a 0:1 trade,
and the exchange rate is the one measure that separates the win from the losses.

Confound to respect: one win against five losses, and the win is a 5 km map
where air matters less. The composition correlation cannot carry a conclusion on
its own. What does not depend on the correlation is the mechanism -- an
unconditional builder, a native plan with no threat gate, and 100% loss rates
measured per blueprint.

# Standing state

| candidate | status |
| --- | --- |
| map control | measured, does not discriminate |
| concentration / piecemeal commitment | **falsified** |
| income, tech, peak army | measured, win is worst |
| directed-plan arrival | real, bounded to a fifth to a third of losses |
| defensive arrival | real (1.2-37%), deficit does not discriminate |
| **exchange rate** | **the only clean discriminator found** |
| gunship output share | strongest mechanism feeding it |

# Implementation experiment: T2 gunships follow counter demand

The resumed implementation uses `84555d4` as its starting point. The earlier
readiness experiment remains outside the checkout. The concentration result
does not justify adding a global gathering rule or a new land-front system in
this experiment.

The intervention is confined to `ShouldBuildT2Air`: its dominance builder must
pass the same doctrine, affordability and fleet-quota decision as the explicit
gunship counter builder. Previously, after `StrategyDirector` abandoned a
gunship response, this sibling could continue replacing gunships simply
because air tier remained T2. The explicit counter, other domains, factory
upgrades and platoon plans retain their existing behavior.

`airdominance=counter/doctrine/quota/tier-or-stall/none` in the periodic state
reports the last evaluation of this condition. It is eligibility telemetry,
not a construction-start counter. Completed output and losses still come from
`combat-production`, and the plan attribution from `combat-plans`.

The hypothesis is that respecting the counter's exit and quota reduces
unrequested gunship replacement, leaving resources for more useful output.
The falsifier is that gunship output does not materially change, or its lost
mass simply moves into equally costly land attrition without improving the
matched outcomes. Lost winning cells count as regressions. The principal cost
is fewer gunships against enemies with weak anti-air; the existing positive
counter path must continue to work.

Contracts cover an active counter, a full quota, reopening below quota,
Balanced/AirDefense rejection, stall rejection, and leaving T2 dominance after
T3 access. The runtime comparison uses all twelve established cells, including
all seven wins, at `income=1.00`, two concurrent games at most.

Two interpretation limits remain important when evaluating it. A blueprint's
100% lifetime loss rate does not establish a 0:1 trade: kills by those attackers
were not measured. Also, the exchange-rate separation above is for the selected
six cells, not the whole baseline: the Sentry Point UEF baseline wins at about
0.81 mass K/L. Neither total K/L nor completed-unit counts alone identify the
responsible policy; the intervention and its displaced production must be read
together.

## Global gate rejected; scope follows the measured profile

Four cells completed on global-gate payload
`0d6826b23f2020f7b94a1998864589bd5622608b279aaab4d48d2e5617e562f3`:

| cell | baseline | global gate | baseline / candidate mass K/L |
| --- | --- | --- | --- |
| Isis 8675309 | defeat | **victory** | 0.423 / 1.469 |
| Isis 31337 | defeat | defeat | 0.667 / 0.890 |
| Syrtis 8675309 | defeat | defeat | 0.590 / 0.376 |
| Sentry Point 2071971 Aeon | **victory** | defeat | 1.399 / 1.315 |

The remaining queue was stopped; the two already-running cells completed and
were analyzed normally. No completed match was truncated. The global policy
is not retained.

Isis 8675309 supplies a completed mechanism example: T2 Specters fall from
47 to 18 completions, T3 Harbingers rise from 23 to 55, and one Galactic
Colossus completes where none did in the control. `GunshipHuntAI` loses 4,050
mass in the control and has no recorded losses in the candidate. This supports
the spending hypothesis on this cell; the other cells show why it cannot yet
be generalized.

The candidate now assigns `DemandDrivenGunships` only to `LandLarge` through
the existing profile selection. Small land, mixed and naval profiles use their
original T2 dominance condition, reported as `airdominance=legacy`. This is a
measured scope restriction, not a claim that size alone explains combat losses.
The scoped twelve-cell verification uses payload
`e1f97d29559e15aa4882af430e24b35dbf1292903275677ba1b64a45d251d724`.

## Scoped result: retain, 8W/4L with all seven previous wins preserved

All twelve cells completed. The current extractor-scope control is **7W/5L**;
the scoped gunship change finishes **8W/4L**. Fields of Isis, seed 8675309,
changes from defeat to victory. No winning control changes to defeat.

All opponents below are Cybran stock Adaptive, with strict 1v1 `income=1.00`.
The reference logs are `/tmp/rq-m-mexscope-<case>.log`; the candidate logs are
`/tmp/rq-m-combat-airland-<case>.log`. Each has its launch manifest and patch.

| case | map | RQ faction | control → scoped | mass K/L control → scoped |
| --- | --- | --- | --- | --- |
| isis-8675309-aeon | SCMP_015 | Aeon | defeat → **victory** | 0.423 → 1.469 |
| isis-31337-aeon | SCMP_015 | Aeon | defeat → defeat | 0.667 → 0.890 |
| syrtis-8675309-aeon | SCMP_017 | Aeon | defeat → defeat | 0.590 → 0.376 |
| syrtis-31337-aeon | SCMP_017 | Aeon | defeat → defeat | 0.540 → 0.928 |
| small-2071971-aeon | SCMP_018 | Aeon | victory → victory | 1.399 → 1.399 |
| small-31337-aeon | SCMP_018 | Aeon | victory → victory | 1.123 → 1.123 |
| small-2071971-uef | SCMP_018 | UEF | victory → victory | 0.806 → 0.806 |
| naval-2071971-aeon | SCMP_037 | Aeon | victory → victory | 2.258 → 2.258 |
| naval-2071971-cybran | SCMP_037 | Cybran | victory → victory | 2.768 → 2.768 |
| naval-2071971-sera | SCMP_037 | Seraphim | victory → victory | 2.294 → 2.294 |
| naval-31337-sera | SCMP_037 | Seraphim | victory → victory | 1.085 → 1.085 |
| naval-8675309-sera | SCMP_037 | Seraphim | defeat → defeat | 0.326 → 0.326 |

All eight cells outside `LandLarge` reproduce their control's complete
contestant `JsonStats`, ignoring generated army names and the unused human
slot. This is stronger than outcome agreement for the tested controls, but it
does not establish balance on untested maps or factions.

The scoped Isis win reproduces the global experiment's 18 Specters, 55
Harbingers and one completed Colossus. The other large-land cells also reduce
T2 gunship completions: Isis 31337 from 28 to 9, Syrtis 8675309 from 42 to 15,
and Syrtis 31337 from 59 to 12. The doctrine condition opens and closes in all
four large-land logs. The fleet-quota boundary is contract-tested; these logs
do not contain a sampled `airdominance=quota` refusal.

**The retained change has a measured cost.** Syrtis 8675309 loses with worse
mass K/L, and its T3 Harbinger completions fall from 25 to zero. Fewer gunships
does not reliably become stronger land output. Whole-match production counts
also cover different match durations, so they describe the resulting army
composition rather than proving the marginal value of each saved gunship.

Verification: `./scripts/validate.sh` and `git diff --check` pass. Every match
passes `scripts/analyze-log.py`, starts one Red Queen brain, and reports zero
Red Queen Lua or scheduler failures. All twelve manifests have the scoped
payload hash above, and their file hashes match the retained Lua tree. Native
FAF advisory failures remain separately reported by the analyzer. The runner
completed its queue; a host process scan found no remaining game processes.
Audit and production comparisons are recorded in
`/tmp/rq-combat-20260919/resumed/airland-audit.json` and
`/tmp/rq-combat-20260919/resumed/airland-comparison.json`.

This closes the existing twelve-cell comparison, not the broader release
matrix. Large-land behavior here covers Aeon against Cybran on two maps and
two seeds; mixed terrain, other large-land factions, team games, Sweepwing and
Crossfire remain unverified for this change.

The next investigation should trace the first production divergence in the
remaining Syrtis losses: counter activation/exit, actual air support, and what
factories produce after the dominance builder stands down. The regression in
land completion is a concrete lead. The current concentration metric does not
justify a global gathering rule, and this result does not settle the value of
local pressure or defense coverage on open maps.
