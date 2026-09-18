# Variety matrix — 2026-09-07

## Why this exists

Every behavioural conclusion in this project up to now rested on one match per
configuration. Three of those conclusions turned out to be wrong, and all three
failed the same way: a single sample was read as a property of the code when it
was a property of the seed.

This document records the first run series large enough to tell those apart. It
is deliberately organised around what the evidence *retracts*, because that is
where the value is.

## Method

Twelve matches, four at a time, each a strict 1v1 against stock `adaptive-ai`
under `victory=Assassination` with `FAF_FIXED_RUNTIME=1`. Concurrency is safe
because each cell gets its own preferences slot (`RQTest<1-6>.prefs`), so no two
instances race the same write-back. `scripts/run-matrix.sh` is the runner; the
harness baseline is in `AGENTS.md`.

All twelve runs share one payload hash, `0cbb34c70ae5`, recorded independently in
each `<log>.manifest.json`. That is what makes them comparable: the numbers below
differ only by map, seed and faction, never by tree state. Check the hash before
adding a row — a result measured against a different payload belongs in a
different table.

Determinism was confirmed separately: two launches of one cell produced
byte-identical logs (tick 7697, built 34804).

## Results

| Map | Profile | Seed | Red Queen | Result | K/L | Opponent K/L |
| --- | --- | --- | --- | --- | --- | --- |
| Sludge `SCMP_037` | Naval | 2071971 | Aeon | victory | 1.85 | 0.38 |
| Sludge `SCMP_037` | Naval | 2071971 | Cybran | victory | **3.36** | 0.24 |
| Sludge `SCMP_037` | Naval | 2071971 | Seraphim | defeat | 0.64 | 0.65 |
| Sludge `SCMP_037` | Naval | 8675309 | Seraphim | defeat | **1.47** | 0.38 |
| Sludge `SCMP_037` | Naval | 31337 | Seraphim | victory | 0.72 | 0.91 |
| Sentry Point `SCMP_018` | LandSmall | 2071971 | Aeon | defeat | 0.63 | 1.44 |
| Sentry Point `SCMP_018` | LandSmall | 31337 | Aeon | victory | 1.08 | 0.87 |
| Sentry Point `SCMP_018` | LandSmall | 2071971 | UEF | victory | 0.79 | 1.25 |
| Fields of Isis `SCMP_015` | LandLarge | 8675309 | Aeon | victory | 1.03 | 0.63 |
| Fields of Isis `SCMP_015` | LandLarge | 31337 | Aeon | defeat | 0.60 | 1.32 |
| Syrtis Major `SCMP_017` | LandLarge | 8675309 | Aeon | victory | 1.12 | 0.76 |
| Syrtis Major `SCMP_017` | LandLarge | 31337 | Aeon | defeat | 0.40 | 2.11 |

By profile: Naval 3W/2L, LandSmall 2W/1L, LandLarge 2W/2L.

## What this retracts

### The naval gain is not the hover fix

The hover/amphibious graph split was justified against an Aeon match, on the
reasoning that Aeon's whole early army and all three engineer tiers are `HOVER`
and were being path-gated on a graph they do not use. That reasoning is still
correct as a defect analysis, but it cannot be what won the naval map: **Cybran
has zero hover units and posts the best naval result in the series at 3.36.**

The naval win therefore belongs to T1 naval production and to water objectives
becoming expressible at all, not to the hover routing. Keep the hover fix — it
is correct and free — but stop crediting it.

### Seraphim on Sludge is not a faction defect

One sample said otherwise: same map, same seed, same profile, Aeon 1.85 and
Cybran 3.36 against Seraphim 0.64. Three seeds say it is ordinary variance.

Seraphim goes 1W/2L on Sludge, and the seed-8675309 defeat is the point: Red
Queen finished it with a mass kill/loss of **1.47 against the opponent's 0.38**,
having out-produced and out-traded the opponent roughly four to one. It lost
because its commander died two seconds after killing the opponent's. That is not
an economic or production failure, and the run before it — the 0.64 — was one
draw from the same distribution.

