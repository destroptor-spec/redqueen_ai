# Faction composition under mirror matchups, 2026-09-22

Read with [storage-placement.md](storage-placement.md), whose "Mirror matchups"
section establishes the setting: every cell of the earlier 24-cell baseline used
opponent faction 3, so Cybran's cells were mirrors and the rest were
cross-matchups. The faction ranking that came out of it was partly a property of
the test design.

Under mirrors — both sides the same faction, so faction balance cancels and only
Red Queen against the stock Adaptive AI remains:

| faction | mirror record | mean mass K/L |
| --- | --- | --- |
| Cybran | **4W/2L** | 1.76 |
| UEF | 1W/5L | 0.97 |
| Aeon | 1W/5L | 0.61 |
| Seraphim | 1W/5L | 0.85 |

Six cells per faction: Fields of Isis and Syrtis Major, seeds 2071971, 424242
and 8675309. Payload `24c0b34595dc`, the control tree, unchanged throughout.

## Where the advantage is not

**Not production rate.** Per game minute Cybran builds 7.61 units and UEF 7.65;
Aeon 6.62 and Seraphim 4.90. An earlier reading that "Cybran wins by building
less" was confounded by match length -- UEF's six mirrors ran 409 game minutes
against Cybran's 202. Cybran wins sooner; it does not build less per minute.

**Not the air exchange.** Air kills scored by each side, summed over six mirrors:

| | Cybran | UEF | Aeon | Seraphim |
| --- | ---: | ---: | ---: | ---: |
| air kill ratio (ours/theirs) | **1.02** | 1.09 | **1.56** | 1.36 |

Cybran has the *worst* air exchange of the four and wins anyway. Every losing
faction beats it in the air. A composition hypothesis built on anti-air and
mobile shields is not supported by this.

**Not support share on its own.** Units built per game minute:

| role | Cybran | UEF | Aeon | Seraphim |
| --- | ---: | ---: | ---: | ---: |
| direct fire | 3.13 | **4.30** | 3.68 | 1.76 |
| fighter + gunship | **3.34** | 1.95 | 1.69 | 2.50 |
| mobile AA | **0.36** | **0.15** | 0.25 | 0.20 |
| mobile shield | 0.00 | **0.94** | 0.62 | 0.03 |
| artillery | **0.38** | 0.21 | 0.28 | 0.28 |

UEF builds six times more mobile shields than mobile AA and has the lowest AA
rate; Cybran builds no mobile shields because it has none. That contrast is real
but the air result above shows it is not what decides these matches.

## Where the advantage is

Land units lost by each side, summed over six mirrors:

| | Cybran | UEF | Aeon | Seraphim |
| --- | ---: | ---: | ---: | ---: |
| land loss ratio (theirs lost / ours lost) | **2.68** | **1.51** | 1.80 | 1.84 |

**Cybran trades land units at 2.68:1 while the others manage 1.51 to 1.84.** It
does so while building *fewer* direct-fire units per minute than UEF (3.13
against 4.30). UEF builds the most land units of any faction and trades them
worst.

In a mirror the unit matchup is neutral by construction. Applying the skill's
test -- unit matchup, missing support, execution failure or economic
disadvantage -- matchup is excluded and economy is close (production rates
within 15% for Cybran and UEF). That leaves support and execution, and the land
exchange is where the difference appears.

## What to measure next

The target for composition work is the **land exchange ratio**, not air and not
support share. Cybran at 2.68:1 is a worked example of Red Queen using a roster
better than the stock AI uses the same roster. UEF at 1.51:1 with the highest
direct-fire output is the clearest deficit.

That frames a question about how land units are supported and committed rather
than which ones are produced. Before acting on it, note that
[red-queen-lessons.md](../../../.claude/skills/faf-strategy-engineering/references/red-queen-lessons.md)
records that lifetime loss counts do not establish a combat exchange without
attacker-attributed kills; the engine's per-category `kills` used here is
attacker-attributed and is the right field for that reason.

## Measurement limits

- **Telemetry mass totals are contaminated where experimentals appear.** In
  `mirror-syrtis-424242-aeon` the engine itself reports army 2 with
  `experimentals built=0 lost=19` while army 3 built 1 and scored 18 kills. Red
  Queen's own telemetry records 15 CZAR deaths for units never built, at 42,750
  mass each -- 641,250 mass, 82% of that cell's telemetry total, which is why it
  read 784k lost against 324k built. Blueprint and controller sums agree exactly
  with each other, so this is not double counting in the analyzer; it follows an
  engine accounting anomaly. `combatdeathrepeats=0`.
- **Consequently plan- and controller-level mass attribution is unusable in any
  cell containing experimentals.** The `unassigned` bucket reading 555,750 mass
  in that cell was phantom experimentals, not a real controller.
