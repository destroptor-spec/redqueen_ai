# Preserved match data, 2026-09-22/23

Everything here came from `/tmp`, which does not survive a reboot. The analysis
that reads it is in `docs/balance/engineer-survival-economics.md`.

## Files

| file | what it is |
| --- | --- |
| `matrix-results.csv` | one row per cell per matrix: 90 rows, 5 payloads, end-of-match values for every instrumented figure |
| `defence-coverage-series.csv` | 935 rows, per game minute: alert state, defences held, defences able to reach the alert, distance to the nearest one, extractors claimed |
| `manifests/` | 92 launch manifests — revision, payload hash, working-tree status, map. This is how a result stays attributable to an exact tree |
| `raw-logs.tar.gz` | the 92 full match logs (2.6 MB compressed) |
| `holding-review/` | the independent review of the placement-probe logs, with its own analyzer outputs |
| `tooling/` | the matrix drivers (parallel and serial) and the paired-comparison script |
| `payloads.json` | payload hash → what that payload changed |

## Payloads

| hash | change |
| --- | --- |
| `24c0b34595dc` | control (committed tree, no instrumentation) |
| `d9d87346e487` | baseline instrumentation — `engsurvival=` counters |
| `cbf11975e7e8` | lever 1: a withdrawal writes no exclusion |
| `1f80dcd5aa3d` | route guard disarmed, refusals still counted |
| `acc05419c5d5` | placement counterfactual probe |
| `592e88deaadc` | defence coverage, extractor losses, fortifiable span |

## Reading the CSV

Columns are zero where that payload did not carry the instrument — the coverage
columns are meaningful only for `defcover`, the placement columns only for
`mexplace`. `peak_claim` is the maximum over the match; every other column is
the final sample.

Cells were observed for 28–95 game minutes, deterministically but unequally, so
**cross-cell comparison of final values is confounded by match length**. Compare
a cell against itself across payloads, at that pair's common horizon. The
paired-comparison script in `tooling/` does this.

## Known limitation in the coverage payload

`592e88deaadc` is not fully behaviour-neutral. Seventeen of eighteen cells
reproduce the baseline exactly; `syrtis-424242-uef` matches for 32 samples and
then diverges. A re-run of that cell on the same payload reproduced the
divergence **68/68 samples identically**, so this is a deterministic effect of
the change and not run-to-run variation — the simulation's determinism itself
holds.

That cell is excluded from every coverage figure reported. The cause is not yet
identified; the candidates are the calls `DefenseCoverage` makes into engine
state — `GetListOfUnits` during a unit-destroyed callback, and the
`pcall(GetLocationCoords)` in `BaseSpan` — one of which is evidently not the
pure query it was assumed to be. **Resolve this before trusting the module in a
payload that also changes a decision.**