Checked and rejected as explanations: per-faction unit costs are near-identical
(T1 frigate 250-290 mass across factions, with Seraphim *cheaper* than Aeon at
270 against 290; engineers, factories, extractors and power identical), and all
four commanders share one blueprint profile (`AMPHIBIOUS`/`LAND`, `RULEUMT`,
speed 1.7, Seraphim second-highest HP at 11500).

### Commander loss carries no information here

Every defeat in the table has `cdr lost = 1` and every victory has `0`. Under
`victory=Assassination` that is a tautology — the match ends when the commander
dies — so the column cannot be evidence for anything. It is recorded here only
to stop it being rediscovered as a finding.

### The Isis/Syrtis disagreement never existed

`TierReadinessObsolescence` is on for `LandLarge` for exactly one reason, stated
in `Profile.lua`: Fields of Isis improved with it and Syrtis Major moved the
other way, so it was "left on here so the disagreement stays measurable against a
recorded baseline."

With three seeds the two maps never disagree:

| Seed | Fields of Isis | Syrtis Major |
| --- | --- | --- |
| 2071971 | defeat | defeat |
| 8675309 | victory (1.03) | victory (1.12) |
| 31337 | defeat (0.60) | defeat (0.40) |

They agree at every seed. The original disagreement was two maps sampled at one
seed each, which is a seed difference wearing a map difference's clothes. The
justification for the flag is void.

That does not by itself mean the flag is harmful, so it is being settled by a
controlled A/B rather than by argument.

## Support commanders and experimentals

These were called out as unvalidated. The series settles half of the question and
shows the other half is not answerable from this instrumentation.

| Run | Map | Result | SACUs built | SACUs lost | Experimentals built |
| --- | --- | --- | --- | --- | --- |
| `seed-isis` | Fields of Isis | victory | **7** | 0 | **1** (`ual0401`, Galactic Colossus) |
| `isis-s3` | Fields of Isis | defeat | **6** | 0 | 0 |
| `syrtis-s3` | Syrtis Major | defeat | 1 | 0 | 0 |
| `isis-off-s2` | Fields of Isis | defeat | 3 | 0 | 0 |
| every other run | Sludge, Sentry Point, Syrtis @8675309 | — | 0 | 0 | 0 |

The first three rows are the `0cbb34c70ae5` payload; `isis-off-s2` is the
readiness-off arm and is listed only to show support commanders appear there
too, not for comparison against the rows above it.

**Support commanders reach the field, and survive.** Six and seven of them on
Fields of Isis, none lost in any run. So the build path works and is not a
theoretical capability — but it only engages on the large dry maps, and it is
uneven even there (Syrtis Major produced 7 fewer than Isis at one seed and none
at the other).

**Experimentals essentially do not.** One completed across sixteen matches. Even
the two longest, best-fed runs — Fields of Isis reaching mass 41 and energy 1908
— produced one Galactic Colossus between them. If experimentals are meant to be
a real part of the endgame, that is the finding to act on.

### What these counters cannot tell us

The engine's per-category `kills` field counts *enemy* units of that category
destroyed by the whole army — not kills achieved by that unit type. Verified
against a case with unambiguous direction: a Red Queen army shows
`ura0303 built=0 lost=0 kills=9`, i.e. it built none of that Cybran blueprint and
destroyed nine.

So `sacu kills=0` means the opponent lost no support commanders. It is **not**
evidence that Red Queen's own support commanders never fought, and must not be
read that way. Whether they contribute combat value or are being used purely as
mobile engineers needs per-unit attribution, which `JsonStats` does not provide —
the production trace or a targeted fixture would be the way to measure it.

## A/B: is `TierReadinessObsolescence` worth keeping?

The flag's justification was void, which is not the same as the flag being
wrong, so it was measured rather than argued about. Four cells on the recorded
`LandLarge` seeds, one arm per setting, payload `d40ba61667aa` for the off arm
against `0cbb34c70ae5` for the on arm.

| Map | Seed | Readiness on | Readiness off |
| --- | --- | --- | --- |
| Fields of Isis | 8675309 | victory 1.03 | defeat 0.39 |
| Fields of Isis | 31337 | defeat 0.60 | victory 1.30 |
| Syrtis Major | 8675309 | victory 1.12 | defeat 0.74 |
| Syrtis Major | 31337 | defeat 0.40 | defeat 0.31 |
| | **record** | **2W/2L**, mean K/L 0.79 | **2W/2L**, mean K/L 0.69 |

