# Scouting isolation

Status: configurations and contract checks prepared. **Do not launch either
matrix until the user gives the go-ahead.** No behavioral conclusion follows
from these checks.

`FAF_SCOUTING_MODE` selects a match-scoped scenario option. It requires
`FAF_FIXED_RUNTIME=1` for either isolation arm; `run-matrix.sh` already sets that.
An unknown mode, or an arm without its launch overlay, fails before starting FAF.

| Mode | Scout production | Red Queen directed dispatch |
| --- | --- | --- |
| `combined` (default) | Coverage-scaled, 5–18% | Dedicated scouts and combat-unit fallback |
| `production-only` | Same coverage-scaled rule | Disabled, including fallback |
| `dispatch-only` | Previous binary rule: 15% with no observations, otherwise 7% | Both dispatch paths enabled |

Coverage measurement and native FAF scouting remain active in every mode.
Production-only therefore still measures the blind share it uses to size scout
production. The commitment gate, terrain profiles, engineer ceiling, and cover
sizing are unchanged by mode selection.

After approval, select the arm without editing the payload, for example:

```bash
FAF_SCOUTING_MODE=production-only ./scripts/run-matrix.sh 1 SCMP_037 2071971 2 3 production-only-sludge-aeon-s1
FAF_SCOUTING_MODE=dispatch-only ./scripts/run-matrix.sh 2 SCMP_037 2071971 2 3 dispatch-only-sludge-aeon-s1
```

Use unique labels or separate `FAF_MATRIX_LOG_DIR` directories for the arms.
Follow the runtime pre-flight in `AGENTS.md`, use at most two simultaneous cells,
and keep production tracing off. Seton's is a two-team map: retain its two 3v3
cells. Saltrock retains the two 2v2v2 cells.

Reuse all 21 cases from the scout-matrix plan for each arm, with the same maps,
seeds, faction requests, preferences policy and layouts. The case list is
preserved in [scouting-isolation-cases.json](scouting-isolation-cases.json).
Its `2v2` cases use `FAF_MIXED=2` through `run-smoke.sh`; the named `FAF_LAYOUT`
values are only `3v3` and `2v2v2`. Do not pass `2v2` as a named layout.
Compare the arms with the existing sizing and combined-scouting results by
matched cell. Keep the 14 strict 1v1 cells separate when assessing mass exchange:
in team games Red Queen's defeat and the final statistics can occur at different
times. Win/loss, coverage, scout counts and dispatches are supporting measures;
the earlier gains remain suggestive and attribution remains open until measured.

Each manifest and overlay `sources.json` records `scouting_mode`. Each Red Queen
brain logs its actual selection, for example:

```text
scouting mode=production-only production=adaptive dispatch=off
scouting mode=dispatch-only production=binary dispatch=on
```

The periodic state line retains `scout=targets/blind/sent-this-pass` and adds:

- `scoutorders=dedicated/fallback`: cumulative directed orders since startup.
- `scouts=N`: currently held mobile scouts, including those in native platoons.
- `scoutfraction=F`: the requested production share, not actual completed production.

`summarize-matrix.py` groups by payload **and** mode, rejects contradictions
between the manifest and runtime configuration, and reports sampled blind share,
cumulative orders, peak scout count and the range of requested fractions for
the first Red Queen army, matching its K/L row. Cumulative orders cover the last
diagnostic sample, not necessarily the end of the match. Existing logs lack
those totals; their last-pass counts must not be summed as complete dispatch
counts. Logs without a recorded mode remain `unrecorded`; a manifest without a
runtime selection line is labeled `unverified`.

## Both arms run — 2026-09-16

Go-ahead given. Both arms run across the eight LandLarge cells (Fields of Isis
and Syrtis Major, Aeon against Cybran, four seeds each), same payload as the
`combined` series.

| Arm | Record |
| --- | --- |
| `combined` | 0W/8L |
| `production-only` (dispatch off) | 1W/7L |
| `dispatch-only` (binary production) | 0W/8L |

Scouting is not what is wrong with LandLarge. No arm wins it.

### `dispatch-only` reproduces `combined` exactly

| cell | combined | dispatch-only | production-only |
| --- | --- | --- | --- |
| Isis 8675309 | defeat 15149 | defeat **15149** | defeat 9581 |
| Isis 31337 | defeat 17425 | defeat **17425** | defeat 10661 |
| Isis 2071971 | defeat 12653 | defeat **12653** | defeat 8777 |
| Isis 5772156 | defeat 20177 | defeat **20177** | defeat 18885 |
| Syrtis 8675309 | defeat 21717 | defeat **21717** | defeat 20421 |
| Syrtis 31337 | defeat 28165 | defeat **28165** | victory 26413 |
| Syrtis 2071971 | defeat 20529 | defeat **20529** | defeat 20953 |
| Syrtis 5772156 | defeat 19317 | defeat **19317** | defeat 20421 |

Every cell ends on the same tick. The only difference between those two arms is
scout production sizing — coverage-scaled against the old binary 15%/7% rule —
so identical matches mean that sizing has **no effect on the simulation at all**.

### Why: the production lever is not connected

`demand.Scouts` has exactly one consumer, `Diagnostics.lua` writing
`scoutfraction=` into the state line. No production code reads it, and
`CounterBuilders` subtracts `categories.SCOUT` from its builders, so Red Queen
never requests a scout. Every scout in every match comes from native FAF
builders, which is why scout counts never varied between arms.