- **Mass K/L is unaffected.** It comes from `general.lost.mass` and
  `general.kills.mass`; 245,087 there is far below the 812k the phantom
  experimentals imply, so that field excludes them.
- **Built counts are clean**, because the phantom units carry `built=0`. Every
  composition figure above uses built counts or engine category stats.
- An earlier check for enemy-unit contamination -- finding no `ur*` blueprints
  in a UEF-versus-Cybran cell -- was **insufficient**: absence only shows the
  enemy built none of those types, and in a mirror both sides share blueprint
  prefixes, so that test cannot detect contamination at all.

Fixing the telemetry to exclude experimental-category units from its mass sums,
or reconciling it against `general.lost.mass` per sample, is a prerequisite for
any further plan-level attribution.

# Wiring demand into production: falsified, and why

`demand.Land`, `demand.Air` and `demand.Artillery` were computed, clamped and
written to the periodic state line with **no consumer at all** -- the same defect
`demand.Scouts` had before `CounterBuilders.lua:175` gave it one. `demand.Land`
swings 0.15 to 0.60 by doctrine and changed nothing.

The candidate gave `ShouldBuildDominantTier` -- the tap that fires on tier
availability alone, with no target of any kind -- the target it never had: stop
adding to a domain already at or above its demanded share. Guarded so an army
under ten combat units is not shaped, and an unpublished demand leaves the tap
untouched. Naval keeps its own `NavalDominanceMinimumDemand`. New state-line
field `domainshare=L<held>/<wanted>,A<held>/<wanted>`.

Twenty-four mirror cells, against the mirror baseline.

| | baseline | demand consumer |
| --- | --- | --- |
| record | 7W/17L | 8W/16L |
| mean mass K/L | **1.05** | **0.93** |
| cells above K/L 1.0 | **8** | **7** |

**The land exchange ratio -- the discriminator -- did not move for any losing
faction:**

| faction | land ratio base | land ratio candidate |
| --- | ---: | ---: |
| Cybran | **2.68** | **1.94** |
| UEF | 1.51 | 1.53 |
| Aeon | 1.80 | 1.77 |
| Seraphim | 1.84 | 1.79 |

The composition was actively reshaped -- `domainshare` shows Red Queen holding
0.80 to 1.00 land against a 0.60 demand, so the gate was firing constantly --
and the exchange rate was unchanged for UEF, Aeon and Seraphim. The only faction
whose ratio moved is the one that was good at it, and it fell by 0.74.

**Production mix is therefore not the lever.** Reshaping what is built left the
rate at which it trades untouched. This was the stated prediction before the run
and it held; it is the cleanest available falsification of the composition
framing.

**Why a share gate cannot rebalance on its own.** `domainshare=L1.00/0.60,
A0.00/0.50` on Syrtis 424242 UEF: capping land production does not create air
production. The gate is purely suppressive, so total force falls while the trade
rate stays put, which is why mean K/L dropped 1.05 to 0.93 while the record
moved +1. Turning demand into production needs the under-supplied role to be
*raised*, not merely the over-supplied one capped -- and that is a different
change from this one.

**Not adopted.** Preserved as `demand-to-production.patch`; tree on control
payload `24c0b34595dc`.

**Correction, 2026-09-22: they were not orphans.** `demand.Land` and
`demand.Air` are read by `ProductionManager.GetFactoryTargets`, which iterates
`{ "Land", "Air", "Naval" }` and reads `demand[domain]` **by index**. A grep for
dotted `demand.Land` cannot see that, and on the strength of one I deleted both.
The result is not subtle: with Land and Air nil and Naval at 0.05 on a land map,
nothing clears the `>= 0.10` relevance test, `relevant` falls back to `{"Land"}`
and every factory in the match is allocated to land. The run diverged from the
control at state sample 11 and the deletion was reverted.

Only `demand.Artillery` has no consumer by either access path. One field, not
three, and not worth a change on its own.

The lesson is about method, not about demand: **a dotted grep does not establish
that a Lua table field is unread**, because `t[k]` with `k` from a list is
invisible to it. `scripts/validate_mod.py` had the same blind spot in the
contract written alongside that deletion; it now counts a quoted field name
beside an indexed read as consumption, so the contract can no longer recommend
deleting a live consumer.

# Command ownership and idle share: neither discriminates

Measured from the mirror logs, time-weighted over six cells per faction.

| share of living combat mass | Cybran | UEF | Aeon | Sera |
| --- | ---: | ---: | ---: | ---: |
| Red Queen directed | 12.2% | 11.6% | 7.7% | 6.3% |
| native platoons | 40.9% | 35.4% | 19.1% | 24.9% |
| uncommanded (pool + unassigned) | **46.8%** | 52.9% | **73.2%** | 68.8% |