The two arms are indistinguishable on record and separated by 0.10 mean K/L,
which is far inside the seed-to-seed spread this same profile shows (0.40 to
1.12 with the setting held fixed). What the flag does do is perturb: it flipped
three of the four individual outcomes, in both directions. Large effect per
match, no direction across matches.

**Conclusion: keep it on, and stop treating it as a tuning knob.** The decisive
argument is not the A/B, which is a wash — it is that on *is* the intended
semantics. Unfinished factories should count toward capacity planning while only
completed ones obsolete lower-tier production; off gets that wrong, and the
measurement says correctness costs nothing here.

The live question this exposes is the reverse of the original one: `Naval`,
`Mixed` and `LandSmall` all still run with obsolescence keyed on `Highest`, which
is *not* the intended semantics. Extending the flag to them is untested. Note
that the Sludge regression once attributed to readiness gating (victory 3.33 to
defeat 1.05) predates the `Highest`/`Ready` split and does not bear on this —
that failure came from gating capability, which no longer happens.

## Standing caveats

- **`FAF_MIXED=2` does not produce a 2v2.** The human occupies `ARMY_1` of four
  starts, so it yields 2v1. Every result labelled 2v2 before 2026-09-07 was
  measured that way and should be treated as unverified.

  Superseded rather than fixed: `FAF_LAYOUT=3v3` and `FAF_LAYOUT=2v2v2`
  (sentinels 49 and 50) place one Red Queen army among stock Adaptive allies and
  opponents, and need seven or more AI starts. `SCMP_009`, Seton's Clutch, has
  eight and confirms as `allies=3 enemies=3` and `allies=2 enemies=4`
  respectively. `FAF_MIXED=2` remains as it was; prefer a layout.
- **Opponent count is logged but unused.** `Profile.lua` records `allies` and
  `enemies` in its selection line and no `When` condition reads either, so the
  profile set scopes by terrain and size only.
- **Manifest seeds before this date are wrong.** `record-runtime.py` hardcoded
  `seed: 2071971` into every manifest regardless of `FAF_SEED`; it now records
  the launched value along with both faction settings. Seeds for the runs above
  were verified at launch from `/proc/<pid>/cmdline`, not read from those
  manifests.

# Re-run after the V9 review fixes — 2026-09-16

Same twelve cells, payload `c6c64e797a84`, against the series above
(`0cbb34c70ae5`). Strict 1v1 versus stock `adaptive-ai`, `victory=Assassination`,
`FAF_FIXED_RUNTIME=1`. Zero Red Queen Lua failures and zero scheduler failures
in all twelve.

| Map | Profile | Seed | Red Queen | Was | Now | K/L was | K/L now | Opp K/L |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Sludge `SCMP_037` | Naval | 2071971 | Aeon | victory | victory | 1.85 | **6.01** | 0.14 |
| Sludge `SCMP_037` | Naval | 2071971 | Cybran | victory | **defeat** | 3.36 | 0.32 | 2.05 |
| Sludge `SCMP_037` | Naval | 2071971 | Seraphim | defeat | **victory** | 0.64 | 3.41 | 0.24 |
| Sludge `SCMP_037` | Naval | 8675309 | Seraphim | defeat | **victory** | 1.47 | 3.65 | 0.25 |
| Sludge `SCMP_037` | Naval | 31337 | Seraphim | victory | victory | 0.72 | **6.39** | 0.14 |
| Sentry Point `SCMP_018` | LandSmall | 2071971 | Aeon | defeat | **victory** | 0.63 | 2.10 | 0.41 |
| Sentry Point `SCMP_018` | LandSmall | 31337 | Aeon | victory | victory | 1.08 | 1.83 | 0.53 |
| Sentry Point `SCMP_018` | LandSmall | 2071971 | UEF | victory | **defeat** | 0.79 | 1.21 | 0.77 |
| Fields of Isis `SCMP_015` | LandLarge | 8675309 | Aeon | victory | **defeat** | 1.03 | 1.18 | 0.77 |
| Fields of Isis `SCMP_015` | LandLarge | 31337 | Aeon | defeat | defeat | 0.60 | 1.03 | 0.92 |
| Syrtis Major `SCMP_017` | LandLarge | 8675309 | Aeon | victory | **defeat** | 1.12 | 0.86 | 1.13 |
| Syrtis Major `SCMP_017` | LandLarge | 31337 | Aeon | defeat | defeat | 0.40 | 0.73 | 1.27 |