So the "coverage-scaled, 5-18%" production mechanism described above does not
exist in effect. It is computed, clamped, probed and reported, and nothing
builds anything because of it. The scout ceiling probe recorded in
`docs/variety-matrix.md` was inert for the same reason, and that was the first
symptom rather than a separate result.

### What directed dispatch is worth

`production-only` turns it off, and that changes every match — the ticks differ
in all eight. It is worse in five of the eight, and substantially so early:
9581 against 15149, 10661 against 17425, 8777 against 12653. It wins one cell.
So directed dispatch is doing real and mostly useful work; 1W/7L against 0W/8L
is not an improvement worth reading on eight samples.

### What is left

The LandLarge weakness is not in scout production, which does nothing, nor in
directed dispatch, whose removal makes things worse. Blindness at 55-67% is
real, but the arms show it is not being caused or cured here. What remains
untested is whether blindness costs anything: coverage feeds the commitment
gate, where an unobserved destination is indistinguishable from one seen and
empty. That is measured by commitment holds and by what waves do on arrival.

## The lever wired, and what blindness costs — 2026-09-16

`demand.Scouts` now drives two builders, air before land. It binds: on Syrtis
`31337`, the cell characterised in every arm above, the same seed goes from
defeat at tick 28165 to **victory** at 30125, K/L 0.73 to 1.13 against an
opponent falling from 1.27 to 0.82, blind 56% to 50%, scouts held 12 to 15, and
peak mass 43.1 to 67.2.

Across the eight LandLarge cells:

| Arm | Record |
| --- | --- |
| `combined` | 0W/8L |
| `dispatch-only` | 0W/8L |
| `production-only` | 1W/7L |
| **wired** | **2W/6L** |

Both wins are on Syrtis. Fields of Isis stays 0W/4L in every arm.

### Blindness costs something

Thirty-two LandLarge runs now exist across four arms, sharing maps, seeds,
faction and opponent. Three are victories, and they are the 1st, 4th and 9th
least blind runs of the thirty-two:

- victory blind: **50%, 52%, 55%**
- defeat blind: min 51%, median 59%, max 71%
- a victory is less blind than a defeat in **79 of 87** pairings
- all three victories fall in the nine least-blind runs: p = 0.017 under a
  random-rank null

Scouts held tells the same story: 8, 14 and 15 for the victories against a
defeat median of 6.

That is the first direct evidence that coverage is worth something on these
maps rather than merely correlating with them. It is three victories, so it is
a signal and not a settled magnitude, and blindness co-varies with scout count
and with match length.

### What has never been tested

**Blind has never gone below 50% on a LandLarge map** — the observed range
across all thirty-two runs is 50-71%, while Naval and LandSmall sit at 15-31%.
The two bands do not overlap anywhere. So the relationship above is measured
entirely inside the blind half of the range, and the question "what happens when
a large map is actually covered" has never been asked.

Wiring the production lever moved blind by about six points at best. Getting
into the 15-31% band needs the coverage budget itself to scale with the map:
`ObserversPerUpdate` 16, `ObservationRadius` 48 and `IntelLifetimeSeconds` 180
are fixed while LandLarge is four times the area of LandSmall. That is the next
thing to change, and now there is a measure that will show whether it works.

## Sampling rate was never the constraint — 2026-09-16

Proposal 3 was to scale the observer budget with map area, on the reasoning that
`ObserversPerUpdate` 16 is fixed while LandLarge is four times the area of
LandSmall. It was implemented, measured, and **refuted**, then reverted.

Terrain sampling scaled with area while the enemy proximity query kept its fixed
budget. On Syrtis `31337` the result was byte-identical to the run before it:
victory at tick 30125, mean blind 50% over 51 samples. Nothing moved.

The arithmetic says it never could. Intel updates every 20 ticks, so a 180
second intel lifetime spans 90 passes. At 16 observers per pass that is 1440
observer-samples per lifetime, against an army of order 50 to 100 units — every
unit was already being sampled roughly 15 to 30 times before any of its
observations expired. The army was never under-sampled. Raising the rate re-reads
the same units standing in the same places and records the same terrain cells.

The binding constraint is **where the units are**, not how often they are read.
Coverage exists only where something has physically been, and an army occupies a
small fraction of a 10 km map however often its positions are sampled. Lowering
blindness on a large map therefore means going to more places — which is
dispatch, already enabled, and whose removal in `production-only` made things
worse — or changing what coverage is measured over.

That leaves the candidate set. `GetScoutTargets` scores every mass cluster on the
map: 16 on Isis and 21 on Syrtis, against 3 on Sludge. Most are irrelevant to the
current objective, and each one nothing has visited counts as blind. A blind
share computed over a bounded, objective-relevant set would measure something the
army can actually act on, and would not be structurally unsatisfiable at scale.
That is the next thing to test, and it is cheap.

### Cost of the attempt

`IntelManager.__init` probed `MapSize` with `if MapSize then`. The strict global
metatable raises on reading a name that does not exist yet, and the brain is
constructed before the engine has published that global, so `Create` threw: zero
brains started, seven Red Queen log lines, and a recorded victory that meant
nothing at all. The contract gate passed throughout, because specs supply their
own permissive environment. `AGENTS.md` now carries the rule.
