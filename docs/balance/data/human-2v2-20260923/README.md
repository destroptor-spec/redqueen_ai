# Two human-versus-Red-Queen matches, 23–24 September 2026

Extracted 2026-09-24 from the local FAF logs and matching replay files. Both
logs pass `scripts/analyze-log.py`: two brains started, no Lua failures,
no scheduler failures and no reported desynchronization. Both games reached
GameEnded and emitted JsonStats. Humans won both; Snider was defeated in the
second game before the Red Queens were defeated.

| Game | Map | Red Queen armies | Last observation |
| --- | --- | --- | --- |
| 27843240 | Adaptive Hrungdaks Canyon v2 | 2: Tengelin, UEF; 4: Kirwan, UEF | 94:09 / 99:09 |
| 27843831 | Adaptive Kusoge v3 | 3: Kijanka, Cybran; 4: Ranga, Aeon | 62:09 / 62:09 |

These are simulation observation times, not wall-clock match durations. Startup
contracts confirm two allies versus two enemies, `income=1.00` for all four
Red Queen brains, and Assassination. The human accounts are Destroptor and
Snider. Replay metadata identifies V9's mod UID. No exact historical payload
hash is available from these normal client launches: the currently correct
development symlink cannot prove what files were loaded last night. These are
real multiplayer observations, not controlled comparisons with a matrix cell.

## 1. The coverage problem appears against humans too

All figures below are from periodic state samples. Defence means the instrument's
entire own STRUCTURE * DEFENSE set, not just point defence.

| Map / army | Alert samples | Mean defences held | Mean geometrically covering alert anchor | Zero coverage | Recorded extractor losses / no coverage |
| --- | ---: | ---: | ---: | ---: | ---: |
| Canyon / Tengelin | 74 | 48.86 | 8.22 | 10/74 (14%) | 34 / 27 |
| Canyon / Kirwan | 74 | 35.11 | 1.51 | 41/74 (55%) | 34 / 30 |
| Kusoge / Kijanka | 17 | 40.06 | 0.24 | 14/17 (82%) | 13 / 13 |
| Kusoge / Ranga | 17 | 28.94 | 1.53 | 14/17 (82%) | 21 / 15 |

Canyon: 57/68 recorded extractor losses lack measured coverage. Kusoge: 28/34.
The aggregate is 85/102 (83%), but these games and armies have different
durations and circumstances; this is not a paired effect estimate.

Concrete instances, using original log line numbers:

- Canyon line 4250, Kirwan at 50:09: 38 defences, zero covering the anchor,
  nearest defence 221 map units away; 13 extractors remain.
- Kusoge line 4777, Kijanka at 47:09: 51 defences, zero covering the anchor,
  nearest defence 335 away; 27 extractors remain.
- Kusoge line 4403, Ranga at 42:09: 30 defences, zero covering the anchor,
  nearest defence 319 away; 49 extractors remain.

**Instrument limits:** `DefenseCoverage` uses each structure's maximum blueprint
weapon radius. It does not establish firing-layer compatibility, line of fire,
completion, power, or actual shots. It counts own rather than allied structures
and measures the alert anchor rather than the attacker. Extractor loss coverage
is resolved at the next diagnostic sample against surviving defences, not at the
instant of death. The last sample can omit subsequent losses. Thus "no measured
coverage" is supported; "nothing could shoot the killer when it attacked" is
not established. Mobile defenders are not counted. These limits also qualify
the earlier matrix's interpretation.

## 2. Kusoge supplies a concrete failed-construction case

14 forward-base starts, **zero established**. The recorded terminal reasons are
six route-unsafe, five no-factory, and three manager-lost. Every no-factory case
lasts 900 seconds. There are 40 recall-failure warnings involving three bases,
not 40 distinct lost bases.

The clearest example is Kijanka's `RQFB_3_6`:

- Line 3880: starts after the 35:09 watch sample, with six queued structures.
- 25 recall failures occur between the preceding-watch times 37:09 and 49:09.
- Line 5010: fails after 900 seconds with `reason=no-factory`.