Overall 7W/5L becomes 6W/6L. By profile:

| Profile | Was | Now |
| --- | --- | --- |
| Naval | 3W/2L | **4W/1L** |
| LandSmall | 2W/1L | 2W/1L |
| LandLarge | 2W/2L | **0W/4L** |

## The gate is not satisfied

LandLarge lost every cell. That is the regression, and it is not visible in the
trading figures: K/L *rose* in three of those four cells while all four became
defeats. This is the failure mode `docs/large-map-expansion-investigation.md`
already names — what is left of an army after a starved economy trades
reasonably per unit, there is simply far less of it — so the outcome column is
the one that moved, not the ratio.

What separates the LandLarge cells from the rest in this series:

| | Naval + LandSmall | LandLarge |
| --- | --- | --- |
| mean blind | 15-31% | 55-66% |
| extractors held, peak | 33-72% of map | 34-48% of map |
| engineers at or below target | 9-31% of samples | 4-5% of samples |
| builders suppressed | none reported | 126-168 |

Across the whole series, forward bases established 2 of 17 attempts (12%), lost
to `engineer-lost=5, manager-lost=3, route-unsafe=2, destroyed=1, no-factory=1`.

K/L improved in ten of twelve cells. The two that fell are Sludge Cybran
(3.36 to 0.32, the only outcome flip on a naval map) and Syrtis 8675309.

## What this series cannot settle

Each cell is one sample, which is the whole thesis of the series above: seed
alone has flipped an outcome on the same map, faction and profile. Six of these
twelve outcomes differ from the baseline, and that is a larger flip rate than a
single-sample comparison can attribute to the code.

The baseline table never recorded **opponent faction**. This re-run used Cybran,
or Aeon where Red Queen was Cybran, following the examples in
`docs/scouting-isolation.md` and `docs/testing.md`. The Sludge Cybran row is the
one most exposed to that: it is the only naval outcome flip, and it is exactly
the row whose opponent cannot be confirmed to match.

Before reading the LandLarge result as a property of the code, re-run those four
cells at a second seed each. If they hold, the economy figures above are where
to look, not the combat ones.

**Re-run 2026-09-16: they hold.** Each LandLarge map was run at two further
seeds, `2071971` and `5772156`, same faction and opponent, same payload.

| Map | Seed | Result | K/L | Opp K/L | mean blind |
| --- | --- | --- | --- | --- | --- |
| Fields of Isis | 8675309 | defeat | 1.18 | 0.77 | 66% |
| Fields of Isis | 31337 | defeat | 1.03 | 0.92 | 55% |
| Fields of Isis | 2071971 | defeat | 0.45 | 2.08 | 63% |
| Fields of Isis | 5772156 | defeat | 0.42 | 2.21 | 58% |
| Syrtis Major | 8675309 | defeat | 0.86 | 1.13 | 56% |
| Syrtis Major | 31337 | defeat | 0.73 | 1.27 | 56% |
| Syrtis Major | 2071971 | defeat | – | – | 65% |
| Syrtis Major | 5772156 | defeat | 0.42 | 2.33 | 67% |

**0W/8L over four seeds on two maps.** This is not seed variance. The two fresh
seeds are also the worse half: K/L 0.42-0.45 against an opponent trading at
2.08-2.33, where the original pair read 0.73-1.18. The first four cells were
flattering, not unlucky.

The discriminator is vision, and it is present in every cell: mean blind
**55-67%** on LandLarge against 15-31% on Naval and LandSmall, with no overlap
between the two groups. Scout orders are not the shortfall — Syrtis issues 86 to
175 of them — so the army is looking and still cannot see, which points at
coverage per observer and map size rather than at dispatch.