| idle share | Cybran | UEF | Aeon | Sera |
| --- | ---: | ---: | ---: | ---: |
| whole combat army | 30.8% | 29.9% | **25.0%** | 34.8% |
| within ArmyPool | 58.7% | 56.9% | 55.5% | 54.9% |
| within unassigned | 82.4% | 85.5% | 84.2% | 77.8% |

Ownership does not order with the result: Cybran has the lowest uncommanded
share, but UEF is second-lowest at 52.9% with the *worst* land exchange (1.51).
Idle is anti-correlated: the winning faction is second-worst at 30.8% while Aeon
is best at 25.0% and has the lowest mean K/L (0.61).

Two absolute figures survive as inefficiencies rather than discriminators, and
they are uniform across factions: **Red Queen directly commands 6-12% of its
combat army**, and **25-35% of that army is idle at any sample**.

# The discriminator is economic, not tactical

`income=1.00` on both sides of every mirror, so the following is not a handicap
artifact. Per game minute, summed over six cells per faction:

| | Cybran | UEF | Aeon | Seraphim |
| --- | ---: | ---: | ---: | ---: |
| stock / Red Queen **mass income** | **1.01** | 1.29 | 1.18 | **1.33** |
| stock / Red Queen **mass built** | **1.06** | 1.29 | 1.29 | **1.42** |
| Red Queen mass K/L | **1.70** | 1.05 | 0.67 | 0.77 |
| land exchange ratio | **2.68** | 1.51 | 1.80 | 1.84 |

**Cybran is the one faction where Red Queen is not out-produced, and the only
faction it beats.** On Seraphim the stock Adaptive AI earns a third more mass a
minute and builds 42% more. That is not a fight lost on tactics; it is entered
with substantially less material.

This corrects two earlier readings in this document's own history. "Cybran is
our strongest faction" was first an artifact of it being the only mirror in a
cross-matchup baseline, and is now better explained as the only faction where
the economies are level. And economy was ruled out earlier on the grounds that
production rates were within 15% *between Red Queen's own factions* -- a
comparison that never included the opponent and therefore could not see this.

It also explains the session's run of failed tactical candidates. Re-aim
hysteresis, composition mix, demand-to-production, mass storage and the gunship
gate all rearrange a force that is 18-42% smaller than the one it fights.

**Next question, and it is answerable from the existing state line:** why does
Red Queen earn 18-33% less mass a minute than the stock AI on three factions and
not on Cybran? Extractor counts, upgrade timing, energy and factory counts over
time are all already recorded per sample.

## The economy is faction-independent; the opponent's is not

Red Queen's own economy at matched game minutes, averaged over six mirror cells
per faction (mass and energy are per-tick engine income):

| minute | Cybran | UEF | Aeon | Seraphim |
| --- | --- | --- | --- | --- |
| 10 | 6.4 mass, 97 nrg, 11 fac, 20 mex | 8.6, 98, 11, 20 | 9.4, 101, 11, 21 | 6.8, 100, 10, 21 |
| 20 | 14.5, 267, 14, 17 | 12.6, 272, 14, 17 | 15.7, 279, 15, 21 | 11.9, 294, 13, 16 |
| 30 | 26.9, 1057, 17, 19 | 23.5, 831, 16, 17 | 24.1, 1065, 18, 19 | 20.6, 790, 15, 15 |

Nearly identical. The 1.18-1.33 income gap is therefore **the opponent's
economy varying by faction, not ours**. Stock Adaptive builds a much stronger
economy with UEF, Aeon and Seraphim than with Cybran; Red Queen's is uniformly
mediocre.

So Cybran mirrors are level because *both* AIs are weak with Cybran's economy.
This is the third distinct correction to "Cybran is our strongest faction": an
artifact of being the only mirror in a cross-matchup baseline, then the only
faction where we are not out-produced, and now the only faction where the
opponent is equally mediocre.

### The absolute figures

- **Peak extractors 21-23 against 46 mass points** on these maps -- under half
  the available resource access -- reached by minute 8-14.
- **Then it declines**: 20-21 held at minute 10 becomes 15-19 by minute 30.
- **Factories plateau at 10-11 by minute 10** and reach only 15-18 by minute 30.

That is goal 2 of the strategy skill failing on both halves: claim, and retain.
It is faction-independent and upstream of every tactical candidate tried this
session, which is consistent with all of them failing.

**This is where the next work belongs.** It is also the same shape as the only
change that has worked: the defence-alert scope on extractor upgrades, which
removed an economic blocker and moved 6W/6L to 7W/5L.