Ranga's `RQFB_4_2` has 14 recall failures followed by the same 900-second
no-factory outcome. `RQFB_4_6` has one. Exact event times are not logged;
`preceding_watch_t` in the event CSV is a lower bound, not an exact timestamp.
Construction-active appears in 89/126 sampled `forward` reason fields across
the two armies. The analyzer's separate blocker-message count is 93; those are
different observations and should not be conflated.

The existing uncommitted ProductionManager work targets a stale platoon handle
in engineer release. It was present before this analysis and was not modified.
These historical warnings do not include the caught error, so they corroborate
the failed-recall symptom, not independently the exact exception or the fix.
The useful next verification is successful release followed by a new executable
assignment, with the forward slot freed before the timeout.

Canyon is a contrasting case: five starts, two establishments, both subsequently
reported destroyed; only one recall warning. Failed recall is therefore not a
complete explanation for the holding problem.

## 3. Kusoge is not primarily an inability to obtain mass

| Map / army | Peak -> final observed extractors | ExpandProduction samples | Peak factory count | Both stores >=95% |
| --- | --- | ---: | ---: | ---: |
| Canyon / Tengelin | 23 -> 8 | 5/95 | 26 | 5/95 |
| Canyon / Kirwan | 22 -> 5 | 5/100 | 25 | 5/100 |
| Kusoge / Kijanka | 29 -> 18 | 20/63 | 32 | 29/63 |
| Kusoge / Ranga | 50 -> 30 | 35/63 | 35 | 39/63 |

The second game spends 55/126 samples in ExpandProduction, versus 10/195 in
the first. The earlier matrix's 3.5% does not generalize to this match. The
factory-expansion mode was available frequently, and factories existed.

End-of-game resource totals provide a further distinction: Kusoge's human team
records 2.062 million mass income and the AI team 1.988 million (about 4% less),
while completed built-mass totals are 1.642 million versus 1.280 million (22%
less). These are whole-match totals, not matched-phase rates; transfers, reclaim,
construction in progress and death timing prevent a direct efficiency estimate.

The engine reports mass `excess` of 74,496 for Kijanka and 257,141 for Ranga,
7.6% and 25.6% of their recorded total mass income. With team overflow enabled,
these are excess-resource counters, not proven net resources destroyed: some
overflow can benefit the ally. Together with the storage samples, they identify
resource conversion as worth inspecting rather than simply increasing income.

## 4. Military output is failing to trade effectively

Engine general killed-mass / lost-mass ratios are 0.38 and 0.35 for the Canyon
Red Queens, and 0.093 and 0.056 for the Kusoge Red Queens. Kusoge's AI team
records roughly 1.14 million lost mass against only 84,929 killed mass.
These are lifetime end-of-match ratios, including the consequences of defeat;
they are not isolated engagement efficiencies. They nevertheless reinforce that
more economic activity alone is not sufficient evidence of useful combat output.

Do not diagnose experimental production from category counts here. The logs
contain conspicuous built/lost inconsistencies (for example zero built and 11
lost experimentals on Tengelin). Transfers and the previously observed telemetry
accounting issues must be resolved before attributing those counts to a builder.

## Recommended use of these games

Use Kusoge's three failed-recall bases as real-match regression cases for the
ongoing release fix. Separately, pursue coverage at the attacked location and
retained extractors, keeping coverage geometry distinct from weapon suitability.
Avoid a new income boost or global defence-count increase based on these games.
They supply specific failure examples; another large diagnostic matrix is not
needed to establish that these symptoms occur against humans.

## Evidence and reproduction

- `raw-logs.tar.gz`: both original complete game logs, unchanged.
- `*-Destroptor.fafreplay`: both original local replay files.
- `provenance.json`: source paths, sizes, timestamps and SHA-256 hashes; unknown
  historical simulation payload is explicitly null.
- `*-replay-metadata.json`, `*-stats.json`: replay headers and complete JsonStats.
- `*-analysis.txt`: analyzer gates and reports.
- `*-samples.csv`, `*-events.csv`, `*-summary.json`: extracted observations,
  original line references and per-army counts.

Reproduce with `python3 docs/balance/data/human-2v2-20260923/extract.py`.
The extractor runs the analyzer before generating observations. The 195 and 126
sample totals match its independent counts. `./scripts/validate.sh` passed on
2026-09-24. No AI behaviour was changed and no games were launched for this study.