Whether this is a regression or a pre-existing weakness the baseline's two wins
masked cannot be settled from four baseline samples. It does not need to be: on
eight samples the current code does not win this profile at all, and that fails
the gate either way.

One cell, Syrtis `2071971`, recorded its result but no end-of-match statistics,
so its K/L is absent above rather than zero.

## Runner note

`run-matrix.sh` does not terminate. The match reaches `GameEnded` and the client
sits on the score screen indefinitely, so the wrapper waits forever on a process
that has already produced its result. The first pair of this re-run consumed
6h53m of wall time for two matches that had finished in 11 and 16 minutes of
game time. With a watcher that stops on `lifecycle game-result`, a cell costs 80
to 300 seconds, and the whole twelve is well under an hour.

Run cells **one at a time**. Two concurrent instances spike memory hard enough
during Wine startup to be killed, even with 22 GiB available.

## Scout ceiling probe: correct, and inert — 2026-09-16

The scout fraction was pinned near its ceiling for whole LandLarge matches, so
production was capped by a probe that steps the ceiling down while blindness
will not move and the scouts we have stay alive. In a match it does exactly
that: on Syrtis `31337` the ceiling walked 0.180, 0.160, 0.140, 0.120, 0.080,
0.050 and the request followed it down.

**It changed nothing else.** The same cell, same seed, before and after:

| | pinned | probed |
| --- | --- | --- |
| requested fraction | 0.090-0.174 | 0.050-0.174 |
| K/L | 0.73 | 0.73 |
| scout orders / peak held | 175 / 12 | 175 / 12 |
| factories / engineers | 24 / 48 | 24 / 48 |
| extractors built / lost | 39 / 25 | 39 / 25 |
| peak mass | 43.1 | 43.1 |
| end tick | 28165 | 28165 |

Asking for 5% scouts instead of 17% produced the same army, the same scouts and
the same match. So the premise behind the change — that blindness was taxing
production on large maps — **is not supported**. `demand.Scouts` does not move
what gets built here. Native FAF scouting stays active in every mode and the
scout count never varied, so the fraction is not the lever it looks like.

That redirects the LandLarge question rather than answering it. Blindness at
55-67% is real, and 175 scout orders holding 12 scouts did not move it, but the
cost of it is not scout production. The causal path left to test is the one the
`GetScoutTargets` comment already names: coverage feeds the commitment gate, and
an unobserved destination reads as a threat of zero, which is indistinguishable
from seen-and-empty. That is where the damage would show, and it is measured by
commitment holds and by what waves do on arrival, not by production shares.

The probe is kept because it is correct, bounded and contract-covered, and it
costs nothing where it does not bind. It should not be counted as a fix.

# Scout wiring measured across all twelve cells — 2026-09-16

The scout production lever was wired and validated on eight LandLarge cells
only. It changes global behaviour, so the whole matrix was re-run at
`b5674abd28c3` against the post-review series `c6c64e797a84` and the original
`0cbb34c70ae5`.

| Profile | baseline | post-review | wired |
| --- | --- | --- | --- |
| Naval | 3W/2L | **4W/1L** | 3W/2L |
| LandSmall | 2W/1L | 2W/1L | 2W/1L |
| LandLarge | 2W/2L | 0W/4L | **1W/3L** |
| total | 7W/5L | 6W/6L | 6W/6L |

It is a wash on record, and it trades: Syrtis `31337` flips to victory,
Sludge Seraphim `2071971` flips to defeat. One win bought on the profile it was
aimed at, one lost on the profile that was already healthy.

**K/L fell in eleven of the twelve cells**, mean 2.39 to 1.28, two-sided sign
test p = 0.006. That is not noise, and the direction is consistent across every
profile including the one whose record improved.

The reason is straightforward once stated: before this, Red Queen built no
scouts at all, and the fraction is blind-scaled but never zero, so it now spends
5 to 18% of production on scouts **everywhere** — including the maps where
native FAF scouting was already sufficient and blindness sits at 15-31%. On
those maps the spend buys nothing and costs army.

