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