The lever is correct and it does what it claims. Where it should be allowed to
spend is a separate question, and the evidence says it should not be everywhere:
confine it to maps where coverage is structurally short, rather than paying the
tax on every profile to win one LandLarge cell.

These are single samples per cell, so individual flips are not conclusive. The
K/L direction across eleven of twelve is.


## 2026-09-17: the session measured against its own starting point

The table above is from an older tree. Measured today, `0a9c707` — the commit
this session began from — also scores 7W/5L but **not on the same cells**: it
loses Sentry Point UEF, Fields of Isis 8675309 and Syrtis Major 8675309, and
wins Sludge 8675309 and Sentry Point 2071971 Aeon. Comparing against the
recorded table therefore invented three regressions that were never real. A
baseline has to be measured on the tree being changed, not read from a document.

Both matrices below were run the same morning, same harness, same seeds,
opponent Cybran, zero scheduler failures in all 24 cells. Runs are
deterministic, so one run per cell is exact rather than a sample.

| cell | anchor `0a9c707` | HEAD, ownership off |
| --- | --- | --- |
| Sludge 2071971 Aeon | victory | victory |
| Sludge 2071971 Cybran | victory | victory |
| Sludge 2071971 Seraphim | defeat | **victory** |
| Sludge 8675309 Seraphim | victory | victory |
| Sludge 31337 Seraphim | victory | victory |
| Sentry Point 2071971 Aeon | victory | victory |
| Sentry Point 31337 Aeon | victory | victory |
| Sentry Point 2071971 UEF | defeat | defeat |
| Fields of Isis 8675309 | defeat | defeat |
| Fields of Isis 31337 | defeat | defeat |
| Syrtis Major 8675309 | defeat | defeat |
| Syrtis Major 31337 | victory | **defeat** |
| **record** | **7W/5L** | **7W/5L** |

Net neutral on record: one cell gained, one lost.

| profile | anchor | now |
| --- | --- | --- |
| Naval | 4W/1L | **5W/0L** |
| LandSmall | 2W/1L | 2W/1L |
| LandLarge | 1W/3L | **0W/4L** |

The economy moved and the record did not. Peak capture rose from 44% to 49% of
map points and extractors built from 230 to 272, which is the opening engineer
floor doing what it was built to do across twelve cells rather than one.

Forward bases went the other way: 4 of 15 established to 3 of 21, with
`route-unsafe` rejections doubling from 5 to 10. More attempts, a worse hit
rate, and that is the clearest single lead for the LandLarge profile.

With `FormationOwnership` on, the same tree scores **3W/9L**. It is off.


## 2026-09-18: the instrument is deterministic, and the audited fixes cost one cell

Two full matrices run back to back on an identical tree, twelve cells each,
zero scheduler failures in all twenty-four.

**Run A and run B agree on every cell.** The harness reproduces exactly: it
kills instances on a timer, terminates processes mid-write and runs under
varying memory pressure, and none of that changes a result. A single-cell
difference between two trees is therefore signal, not noise, and cell-level
attribution from this matrix is sound.

That was worth establishing. Most of the previous session steered by single-cell
flips without ever checking that the instrument could resolve them.

| cell | baseline | run A | run B |
| --- | --- | --- | --- |
| Sludge 2071971 Aeon | victory | victory | victory |
| Sludge 2071971 Cybran | victory | victory | victory |
| Sludge 2071971 Seraphim | victory | victory | victory |
| Sludge 8675309 Seraphim | victory | **defeat** | defeat |
| Sludge 31337 Seraphim | victory | victory | victory |
| Sentry Point 2071971 Aeon | victory | **defeat** | defeat |
| Sentry Point 31337 Aeon | victory | victory | victory |
| Sentry Point 2071971 UEF | defeat | **victory** | victory |
| Fields of Isis 8675309 | defeat | defeat | defeat |
| Fields of Isis 31337 | defeat | defeat | defeat |
| Syrtis Major 8675309 | defeat | defeat | defeat |
| Syrtis Major 31337 | defeat | defeat | defeat |
| **record** | **7W/5L** | **6W/6L** | **6W/6L** |

Two cells lost, one gained: net one cell down on the baseline.

For scale, the same fixes written to fight native rather than coordinate with
them scored **3W/9L**, and the directed-platoon work alone scored 5W/7L. The
audit recovered most of that ground without reaching parity.

The four LandLarge cells have now lost under every tree measured across two
days, including the session anchor. Nothing attempted has moved them.

## No Tech 2 engineer ever exists on LandLarge

Watching one of those cells with the new `watch` line found a mechanism.

Every Red Queen fortification builder for a Tech 2 defence -- point defence,
anti-air, shield, tactical missile -- declares `PlatoonTemplate =
"T2EngineerBuilder"`. None of them can form without a Tech 2 engineer.

`engtier` across run A, the audited tree, twelve cells:

| Profile | Cell | Peak Tech 2 engineers | Result |
| --- | --- | --- | --- |
| LandLarge | Fields of Isis 8675309 | **0** | defeat |
| LandLarge | Fields of Isis 31337 | **0** | defeat |
| LandLarge | Syrtis Major 8675309 | **0** | defeat |
| LandLarge | Syrtis Major 31337 | **0** | defeat |
| Naval | Sludge 2071971 Cybran | 9 | victory |
| Naval | Sludge 31337 Seraphim | 8 | victory |
| Naval | Sludge 2071971 Seraphim | 7 | victory |
| Naval | Sludge 8675309 Seraphim | 2 | defeat |
| Naval | Sludge 2071971 Aeon | 0 | victory |
| LandSmall | Sentry Point 2071971 Aeon | 7 | defeat |
| LandSmall | Sentry Point 2071971 UEF | 3 | victory |
| LandSmall | Sentry Point 31337 Aeon | 0 | victory |

Every LandLarge cell reaches land Tech 2 and never builds a Tech 2 engineer, so
on those four maps Red Queen cannot build a Tech 2 defence of any kind. Two
further runs of Fields of Isis 8675309 today, one at `28c1f16` and one with the
observer added, both reported zero for the whole match and confirmed the
consequence directly: 31 Tech 1 point defences, 21 Tech 1 anti-air, no shield.

The correlation does not extend past the profile and should not be read as one.
Sludge 2071971 Aeon and Sentry Point 31337 Aeon also held zero and won; Sentry
Point 2071971 Aeon held seven and lost. Zero Tech 2 engineers does not predict
defeat on its own -- but it is a capability Red Queen does not have on exactly
the profile it has never won.

No cell in the matrix fielded a **Tech 3 engineer at all**, and land tier never
exceeded 2 anywhere.

### What the watched match actually did

Fields of Isis 8675309, Aeon against Aeon, the whole match in one column of
figures (`scripts/watch-match.py --timeline`):

| Phase | What it looked like |
| --- | --- |
| 00:00-05:00 | clean opening: 17 extractors by 05:09, 13 engineers, none idle, unit parity |
| 07:09 | land Tech 2 reached |
| 08:09 | energy storage 4%, 6 of 25 engineers idle, outgunned 29 to 63 |
| 10:09-14:09 | worst point, 0.29 of the enemy army, 16-18 of 25 engineers idle, extractors falling 20 to 12 |
| 19:09-25:09 | recovery to **2.05x the enemy army** on 23 Tech 1 point defences |
| 25:09-36:09 | mass income frozen at 9.8 for twelve minutes, extractors unchanged at 13/5/2, 14-18 of 22-24 engineers idle, commander idle |
| 32:09-36:09 | enemy 214 to 361 while Red Queen falls 219 to 138; defeat |

Red Queen wins the middle game on this map and then stops. It is not ground
down from behind: it reaches twice the opponent's army, holds mass and
engineers, spends neither, and is out-scaled from minute 25. That is a different
defect from the one the matrix's win column suggests, and it is the one worth
attacking next.

## The engineer ladder: right diagnosis, wrong inference

Four matrices, one per tree, twelve cells each.

| tree | what the engineer ladder did | record |
| --- | --- | --- |
| run A | baseline: one priority function, every tier counted at once | **6W/6L** |
| `6f0bbf2` | tier-aware, upper tiers capped at a quota of 3 | 5W/7L |
| `a9290de` | quota turned into a floor | 4W/8L |
| `2e8e262` | floor priced at 690, below every combat builder | 3W/9L |
| `549712a` | reverted | **6W/6L**, 12/12 with run A |

The diagnosis is not in doubt and the observer now reports it. A Tech 1 engineer
cannot build a Tech 2 structure. All three engineer builders share one
`PriorityFunction`, and it counted engineers across every tier; FAF's
`Builder:CalculatePriority` *replaces* Priority with what it returns, so a roster
held above target by native production switched off the Tech 2 and Tech 3
ladders along with their own. Every Tech 2 fortification builder declares
`T2EngineerBuilder` and so could not form. That is why all four LandLarge cells
reach Tech 2 and finish on Tech 1 point defence, Tech 1 anti-air and no shield.

What is false is that closing the gap wins games.

**Priced as a shortage it takes the factory from the army.** The claim reached
910; `Tech2Priority` returns 910 for the combat mainline, so it tied. Sludge
2071971 Cybran is exact — run A and the fix ran byte-identical for twelve
samples, diverged at sample 13 on one Tech 2 engineer against one combat unit,
and the match ended at sample 14 instead of 24.

**Priced below the army it goes inert where it was needed.** At 690, under
StrategicPriority's 700 floor, the four LandLarge cells returned to zero Tech 2
engineers -- and the tree still lost three cells elsewhere, because a builder
merely *present* at a non-zero priority changes what the factory manager
considers at all. There is no "strictly additive" change to a builder list.

Syrtis Major 8675309 settles the question on its own: under `6f0bbf2` it built
14 Tech 2 engineers, 6 Tech 2 point defences and reached Tech 3 factories, where
it had built none of that -- and lost exactly as it always has.

The control also establishes that `Observer.lua` is inert. It is the only
simulation difference between `549712a` and run A's tree, and all twelve cells
agree.

## The alert freeze: mechanism fixed, outcome unmoved

`37bf144` scopes the defence-alert freeze on engineer work to engineers within
`DefenseAlertWorkRadius` of the anchor. Measured against the control, twelve
cells each.

| | control | scoped |
| --- | --- | --- |
| mean idle engineers while alerted | 14.2 | **9.5** |
| mean active assistants while alerted | **0.00** | **1.06** |
| record | 6W/6L | 6W/6L |

Cell for cell identical, and seven cells did not change behaviour at all -- their
alerts sit on top of the engineers, so the scope makes no difference. The five
that did change moved a long way: Fields of Isis 31337 went from 25.0 idle
engineers while alerted to 13.3 and doubled its peak mass income, 5.9 to 12.4.

So this is a real behavioural improvement at no measured cost, and it is kept on
that basis. It is not a win, and the negative result is the useful part: idle
engineers were not what was losing these games either, any more than the missing
Tech 2 defences were.

### What is actually losing them

Peak army strength, weighted 1/3/9/40 by tier, on the scoped tree:

| cell | result | peak own | peak enemy | best ratio | ratio at end |
| --- | --- | --- | --- | --- | --- |
| Fields of Isis 8675309 | defeat | 272 | 285 | 2.21 | 0.36 |
| Fields of Isis 31337 | defeat | 123 | **771** | 0.58 | 0.04 |
| Syrtis Major 8675309 | defeat | 75 | **544** | 0.86 | 0.02 |
| Syrtis Major 31337 | defeat | 176 | 389 | 1.18 | 0.13 |
| Sludge 2071971 Cybran | victory | 88 | 98 | 1.66 | 1.17 |
| Sentry Point 31337 | victory | 58 | 54 | 1.76 | 1.76 |

On the naval and small maps both sides top out near 50-100 and Red Queen wins.
On the large maps the opponent reaches 285 to 771 while Red Queen tops out at 75
to 272 -- and on two of the four cells Red Queen is *ahead at its peak* and then
loses the army outright.

The gap is army production capacity on large maps, not economy, not defences and
not engineer scheduling. That matches the original spectating note, which said it
first: "UEF managed to make a forward base early and therefore also starts to be
able to scale production capacity and keeps some map control."
